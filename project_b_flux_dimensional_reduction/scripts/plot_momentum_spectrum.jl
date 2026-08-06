#!/usr/bin/env julia

const MPL_CACHE = normpath(joinpath(@__DIR__, "..", "tmp", "matplotlib"))
mkpath(MPL_CACHE)
ENV["MPLCONFIGDIR"] = MPL_CACHE
ENV["MPLBACKEND"] = "Agg"

using HDF5
using PyPlot
using TriangularJ1J2ProjectB

length(ARGS) in (2, 3) || error(
    "usage: plot_momentum_spectrum.jl CONFIG.toml PHYSICAL_SZ [OUTPUT.png]",
)
settings = load_settings(ARGS[1])
physical_sz = parse(Float64, ARGS[2])
sector = TriangularJ1J2ProjectB.spectrum_sector_name(physical_sz)
rows = sort(
    filter(
        row -> row.converged,
        summarize_state_files(joinpath(settings.runtime.output_directory, "states")),
    );
    by=row -> row.theta_over_pi,
)
isempty(rows) && error("no converged state files found")

points = NamedTuple[]
for row in rows
    spectrum_path = TriangularJ1J2ProjectB.spectrum_file_path(
        row.path,
        settings.runtime.output_directory,
    )
    isfile(spectrum_path) || continue
    append!(
        points,
        h5open(spectrum_path, "r") do file
            group_path = "sectors/$sector"
            haskey(file, "$group_path/momentum_resolved") || error(
                "legacy spectrum has no momentum labels: $spectrum_path",
            )
            inverse_xi = Float64.(read(file, "$group_path/inverse_xi"))
            k1 = Float64.(read(file, "$group_path/k1"))
            k1_secondary = Float64.(read(file, "$group_path/k1_secondary"))
            k2 = Float64.(read(file, "$group_path/k2"))
            resolved = Bool.(read(file, "$group_path/momentum_resolved"))
            converged = min(Int(read(file, "$group_path/krylov_converged")), length(inverse_xi))
            [
                (;
                    theta_over_pi=row.theta_over_pi,
                    inverse_xi=inverse_xi[index],
                    k1=k1[index],
                    k1_secondary=k1_secondary[index],
                    k2=k2[index],
                ) for index in 1:converged if resolved[index]
            ]
        end,
    )
end
isempty(points) && error(
    "no momentum-resolved modes passed the stored validity checks; inspect the spectrum HDF5 diagnostics",
)

figure, axes = subplots(1, 2; figsize=(10.0, 4.4), sharey=true, constrained_layout=true)
theta_values = [point.theta_over_pi for point in points]
normalizer = matplotlib.colors.Normalize(vmin=minimum(theta_values), vmax=maximum(theta_values))
colormap = get_cmap("viridis")

for point in points
    color = colormap(normalizer(point.theta_over_pi))
    axes[1].scatter(point.k1 / pi, point.inverse_xi; s=20, color=color, alpha=0.8)
    if isfinite(point.k1_secondary)
        axes[1].scatter(
            point.k1_secondary / pi,
            point.inverse_xi;
            s=20,
            facecolors="none",
            edgecolors=[color],
            alpha=0.8,
        )
    end
    axes[2].scatter(point.k2 / pi, point.inverse_xi; s=20, color=color, alpha=0.8)
end

axes[1].set_xlabel(L"$k_1/\pi$")
axes[2].set_xlabel(L"$k_2/\pi$")
axes[1].set_ylabel(L"$1/\xi_{S^z}$")
for axis in axes
    axis.set_xlim(-1, 1)
    axis.set_ylim(bottom=0)
    axis.grid(alpha=0.18)
end
scalar_map = matplotlib.cm.ScalarMappable(norm=normalizer, cmap=colormap)
scalar_map.set_array([])
figure.colorbar(scalar_map, ax=axes, label=L"spin flux $\theta/\pi$")
figure.suptitle(
    "$(settings.model.geometry), J2/J1=$(settings.model.J2), physical Sz=$physical_sz\n" *
    "filled: primary branch; open: YC-1 pi-ambiguous branch",
)

output_path = length(ARGS) == 3 ? abspath(ARGS[3]) : joinpath(
    settings.runtime.output_directory,
    "plots",
    "momentum_spectrum_$(lowercase(string(settings.model.geometry)))_sz_$(replace(string(physical_sz), "." => "p")).png",
)
mkpath(dirname(output_path))
savefig(output_path; dpi=180)
close(figure)
println(output_path)
