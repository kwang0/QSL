using Dates
using HDF5
using TOML
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const ACCEPTED_PARENT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const FIRST_RESULT_SHA256 =
    "527afdf421e3411fb91f622ae0a5f8764d453f892c7752b2294913813749c8de"
const FIRST_CONTROL_SHA256 =
    "3eb0d1c9209c978f277b6704de39bc899cf2a8abce0c84f950fb204febca8369"
const FIRST_BRIDGE_SHA256 =
    "df1e402f0922937da0e266427a2bae7ce7de0fc844884ae3f747f5410fcd7d01"
const FIRST_ANALYSIS_SHA256 =
    "84730a3d0e67f2c4a6e09372c407a9d5d0e806d0357d8d6c6b712cf6aafb7a2c"
const FIRST_SACCT_SHA256 =
    "99336db6bd57c6de322e3b7f9d10cb054a6b865397702e5b00d186a045683785"
const FIRST_LOG_SHA256 =
    "745c02a1bc23cf20c2071cd05d9d97a84b45ac212458e00a37e8cd9df5c6af8f"
const PACKAGE_NAME = "theta_p0p20000000_resume_from_527afdf421e3"

length(ARGS) == 4 || error(
    "usage: prepare_phase1_idmrg_resume.jl FIRST_PACKAGE ACCEPTED_PARENT.h5 " *
    "OUTPUT_DIRECTORY PERLMUTTER_PROJECT_ROOT",
)

project_root = normpath(joinpath(@__DIR__, ".."))
working_policy_path = joinpath(
    project_root,
    "configs",
    "phase1_idmrg_working_convergence.toml",
)
working_policy = TOML.parsefile(working_policy_path)
working_policy["artifact_kind"] ==
    "project_b_phase1_idmrg_working_convergence_policy" ||
    error("unexpected working-convergence policy kind")
working_scope = working_policy["scope"]
working_native = working_policy["native_convergence"]
working_scope["profile"] == "phase1_exploratory_working_20260824" ||
    error("working-convergence profile changed")
working_policy_sha256 = PB.file_sha256(working_policy_path)
first_package = abspath(ARGS[1])
accepted_parent_path = abspath(ARGS[2])
output_directory = abspath(ARGS[3])
perlmutter_root = normpath(ARGS[4])
basename(output_directory) == PACKAGE_NAME || error(
    "successor directory must be named $PACKAGE_NAME",
)
isdir(output_directory) && !isempty(readdir(output_directory)) && error(
    "refusing to populate nonempty successor directory: $output_directory",
)
isabspath(perlmutter_root) || error("Perlmutter project root must be absolute")

function project_relative(path)
    relative = relpath(abspath(path), project_root)
    any(==(".."), splitpath(relative)) && error("path is outside the project: $path")
    return relative
end
perlmutter_path(path) = joinpath(perlmutter_root, project_relative(path))

first_control_path = joinpath(first_package, "phase1_idmrg_control.toml")
first_bridge_path = joinpath(first_package, "accepted_parent_to_mpskit_bridge.h5")
first_result_path = joinpath(first_package, "idmrg_result_bridge.h5")
first_analysis_path = joinpath(
    first_package,
    "analysis/analysis_idmrg_theta_p0p20000000_chi512_rejected_527afdf421e3.h5",
)
first_sacct_path = joinpath(first_package, "sacct-57452187.tsv")
first_log_path = joinpath(first_package, "logs/idmrg-57452187.out")
for (path, expected, label) in (
    (accepted_parent_path, ACCEPTED_PARENT_SHA256, "accepted parent"),
    (first_control_path, FIRST_CONTROL_SHA256, "first control"),
    (first_bridge_path, FIRST_BRIDGE_SHA256, "first bridge"),
    (first_result_path, FIRST_RESULT_SHA256, "first result"),
    (first_analysis_path, FIRST_ANALYSIS_SHA256, "first analysis"),
    (first_sacct_path, FIRST_SACCT_SHA256, "first sacct evidence"),
    (first_log_path, FIRST_LOG_SHA256, "first scheduler log"),
)
    isfile(path) || error("missing $label: $path")
    PB.file_sha256(path) == expected || error("$label SHA-256 mismatch")
end

first_control = TOML.parsefile(first_control_path)
first_control["lineage"]["parent_state_sha256"] == ACCEPTED_PARENT_SHA256 ||
    error("first control changed its accepted parent")

