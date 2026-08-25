#!/usr/bin/env julia

using Dates
using HDF5
using TOML
using TriangularJ1J2ProjectB

1 <= length(ARGS) <= 2 || error(
    "usage: prepare_phase1_automatic_advance.jl PHASE1_RUN_DIRECTORY " *
    "[GENERATED_PROJECT_ROOT]",
)

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const POLICY_VERSION = "yc8-1-primary-forward-chi512-v1"
const EXPECTED_BRANCH = "primary_forward_chi512_legacy_0p1"
const EXPECTED_PREPARATION = "independent_theta0_alternating_chi512"
const EXPECTED_MAXDIM = 512
const BASE_MAX_ITERATIONS = 180
const DECISION_FILENAME = "automatic_advance.toml"
const FINAL_CONTROL_SOURCE_JOB_ID = "57245573"
const FINAL_CONTROL_SOURCE_CONFIG_SHA256 =
    "1a272abe6879c69827d1f14547a0b6d4780083945e414ad3f1cb9ee1a050749f"
const FINAL_CONTROL_SOURCE_OUTCOME_SHA256 =
    "001eadee6f43e73fa9228c4221c8ac81edc821db58a391625037806b16e0b2cf"
const FINAL_CONTROL_SEQUENTIAL_CANDIDATE_SHA256 =
    "b5ef48caaf7a10eb00e4fd003e8fd1b5a57add77a8111b270a358a7c8f049953"
const PARALLEL_PROMOTION_SOURCE_JOB_ID = "57337312"
const PARALLEL_PROMOTION_SOURCE_CONFIG_SHA256 =
    "78a2a320b8fe641947336989188cd5c3e33b2607b1c29037ff88c3d664c43b93"
const PARALLEL_PROMOTION_SOURCE_DECISION_SHA256 =
    "19e2e1e6f58752d6540672c311d23767aed7a45270b3528be476567da77ff778"
const PARALLEL_PROMOTION_ACCEPTED_STATE_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"

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
    isfile(path) || return result
    for line in eachline(path)
        isempty(strip(line)) && continue
        pieces = split(line, '='; limit=2)
        length(pieces) == 2 || error("malformed key-value row in $path: $line")
        result[pieces[1]] = pieces[2]
    end
    return result
end

function scheduler_state(run_dir::AbstractString, job_id::AbstractString)
    path = joinpath(run_dir, "sacct.tsv")
    isfile(path) || error("reconcile the run before automatic advance: missing $path")
    for line in eachline(path)
        isempty(strip(line)) && continue
        fields = split(line, '|'; keepempty=true)
        length(fields) >= 3 || continue
        fields[1] == job_id || continue
        return fields[3]
    end
    error("accounting export $path has no allocation row for job $job_id")
end

function resolve_recorded_path(value, source_config_path::AbstractString)
    path = String(value)
    return isabspath(path) ? normpath(path) :
        normpath(joinpath(dirname(source_config_path), path))
end

function required_table(raw, name::AbstractString)
    haskey(raw, name) || error("source configuration is missing [$name]")
    return raw[name]
end

function require_equal(actual, expected, label::AbstractString)
    actual == expected || error("$label=$actual, expected $expected")
end

function require_approx(actual, expected, label::AbstractString)
    isapprox(Float64(actual), Float64(expected); atol=0, rtol=1e-12) ||
        error("$label=$actual, expected $expected")
end

function is_final_parallel_control(raw)
    optimizer = get(raw, "optimizer", Dict{String,Any}())
    scan = get(raw, "scan", Dict{String,Any}())
    control = get(raw, "control", Dict{String,Any}())
    fluxes = Float64.(get(scan, "fluxes_over_pi", Float64[]))
    return String(get(optimizer, "multisite_update_alg", "sequential")) == "parallel" &&
        Bool(get(optimizer, "restore_best_on_failure", false)) &&
        length(fluxes) == 1 && isapprox(only(fluxes), 0.15; atol=1e-12, rtol=0) &&
        String(get(control, "artifact_kind", "")) ==
            "project_b_chi512_parallel_update_control" &&
        String(get(control, "decision_on_failure", "")) == "switch_to_idmrg" &&
        String(get(control, "source_job_id", "")) == FINAL_CONTROL_SOURCE_JOB_ID &&
        lowercase(String(get(control, "source_config_sha256", ""))) ==
            FINAL_CONTROL_SOURCE_CONFIG_SHA256 &&
        lowercase(String(get(control, "source_outcome_sha256", ""))) ==
            FINAL_CONTROL_SOURCE_OUTCOME_SHA256 &&
        lowercase(String(get(control, "sequential_candidate_sha256", ""))) ==
            FINAL_CONTROL_SEQUENTIAL_CANDIDATE_SHA256
