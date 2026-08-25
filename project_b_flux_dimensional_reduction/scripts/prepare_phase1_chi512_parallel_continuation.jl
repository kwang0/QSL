#!/usr/bin/env julia

using HDF5
using SHA
using TOML

3 <= length(ARGS) <= 4 || error(
    "usage: prepare_phase1_chi512_parallel_continuation.jl " *
    "ACCEPTED_CONTROL_STATE.h5 ACCEPTED_STATE_SHA256 FINAL_CONTROL_RUN_DIRECTORY " *
    "[CONFIG_DIRECTORY]",
)

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const EXPECTED_BRANCH = "primary_forward_chi512_legacy_0p1"
const EXPECTED_PREPARATION = "independent_theta0_alternating_chi512"
const EXPECTED_CONTROL_JOB_ID = "57337312"
const EXPECTED_CONTROL_CONFIG_SHA256 =
    "78a2a320b8fe641947336989188cd5c3e33b2607b1c29037ff88c3d664c43b93"
const EXPECTED_CONTROL_DECISION_SHA256 =
    "19e2e1e6f58752d6540672c311d23767aed7a45270b3528be476567da77ff778"
const EXPECTED_ACCEPTED_STATE_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const EXPECTED_PARENT_STATE_SHA256 =
    "f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc"
const EXPECTED_THETA0_STATE_SHA256 =
    "95255fbe3a590505902bd0061d7d9d9f14f8ecd7ca3e4eac1aacfc5c7fe72d0b"
const EXPECTED_CONTROL_THETA = 0.15
const EXPECTED_MAXDIM = 512
const MAX_OUTER_ITERATIONS = 180
const POLICY_VERSION = "yc8-1-primary-forward-chi512-v1"

function require_approx(actual, expected, label::AbstractString)
    isapprox(Float64(actual), Float64(expected); atol=1e-12, rtol=0) ||
        error("$label=$actual, expected $expected")
end

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function read_tsv_record(path::AbstractString)
    lines = readlines(path)
    length(lines) == 2 || error("expected exactly one TSV record in $path")
    header = split(lines[1], '\t'; keepempty=true)
    values = split(lines[2], '\t'; keepempty=true)
    length(header) == length(values) || error("malformed TSV record in $path")
    return Dict(header .=> values)
end

function read_key_value_file(path::AbstractString)
    result = Dict{String,String}()
    for line in eachline(path)
        isempty(strip(line)) && continue
        pieces = split(line, '='; limit=2)
        length(pieces) == 2 || error("malformed key-value row in $path: $line")
        result[pieces[1]] = pieces[2]
    end
    return result
end

function read_state_metadata(path::AbstractString)
    return h5open(path, "r") do file
        krylov = file["optimizer/krylov_solves"]
        solve_count = Int(read(krylov, "count"))
        solve_convergence = Int.(vec(read(krylov, "converged_count")))
        return (
            schema_version=Int(read(file, "schema_version")),
            artifact_kind=String(read(file, "artifact_kind")),
            converged=Bool(read(file, "optimizer/converged")),
            continuation_accepted=Bool(read(file, "continuation_accepted")),
            optimizer_stop_reason=String(read(file, "optimizer/stop_reason")),
            optimizer_residual=Float64(read(file, "optimizer/residual")),
            optimizer_minimum_residual=Float64(read(file, "optimizer/minimum_residual")),
            optimizer_terminal_residual=Float64(read(file, "optimizer/terminal_residual")),
            optimizer_residual_tolerance=Float64(read(file, "optimizer/residual_tolerance")),
            optimizer_iterations=Int(read(file, "optimizer/iterations")),
            optimizer_best_iteration=Int(read(file, "optimizer/best_iteration")),
            optimizer_returned_iteration=Int(read(file, "optimizer/returned_iteration")),
            optimizer_multisite_update_alg=String(read(file, "optimizer/multisite_update_alg")),
            optimizer_restore_best_enabled=Bool(read(
                file,
                "optimizer/restore_best_on_failure_enabled",
            )),
            optimizer_restored_best=Bool(read(file, "optimizer/restored_best_on_failure")),
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
            continuity_checked=Bool(read(file, "continuation/continuity_checked")),
            continuity_passed=Bool(read(file, "continuation/continuity_passed")),
            parent_overlap_per_site=Float64(read(file, "continuation/overlap_per_site")),
            maxlinkdim=Int(read(file, "observables/maxlinkdim")),
            J1=Float64(read(file, "model/J1")),
            J2=Float64(read(file, "model/J2")),
            Delta1=Float64(read(file, "model/Delta1")),
            Delta2=Float64(read(file, "model/Delta2")),
            Bz=Float64(read(file, "model/Bz")),
            krylov_solve_count=solve_count,
            krylov_converged_count=solve_convergence,
        )
    end
