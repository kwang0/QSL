using HDF5
using PyPlot

function discover_overlap_files(
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

    isempty(file_map) && error("No matching overlap files were found in $directory for C=$(C), L=$(L).")
    return file_map
end

function read_overlap(input_file::AbstractString)
    h5open(input_file, "r") do file
        haskey(file, "overlap") || error("The file $input_file does not contain an `overlap` dataset.")
        return abs(read(file, "overlap"))
    end
end

function collect_overlap_series(
    C::Integer,
    L::Integer;
    directory::AbstractString = "processed_data",
    delta1::Real = 1.0,
    delta2::Real = 1.0,
    chi::Integer = 512,
    J2_min = nothing,
    J2_max = nothing,
)
    file_map = discover_overlap_files(
        C,
        L;
        directory = directory,
        delta1 = delta1,
        delta2 = delta2,
        chi = chi,
    )

    J2_values = sort(collect(keys(file_map)))
    if !isnothing(J2_min)
        J2_values = filter(J2 -> J2 >= J2_min, J2_values)
    end
    if !isnothing(J2_max)
        J2_values = filter(J2 -> J2 <= J2_max, J2_values)
    end
    isempty(J2_values) && error("No J2 values remain after applying the requested range filter.")

    overlaps = [read_overlap(file_map[J2]) for J2 in J2_values]
    per_site_overlaps = overlaps .^ (1 / (C * L))

    return (
        C = C,
        L = L,
        J2 = J2_values,
        overlap = overlaps,
        overlap_per_site = per_site_overlaps,
        file_map = file_map,
    )
end

function default_overlap_title()
    return "Overlap of DMRG ground states with U(1) MF ansatz"
end

function plot_overlap_panel!(
    ax,
    series_collection;
    field::Symbol,
    title::AbstractString = default_overlap_title(),
    ylabel::AbstractString,
)
    for series in series_collection
        values = getfield(series, field)
        ax.plot(series.J2, values; label = "6x$(series.L)")
    end

    ax.set_title(title)
    ax.set_xlabel(raw"$J_2/J_1$")
    ax.set_ylabel(ylabel)
    ax.legend()
    return nothing
end

function plot_u1_overlaps(
    ;
    C::Integer = 6,
    lengths::AbstractVector{<:Integer} = [6, 18, 36],
    directory::AbstractString = "processed_data",
    delta1::Real = 1.0,
    delta2::Real = 1.0,
    chi::Integer = 512,
    J2_min = nothing,
    J2_max = nothing,
    output_png = nothing,
    show_plot::Bool = true,
)
    series_collection = [
        collect_overlap_series(
            C,
            L;
            directory = directory,
            delta1 = delta1,
            delta2 = delta2,
            chi = chi,
            J2_min = J2_min,
            J2_max = J2_max,
        ) for L in lengths
    ]

    fig, axes = subplots(1, 2, figsize = (12.5, 4.3), constrained_layout = true)

    plot_overlap_panel!(
        axes[1],
        series_collection;
        field = :overlap,
        ylabel = raw"$|\langle \psi_0 | \psi_{U(1)} \rangle|$",
    )

    plot_overlap_panel!(
        axes[2],
        series_collection;
        field = :overlap_per_site,
        ylabel = raw"$|\langle \psi_0 | \psi_{U(1)} \rangle|^{1/N}$",
    )

    if !isnothing(output_png)
        savefig(output_png, dpi = 180, bbox_inches = "tight")
    end
    if show_plot
        display(fig)
    end

    return (fig = fig, axes = axes, series = series_collection)
end

