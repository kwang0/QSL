using HDF5
using PyPlot
using PyCall

@pyimport matplotlib.widgets as widgets
@pyimport PIL.Image as PILImage

const SQRT3 = sqrt(3.0)

site_row(i::Integer, C::Integer) = (i - 1) % C
site_col(i::Integer, C::Integer) = div(i - 1, C)

function wrap_periodic(delta::Integer, period::Integer)
    wrapped = delta
    while wrapped > period / 2
        wrapped -= period
    end
    while wrapped <= -period / 2
        wrapped += period
    end
    return wrapped
end

"""
Return the displacement r_j - r_i for the YC triangular cylinder in the
same brick-wall embedding used by `coord(lat::TriangularYC, i)` in
`triangular_gutzwiller_mps.jl`:
  a_row = (0, 1), a_col = (sqrt(3)/2, 1/2).

The wrapped direction is the YC circumference.
"""
function yc_displacement(i::Integer, j::Integer, C::Integer)
    row_i = site_row(i, C)
    col_i = site_col(i, C)
    row_j = site_row(j, C)
    col_j = site_col(j, C)

    drow = wrap_periodic(row_j - row_i, C)
    dcol = col_j - col_i

    dx = (SQRT3 / 2) * dcol
    dy = drow + 0.5 * (isodd(col_j) - isodd(col_i))
    return dx, dy
end

displacement_key(dx::Real, dy::Real) = (
    round(Int, (2 / SQRT3) * dx),
    round(Int, 2 * dy),
)

function key_to_displacement(key::NTuple{2, Int})
    dx = key[1] * SQRT3 / 2
    dy = key[2] / 2
    return dx, dy
end

function normalize_corrs_shape(corrs)
    if ndims(corrs) != 2
        error("Expected `corrs` to be a 2D array, got size $(size(corrs)).")
    end

    if size(corrs, 1) == size(corrs, 2)
        return ComplexF64.(corrs), :matrix
    elseif 1 in size(corrs)
        return ComplexF64.(vec(corrs)), :vector
    end

    error(
        "Unsupported `corrs` shape $(size(corrs)). " *
        "This script expects a ground-state correlation matrix (N x N) " *
        "or a single correlation vector (N).",
    )
end