end

accepted_state_path = abspath(ARGS[1])
expected_state_sha256 = lowercase(ARGS[2])
control_run_dir = abspath(ARGS[3])
isfile(accepted_state_path) || error(
    "accepted parallel-control state does not exist: $accepted_state_path",
)
isdir(control_run_dir) || error("final-control run directory does not exist: $control_run_dir")
expected_state_sha256 == EXPECTED_ACCEPTED_STATE_SHA256 || error(
    "parallel promotion requires accepted state SHA-256 $EXPECTED_ACCEPTED_STATE_SHA256",
)
file_sha256(accepted_state_path) == expected_state_sha256 || error(
    "accepted parallel-control state SHA-256 mismatch",
)

job_path = joinpath(control_run_dir, "job.tsv")
result_path = joinpath(control_run_dir, "job.result")
sacct_path = joinpath(control_run_dir, "sacct.tsv")
snapshot_path = joinpath(control_run_dir, "config.snapshot.toml")
decision_path = joinpath(control_run_dir, "automatic_advance.toml")
for path in (job_path, result_path, sacct_path, snapshot_path, decision_path)
    isfile(path) || error("final-control evidence is missing: $path")
end
file_sha256(snapshot_path) == EXPECTED_CONTROL_CONFIG_SHA256 || error(
    "final-control configuration snapshot SHA-256 mismatch",
)
file_sha256(decision_path) == EXPECTED_CONTROL_DECISION_SHA256 || error(
    "final-control automatic decision SHA-256 mismatch",
)

job = read_tsv_record(job_path)
get(job, "job_id", "") == EXPECTED_CONTROL_JOB_ID || error(
    "promotion source is not final-control job $EXPECTED_CONTROL_JOB_ID",
)
lowercase(get(job, "config_sha256", "")) == EXPECTED_CONTROL_CONFIG_SHA256 || error(
    "final-control job record has a different configuration SHA-256",
)
get(job, "multisite_update_alg", "") == "parallel" || error(
    "final-control job record does not specify parallel VUMPS",
)
get(job, "restore_best_on_failure", "") == "true" || error(
    "final-control job record does not enable best-iterate preservation",
)

result = read_key_value_file(result_path)
get(result, "job_id", "") == EXPECTED_CONTROL_JOB_ID || error(
    "final-control result names a different job",
)
get(result, "exit_code", "") == "0" || error("final-control scan process did not exit cleanly")
allocation_rows = filter(!isempty, readlines(sacct_path))
any(row -> startswith(row, EXPECTED_CONTROL_JOB_ID * "|pb1-scan|COMPLETED|"), allocation_rows) ||
    error("final-control accounting does not record a completed allocation")

