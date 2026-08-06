#!/usr/bin/env julia

using Printf
using TriangularJ1J2ProjectB

length(ARGS) == 1 || error("usage: summarize_states.jl STATE_DIRECTORY")
rows = summarize_state_files(only(ARGS))
println("theta_over_pi\tchi\tmps_period\ttwist_gauge\tconverged\tresidual\tenergy_density\tmean_entropy\tenergy_term_std\tpath")
for row in sort(rows; by=row -> (row.theta_over_pi, row.maxlinkdim))
    @printf(
        "%.10g\t%d\t%d\t%s\t%s\t%.8e\t%.14g\t%.10g\t%.8e\t%s\n",
        row.theta_over_pi,
        row.maxlinkdim,
        row.mps_period,
        row.twist_gauge,
        row.converged,
        row.residual,
        row.energy_density,
        row.mean_entropy,
        row.energy_term_std,
        row.path,
    )
end
