ENV["MPLBACKEND"] = get(ENV, "MPLBACKEND", "Agg")

using HDF5
using Printf
using PyPlot

# Plot a Fig. 4a-style transfer-matrix spectrum:
# inverse correlation length 1/xi versus flux twist theta/pi.

const DEFAULT_OUTPUT_DIR = "plots_vumps_transfer_spectrum"
const LEVEL_COLORS = [
    "#d62728",
    "#f0ad00",
    "#1f77b4",
    "#2ca02c",
    "#9467bd",
    "#8c564b",
    "#e377c2",
    "#7f7f7f",
]

struct PlotOptions
    input_file::String
    output_dir::String
    max_levels::Int
    label_filter::String
    first_level::Int
    dataset_prefix::String
end

function usage()
    return """
    Usage:
      julia plot_vumps_transfer_spectrum_fig4a.jl input_file.h5 [output_dir] [max_levels] [label_filter] [first_level] [dataset_prefix]

    Defaults:
      output_dir   = $(DEFAULT_OUTPUT_DIR)
      max_levels   = 16
      label_filter = ""   # optional substring filter for transfer_flux_labels
      first_level  = 2    # skip dominant transfer eigenvalue with 1/xi = 0
      dataset_prefix = "transfer"

    Examples:
      julia plot_vumps_transfer_spectrum_fig4a.jl processed_data/ground_state_search_flux_threaded_vumps_YC8-2_J0.05_1Delta1.0_2Delta1.0_thetaPi2_chi6000.h5
      julia plot_vumps_transfer_spectrum_fig4a.jl processed_data/run.h5 plots_vumps_transfer_spectrum 12
      julia plot_vumps_transfer_spectrum_fig4a.jl processed_data/run.h5 plots_vumps_transfer_spectrum 16 Sz
      julia plot_vumps_transfer_spectrum_fig4a.jl processed_data/run.h5 plots_vumps_transfer_spectrum 16 "" 1 transfer_sz1
    """
end

function parse_args(args)
    any(arg -> startswith(arg, "-"), args) && error(usage())
    1 <= length(args) <= 6 || error(usage())

    input_file = args[1]
    isfile(input_file) || error("Input HDF5 file does not exist: $(input_file)")
    output_dir = length(args) >= 2 ? args[2] : DEFAULT_OUTPUT_DIR
    max_levels = length(args) >= 3 ? parse(Int, args[3]) : 16
    label_filter = length(args) >= 4 ? args[4] : ""
    first_level = length(args) >= 5 ? parse(Int, args[5]) : 2
    dataset_prefix = length(args) >= 6 ? args[6] : "transfer"

    max_levels >= 1 || error("max_levels must be >= 1")
    first_level >= 1 || error("first_level must be >= 1")
    !isempty(dataset_prefix) || error("dataset_prefix must be non-empty")
    return PlotOptions(input_file, output_dir, max_levels, label_filter, first_level, dataset_prefix)
end

function read_fluxes(file)
    if haskey(file, "fluxes")
        return Float64.(vec(real.(read(file, "fluxes"))))
    elseif haskey(file, "fluxes_over_pi")
        return pi .* Float64.(vec(real.(read(file, "fluxes_over_pi"))))
    else
        error("Missing fluxes or fluxes_over_pi")
    end
end

function orient_level_matrix(values, nflux::Integer, key::AbstractString)
    ndims(values) == 2 || error("Expected $(key) to be a matrix, got ndims=$(ndims(values))")
    if size(values, 2) == nflux
        return values
    elseif size(values, 1) == nflux
        return permutedims(values)
    else
        error("$(key) shape $(size(values)) is incompatible with $(nflux) flux points")
    end
end

function orient_level_matrix(values, nflux_candidates::AbstractVector{<:Integer}, key::AbstractString)
    ndims(values) == 2 || error("Expected $(key) to be a matrix, got ndims=$(ndims(values))")
    for nflux in nflux_candidates
        if size(values, 2) == nflux
            return values, nflux
        elseif size(values, 1) == nflux
            return permutedims(values), nflux
        end
    end
    expected = join(string.(nflux_candidates), ", ")
    error("$(key) shape $(size(values)) is incompatible with flux point counts [$(expected)]")
end