decision = TOML.parsefile(decision_path)
get(decision, "artifact_kind", "") == "project_b_phase1_automatic_advance" || error(
    "source decision is not a Phase 1 automatic-advance artifact",
)
get(decision, "policy_version", "") == POLICY_VERSION || error(
    "source decision uses an unexpected policy version",
)
get(decision, "source_job_id", "") == EXPECTED_CONTROL_JOB_ID || error(
    "source decision names a different control job",
)
get(decision, "source_scheduler_state", "") == "COMPLETED" || error(
    "source decision does not record a completed control",
)
get(decision, "source_config_sha256", "") == EXPECTED_CONTROL_CONFIG_SHA256 || error(
    "source decision names a different control configuration",
)
get(decision, "source_is_final_parallel_control", false) || error(
    "source decision is not marked as the final parallel control",
)
get(decision, "action", "") == "manual_review" || error(
    "source decision did not stop for manual promotion review",
)
get(decision, "transition", "") == "manual_review" || error(
    "source decision has an unexpected transition",
)
get(decision, "submit_permitted", true) && error(
    "source decision unexpectedly permitted an automatic submission",
)
require_approx(decision["parent_theta_over_pi"], EXPECTED_CONTROL_THETA, "decision parent theta/pi")
lowercase(String(decision["parent_state_sha256"])) == expected_state_sha256 || error(
    "source decision names a different accepted state",
)
basename(String(decision["parent_state_path"])) == basename(accepted_state_path) || error(
    "source decision names a different accepted-state basename",
)
get(decision, "parent_inner_solves_converged", false) || error(
    "source decision did not verify all accepted-state inner solves",
)

state = read_state_metadata(accepted_state_path)
state.schema_version >= 7 || error("parallel promotion requires a schema-v7 state")
state.artifact_kind == "project_b_vumps_state" || error("accepted artifact is not a VUMPS state")
state.converged || error("parallel-control state is not numerically converged")
state.continuation_accepted || error("parallel-control state is not accepted for continuation")
state.optimizer_stop_reason == "converged" || error("parallel-control optimizer did not converge")
state.optimizer_residual <= state.optimizer_residual_tolerance || error(
    "parallel-control residual exceeds its recorded tolerance",
)
require_approx(state.optimizer_residual_tolerance, 1e-5, "state residual tolerance")
require_approx(state.optimizer_residual, 9.1837732142842e-6, "state residual")
require_approx(state.optimizer_minimum_residual, state.optimizer_residual, "state minimum residual")
require_approx(state.optimizer_terminal_residual, state.optimizer_residual, "state terminal residual")
state.optimizer_iterations == 10 || error("parallel control did not converge in 10 iterations")
state.optimizer_best_iteration == 10 || error("parallel control has an unexpected best iteration")
state.optimizer_returned_iteration == 10 || error(
    "parallel control returned an unexpected iteration",
)
state.optimizer_multisite_update_alg == "parallel" || error(
    "accepted state was not produced by parallel VUMPS",
)
state.optimizer_restore_best_enabled || error(
    "accepted state does not record best-iterate preservation",
)
!state.optimizer_restored_best || error(
    "converged parallel-control state unexpectedly required rollback",
)
state.circumference == 8 && state.shift == 1 || error("accepted state is not YC8-1")
state.mps_period == 2 || error("accepted state does not use the minimal period-2 cell")
state.twist_gauge == "uniform" || error("accepted state does not use uniform twist gauge")
state.branch == EXPECTED_BRANCH || error("accepted state has the wrong branch")
state.preparation == EXPECTED_PREPARATION || error("accepted state has the wrong preparation")
state.direction == "forward" || error("accepted state is not forward lineage")
state.seed_pattern == "alternating" || error("accepted state has the wrong seed pattern")
state.random_seed == 101 || error("accepted state has the wrong random seed")
require_approx(state.theta_over_pi, EXPECTED_CONTROL_THETA, "accepted state theta/pi")
state.flux_history_over_pi == [0.0, 0.1, 0.15] || error(
    "accepted state does not have the pinned [0.0, 0.1, 0.15] history",
)
state.parent_state_sha256 == EXPECTED_PARENT_STATE_SHA256 || error(
    "accepted state does not descend from the pinned theta/pi=0.1 parent",
)
state.maxlinkdim == EXPECTED_MAXDIM || error("accepted state is not chi 512")
state.optimizer_requested_maxdim == EXPECTED_MAXDIM || error(
    "accepted state did not request chi 512",
)
state.continuity_checked || error("accepted state did not check parent continuity")
state.continuity_passed || error("accepted state failed parent continuity")
state.parent_overlap_per_site >= 0.99 || error("accepted state failed the overlap floor")
state.krylov_solve_count == 60 || error("parallel control has an unexpected inner-solve count")
length(state.krylov_converged_count) == state.krylov_solve_count || error(
    "parallel-control Krylov diagnostics have inconsistent lengths",
)
all(>(0), state.krylov_converged_count) || error(
    "parallel-control state contains an unconverged inner solve",
)
for (field, expected) in (
    (:J1, 1.0),
    (:J2, 0.12),
    (:Delta1, 1.0),
    (:Delta2, 1.0),
    (:Bz, 0.0),
)
    require_approx(getproperty(state, field), expected, "state $field")
