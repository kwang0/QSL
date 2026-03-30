using HDF5
using PyPlot
using PyCall

@pyimport matplotlib.widgets as widgets
@pyimport PIL.Image as PILImage

const SQRT3 = sqrt(3.0)

site_row(i::Integer, C::Integer) = (i - 1) % C + 1
site_col(i::Integer, C::Integer) = div(i - 1, C) + 1

function yc_center_site(C::Integer, L::Integer)
    center_col = cld(L, 2)
    center_row = cld(C, 2)
    return (center_col - 1) * C + center_row
end

function discover_ground_state_search_files_for_corrs(
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

function read_ground_state_corrs_for_plot(
    input_file::AbstractString;
    corrs_dataset::AbstractString = "corrs",
)
    h5open(input_file, "r") do file
        haskey(file, corrs_dataset) || error("The file $input_file does not contain a `$corrs_dataset` dataset.")
        corrs = read(file, corrs_dataset)
        Zs = haskey(file, "Zs") ? vec(read(file, "Zs")) : nothing
        return ComplexF64.(corrs), Zs
    end
end

function select_correlation_component(corrs::AbstractVector, component::Symbol)
    if component === :real
        return real.(corrs)
    elseif component === :imag
        return imag.(corrs)
    elseif component === :abs
        return abs.(corrs)
    end

    error("Unsupported component `$component`. Use :real, :imag, or :abs.")
end

function extract_reference_corrs(
    input_file::AbstractString,
    C::Integer,
    L::Integer;
    reference_site::Integer = yc_center_site(C, L),
    connected::Bool = false,
    component::Symbol = :real,
    corrs_dataset::AbstractString = "corrs",
)
    corrs, Zs = read_ground_state_corrs_for_plot(input_file; corrs_dataset = corrs_dataset)
    size(corrs, 1) == size(corrs, 2) || error("Expected a square correlation matrix in $input_file.")

    N = C * L
    size(corrs, 1) == N || error("Expected `$corrs_dataset` to have size ($N, $N), got $(size(corrs)).")
    1 <= reference_site <= N || error("reference_site = $reference_site is outside 1:$N.")

    ref_corrs = vec(corrs[reference_site, :])
    if connected
        isnothing(Zs) && error("Requested connected correlations, but `Zs` is missing from $input_file.")
        ref_corrs .-= ComplexF64.(Zs[reference_site] .* Zs)
    end

    values = reshape(select_correlation_component(ref_corrs, component), C, L)
    return values
end

function interpolate_corr_grid(
    corr_stack::Array{Float64, 3},
    values::AbstractVector,
    x::Real,
)
    idx_hi = searchsortedfirst(values, x)
    if idx_hi <= 1
        return copy(@view corr_stack[:, :, 1]), values[1], values[1], 0.0
    elseif idx_hi > length(values)
        return copy(@view corr_stack[:, :, end]), values[end], values[end], 0.0
    end

    idx_lo = idx_hi - 1
    x_lo = values[idx_lo]
    x_hi = values[idx_hi]
    weight_hi = (x - x_lo) / (x_hi - x_lo)
    weight_lo = 1 - weight_hi
    frame = weight_lo .* @view(corr_stack[:, :, idx_lo]) .+ weight_hi .* @view(corr_stack[:, :, idx_hi])
    return frame, x_lo, x_hi, weight_hi
end

function triangular_yc_positions(C::Integer, L::Integer)
    xs = Matrix{Float64}(undef, C, L)
    ys = Matrix{Float64}(undef, C, L)

    for col in 1:L
        x = (SQRT3 / 2) * (col - 1)
        y_shift = 0.5 * isodd(col - 1)
        for row in 1:C
            xs[row, col] = x
            ys[row, col] = (row - 1) + y_shift
        end
    end

    return xs, ys
end

function draw_triangular_yc_bonds!(ax, xs::AbstractMatrix, ys::AbstractMatrix)
    C, L = size(xs)

    for col in 1:L
        for row in 1:C
            x0 = xs[row, col]
            y0 = ys[row, col]

            if row < C
                ax.plot([x0, xs[row + 1, col]], [y0, ys[row + 1, col]]; color = "0.85", linewidth = 0.8, zorder = 0)
            end
            if col < L
                ax.plot([x0, xs[row, col + 1]], [y0, ys[row, col + 1]]; color = "0.85", linewidth = 0.8, zorder = 0)
            end
            if col < L
                diag_row = isodd(col) ? row - 1 : row + 1
                if 1 <= diag_row <= C
                    ax.plot([x0, xs[diag_row, col + 1]], [y0, ys[diag_row, col + 1]]; color = "0.85", linewidth = 0.8, zorder = 0)
                end
            end
        end
    end

    return nothing
end

function corrs_colorbar_label(component::Symbol)
    if component === :real
        return raw"$\mathrm{Re}\,\langle S_i^z S_j^z \rangle$"
    elseif component === :imag
        return raw"$\mathrm{Im}\,\langle S_i^z S_j^z \rangle$"
    elseif component === :abs
        return raw"$|\langle S_i^z S_j^z \rangle|$"
    end

    error("Unsupported component `$component`. Use :real, :imag, or :abs.")
end

function default_corr_color_limits(data, component::Symbol)
    bound = maximum(abs, data)
    bound = bound > 0 ? bound : 1e-12
    return component === :abs ? (0.0, bound) : (-bound, bound)
end

function resolve_corr_color_scale(
    data,
    component::Symbol;
    color_limits = nothing,
    logscale::Bool = false,
    log_vmin::Real = 1e-3,
    symlog_linthresh = nothing,
)
    resolved_color_limits = isnothing(color_limits) ? default_corr_color_limits(data, component) : color_limits

    if !logscale
        return (color_limits = resolved_color_limits, norm = nothing)
    end

    if component === :abs || resolved_color_limits[1] >= 0
        vmin = max(resolved_color_limits[1], log_vmin)
        vmax = max(resolved_color_limits[2], vmin * (1 + 1e-12))
        norm = matplotlib[:colors][:LogNorm](vmin = vmin, vmax = vmax)
        return (color_limits = (vmin, vmax), norm = norm)
    end

    maxabs = max(abs(resolved_color_limits[1]), abs(resolved_color_limits[2]))
    linthresh = isnothing(symlog_linthresh) ? max(log_vmin, 0.05 * maxabs) : symlog_linthresh
    norm = matplotlib[:colors][:SymLogNorm](
        linthresh = linthresh,
        vmin = -maxabs,
        vmax = maxabs,
        base = 10,
    )
    return (color_limits = (-maxabs, maxabs), norm = norm)
end

function create_corr_artist!(
    ax,
    frame::AbstractMatrix,
    C::Integer,
    L::Integer;
    plot_mode::Symbol,
    cmap::AbstractString,
    color_limits,
    color_norm,
    reference_site::Integer,
    site_marker_size::Real,
)
    if plot_mode === :image
        if isnothing(color_norm)
            artist = ax.imshow(
                frame,
                origin = "lower",
                cmap = cmap,
                vmin = color_limits[1],
                vmax = color_limits[2],
                aspect = "auto",
            )
        else
            artist = ax.imshow(
                frame,
                origin = "lower",
                cmap = cmap,
                norm = color_norm,
                aspect = "auto",
            )
        end
        ax.set_xlabel("Cylinder length index")
        ax.set_ylabel("Circumference index")
        return artist
    elseif plot_mode === :triangular
        xs, ys = triangular_yc_positions(C, L)
        draw_triangular_yc_bonds!(ax, xs, ys)

        if isnothing(color_norm)
            artist = ax.scatter(
                vec(xs),
                vec(ys),
                c = vec(frame),
                cmap = cmap,
                vmin = color_limits[1],
                vmax = color_limits[2],
                s = site_marker_size,
                marker = "o",
                edgecolors = "0.2",
                linewidths = 0.8,
                zorder = 2,
            )
        else
            artist = ax.scatter(
                vec(xs),
                vec(ys),
                c = vec(frame),
                cmap = cmap,
                norm = color_norm,
                s = site_marker_size,
                marker = "o",
                edgecolors = "0.2",
                linewidths = 0.8,
                zorder = 2,
            )
        end

        row = site_row(reference_site, C)
        col = site_col(reference_site, C)
        highlight_marker_size = 1.35 * site_marker_size
        highlight_linewidth = max(1.5, 0.012 * site_marker_size)
        ax.scatter(
            [xs[row, col]],
            [ys[row, col]];
            s = highlight_marker_size,
            facecolors = "none",
            edgecolors = "forestgreen",
            linewidths = highlight_linewidth,
            zorder = 3,
        )

        ax.set_xlabel("Open YC direction")
        ax.set_ylabel("Wrapped YC direction")
        ax.set_aspect("equal")
        ax.set_xlim(minimum(xs) - 0.8, maximum(xs) + 0.8)
        ax.set_ylim(minimum(ys) - 0.8, maximum(ys) + 0.8)
        return artist
    end

    error("Unsupported plot_mode `$plot_mode`. Use :triangular or :image.")
end

function update_corr_artist!(artist, frame::AbstractMatrix; plot_mode::Symbol)
    if plot_mode === :image
        artist.set_data(frame)
    elseif plot_mode === :triangular
        artist.set_array(vec(frame))
    else
        error("Unsupported plot_mode `$plot_mode`. Use :triangular or :image.")
    end
    return nothing
end

function format_corrs_title(
    J2_value::Real,
    reference_site::Integer,
    C::Integer;
    component::Symbol = :real,
    corrs_dataset::AbstractString = "corrs",
)
    row = site_row(reference_site, C)
    col = site_col(reference_site, C)
    component_label =
        component === :real ? "Re" :
        component === :imag ? "Im" :
        "Abs"
    rounded_J2 = round(J2_value, digits = 3)
    dataset_suffix = corrs_dataset == "corrs" ? "" : " [$corrs_dataset]"
    return component_label * raw"($\langle S_i^z S_j^z \rangle$)" *
           ", central site (row = $(row), col = $(col))" *
           dataset_suffix * ", " * raw"$J_2/J_1$" * " = $(rounded_J2)"
end

function format_reference_corrs_title(
    reference_site::Integer,
    C::Integer;
    component::Symbol = :real,
    corrs_dataset::AbstractString = "corrs",
    state_label::AbstractString = "",
)
    row = site_row(reference_site, C)
    col = site_col(reference_site, C)
    component_label =
        component === :real ? "Re" :
        component === :imag ? "Im" :
        "Abs"

    dataset_suffix = corrs_dataset == "corrs" ? "" : " [$corrs_dataset]"
    title = component_label * raw"($\langle S_i^z S_j^z \rangle$)" *
            ", central site (row = $(row), col = $(col))" * dataset_suffix
    if !isempty(state_label)
        title *= ", " * state_label
    end
    return title
end

function infer_J2_from_filename(input_file::AbstractString)
    name = basename(input_file)
    match_obj = match(r"_J([0-9eE+\-\.]+)_1Delta", name)
    return isnothing(match_obj) ? nothing : parse(Float64, match_obj.captures[1])
end

function plot_corrs_from_file(
    input_file::AbstractString,
    C::Integer,
    L::Integer;
    reference_site::Integer = yc_center_site(C, L),
    connected::Bool = false,
    component::Symbol = :real,
    plot_mode::Symbol = :triangular,
    cmap::AbstractString = "RdBu_r",
    corrs_dataset::AbstractString = "corrs",
    color_limits = nothing,
    logscale::Bool = false,
    log_vmin::Real = 1e-3,
    symlog_linthresh = nothing,
    site_marker_size::Real = 100,
    title = nothing,
    state_label::AbstractString = "",
    show_plot::Bool = true,
)
    frame = extract_reference_corrs(
        input_file,
        C,
        L;
        reference_site = reference_site,
        connected = connected,
        component = component,
        corrs_dataset = corrs_dataset,
    )

    color_scale = resolve_corr_color_scale(
        frame,
        component;
        color_limits = color_limits,
        logscale = logscale,
        log_vmin = log_vmin,
        symlog_linthresh = symlog_linthresh,
    )
    resolved_color_limits = color_scale.color_limits

    inferred_J2 = infer_J2_from_filename(input_file)
    resolved_title =
        isnothing(title) ?
        (isnothing(inferred_J2) ?
            format_reference_corrs_title(reference_site, C; component = component, corrs_dataset = corrs_dataset, state_label = state_label) :
            format_corrs_title(inferred_J2, reference_site, C; component = component, corrs_dataset = corrs_dataset)
        ) :
        String(title)

    fig, ax = subplots(figsize = (10.0, 4.8))
    image = create_corr_artist!(
        ax,
        frame,
        C,
        L;
        plot_mode = plot_mode,
        cmap = cmap,
        color_limits = resolved_color_limits,
        color_norm = color_scale.norm,
        reference_site = reference_site,
        site_marker_size = site_marker_size,
    )
    colorbar(image, ax = ax, label = corrs_colorbar_label(component))
    ax.set_title(resolved_title)
    fig.subplots_adjust(left = 0.10, right = 0.90, top = 0.88, bottom = 0.16)

    if show_plot
        display(fig)
    end

    return (
        fig = fig,
        ax = ax,
        image = image,
        frame = frame,
        reference_site = reference_site,
        color_limits = resolved_color_limits,
        logscale = logscale,
        plot_mode = plot_mode,
        site_marker_size = site_marker_size,
        input_file = input_file,
        corrs_dataset = corrs_dataset,
    )
end

function plot_corrs_J2_slider(
    C::Integer,
    L::Integer;
    directory::AbstractString = "processed_data",
    delta1::Real = 1.0,
    delta2::Real = 1.0,
    chi::Integer = 512,
    reference_site::Integer = yc_center_site(C, L),
    connected::Bool = false,
    component::Symbol = :real,
    plot_mode::Symbol = :triangular,
    cmap::AbstractString = "RdBu_r",
    corrs_dataset::AbstractString = "corrs",
    color_limits = nothing,
    logscale::Bool = false,
    log_vmin::Real = 1e-3,
    symlog_linthresh = nothing,
    site_marker_size::Real = 100,
    show_plot::Bool = true,
)
    file_map = discover_ground_state_search_files_for_corrs(
        C,
        L;
        directory = directory,
        delta1 = delta1,
        delta2 = delta2,
        chi = chi,
    )
    J2_values = sort(collect(keys(file_map)))

    frames = [
        extract_reference_corrs(
            file_map[J2],
            C,
            L;
            reference_site = reference_site,
            connected = connected,
            component = component,
            corrs_dataset = corrs_dataset,
        ) for J2 in J2_values
    ]

    corr_stack = Array{Float64}(undef, C, L, length(J2_values))
    for (idx, frame) in enumerate(frames)
        corr_stack[:, :, idx] .= frame
    end

    first_frame = corr_stack[:, :, 1]
    color_scale = resolve_corr_color_scale(
        corr_stack,
        component;
        color_limits = color_limits,
        logscale = logscale,
        log_vmin = log_vmin,
        symlog_linthresh = symlog_linthresh,
    )
    resolved_color_limits = color_scale.color_limits

    fig, ax = subplots(figsize = (10.0, 4.8))
    image = create_corr_artist!(
        ax,
        first_frame,
        C,
        L;
        plot_mode = plot_mode,
        cmap = cmap,
        color_limits = resolved_color_limits,
        color_norm = color_scale.norm,
        reference_site = reference_site,
        site_marker_size = site_marker_size,
    )
    colorbar(image, ax = ax, label = corrs_colorbar_label(component))
    ax.set_title(format_corrs_title(J2_values[1], reference_site, C; component = component, corrs_dataset = corrs_dataset))

    fig.subplots_adjust(left = 0.10, right = 0.90, top = 0.88, bottom = 0.22)
    ax_slider = fig.add_axes([0.20, 0.08, 0.60, 0.05])
    slider = widgets.Slider(
        ax_slider,
        raw"$J_2/J_1$",
        J2_values[1],
        J2_values[end],
        valinit = J2_values[1],
        valfmt = "%0.3f",
    )

    function update_slider(val)
        J2_value = Float64(val)
        frame, _, _, _ = interpolate_corr_grid(corr_stack, J2_values, J2_value)
        update_corr_artist!(image, frame; plot_mode = plot_mode)
        ax.set_title(format_corrs_title(J2_value, reference_site, C; component = component, corrs_dataset = corrs_dataset))
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
        J2_values = J2_values,
        file_map = file_map,
        corr_stack = corr_stack,
        reference_site = reference_site,
        corrs_dataset = corrs_dataset,
        color_limits = resolved_color_limits,
        logscale = logscale,
        plot_mode = plot_mode,
        site_marker_size = site_marker_size,
    )
