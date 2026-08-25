using Dates
using HDF5
using ITensors
using ITensorMPS
using ITensorInfiniteMPS
using SHA
using TOML
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const ACCEPTED_PARENT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const REJECTED_DIAGNOSTIC_SHA256 =
    "f59dd18f29004d259a3d94e7bedadd99a7fcb88b1ba960fb7e357dd8e645e7c0"
const TARGET_THETA_OVER_PI = 0.2
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const WORKING_CONVERGENCE_POLICY_PATH = joinpath(
    PROJECT_ROOT,
    "configs",
    "phase1_idmrg_working_convergence.toml",
)

working_policy = TOML.parsefile(WORKING_CONVERGENCE_POLICY_PATH)
working_policy["artifact_kind"] ==
    "project_b_phase1_idmrg_working_convergence_policy" ||
    error("unexpected working-convergence policy kind")
working_scope = working_policy["scope"]
working_native = working_policy["native_convergence"]
working_scope["profile"] == "phase1_exploratory_working_20260824" ||
    error("working-convergence profile changed")
working_policy_sha256 = PB.file_sha256(WORKING_CONVERGENCE_POLICY_PATH)

length(ARGS) == 4 || error(
    "usage: prepare_phase1_idmrg_control.jl ACCEPTED_PARENT.h5 " *
    "REJECTED_DIAGNOSTIC.h5 OUTPUT_DIRECTORY PERLMUTTER_PROJECT_ROOT",
)

parent_path = abspath(ARGS[1])
rejected_path = abspath(ARGS[2])
output_directory = abspath(ARGS[3])
perlmutter_root = normpath(ARGS[4])
isdir(output_directory) && !isempty(readdir(output_directory)) && error(
    "refusing to populate nonempty control directory: $output_directory",
)
PB.file_sha256(parent_path) == ACCEPTED_PARENT_SHA256 ||
    error("accepted-parent SHA-256 mismatch")
PB.file_sha256(rejected_path) == REJECTED_DIAGNOSTIC_SHA256 ||
    error("rejected-diagnostic SHA-256 mismatch")

parent = PB.read_state_file(parent_path)
rejected = PB.read_state_file(rejected_path)
parent.schema_version >= 7 || error("accepted parent is older than schema 7")
parent.converged && parent.continuation_accepted ||
    error("pinned parent is not accepted and converged")
isapprox(parent.theta_over_pi, 0.15; atol=1e-12, rtol=0) ||
    error("pinned parent is not theta/pi=0.15")
parent.circumference == 8 && parent.shift == 1 || error("parent is not YC8-1")
parent.mps_period == 2 || error("parent does not use period 2")
parent.twist_gauge === :uniform || error("parent does not use the uniform twist gauge")
parent.branch == "primary_forward_chi512_legacy_0p1" || error("wrong primary branch")
parent.direction === :forward || error("parent is not forward lineage")
parent.maxlinkdim == 512 || error("parent is not chi 512")
parent.J1 == 1.0 && parent.J2 == 0.12 && parent.Delta1 == 1.0 &&
    parent.Delta2 == 1.0 && parent.Bz == 0.0 || error("parent model mismatch")
!rejected.converged && !rejected.continuation_accepted ||
    error("theta/pi=0.2 diagnostic is no longer rejected")
isapprox(rejected.theta_over_pi, TARGET_THETA_OVER_PI; atol=1e-12, rtol=0) ||
    error("diagnostic is not theta/pi=0.2")
rejected.parent_state_sha256 == ACCEPTED_PARENT_SHA256 ||
    error("rejected diagnostic does not descend from the accepted parent")

function tensor_indices(tensor)
    physical = only(filter(index -> hastags(index, "Site"), inds(tensor)))
    links = filter(index -> hastags(index, "Link"), inds(tensor))
    left = only(filter(index -> dir(index) == ITensors.Out, links))
    right = only(filter(index -> dir(index) == ITensors.In, links))
    return left, physical, right
end

function basis_charges(index)
    charges = Int[]
    for (qn, multiplicity) in space(index)
        append!(charges, fill(Int(val(qn, "Sz")), Int(multiplicity)))
    end
    length(charges) == dim(index) || error("QN multiplicities do not sum to index size")
    return charges
end

geometry = PB.YCGeometry(8, 1)
model = PB.ModelSettings(
    geometry=geometry,
    J1=1.0,
    J2=0.12,
    Delta1=1.0,
    Delta2=1.0,
    Bz=0.0,
    twist_gauge=:uniform,
    mps_period=2,
)
target_hamiltonian = PB.build_hamiltonian(
    model,
    siteinds(only, parent.psi),
    TARGET_THETA_OVER_PI,
)
parent_target_observables = PB.local_observables(parent.psi, target_hamiltonian)
bonds = PB.unit_cell_bonds(geometry; period=2)

