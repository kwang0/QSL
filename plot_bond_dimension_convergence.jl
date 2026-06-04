ENV["MPLBACKEND"] = get(ENV, "MPLBACKEND", "Agg")

using HDF5
using LinearAlgebra
using Printf
using PyPlot
using Statistics

const SQRT3 = sqrt(3.0)

struct BondRun
    chi::Int
    path::String
    E0::Float64
    entropy::Float64
    final_maxerr::Float64
    energy_variance::Float64
    energy_variance_per_site::Float64
    sweep_energies::Vector{Float64}
    sweep_maxerrs::Vector{Float64}
    Zs::Vector{Float64}
    corrs::Matrix{Float64}
    connected_corrs::Matrix{Float64}
    m1202_bulk::Float64
    m1202_full::Float64
    m1202_offdiag_bulk::Float64
    m1202_by_k_bulk::Vector{Float64}
    best_k_label::String
end

site_index(row::Integer, col::Integer, C::Integer) = col * C + mod(row, C) + 1
site_row(i::Integer, C::Integer) = (i - 1) % C + 1
site_col(i::Integer, C::Integer) = div(i - 1, C) + 1

function xc_positions(C::Integer, L::Integer)
    xs = Matrix{Float64}(undef, C, L)
    ys = Matrix{Float64}(undef, C, L)
    for col in 1:L
        for row in 1:C
            row0 = row - 1
            xs[row, col] = (col - 1) + 0.5 * isodd(row0)
            ys[row, col] = row0 * SQRT3 / 2
        end
    end
    return xs, ys
end

function draw_xc_bonds!(ax, xs::AbstractMatrix, ys::AbstractMatrix)
    C, L = size(xs)
    for col in 1:L
        for row in 1:C
            x0 = xs[row, col]
            y0 = ys[row, col]
            if row < C
                ax.plot([x0, xs[row + 1, col]], [y0, ys[row + 1, col]];
                        color = "0.86", linewidth = 0.7, zorder = 0)
            end
            if col < L
                ax.plot([x0, xs[row, col + 1]], [y0, ys[row, col + 1]];
                        color = "0.86", linewidth = 0.7, zorder = 0)
            end
            if col < L && iseven(row)
                for diag_row in (row - 1, row + 1)
                    if 1 <= diag_row <= C
                        ax.plot([x0, xs[diag_row, col + 1]], [y0, ys[diag_row, col + 1]];
                                color = "0.86", linewidth = 0.7, zorder = 0)
                    end
                end
            end
        end
    end
    return nothing
end

function center_site(C::Integer, L::Integer)
    center_col = cld(L, 2)
    center_row = cld(C, 2)
    return (center_col - 1) * C + center_row
end

function bulk_indices(C::Integer, L::Integer; edge_cols::Integer = 4)
    if 2 * edge_cols >= L
        return collect(1:(C * L))
    end
    inds = Int[]
    for col0 in edge_cols:(L - edge_cols - 1)
        for row0 in 0:(C - 1)
            push!(inds, site_index(row0, col0, C))
        end
    end
    return inds
end

function k_vectors_120()
    return [
        ("K1", (4pi / 3, 0.0)),
        ("K2", (2pi / 3, 2pi / SQRT3)),
        ("K3", (-2pi / 3, 2pi / SQRT3)),
    ]
end

function structure_factor_m1202(
    connected_corrs::AbstractMatrix,
    C::Integer,
    L::Integer;
    inds::AbstractVector{<:Integer} = collect(1:(C * L)),
)
    xs, ys = xc_positions(C, L)
    xvec = vec(xs)
    yvec = vec(ys)
    nsites = length(inds)
    vals = Float64[]
    labels = String[]

    for (label, (kx, ky)) in k_vectors_120()
        phase = exp.(im .* (kx .* xvec[inds] .+ ky .* yvec[inds]))
        subcorrs = connected_corrs[inds, inds]
        szz_q = real(dot(phase, subcorrs * phase)) / nsites
        push!(vals, 3 * szz_q / nsites)
        push!(labels, label)
    end

    best = argmax(vals)
    return vals[best], vals, labels[best]