end

source_configuration = TOML.parsefile(snapshot_path)
source_optimizer = source_configuration["optimizer"]
source_scan = source_configuration["scan"]
String(source_optimizer["multisite_update_alg"]) == "parallel" || error(
    "source configuration is not the parallel control",
)
Bool(source_optimizer["restore_best_on_failure"]) || error(
    "source configuration did not preserve its best iterate",
)
Int(source_optimizer["max_iterations"]) == MAX_OUTER_ITERATIONS || error(
    "source configuration has an unexpected iteration cap",
)
Float64.(source_scan["fluxes_over_pi"]) == [EXPECTED_CONTROL_THETA] || error(
    "source configuration is not the one-point control",
)

short_hash = first(expected_state_sha256, 12)
experiment = "chi512_parallel_promoted_from_p0p15000000_$short_hash"
config_directory = length(ARGS) == 4 ? abspath(ARGS[4]) : joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_generated_configs",
    experiment,
)
output_directory = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1",
    "yc8_1",
    experiment,
    "seed_101",
    "chi512",
)
config_path = joinpath(config_directory, "phase1_chi512_parallel_automatic.toml")
ispath(config_path) && error("refusing to overwrite generated configuration: $config_path")
ispath(output_directory) && error("refusing to reuse promoted-campaign output: $output_directory")
mkpath(config_directory)

configuration = deepcopy(source_configuration)
delete!(configuration, "control")
delete!(configuration, "automation")
configuration["promotion"] = Dict{String,Any}(
    "artifact_kind" => "project_b_chi512_parallel_update_promotion",
    "accepted_control_state_path" => accepted_state_path,
    "accepted_control_state_sha256" => EXPECTED_ACCEPTED_STATE_SHA256,
    "decision_on_numerical_failure" => "automatic_recovery_then_idmrg_review",
    "source_control_config_path" => snapshot_path,
    "source_control_config_sha256" => EXPECTED_CONTROL_CONFIG_SHA256,
    "source_control_decision_path" => decision_path,
    "source_control_decision_sha256" => EXPECTED_CONTROL_DECISION_SHA256,
    "source_control_job_id" => EXPECTED_CONTROL_JOB_ID,
)
configuration["optimizer"]["max_iterations"] = MAX_OUTER_ITERATIONS
configuration["optimizer"]["multisite_update_alg"] = "parallel"
configuration["optimizer"]["restore_best_on_failure"] = true
configuration["scan"]["fluxes_over_pi"] = Float64.(2:10) ./ 10
configuration["scan"]["minimum_step_over_pi"] = 0.05
configuration["scan"]["initial_state_file"] = accepted_state_path
configuration["scan"]["initial_state_sha256"] = expected_state_sha256
delete!(configuration["scan"], "optimizer_checkpoint_file")
delete!(configuration["scan"], "optimizer_checkpoint_sha256")
configuration["runtime"]["output_directory"] = output_directory

open(config_path, "w") do io
    println(io, "# Promoted chi-512 parallel-VUMPS continuation after successful job 57337312")
    println(io, "# Exact accepted theta/pi=0.15 parent: $accepted_state_path")
    println(io, "# Parent SHA-256: $expected_state_sha256")
    println(io, "# Nominal targets resume at 0.2 and continue on the legacy 0.1-pi grid")
    println(io, "# Automatic recovery may bisect only to 0.05*pi; iDMRG remains the fallback")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println("Promoted the pinned accepted theta/pi=0.15 state to parallel-VUMPS continuation.")
println("Schedule: 0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1.0")
println("All 60 control inner solves, the continuity gate, and immutable source hashes passed.")
println("The immutable output destination is $output_directory")