end

function is_promoted_parallel_campaign(raw)
    optimizer = get(raw, "optimizer", Dict{String,Any}())
    promotion = get(raw, "promotion", Dict{String,Any}())
    return String(get(optimizer, "multisite_update_alg", "sequential")) == "parallel" &&
        Bool(get(optimizer, "restore_best_on_failure", false)) &&
        String(get(promotion, "artifact_kind", "")) ==
            "project_b_chi512_parallel_update_promotion" &&
        String(get(promotion, "decision_on_numerical_failure", "")) ==
            "automatic_recovery_then_idmrg_review" &&
        String(get(promotion, "source_control_job_id", "")) ==
            PARALLEL_PROMOTION_SOURCE_JOB_ID &&
        lowercase(String(get(promotion, "source_control_config_sha256", ""))) ==
            PARALLEL_PROMOTION_SOURCE_CONFIG_SHA256 &&
        lowercase(String(get(promotion, "source_control_decision_sha256", ""))) ==
            PARALLEL_PROMOTION_SOURCE_DECISION_SHA256 &&
        lowercase(String(get(promotion, "accepted_control_state_sha256", ""))) ==
            PARALLEL_PROMOTION_ACCEPTED_STATE_SHA256
end

function validate_promotion_evidence(raw, source_path::AbstractString)
    promotion = required_table(raw, "promotion")
    for (path_key, expected_sha256) in (
        ("source_control_config_path", PARALLEL_PROMOTION_SOURCE_CONFIG_SHA256),
        ("source_control_decision_path", PARALLEL_PROMOTION_SOURCE_DECISION_SHA256),
        ("accepted_control_state_path", PARALLEL_PROMOTION_ACCEPTED_STATE_SHA256),
    )
        path = resolve_recorded_path(promotion[path_key], source_path)
        isfile(path) || error("parallel-promotion evidence does not exist: $path")
        PB.file_sha256(path) == expected_sha256 || error(
            "parallel-promotion evidence SHA-256 mismatch for $path",
        )
    end
end

