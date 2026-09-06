using ProjectBIDMRG
using HDF5
using TOML

1 <= length(ARGS) <= 2 || error(
    "usage: validate_control.jl CONTROL.toml [--postprocess]",
)
postprocess_mode = length(ARGS) == 2
postprocess_mode && ARGS[2] != "--postprocess" && error("unknown validator mode")
record = ProjectBIDMRG.load_control(ARGS[1])
control = record.raw
schema_version = Int(control["schema_version"])
lineage = control["lineage"]
model = control["model"]
solver = control["solver"]
native = control["native_convergence"]
validation = control["validation"]
resources = control["resources"]
authorization = control["authorization"]
provenance = control["provenance"]
storage = control["storage"]

const ACCEPTED_PARENT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const FIRST_IDMRG_RESULT_SHA256 =
    "527afdf421e3411fb91f622ae0a5f8764d453f892c7752b2294913813749c8de"
const FIRST_IDMRG_SACCT_SHA256 =
    "99336db6bd57c6de322e3b7f9d10cb054a6b865397702e5b00d186a045683785"
const BENCHMARK_CONTROL_SHA256 =
    "8fb5a1c0b99e5fa3c955f9e0e914913735e08fe64e90681a648d9ca339a05110"
const BENCHMARK_THREADS_2_RESULT_SHA256 =
    "23ce74663e34fefb1b0108d136f6aef3d15519a778dae45d9b0f578bbaefa72d"
const BENCHMARK_SACCT_SHA256 =
    "5824d9e3e1a579dcf452ecbfcb4c475da13cd3f80f83c9c398f33d599d47c969"
const BENCHMARK_STEPS_SACCT_SHA256 =
    "de9eeec59e116d0085615cb7ee829d8c6631920caaf1656e6a717b9f835f5200"
const FAILED_TARGET_RESULT_SHA256 =
    "c7ef67c0e22b32d581fec9ed3d4f86b14182db15a1f80688c88fc311eb326116"
const FAILED_TARGET_ANALYSIS_SHA256 =
    "10ccb7a9dadf30d6b18d465c33dd0d418b273520fbdb1e9f46c236b1b40aab01"
const FAILED_SWEEP_JOB_ID = "57608599"
const FAILED_SWEEP_SACCT_SHA256 =
    "fc4f6830d0a18fae918f50409cce725d6fc675388657ab64a8c806411754582e"
const FAILED_SWEEP_LOG_SHA256 =
    "c91376b758a9fa143cf7e36fbb7a3d4d79688486d7e9d665c02126a17377f126"
const FAILED_SWEEP_CHARGED_NODE_HOURS = 8 / 3600 * 5 / 128
const RETRY_PACKAGE_BASENAME =
    "theta_p0p17500000_from_38312fc996fe_working_shared16g_retry_after_57608599"
const MIDPOINT_PACKAGE_BASENAME =
    "theta_p0p16250000_from_38312fc996fe_working_shared16g_after_57611537"
const MIDPOINT_PREDECESSOR_JOB_ID = "57611537"
const MIDPOINT_PREDECESSOR_CONTROL_SHA256 =
    "a3b75247770cb86a3c155d48dfecf438b1e21b98119b3b8ed2db51a4868d02de"
const MIDPOINT_PREDECESSOR_BRIDGE_SHA256 =
    "533f772c47d715535e6db1da274fb48bde5162dcb90e11d2665bdb9e89fe5b61"
const MIDPOINT_PREDECESSOR_RESULT_SHA256 =
    "03734ddbc4389a45428d69f961a0fdd0adda80567641c383d2f97998be734676"
const MIDPOINT_PREDECESSOR_LIGHTWEIGHT_SHA256 =
    "e7a488e685e68026132a3d48cec09c1e019eb777df0d09e3b93669699fa70b78"
const MIDPOINT_PREDECESSOR_CONVERSION_ANALYSIS_SHA256 =
    "37562ba47872de88494894e61fdcde9da6f67954ecdbbf83fe80dd99526c62bd"
const MIDPOINT_PREDECESSOR_FINAL_ANALYSIS_SHA256 =
    "302b6db4a8e90d568dc61c82c2f8d2b37e588fa3125b69b5cced91752b99fe47"
const MIDPOINT_PREDECESSOR_SACCT_SHA256 =
    "6888060a71a20ef0b2dbdceeb34eebc093b94dac9bf31cf79dc7dd1187172a0d"
const MIDPOINT_PREDECESSOR_LOG_SHA256 =
    "4af8d9ed4adcd9c6612344c937478eb8e25b45c8b177e989a7f1d9547340939d"
