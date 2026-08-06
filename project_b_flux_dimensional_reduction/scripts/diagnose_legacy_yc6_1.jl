#!/usr/bin/env julia

const MPL_CACHE = normpath(joinpath(@__DIR__, "..", "tmp", "matplotlib"))
mkpath(MPL_CACHE)
ENV["MPLCONFIGDIR"] = MPL_CACHE
ENV["MPLBACKEND"] = "Agg"

using HDF5
using Printf
using PyPlot
using TriangularJ1J2ProjectB

length(ARGS) == 5 || error(
    "usage: diagnose_legacy_yc6_1.jl CHI64.h5 CHI64.log CHI512.h5 CHI512.log OUTPUT_DIRECTORY",
)

function aligned_log_rows(diagnostic, log_rows)
    result = NamedTuple[]
    for theta in diagnostic.theta
        index = findfirst(row -> isapprox(row.theta_over_pi, theta; atol=1e-12, rtol=0), log_rows)
        if index === nothing
            push!(result, (; theta_over_pi=theta, last_residual=NaN, minimum_residual=NaN, tolerance=NaN))
        else
            row = log_rows[index]
            push!(result, row)
        end
    end
    return result
end

chi64_path, chi64_log_path, chi512_path, chi512_log_path, output_directory = ARGS
mkpath(output_directory)
assets_directory = joinpath(output_directory, "assets")
data_directory = joinpath(output_directory, "data")
mkpath(assets_directory)
mkpath(data_directory)

log64 = parse_vumps_log(chi64_log_path)
log512 = parse_vumps_log(chi512_log_path)
d64 = diagnose_legacy_file(chi64_path; log_rows=log64)
d512 = diagnose_legacy_file(chi512_path; log_rows=log512)
aligned64 = aligned_log_rows(d64, log64)
aligned512 = aligned_log_rows(d512, log512)

csv_path = joinpath(data_directory, "legacy_yc6_1_flux_diagnostics.csv")
open(csv_path, "w") do io
    println(io, "chi,theta_over_pi,last_residual,minimum_residual,tolerance,mean_entropy,energy_term_std,leading_inverse_xi")
    for (diagnostic, aligned) in ((d64, aligned64), (d512, aligned512))
        for index in eachindex(diagnostic.theta)
            row = aligned[index]
            println(
                io,
                join(
                    (
                        diagnostic.maxdim,
                        diagnostic.theta[index],
                        row.last_residual,
                        row.minimum_residual,
                        row.tolerance,
                        diagnostic.mean_entropy[index],
                        diagnostic.energy_term_std[index],
                        diagnostic.leading_inverse_xi[index],
                    ),
                    ",",
                ),
            )
        end
    end
end

figure, axes = subplots(2, 2; figsize=(10.5, 7.5), sharex=true, constrained_layout=true)
colors = Dict(64 => "#2166ac", 512 => "#b2182b")
for (diagnostic, path) in ((d64, chi64_path), (d512, chi512_path))
    inverse_xi = h5open(path, "r") do file
        Float64.(read(file, "transfer_inverse_xi"))
    end
    for column in Base.axes(inverse_xi, 2)
        values = inverse_xi[:, column]
        axes[1, 1].scatter(
            fill(diagnostic.theta[column], length(values)),
            values;
            s=11,
            alpha=0.55,
            color=colors[diagnostic.maxdim],
        )
    end
    axes[1, 2].plot(
        diagnostic.theta,
        diagnostic.residual ./ diagnostic.residual_tolerance;
        marker="o",
        label="chi=$(diagnostic.maxdim)",
        color=colors[diagnostic.maxdim],
    )
    axes[2, 1].plot(
        diagnostic.theta,
        diagnostic.mean_entropy;
        marker="o",
        color=colors[diagnostic.maxdim],
    )
    axes[2, 2].plot(
        diagnostic.theta,
        diagnostic.energy_term_std;
        marker="o",
        color=colors[diagnostic.maxdim],
    )
end

axes[1, 1].set_title("neutral transfer spectrum (scatter only)")
axes[1, 1].set_ylabel(L"$1/\xi$")
axes[1, 1].set_ylim(bottom=0)
axes[1, 2].set_title("VUMPS residual / requested tolerance")
axes[1, 2].set_ylabel("residual ratio")
axes[1, 2].set_yscale("log")
axes[1, 2].axhline(1; color="black", linewidth=1, linestyle=":")
axes[1, 2].legend(frameon=false)
axes[2, 1].set_title("mean cut entropy")
axes[2, 1].set_ylabel("S")
axes[2, 2].set_title("within-cell energy nonuniformity")
axes[2, 2].set_ylabel("std(energy terms)")
axes[2, 2].set_yscale("log")
for axis in axes
    axis.set_xlabel(L"spin flux $\theta/\pi$")
    axis.axvline(1.0; color="#f4a582", linestyle="--", linewidth=1.3)
    axis.grid(alpha=0.17)