function level_matrix_flux_counts(file, planned_nflux::Integer)
    counts = Int[]
    if haskey(file, "completed_flux_step")
        completed_flux_step = Int(read(file, "completed_flux_step"))
        0 <= completed_flux_step <= planned_nflux ||
            error("completed_flux_step=$(completed_flux_step) is outside 0:$(planned_nflux)")
        push!(counts, completed_flux_step)
    end
    push!(counts, planned_nflux)
    return unique(counts)
end

function read_level_matrix(file, key::AbstractString, nflux::Integer; default=missing)
    if !haskey(file, key)
        default === missing && error("Missing required HDF5 dataset $(key)")
        return default
    end
    return orient_level_matrix(read(file, key), nflux, key)
end

function read_level_matrix(file, key::AbstractString, nflux_candidates::AbstractVector{<:Integer}; default=missing)
    if !haskey(file, key)
        default === missing && error("Missing required HDF5 dataset $(key)")
        return default
    end
    return orient_level_matrix(read(file, key), nflux_candidates, key)
end

function read_run(path::AbstractString, dataset_prefix::AbstractString="transfer")
    h5open(path, "r") do file
        fluxes = read_fluxes(file)
        planned_theta_over_pi = haskey(file, "fluxes_over_pi") ?
            Float64.(vec(real.(read(file, "fluxes_over_pi")))) :
            fluxes ./ pi
        planned_nflux = length(planned_theta_over_pi)

        inverse_xi_key = "$(dataset_prefix)_inverse_xi"
        momenta_key = "$(dataset_prefix)_momenta"
        labels_key = "$(dataset_prefix)_flux_labels"
        inverse_xi_raw, data_nflux = read_level_matrix(
            file,
            inverse_xi_key,
            level_matrix_flux_counts(file, planned_nflux),
        )
        data_nflux > 0 || error("No completed transfer spectrum flux points found in $(path)")
        data_nflux <= planned_nflux ||
            error("$(inverse_xi_key) has $(data_nflux) flux points, but only $(planned_nflux) flux points are listed")

        theta_over_pi = planned_theta_over_pi[1:data_nflux]
        inverse_xi = Float64.(real.(inverse_xi_raw))
        momenta = haskey(file, momenta_key) ?
            Float64.(real.(read_level_matrix(file, momenta_key, data_nflux))) :
            fill(NaN, size(inverse_xi))
        labels = haskey(file, labels_key) ?
            String.(read_level_matrix(file, labels_key, data_nflux)) :
            fill("", size(inverse_xi))

        params = Dict{String,Any}()
        for key in ("C", "J1", "J2", "yc_shift", "Delta1", "Delta2", "theta_pi", "maxdim")
            haskey(file, key) && (params[key] = read(file, key))
        end
        if haskey(file, "completed_flux_step")
            params["completed_flux_step"] = Int(read(file, "completed_flux_step"))
            params["nflux"] = planned_nflux
        end
        dataset_prefix == "transfer" || (params["dataset_prefix"] = dataset_prefix)

        return (; path, dataset_prefix, theta_over_pi, inverse_xi, momenta, labels, params)
    end
end

function param_string(params)
    parts = String[]
    if all(haskey(params, key) for key in ("C", "yc_shift"))
        push!(parts, "YC$(params["C"])-$(params["yc_shift"])")
    elseif haskey(params, "C")
        push!(parts, "YC$(params["C"])")
    end
    haskey(params, "J2") && push!(parts, "J2=$(params["J2"])")
    if all(haskey(params, key) for key in ("Delta1", "Delta2"))
        push!(parts, "Delta=$(params["Delta1"]),$(params["Delta2"])")
    end
    haskey(params, "maxdim") && push!(parts, "chi=$(params["maxdim"])")
    haskey(params, "dataset_prefix") && push!(parts, "$(params["dataset_prefix"])")
    if all(haskey(params, key) for key in ("completed_flux_step", "nflux")) &&
       params["completed_flux_step"] < params["nflux"]
        push!(parts, "checkpoint $(params["completed_flux_step"])/$(params["nflux"])")
    end
    return join(parts, ", ")
end

function output_stem(path::AbstractString, dataset_prefix::AbstractString="transfer")
    stem = splitext(basename(path))[1]
    prefix_label = dataset_prefix == "transfer" ? "" : replace(dataset_prefix, r"[^A-Za-z0-9_.-]" => "_") * "_"
    return "transfer_spectrum_" * prefix_label * replace(stem, r"[^A-Za-z0-9_.-]" => "_")
end

function color_for_level(level::Integer, first_level::Integer)
    return LEVEL_COLORS[mod(level - first_level, length(LEVEL_COLORS)) + 1]