const MIDPOINT_PREDECESSOR_ELAPSED_SECONDS = 33423
const MIDPOINT_PREDECESSOR_CHARGED_NODE_HOURS = 33423 / 3600 * 5 / 128
const PROJECT_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const WORKING_POLICY_RELATIVE = "configs/phase1_idmrg_working_convergence.toml"
const WORKING_POLICY_PATH = joinpath(PROJECT_ROOT, WORKING_POLICY_RELATIVE)
const WORKING_POLICY_SHA256 =
    "a3056820571c674d1d6d450d6e44e403cd6ead3ae68709a5c5656a2dc05aa38c"

if schema_version <= 2
    lineage["parent_state_sha256"] == ACCEPTED_PARENT_SHA256 ||
        error("unpinned accepted-parent hash")
    lineage["overlap_reference_sha256"] == ACCEPTED_PARENT_SHA256 ||
        error("accepted parent and overlap reference differ")
else
    lineage["root_state_sha256"] == ACCEPTED_PARENT_SHA256 ||
        error("immutable theta/pi=0.15 lineage root changed")
    lineage["parent_state_sha256"] == ACCEPTED_PARENT_SHA256 ||
        error("first smaller-step control must retain the accepted theta/pi=0.15 parent")
    lineage["overlap_reference_sha256"] == lineage["parent_state_sha256"] ||
        error("accepted parent and overlap reference differ")
end
lineage["direction"] == "forward" || error("not forward lineage")
lineage["branch"] == "primary_forward_chi512_legacy_0p1" ||
    error("primary-forward branch label changed")
model["circumference"] == 8 && model["shift"] == 1 && model["mps_period"] == 2 ||
    error("geometry/period mismatch")
model["twist_gauge"] == "uniform" && model["u1_conserved"] == true ||
    error("gauge or U(1) mismatch")
solver["library"] == "MPSKit" && solver["library_version"] == "0.13.13" ||
    error("solver pin mismatch")
solver["algorithm"] == "one_site_idmrg" && solver["nominal_chi"] == 512 ||
    error("algorithm/chi mismatch")
native["defined_before_run"] == true || error("native convergence was not predeclared")
legacy_native_thresholds = native["environment_tolerance"] == 1e-8 &&
    native["energy_density_span_tolerance"] == 1e-9
working_native_thresholds = native["environment_tolerance"] == 1e-5 &&
    native["energy_density_span_tolerance"] == 1e-8
if working_native_thresholds
    get(native, "criterion_profile", "") == "phase1_exploratory_working_20260824" ||
        error("working native thresholds require the pinned criterion profile")
    get(native, "criterion_selected_after_job_id", "") == "57500598" ||
        error("working native thresholds require their post-job decision provenance")
    get(native, "criterion_policy_path", "") == WORKING_POLICY_RELATIVE ||
        error("working native thresholds require the pinned policy path")
    isfile(WORKING_POLICY_PATH) || error("missing working convergence policy")
    policy_sha256 = ProjectBIDMRG.file_sha256(WORKING_POLICY_PATH)
    policy_sha256 == WORKING_POLICY_SHA256 ||
        error("immutable working convergence policy changed")
    get(native, "criterion_policy_sha256", "") == policy_sha256 ||
        error("working convergence policy SHA-256 mismatch")
    working_policy = TOML.parsefile(WORKING_POLICY_PATH)
    working_policy["scope"]["profile"] == native["criterion_profile"] ||
        error("working convergence profile does not match policy")
    policy_native = working_policy["native_convergence"]
    policy_native["bond_matrix_update_norm_tolerance"] ==
        native["environment_tolerance"] ||
        error("working bond-matrix update threshold does not match policy")
    policy_native["energy_density_span_tolerance"] ==
        native["energy_density_span_tolerance"] ||
        error("working energy threshold does not match policy")
elseif !legacy_native_thresholds
    error("unsupported native convergence threshold pair")
end
native["energy_window"] == 4 || error("native energy window changed")
native["require_achieved_bond_dimension"] == 512 ||
    error("native achieved-chi guard changed")
validation["tensor_roundtrip_relative_tolerance"] == 5e-13 ||
    error("tensor round-trip tolerance changed")
validation["model_energy_density_tolerance"] == 1e-6 ||
    error("model equivalence tolerance changed")
resources["system"] == "perlmutter" && resources["constraint"] == "cpu" ||
    error("resource platform mismatch")
resources["nodes"] == 1 && resources["tasks"] == 1 ||
    error("resource shape mismatch")
resources["maximum_jobs"] == 1 || error("one-job guard changed")
if schema_version == 5
    authorization["submission_authorized"] == true ||
        error("schema-5 control lost the standing owner authorization")
    authorization["authorization_basis"] == "standing_owner_authorization_20260825" ||
        error("schema-5 standing authorization provenance changed")
