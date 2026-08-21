#!/usr/bin/env julia

using HDF5
using SHA
using TOML

3 <= length(ARGS) <= 4 || error(
    "usage: prepare_phase1_chi512_parallel_control.jl PARENT_STATE.h5 " *
    "PARENT_SHA256 SEQUENTIAL_SCAN_OUTCOME.toml [CONFIG_DIRECTORY]",
)

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const EXPECTED_BRANCH = "primary_forward_chi512_legacy_0p1"
const EXPECTED_PREPARATION = "independent_theta0_alternating_chi512"
const EXPECTED_PARENT_THETA = 0.1
const EXPECTED_TARGET_THETA = 0.15
const EXPECTED_MAXDIM = 512
const EXPECTED_PARENT_SHA256 =
    "f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc"
const EXPECTED_THETA0_SHA256 =
    "95255fbe3a590505902bd0061d7d9d9f14f8ecd7ca3e4eac1aacfc5c7fe72d0b"
const EXPECTED_SOURCE_JOB_ID = "57245573"
const EXPECTED_SOURCE_CONFIG_SHA256 =
    "1a272abe6879c69827d1f14547a0b6d4780083945e414ad3f1cb9ee1a050749f"
const EXPECTED_SOURCE_CONFIG_RELATIVE = joinpath(
    "output",
    "phase1_generated_configs",
    "chi512_auto_refine_interval_from_p0p10000000_p0p15000000_to_p1p00000000_f71fc084883e",
    "phase1_chi512_automatic.toml",
)
const EXPECTED_SOURCE_OUTCOME_SHA256 =
    "001eadee6f43e73fa9228c4221c8ac81edc821db58a391625037806b16e0b2cf"
const EXPECTED_SEQUENTIAL_CANDIDATE_SHA256 =
    "b5ef48caaf7a10eb00e4fd003e8fd1b5a57add77a8111b270a358a7c8f049953"
const MAX_OUTER_ITERATIONS = 180

function require_approx(actual, expected, label::AbstractString)
    isapprox(Float64(actual), Float64(expected); atol=1e-12, rtol=0) ||
        error("$label=$actual, expected $expected")
end

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function read_state_metadata(path::AbstractString)
    return h5open(path, "r") do file
        return (
            schema_version=Int(read(file, "schema_version")),
            artifact_kind=String(read(file, "artifact_kind")),
            converged=Bool(read(file, "optimizer/converged")),
            continuation_accepted=Bool(read(file, "continuation_accepted")),
            optimizer_stop_reason=String(read(file, "optimizer/stop_reason")),
            optimizer_residual=Float64(read(file, "optimizer/residual")),
            optimizer_residual_tolerance=Float64(read(file, "optimizer/residual_tolerance")),
            optimizer_requested_maxdim=Int(read(file, "optimizer/requested_maxdim")),
            circumference=Int(read(file, "geometry/circumference")),
            shift=Int(read(file, "geometry/shift")),
            mps_period=Int(read(file, "geometry/mps_period")),
            twist_gauge=String(read(file, "model/twist_gauge")),
            branch=String(read(file, "branch")),
            preparation=String(read(file, "preparation")),
            direction=String(read(file, "direction")),
            seed_pattern=String(read(file, "continuation/seed_pattern")),
            random_seed=Int(read(file, "random_seed")),
            theta_over_pi=Float64(read(file, "theta_over_pi")),
            flux_history_over_pi=Float64.(vec(read(
                file,
                "continuation/flux_history_over_pi",
            ))),
            parent_state_sha256=String(read(file, "continuation/parent_state_sha256")),
            maxlinkdim=Int(read(file, "observables/maxlinkdim")),
            J1=Float64(read(file, "model/J1")),
            J2=Float64(read(file, "model/J2")),
            Delta1=Float64(read(file, "model/Delta1")),
            Delta2=Float64(read(file, "model/Delta2")),
            Bz=Float64(read(file, "model/Bz")),
        )
    end
