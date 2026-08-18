#!/usr/bin/env julia

using TOML
using TriangularJ1J2ProjectB

2 <= length(ARGS) <= 3 || error(
    "usage: prepare_phase1_chi512_legacy_resume.jl PARENT_STATE.h5 " *
    "PARENT_SHA256 [CONFIG_DIRECTORY]",
)

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const EXPECTED_MAXDIM = 512
const EXPECTED_BRANCH = "primary_forward_chi512_legacy_0p1"
const EXPECTED_PREPARATION = "independent_theta0_alternating_chi512"
const FULL_SCHEDULE = Float64.(0:10) ./ 10
const MAX_OUTER_ITERATIONS = 180

parent_path = abspath(ARGS[1])
expected_sha256 = lowercase(ARGS[2])
occursin(r"^[0-9a-f]{64}$", expected_sha256) || error(
    "PARENT_SHA256 must contain 64 lowercase hexadecimal digits",
)
actual_sha256 = PB.file_sha256(parent_path)
actual_sha256 == expected_sha256 || error(
    "parent SHA-256 mismatch: expected $expected_sha256, got $actual_sha256",
)

parent = PB.read_state_file(parent_path)
parent.schema_version >= 6 || error(
    "the chi-512 legacy-spacing resume requires a schema-v6 accepted parent",
)
parent.converged || error("parent state is not numerically converged")
parent.continuation_accepted || error("parent state was not accepted for continuation")
parent.optimizer_stop_reason == "converged" || error(
    "parent optimizer stop reason is $(parent.optimizer_stop_reason), not converged",
)
parent.optimizer_residual <= parent.optimizer_residual_tolerance || error(
    "parent residual $(parent.optimizer_residual) exceeds its recorded tolerance " *
    "$(parent.optimizer_residual_tolerance)",
)
isapprox(parent.optimizer_residual_tolerance, 1e-5; atol=0, rtol=1e-12) || error(
    "parent residual tolerance $(parent.optimizer_residual_tolerance) is not 1e-5",
)
parent.circumference == 8 && parent.shift == 1 || error(
    "the chi-512 legacy-spacing resume requires a YC8-1 parent",
)
parent.mps_period == 2 || error("the chi-512 campaign requires the minimal two-site cell")
parent.twist_gauge === :uniform || error("the chi-512 campaign requires uniform twist gauge")
parent.branch == EXPECTED_BRANCH || error(
    "unexpected parent branch $(parent.branch); expected $EXPECTED_BRANCH",
)
parent.preparation == EXPECTED_PREPARATION || error(
    "unexpected parent preparation $(parent.preparation); expected $EXPECTED_PREPARATION",
)
parent.direction === :forward || error("the chi-512 campaign requires a forward parent")
parent.seed_pattern == "alternating" || error(
    "unexpected parent seed pattern $(parent.seed_pattern)",
)
parent.random_seed == 101 || error("unexpected parent random seed $(parent.random_seed)")

actual_parent_maxdim = PB.maxlinkdim(parent.psi)
parent.maxlinkdim == actual_parent_maxdim || error(
    "parent maxlinkdim metadata $(parent.maxlinkdim) disagrees with psi ($actual_parent_maxdim)",
)
actual_parent_maxdim == EXPECTED_MAXDIM || error(
    "the controlled resume requires chi=$EXPECTED_MAXDIM, got chi=$actual_parent_maxdim",
)
parent.optimizer_requested_maxdim == EXPECTED_MAXDIM || error(
    "parent optimizer requested chi=$(parent.optimizer_requested_maxdim), expected " *
    "$EXPECTED_MAXDIM",
)

parent_index = findfirst(theta ->
    isapprox(theta, parent.theta_over_pi; atol=1e-12, rtol=0), FULL_SCHEDULE)
parent_index === nothing && error(
    "parent theta/pi=$(parent.theta_over_pi) is not on the 0.1 legacy-spacing grid",
)
parent_index == length(FULL_SCHEDULE) && error(
    "parent is already the final theta/pi=1.0 point; the campaign is complete",
)
expected_history = FULL_SCHEDULE[1:parent_index]
length(parent.flux_history_over_pi) == length(expected_history) || error(
    "parent flux-history length $(length(parent.flux_history_over_pi)) does not match " *
    "the scheduled prefix length $(length(expected_history))",
)
all(isapprox.(parent.flux_history_over_pi, expected_history; atol=1e-12, rtol=0)) || error(
    "parent flux history does not match the 0.1-spaced campaign prefix",
)
remaining_fluxes = FULL_SCHEDULE[(parent_index + 1):end]

