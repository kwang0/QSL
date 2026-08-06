#!/usr/bin/env julia

const MPL_CACHE = normpath(joinpath(@__DIR__, "..", "tmp", "matplotlib"))
mkpath(MPL_CACHE)
ENV["MPLCONFIGDIR"] = MPL_CACHE
ENV["MPLBACKEND"] = "Agg"

using HDF5
using PyPlot
using Statistics
using TriangularJ1J2ProjectB

length(ARGS) in (2, 3) || error(
    "usage: plot_flux_summary.jl CONFIG.toml PHYSICAL_SZ [OUTPUT.png]",
)
settings = load_settings(ARGS[1])
physical_sz = parse(Float64, ARGS[2])
rows = sort(
    summarize_state_files(joinpath(settings.runtime.output_directory, "states"));
    by=row -> row.theta_over_pi,
)
isempty(rows) && error("no state files found")
sector = TriangularJ1J2ProjectB.spectrum_sector_name(physical_sz)

figure, axes = subplots(2, 1; figsize=(7.2, 7.2), sharex=true, constrained_layout=true)
accepted = filter(row -> row.converged, rows)
rejected = filter(row -> !row.converged, rows)
axes[1].scatter(
    [row.theta_over_pi for row in accepted],
    [row.mean_entropy for row in accepted];
    color="#2166ac",
    label="accepted",
    zorder=3,
)
!isempty(rejected) && axes[1].scatter(
    [row.theta_over_pi for row in rejected],
    [row.mean_entropy for row in rejected];
    color="#b2182b",
    marker="x",
    label="rejected VUMPS point",
    zorder=4,
)
axes[1].set_ylabel("mean cut entropy S")
axes[1].legend(frameon=false)

plotted = 0
for row in accepted
    spectrum_path = TriangularJ1J2ProjectB.spectrum_file_path(
        row.path,
        settings.runtime.output_directory,
    )
    isfile(spectrum_path) || continue
    inverse_xi = h5open(spectrum_path, "r") do file
        values = Float64.(read(file, "sectors/$sector/inverse_xi"))
        converged = Int(read(file, "sectors/$sector/krylov_converged"))
        if converged < length(values)
            @warn "Plotting only converged transfer eigenvalues" spectrum_path converged requested=length(values)
        end
        values[1:min(converged, length(values))]
    end
    isempty(inverse_xi) && continue
    axes[2].scatter(
        fill(row.theta_over_pi, length(inverse_xi)),
        inverse_xi;
        s=16,
        color="#4d4d4d",
        alpha=0.75,
    )
    plotted += 1
end
plotted > 0 || error("no matching spectrum files found; run scripts/run_spectrum.jl first")

crossing = predicted_crossing_over_pi(settings.model.geometry)
for axis in axes
    axis.axvline(crossing; color="#d95f02", linestyle="--", linewidth=1.4)
    axis.grid(alpha=0.18)
end
axes[2].set_xlabel(L"spin flux $\theta/\pi$")
axes[2].set_ylabel(L"$1/\xi_{S^z}$")
axes[2].set_ylim(bottom=0)
figure.suptitle(
    "$(settings.model.geometry), J2/J1=$(settings.model.J2), physical Sz=$physical_sz\n" *
    "scatter only: eigenvalue ranks are not branch identities",
)

output_path = length(ARGS) == 3 ? abspath(ARGS[3]) : joinpath(
    settings.runtime.output_directory,
    "plots",
    "flux_summary_$(lowercase(string(settings.model.geometry)))_sz_$(replace(string(physical_sz), "." => "p")).png",
)
mkpath(dirname(output_path))
savefig(output_path; dpi=180)
close(figure)
println(output_path)
