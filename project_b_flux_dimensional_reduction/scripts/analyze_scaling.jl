#!/usr/bin/env julia

using HDF5
using Printf
using Statistics
using TriangularJ1J2ProjectB

length(ARGS) >= 3 || error(
    "usage: analyze_scaling.jl CONFIG.toml PHYSICAL_SZ STATE.h5 [STATE.h5 ...]",
)
settings = load_settings(ARGS[1])
physical_sz = parse(Float64, ARGS[2])
state_paths = ARGS[3:end]
sector = TriangularJ1J2ProjectB.spectrum_sector_name(physical_sz)

rows = NamedTuple[]
for state_path in state_paths
    spectrum_path = TriangularJ1J2ProjectB.spectrum_file_path(
        state_path,
        settings.runtime.output_directory,
    )
    isfile(spectrum_path) || error("missing spectrum file: $spectrum_path")
    state_values = h5open(state_path, "r") do file
        Bool(read(file, "optimizer/converged")) || error("unconverged state: $state_path")
        (;
            chi=Int(read(file, "observables/maxlinkdim")),
            entropy=mean(Float64.(read(file, "observables/von_neumann_entropies"))),
            theta_over_pi=Float64(read(file, "theta_over_pi")),
        )
    end
    xi = h5open(spectrum_path, "r") do file
        values = Float64.(read(file, "sectors/$sector/xi"))
        converged = Int(read(file, "sectors/$sector/krylov_converged"))
        converged >= 1 || error("spectrum has no converged eigenvalues: $spectrum_path")
        finite_values = filter(isfinite, values[1:min(converged, length(values))])
        isempty(finite_values) ? NaN : maximum(finite_values)
    end
    push!(rows, (; state_values..., xi, state_path, spectrum_path))
end

theta_values = unique([row.theta_over_pi for row in rows])
length(theta_values) == 1 || error("all chi-ladder states must have the same flux")
sort!(rows; by=row -> row.chi)
local_rows = local_central_charges(
    [row.chi for row in rows],
    [row.entropy for row in rows],
    [row.xi for row in rows],
)

println("# theta/pi=$(only(theta_values)), physical Sz=$physical_sz")
println("chi\tentropy\txi")
for row in rows
    @printf("%d\t%.12g\t%.12g\n", row.chi, row.entropy, row.xi)
end
println("\nchi_low\tchi_high\tc_eff")
for row in local_rows
    @printf("%d\t%d\t%.12g\n", row.chi_low, row.chi_high, row.c_eff)
end
if length(rows) >= 3
    fit = fit_central_charge([row.entropy for row in rows], [row.xi for row in rows])
    @printf(
        "\nfit: c=%.8g +/- %.3g, R^2=%.6f, n=%d, xi=[%.5g, %.5g]\n",
        fit.central_charge,
        fit.central_charge_standard_error,
        fit.r_squared,
        fit.npoints,
        fit.min_xi,
        fit.max_xi,
    )
end