subtract_disconnected(corrs::AbstractMatrix, Zs::AbstractVector) = corrs .- ComplexF64.(Zs * Zs')

function subtract_disconnected(
    corrs::AbstractVector,
    Zs::AbstractVector;
    reference_site::Integer,
)
    return corrs .- ComplexF64.(Zs[reference_site] .* Zs)
end

function collapse_weights(weight_dict::Dict{NTuple{2, Int}, ComplexF64})
    keys_sorted = sort!(collect(keys(weight_dict)))
    displacements = Matrix{Float64}(undef, 2, length(keys_sorted))
    weights = Vector{ComplexF64}(undef, length(keys_sorted))

    for (n, key) in enumerate(keys_sorted)
        dx, dy = key_to_displacement(key)
        displacements[:, n] .= (dx, dy)
        weights[n] = weight_dict[key]
    end

    return displacements, weights
end

function build_weights_full(corrs::AbstractMatrix, C::Integer)
    N = size(corrs, 1)
    weights = Dict{NTuple{2, Int}, ComplexF64}()

    for i in 1:N
        for j in 1:N
            dx, dy = yc_displacement(i, j, C)
            key = displacement_key(dx, dy)
            weights[key] = get(weights, key, 0.0 + 0.0im) + corrs[i, j] / N
        end
    end

    return collapse_weights(weights)
end

function build_weights_reference(
    corrs::AbstractVector,
    C::Integer;
    reference_site::Integer,
)
    N = length(corrs)
    weights = Dict{NTuple{2, Int}, ComplexF64}()

    for j in 1:N
        dx, dy = yc_displacement(reference_site, j, C)
        key = displacement_key(dx, dy)
        weights[key] = get(weights, key, 0.0 + 0.0im) + corrs[j] / N
    end

    return collapse_weights(weights)
end

function compute_structure_factor_grid(
    displacements::AbstractMatrix,
    weights::AbstractVector,
    qx::AbstractVector,
    qy::AbstractVector,
)
    dx = @view displacements[1, :]
    dy = @view displacements[2, :]
    Sq = Matrix{Float64}(undef, length(qy), length(qx))

    for iy in eachindex(qy)
        qy_val = qy[iy]
        for ix in eachindex(qx)
            qx_val = qx[ix]
            phase = @. qx_val * dx + qy_val * dy
            Sq[iy, ix] = real(sum(weights .* cis.(phase)))
        end
    end

    return Sq
end


function pi_flux_mf_dvector(qx::Real, qy::Real; t::Real = 1.0)
    dx = 4 * t * cos((SQRT3 / 2) * qx) * cos(qy / 2)
    dz = 2 * t * cos(qy)
    return dx, dz
end

function pi_flux_mf_reciprocal_basis_vectors()
    b1 = (2 * pi / SQRT3, 0.0)
    b2 = (-2 * pi / SQRT3, 2 * pi)
    return b1, b2
end

function build_pi_flux_mf_kgrid(nk1::Integer, nk2::Integer)
    b1, b2 = pi_flux_mf_reciprocal_basis_vectors()
    kx = Matrix{Float64}(undef, nk1, nk2)
    ky = Matrix{Float64}(undef, nk1, nk2)

    for i in 1:nk1
        u = (i - 0.5) / nk1
        for j in 1:nk2
            v = (j - 0.5) / nk2
            kx[i, j] = u * b1[1] + v * b2[1]
            ky[i, j] = u * b1[2] + v * b2[2]
        end
    end

    return kx, ky
end

function compute_pi_flux_mean_field_structure_factor_grid(
    qx::AbstractVector,
    qy::AbstractVector;
    t::Real = 1.0,
    nk1::Integer = 121,
    nk2::Integer = 121,
    prefactor::Real = 3 / 8,
    singular_cutoff::Real = 1e-12,
)
    kx, ky = build_pi_flux_mf_kgrid(nk1, nk2)
    dhx = Matrix{Float64}(undef, nk1, nk2)
    dhz = Matrix{Float64}(undef, nk1, nk2)

    for i in 1:nk1
        for j in 1:nk2
            dx, dz = pi_flux_mf_dvector(kx[i, j], ky[i, j]; t = t)
            norm_d = hypot(dx, dz)
            if norm_d <= singular_cutoff
                dhx[i, j] = 0.0
                dhz[i, j] = 0.0
            else
                inv_norm = inv(norm_d)
                dhx[i, j] = dx * inv_norm
                dhz[i, j] = dz * inv_norm
            end
        end
    end

    Sq = Matrix{Float64}(undef, length(qy), length(qx))
    norm_factor = prefactor / (nk1 * nk2)

    for iy in eachindex(qy)
        qy_val = qy[iy]
        for ix in eachindex(qx)
            qx_val = qx[ix]
            accum = 0.0

            @inbounds for i in 1:nk1
                for j in 1:nk2
                    dx2, dz2 = pi_flux_mf_dvector(kx[i, j] + qx_val, ky[i, j] + qy_val; t = t)
                    norm_d2 = hypot(dx2, dz2)
                    if norm_d2 <= singular_cutoff
                        continue
                    end

                    accum += 1 - (dhx[i, j] * dx2 + dhz[i, j] * dz2) / norm_d2
                end
            end

            Sq[iy, ix] = norm_factor * accum
        end
    end

    return Sq
end

function compute_pi_flux_mean_field_structure_factor_data(
    ;
    nqx::Integer = 241,
    nqy::Integer = 181,
    qx_limits = nothing,
    qy_limits = nothing,
    t::Real = 1.0,
    nk1::Integer = 121,
    nk2::Integer = 121,
    prefactor::Real = 3 / 8,
)
    qx, qy = default_q_axes(
        nqx = nqx,
        nqy = nqy,
        qx_limits = qx_limits,
        qy_limits = qy_limits,
    )
    Sq = compute_pi_flux_mean_field_structure_factor_grid(
        qx,
        qy;
        t = t,
        nk1 = nk1,
        nk2 = nk2,
        prefactor = prefactor,
    )
    title = "Static structure factor S(q) U(1) DSL mean field"

    return (
        Sq = Sq,
        qx = qx,
        qy = qy,
        title = title,
        nk1 = nk1,
        nk2 = nk2,
        t = t,
    )
end

function plot_pi_flux_mean_field_structure_factor(
    ;
    C::Union{Nothing, Integer} = nothing,
    L::Union{Nothing, Integer} = nothing,
    nqx::Integer = 241,
    nqy::Integer = 181,
    qx_limits = nothing,
    qy_limits = nothing,
    t::Real = 1.0,
    nk1::Integer = 121,
    nk2::Integer = 121,
    prefactor::Real = 3 / 8,
    output_png = nothing,
    normalize::Bool = true,
    logscale::Bool = true,
    show_plot::Bool = true,
    log_vmin::Float64 = 1e-1,
    show_allowed_momenta::Bool = false,
    allowed_momenta_color::AbstractString = "deepskyblue",
    allowed_momenta_size::Real = 12,
)
    data = compute_pi_flux_mean_field_structure_factor_data(
        nqx = nqx,
        nqy = nqy,
        qx_limits = qx_limits,
        qy_limits = qy_limits,
        t = t,
        nk1 = nk1,
        nk2 = nk2,
        prefactor = prefactor,
    )

    fig, ax, image = plot_structure_factor(
        data.Sq,
        data.qx,
        data.qy;
        C = C,
        L = L,
        output_png = output_png,
        title = data.title,
        normalize = normalize,
        logscale = logscale,
        show_plot = show_plot,
        log_vmin = log_vmin,
        show_allowed_momenta = show_allowed_momenta,
        allowed_momenta_color = allowed_momenta_color,
        allowed_momenta_size = allowed_momenta_size,
    )

    return (
        Sq = data.Sq,
        qx = data.qx,
        qy = data.qy,
        fig = fig,
        ax = ax,
        image = image,
        nk1 = nk1,
        nk2 = nk2,
        t = t,
    )
end

function first_bz_hexagon()
    return [
         0.0              4 * pi / 3
         2 * pi / SQRT3   2 * pi / 3
         2 * pi / SQRT3  -2 * pi / 3
         0.0             -4 * pi / 3
        -2 * pi / SQRT3  -2 * pi / 3
        -2 * pi / SQRT3   2 * pi / 3
         0.0              4 * pi / 3
    ]
end

function default_bz_q_limits(; pad_fraction::Real = 0.0)
    bz = first_bz_hexagon()
    xmin, xmax = extrema(bz[:, 1])
    ymin, ymax = extrema(bz[:, 2])

    xpad = pad_fraction * (xmax - xmin)
    ypad = pad_fraction * (ymax - ymin)

    qx_limits = (xmin - xpad, xmax + xpad)
    qy_limits = (ymin - ypad, ymax + ypad)
    return qx_limits, qy_limits
end

function default_q_axes(
    ;
    nqx::Integer = 241,
    nqy::Integer = 181,
    qx_limits = nothing,
    qy_limits = nothing,
)
    bz_qx_limits, bz_qy_limits = default_bz_q_limits()
    resolved_qx_limits = isnothing(qx_limits) ? bz_qx_limits : qx_limits
    resolved_qy_limits = isnothing(qy_limits) ? bz_qy_limits : qy_limits

    qx = collect(range(resolved_qx_limits[1], resolved_qx_limits[2]; length = nqx))
    qy = collect(range(resolved_qy_limits[1], resolved_qy_limits[2]; length = nqy))
    return qx, qy
end

function reciprocal_basis_vectors()
    b_col = (4 * pi / SQRT3, 0.0)
    b_row = (-2 * pi / SQRT3, 2 * pi)
    return b_col, b_row
end

function finite_sample_momentum_points(
    C::Integer,
    L::Integer,
    qx::AbstractVector,
    qy::AbstractVector;
    shift_range::UnitRange{Int} = -2:2,
)
    b_col, b_row = reciprocal_basis_vectors()
    qx_min, qx_max = extrema(qx)
    qy_min, qy_max = extrema(qy)
    pad_x = 0.02 * max(qx_max - qx_min, 1.0)
    pad_y = 0.02 * max(qy_max - qy_min, 1.0)

    points = Set{Tuple{Int, Int}}()
    q_points = NTuple{2, Float64}[]

    for ncol in 0:(L - 1)
        for nrow in 0:(C - 1)
            qx0 = ncol / L * b_col[1] + nrow / C * b_row[1]
            qy0 = ncol / L * b_col[2] + nrow / C * b_row[2]

            for s_col in shift_range
                for s_row in shift_range
                    qx_val = qx0 + s_col * b_col[1] + s_row * b_row[1]
                    qy_val = qy0 + s_col * b_col[2] + s_row * b_row[2]

                    if qx_min - pad_x <= qx_val <= qx_max + pad_x &&
                       qy_min - pad_y <= qy_val <= qy_max + pad_y
                        key = (round(Int, 1_000_000 * qx_val), round(Int, 1_000_000 * qy_val))
                        if !(key in points)
                            push!(points, key)
                            push!(q_points, (qx_val, qy_val))
                        end
                    end
                end
            end
        end
    end

    sort!(q_points, by = p -> (p[2], p[1]))
    q_overlay = Matrix{Float64}(undef, 2, length(q_points))
    for (idx, point) in enumerate(q_points)
        q_overlay[:, idx] .= point
    end
    return q_overlay
end

function prepare_structure_factor_image(
    Sq::AbstractMatrix;
    normalize::Bool = true,
    logscale::Bool = false,
    log_vmin::Float64 = 1e-1,
)
    Sq_plot = Float64.(Sq)
    if normalize
        scale = maximum(abs, Sq_plot)
        if scale > 0
            Sq_plot ./= scale
        end
    end
    if logscale
        Sq_plot .= max.(Sq_plot, max(log_vmin, eps(Float64)))
    end
    return Sq_plot
end

function structure_factor_color_limits(
    Sq_plot::AbstractMatrix;
    logscale::Bool = true,
    log_vmin::Float64 = 1e-1,
)
    if logscale
        raw_vmax = maximum(Sq_plot)
        vmin = max(minimum(Sq_plot), log_vmin)
        vmax = max(raw_vmax, vmin * (1 + 1e-12))
        return (use_logscale = true, vmin = vmin, vmax = vmax)
    end

    vmin, vmax = extrema(Sq_plot)
    if vmin == vmax
        vmax = vmin + 1e-12
    end
    return (use_logscale = false, vmin = vmin, vmax = vmax)
end

function apply_structure_factor_color_scale!(image, color_limits)
    if color_limits.use_logscale
        image.set_norm(matplotlib[:colors][:LogNorm](vmin = color_limits.vmin, vmax = color_limits.vmax))
    else
        image.set_norm(matplotlib[:colors][:Normalize](vmin = color_limits.vmin, vmax = color_limits.vmax))
    end
    return nothing
end

function plot_structure_factor(
    Sq::AbstractMatrix,
    qx::AbstractVector,
    qy::AbstractVector;
    C::Union{Nothing, Integer} = nothing,
    L::Union{Nothing, Integer} = nothing,
    output_png = nothing,
    title::AbstractString = "Static structure factor S(q)",
    normalize::Bool = true,
    logscale::Bool = true,
    show_plot::Bool = false,
    log_vmin::Float64 = 1e-1,
    show_allowed_momenta::Bool = false,
    allowed_momenta_color::AbstractString = "deepskyblue",
    allowed_momenta_size::Real = 12,
)
    Sq_plot = prepare_structure_factor_image(
        Sq;
        normalize = normalize,
        logscale = logscale,
        log_vmin = log_vmin,
    )
    color_limits = structure_factor_color_limits(Sq_plot; logscale = logscale, log_vmin = log_vmin)
    extent = (first(qx), last(qx), first(qy), last(qy))

    fig, ax = subplots(figsize = (7.0, 5.5))
    if color_limits.use_logscale
        image = ax.imshow(
            Sq_plot,
            origin = "lower",
            extent = extent,
            interpolation = "bicubic",
            cmap = "afmhot",
            aspect = "equal",
            norm = matplotlib[:colors][:LogNorm](vmin = color_limits.vmin, vmax = color_limits.vmax),
        )
    else
        image = ax.imshow(
            Sq_plot,
            origin = "lower",
            extent = extent,
            interpolation = "bicubic",
            cmap = "afmhot",
            aspect = "equal",
            vmin = color_limits.vmin,
            vmax = color_limits.vmax,
        )
    end

    bz = first_bz_hexagon()
    ax.plot(bz[:, 1], bz[:, 2], color = "0.75", linewidth = 2.2)
    if show_allowed_momenta
        isnothing(C) && error("`show_allowed_momenta=true` requires passing C to `plot_structure_factor`.")
        isnothing(L) && error("`show_allowed_momenta=true` requires passing L to `plot_structure_factor`.")
        q_overlay = finite_sample_momentum_points(C, L, qx, qy)
        ax.scatter(
            q_overlay[1, :],
            q_overlay[2, :];
            s = allowed_momenta_size,
            facecolors = "none",
            edgecolors = allowed_momenta_color,
            linewidths = 0.8,
            alpha = 0.9,
            zorder = 4,
        )
    end
    ax.set_xlim(first(qx), last(qx))
    ax.set_ylim(first(qy), last(qy))
    ax.set_xlabel(raw"$q_x$")
    ax.set_ylabel(raw"$q_y$")
    ax.set_title(title)
    fig.colorbar(image, ax = ax, fraction = 0.046, pad = 0.04)
    fig.tight_layout()
    if output_png !== nothing
        savefig(output_png, dpi = 300, bbox_inches = "tight")
    end
    if show_plot
        display(fig)
    end
    return fig, ax, image
end

function save_structure_factor(
    output_h5::AbstractString,
    Sq::AbstractMatrix,
    qx::AbstractVector,
    qy::AbstractVector,
    displacements::AbstractMatrix,
    weights::AbstractVector,
)
    h5open(output_h5, "w") do file
        file["S_q"] = Sq
        file["qx"] = qx
        file["qy"] = qy
        file["displacements"] = displacements
        file["weights"] = weights
    end
end

function read_ground_state_corrs(
    input_file::AbstractString;
    corrs_dataset::AbstractString = "corrs",
)
    h5open(input_file, "r") do file
        haskey(file, corrs_dataset) || error("The file $input_file does not contain a `$corrs_dataset` dataset.")
        corrs = read(file, corrs_dataset)
        Zs = haskey(file, "Zs") ? read(file, "Zs") : nothing
        E0 = haskey(file, "E0") ? read(file, "E0") : nothing
        return corrs, Zs, E0
    end
end

function compute_structure_factor_data(
    input_file::AbstractString,
    C::Integer,
    L::Integer;
    connected::Bool = false,
    reference_site::Integer = 0,
    corrs_dataset::AbstractString = "corrs",
    nqx::Integer = 241,
    nqy::Integer = 181,
    qx_limits = nothing,
    qy_limits = nothing,
)
    corrs_raw, Zs, E0 = read_ground_state_corrs(input_file; corrs_dataset = corrs_dataset)
    corrs, corr_kind = normalize_corrs_shape(corrs_raw)

    N = corr_kind == :matrix ? size(corrs, 1) : length(corrs)
    expected_N = C * L
    if N != expected_N
        error("The lattice size C * L = $expected_N does not match the correlation data size N = $N.")
    end

    if corr_kind == :matrix
        if connected
            if Zs === nothing
                @warn "Requested connected correlations, but `Zs` is missing. Using raw `corrs`."
            else
                corrs = subtract_disconnected(corrs, Zs)
            end
        end

        if reference_site > 0
            ref_corrs = vec(corrs[reference_site, :])
            displacements, weights = build_weights_reference(ref_corrs, C; reference_site = reference_site)
        else
            displacements, weights = build_weights_full(corrs, C)
        end
    else
        ref_site = reference_site > 0 ? reference_site : cld(N, 2)
        if connected
            if Zs === nothing
                @warn "Requested connected correlations, but `Zs` is missing. Using raw `corrs`."
            else
                corrs = subtract_disconnected(corrs, Zs; reference_site = ref_site)
            end
        end
        displacements, weights = build_weights_reference(corrs, C; reference_site = ref_site)
    end

    qx, qy = default_q_axes(
        nqx = nqx,
        nqy = nqy,
        qx_limits = qx_limits,
        qy_limits = qy_limits,
    )
    Sq = compute_structure_factor_grid(displacements, weights, qx, qy)
    title = corrs_dataset == "corrs" ? "Static structure factor S(q)" : "Static structure factor S(q) from $corrs_dataset"

    return (
        Sq = Sq,
        qx = qx,
        qy = qy,
        E0 = E0,
        title = title,
        displacements = displacements,
        weights = weights,
    )
end

function default_output_prefix(input_file::AbstractString)
    stem, _ = splitext(input_file)
    return stem * "_static_Sq_YC"
end

function print_usage()
    println(
        "Usage:\n" *
        "  julia structure_factor_YC.jl <input.h5> <C> <L> [options]\n\n" *
        "Options:\n" *
        "  --connected            subtract <Sz_i><Sz_j> if Zs is present\n" *
        "  --corrs-dataset=<key>  choose the HDF5 correlation dataset (default `corrs`)\n" *
        "  --reference-site=<n>   use a single reference site instead of the full matrix\n" *
        "  --nqx=<n>              number of qx points (default 241)\n" *
        "  --nqy=<n>              number of qy points (default 181)\n" *
        "  --output-prefix=<path> write <path>.h5 and <path>.png\n" *
        "  --linear-scale         disable log color scaling\n" *
        "  --no-normalize         keep the raw S(q) scale in the plot\n",
    )
end

function parse_cli(args::Vector{String})
    if isempty(args) || "--help" in args || "-h" in args
        print_usage()
        return nothing
    end

    positional = String[]
    options = Dict{String, Any}(
        "connected" => false,
        "corrs_dataset" => "corrs",
        "reference_site" => 0,
        "nqx" => 241,
        "nqy" => 181,
        "output_prefix" => "",
        "logscale" => true,
        "normalize" => true,
    )

    for arg in args
        if arg == "--connected"
            options["connected"] = true
        elseif startswith(arg, "--corrs-dataset=")
            options["corrs_dataset"] = split(arg, "=", limit = 2)[2]
        elseif arg == "--linear-scale"
            options["logscale"] = false
        elseif arg == "--no-normalize"
            options["normalize"] = false
        elseif startswith(arg, "--reference-site=")
            options["reference_site"] = parse(Int, split(arg, "=", limit = 2)[2])
        elseif startswith(arg, "--nqx=")
            options["nqx"] = parse(Int, split(arg, "=", limit = 2)[2])
        elseif startswith(arg, "--nqy=")
            options["nqy"] = parse(Int, split(arg, "=", limit = 2)[2])
        elseif startswith(arg, "--output-prefix=")
            options["output_prefix"] = split(arg, "=", limit = 2)[2]
        elseif startswith(arg, "--")
            error("Unknown option: $arg")
        else
            push!(positional, arg)
        end
    end

    if length(positional) < 3
        print_usage()
        error("Please provide <input.h5> <C> <L>.")
    end

    options["input_file"] = positional[1]
    options["C"] = parse(Int, positional[2])
    options["L"] = parse(Int, positional[3])
    return options
end

function process_static_structure_factor(
    input_file::AbstractString,
    C::Integer,
    L::Integer;
    connected::Bool = false,
    reference_site::Integer = 0,
    corrs_dataset::AbstractString = "corrs",
    nqx::Integer = 241,
    nqy::Integer = 181,
    qx_limits = nothing,
    qy_limits = nothing,
    output_prefix = nothing,
    logscale::Bool = true,
    normalize::Bool = true,
    save_plot::Bool = true,
    save_data::Bool = true,
    show_plot::Bool = false,
    log_vmin::Float64 = 1e-1,
    show_allowed_momenta::Bool = false,
    allowed_momenta_color::AbstractString = "deepskyblue",
    allowed_momenta_size::Real = 12,
)
    data = compute_structure_factor_data(
        input_file,
        C,
        L;
        connected = connected,
        reference_site = reference_site,
        corrs_dataset = corrs_dataset,
        nqx = nqx,
        nqy = nqy,
        qx_limits = qx_limits,
        qy_limits = qy_limits,
    )
    Sq = data.Sq
    qx = data.qx
    qy = data.qy

    resolved_prefix = output_prefix === nothing ? default_output_prefix(input_file) : output_prefix
    output_h5 = save_data ? resolved_prefix * ".h5" : nothing
    output_png = save_plot ? resolved_prefix * ".png" : nothing

    fig, ax, image = plot_structure_factor(
        Sq,
        qx,
        qy;
        C = C,
        L = L,
        output_png = output_png,
        title = data.title,
        normalize = normalize,
        logscale = logscale,
        show_plot = show_plot,
        log_vmin = log_vmin,
        show_allowed_momenta = show_allowed_momenta,
        allowed_momenta_color = allowed_momenta_color,
        allowed_momenta_size = allowed_momenta_size,
    )

    if save_data
        save_structure_factor(output_h5, Sq, qx, qy, data.displacements, data.weights)
        println("Saved structure-factor data to $output_h5")
    end
    if save_plot
        println("Saved structure-factor plot to $output_png")
    end

    return (
        Sq = Sq,
        qx = qx,
        qy = qy,
        fig = fig,
        ax = ax,
        image = image,
        output_h5 = output_h5,
        output_png = output_png,
    )
end

function plot_structure_factor_from_file(
    input_file::AbstractString,
    C::Integer,
    L::Integer;
    connected::Bool = false,
    reference_site::Integer = 0,
    corrs_dataset::AbstractString = "corrs",
    nqx::Integer = 241,
    nqy::Integer = 181,
    qx_limits = nothing,
    qy_limits = nothing,
    logscale::Bool = true,
    normalize::Bool = true,
    show_plot::Bool = true,
    log_vmin::Float64 = 1e-1,
    show_allowed_momenta::Bool = false,
    allowed_momenta_color::AbstractString = "deepskyblue",
    allowed_momenta_size::Real = 12,
)
    return process_static_structure_factor(
        input_file,
        C,
        L;
        connected = connected,
        reference_site = reference_site,
        corrs_dataset = corrs_dataset,
        nqx = nqx,
        nqy = nqy,
        qx_limits = qx_limits,
        qy_limits = qy_limits,
        logscale = logscale,
        normalize = normalize,
        save_plot = false,
        save_data = false,
        show_plot = show_plot,
        log_vmin = log_vmin,
        show_allowed_momenta = show_allowed_momenta,
        allowed_momenta_color = allowed_momenta_color,
        allowed_momenta_size = allowed_momenta_size,
    )
end

function discover_ground_state_search_files(
    C::Integer,
    L::Integer;
    directory::AbstractString = "processed_data",
    delta1::Real = 1.0,
    delta2::Real = 1.0,
    chi::Integer = 512,
)
    prefix = "ground_state_search_YC_C$(C)_L$(L)_J"
    suffix = "_1Delta$(delta1)_2Delta$(delta2)_chi$(chi).h5"
    file_map = Dict{Float64, String}()

    for path in readdir(directory; join = true)
        name = basename(path)
        if startswith(name, prefix) && endswith(name, suffix)
            jstr = name[(length(prefix) + 1):(end - length(suffix))]
            file_map[parse(Float64, jstr)] = path
        end
    end

    isempty(file_map) && error("No matching ground-state search files were found in $directory.")
    return file_map
end

function interpolate_structure_factor(
    Sq_stack::Array{Float64, 3},
    values::AbstractVector,
    x::Real,
)
    idx_hi = searchsortedfirst(values, x)
    if idx_hi <= 1
        return copy(@view Sq_stack[:, :, 1]), values[1], values[1], 0.0
    elseif idx_hi > length(values)
        return copy(@view Sq_stack[:, :, end]), values[end], values[end], 0.0
    end

    idx_lo = idx_hi - 1
    x_lo = values[idx_lo]
    x_hi = values[idx_hi]
    weight_hi = (x - x_lo) / (x_hi - x_lo)
    weight_lo = 1 - weight_hi
    frame = weight_lo .* @view(Sq_stack[:, :, idx_lo]) .+ weight_hi .* @view(Sq_stack[:, :, idx_hi])
    return frame, x_lo, x_hi, weight_hi
end

function format_structure_factor_title(
    J2_value::Real;
)
    rounded_J2 = round(J2_value, digits = 3)
    return "Static structure factor S(q), " * raw"$J_2/J_1$" * " = $(rounded_J2)"
end

function update_structure_factor_artist!(
    image,
    ax,
    frame::AbstractMatrix,
    J2_value::Real;
    normalize::Bool = true,
    logscale::Bool = true,
    log_vmin::Float64 = 1e-1,
)
    frame_plot = prepare_structure_factor_image(
        frame;
        normalize = normalize,
        logscale = logscale,
        log_vmin = log_vmin,
    )
    color_limits = structure_factor_color_limits(frame_plot; logscale = logscale, log_vmin = log_vmin)

    image.set_data(frame_plot)
    apply_structure_factor_color_scale!(image, color_limits)
    ax.set_title(format_structure_factor_title(J2_value))
    return nothing
end

function plot_structure_factor_J_slider(
    C::Integer,
    L::Integer;
    directory::AbstractString = "processed_data",
    delta1::Real = 1.0,
    delta2::Real = 1.0,
    chi::Integer = 512,
    connected::Bool = false,
    reference_site::Integer = 0,
    corrs_dataset::AbstractString = "corrs",
    nqx::Integer = 241,
    nqy::Integer = 181,
    qx_limits = nothing,
    qy_limits = nothing,
    logscale::Bool = true,
    normalize::Bool = true,
    show_plot::Bool = true,
    log_vmin::Float64 = 3e-1,
    show_allowed_momenta::Bool = false,
    allowed_momenta_color::AbstractString = "deepskyblue",
    allowed_momenta_size::Real = 12,
)
    file_map = discover_ground_state_search_files(
        C,
        L;
        directory = directory,
        delta1 = delta1,
        delta2 = delta2,
        chi = chi,
    )
    Js = sort(collect(keys(file_map)))

    datasets = [
        compute_structure_factor_data(
            file_map[J],
            C,
            L;
            connected = connected,
            reference_site = reference_site,
            corrs_dataset = corrs_dataset,
            nqx = nqx,
            nqy = nqy,
            qx_limits = qx_limits,
            qy_limits = qy_limits,
        ) for J in Js
    ]

    qx = datasets[1].qx
    qy = datasets[1].qy
    Sq_stack = Array{Float64}(undef, length(qy), length(qx), length(Js))

    for (idx, data) in enumerate(datasets)
        data.qx == qx || error("Inconsistent qx grid while building the J slider.")
        data.qy == qy || error("Inconsistent qy grid while building the J slider.")
        Sq_stack[:, :, idx] .= data.Sq
    end

    initial_frame, _, _, _ = interpolate_structure_factor(Sq_stack, Js, Js[1])
    fig, ax, image = plot_structure_factor(
        initial_frame,
        qx,
        qy;
        C = C,
        L = L,
        title = format_structure_factor_title(Js[1]),
        normalize = normalize,
        logscale = logscale,
        show_plot = false,
        log_vmin = log_vmin,
        show_allowed_momenta = show_allowed_momenta,
        allowed_momenta_color = allowed_momenta_color,
        allowed_momenta_size = allowed_momenta_size,
    )

    fig.subplots_adjust(bottom = 0.17)
    ax_slider = fig.add_axes([0.20, 0.06, 0.60, 0.04])
    slider = widgets.Slider(
        ax_slider,
        raw"$J_2/J_1$",
        Js[1],
        Js[end],
        valinit = Js[1],
        valfmt = "%0.3f",
    )

    function update_slider(val)
        J2_value = Float64(val)
        frame, _, _, _ = interpolate_structure_factor(Sq_stack, Js, J2_value)

        update_structure_factor_artist!(
            image,
            ax,
            frame,
            J2_value;
            normalize = normalize,
            logscale = logscale,
            log_vmin = log_vmin,
        )
        fig.canvas.draw_idle()
        return nothing
    end

    slider.on_changed(update_slider)
    if show_plot
        display(fig)
    end

    return (
        fig = fig,
        ax = ax,
        image = image,
        slider = slider,
        J_values = Js,
        file_map = file_map,
        qx = qx,
        qy = qy,
        Sq_stack = Sq_stack,
        corrs_dataset = corrs_dataset,
        show_allowed_momenta = show_allowed_momenta,
    )
end

function export_structure_factor_J2_gif(
    output_gif::AbstractString,
    C::Integer,
    L::Integer;
    directory::AbstractString = "processed_data",
    delta1::Real = 1.0,
    delta2::Real = 1.0,
    chi::Integer = 512,
    connected::Bool = false,
    reference_site::Integer = 0,
    corrs_dataset::AbstractString = "corrs",
    nqx::Integer = 241,
    nqy::Integer = 181,
    qx_limits = nothing,
    qy_limits = nothing,
    logscale::Bool = true,
    normalize::Bool = true,
    log_vmin::Float64 = 3e-1,
    show_allowed_momenta::Bool = false,
    allowed_momenta_color::AbstractString = "deepskyblue",
    allowed_momenta_size::Real = 12,
    fps::Integer = 10,
    frames_per_interval::Integer = 4,
    hold_frames::Integer = 1,
)
    viewer = plot_structure_factor_J_slider(
        C,
        L;
        directory = directory,
        delta1 = delta1,
        delta2 = delta2,
        chi = chi,
        connected = connected,
        reference_site = reference_site,
        corrs_dataset = corrs_dataset,
        nqx = nqx,
        nqy = nqy,
        qx_limits = qx_limits,
        qy_limits = qy_limits,
        logscale = logscale,
        normalize = normalize,
        show_plot = false,
        log_vmin = log_vmin,
        show_allowed_momenta = show_allowed_momenta,
        allowed_momenta_color = allowed_momenta_color,
        allowed_momenta_size = allowed_momenta_size,
    )

    Js = viewer.J_values
    Sq_stack = viewer.Sq_stack
    qx = viewer.qx
    qy = viewer.qy
    close(viewer.fig)

    initial_frame, _, _, _ = interpolate_structure_factor(Sq_stack, Js, Js[1])
    fig, ax, image = plot_structure_factor(
        initial_frame,
        qx,
        qy;
        C = C,
        L = L,
        title = format_structure_factor_title(Js[1]),
        normalize = normalize,
        logscale = logscale,
        show_plot = false,
        log_vmin = log_vmin,
        show_allowed_momenta = show_allowed_momenta,
        allowed_momenta_color = allowed_momenta_color,
        allowed_momenta_size = allowed_momenta_size,
    )

    tempdir = mktempdir()
    frame_paths = String[]
    frame_counter = 0

    try
        function save_current_frame!(J2_value::Real)
            frame, _, _, _ = interpolate_structure_factor(Sq_stack, Js, J2_value)

            update_structure_factor_artist!(
                image,
                ax,
                frame,
                J2_value;
                normalize = normalize,
                logscale = logscale,
                log_vmin = log_vmin,
            )
            fig.canvas.draw()
            path = joinpath(tempdir, "frame_" * lpad(string(frame_counter), 4, '0') * ".png")
            savefig(path, dpi = 160, bbox_inches = "tight")
            push!(frame_paths, path)
            return nothing
        end

        sampled_Js = Float64[]
        for idx in 1:(length(Js) - 1)
            segment = collect(range(Js[idx], Js[idx + 1]; length = frames_per_interval + 1))
            append!(sampled_Js, idx == 1 ? segment : segment[2:end])
        end
        if isempty(sampled_Js)
            sampled_Js = [Js[1]]
        end

        for J2_value in sampled_Js
            for _ in 1:hold_frames
                frame_counter += 1
                save_current_frame!(J2_value)
            end
        end

        pil_frames = pybuiltin("list")([PILImage.open(path) for path in frame_paths])
        duration_ms = round(Int, 1000 / max(fps, 1))
        first_frame = pil_frames[1]
        append_images = pil_frames[2:end]
        first_frame.save(
            output_gif;
            save_all = true,
            append_images = append_images,
            duration = duration_ms,
            loop = 0,
        )
        println("Saved animated GIF to $output_gif")
    finally
        close(fig)
        rm(tempdir; recursive = true, force = true)
    end

    return output_gif
end

function main(args::Vector{String})
    config = parse_cli(args)
    config === nothing && return

    process_static_structure_factor(
        config["input_file"],
        config["C"],
        config["L"];
        connected = config["connected"],
        reference_site = config["reference_site"],
        corrs_dataset = config["corrs_dataset"],
        nqx = config["nqx"],
        nqy = config["nqy"],
        output_prefix = isempty(config["output_prefix"]) ? default_output_prefix(config["input_file"]) : config["output_prefix"],
        logscale = config["logscale"],
        normalize = config["normalize"],
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