function validate_source_configuration(raw, source_path::AbstractString)
    model = required_table(raw, "model")
    optimizer = required_table(raw, "optimizer")
    scan = required_table(raw, "scan")
    runtime = required_table(raw, "runtime")
    require_equal(Int(model["circumference"]), 8, "model.circumference")
    require_equal(Int(get(model, "shift", 0)), 1, "model.shift")
    require_equal(Int(model["mps_period"]), 2, "model.mps_period")
    require_equal(lowercase(String(model["twist_gauge"])), "uniform", "model.twist_gauge")
    require_approx(model["J1"], 1.0, "model.J1")
    require_approx(model["J2"], 0.12, "model.J2")
    require_approx(model["Delta1"], 1.0, "model.Delta1")
    require_approx(model["Delta2"], 1.0, "model.Delta2")
    require_approx(model["Bz"], 0.0, "model.Bz")
    require_equal(Int(optimizer["maxdim"]), EXPECTED_MAXDIM, "optimizer.maxdim")
    require_approx(optimizer["cutoff"], 1e-10, "optimizer.cutoff")
    require_approx(optimizer["residual_tol"], 1e-5, "optimizer.residual_tol")
    max_iterations = Int(get(optimizer, "max_iterations", 0))
    1 <= max_iterations <= PB.PHASE1_CHI512_MAX_AUTOMATIC_ITERATIONS ||
        error("optimizer.max_iterations lies outside the automatic range 1:720")
    require_equal(Int(get(optimizer, "max_growth_steps", 0)), 20, "optimizer.max_growth_steps")
    require_approx(get(optimizer, "solver_tol_scale", NaN), 100.0, "optimizer.solver_tol_scale")
    require_approx(get(optimizer, "solver_tol_floor", NaN), 1e-10, "optimizer.solver_tol_floor")
    require_equal(
        Int(get(optimizer, "solver_krylov_dimension", 0)),
        30,
        "optimizer.solver_krylov_dimension",
    )
    require_equal(
        Int(get(optimizer, "solver_max_iterations", 0)),
        100,
        "optimizer.solver_max_iterations",
    )
    Bool(get(optimizer, "require_converged", false)) ||
        error("optimizer.require_converged must remain true")
    Bool(get(optimizer, "record_krylov_diagnostics", false)) ||
        error("automatic advance requires recorded Krylov diagnostics")
    final_parallel_control = is_final_parallel_control(raw)
    promoted_parallel_campaign = is_promoted_parallel_campaign(raw)
    final_parallel_control && promoted_parallel_campaign && error(
        "a source configuration cannot be both the final control and its promotion",
    )
    expected_algorithm = final_parallel_control || promoted_parallel_campaign ?
        "parallel" : "sequential"
    require_equal(
        String(get(optimizer, "multisite_update_alg", "sequential")),
        expected_algorithm,
        "optimizer.multisite_update_alg",
    )
    require_equal(
        Bool(get(optimizer, "restore_best_on_failure", false)),
        final_parallel_control || promoted_parallel_campaign,
        "optimizer.restore_best_on_failure",
    )
    promoted_parallel_campaign && validate_promotion_evidence(raw, source_path)
    require_equal(Int(get(optimizer, "divergence_patience", 0)), 8, "optimizer.divergence_patience")
    require_approx(get(optimizer, "divergence_factor", NaN), 4.0, "optimizer.divergence_factor")
    Bool(get(optimizer, "plateau_detection", false)) ||
        error("optimizer.plateau_detection must remain true")
    require_equal(
        Int(get(optimizer, "plateau_warmup_iterations", 0)),
        40,
        "optimizer.plateau_warmup_iterations",
    )
    require_equal(
        Int(get(optimizer, "plateau_patience", 0)),
        32,
        "optimizer.plateau_patience",
    )
    require_approx(
        get(optimizer, "plateau_min_relative_improvement", NaN),
        5e-3,
        "optimizer.plateau_min_relative_improvement",
    )
    require_equal(String(scan["branch"]), EXPECTED_BRANCH, "scan.branch")
    require_equal(String(scan["preparation"]), EXPECTED_PREPARATION, "scan.preparation")
    require_equal(lowercase(String(scan["direction"])), "forward", "scan.direction")
    require_equal(lowercase(String(scan["lineage_policy"])), "strict", "scan.lineage_policy")
    require_equal(String(scan["seed_pattern"]), "alternating", "scan.seed_pattern")
    require_equal(Int(scan["random_seed"]), 101, "scan.random_seed")
    Bool(get(scan, "adaptive_bisection", false)) ||
        error("scan.adaptive_bisection must remain true")
    minimum_step = Float64(get(scan, "minimum_step_over_pi", NaN))
    any(value -> isapprox(minimum_step, value; atol=1e-12, rtol=0), (0.1, 0.05)) ||
        error("scan.minimum_step_over_pi must be 0.1 or 0.05")
    fluxes = Float64.(scan["fluxes_over_pi"])
    all(theta -> 0.0 <= theta <= 1.0, fluxes) ||
        error("automatic source flux lies outside [0, 1]")
    if promoted_parallel_campaign
        if haskey(raw, "automation")
            automation = required_table(raw, "automation")
            require_equal(
                String(get(automation, "policy_version", "")),
                POLICY_VERSION,
                "automation.policy_version",
            )
        else
            require_equal(
                lowercase(String(get(scan, "initial_state_sha256", ""))),
                PARALLEL_PROMOTION_ACCEPTED_STATE_SHA256,
                "scan.initial_state_sha256",
            )
            expected_fluxes = Float64.(2:10) ./ 10
            length(fluxes) == length(expected_fluxes) &&
                all(isapprox.(fluxes, expected_fluxes; atol=1e-12, rtol=0)) ||
                error("initial promoted campaign must schedule theta/pi=0.2:0.1:1.0")
        end
    end
    Bool(get(scan, "save_rejected", false)) || error("scan.save_rejected must remain true")
    Bool(get(scan, "require_parent_overlap", false)) ||
        error("scan.require_parent_overlap must remain true")
    require_approx(
        scan["minimum_parent_overlap_per_site"],
        0.99,
        "scan.minimum_parent_overlap_per_site",
    )
    require_approx(
        get(scan, "parent_overlap_tolerance", NaN),
        1e-8,
        "scan.parent_overlap_tolerance",
    )
    require_equal(
        Int(get(scan, "parent_overlap_krylov_dimension", 0)),
        16,
        "scan.parent_overlap_krylov_dimension",
    )
    Int(get(runtime, "blas_threads", 0)) == 1 || error("runtime.blas_threads must remain 1")
    Int(get(runtime, "strided_threads", 0)) == 1 ||
        error("runtime.strided_threads must remain 1")
    Bool(get(runtime, "threaded_blocksparse", false)) ||
        error("runtime.threaded_blocksparse must remain true")
    require_equal(Int(get(runtime, "output_level", -1)), 1, "runtime.output_level")
    return (;
        final_parallel_control,
        promoted_parallel_campaign,
    )