short_hash = first(expected_sha256, 12)
parent_label = PB.theta_label(parent.theta_over_pi)
experiment_label = "chi512_legacy_0p1_resume_from_$(parent_label)_$short_hash"
config_directory = length(ARGS) == 3 ? abspath(ARGS[3]) : joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_generated_configs",
    experiment_label,
)
output_directory = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1",
    "yc8_1",
    experiment_label,
    "seed_101",
    "chi512",
)
config_path = joinpath(config_directory, "phase1_chi512_legacy_resume.toml")
ispath(config_path) && error("refusing to overwrite generated configuration: $config_path")
ispath(output_directory) && error("refusing to reuse resume output directory: $output_directory")
mkpath(config_directory)

configuration = Dict{String,Any}(
    "model" => Dict{String,Any}(
        "circumference" => parent.circumference,
        "shift" => parent.shift,
        "mps_period" => parent.mps_period,
        "twist_gauge" => string(parent.twist_gauge),
        "J1" => parent.J1,
        "J2" => parent.J2,
        "Delta1" => parent.Delta1,
        "Delta2" => parent.Delta2,
        "Bz" => parent.Bz,
    ),
    "optimizer" => Dict{String,Any}(
        "maxdim" => EXPECTED_MAXDIM,
        "cutoff" => 1e-10,
        "residual_tol" => 1e-5,
        "max_iterations" => MAX_OUTER_ITERATIONS,
        "max_growth_steps" => 20,
        "solver_tol_scale" => 100.0,
        "solver_tol_floor" => 1e-10,
        "solver_krylov_dimension" => 30,
        "solver_max_iterations" => 100,
        "record_krylov_diagnostics" => true,
        "multisite_update_alg" => "sequential",
        "require_converged" => true,
        "divergence_patience" => 8,
        "divergence_factor" => 4.0,
        "plateau_detection" => true,
        "plateau_warmup_iterations" => 40,
        "plateau_patience" => 32,
        "plateau_min_relative_improvement" => 5e-3,
    ),
    "scan" => Dict{String,Any}(
        "branch" => EXPECTED_BRANCH,
        "preparation" => EXPECTED_PREPARATION,
        "direction" => "forward",
        "lineage_policy" => "strict",
        "fluxes_over_pi" => remaining_fluxes,
        "seed_pattern" => "alternating",
        "random_seed" => 101,
        "adaptive_bisection" => true,
        "minimum_step_over_pi" => 0.1,
        "save_rejected" => true,
        "require_parent_overlap" => true,
        "minimum_parent_overlap_per_site" => 0.99,
        "parent_overlap_tolerance" => 1e-8,
        "parent_overlap_krylov_dimension" => 16,
        "initial_state_file" => parent_path,
        "initial_state_sha256" => expected_sha256,
    ),
    "spectrum" => Dict{String,Any}(
        "physical_sz_sectors" => [0.0, 1.0],
        "neigs" => 4,
        "tolerance" => 1e-8,
        "krylov_dimension" => 16,
        "random_seed" => 101,
    ),
    "runtime" => Dict{String,Any}(
        "output_directory" => output_directory,
        "blas_threads" => 1,
        "strided_threads" => 1,
        "threaded_blocksparse" => true,
        "output_level" => 1,
    ),
)

open(config_path, "w") do io
    println(io, "# SHA-pinned continuation of the fresh chi-512 0.1*pi campaign")
    println(io, "# Accepted parent: $parent_path")
    println(io, "# Parent SHA-256: $expected_sha256")
    println(io, "# Parent theta/pi: $(parent.theta_over_pi)")
    println(io, "# Remaining scheduled fluxes: $(join(remaining_fluxes, ","))")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println(
    "Generated the remaining chi-512 legacy-spacing schedule after accepted " *
    "theta/pi=$(parent.theta_over_pi): $(join(remaining_fluxes, ","))",
)
println("The parent digest was verified and the destination is $output_directory")