result = h5open(first_result_path, "r") do file
    String(read(file, "artifact_kind")) == "project_b_mpskit_idmrg_result_bridge" ||
        error("unexpected first-result artifact kind")
    String(read(file, "lineage/parent_state_sha256")) == ACCEPTED_PARENT_SHA256 ||
        error("first result changed its accepted parent")
    !Bool(read(file, "optimizer/converged")) ||
        error("first result must remain explicitly nonconverged")
    iterations = Int(read(file, "optimizer/iterations"))
    iterations == 80 || error("first result iteration count changed")
    environment_error = Float64(read(file, "optimizer/final_environment_error"))
    isapprox(environment_error, 3.781953625219294e-5; atol=1e-16, rtol=1e-12) ||
        error("first result environment error changed")
    intensive_energy = Float64.(read(file, "optimizer/history/energy_density_delta"))
    energy_span = maximum(@view intensive_energy[(end - 3):end]) -
        minimum(@view intensive_energy[(end - 3):end])
    isapprox(energy_span, 6.930349627509713e-9; atol=1e-16, rtol=1e-10) ||
        error("corrected first-result energy span changed")
    tensors = map(1:2) do site
        prefix = "state/site_$site"
        (;
            AL=ComplexF64.(read(file, "$prefix/AL")),
            left_charges=Int.(read(file, "$prefix/left_charges")),
            physical_charges=Int.(read(file, "$prefix/physical_charges")),
            right_charges=Int.(read(file, "$prefix/right_charges")),
        )
    end
    return (; iterations, environment_error, energy_span, intensive_energy, tensors)
end

analysis = h5open(first_analysis_path, "r") do file
    String(read(file, "artifact_kind")) == "project_b_idmrg_analysis" ||
        error("unexpected analysis artifact kind")
    String(read(file, "source/result_bridge_sha256")) == FIRST_RESULT_SHA256 ||
        error("analysis does not describe the pinned first result")
    !Bool(read(file, "continuation_accepted")) ||
        error("first result must remain rejected")
    !Bool(read(file, "optimizer/converged")) ||
        error("corrected native convergence must remain false")
    Bool(read(file, "continuation/continuity_passed")) ||
        error("first result failed the primary-branch continuity gate")
    overlap = Float64(read(file, "continuation/overlap_per_site"))
    overlap >= 0.99 || error("first result failed the parent-overlap gate")
    before = Int.(read(file, "sectors/before_multiplicity"))
    after = Int.(read(file, "sectors/after_multiplicity"))
    before == after || error("first result changed U(1) sector multiplicities")
    return (;
        energy_density=Float64(read(file, "observables/energy_density")),
        overlap_per_site=overlap,
        mean_entropy_delta=Float64(read(file, "continuation/mean_entropy_delta")),
        maximum_cut_entropy_jump=Float64(read(
            file,
            "continuation/maximum_cut_entropy_jump",
        )),
        magnetization_rms_jump=Float64(read(
            file,
            "continuation/magnetization_rms_jump",
        )),
        energy_term_rms_jump=Float64(read(
            file,
            "continuation/energy_term_rms_jump",
        )),
    )
end
isapprox(analysis.energy_density, -0.5071807876072965; atol=5e-13, rtol=0) ||
    error("independently analyzed seed energy changed")

source_model = h5open(first_bridge_path, "r") do file
    paths = (
        "model/bonds/family",
        "model/bonds/source_site",
        "model/bonds/target_site",
        "model/bonds/coupling",
        "model/bonds/anisotropy",
        "model/bonds/twist_charge",
    )
    return Dict(path => read(file, path) for path in paths)
end

mkpath(output_directory)
bridge_path = joinpath(output_directory, "rejected_idmrg_seed_to_mpskit_bridge.h5")
try
    h5open(bridge_path * ".tmp", "w") do file
        file["schema_version"] = 2
        file["artifact_kind"] = "project_b_itensor_mpskit_bridge"
        file["created_at_utc"] = string(now(UTC))
        file["lineage/branch"] = "primary_forward_chi512_legacy_0p1"
        file["lineage/direction"] = "forward"
        file["lineage/parent_state_path"] =
            first_control["lineage"]["parent_state_path"]
        file["lineage/parent_state_sha256"] = ACCEPTED_PARENT_SHA256
        file["lineage/parent_theta_over_pi"] = 0.15
        file["lineage/numerical_seed_kind"] = "rejected_nonconverged_idmrg_result"
        file["lineage/numerical_seed_path"] = perlmutter_path(first_result_path)
        file["lineage/numerical_seed_sha256"] = FIRST_RESULT_SHA256
        file["lineage/numerical_seed_theta_over_pi"] = 0.2
        file["lineage/numerical_seed_is_lineage_parent"] = false
        file["lineage/numerical_seed_analysis_path"] =
            perlmutter_path(first_analysis_path)
        file["lineage/numerical_seed_analysis_sha256"] = FIRST_ANALYSIS_SHA256
        file["geometry/circumference"] = 8
        file["geometry/shift"] = 1
        file["geometry/mps_period"] = 2
        file["model/J1"] = 1.0
        file["model/J2"] = 0.12
        file["model/Delta1"] = 1.0
        file["model/Delta2"] = 1.0
        file["model/Bz"] = 0.0
        file["model/twist_gauge"] = "uniform"
        file["model/target_theta_over_pi"] = 0.2
        for (path, value) in source_model
            file[path] = value
        end
        file["validation/seed_energy_density_at_target"] = analysis.energy_density
        file["validation/conversion_roundtrip_tolerance"] = 5e-13
        file["validation/model_energy_density_tolerance"] = 1e-6
        file["validation/source_native_converged"] = false
        file["validation/source_final_environment_error"] = result.environment_error
        file["validation/source_final_energy_density_span"] = result.energy_span
        file["validation/source_parent_overlap_per_site"] = analysis.overlap_per_site
        for site in 1:2
            tensor = result.tensors[site]
            prefix = "state/site_$site"
            file["$prefix/AL"] = tensor.AL
            file["$prefix/left_charges"] = tensor.left_charges
            file["$prefix/physical_charges"] = tensor.physical_charges
            file["$prefix/right_charges"] = tensor.right_charges
        end
    end
    mv(bridge_path * ".tmp", bridge_path)