end

function structure_factor_m1202_offdiag(
    connected_corrs::AbstractMatrix,
    C::Integer,
    L::Integer;
    inds::AbstractVector{<:Integer} = collect(1:(C * L)),
)
    xs, ys = xc_positions(C, L)
    xvec = vec(xs)
    yvec = vec(ys)
    nsites = length(inds)
    nsites <= 1 && return NaN

    best = -Inf
    for (_, (kx, ky)) in k_vectors_120()
        phase = exp.(im .* (kx .* xvec[inds] .+ ky .* yvec[inds]))
        subcorrs = copy(connected_corrs[inds, inds])
        for i in 1:nsites
            subcorrs[i, i] = 0.0
        end
        szz_q = real(dot(phase, subcorrs * phase)) / (nsites * (nsites - 1))
        best = max(best, 3 * szz_q)
    end
    return best
end

function read_scalar(file, key::AbstractString; default = NaN)
    return haskey(file, key) ? Float64(read(file, key)) : Float64(default)
end

function read_entropy(file)
    if haskey(file, "S")
        return Float64(read(file, "S"))
    elseif haskey(file, "Ss")
        values = vec(read(file, "Ss"))
        return Float64(values[end])
    end
    return NaN
end

function read_vector(file, key::AbstractString)
    return haskey(file, key) ? Float64.(vec(real.(read(file, key)))) : Float64[]
end

function discover_ground_state_files(
    directory::AbstractString;
    C::Integer,
    L::Integer,
    J2::Real,
    delta1::Real,
    delta2::Real,
    chis::AbstractVector{<:Integer},
    geometry::Symbol = :XC,
)
    pattern = r"^ground_state_search(_YC)?_C([0-9]+)_L([0-9]+)_J([0-9eE+\-.]+)_1Delta([0-9eE+\-.]+)_2Delta([0-9eE+\-.]+)_chi([0-9]+).*\.h5$"
    wanted = Set(Int.(chis))
    files = Dict{Int,String}()
    for path in readdir(directory; join = true)
        name = basename(path)
        m = match(pattern, name)
        isnothing(m) && continue
        is_yc = !isnothing(m.captures[1])
        file_geometry = is_yc ? :YC : :XC
        file_geometry == geometry || continue
        parse(Int, m.captures[2]) == C || continue
        parse(Int, m.captures[3]) == L || continue
        isapprox(parse(Float64, m.captures[4]), Float64(J2); atol = 1e-12) || continue
        isapprox(parse(Float64, m.captures[5]), Float64(delta1); atol = 1e-12) || continue
        isapprox(parse(Float64, m.captures[6]), Float64(delta2); atol = 1e-12) || continue
        chi = parse(Int, m.captures[7])
        chi in wanted || continue
        files[chi] = path
    end
    missing = setdiff(wanted, Set(keys(files)))
    isempty(missing) || error("Missing chi files in $(directory): $(sort(collect(missing)))")
    return files
end