end
figure.suptitle("Why the apparent YC6-1 branch bends before the expected theta/pi=1 crossing")
plot_path = joinpath(assets_directory, "legacy_yc6_1_diagnosis.png")
savefig(plot_path; dpi=180)
close(figure)

function log_row_at(log_rows, theta)
    index = findfirst(row -> isapprox(row.theta_over_pi, theta; atol=1e-12, rtol=0), log_rows)
    index === nothing && error("missing theta/pi=$theta in log")
    return log_rows[index]
end

row512_04 = log_row_at(log512, 0.4)
interval512 = first(d512.intervals)
interval64 = first(d64.intervals)
report_path = joinpath(output_directory, "YC6_1_DIAGNOSIS.md")
open(report_path, "w") do io
    println(io, "# Diagnosis of the legacy YC6-1 transfer-spectrum scan")
    println(io)
    println(io, "## Verdict")
    println(io)
    println(
        io,
        "The apparent low-lying feature near `theta/pi = 0.4` is not evidence for the Hu et al. " *
        "Dirac crossing. It coincides with a failed VUMPS solve and a jump between variational " *
        "basins. For YC6-1 the expected positive crossing is `theta/pi = 1`, which the chi=512 " *
        "checkpoint never reached.",
    )
    println(io)
    println(io, "![Legacy YC6-1 diagnostic](assets/legacy_yc6_1_diagnosis.png)")
    println(io)
    println(io, "## Direct evidence")
    println(io)
    println(io, "| check | chi=64 | chi=512 |")
    println(io, "|---|---:|---:|")
    println(io, "| completed flux points | $(d64.completed_points) | $(d512.completed_points) |")
    println(io, "| largest completed `theta/pi` | $(d64.completed_theta_maximum) | $(d512.completed_theta_maximum) |")
    println(io, "| requested residual tolerance | $(d64.residual_tolerance) | $(d512.residual_tolerance) |")
    println(io, "| largest final residual/tolerance | $(maximum(d64.residual ./ d64.residual_tolerance)) | $(maximum(d512.residual ./ d512.residual_tolerance)) |")
    println(io, "| physical `S^z=1` transfer sector present | $(d64.contains_physical_sz1) | $(d512.contains_physical_sz1) |")
    println(io, "| MPS state retained in processed HDF5 | $(d64.contains_state) | $(d512.contains_state) |")
    println(io)
    @printf(
        io,
        "At chi=512 and `theta/pi=0.4`, the residual reached only `%.6e` at iteration `%d` of `%d` and ended at `%.6e`, versus a target of `%.1e`. The final residual is therefore `%.1f` times the target.\n\n",
        row512_04.minimum_residual,
        argmin(row512_04.residuals),
        length(row512_04.residuals),
        row512_04.last_residual,
        row512_04.tolerance,
        row512_04.last_residual / row512_04.tolerance,
    )
    @printf(
        io,
        "Across `theta/pi=%.1f -> %.1f`, the mean entropy jumps by `%.6f`, while the standard deviation of unit-cell energy terms collapses by a factor of `%.2f`. This is the state reorganization that the old rank-connected spectrum renders as a branch feature.\n\n",
        interval512.left_theta_over_pi,
        interval512.right_theta_over_pi,
        interval512.entropy_jump,
        inv(interval512.energy_term_std_ratio),
    )
    @printf(
        io,
        "The corresponding anomaly is not fixed in flux: at chi=64 the highest-ranked jump is `theta/pi=%.1f -> %.1f`, with residual/tolerance `%.1f`. Its movement with chi is further evidence for a finite-chi optimization spinodal rather than a symmetry-predicted cone.\n\n",
        interval64.left_theta_over_pi,
        interval64.right_theta_over_pi,
        interval64.residual_ratio,
    )
    println(io, "## Why the old plot cannot reproduce Fig. 3")
    println(io)
    println(io, "1. Hu et al. plot the physical `S^z=1` transfer spectrum; these files contain only labels in the neutral `Sz=0` sector.")
    println(io, "2. The chi=512 scan stops at `0.7 pi`, below the predicted YC6-1 crossing at `pi`.")
    println(io, "3. The processed checkpoint stripped `psi`, so the missing sector cannot be reconstructed after the fact.")
    println(io, "4. Sorting eigenvalues independently at each flux and connecting equal ranks does not track eigenvectors; crossings and reordered levels become artificial lines.")
    println(io, "5. No completed point in either legacy run satisfies the stated VUMPS residual tolerance.")
    println(io)
    println(io, "The machine-readable values used here are in [`data/legacy_yc6_1_flux_diagnostics.csv`](data/legacy_yc6_1_flux_diagnostics.csv).")
end

println(report_path)
println(plot_path)
println(csv_path)