end

function recorded_inner_solves_converged(path::AbstractString)
    return h5open(path, "r") do file
        group_path = "optimizer/krylov_solves"
        haskey(file, group_path) || return false
        group = file[group_path]
        count = Int(read(group, "count"))
        count > 0 || return false
        haskey(group, "converged_count") || return false
        convergence = Int.(vec(read(group, "converged_count")))
        return length(convergence) == count && all(>(0), convergence)
    end
end

function resolve_recorded_artifact(recorded_path::AbstractString, outcome_path::AbstractString)
    isfile(recorded_path) && return abspath(recorded_path)
    synced_path = joinpath(dirname(outcome_path), "states", basename(recorded_path))
    isfile(synced_path) || error(
        "recorded artifact is absent at both its Perlmutter and synced paths: " *
        "$recorded_path",
    )
    return abspath(synced_path)
end

function resolve_source_configuration(recorded_path::AbstractString)
    normalized_recorded = normpath(recorded_path)
    expected_suffix = normpath(EXPECTED_SOURCE_CONFIG_RELATIVE)
    endswith(normalized_recorded, expected_suffix) || error(
        "sequential outcome names an unexpected source configuration: $recorded_path",
    )
    isfile(normalized_recorded) && return abspath(normalized_recorded)
    synced_path = joinpath(PROJECT_ROOT, EXPECTED_SOURCE_CONFIG_RELATIVE)
    isfile(synced_path) || error(
        "source configuration is absent at both its Perlmutter and synced paths",
    )
    return abspath(synced_path)
end

parent_path = abspath(ARGS[1])
expected_parent_sha256 = lowercase(ARGS[2])
outcome_path = abspath(ARGS[3])
isfile(parent_path) || error("accepted parent does not exist: $parent_path")
isfile(outcome_path) || error("sequential scan outcome does not exist: $outcome_path")
expected_parent_sha256 == EXPECTED_PARENT_SHA256 || error(
    "this control requires accepted theta/pi=0.1 SHA-256 $EXPECTED_PARENT_SHA256",
)
file_sha256(parent_path) == expected_parent_sha256 || error(
    "accepted-parent SHA-256 mismatch",
)
file_sha256(outcome_path) == EXPECTED_SOURCE_OUTCOME_SHA256 || error(
    "the sequential scan outcome does not match job $EXPECTED_SOURCE_JOB_ID",
)

parent = read_state_metadata(parent_path)
parent.schema_version >= 6 || error("the parallel control requires a schema-v6 parent")
parent.artifact_kind == "project_b_vumps_state" || error("parent is not a Project B state")
parent.converged || error("parent is not numerically converged")
parent.continuation_accepted || error("parent is not accepted for continuation")
parent.optimizer_stop_reason == "converged" || error("parent optimizer did not converge")
parent.optimizer_residual <= parent.optimizer_residual_tolerance || error(
    "parent residual exceeds its recorded tolerance",
)
require_approx(parent.optimizer_residual_tolerance, 1e-5, "parent residual tolerance")
parent.circumference == 8 && parent.shift == 1 || error("parent is not YC8-1")
parent.mps_period == 2 || error("parent does not use the minimal period-2 cell")
parent.twist_gauge == "uniform" || error("parent does not use uniform twist gauge")
parent.branch == EXPECTED_BRANCH || error("parent has the wrong branch")
parent.preparation == EXPECTED_PREPARATION || error("parent has the wrong preparation")
parent.direction == "forward" || error("parent is not a forward state")
parent.seed_pattern == "alternating" || error("parent has the wrong seed pattern")
parent.random_seed == 101 || error("parent has the wrong random seed")
require_approx(parent.theta_over_pi, EXPECTED_PARENT_THETA, "parent theta/pi")
parent.flux_history_over_pi == [0.0, 0.1] || error(
    "parent flux history is not the accepted [0.0, 0.1] prefix",
)
parent.parent_state_sha256 == EXPECTED_THETA0_SHA256 || error(
    "parent does not descend from the pinned accepted theta-zero state",
)
parent.maxlinkdim == EXPECTED_MAXDIM || error("parent is not chi 512")
parent.optimizer_requested_maxdim == EXPECTED_MAXDIM || error(
    "parent did not request chi 512",
)
recorded_inner_solves_converged(parent_path) || error(
    "accepted parent has a recorded unconverged inner solve",
)

