#!/usr/bin/env julia

using TOML
using TriangularJ1J2ProjectB

3 <= length(ARGS) <= 4 || error(
    "usage: prepare_phase1_chi192_forward_step.jl PARENT_STATE.h5 " *
    "PARENT_SHA256 TARGET_THETA_OVER_PI [CONFIG_DIRECTORY]",
)

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const EXPECTED_PARENT_THETA = 31 / 128
const EXPECTED_TARGET_THETA = 63 / 256
const EXPECTED_MAXDIM = 192
const MAX_OUTER_ITERATIONS = 360

parent_path = abspath(ARGS[1])
expected_sha256 = lowercase(ARGS[2])
occursin(r"^[0-9a-f]{64}$", expected_sha256) || error(
    "PARENT_SHA256 must contain 64 lowercase hexadecimal digits",
)
actual_sha256 = PB.file_sha256(parent_path)
actual_sha256 == expected_sha256 || error(
    "parent SHA-256 mismatch: expected $expected_sha256, got $actual_sha256",
)

target_theta = try
    parse(Float64, ARGS[3])
catch
    error("TARGET_THETA_OVER_PI must be a finite decimal")
end
isfinite(target_theta) || error("TARGET_THETA_OVER_PI must be finite")

parent = PB.read_state_file(parent_path)
parent.schema_version >= 6 || error(
    "the chi-192 forward-step test requires a schema-v6 accepted parent",
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
parent.circumference == 8 && parent.shift == 1 || error(
    "the chi-192 forward-step test requires a YC8-1 parent",
)
parent.mps_period == 2 || error(
    "the chi-192 forward-step test requires the minimal two-site MPS cell",
)
parent.branch == "primary_forward" || error(
    "the chi-192 forward-step test requires the primary-forward branch",
)
parent.preparation == "independent_theta0_alternating" || error(
    "unexpected parent preparation: $(parent.preparation)",
)
parent.direction === :forward || error(
    "the chi-192 forward-step test requires a forward parent",
)
parent.seed_pattern == "alternating" || error(
    "unexpected parent seed pattern: $(parent.seed_pattern)",
)
parent.random_seed == 101 || error(
    "unexpected parent random seed: $(parent.random_seed)",
)
parent.twist_gauge === :uniform || error(
    "the chi-192 forward-step test requires uniform twist gauge",
)
isapprox(parent.theta_over_pi, EXPECTED_PARENT_THETA; atol=1e-12, rtol=0) || error(
    "expected parent theta/pi=$EXPECTED_PARENT_THETA, got $(parent.theta_over_pi)",
)
isapprox(target_theta, EXPECTED_TARGET_THETA; atol=1e-12, rtol=0) || error(
    "this controlled test requires target theta/pi=$EXPECTED_TARGET_THETA, got $target_theta",
)

actual_parent_maxdim = PB.maxlinkdim(parent.psi)
parent.maxlinkdim == actual_parent_maxdim || error(
    "parent maxlinkdim metadata $(parent.maxlinkdim) disagrees with psi " *
    "($actual_parent_maxdim)",
)
actual_parent_maxdim == EXPECTED_MAXDIM || error(
    "the controlled forward step requires chi=$EXPECTED_MAXDIM, got chi=$actual_parent_maxdim",
)
parent.optimizer_requested_maxdim == EXPECTED_MAXDIM || error(
    "parent optimizer requested chi=$(parent.optimizer_requested_maxdim), expected " *
    "$EXPECTED_MAXDIM",
)

step_over_pi = target_theta - parent.theta_over_pi
isapprox(step_over_pi, 1 / 256; atol=1e-12, rtol=0) || error(
    "the controlled forward step must be exactly 1/256 of pi, got $step_over_pi",
)

short_hash = first(expected_sha256, 12)
parent_label = PB.theta_label(parent.theta_over_pi)
target_label = PB.theta_label(target_theta)
experiment_label =
    "forward_step_$(parent_label)_to_$(target_label)_chi$(actual_parent_maxdim)_$short_hash"
config_directory = length(ARGS) == 4 ? abspath(ARGS[4]) : joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_test_configs",
    experiment_label,
)
output_directory = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_tests",
    "yc8_1",
    experiment_label,
    "chi$actual_parent_maxdim",
)
config_path = joinpath(
    config_directory,
    "phase1_forward_step_chi$actual_parent_maxdim.toml",
)
ispath(config_path) && error("refusing to overwrite generated configuration: $config_path")
ispath(output_directory) && error(
    "refusing to reuse forward-step output directory: $output_directory",
)
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
        "maxdim" => actual_parent_maxdim,
        "cutoff" => 1e-10,
        "residual_tol" => 1e-5,
        "max_iterations" => MAX_OUTER_ITERATIONS,
        "max_growth_steps" => 16,
        "solver_tol_scale" => 100.0,
        "solver_tol_floor" => 1e-10,
        "solver_krylov_dimension" => 30,
        "solver_max_iterations" => 100,
        "record_krylov_diagnostics" => true,
        "multisite_update_alg" => "sequential",
        "require_converged" => true,
        "divergence_patience" => 8,
        "divergence_factor" => 4.0,
        # Unlike the completed same-flux expansion, this step does not change
        # the variational space. The conservative plateau rule can therefore
        # stop a genuinely stalled target without truncating an expansion
        # transient.
        "plateau_detection" => true,
        "plateau_warmup_iterations" => 40,
        "plateau_patience" => 32,
        "plateau_min_relative_improvement" => 5e-3,
    ),
    "scan" => Dict{String,Any}(
        "branch" => parent.branch,
        "preparation" => parent.preparation,
        "direction" => string(parent.direction),
        "lineage_policy" => "strict",
        "fluxes_over_pi" => [target_theta],
        "seed_pattern" => parent.seed_pattern,
        "random_seed" => parent.random_seed,
        "adaptive_bisection" => true,
        # Equal to this one requested interval so a failed test is bracketed
        # without silently inserting a smaller theta step.
        "minimum_step_over_pi" => step_over_pi,
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
        "random_seed" => parent.random_seed,
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
    println(io, "# Controlled fixed-chi Phase 1 forward step")
    println(io, "# Immutable accepted chi-192 parent: $parent_path")
    println(io, "# Parent SHA-256: $expected_sha256")
    println(io, "# Theta/pi: $(parent.theta_over_pi) -> $target_theta")
    println(io, "# Bond dimension remains fixed at chi=$actual_parent_maxdim")
    println(io, "# Maximum outer iterations: $MAX_OUTER_ITERATIONS")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println(
    "Generated one fixed-chi chi=$actual_parent_maxdim primary-forward step: " *
    "theta/pi=$(parent.theta_over_pi) -> $target_theta",
)
println("The parent digest was verified and the destination is $output_directory")
println("Run only this generated configuration; do not reuse either earlier chi-192 control.")