else
    authorization["submission_authorized"] == false ||
        error("historical control authorization changed")
end
authorization["requires_explicit_submit_command"] == true &&
    authorization["automatic_advance_allowed"] == false ||
    error("operational submission/advance guard changed")

resolve(value) = isabspath(value) ? normpath(value) :
    normpath(joinpath(dirname(record.path), value))

numerical_seed_path = lineage["parent_state_path"]
numerical_seed_sha256 = ACCEPTED_PARENT_SHA256
storage_backend = "package_directory"
scratch_subdirectory = "none"
previous_sacct_path = "none"
previous_sacct_sha256 = "none"
previous_job_id = "none"
prior_phase1_node_hours = 0.0
phase1_ceiling_node_hours = 20.0
prior_project_node_hours = 0.0
project_ceiling_node_hours = 150.0
julia_threads = Int(
    haskey(resources, "julia_threads") ?
        resources["julia_threads"] : resources["cpus_per_task"],
)
allocation_logical_cpus = Int(
    haskey(resources, "allocation_logical_cpus") ?
        resources["allocation_logical_cpus"] : resources["cpus_per_task"],
)
solver_step_logical_cpus = Int(
    haskey(resources, "solver_step_logical_cpus") ?
        resources["solver_step_logical_cpus"] : resources["cpus_per_task"],
)
memory = String(resources["memory"])

if schema_version == 1
    lineage["use_rejected_vumps_diagnostic_as_seed"] == false ||
        error("primary control must not use the rejected VUMPS tensor as its seed")
    solver["maximum_iterations"] == 80 || error("schema-1 iteration guard changed")
    resources["time_limit"] == "06:00:00" &&
        resources["maximum_new_node_hours"] == 6.0 ||
        error("schema-1 resource guard changed")
    resources["cpus_per_task"] == 128 && julia_threads == 128 &&
        resources["qos"] == "regular" && memory == "0" ||
        error("schema-1 resource shape changed")
    storage["checkpoint_every_iterations"] == 5 ||
        error("schema-1 checkpoint cadence changed")
elseif schema_version == 2
    lineage["numerical_seed_kind"] == "rejected_nonconverged_idmrg_result" ||
        error("continuation seed must remain explicitly rejected")
    lineage["numerical_seed_sha256"] == FIRST_IDMRG_RESULT_SHA256 ||
        error("unpinned iDMRG numerical-seed hash")
    lineage["numerical_seed_native_converged"] == false ||
        error("first iDMRG result must not be relabeled converged")
    lineage["numerical_seed_branch_gate_passed"] == true ||
        error("continuation requires the recorded branch gate")
    lineage["numerical_seed_is_lineage_parent"] == false ||
        error("rejected seed must not become the lineage parent")
    numerical_seed_path = lineage["numerical_seed_path"]
    numerical_seed_sha256 = lineage["numerical_seed_sha256"]
    solver["maximum_iterations"] == 400 || error("continuation iteration guard changed")
    native["energy_density_semantics"] ==
        "MPSKit IDMRG superblock-energy increment divided by period" ||
        error("native intensive-energy semantics changed")
    resources["time_limit"] == "10:00:00" &&
        resources["maximum_new_node_hours"] == 10.0 ||
        error("continuation resource guard changed")
    resources["cpus_per_task"] == 128 && julia_threads == 128 &&
        resources["qos"] == "regular" && memory == "0" ||
        error("schema-2 resource shape changed")
    storage_backend = String(storage["backend"])
    storage_backend == "perlmutter_scratch" ||
        error("heavy continuation checkpoints must use Perlmutter scratch")
    storage["checkpoint_every_iterations"] == 20 ||
        error("continuation checkpoint cadence changed")
    storage["checkpoint_directory"] == "checkpoints" ||
        error("checkpoint leaf directory changed")
    haskey(storage, "lightweight_result_path") ||
        error("automatic lightweight result is required")
    scratch_subdirectory = String(storage["scratch_subdirectory"])
    isabspath(scratch_subdirectory) && error("scratch subdirectory must be PSCRATCH-relative")
    any(==(".."), splitpath(scratch_subdirectory)) &&
        error("scratch subdirectory may not escape PSCRATCH")

    accounting = control["accounting"]
    accounting["previous_job_id"] == "57452187" || error("previous job id changed")
    accounting["previous_sacct_sha256"] == FIRST_IDMRG_SACCT_SHA256 ||
        error("previous sacct hash changed")
    accounting["previous_job_state"] == "COMPLETED" &&
        accounting["previous_job_exit_code"] == "0:0" ||
        error("previous job was not scheduler/process successful")
    accounting["previous_job_elapsed_seconds"] == 6567 ||
        error("previous elapsed time changed")
    prior_phase1_node_hours = Float64(accounting["prior_phase1_charged_node_hours"])
    phase1_ceiling_node_hours = Float64(accounting["phase1_ceiling_node_hours"])
    prior_project_node_hours = Float64(accounting["prior_project_charged_node_hours"])
    project_ceiling_node_hours = Float64(accounting["project_ceiling_node_hours"])
    isapprox(prior_phase1_node_hours, 3.2956575527; atol=5e-10, rtol=0) ||
        error("Phase 1 reconciled charge changed")
    isapprox(prior_project_node_hours, 4.3900905527; atol=5e-10, rtol=0) ||
        error("project reconciled charge changed")
    prior_phase1_node_hours + resources["maximum_new_node_hours"] <=
        phase1_ceiling_node_hours || error("Phase 1 forecast exceeds its ceiling")
    prior_project_node_hours + resources["maximum_new_node_hours"] <=
        project_ceiling_node_hours || error("project forecast exceeds its ceiling")
    previous_sacct_path = resolve(accounting["previous_sacct_path"])
    previous_sacct_sha256 = accounting["previous_sacct_sha256"]
    previous_job_id = accounting["previous_job_id"]
    isfile(previous_sacct_path) || error("missing prior sacct evidence: $previous_sacct_path")
    ProjectBIDMRG.file_sha256(previous_sacct_path) == previous_sacct_sha256 ||
        error("prior sacct evidence SHA-256 mismatch")