function read_run(path::AbstractString, chi::Integer, C::Integer, L::Integer; edge_cols::Integer = 4)
    h5open(path, "r") do file
        E0 = read_scalar(file, "E0")
        entropy = read_entropy(file)
        final_maxerr = read_scalar(file, "final_maxerr")
        energy_variance = read_scalar(file, "energy_variance")
        energy_variance_per_site = read_scalar(file, "energy_variance_per_site")
        sweep_energies = read_vector(file, "sweep_energies")
        sweep_maxerrs = read_vector(file, "sweep_maxerrs")
        if isnan(final_maxerr) && !isempty(sweep_maxerrs)
            final_maxerr = sweep_maxerrs[end]
        end

        Zs = Float64.(vec(real.(read(file, "Zs"))))
        corrs = Float64.(real.(read(file, "corrs")))
        connected_corrs = corrs .- Zs * transpose(Zs)
        N = C * L
        size(corrs) == (N, N) || error("Expected $(N)x$(N) corrs in $(path), got $(size(corrs))")
        length(Zs) == N || error("Expected $(N) Zs in $(path), got $(length(Zs))")

        bulk = bulk_indices(C, L; edge_cols = edge_cols)
        m1202_bulk, m1202_by_k_bulk, best_k_label =
            structure_factor_m1202(connected_corrs, C, L; inds = bulk)
        m1202_full, _, _ = structure_factor_m1202(connected_corrs, C, L)
        m1202_offdiag_bulk =
            structure_factor_m1202_offdiag(connected_corrs, C, L; inds = bulk)

        return BondRun(
            chi,
            path,
            E0,
            entropy,
            final_maxerr,
            energy_variance,
            energy_variance_per_site,
            sweep_energies,
            sweep_maxerrs,
            Zs,
            corrs,
            connected_corrs,
            m1202_bulk,
            m1202_full,
            m1202_offdiag_bulk,
            m1202_by_k_bulk,
            best_k_label,
        )
    end
end

function rms_abs(x)
    return sqrt(mean(abs2, x))
end

function safe_log_values(values)
    return [v > 0 && isfinite(v) ? v : NaN for v in values]
end

function output_tag(C, L, J2, delta1, delta2, chis)
    jtag = replace(string(J2), "." => "p")
    dtag = replace("D$(delta1)_$(delta2)", "." => "p")
    return "bond_dim_convergence_XC_C$(C)_L$(L)_J$(jtag)_$(dtag)_chi$(minimum(chis))-$(maximum(chis))"
end

function save_figure(fig, output_dir::AbstractString, stem::AbstractString)
    png = joinpath(output_dir, stem * ".png")
    pdf = joinpath(output_dir, stem * ".pdf")
    fig.savefig(png; dpi = 220, bbox_inches = "tight")
    fig.savefig(pdf; bbox_inches = "tight")
    close(fig)
    return png, pdf
end

function plot_summary(runs::Vector{BondRun}, C::Integer, L::Integer, output_dir::AbstractString, tag::AbstractString)
    chis = [r.chi for r in runs]
    inv_chis = 1.0 ./ chis
    N = C * L
    ref = runs[end]
    rms_dZ = [rms_abs(r.Zs .- ref.Zs) for r in runs]
    max_dZ = [maximum(abs.(r.Zs .- ref.Zs)) for r in runs]
    rms_dC = [rms_abs(r.connected_corrs .- ref.connected_corrs) for r in runs]
    max_dC = [maximum(abs.(r.connected_corrs .- ref.connected_corrs)) for r in runs]

    fig, axs = subplots(2, 3, figsize = (14.0, 8.0))

    ax = axs[1, 1]
    ax.plot(inv_chis, [r.E0 / N for r in runs], marker = "o", color = "tab:blue")
    ax.set_xlabel(raw"$1/\chi$")
    ax.set_ylabel(raw"$E_0/N$")
    ax.set_title("Energy")
    ax.grid(true; alpha = 0.25)

    ax = axs[1, 2]
    ax.plot(chis, safe_log_values([r.energy_variance_per_site for r in runs]),
            marker = "o", label = "variance/N", color = "tab:red")
    ax.plot(chis, safe_log_values([r.final_maxerr for r in runs]),
            marker = "s", label = "final maxerr", color = "tab:purple")
    ax.set_yscale("log")
    ax.set_xlabel(raw"$\chi$")
    ax.set_title("DMRG Quality")
    ax.legend(frameon = false)
    ax.grid(true; alpha = 0.25, which = "both")

    ax = axs[1, 3]
    ax.plot(inv_chis, [r.entropy for r in runs], marker = "o", color = "tab:green")
    ax.set_xlabel(raw"$1/\chi$")
    ax.set_ylabel(raw"$S_{\mathrm{vN}}$")
    ax.set_title("Mid-Bond Entropy")
    ax.grid(true; alpha = 0.25)

    ax = axs[2, 1]
    ax.plot(inv_chis, [r.m1202_bulk for r in runs], marker = "o", color = "tab:orange",
            label = raw"$m_{120}^2$")
    ax.set_xlabel(raw"$1/\chi$")
    ax.set_ylabel(raw"$m_{120}^2$")
    ax.set_title("120-Degree Order, Bulk Connected")
    ax.grid(true; alpha = 0.25)

    ax = axs[2, 2]
    ax.plot(chis, safe_log_values(rms_dZ), marker = "o", color = "tab:blue", label = "RMS")
    ax.plot(chis, safe_log_values(max_dZ), marker = "s", color = "tab:cyan", label = "max")
    ax.set_yscale("log")
    ax.set_xlabel(raw"$\chi$")
    ax.set_title("Local Magnetization Change vs Highest Chi")
    ax.legend(frameon = false)
    ax.grid(true; alpha = 0.25, which = "both")

    ax = axs[2, 3]
    ax.plot(chis, safe_log_values(rms_dC), marker = "o", color = "tab:red", label = "RMS")
    ax.plot(chis, safe_log_values(max_dC), marker = "s", color = "tab:pink", label = "max")
    ax.set_yscale("log")
    ax.set_xlabel(raw"$\chi$")
    ax.set_title("Connected Correlation Change vs Highest Chi")
    ax.legend(frameon = false)
    ax.grid(true; alpha = 0.25, which = "both")

    fig.suptitle("Bond-Dimension Convergence: XC C$(C) L$(L)")
    fig.tight_layout(rect = [0, 0, 1, 0.95])
    return save_figure(fig, output_dir, tag * "_summary")