end

function export_corrs_J2_gif(
    output_gif::AbstractString,
    C::Integer,
    L::Integer;
    directory::AbstractString = "processed_data",
    delta1::Real = 1.0,
    delta2::Real = 1.0,
    chi::Integer = 512,
    reference_site::Integer = yc_center_site(C, L),
    connected::Bool = false,
    component::Symbol = :real,
    plot_mode::Symbol = :triangular,
    cmap::AbstractString = "RdBu_r",
    corrs_dataset::AbstractString = "corrs",
    color_limits = nothing,
    logscale::Bool = false,
    log_vmin::Real = 1e-3,
    symlog_linthresh = nothing,
    site_marker_size::Real = 100,
    fps::Integer = 10,
    frames_per_interval::Integer = 4,
    hold_frames::Integer = 1,
)
    viewer = plot_corrs_J2_slider(
        C,
        L;
        directory = directory,
        delta1 = delta1,
        delta2 = delta2,
        chi = chi,
        reference_site = reference_site,
        connected = connected,
        component = component,
        plot_mode = plot_mode,
        cmap = cmap,
        corrs_dataset = corrs_dataset,
        color_limits = color_limits,
        logscale = logscale,
        log_vmin = log_vmin,
        symlog_linthresh = symlog_linthresh,
        site_marker_size = site_marker_size,
        show_plot = false,
    )

    J2_values = viewer.J2_values
    corr_stack = viewer.corr_stack
    resolved_color_limits = viewer.color_limits
    close(viewer.fig)

    color_scale = resolve_corr_color_scale(
        corr_stack,
        component;
        color_limits = resolved_color_limits,
        logscale = logscale,
        log_vmin = log_vmin,
        symlog_linthresh = symlog_linthresh,
    )

    first_frame = corr_stack[:, :, 1]
    fig, ax = subplots(figsize = (10.0, 4.8))
    image = create_corr_artist!(
        ax,
        first_frame,
        C,
        L;
        plot_mode = plot_mode,
        cmap = cmap,
        color_limits = color_scale.color_limits,
        color_norm = color_scale.norm,
        reference_site = reference_site,
        site_marker_size = site_marker_size,
    )
    colorbar(image, ax = ax, label = corrs_colorbar_label(component))
    ax.set_title(format_corrs_title(J2_values[1], reference_site, C; component = component, corrs_dataset = corrs_dataset))
    fig.subplots_adjust(left = 0.10, right = 0.90, top = 0.88, bottom = 0.16)

    tempdir = mktempdir()
    frame_paths = String[]
    frame_counter = 0

    try
        function save_current_frame!(J2_value::Real)
            frame, _, _, _ = interpolate_corr_grid(corr_stack, J2_values, J2_value)
            update_corr_artist!(image, frame; plot_mode = plot_mode)
            ax.set_title(format_corrs_title(J2_value, reference_site, C; component = component, corrs_dataset = corrs_dataset))
            fig.canvas.draw()
            path = joinpath(tempdir, "frame_" * lpad(string(frame_counter), 4, '0') * ".png")
            savefig(path, dpi = 160, bbox_inches = "tight")
            push!(frame_paths, path)
            return nothing
        end

        sampled_J2_values = Float64[]
        for idx in 1:(length(J2_values) - 1)
            segment = collect(range(J2_values[idx], J2_values[idx + 1]; length = frames_per_interval + 1))
            append!(sampled_J2_values, idx == 1 ? segment : segment[2:end])
        end
        if isempty(sampled_J2_values)
            sampled_J2_values = [J2_values[1]]
        end

        for J2_value in sampled_J2_values
            for _ in 1:hold_frames
                frame_counter += 1
                save_current_frame!(J2_value)
            end
        end

        pil_frames = pybuiltin("list")([PILImage.open(path) for path in frame_paths])
        duration_ms = round(Int, 1000 / max(fps, 1))
        first_frame_image = pil_frames[1]
        append_images = pil_frames[2:end]
        first_frame_image.save(
            output_gif;
            save_all = true,
            append_images = append_images,
            duration = duration_ms,
            loop = 0,
        )
        println("Saved animated GIF to " * output_gif)
    finally
        close(fig)
        rm(tempdir; recursive = true, force = true)
    end

    return output_gif
end