elseif schema_version in (3, 4, 5)
    lineage["numerical_seed_kind"] == "accepted_parent" ||
        error("smaller-step numerical seed must be the accepted parent")
    lineage["numerical_seed_sha256"] == lineage["parent_state_sha256"] ||
        error("smaller-step numerical seed and accepted parent differ")
    lineage["numerical_seed_is_lineage_parent"] == true ||
        error("smaller-step numerical seed must be the lineage parent")
    isapprox(Float64(lineage["parent_theta_over_pi"]), 0.15; atol=1e-12, rtol=0) ||
        error("smaller-step parent theta changed")
    expected_target_theta = schema_version == 5 ? 0.1625 : 0.175
    isapprox(Float64(lineage["target_theta_over_pi"]), expected_target_theta;
        atol=1e-12, rtol=0) ||
        error("smaller-step target theta changed")
    solver["maximum_iterations"] == 400 ||
        error("smaller-step iteration guard changed")
    native["energy_density_semantics"] ==
        "MPSKit IDMRG superblock-energy increment divided by period" ||
        error("native intensive-energy semantics changed")
    if schema_version == 3
        allocation_logical_cpus == 4 && solver_step_logical_cpus == 4 &&
            julia_threads == 2 || error("benchmarked CPU/thread selection changed")
    else
        allocation_logical_cpus == 10 && solver_step_logical_cpus == 4 &&
            julia_threads == 2 ||
            error("retry allocation/solver-step CPU selection changed")
        expected_package = schema_version == 5 ?
            MIDPOINT_PACKAGE_BASENAME : RETRY_PACKAGE_BASENAME
        basename(dirname(record.path)) == expected_package ||
            error("Shared-QOS control is not in its immutable package")
    end
    resources["qos"] == "shared" && memory == "16G" ||
        error("benchmarked Shared-QOS memory selection changed")
    resources["time_limit"] == "12:00:00" &&
        resources["maximum_new_node_hours"] == 0.46875 ||
        error("smaller-step resource guard changed")
    storage_backend = String(storage["backend"])
    storage_backend == "perlmutter_scratch" ||
        error("heavy smaller-step checkpoints must use Perlmutter scratch")
    storage["checkpoint_every_iterations"] == 20 ||
        error("smaller-step checkpoint cadence changed")
    storage["checkpoint_directory"] == "checkpoints" ||
        error("checkpoint leaf directory changed")
    haskey(storage, "lightweight_result_path") ||
        error("automatic lightweight result is required")
    scratch_subdirectory = String(storage["scratch_subdirectory"])
    isabspath(scratch_subdirectory) && error("scratch subdirectory must be PSCRATCH-relative")
    any(==(".."), splitpath(scratch_subdirectory)) &&
        error("scratch subdirectory may not escape PSCRATCH")
    if schema_version in (4, 5)
        expected_package = schema_version == 5 ?
            MIDPOINT_PACKAGE_BASENAME : RETRY_PACKAGE_BASENAME
        basename(scratch_subdirectory) == expected_package ||
            error("Shared-QOS scratch directory changed")
    end

    accounting = control["accounting"]
    if schema_version == 3
        accounting["previous_job_id"] == "57576411" ||
            error("benchmark job id changed")
        accounting["previous_sacct_sha256"] == BENCHMARK_SACCT_SHA256 ||
            error("benchmark sacct hash changed")
        accounting["previous_job_state"] == "COMPLETED" &&
            accounting["previous_job_exit_code"] == "0:0" ||
            error("benchmark job was not scheduler/process successful")
        accounting["previous_job_elapsed_seconds"] == 3131 ||
            error("benchmark elapsed time changed")
        isapprox(
            Float64(accounting["previous_job_charged_node_hours"]),
            0.10871527777777777;
            atol=5e-12,
            rtol=0,
        ) || error("benchmark charge changed")
    elseif schema_version == 4
        accounting["previous_job_id"] == FAILED_SWEEP_JOB_ID ||
            error("failed predecessor job id changed")
        accounting["previous_sacct_sha256"] == FAILED_SWEEP_SACCT_SHA256 ||
            error("failed predecessor sacct hash changed")
        accounting["previous_job_state"] == "FAILED" &&
            accounting["previous_job_exit_code"] == "1:0" ||
            error("failed predecessor scheduler classification changed")
        accounting["previous_job_elapsed_seconds"] == 8 ||
            error("failed predecessor elapsed time changed")
        isapprox(
            Float64(accounting["previous_job_charged_node_hours"]),
            FAILED_SWEEP_CHARGED_NODE_HOURS;
            atol=5e-15,
            rtol=0,
        ) || error("failed predecessor charge changed")
    else
        accounting["previous_job_id"] == MIDPOINT_PREDECESSOR_JOB_ID ||
            error("midpoint predecessor job id changed")
        accounting["previous_sacct_sha256"] == MIDPOINT_PREDECESSOR_SACCT_SHA256 ||
            error("midpoint predecessor sacct hash changed")
        accounting["previous_job_state"] == "COMPLETED" &&
            accounting["previous_job_exit_code"] == "0:0" ||
            error("midpoint predecessor was not scheduler/process successful")
        accounting["previous_job_elapsed_seconds"] ==
            MIDPOINT_PREDECESSOR_ELAPSED_SECONDS ||
            error("midpoint predecessor elapsed time changed")
        isapprox(
            Float64(accounting["previous_job_charged_node_hours"]),
            MIDPOINT_PREDECESSOR_CHARGED_NODE_HOURS;
            atol=5e-15,
            rtol=0,
        ) || error("midpoint predecessor charge changed")
    end
    prior_phase1_node_hours = Float64(accounting["prior_phase1_charged_node_hours"])
    phase1_ceiling_node_hours = Float64(accounting["phase1_ceiling_node_hours"])
    prior_project_node_hours = Float64(accounting["prior_project_charged_node_hours"])
    project_ceiling_node_hours = Float64(accounting["project_ceiling_node_hours"])
    expected_phase1_node_hours = if schema_version == 5
        12.252445747144446 + MIDPOINT_PREDECESSOR_CHARGED_NODE_HOURS
    else
        12.25235894158889 +
            (schema_version == 4 ? FAILED_SWEEP_CHARGED_NODE_HOURS : 0.0)
    end
    expected_project_node_hours = if schema_version == 5
        13.346878747144446 + MIDPOINT_PREDECESSOR_CHARGED_NODE_HOURS
    else
        13.34679194158889 +
            (schema_version == 4 ? FAILED_SWEEP_CHARGED_NODE_HOURS : 0.0)
    end
    isapprox(prior_phase1_node_hours, expected_phase1_node_hours;
        atol=5e-10, rtol=0) ||
        error("Phase 1 reconciled charge changed")
    isapprox(prior_project_node_hours, expected_project_node_hours;
        atol=5e-10, rtol=0) ||
        error("project reconciled charge changed")
    prior_phase1_node_hours + resources["maximum_new_node_hours"] <=
        phase1_ceiling_node_hours || error("Phase 1 forecast exceeds its ceiling")
    prior_project_node_hours + resources["maximum_new_node_hours"] <=
        project_ceiling_node_hours || error("project forecast exceeds its ceiling")
    previous_sacct_path = resolve(accounting["previous_sacct_path"])
    previous_sacct_sha256 = accounting["previous_sacct_sha256"]
    previous_job_id = accounting["previous_job_id"]
    isfile(previous_sacct_path) || error("missing predecessor sacct evidence: $previous_sacct_path")
    ProjectBIDMRG.file_sha256(previous_sacct_path) == previous_sacct_sha256 ||
        error("predecessor sacct evidence SHA-256 mismatch")

    if schema_version == 4
        retry = control["retry_evidence"]
        retry["failed_job_id"] == FAILED_SWEEP_JOB_ID &&
            retry["failed_job_state"] == "FAILED" &&
            retry["failed_job_exit_code"] == "1:0" ||
            error("retry failure identity changed")
        retry["failed_job_elapsed_seconds"] == 8 &&
            retry["failed_job_allocated_logical_cpus"] == 10 &&
            retry["failed_job_charged_physical_cores"] == 5 ||
            error("retry failure accounting shape changed")
        isapprox(Float64(retry["failed_job_charged_node_hours"]),
            FAILED_SWEEP_CHARGED_NODE_HOURS; atol=5e-15, rtol=0) ||
            error("retry failure charge changed")
        retry["observed_slurm_cpus_per_task"] == 9 &&
            retry["observed_slurm_tres_per_task_logical_cpus"] == 4 ||
            error("retry failure CPU conflict changed")
        !Bool(retry["julia_started"]) &&
            retry["scientific_updates_completed"] == 0 ||
            error("failed retry must remain a zero-update infrastructure failure")
        retry["classification"] ==
            "slurm_allocation_step_cpu_conflict_before_julia" ||
            error("retry failure classification changed")
        retry["failed_job_sacct_sha256"] == FAILED_SWEEP_SACCT_SHA256 &&
            retry["failed_job_log_sha256"] == FAILED_SWEEP_LOG_SHA256 ||
            error("retry failure evidence hashes changed")
        failed_sacct_path = resolve(retry["failed_job_sacct_path"])
        failed_log_path = resolve(retry["failed_job_log_path"])
        failed_sacct_path == previous_sacct_path ||
            error("retry and accounting sacct paths differ")
        for (label, path, sha256) in (
            ("failed theta/pi=0.175 accounting", failed_sacct_path,
                FAILED_SWEEP_SACCT_SHA256),
            ("failed theta/pi=0.175 log", failed_log_path,
                FAILED_SWEEP_LOG_SHA256),
        )
            isfile(path) || error("missing $label evidence: $path")
            ProjectBIDMRG.file_sha256(path) == sha256 ||
                error("$label SHA-256 mismatch")
        end
        strip(read(failed_sacct_path, String)) ==
            "57608599|pb1-idmrg|FAILED|8|720|1|10|1:0" ||
            error("failed theta/pi=0.175 accounting contents changed")
        occursin(
            "SLURM_CPUS_PER_TASK=9 != SLURM_TRES_PER_TASK=cpu=4",
            read(failed_log_path, String),
        ) || error("failed theta/pi=0.175 log diagnosis changed")
    elseif schema_version == 5
        predecessor = control["predecessor_evidence"]
        predecessor["job_id"] == MIDPOINT_PREDECESSOR_JOB_ID &&
            predecessor["job_state"] == "COMPLETED" &&
            predecessor["job_exit_code"] == "0:0" ||
            error("midpoint predecessor identity changed")
        predecessor["job_elapsed_seconds"] == MIDPOINT_PREDECESSOR_ELAPSED_SECONDS &&
            predecessor["job_allocated_logical_cpus"] == 10 &&
            predecessor["job_charged_physical_cores"] == 5 ||
            error("midpoint predecessor accounting shape changed")
        isapprox(Float64(predecessor["job_charged_node_hours"]),
            MIDPOINT_PREDECESSOR_CHARGED_NODE_HOURS; atol=5e-15, rtol=0) ||
            error("midpoint predecessor charge changed")
        Bool(predecessor["native_converged"]) &&
            !Bool(predecessor["branch_accepted"]) ||
            error("midpoint predecessor classification changed")
        predecessor["classification"] ==
            "native_converged_primary_branch_overlap_rejected" ||
            error("midpoint predecessor classification label changed")
        predecessor_files = (
            ("control", "control_path", "control_sha256",
                MIDPOINT_PREDECESSOR_CONTROL_SHA256),
            ("bridge", "bridge_path", "bridge_sha256",
                MIDPOINT_PREDECESSOR_BRIDGE_SHA256),
            ("result", "result_path", "result_sha256",
                MIDPOINT_PREDECESSOR_RESULT_SHA256),
            ("lightweight archive", "lightweight_path", "lightweight_sha256",
                MIDPOINT_PREDECESSOR_LIGHTWEIGHT_SHA256),
            ("conversion analysis", "conversion_analysis_path",
                "conversion_analysis_sha256",
                MIDPOINT_PREDECESSOR_CONVERSION_ANALYSIS_SHA256),
            ("final analysis", "final_analysis_path", "final_analysis_sha256",
                MIDPOINT_PREDECESSOR_FINAL_ANALYSIS_SHA256),
            ("accounting", "sacct_path", "sacct_sha256",
                MIDPOINT_PREDECESSOR_SACCT_SHA256),
            ("log", "log_path", "log_sha256", MIDPOINT_PREDECESSOR_LOG_SHA256),
        )
        for (label, path_key, sha_key, expected_sha256) in predecessor_files
            predecessor[sha_key] == expected_sha256 ||
                error("midpoint predecessor $label digest changed")
            path = resolve(predecessor[path_key])
            isfile(path) || error("missing midpoint predecessor $label: $path")
            ProjectBIDMRG.file_sha256(path) == expected_sha256 ||
                error("midpoint predecessor $label SHA-256 mismatch")
        end
        resolve(predecessor["sacct_path"]) == previous_sacct_path ||
            error("midpoint predecessor and accounting sacct paths differ")
        strip(read(previous_sacct_path, String)) ==
            "57611537|pb1-idmrg|COMPLETED|33423|720|1|10|0:0" ||
            error("midpoint predecessor accounting contents changed")
    end

    selection = control["resource_selection"]
    selection["benchmark_control_sha256"] == BENCHMARK_CONTROL_SHA256 ||
        error("benchmark-control evidence changed")
    selection["benchmark_result_sha256"] == BENCHMARK_THREADS_2_RESULT_SHA256 ||
        error("2-thread benchmark-result evidence changed")
    selection["benchmark_steps_sacct_sha256"] == BENCHMARK_STEPS_SACCT_SHA256 ||
        error("benchmark step-accounting evidence changed")
    selection["selected_julia_threads"] == 2 ||
        error("benchmark Julia-thread selection metadata changed")
    if schema_version == 3
        selection["selected_slurm_logical_cpus"] == 4 ||
            error("benchmark selection metadata changed")
    else
        selection["selected_solver_step_logical_cpus"] == 4 &&
            selection["allocation_logical_cpus"] == 10 ||
            error("retry allocation/step selection metadata changed")
    end
    benchmark_control_path = resolve(selection["benchmark_control_path"])
    benchmark_result_path = resolve(selection["benchmark_result_path"])
    benchmark_steps_sacct_path = resolve(selection["benchmark_steps_sacct_path"])
    for (label, path, sha256) in (
        ("benchmark control", benchmark_control_path, BENCHMARK_CONTROL_SHA256),
        ("2-thread benchmark result", benchmark_result_path,
            BENCHMARK_THREADS_2_RESULT_SHA256),
        ("benchmark step accounting", benchmark_steps_sacct_path,
            BENCHMARK_STEPS_SACCT_SHA256),
    )
        isfile(path) || error("missing $label evidence: $path")
        ProjectBIDMRG.file_sha256(path) == sha256 || error("$label SHA-256 mismatch")
    end
    HDF5.h5open(benchmark_result_path, "r") do file
        String(read(file, "artifact_kind")) ==
            "project_b_mpskit_idmrg_thread_benchmark" ||
            error("unexpected benchmark result kind")
        Int(read(file, "benchmark/julia_threads")) == julia_threads ||
            error("benchmark result does not support selected Julia threads")
        Int(read(file, "benchmark/slurm_logical_cpus")) ==
            solver_step_logical_cpus ||
            error("benchmark result does not support selected Slurm CPUs")
        String(read(file, "source/benchmark_control_sha256")) ==
            BENCHMARK_CONTROL_SHA256 || error("benchmark result control lineage changed")
    end

    source_evidence = control["source_evidence"]
    expected_failed_result_sha256 = schema_version == 5 ?
        MIDPOINT_PREDECESSOR_RESULT_SHA256 : FAILED_TARGET_RESULT_SHA256
    expected_failed_analysis_sha256 = schema_version == 5 ?
        MIDPOINT_PREDECESSOR_FINAL_ANALYSIS_SHA256 : FAILED_TARGET_ANALYSIS_SHA256
    expected_failed_theta = schema_version == 5 ? 0.175 : 0.2
    expected_failed_overlap = schema_version == 5 ?
        0.9662443394038124 : 0.9662307284691443
    isapprox(Float64(source_evidence["failed_target_theta_over_pi"]),
        expected_failed_theta; atol=1e-12, rtol=0) ||
        error("failed-target theta changed")
    source_evidence["failed_target_result_sha256"] == expected_failed_result_sha256 ||
        error("failed-target result evidence changed")
    source_evidence["failed_target_analysis_sha256"] ==
        expected_failed_analysis_sha256 || error("failed-target analysis evidence changed")
    Bool(source_evidence["failed_target_working_native_converged"]) ||
        error("failed target must retain its working-native pass")
    !Bool(source_evidence["failed_target_branch_accepted"]) ||
        error("failed target must remain branch-rejected")
    isapprox(
        Float64(source_evidence["failed_target_parent_overlap_per_site"]),
        expected_failed_overlap;
        atol=5e-15,
        rtol=0,
    ) || error("failed-target parent overlap changed")
    failed_result_path = resolve(source_evidence["failed_target_result_path"])
    failed_analysis_path = resolve(source_evidence["failed_target_analysis_path"])
    for (label, path, sha256) in (
        ("failed-target result", failed_result_path, expected_failed_result_sha256),
        ("failed-target analysis", failed_analysis_path, expected_failed_analysis_sha256),
    )
        isfile(path) || error("missing $label evidence: $path")
        ProjectBIDMRG.file_sha256(path) == sha256 || error("$label SHA-256 mismatch")
    end
    HDF5.h5open(failed_analysis_path, "r") do file
        Bool(read(file, "optimizer/converged")) ||
            error("failed target no longer passes the working native gate")
        !Bool(read(file, "continuation_accepted")) ||
            error("failed target no longer fails branch promotion")
        Float64(read(file, "continuation/overlap_per_site")) < 0.99 ||
            error("failed target no longer fails the parent-overlap gate")
        String(read(file, "lineage/root_state_sha256")) == ACCEPTED_PARENT_SHA256 ||
            error("failed-target lineage root changed")
        if schema_version == 5
            !Bool(read(file, "validation/common_vumps_projected_residual_ran")) ||
                error("failed midpoint target must retain its skipped VUMPS probe")
        end
    end