for (field, expected) in (
    (:J1, 1.0),
    (:J2, 0.12),
    (:Delta1, 1.0),
    (:Delta2, 1.0),
    (:Bz, 0.0),
)
    require_approx(getproperty(parent, field), expected, "parent $field")
end

outcome = TOML.parsefile(outcome_path)
get(outcome, "artifact_kind", "") == "project_b_flux_scan_outcome" || error(
    "source artifact is not a flux-scan outcome",
)
get(outcome, "status", "") == "numerical_continuation_loss_bracketed" || error(
    "sequential control did not end in a bracketed numerical failure",
)
get(outcome, "classification", "") == "numerical_divergence_not_physical_endpoint" ||
    error("sequential control was not classified as residual divergence")
get(outcome, "optimizer_stop_reason", "") == "diverging_residual" || error(
    "sequential control did not stop for a diverging residual",
)
String(outcome["accepted_state_sha256"]) == expected_parent_sha256 || error(
    "sequential outcome names a different accepted parent",
)
String(outcome["rejected_state_sha256"]) == EXPECTED_SEQUENTIAL_CANDIDATE_SHA256 ||
    error("sequential outcome names an unexpected rejected candidate")
require_approx(outcome["last_accepted_theta_over_pi"], EXPECTED_PARENT_THETA, "last accepted theta/pi")
require_approx(outcome["rejected_theta_over_pi"], EXPECTED_TARGET_THETA, "rejected theta/pi")
require_approx(outcome["bracket_width_over_pi"], 0.05, "sequential bracket width")
require_approx(outcome["minimum_step_over_pi"], 0.05, "sequential minimum step")
require_approx(outcome["residual_tolerance"], 1e-5, "sequential residual tolerance")
Int(outcome["requested_maxdim"]) == EXPECTED_MAXDIM || error(
    "sequential outcome did not request chi 512",
)
source_config_path = resolve_source_configuration(String(outcome["config_path"]))
file_sha256(source_config_path) == EXPECTED_SOURCE_CONFIG_SHA256 || error(
    "sequential source-configuration SHA-256 mismatch",
)
source_configuration = TOML.parsefile(source_config_path)
source_optimizer = source_configuration["optimizer"]
source_scan = source_configuration["scan"]
String(get(source_optimizer, "multisite_update_alg", "")) == "sequential" ||
    error("source configuration is not the sequential control")
!Bool(get(source_optimizer, "restore_best_on_failure", false)) || error(
    "source configuration unexpectedly restores a best iterate",
)
Int(source_optimizer["max_iterations"]) == MAX_OUTER_ITERATIONS || error(
    "source configuration has an unexpected outer-iteration cap",
)
Float64.(source_scan["fluxes_over_pi"]) ==
    vcat([EXPECTED_TARGET_THETA], Float64.(2:10) ./ 10) || error(
        "source configuration has an unexpected flux schedule",
    )
lowercase(String(source_scan["initial_state_sha256"])) == expected_parent_sha256 ||
    error("source configuration names a different accepted parent")

sequential_candidate_path = resolve_recorded_artifact(
    String(outcome["rejected_state_path"]),
    outcome_path,
)
file_sha256(sequential_candidate_path) == EXPECTED_SEQUENTIAL_CANDIDATE_SHA256 ||
    error("sequential rejected-candidate SHA-256 mismatch")
