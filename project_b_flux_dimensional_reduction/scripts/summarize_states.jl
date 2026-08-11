#!/usr/bin/env julia

using Printf
using TriangularJ1J2ProjectB

length(ARGS) == 1 || error("usage: summarize_states.jl STATE_DIRECTORY")
rows = summarize_state_files(only(ARGS); include_hashes=true)
println(
    "geometry\tbranch\tpreparation\tdirection\tseed\ttheta_over_pi\tchi\t" *
    "mps_period\ttwist_gauge\tconverged\tcontinuation_accepted\tresidual\t" *
    "parent_overlap_per_site\tcontinuity_checked\tcontinuity_passed\t" *
    "energy_density\tmean_entropy\tenergy_term_std\tparent_sha256\tstate_sha256\tpath",
)
for row in sort(rows; by=row -> (row.branch, row.theta_over_pi, row.maxlinkdim))
    @printf(
        "%s\t%s\t%s\t%s\t%d\t%.10g\t%d\t%d\t%s\t%s\t%s\t%.8e\t%.10g\t%s\t%s\t%.14g\t%.10g\t%.8e\t%s\t%s\t%s\n",
        row.geometry,
        row.branch,
        row.preparation,
        row.direction,
        row.random_seed,
        row.theta_over_pi,
        row.maxlinkdim,
        row.mps_period,
        row.twist_gauge,
        row.converged,
        row.continuation_accepted,
        row.residual,
        row.parent_overlap_per_site,
        row.continuity_checked,
        row.continuity_passed,
        row.energy_density,
        row.mean_entropy,
        row.energy_term_std,
        row.parent_state_sha256,
        row.state_sha256,
        row.path,
    )
end