end

project_root = normpath(joinpath(@__DIR__, "../.."))
provenance_paths = Dict(
    "idmrg_manifest_sha256" => joinpath(project_root, "idmrg/Manifest.toml"),
    "solver_module_sha256" => joinpath(project_root, "idmrg/src/ProjectBIDMRG.jl"),
    "root_manifest_sha256" => joinpath(project_root, "Manifest.toml"),
    "analyzer_sha256" => joinpath(project_root, "scripts/analyze_phase1_idmrg_result.jl"),
    "launcher_sha256" => joinpath(project_root, "slurm/run_idmrg_cpu.sh"),
    "decision_document_sha256" =>
        joinpath(project_root, "docs/PHASE1_IDMRG_LIBRARY_DECISION.md"),
)
if schema_version == 2
    merge!(provenance_paths, Dict(
        "resume_preparer_sha256" =>
            joinpath(project_root, "scripts/prepare_phase1_idmrg_resume.jl"),
        "storage_document_sha256" =>
            joinpath(project_root, "docs/PHASE1_IDMRG_STORAGE.md"),
    ))
elseif schema_version in (3, 4, 5)
    merge!(provenance_paths, Dict(
        "sweep_step_preparer_sha256" =>
            joinpath(project_root, "scripts/prepare_phase1_idmrg_sweep_step.jl"),
        "storage_document_sha256" =>
            joinpath(project_root, "docs/PHASE1_IDMRG_STORAGE.md"),
        "working_policy_sha256" => WORKING_POLICY_PATH,
    ))