end

function recorded_inner_solves_converged(path::AbstractString)
    return h5open(path, "r") do file
        count_path = "optimizer/krylov_solves/count"
        convergence_path = "optimizer/krylov_solves/converged_count"
        haskey(file, count_path) || return false
        count = Int(read(file, count_path))
        count > 0 || return false
        haskey(file, convergence_path) || return false
        values = Int.(vec(read(file, convergence_path)))
        return length(values) == count && all(>(0), values)
    end
end

function accepted_state_paths(output_directory::AbstractString)
    directory = joinpath(output_directory, "states")
    isdir(directory) || return String[]
    candidates = Tuple{Int,String}[]
    for name in readdir(directory)
        match_result = match(r"^state_([0-9]+)_.*_accepted_.*[.]h5$", name)
        match_result === nothing && continue
        push!(candidates, (parse(Int, match_result.captures[1]), joinpath(directory, name)))
    end
    sort!(candidates; by=first)
    return last.(candidates)
end

function validate_parent(
    path::AbstractString,
    expected_sha256::Union{Nothing,AbstractString}=nothing;
    require_parallel::Bool=false,
)
    isfile(path) || error("accepted parent does not exist: $path")
    actual_sha256 = PB.file_sha256(path)
    expected_sha256 === nothing || actual_sha256 == lowercase(String(expected_sha256)) ||
        error("accepted-parent SHA-256 mismatch for $path")
    parent = PB.read_state_file(path)
    parent.schema_version >= 6 || error("automatic advance requires a schema-v6 parent")
    parent.converged || error("automatic parent is not numerically converged")
    parent.continuation_accepted || error("automatic parent was not accepted for continuation")
    parent.optimizer_stop_reason == "converged" ||
        error("automatic parent optimizer did not stop as converged")
    parent.circumference == 8 && parent.shift == 1 ||
        error("automatic parent is not YC8-1")
    parent.mps_period == 2 || error("automatic parent does not use the minimal two-site cell")
    parent.twist_gauge === :uniform || error("automatic parent does not use uniform gauge")
    parent.branch == EXPECTED_BRANCH || error("automatic parent has the wrong branch")
    parent.preparation == EXPECTED_PREPARATION ||
        error("automatic parent has the wrong preparation")
    parent.direction === :forward || error("automatic parent is not forward lineage")
    parent.seed_pattern == "alternating" || error("automatic parent has the wrong seed pattern")
    parent.random_seed == 101 || error("automatic parent has the wrong random seed")
    PB.maxlinkdim(parent.psi) == EXPECTED_MAXDIM || error("automatic parent is not chi 512")
    parent.optimizer_requested_maxdim == EXPECTED_MAXDIM ||
        error("automatic parent did not request chi 512")
    isapprox(parent.optimizer_residual_tolerance, 1e-5; atol=0, rtol=1e-12) ||
        error("automatic parent did not use residual tolerance 1e-5")
    parent.optimizer_residual <= parent.optimizer_residual_tolerance ||
        error("automatic parent residual exceeds its recorded tolerance")
    if require_parallel
        parent.optimizer_multisite_update_alg == "parallel" || error(
            "promoted-campaign parent was not produced by parallel VUMPS",
        )
        parent.optimizer_restore_best_on_failure_enabled || error(
            "promoted-campaign parent lacks best-iterate preservation metadata",
        )
    end
    for (field, expected) in (
        (:J1, 1.0),
        (:J2, 0.12),
        (:Delta1, 1.0),
        (:Delta2, 1.0),
        (:Bz, 0.0),
    )
        isapprox(getproperty(parent, field), expected; atol=1e-12, rtol=1e-12) ||
            error("automatic parent $field does not match the campaign")
    end
    isempty(parent.flux_history_over_pi) && error("automatic parent has no flux history")
    isapprox(first(parent.flux_history_over_pi), 0.0; atol=1e-12, rtol=0) ||
        error("automatic parent flux history does not begin at theta/pi=0")
    all(>(0), diff(parent.flux_history_over_pi)) ||
        error("automatic parent flux history is not strictly forward")
    isapprox(last(parent.flux_history_over_pi), parent.theta_over_pi; atol=1e-12, rtol=0) ||
        error("automatic parent flux history does not terminate at its saved flux")
    return (; path=abspath(path), sha256=actual_sha256, state=parent)