end

function linear_fit(x, y)
    keep = findall(i -> isfinite(x[i]) && isfinite(y[i]), eachindex(x))
    length(keep) >= 2 || return nothing
    A = hcat(ones(length(keep)), x[keep])
    coeff = A \ y[keep]
    return keep, coeff
end

function plot_energy_extrapolation(runs::Vector{BondRun}, C::Integer, L::Integer, output_dir::AbstractString, tag::AbstractString)
    N = C * L
    e = [r.E0 / N for r in runs]
    xs = [
        ("variance/N", [r.energy_variance_per_site for r in runs]),
        ("final maxerr", [r.final_maxerr for r in runs]),
    ]

    fig, axs = subplots(1, 2, figsize = (10.5, 4.2))
    for (panel, (xlabel, x)) in enumerate(xs)
        ax = axs[panel]
        ax.scatter(x, e; color = "tab:blue", zorder = 3)
        for (i, r) in enumerate(runs)
            ax.annotate("$(r.chi)", (x[i], r.E0 / N);
                        xytext = (5, 5), textcoords = "offset points", fontsize = 8)
        end
        fit = linear_fit(x, e)
        if !isnothing(fit)
            keep, coeff = fit
            xmin, xmax = extrema(x[keep])
            xx = collect(range(min(0.0, xmin), xmax; length = 100))
            yy = coeff[1] .+ coeff[2] .* xx
            ax.plot(xx, yy; color = "tab:orange", linewidth = 1.6,
                    label = @sprintf("intercept %.10f", coeff[1]))
            ax.legend(frameon = false, fontsize = 8)
        end
        ax.set_xlabel(xlabel)
        ax.set_ylabel(raw"$E_0/N$")
        ax.set_title("Energy Extrapolation")
        ax.grid(true; alpha = 0.25)
    end

    fig.tight_layout()
    return save_figure(fig, output_dir, tag * "_energy_extrapolation")
end