end
for (key, path) in provenance_paths
    expected = lowercase(provenance[key])
    occursin(r"^[0-9a-f]{64}$", expected) ||
        error("invalid pinned provenance digest for $path")
    if !postprocess_mode
        ProjectBIDMRG.file_sha256(path) == expected ||
            error("pinned provenance mismatch for $path")
    end
end

fields = (
    ProjectBIDMRG.file_sha256(record.path),
    ProjectBIDMRG.file_sha256(record.bridge_path),
    lineage["parent_state_path"],
    lineage["parent_state_sha256"],
    numerical_seed_path,
    numerical_seed_sha256,
    resolve(storage["result_path"]),
    haskey(storage, "lightweight_result_path") ?
        resolve(storage["lightweight_result_path"]) : "none",
    storage_backend,
    scratch_subdirectory,
    storage_backend == "package_directory" ?
        resolve(storage["checkpoint_directory"]) : String(storage["checkpoint_directory"]),
    string(lineage["parent_theta_over_pi"]),
    string(lineage["target_theta_over_pi"]),
    string(resources["nodes"]),
    string(allocation_logical_cpus),
    string(solver_step_logical_cpus),
    string(julia_threads),
    memory,
    resources["time_limit"],
    resources["qos"],
    string(resources["maximum_new_node_hours"]),
    string(resources["maximum_jobs"]),
    string(prior_phase1_node_hours),
    string(phase1_ceiling_node_hours),
    string(prior_project_node_hours),
    string(project_ceiling_node_hours),
    previous_sacct_path,
    previous_sacct_sha256,
    previous_job_id,
)
println(join(fields, '\t'))