end

function keep_point(y, label::AbstractString, label_filter::AbstractString)
    isfinite(y) || return false
    isempty(label_filter) && return true
    return occursin(label_filter, label)
end

function csv_escape(s::AbstractString)
    return "\"" * replace(s, "\"" => "\"\"") * "\""
end

function write_points_csv(path, run, first_level::Integer, last_level::Integer, label_filter::String)
    open(path, "w") do io
        println(io, "theta_over_pi,level,inverse_xi,momentum,flux_label")
        for level in first_level:last_level
            for k in eachindex(run.theta_over_pi)
                y = run.inverse_xi[level, k]
                label = run.labels[level, k]
                keep_point(y, label, label_filter) || continue
                @printf(
                    io,
                    "%.17g,%d,%.17g,%.17g,%s\n",
                    run.theta_over_pi[k],
                    level,
                    y,
                    run.momenta[level, k],
                    csv_escape(label),
                )
            end
        end
    end
    return path
end

function plot_transfer_spectrum(run, output_dir::AbstractString, opts::PlotOptions)
    nlevels_total, nflux = size(run.inverse_xi)
    length(run.theta_over_pi) == nflux || error("theta axis length does not match transfer spectrum")
    opts.first_level <= nlevels_total || error("first_level exceeds available levels")
    last_level = min(nlevels_total, opts.max_levels)
    opts.first_level <= last_level || error("No levels selected")

    fig, ax = subplots(figsize=(4.4, 3.3))
    for level in opts.first_level:last_level
        xvals = Float64[]
        yvals = Float64[]
        for k in eachindex(run.theta_over_pi)
            y = run.inverse_xi[level, k]
            label = run.labels[level, k]
            keep_point(y, label, opts.label_filter) || continue
            push!(xvals, run.theta_over_pi[k])
            push!(yvals, y)
        end
        isempty(xvals) && continue

        color = color_for_level(level, opts.first_level)
        ax.plot(xvals, yvals; color=color, linewidth=1.0, alpha=0.55)
        ax.scatter(
            xvals,
            yvals;
            s=20,
            color=color,
            edgecolors="black",
            linewidths=0.25,
            label=level <= opts.first_level + 7 ? "level $(level)" : nothing,
            zorder=3,
        )
    end

    ax.set_xlabel(raw"twist angle $\theta/\pi$")
    ax.set_ylabel(raw"inverse correlation length $1/\xi$")
    ax.set_title(param_string(run.params); fontsize=9)
    ax.text(
        0.03,
        0.95,
        "(a)";
        transform=ax.transAxes,
        ha="left",
        va="top",
        fontsize=12,
        fontweight="bold",
    )
    ax.grid(true; alpha=0.22)
    ax.set_xlim(minimum(run.theta_over_pi), maximum(run.theta_over_pi))
    ax.set_ylim(bottom=0)
    if last_level - opts.first_level <= 7
        ax.legend(frameon=false, fontsize=7, ncol=2, loc="best")
    end
    fig.tight_layout()

    mkpath(output_dir)
    stem = output_stem(run.path, run.dataset_prefix)
    png = joinpath(output_dir, stem * ".png")
    pdf = joinpath(output_dir, stem * ".pdf")
    csv = joinpath(output_dir, stem * "_points.csv")
    fig.savefig(png; dpi=250, bbox_inches="tight")
    fig.savefig(pdf; bbox_inches="tight")
    close(fig)
    write_points_csv(csv, run, opts.first_level, last_level, opts.label_filter)
    return png, pdf, csv
end

function main(args=ARGS)
    opts = parse_args(args)
    mkpath(opts.output_dir)

    println("Plotting VUMPS transfer spectrum")
    println("input_file: $(opts.input_file)")
    println("output_dir: $(opts.output_dir)")
    isempty(opts.label_filter) || println("label_filter: $(opts.label_filter)")
    opts.dataset_prefix == "transfer" || println("dataset_prefix: $(opts.dataset_prefix)")

    run = read_run(opts.input_file, opts.dataset_prefix)
    if all(haskey(run.params, key) for key in ("completed_flux_step", "nflux")) &&
       run.params["completed_flux_step"] < run.params["nflux"]
        println("checkpoint progress: $(run.params["completed_flux_step"]) / $(run.params["nflux"]) flux step(s)")
    end
    outputs = plot_transfer_spectrum(run, opts.output_dir, opts)
    println("Wrote:")
    for output in outputs
        println(output)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