function plot_sweep_histories(runs::Vector{BondRun}, C::Integer, L::Integer, output_dir::AbstractString, tag::AbstractString)
    N = C * L
    fig, axs = subplots(1, 2, figsize = (11.0, 4.2))

    ax = axs[1]
    for r in runs
        isempty(r.sweep_energies) && continue
        sweeps = collect(1:length(r.sweep_energies))
        residual = abs.(r.sweep_energies .- r.E0) ./ N
        residual[end] = max(residual[end], 1e-16)
        ax.plot(sweeps, residual; marker = "o", label = "chi $(r.chi)")
    end
    ax.set_yscale("log")
    ax.set_xlabel("sweep")
    ax.set_ylabel(raw"$|E_{\mathrm{sweep}}-E_0|/N$")
    ax.set_title("Sweep Energy Residual")
    ax.legend(frameon = false, fontsize = 8)
    ax.grid(true; alpha = 0.25, which = "both")

    ax = axs[2]
    for r in runs
        isempty(r.sweep_maxerrs) && continue
        sweeps = collect(1:length(r.sweep_maxerrs))
        ax.plot(sweeps, safe_log_values(r.sweep_maxerrs); marker = "o", label = "chi $(r.chi)")
    end
    ax.set_yscale("log")
    ax.set_xlabel("sweep")
    ax.set_ylabel("maxerr")
    ax.set_title("Sweep Truncation Error")
    ax.legend(frameon = false, fontsize = 8)
    ax.grid(true; alpha = 0.25, which = "both")

    fig.tight_layout()
    return save_figure(fig, output_dir, tag * "_sweeps")
end

function plot_reference_maps(runs::Vector{BondRun}, C::Integer, L::Integer, output_dir::AbstractString, tag::AbstractString)
    ref_site = center_site(C, L)
    ref_run = runs[end]
    xs, ys = xc_positions(C, L)
    corr_frames = [reshape(r.connected_corrs[ref_site, :], C, L) for r in runs]
    diff_frames = [frame .- reshape(ref_run.connected_corrs[ref_site, :], C, L) for frame in corr_frames]
    corr_limit = maximum(maximum(abs.(frame)) for frame in corr_frames)
    diff_limit = maximum(maximum(abs.(frame)) for frame in diff_frames)
    diff_limit = max(diff_limit, 1e-12)

    ncols = length(runs)
    fig, axs = subplots(2, ncols, figsize = (4.0 * ncols, 7.0))
    for (j, r) in enumerate(runs)
        ax = axs[1, j]
        draw_xc_bonds!(ax, xs, ys)
        sc = ax.scatter(vec(xs), vec(ys); c = vec(corr_frames[j]), cmap = "RdBu_r",
                        vmin = -corr_limit, vmax = corr_limit, s = 35,
                        edgecolors = "0.2", linewidths = 0.25, zorder = 2)
        row = site_row(ref_site, C)
        col = site_col(ref_site, C)
        ax.scatter([xs[row, col]], [ys[row, col]]; s = 85, facecolors = "none",
                   edgecolors = "black", linewidths = 1.3, zorder = 3)
        ax.set_title("chi $(r.chi)")
        ax.set_aspect("equal")
        ax.set_axis_off()
        fig.colorbar(sc, ax = ax, fraction = 0.046, pad = 0.02)

        ax = axs[2, j]
        draw_xc_bonds!(ax, xs, ys)
        sc = ax.scatter(vec(xs), vec(ys); c = vec(diff_frames[j]), cmap = "RdBu_r",
                        vmin = -diff_limit, vmax = diff_limit, s = 35,
                        edgecolors = "0.2", linewidths = 0.25, zorder = 2)
        ax.set_title("difference from chi $(ref_run.chi)")
        ax.set_aspect("equal")
        ax.set_axis_off()
        fig.colorbar(sc, ax = ax, fraction = 0.046, pad = 0.02)
    end
    fig.suptitle("Center-Site Connected Correlations, XC Geometry")
    fig.tight_layout(rect = [0, 0, 1, 0.94])
    return save_figure(fig, output_dir, tag * "_center_connected_corrs")
end

