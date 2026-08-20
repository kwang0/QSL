#!/usr/bin/env julia

using TOML
using TriangularJ1J2ProjectB

2 <= length(ARGS) <= 3 || error(
    "usage: prepare_phase1_chi512_bridge_from_0p1.jl PARENT_STATE.h5 " *
    "PARENT_SHA256 [CONFIG_DIRECTORY]",
)

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const EXPECTED_MAXDIM = 512
const EXPECTED_BRANCH = "primary_forward_chi512_legacy_0p1"
const EXPECTED_PREPARATION = "independent_theta0_alternating_chi512"
const EXPECTED_PARENT_THETA = 0.1
const EXPECTED_PARENT_HISTORY = [0.0, 0.1]
const EXPECTED_PARENT_SHA256 =
    "f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc"
const EXPECTED_THETA0_SHA256 =
    "95255fbe3a590505902bd0061d7d9d9f14f8ecd7ca3e4eac1aacfc5c7fe72d0b"
const BRIDGE_SCHEDULE = vcat([0.15], Float64.(2:10) ./ 10)
const MINIMUM_STEP_OVER_PI = 0.05
const MAX_OUTER_ITERATIONS = 180

parent_path = abspath(ARGS[1])
expected_sha256 = lowercase(ARGS[2])
occursin(r"^[0-9a-f]{64}$", expected_sha256) || error(
    "PARENT_SHA256 must contain 64 lowercase hexadecimal digits",
)
expected_sha256 == EXPECTED_PARENT_SHA256 || error(
    "this controlled bridge requires accepted theta/pi=0.1 parent SHA-256 " *
    "$EXPECTED_PARENT_SHA256, got $expected_sha256",
)
actual_sha256 = PB.file_sha256(parent_path)
actual_sha256 == expected_sha256 || error(
    "parent SHA-256 mismatch: expected $expected_sha256, got $actual_sha256",
)

parent = PB.read_state_file(parent_path)
parent.schema_version >= 6 || error(
    "the chi-512 bridge requires a schema-v6 accepted parent",
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
    "the chi-512 bridge requires a YC8-1 parent",
)
parent.mps_period == 2 || error("the chi-512 bridge requires the minimal two-site cell")
parent.twist_gauge === :uniform || error("the chi-512 bridge requires uniform twist gauge")
parent.branch == EXPECTED_BRANCH || error(
    "unexpected parent branch $(parent.branch); expected $EXPECTED_BRANCH",
)
parent.preparation == EXPECTED_PREPARATION || error(
    "unexpected parent preparation $(parent.preparation); expected $EXPECTED_PREPARATION",
)
parent.direction === :forward || error("the chi-512 bridge requires a forward parent")
parent.seed_pattern == "alternating" || error(
    "unexpected parent seed pattern $(parent.seed_pattern)",
)
parent.random_seed == 101 || error("unexpected parent random seed $(parent.random_seed)")
isapprox(parent.theta_over_pi, EXPECTED_PARENT_THETA; atol=1e-12, rtol=0) || error(
    "expected parent theta/pi=$EXPECTED_PARENT_THETA, got $(parent.theta_over_pi)",
)
length(parent.flux_history_over_pi) == length(EXPECTED_PARENT_HISTORY) &&
    all(isapprox.(
        parent.flux_history_over_pi,
        EXPECTED_PARENT_HISTORY;
        atol=1e-12,
        rtol=0,
    )) || error(
        "parent flux history must be the accepted [0.0, 0.1] campaign prefix",
    )
parent.parent_state_sha256 == EXPECTED_THETA0_SHA256 || error(
    "theta/pi=0.1 parent does not descend from the expected accepted theta-zero state",
)

for (field, expected) in (
    (:J1, 1.0),
    (:J2, 0.12),
    (:Delta1, 1.0),
    (:Delta2, 1.0),
    (:Bz, 0.0),
)
    actual = getproperty(parent, field)
    isapprox(actual, expected; atol=1e-12, rtol=1e-12) || error(
        "parent $field=$actual does not match the controlled bridge value $expected",
    )
end

actual_parent_maxdim = PB.maxlinkdim(parent.psi)
parent.maxlinkdim == actual_parent_maxdim || error(
    "parent maxlinkdim metadata $(parent.maxlinkdim) disagrees with psi ($actual_parent_maxdim)",
)
actual_parent_maxdim == EXPECTED_MAXDIM || error(
    "the controlled bridge requires chi=$EXPECTED_MAXDIM, got chi=$actual_parent_maxdim",
)
parent.optimizer_requested_maxdim == EXPECTED_MAXDIM || error(
    "parent optimizer requested chi=$(parent.optimizer_requested_maxdim), expected " *
    "$EXPECTED_MAXDIM",
)

short_hash = first(expected_sha256, 12)
parent_label = PB.theta_label(EXPECTED_PARENT_THETA)
midpoint_label = PB.theta_label(first(BRIDGE_SCHEDULE))
target_label = PB.theta_label(last(BRIDGE_SCHEDULE))
experiment_label =
    "chi512_adaptive_from_$(parent_label)_via_$(midpoint_label)_to_$(target_label)_$short_hash"
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
config_path = joinpath(config_directory, "phase1_chi512_adaptive_forward.toml")
ispath(config_path) && error("refusing to overwrite generated configuration: $config_path")
ispath(output_directory) && error("refusing to reuse bridge output directory: $output_directory")
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
        "fluxes_over_pi" => BRIDGE_SCHEDULE,
        "seed_pattern" => "alternating",
        "random_seed" => 101,
        "adaptive_bisection" => true,
        # The approved floor is 0.05*pi. Later failed 0.1*pi intervals may be
        # bisected once in the same allocation, but nothing smaller is inserted.
        "minimum_step_over_pi" => MINIMUM_STEP_OVER_PI,
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
    println(io, "# Adaptive chi-512 continuation after the rejected direct 0.1 -> 0.2 step")
    println(io, "# Immutable accepted theta/pi=0.1 parent: $parent_path")
    println(io, "# Parent SHA-256: $expected_sha256")
    println(io, "# Adaptive remaining schedule: $(join(BRIDGE_SCHEDULE, ","))")
    println(io, "# The rejected direct theta/pi=0.2 artifact is not an optimizer input")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println(
    "Generated the adaptive chi-512 continuation from theta/pi=$EXPECTED_PARENT_THETA " *
    "through $(join(BRIDGE_SCHEDULE, ","))",
)
println("The exact accepted parent digest and theta-zero ancestry were verified.")
println("The rejected direct theta/pi=0.2 artifact is not used.")
println("The new immutable destination is $output_directory")