sequential_candidate = read_state_metadata(sequential_candidate_path)
sequential_candidate.artifact_kind == "project_b_vumps_state" || error(
    "sequential candidate is not a Project B state",
)
!sequential_candidate.converged || error("sequential candidate is unexpectedly converged")
!sequential_candidate.continuation_accepted || error(
    "sequential candidate is unexpectedly accepted",
)
sequential_candidate.optimizer_stop_reason == "diverging_residual" || error(
    "sequential candidate has an unexpected optimizer stop reason",
)
sequential_candidate.parent_state_sha256 == expected_parent_sha256 || error(
    "sequential candidate does not descend from the accepted parent",
)
require_approx(sequential_candidate.theta_over_pi, EXPECTED_TARGET_THETA, "candidate theta/pi")
recorded_inner_solves_converged(sequential_candidate_path) || error(
    "sequential candidate has a recorded unconverged inner solve",
)

short_parent_hash = first(expected_parent_sha256, 12)
short_control_hash = first(EXPECTED_SEQUENTIAL_CANDIDATE_SHA256, 12)
experiment =
    "parallel_update_p0p10000000_to_p0p15000000_chi512_" *
    "$(short_parent_hash)_$(short_control_hash)"
config_directory = length(ARGS) == 4 ? abspath(ARGS[4]) : joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_test_configs",
    experiment,
)
output_directory = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_tests",
    "yc8_1",
    experiment,
    "chi512",
)
config_path = joinpath(config_directory, "phase1_chi512_parallel_control.toml")
ispath(config_path) && error("refusing to overwrite generated configuration: $config_path")
ispath(output_directory) && error("refusing to reuse control output: $output_directory")
mkpath(config_directory)

configuration = deepcopy(source_configuration)
delete!(configuration, "automation")
configuration["control"] = Dict{String,Any}(
    "artifact_kind" => "project_b_chi512_parallel_update_control",
    "decision_on_failure" => "switch_to_idmrg",
    "source_job_id" => EXPECTED_SOURCE_JOB_ID,
    "source_config_path" => source_config_path,
    "source_config_sha256" => EXPECTED_SOURCE_CONFIG_SHA256,
    "source_outcome_path" => outcome_path,
    "source_outcome_sha256" => EXPECTED_SOURCE_OUTCOME_SHA256,
    "sequential_candidate_path" => sequential_candidate_path,
    "sequential_candidate_sha256" => EXPECTED_SEQUENTIAL_CANDIDATE_SHA256,
)
configuration["optimizer"]["multisite_update_alg"] = "parallel"
configuration["optimizer"]["restore_best_on_failure"] = true
configuration["scan"]["fluxes_over_pi"] = [EXPECTED_TARGET_THETA]
configuration["scan"]["initial_state_file"] = parent_path
configuration["scan"]["initial_state_sha256"] = expected_parent_sha256
delete!(configuration["scan"], "optimizer_checkpoint_file")
delete!(configuration["scan"], "optimizer_checkpoint_sha256")
configuration["runtime"]["output_directory"] = output_directory

open(config_path, "w") do io
    println(io, "# Final controlled VUMPS test before an iDMRG pivot")
    println(io, "# Exact accepted theta/pi=0.1 parent: $parent_path")
    println(io, "# Parent SHA-256: $expected_parent_sha256")
    println(io, "# Sequential theta/pi=0.15 failure: $outcome_path")
    println(io, "# Only shared-point optimizer change: sequential -> parallel multisite update")
    println(io, "# A failed run restores and saves its lowest-residual iterate")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println("Generated the single-point chi-512 parallel control at theta/pi=0.15.")
println("The accepted parent, sequential outcome, rejected candidate, and inner solves were verified.")
println("Failure is terminal for the VUMPS campaign and triggers the documented iDMRG pivot.")
println("The immutable output destination is $output_directory")