function write_summary_csv(runs::Vector{BondRun}, C::Integer, L::Integer, output_dir::AbstractString, tag::AbstractString)
    ref = runs[end]
    path = joinpath(output_dir, tag * "_summary.csv")
    open(path, "w") do io
        println(io, join([
            "chi",
            "E0",
            "E_per_site",
            "S",
            "final_maxerr",
            "energy_variance",
            "energy_variance_per_site",
            "m1202_bulk_connected",
            "m120_bulk_connected",
            "m1202_full_connected",
            "m1202_offdiag_bulk_connected",
            "best_K",
            "rms_dZ_to_highest_chi",
            "max_dZ_to_highest_chi",
            "rms_dCconn_to_highest_chi",
            "max_dCconn_to_highest_chi",
            "path",
        ], ","))
        for r in runs
            rms_dZ = rms_abs(r.Zs .- ref.Zs)
            max_dZ = maximum(abs.(r.Zs .- ref.Zs))
            rms_dC = rms_abs(r.connected_corrs .- ref.connected_corrs)
            max_dC = maximum(abs.(r.connected_corrs .- ref.connected_corrs))
            @printf(
                io,
                "%d,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%s,%.17g,%.17g,%.17g,%.17g,%s\n",
                r.chi,
                r.E0,
                r.E0 / (C * L),
                r.entropy,
                r.final_maxerr,
                r.energy_variance,
                r.energy_variance_per_site,
                r.m1202_bulk,
                sqrt(max(r.m1202_bulk, 0.0)),
                r.m1202_full,
                r.m1202_offdiag_bulk,
                r.best_k_label,
                rms_dZ,
                max_dZ,
                rms_dC,
                max_dC,
                r.path,
            )
        end
    end
    return path
end

function print_summary(runs::Vector{BondRun}, C::Integer, L::Integer)
    println("Bond-dimension convergence summary")
    println("chi,E/N,S,final_maxerr,var/N,m1202_bulk,m120_bulk")
    for r in runs
        @printf(
            "%d,%.12f,%.9f,%.4e,%.4e,%.9f,%.9f\n",
            r.chi,
            r.E0 / (C * L),
            r.entropy,
            r.final_maxerr,
            r.energy_variance_per_site,
            r.m1202_bulk,
            sqrt(max(r.m1202_bulk, 0.0)),
        )
    end
end

function main(args = ARGS)
    directory = length(args) >= 1 ? args[1] : "processed_data"
    C = length(args) >= 2 ? parse(Int, args[2]) : 6
    L = length(args) >= 3 ? parse(Int, args[3]) : 36
    J2 = length(args) >= 4 ? parse(Float64, args[4]) : 0.043
    delta = length(args) >= 5 ? parse(Float64, args[5]) : 1.0
    chis = length(args) >= 6 ? parse.(Int, args[6:end]) : [513, 1025, 2049]

    output_dir = "plots_bond_dim_convergence"
    edge_cols = 4
    mkpath(output_dir)

    files = discover_ground_state_files(
        directory;
        C = C,
        L = L,
        J2 = J2,
        delta1 = delta,
        delta2 = delta,
        chis = chis,
        geometry = :XC,
    )
    sorted_chis = sort(collect(keys(files)))
    runs = [read_run(files[chi], chi, C, L; edge_cols = edge_cols) for chi in sorted_chis]

    tag = output_tag(C, L, J2, delta, delta, sorted_chis)
    summary_paths = plot_summary(runs, C, L, output_dir, tag)
    extrap_paths = plot_energy_extrapolation(runs, C, L, output_dir, tag)
    sweep_paths = plot_sweep_histories(runs, C, L, output_dir, tag)
    map_paths = plot_reference_maps(runs, C, L, output_dir, tag)
    csv_path = write_summary_csv(runs, C, L, output_dir, tag)

    print_summary(runs, C, L)
    println("Wrote:")
    for path in (summary_paths..., extrap_paths..., sweep_paths..., map_paths..., csv_path)
        println(path)
    end

    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