catch
    isfile(bridge_path * ".tmp") && rm(bridge_path * ".tmp"; force=true)
    rethrow()
end
bridge_sha256 = PB.file_sha256(bridge_path)

relative_sacct = relpath(first_sacct_path, output_directory)
control = Dict{String,Any}(
    "artifact_kind" => "project_b_phase1_idmrg_control",
    "schema_version" => 2,
    "created_at_utc" => string(now(UTC)),
    "bridge" => Dict(
        "path" => basename(bridge_path),
        "sha256" => bridge_sha256,
    ),
    "lineage" => Dict(
        "branch" => "primary_forward_chi512_legacy_0p1",
        "direction" => "forward",
        "parent_state_path" => first_control["lineage"]["parent_state_path"],
        "parent_state_sha256" => ACCEPTED_PARENT_SHA256,
        "parent_theta_over_pi" => 0.15,
        "target_theta_over_pi" => 0.2,
        "overlap_reference_sha256" => ACCEPTED_PARENT_SHA256,
        "numerical_seed_kind" => "rejected_nonconverged_idmrg_result",
        "numerical_seed_path" => perlmutter_path(first_result_path),
        "numerical_seed_sha256" => FIRST_RESULT_SHA256,
        "numerical_seed_theta_over_pi" => 0.2,
        "numerical_seed_analysis_path" => perlmutter_path(first_analysis_path),
        "numerical_seed_analysis_sha256" => FIRST_ANALYSIS_SHA256,
        "numerical_seed_native_converged" => false,
        "numerical_seed_branch_gate_passed" => true,
        "numerical_seed_is_lineage_parent" => false,
    ),
    "model" => Dict(
        "circumference" => 8,
        "shift" => 1,
        "mps_period" => 2,
        "J1" => 1.0,
        "J2" => 0.12,
        "Delta1" => 1.0,
        "Delta2" => 1.0,
        "Bz" => 0.0,
        "twist_gauge" => "uniform",
        "u1_conserved" => true,
    ),
    "solver" => Dict(
        "library" => "MPSKit",
        "library_version" => "0.13.13",
        "algorithm" => "one_site_idmrg",
        "nominal_chi" => 512,
        "maximum_iterations" => 400,
        "verbosity" => 2,
    ),
    "native_convergence" => Dict(
        "defined_before_run" => true,
        "minimum_iterations" => 4,
        "environment_tolerance" =>
            Float64(working_native["bond_matrix_update_norm_tolerance"]),
        "energy_window" => 4,
        "energy_density_span_tolerance" =>
            Float64(working_native["energy_density_span_tolerance"]),
        "criterion_profile" => String(working_scope["profile"]),
        "criterion_selected_after_job_id" =>
            String(working_scope["applies_to_controls_prepared_after_job_id"]),
        "criterion_policy_path" => relpath(working_policy_path, project_root),
        "criterion_policy_sha256" => working_policy_sha256,
        "energy_density_semantics" =>
            "MPSKit IDMRG superblock-energy increment divided by period",
        "discarded_weight_semantics" =>
            "exactly zero for one-site fixed-space iDMRG; not a VUMPS residual",
        "require_achieved_bond_dimension" => 512,
    ),
    "validation" => Dict(
        "tensor_roundtrip_relative_tolerance" => 5e-13,
        "model_energy_density_tolerance" => 1e-6,
    ),
    "acceptance" => Dict(
        "minimum_parent_overlap_per_site" => 0.99,
        "overlap_tolerance" => 1e-8,
        "overlap_krylov_dimension" => 16,
        "require_common_observables" => true,
        "require_sector_resolved_virtual_diagnostics" => true,
        "accept_lower_energy_without_branch_gates" => false,
    ),
    "storage" => Dict(
        "backend" => "perlmutter_scratch",
        "scratch_subdirectory" => joinpath(
            "QSL/project_b_flux_dimensional_reduction/phase1_idmrg/yc8_1",
            PACKAGE_NAME,
        ),
        "checkpoint_every_iterations" => 20,
        "checkpoint_directory" => "checkpoints",
        "result_path" => "idmrg_result_bridge.h5",
        "lightweight_result_path" => "idmrg_result_lightweight.h5",
        "final_state_directory" => "analysis",
    ),
    "resources" => Dict(
        "system" => "perlmutter",
        "constraint" => "cpu",
        "qos" => "regular",
        "nodes" => 1,
        "tasks" => 1,
        "cpus_per_task" => 128,
        "memory" => "0",
        "time_limit" => "10:00:00",
        "maximum_new_node_hours" => 10.0,
        "maximum_jobs" => 1,
    ),
    "accounting" => Dict(
        "previous_job_id" => "57452187",
        "previous_job_state" => "COMPLETED",
        "previous_job_exit_code" => "0:0",
        "previous_job_elapsed_seconds" => 6567,
        "previous_job_charged_node_hours" => 6567 / 3600,
        "previous_sacct_path" => relative_sacct,
        "previous_sacct_sha256" => FIRST_SACCT_SHA256,
        "prior_phase1_charged_node_hours" => 3.2956575527,
        "phase1_ceiling_node_hours" => 20.0,
        "prior_project_charged_node_hours" => 4.3900905527,
        "project_ceiling_node_hours" => 150.0,
    ),
    "source_evidence" => Dict(
        "first_control_sha256" => FIRST_CONTROL_SHA256,
        "first_bridge_sha256" => FIRST_BRIDGE_SHA256,
        "first_result_sha256" => FIRST_RESULT_SHA256,
        "first_analysis_sha256" => FIRST_ANALYSIS_SHA256,
        "first_sacct_sha256" => FIRST_SACCT_SHA256,
        "first_log_sha256" => FIRST_LOG_SHA256,
        "first_final_environment_error" => result.environment_error,
        "first_final_energy_density_span" => result.energy_span,
        "first_parent_overlap_per_site" => analysis.overlap_per_site,
        "first_seed_energy_density" => analysis.energy_density,
        "first_mean_entropy_delta" => analysis.mean_entropy_delta,
        "first_maximum_cut_entropy_jump" => analysis.maximum_cut_entropy_jump,
        "first_magnetization_rms_jump" => analysis.magnetization_rms_jump,
        "first_energy_term_rms_jump" => analysis.energy_term_rms_jump,
    ),
    "authorization" => Dict(
        "submission_authorized" => false,
        "requires_explicit_submit_command" => true,
        "automatic_advance_allowed" => false,
    ),
    "provenance" => Dict(
        "idmrg_manifest_sha256" => PB.file_sha256(joinpath(project_root, "idmrg/Manifest.toml")),
        "solver_module_sha256" =>
            PB.file_sha256(joinpath(project_root, "idmrg/src/ProjectBIDMRG.jl")),
        "root_manifest_sha256" => PB.file_sha256(joinpath(project_root, "Manifest.toml")),
        "analyzer_sha256" => PB.file_sha256(
            joinpath(project_root, "scripts/analyze_phase1_idmrg_result.jl"),
        ),
        "launcher_sha256" =>
            PB.file_sha256(joinpath(project_root, "slurm/run_idmrg_cpu.sh")),
        "decision_document_sha256" => PB.file_sha256(
            joinpath(project_root, "docs/PHASE1_IDMRG_LIBRARY_DECISION.md"),
        ),
        "resume_preparer_sha256" => PB.file_sha256(@__FILE__),
        "storage_document_sha256" => PB.file_sha256(
            joinpath(project_root, "docs/PHASE1_IDMRG_STORAGE.md"),
        ),
    ),
)
control_path = joinpath(output_directory, "phase1_idmrg_control.toml")
open(control_path, "w") do io
    TOML.print(io, control; sorted=true)
end

println("Wrote rejected-seed bridge: $bridge_path")
println("Bridge SHA-256: $bridge_sha256")
println("Wrote guarded continuation control: $control_path")
println("Control SHA-256: $(PB.file_sha256(control_path))")
println("Heavy checkpoints are routed to PSCRATCH; home receives a lightweight archive.")
println("Submission authorization remains false; no job was submitted.")