end

function validate_candidate(
    path::AbstractString,
    expected_sha256::AbstractString;
    require_parallel::Bool=false,
)
    isfile(path) || error("rejected candidate does not exist: $path")
    actual_sha256 = PB.file_sha256(path)
    actual_sha256 == lowercase(String(expected_sha256)) ||
        error("rejected-candidate SHA-256 mismatch for $path")
    candidate = PB.read_state_file(path)
    candidate.continuation_accepted && error("outcome candidate is unexpectedly accepted")
    candidate.branch == EXPECTED_BRANCH || error("outcome candidate has the wrong branch")
    candidate.preparation == EXPECTED_PREPARATION ||
        error("outcome candidate has the wrong preparation")
    candidate.direction === :forward || error("outcome candidate is not forward lineage")
    candidate.seed_pattern == "alternating" ||
        error("outcome candidate has the wrong seed pattern")
    candidate.random_seed == 101 || error("outcome candidate has the wrong random seed")
    PB.maxlinkdim(candidate.psi) == EXPECTED_MAXDIM ||
        error("outcome candidate is not chi 512")
    candidate.optimizer_requested_maxdim == EXPECTED_MAXDIM ||
        error("outcome candidate did not request chi 512")
    isapprox(candidate.optimizer_residual_tolerance, 1e-5; atol=0, rtol=1e-12) ||
        error("outcome candidate did not use residual tolerance 1e-5")
    if require_parallel
        candidate.optimizer_multisite_update_alg == "parallel" || error(
            "promoted-campaign candidate was not produced by parallel VUMPS",
        )
        candidate.optimizer_restore_best_on_failure_enabled || error(
            "promoted-campaign candidate lacks best-iterate preservation metadata",
        )
    end
    return (; path=abspath(path), sha256=actual_sha256, state=candidate)
end

function atomic_toml(path::AbstractString, data)
    ispath(path) && error("refusing to overwrite immutable artifact: $path")
    temporary = path * ".tmp"
    ispath(temporary) && error("stale temporary artifact exists: $temporary")
    try
        open(temporary, "w") do io
            TOML.print(io, data; sorted=true)
        end
        Base.Filesystem.rename(temporary, path)
    catch
        isfile(temporary) && rm(temporary; force=true)
        rethrow()
    end
    return path
end

function verify_existing_decision(
    path::AbstractString,
    run_dir::AbstractString,
    job_id::AbstractString,
    snapshot_path::AbstractString,
)
    decision = TOML.parsefile(path)
    get(decision, "artifact_kind", "") == "project_b_phase1_automatic_advance" ||
        error("unexpected automatic decision artifact: $path")
    get(decision, "policy_version", "") == POLICY_VERSION ||
        error("automatic decision was created by a different policy version")
    get(decision, "source_run_directory", "") == run_dir ||
        error("automatic decision names a different source run")
    get(decision, "source_job_id", "") == job_id ||
        error("automatic decision names a different source job")
    get(decision, "source_scheduler_state", "") == scheduler_state(run_dir, job_id) ||
        error("automatic decision scheduler state differs from reconciled accounting")
    snapshot_sha256 = PB.file_sha256(snapshot_path)
    get(decision, "source_config_sha256", "") == snapshot_sha256 ||
        error("submitted configuration snapshot changed after automatic decision")
    for prefix in ("parent_state", "candidate_state")
        state_path = String(get(decision, "$(prefix)_path", ""))
        state_sha256 = String(get(decision, "$(prefix)_sha256", ""))
        isempty(state_path) == isempty(state_sha256) ||
            error("automatic decision has incomplete $prefix provenance")
        isempty(state_path) && continue
        isfile(state_path) || error("automatic decision state is missing: $state_path")
        PB.file_sha256(state_path) == state_sha256 ||
            error("automatic decision state changed: $state_path")
    end
    if get(decision, "action", "") == "next_config"
        config_path = String(decision["next_config_path"])
        isfile(config_path) || error("recorded next configuration is missing: $config_path")
        PB.file_sha256(config_path) == String(decision["next_config_sha256"]) ||
            error("recorded next configuration changed: $config_path")
    end
    return path
end