mkpath(output_directory)
bridge_path = joinpath(output_directory, "accepted_parent_to_mpskit_bridge.h5")
ispath(bridge_path) && error("refusing to overwrite bridge: $bridge_path")
try
HDF5.h5open(bridge_path * ".tmp", "w") do file
    file["schema_version"] = 1
    file["artifact_kind"] = "project_b_itensor_mpskit_bridge"
    file["created_at_utc"] = string(now(UTC))
    file["lineage/branch"] = parent.branch
    file["lineage/direction"] = string(parent.direction)
    file["lineage/parent_state_path"] = parent_path
    file["lineage/parent_state_sha256"] = ACCEPTED_PARENT_SHA256
    file["lineage/parent_theta_over_pi"] = parent.theta_over_pi
    file["lineage/rejected_diagnostic_path"] = rejected_path
    file["lineage/rejected_diagnostic_sha256"] = REJECTED_DIAGNOSTIC_SHA256
    file["lineage/rejected_diagnostic_is_seed"] = false
    file["geometry/circumference"] = 8
    file["geometry/shift"] = 1
    file["geometry/mps_period"] = 2
    file["model/J1"] = 1.0
    file["model/J2"] = 0.12
    file["model/Delta1"] = 1.0
    file["model/Delta2"] = 1.0
    file["model/Bz"] = 0.0
    file["model/twist_gauge"] = "uniform"
    file["model/target_theta_over_pi"] = TARGET_THETA_OVER_PI
    file["model/bonds/family"] = string.([bond.family for bond in bonds])
    file["model/bonds/source_site"] = [bond.source_site for bond in bonds]
    file["model/bonds/target_site"] = [bond.target_site for bond in bonds]
    file["model/bonds/coupling"] = [bond.family === :NN ? 1.0 : 0.12 for bond in bonds]
    file["model/bonds/anisotropy"] = ones(length(bonds))
    file["model/bonds/twist_charge"] =
        [PB.bond_twist_charge(bond, geometry, :uniform) for bond in bonds]
    file["validation/parent_energy_density_at_target"] =
        parent_target_observables.energy_density
    file["validation/conversion_roundtrip_tolerance"] = 5e-13
    file["validation/model_energy_density_tolerance"] = 1e-6
    for site in 1:2
        tensor = parent.psi.AL[site]
        left, physical, right = tensor_indices(tensor)
        prefix = "state/site_$site"
        file["$prefix/AL"] = Array(tensor, left, physical, right)
        file["$prefix/left_charges"] = basis_charges(left)
        file["$prefix/physical_charges"] = basis_charges(physical)
        file["$prefix/right_charges"] = basis_charges(right)
    end
end
mv(bridge_path * ".tmp", bridge_path)
catch
    isfile(bridge_path * ".tmp") && rm(bridge_path * ".tmp"; force=true)
    rethrow()
end
bridge_sha256 = PB.file_sha256(bridge_path)

perlmutter_control_directory = joinpath(
    perlmutter_root,
    "output/phase1_idmrg/yc8_1/theta_p0p20000000_from_38312fc996fe",
)
control = Dict{String,Any}(
    "artifact_kind" => "project_b_phase1_idmrg_control",
    "schema_version" => 1,
    "created_at_utc" => string(now(UTC)),
    "bridge" => Dict(
        "path" => basename(bridge_path),
        "sha256" => bridge_sha256,
    ),
    "lineage" => Dict(
        "branch" => parent.branch,
        "direction" => "forward",
        "parent_state_path" => joinpath(perlmutter_root, relpath(parent_path, pwd())),
        "parent_state_sha256" => ACCEPTED_PARENT_SHA256,
        "parent_theta_over_pi" => 0.15,
        "target_theta_over_pi" => TARGET_THETA_OVER_PI,
        "overlap_reference_sha256" => ACCEPTED_PARENT_SHA256,
        "rejected_vumps_diagnostic_path" =>
            joinpath(perlmutter_root, relpath(rejected_path, pwd())),
        "rejected_vumps_diagnostic_sha256" => REJECTED_DIAGNOSTIC_SHA256,
        "use_rejected_vumps_diagnostic_as_seed" => false,
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
        "maximum_iterations" => 80,
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
        "criterion_policy_path" => relpath(
            WORKING_CONVERGENCE_POLICY_PATH,
            PROJECT_ROOT,
        ),
        "criterion_policy_sha256" => working_policy_sha256,
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
        "checkpoint_every_iterations" => 5,
        "checkpoint_directory" => "checkpoints",
        "result_path" => "idmrg_result_bridge.h5",
        "final_state_directory" => "states",
    ),
    "resources" => Dict(
        "system" => "perlmutter",
        "constraint" => "cpu",
        "qos" => "regular",
        "nodes" => 1,
        "tasks" => 1,
        "cpus_per_task" => 128,
        "memory" => "0",
        "time_limit" => "06:00:00",
        "maximum_new_node_hours" => 6.0,
        "maximum_jobs" => 1,
    ),
    "authorization" => Dict(
        "submission_authorized" => false,
        "requires_explicit_submit_command" => true,
        "automatic_advance_allowed" => false,
    ),
    "provenance" => Dict(
        "idmrg_manifest_sha256" => PB.file_sha256(joinpath(pwd(), "idmrg/Manifest.toml")),
        "solver_module_sha256" =>
            PB.file_sha256(joinpath(pwd(), "idmrg/src/ProjectBIDMRG.jl")),
        "root_manifest_sha256" => PB.file_sha256(joinpath(pwd(), "Manifest.toml")),
        "analyzer_sha256" =>
            PB.file_sha256(joinpath(pwd(), "scripts/analyze_phase1_idmrg_result.jl")),
        "launcher_sha256" => PB.file_sha256(joinpath(pwd(), "slurm/run_idmrg_cpu.sh")),
        "decision_document_sha256" => PB.file_sha256(
            joinpath(pwd(), "docs/PHASE1_IDMRG_LIBRARY_DECISION.md"),
        ),
    ),
)
control_path = joinpath(output_directory, "phase1_idmrg_control.toml")
ispath(control_path) && error("refusing to overwrite control: $control_path")
open(control_path, "w") do io
    TOML.print(io, control; sorted=true)
end

println("Wrote immutable bridge: $bridge_path")
println("Bridge SHA-256: $bridge_sha256")
println("Wrote guarded control: $control_path")
println("Control SHA-256: $(PB.file_sha256(control_path))")
println("Submission authorization remains false; no job was submitted.")
