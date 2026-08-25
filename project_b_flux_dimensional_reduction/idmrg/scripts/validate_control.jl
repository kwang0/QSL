using ProjectBIDMRG
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
const PROJECT_ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const WORKING_POLICY_RELATIVE = "configs/phase1_idmrg_working_convergence.toml"
const WORKING_POLICY_PATH = joinpath(PROJECT_ROOT, WORKING_POLICY_RELATIVE)

lineage["parent_state_sha256"] == ACCEPTED_PARENT_SHA256 ||
    error("unpinned accepted-parent hash")
lineage["overlap_reference_sha256"] == ACCEPTED_PARENT_SHA256 ||
    error("accepted parent and overlap reference differ")
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
resources["nodes"] == 1 && resources["tasks"] == 1 &&
    resources["cpus_per_task"] == 128 || error("resource shape mismatch")
resources["maximum_jobs"] == 1 || error("one-job guard changed")
authorization["submission_authorized"] == false ||
    error("control artifact must not pre-authorize submission")
authorization["requires_explicit_submit_command"] == true &&
    authorization["automatic_advance_allowed"] == false ||
    error("submission authorization guard changed")

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

if schema_version == 1
    lineage["use_rejected_vumps_diagnostic_as_seed"] == false ||
        error("primary control must not use the rejected VUMPS tensor as its seed")
    solver["maximum_iterations"] == 80 || error("schema-1 iteration guard changed")
    resources["time_limit"] == "06:00:00" &&
        resources["maximum_new_node_hours"] == 6.0 ||
        error("schema-1 resource guard changed")
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
    string(resources["nodes"]),
    string(resources["cpus_per_task"]),
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