run_dir = abspath(first(ARGS))
generated_project_root = length(ARGS) == 2 ? abspath(ARGS[2]) : PROJECT_ROOT
isdir(run_dir) || error("Phase 1 run directory does not exist: $run_dir")
job_path = joinpath(run_dir, "job.tsv")
snapshot_path = joinpath(run_dir, "config.snapshot.toml")
isfile(job_path) || error("missing Phase 1 job record: $job_path")
isfile(snapshot_path) || error("missing submitted configuration snapshot: $snapshot_path")
job = read_tsv_record(job_path)
job_id = get(job, "job_id", "")
occursin(r"^[0-9]+$", job_id) || error("invalid job ID in $job_path")
decision_path = joinpath(run_dir, DECISION_FILENAME)
if isfile(decision_path)
    println(verify_existing_decision(decision_path, run_dir, job_id, snapshot_path))
    exit()
end

source_config_path = get(job, "config_path", "")
isabspath(source_config_path) || error("job record does not contain an absolute config path")
source_config_sha256 = lowercase(get(job, "config_sha256", ""))
occursin(r"^[0-9a-f]{64}$", source_config_sha256) ||
    error("job record has an invalid config SHA-256")
PB.file_sha256(snapshot_path) == source_config_sha256 ||
    error("submitted configuration snapshot does not match the recorded SHA-256")
raw = TOML.parsefile(snapshot_path)
campaign_kind = validate_source_configuration(raw, snapshot_path)
final_parallel_control = campaign_kind.final_parallel_control
promoted_parallel_campaign = campaign_kind.promoted_parallel_campaign
runtime = required_table(raw, "runtime")
scan = required_table(raw, "scan")
optimizer = required_table(raw, "optimizer")
output_directory = resolve_recorded_path(runtime["output_directory"], source_config_path)

state = scheduler_state(run_dir, job_id)
job_result = read_key_value_file(joinpath(run_dir, "job.result"))
exit_code = haskey(job_result, "exit_code") ? parse(Int, job_result["exit_code"]) : nothing
outcome_path = joinpath(output_directory, "scan_outcome.toml")
termination_path = joinpath(run_dir, "termination.toml")
outcome = isfile(outcome_path) ? TOML.parsefile(outcome_path) : Dict{String,Any}()

parent_path = nothing
parent_expected_sha256 = nothing
if !isempty(outcome) && haskey(outcome, "accepted_state_path")
    parent_path = String(outcome["accepted_state_path"])
    parent_expected_sha256 = String(outcome["accepted_state_sha256"])
else
    candidates = accepted_state_paths(output_directory)
    if !isempty(candidates)
        parent_path = last(candidates)
    elseif haskey(scan, "initial_state_file")
        parent_path = resolve_recorded_path(scan["initial_state_file"], source_config_path)
        parent_expected_sha256 = haskey(scan, "initial_state_sha256") ?
            String(scan["initial_state_sha256"]) : nothing
    end
end
parent = parent_path === nothing ? nothing : validate_parent(
    parent_path,
    parent_expected_sha256;
    require_parallel=promoted_parallel_campaign,
)

outcome_kind = "none"
outcome_status = ""
classification = ""
stop_reason = ""
bracket_width = NaN
projected_iterations = NaN
rejected_theta = NaN
candidate = nothing
candidate_inner_converged = true
if isfile(termination_path)
    outcome_kind = "operator_termination"
    termination = TOML.parsefile(termination_path)
    outcome_status = String(get(termination, "classification", "operator_termination"))
elseif !isempty(outcome)
    artifact_kind = String(get(outcome, "artifact_kind", ""))
    outcome_kind = artifact_kind == "project_b_flux_scan_outcome" ? "flux_scan" : artifact_kind
    outcome_status = String(get(outcome, "status", ""))
    classification = String(get(outcome, "classification", ""))
    stop_reason = String(get(outcome, "optimizer_stop_reason", ""))
    bracket_width = Float64(get(outcome, "bracket_width_over_pi", NaN))
    projected_iterations = Float64(get(outcome, "optimizer_projected_total_iterations", NaN))
    rejected_theta = Float64(get(
        outcome,
        "rejected_theta_over_pi",
        get(outcome, "theta_over_pi", NaN),
    ))
    if haskey(outcome, "rejected_state_path")
        candidate = validate_candidate(
            String(outcome["rejected_state_path"]),
            String(outcome["rejected_state_sha256"]);
            require_parallel=final_parallel_control || promoted_parallel_campaign,
        )
        candidate_inner_converged = recorded_inner_solves_converged(candidate.path)
    elseif haskey(outcome, "candidate_state_path")
        candidate = validate_candidate(
            String(outcome["candidate_state_path"]),
            String(outcome["candidate_state_sha256"]);
            require_parallel=final_parallel_control || promoted_parallel_campaign,
        )
        candidate_inner_converged = recorded_inner_solves_converged(candidate.path)
    end
end

if candidate !== nothing
    parent === nothing && error("a rejected outcome candidate has no accepted parent")
    candidate.state.parent_state_sha256 == parent.sha256 ||
        error("rejected candidate does not name the selected accepted-parent SHA-256")
    basename(candidate.state.parent_state_path) == basename(parent.path) ||
        error("rejected candidate does not name the selected accepted-parent basename")
    expected_candidate_history = copy(parent.state.flux_history_over_pi)
    if !isapprox(
        last(expected_candidate_history),
        candidate.state.theta_over_pi;
        atol=1e-12,
        rtol=0,
    )
        push!(expected_candidate_history, candidate.state.theta_over_pi)
    end
    length(candidate.state.flux_history_over_pi) == length(expected_candidate_history) ||
        error("rejected candidate flux history does not extend the accepted parent")
    all(isapprox.(
        candidate.state.flux_history_over_pi,
        expected_candidate_history;
        atol=1e-12,
        rtol=0,
    )) || error("rejected candidate flux history does not extend the accepted parent")
end

if (final_parallel_control || promoted_parallel_campaign) && candidate !== nothing
    candidate.state.optimizer_multisite_update_alg == "parallel" || error(
        "parallel-campaign candidate was not produced by parallel VUMPS",
    )
    candidate.state.optimizer_restore_best_on_failure_enabled || error(
        "parallel-campaign candidate did not enable best-iterate preservation",
    )
    isapprox(
        candidate.state.optimizer_residual,
        candidate.state.optimizer_minimum_residual;
        atol=0,
        rtol=1e-12,
    ) || error("parallel-campaign rejected state is not its lowest-residual iterate")
    candidate.state.optimizer_returned_iteration ==
        candidate.state.optimizer_best_iteration || error(
            "parallel-campaign rejected state does not record the best iteration as returned",
        )
    if candidate.state.optimizer_terminal_residual >
            candidate.state.optimizer_minimum_residual * (1 + 1e-12)
        candidate.state.optimizer_restored_best_on_failure || error(
            "degraded parallel-campaign trajectory did not restore its best iterate",
        )
    end
end

if final_parallel_control && parent !== nothing &&
        isapprox(parent.state.theta_over_pi, 0.15; atol=1e-12, rtol=0)
    parent.state.optimizer_multisite_update_alg == "parallel" || error(
        "accepted final-control state was not produced by parallel VUMPS",
    )
    parent.state.optimizer_restore_best_on_failure_enabled || error(
        "accepted final-control state lacks the requested control metadata",
    )
end

parent_inner_converged = parent === nothing ? false :
    recorded_inner_solves_converged(parent.path)
policy = PB.phase1_advance_policy(
    scheduler_state=state,
    job_exit_code=exit_code,
    has_accepted_parent=parent !== nothing,
    parent_theta_over_pi=parent === nothing ? NaN : parent.state.theta_over_pi,
    parent_inner_solves_converged=parent_inner_converged,
    outcome_kind=outcome_kind,
    outcome_status=outcome_status,
    classification=classification,
    optimizer_stop_reason=stop_reason,
    bracket_width_over_pi=bracket_width,
    current_max_iterations=Int(get(optimizer, "max_iterations", BASE_MAX_ITERATIONS)),
    projected_total_iterations=projected_iterations,
    candidate_inner_solves_converged=candidate_inner_converged,
)

if final_parallel_control
    reached_control_target = parent !== nothing &&
        isapprox(parent.state.theta_over_pi, 0.15; atol=1e-12, rtol=0)
    policy = PB.phase1_final_vumps_control_policy(
        scheduler_state=state,
        job_exit_code=exit_code,
        reached_target=reached_control_target,
        outcome_kind=outcome_kind,
    )
end

next_schedule = Float64[]
next_max_iterations = BASE_MAX_ITERATIONS
if policy.action === :continue_schedule
    next_schedule = PB.phase1_next_nominal_fluxes(parent.state.theta_over_pi)
    if isempty(next_schedule)
        policy = (action=:complete, reason="the accepted lineage reached the campaign target")
    end
elseif policy.action === :refine_interval
    isfinite(rejected_theta) || error("refinement outcome has no rejected theta")
    next_schedule = PB.phase1_refined_forward_schedule(
        parent.state.theta_over_pi,
        rejected_theta,
    )
elseif policy.action === :retry_contracting
    isfinite(rejected_theta) || error("contracting outcome has no target theta")
    next_schedule = Float64[rejected_theta]
    append!(next_schedule, PB.phase1_next_nominal_fluxes(rejected_theta))
    next_max_iterations = PB.phase1_contracting_retry_cap(
        Int(get(optimizer, "max_iterations", BASE_MAX_ITERATIONS)),
        projected_iterations,
    )
end

decision = Dict{String,Any}(
    "schema_version" => 1,
    "artifact_kind" => "project_b_phase1_automatic_advance",
    "policy_version" => POLICY_VERSION,
    "created_at_utc" => string(now(UTC)),
    "source_run_directory" => run_dir,
    "source_job_id" => job_id,
    "source_scheduler_state" => state,
    "source_config_sha256" => source_config_sha256,
    "source_outcome_path" => isfile(outcome_path) ? outcome_path : "",
    "source_outcome_kind" => outcome_kind,
    "source_outcome_status" => outcome_status,
    "source_classification" => classification,
    "source_optimizer_stop_reason" => stop_reason,
    "source_is_final_parallel_control" => final_parallel_control,
    "source_is_promoted_parallel_campaign" => promoted_parallel_campaign,
    "next_solver_on_numerical_failure" => if final_parallel_control
        "idmrg"
    elseif promoted_parallel_campaign
        "idmrg_after_automatic_recovery"
    else
        ""
    end,
    "action" => policy.action in (:continue_schedule, :refine_interval, :retry_contracting) ?
        "next_config" : String(policy.action),
    "transition" => String(policy.action),
    "reason" => policy.reason,
    "submit_permitted" => policy.action in (
        :continue_schedule,
        :refine_interval,
        :retry_contracting,
    ),
    "parent_state_path" => parent === nothing ? "" : parent.path,
    "parent_state_sha256" => parent === nothing ? "" : parent.sha256,
    "parent_theta_over_pi" => parent === nothing ? NaN : parent.state.theta_over_pi,
    "parent_inner_solves_converged" => parent_inner_converged,
    "candidate_state_path" => candidate === nothing ? "" : candidate.path,
    "candidate_state_sha256" => candidate === nothing ? "" : candidate.sha256,
    "candidate_inner_solves_converged" => candidate_inner_converged,
    "next_fluxes_over_pi" => next_schedule,
    "next_max_iterations" => next_max_iterations,
)

if decision["action"] == "next_config"
    isempty(next_schedule) && error("automatic next configuration has an empty schedule")
    short_hash = first(parent.sha256, 12)
    transition = String(policy.action)
    first_label = PB.theta_label(first(next_schedule))
    last_label = PB.theta_label(last(next_schedule))
    parent_label = PB.theta_label(parent.state.theta_over_pi)
    experiment =
        "chi512_auto_$(transition)_from_$(parent_label)_$(first_label)_to_$(last_label)_$short_hash"
    config_directory = joinpath(
        generated_project_root,
        "output",
        "phase1_generated_configs",
        experiment,
    )
    next_output_directory = joinpath(
        generated_project_root,
        "output",
        "phase1",
        "yc8_1",
        experiment,
        "seed_101",
        "chi512",
    )
    next_config_path = joinpath(config_directory, "phase1_chi512_automatic.toml")
    ispath(config_directory) && error(
        "automatic configuration destination already exists without a decision record: " *
        config_directory,
    )
    ispath(next_output_directory) && error(
        "automatic output destination already exists: $next_output_directory",
    )
    mkpath(config_directory)
    next_raw = deepcopy(raw)
    next_raw["optimizer"]["max_iterations"] = next_max_iterations
    next_raw["scan"]["fluxes_over_pi"] = next_schedule
    next_raw["scan"]["minimum_step_over_pi"] =
        PB.PHASE1_CHI512_MINIMUM_STEP_OVER_PI
    next_raw["scan"]["initial_state_file"] = parent.path
    next_raw["scan"]["initial_state_sha256"] = parent.sha256
    delete!(next_raw["scan"], "optimizer_checkpoint_file")
    delete!(next_raw["scan"], "optimizer_checkpoint_sha256")
    next_raw["runtime"]["output_directory"] = next_output_directory
    next_raw["automation"] = Dict{String,Any}(
        "policy_version" => POLICY_VERSION,
        "source_run_directory" => run_dir,
        "source_job_id" => job_id,
        "transition" => transition,
    )
    atomic_toml(next_config_path, next_raw)
    decision["next_config_path"] = next_config_path
    decision["next_config_sha256"] = PB.file_sha256(next_config_path)
    decision["next_output_directory"] = next_output_directory
end

atomic_toml(decision_path, decision)
println(decision_path)
