using Dates
using HDF5
using ITensors
using ITensorMPS
using ITensorInfiniteMPS
using TOML
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const LINEAGE_ROOT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const WORKING_POLICY_SHA256 =
    "a3056820571c674d1d6d450d6e44e403cd6ead3ae68709a5c5656a2dc05aa38c"
const FAILED_TARGET_RESULT_SHA256 =
    "c7ef67c0e22b32d581fec9ed3d4f86b14182db15a1f80688c88fc311eb326116"
const FAILED_TARGET_ANALYSIS_SHA256 =
    "10ccb7a9dadf30d6b18d465c33dd0d418b273520fbdb1e9f46c236b1b40aab01"
const BENCHMARK_CONTROL_SHA256 =
    "8fb5a1c0b99e5fa3c955f9e0e914913735e08fe64e90681a648d9ca339a05110"
const BENCHMARK_RESULT_SHA256 =
    "23ce74663e34fefb1b0108d136f6aef3d15519a778dae45d9b0f578bbaefa72d"
const BENCHMARK_SACCT_SHA256 =
    "5824d9e3e1a579dcf452ecbfcb4c475da13cd3f80f83c9c398f33d599d47c969"
const BENCHMARK_STEPS_SACCT_SHA256 =
    "de9eeec59e116d0085615cb7ee829d8c6631920caaf1656e6a717b9f835f5200"
const PREDECESSOR_JOB_ID = "57611537"
const PREDECESSOR_CONTROL_SHA256 =
    "a3b75247770cb86a3c155d48dfecf438b1e21b98119b3b8ed2db51a4868d02de"
const PREDECESSOR_BRIDGE_SHA256 =
    "533f772c47d715535e6db1da274fb48bde5162dcb90e11d2665bdb9e89fe5b61"
const PREDECESSOR_RESULT_SHA256 =
    "03734ddbc4389a45428d69f961a0fdd0adda80567641c383d2f97998be734676"
const PREDECESSOR_LIGHTWEIGHT_SHA256 =
    "e7a488e685e68026132a3d48cec09c1e019eb777df0d09e3b93669699fa70b78"
const PREDECESSOR_CONVERSION_ANALYSIS_SHA256 =
    "37562ba47872de88494894e61fdcde9da6f67954ecdbbf83fe80dd99526c62bd"
const PREDECESSOR_FINAL_ANALYSIS_SHA256 =
    "302b6db4a8e90d568dc61c82c2f8d2b37e588fa3125b69b5cced91752b99fe47"
const PREDECESSOR_SACCT_SHA256 =
    "6888060a71a20ef0b2dbdceeb34eebc093b94dac9bf31cf79dc7dd1187172a0d"
const PREDECESSOR_LOG_SHA256 =
    "4af8d9ed4adcd9c6612344c937478eb8e25b45c8b177e989a7f1d9547340939d"
const PREDECESSOR_ELAPSED_SECONDS = 33423
const PREDECESSOR_ALLOCATED_LOGICAL_CPUS = 10
const PREDECESSOR_CHARGED_PHYSICAL_CORES = 5
const PREDECESSOR_CHARGED_NODE_HOURS =
    PREDECESSOR_ELAPSED_SECONDS / 3600 * PREDECESSOR_CHARGED_PHYSICAL_CORES / 128
const PRIOR_PHASE1_CHARGED_NODE_HOURS =
    12.252445747144446 + PREDECESSOR_CHARGED_NODE_HOURS
const PRIOR_PROJECT_CHARGED_NODE_HOURS =
    13.346878747144446 + PREDECESSOR_CHARGED_NODE_HOURS
const NEXT_PACKAGE_BASENAME =
    "theta_p0p16250000_from_38312fc996fe_working_shared16g_after_57611537"
const PARENT_THETA_OVER_PI = 0.15
const TARGET_THETA_OVER_PI = 0.1625
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const WORKING_POLICY_PATH = joinpath(
    PROJECT_ROOT,
    "configs",
    "phase1_idmrg_working_convergence.toml",
)
const FAILED_TARGET_PACKAGE = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_idmrg",
    "yc8_1",
    "theta_p0p20000000_resume_from_527afdf421e3",
)
const FAILED_TARGET_RESULT_PATH = joinpath(
    FAILED_TARGET_PACKAGE,
    "idmrg_result_bridge.h5",
)
const FAILED_TARGET_ANALYSIS_PATH = joinpath(
    FAILED_TARGET_PACKAGE,
    "analysis",
    "analysis_idmrg_theta_p0p20000000_chi512_working_rejected_" *
    "c7ef67c0e22b_047345111a33.h5",
)
const BENCHMARK_PACKAGE = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_idmrg",
    "benchmarks",
    "theta_p0p20000000_chi512_threads_retry_after_57574096_c7ef67c0e22b",
)
const BENCHMARK_CONTROL_PATH = joinpath(
    BENCHMARK_PACKAGE,
    "phase1_idmrg_benchmark_control.toml",
)
const BENCHMARK_RESULT_PATH = joinpath(
    BENCHMARK_PACKAGE,
    "results",
    "benchmark_threads_2.h5",
)
const BENCHMARK_SACCT_PATH = joinpath(BENCHMARK_PACKAGE, "sacct-57576411.tsv")
const BENCHMARK_STEPS_SACCT_PATH =
    joinpath(BENCHMARK_PACKAGE, "sacct-steps-57576411.tsv")
const PREDECESSOR_PACKAGE = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_idmrg",
    "yc8_1",
    "theta_p0p17500000_from_38312fc996fe_working_shared16g_retry_after_57608599",
)
const PREDECESSOR_CONTROL_PATH =
    joinpath(PREDECESSOR_PACKAGE, "phase1_idmrg_sweep_step_control.toml")
const PREDECESSOR_BRIDGE_PATH =
    joinpath(PREDECESSOR_PACKAGE, "accepted_parent_to_mpskit_bridge.h5")
const PREDECESSOR_RESULT_PATH = joinpath(PREDECESSOR_PACKAGE, "idmrg_result_bridge.h5")
const PREDECESSOR_LIGHTWEIGHT_PATH =
    joinpath(PREDECESSOR_PACKAGE, "idmrg_result_lightweight.h5")
const PREDECESSOR_CONVERSION_ANALYSIS_PATH = joinpath(
    PREDECESSOR_PACKAGE,
    "analysis",
    "analysis_idmrg_theta_p0p17500000_chi512_conversion_rejected_" *
    "03734ddbc438_047345111a33.h5",
)
const PREDECESSOR_FINAL_ANALYSIS_PATH = joinpath(
    PREDECESSOR_PACKAGE,
    "analysis",
    "analysis_idmrg_theta_p0p17500000_chi512_rejected_03734ddbc438.h5",
)
const PREDECESSOR_SACCT_PATH =
    joinpath(PREDECESSOR_PACKAGE, "sacct-$PREDECESSOR_JOB_ID.tsv")
const PREDECESSOR_LOG_PATH =
    joinpath(PREDECESSOR_PACKAGE, "logs", "idmrg-$PREDECESSOR_JOB_ID.out")

length(ARGS) == 3 || error(
    "usage: prepare_phase1_idmrg_sweep_step.jl ACCEPTED_PARENT.h5 " *
    "OUTPUT_DIRECTORY PERLMUTTER_PROJECT_ROOT",
)

parent_path = abspath(ARGS[1])
output_directory = abspath(ARGS[2])
perlmutter_root = replace(normpath(ARGS[3]), '\\' => '/')
startswith(perlmutter_root, "/") || error("Perlmutter project root must be absolute")
basename(output_directory) == NEXT_PACKAGE_BASENAME || error(
    "output directory must end in $NEXT_PACKAGE_BASENAME",
)
isdir(output_directory) && !isempty(readdir(output_directory)) && error(
    "refusing to populate nonempty control directory: $output_directory",
)

function verify_file(path, expected_sha256, label)
    isfile(path) || error("missing $label: $path")
    PB.file_sha256(path) == expected_sha256 || error("$label SHA-256 mismatch")
    return abspath(path)
end

function project_relative(path)
    relative = relpath(abspath(path), PROJECT_ROOT)
    any(==(".."), splitpath(relative)) &&
        error("path is outside the Project B root: $path")
    return replace(relative, '\\' => '/')
end

function perlmutter_path(path)
    return rstrip(perlmutter_root, '/') * "/" * project_relative(path)
end

function package_relative(path)
    return replace(relpath(abspath(path), output_directory), '\\' => '/')
end

verify_file(parent_path, LINEAGE_ROOT_SHA256, "accepted lineage parent")
verify_file(WORKING_POLICY_PATH, WORKING_POLICY_SHA256, "working convergence policy")
verify_file(FAILED_TARGET_RESULT_PATH, FAILED_TARGET_RESULT_SHA256,
    "branch-failing theta/pi=0.20 result")
verify_file(FAILED_TARGET_ANALYSIS_PATH, FAILED_TARGET_ANALYSIS_SHA256,
    "branch-failing theta/pi=0.20 working analysis")
verify_file(BENCHMARK_CONTROL_PATH, BENCHMARK_CONTROL_SHA256, "benchmark control")
verify_file(BENCHMARK_RESULT_PATH, BENCHMARK_RESULT_SHA256, "2-thread benchmark result")
verify_file(BENCHMARK_SACCT_PATH, BENCHMARK_SACCT_SHA256, "benchmark accounting")
verify_file(BENCHMARK_STEPS_SACCT_PATH, BENCHMARK_STEPS_SACCT_SHA256,
    "benchmark step accounting")
for (path, sha256, label) in (
    (PREDECESSOR_CONTROL_PATH, PREDECESSOR_CONTROL_SHA256, "predecessor control"),
    (PREDECESSOR_BRIDGE_PATH, PREDECESSOR_BRIDGE_SHA256, "predecessor bridge"),
    (PREDECESSOR_RESULT_PATH, PREDECESSOR_RESULT_SHA256, "predecessor result"),
    (PREDECESSOR_LIGHTWEIGHT_PATH, PREDECESSOR_LIGHTWEIGHT_SHA256,
        "predecessor lightweight archive"),
    (PREDECESSOR_CONVERSION_ANALYSIS_PATH, PREDECESSOR_CONVERSION_ANALYSIS_SHA256,
        "predecessor conversion-rejection analysis"),
    (PREDECESSOR_FINAL_ANALYSIS_PATH, PREDECESSOR_FINAL_ANALYSIS_SHA256,
        "predecessor final branch analysis"),
    (PREDECESSOR_SACCT_PATH, PREDECESSOR_SACCT_SHA256, "predecessor accounting"),
    (PREDECESSOR_LOG_PATH, PREDECESSOR_LOG_SHA256, "predecessor log"),
)
    verify_file(path, sha256, label)
end

strip(read(PREDECESSOR_SACCT_PATH, String)) ==
    "57611537|pb1-idmrg|COMPLETED|33423|720|1|10|0:0" ||
    error("theta/pi=0.175 accounting contents changed")

working_policy = TOML.parsefile(WORKING_POLICY_PATH)
working_policy["artifact_kind"] ==
    "project_b_phase1_idmrg_working_convergence_policy" ||
    error("unexpected working-convergence policy kind")
working_scope = working_policy["scope"]
working_native = working_policy["native_convergence"]
working_scope["profile"] == "phase1_exploratory_working_20260824" ||
    error("working-convergence profile changed")

parent = PB.read_state_file(parent_path)
parent.schema_version >= 7 || error("accepted parent is older than schema 7")
parent.converged && parent.continuation_accepted ||
    error("pinned parent is not accepted and converged")
isapprox(parent.theta_over_pi, PARENT_THETA_OVER_PI; atol=1e-12, rtol=0) ||
    error("pinned parent is not theta/pi=$PARENT_THETA_OVER_PI")
parent.circumference == 8 && parent.shift == 1 || error("parent is not YC8-1")
parent.mps_period == 2 && parent.unit_cell_is_minimal ||
    error("parent does not use the minimal period-2 representation")
parent.twist_gauge === :uniform || error("parent does not use the uniform twist gauge")
parent.branch == "primary_forward_chi512_legacy_0p1" || error("wrong primary branch")
parent.direction === :forward || error("parent is not forward lineage")
parent.maxlinkdim == 512 || error("parent is not chi 512")
parent.J1 == 1.0 && parent.J2 == 0.12 && parent.Delta1 == 1.0 &&
    parent.Delta2 == 1.0 && parent.Bz == 0.0 || error("parent model mismatch")

HDF5.h5open(FAILED_TARGET_ANALYSIS_PATH, "r") do file
    Bool(read(file, "optimizer/converged")) ||
        error("theta/pi=0.20 no longer passes the working native gate")
    !Bool(read(file, "continuation_accepted")) ||
        error("theta/pi=0.20 is no longer branch-rejected")
    Float64(read(file, "continuation/overlap_per_site")) < 0.99 ||
        error("theta/pi=0.20 no longer fails the parent-overlap gate")
    String(read(file, "lineage/root_state_sha256")) == LINEAGE_ROOT_SHA256 ||
        error("theta/pi=0.20 analysis lineage root changed")
end

HDF5.h5open(PREDECESSOR_RESULT_PATH, "r") do file
    String(read(file, "artifact_kind")) == "project_b_mpskit_idmrg_result_bridge" ||
        error("unexpected theta/pi=0.175 result kind")
    Bool(read(file, "optimizer/converged")) ||
        error("theta/pi=0.175 no longer passes its predeclared native gate")
    Int(read(file, "optimizer/iterations")) == 371 ||
        error("theta/pi=0.175 iteration count changed")
    isapprox(Float64(read(file, "optimizer/final_environment_error")),
        9.784243012995464e-6; atol=5e-18, rtol=0) ||
        error("theta/pi=0.175 final bond-matrix update norm changed")
    String(read(file, "lineage/root_state_sha256")) == LINEAGE_ROOT_SHA256 ||
        error("theta/pi=0.175 result lineage root changed")
end

HDF5.h5open(PREDECESSOR_CONVERSION_ANALYSIS_PATH, "r") do file
    String(read(file, "analysis/stage")) == "promotion_blocked_conversion_failure" ||
        error("initial theta/pi=0.175 conversion analysis changed")
    !Bool(read(file, "continuation_accepted")) ||
        error("initial conversion-rejected analysis was relabeled")
end

HDF5.h5open(PREDECESSOR_FINAL_ANALYSIS_PATH, "r") do file
    String(read(file, "analysis/stage")) == "full_promotion_analysis" ||
        error("theta/pi=0.175 final analysis stage changed")
    Bool(read(file, "optimizer/converged")) ||
        error("theta/pi=0.175 final analysis lost native convergence")
    !Bool(read(file, "continuation_accepted")) ||
        error("theta/pi=0.175 must remain branch-rejected")
    overlap = Float64(read(file, "continuation/overlap_per_site"))
    isapprox(overlap, 0.9662443394038124; atol=5e-15, rtol=0) ||
        error("theta/pi=0.175 parent overlap changed")
    overlap < 0.99 || error("theta/pi=0.175 no longer fails the parent-overlap gate")
    !Bool(read(file, "validation/common_vumps_projected_residual_ran")) ||
        error("VUMPS probe must remain skipped after the overlap rejection")
    String(read(file, "source/result_bridge_sha256")) == PREDECESSOR_RESULT_SHA256 ||
        error("theta/pi=0.175 analysis names a different result")
    String(read(file, "lineage/root_state_sha256")) == LINEAGE_ROOT_SHA256 ||
        error("theta/pi=0.175 analysis lineage root changed")
end

HDF5.h5open(BENCHMARK_RESULT_PATH, "r") do file
    String(read(file, "artifact_kind")) ==
        "project_b_mpskit_idmrg_thread_benchmark" ||
        error("unexpected benchmark result kind")
    Int(read(file, "benchmark/julia_threads")) == 2 ||
        error("benchmark no longer supports 2 Julia threads")
    Int(read(file, "benchmark/slurm_logical_cpus")) == 4 ||
        error("benchmark no longer supports 4 Slurm logical CPUs")
    String(read(file, "source/benchmark_control_sha256")) ==
        BENCHMARK_CONTROL_SHA256 || error("benchmark control lineage changed")
end

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
        file["schema_version"] = 3
        file["artifact_kind"] = "project_b_itensor_mpskit_bridge"
        file["created_at_utc"] = string(now(UTC))
        file["lineage/branch"] = parent.branch
        file["lineage/direction"] = string(parent.direction)
        file["lineage/root_state_path"] = perlmutter_path(parent_path)
        file["lineage/root_state_sha256"] = LINEAGE_ROOT_SHA256
        file["lineage/root_theta_over_pi"] = PARENT_THETA_OVER_PI
        file["lineage/parent_state_path"] = perlmutter_path(parent_path)
        file["lineage/parent_state_sha256"] = LINEAGE_ROOT_SHA256
        file["lineage/parent_theta_over_pi"] = PARENT_THETA_OVER_PI
        file["lineage/numerical_seed_kind"] = "accepted_parent"
        file["lineage/numerical_seed_path"] = perlmutter_path(parent_path)
        file["lineage/numerical_seed_sha256"] = LINEAGE_ROOT_SHA256
        file["lineage/numerical_seed_theta_over_pi"] = PARENT_THETA_OVER_PI
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
        file["model/bonds/coupling"] =
            [bond.family === :NN ? 1.0 : 0.12 for bond in bonds]
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

scratch_subdirectory =
    "QSL/project_b_flux_dimensional_reduction/phase1_idmrg/yc8_1/" *
    NEXT_PACKAGE_BASENAME
control = Dict{String,Any}(
    "artifact_kind" => "project_b_phase1_idmrg_control",
    "schema_version" => 5,
    "created_at_utc" => string(now(UTC)),
    "bridge" => Dict(
        "path" => basename(bridge_path),
        "sha256" => bridge_sha256,
    ),
    "lineage" => Dict(
        "branch" => parent.branch,
        "direction" => "forward",
        "root_state_path" => perlmutter_path(parent_path),
        "root_state_sha256" => LINEAGE_ROOT_SHA256,
        "root_theta_over_pi" => PARENT_THETA_OVER_PI,
        "parent_state_path" => perlmutter_path(parent_path),
        "parent_state_sha256" => LINEAGE_ROOT_SHA256,
        "parent_theta_over_pi" => PARENT_THETA_OVER_PI,
        "target_theta_over_pi" => TARGET_THETA_OVER_PI,
        "overlap_reference_sha256" => LINEAGE_ROOT_SHA256,
        "numerical_seed_kind" => "accepted_parent",
        "numerical_seed_path" => perlmutter_path(parent_path),
        "numerical_seed_sha256" => LINEAGE_ROOT_SHA256,
        "numerical_seed_is_lineage_parent" => true,
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
        "minimum_iterations" => Int(working_native["minimum_iterations"]),
        "environment_tolerance" =>
            Float64(working_native["bond_matrix_update_norm_tolerance"]),
        "energy_window" => Int(working_native["energy_window"]),
        "energy_density_span_tolerance" =>
            Float64(working_native["energy_density_span_tolerance"]),
        "energy_density_semantics" =>
            "MPSKit IDMRG superblock-energy increment divided by period",
        "criterion_profile" => String(working_scope["profile"]),
        "criterion_selected_after_job_id" =>
            String(working_scope["applies_to_controls_prepared_after_job_id"]),
        "criterion_policy_path" => project_relative(WORKING_POLICY_PATH),
        "criterion_policy_sha256" => WORKING_POLICY_SHA256,
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
    "source_evidence" => Dict(
        "failed_target_theta_over_pi" => 0.175,
        "failed_target_result_path" => package_relative(PREDECESSOR_RESULT_PATH),
        "failed_target_result_sha256" => PREDECESSOR_RESULT_SHA256,
        "failed_target_analysis_path" => package_relative(PREDECESSOR_FINAL_ANALYSIS_PATH),
        "failed_target_analysis_sha256" => PREDECESSOR_FINAL_ANALYSIS_SHA256,
        "failed_target_working_native_converged" => true,
        "failed_target_parent_overlap_per_site" => 0.9662443394038124,
        "failed_target_branch_accepted" => false,
        "failed_target_common_vumps_probe_ran" => false,
        "previous_failed_target_theta_over_pi" => 0.2,
        "previous_failed_target_result_sha256" => FAILED_TARGET_RESULT_SHA256,
        "previous_failed_target_analysis_sha256" => FAILED_TARGET_ANALYSIS_SHA256,
    ),
    "resource_selection" => Dict(
        "benchmark_job_id" => "57576411",
        "benchmark_control_path" => package_relative(BENCHMARK_CONTROL_PATH),
        "benchmark_control_sha256" => BENCHMARK_CONTROL_SHA256,
        "benchmark_result_path" => package_relative(BENCHMARK_RESULT_PATH),
        "benchmark_result_sha256" => BENCHMARK_RESULT_SHA256,
        "benchmark_steps_sacct_path" => package_relative(BENCHMARK_STEPS_SACCT_PATH),
        "benchmark_steps_sacct_sha256" => BENCHMARK_STEPS_SACCT_SHA256,
        "selected_julia_threads" => 2,
        "selected_solver_step_logical_cpus" => 4,
        "allocation_logical_cpus" => 10,
        "selection_metric" =>
            "minimum projected Shared-QOS node-hours per 100 iDMRG updates",
    ),
    "predecessor_evidence" => Dict(
        "job_id" => PREDECESSOR_JOB_ID,
        "job_state" => "COMPLETED",
        "job_exit_code" => "0:0",
        "job_elapsed_seconds" => PREDECESSOR_ELAPSED_SECONDS,
        "job_allocated_logical_cpus" => PREDECESSOR_ALLOCATED_LOGICAL_CPUS,
        "job_charged_physical_cores" => PREDECESSOR_CHARGED_PHYSICAL_CORES,
        "job_charged_node_hours" => PREDECESSOR_CHARGED_NODE_HOURS,
        "control_path" => package_relative(PREDECESSOR_CONTROL_PATH),
        "control_sha256" => PREDECESSOR_CONTROL_SHA256,
        "bridge_path" => package_relative(PREDECESSOR_BRIDGE_PATH),
        "bridge_sha256" => PREDECESSOR_BRIDGE_SHA256,
        "result_path" => package_relative(PREDECESSOR_RESULT_PATH),
        "result_sha256" => PREDECESSOR_RESULT_SHA256,
        "lightweight_path" => package_relative(PREDECESSOR_LIGHTWEIGHT_PATH),
        "lightweight_sha256" => PREDECESSOR_LIGHTWEIGHT_SHA256,
        "conversion_analysis_path" => package_relative(PREDECESSOR_CONVERSION_ANALYSIS_PATH),
        "conversion_analysis_sha256" => PREDECESSOR_CONVERSION_ANALYSIS_SHA256,
        "final_analysis_path" => package_relative(PREDECESSOR_FINAL_ANALYSIS_PATH),
        "final_analysis_sha256" => PREDECESSOR_FINAL_ANALYSIS_SHA256,
        "sacct_path" => package_relative(PREDECESSOR_SACCT_PATH),
        "sacct_sha256" => PREDECESSOR_SACCT_SHA256,
        "log_path" => package_relative(PREDECESSOR_LOG_PATH),
        "log_sha256" => PREDECESSOR_LOG_SHA256,
        "native_converged" => true,
        "branch_accepted" => false,
        "classification" => "native_converged_primary_branch_overlap_rejected",
    ),
    "storage" => Dict(
        "backend" => "perlmutter_scratch",
        "scratch_subdirectory" => scratch_subdirectory,
        "checkpoint_every_iterations" => 20,
        "checkpoint_directory" => "checkpoints",
        "result_path" => "idmrg_result_bridge.h5",
        "lightweight_result_path" => "idmrg_result_lightweight.h5",
        "final_state_directory" => "analysis",
    ),
    "resources" => Dict(
        "system" => "perlmutter",
        "constraint" => "cpu",
        "qos" => "shared",
        "nodes" => 1,
        "tasks" => 1,
        "allocation_logical_cpus" => 10,
        "solver_step_logical_cpus" => 4,
        "julia_threads" => 2,
        "memory" => "16G",
        "time_limit" => "12:00:00",
        "maximum_new_node_hours" => 0.46875,
        "maximum_jobs" => 1,
    ),
    "accounting" => Dict(
        "previous_job_id" => PREDECESSOR_JOB_ID,
        "previous_job_state" => "COMPLETED",
        "previous_job_exit_code" => "0:0",
        "previous_job_elapsed_seconds" => PREDECESSOR_ELAPSED_SECONDS,
        "previous_job_charged_node_hours" => PREDECESSOR_CHARGED_NODE_HOURS,
        "previous_sacct_path" => package_relative(PREDECESSOR_SACCT_PATH),
        "previous_sacct_sha256" => PREDECESSOR_SACCT_SHA256,
        "prior_phase1_charged_node_hours" => PRIOR_PHASE1_CHARGED_NODE_HOURS,
        "phase1_ceiling_node_hours" => 20.0,
        "prior_project_charged_node_hours" => PRIOR_PROJECT_CHARGED_NODE_HOURS,
        "project_ceiling_node_hours" => 150.0,
    ),
    "authorization" => Dict(
        "submission_authorized" => true,
        "authorization_basis" => "standing_owner_authorization_20260825",
        "requires_explicit_submit_command" => true,
        "automatic_advance_allowed" => false,
    ),
    "provenance" => Dict(
        "idmrg_manifest_sha256" => PB.file_sha256(joinpath(PROJECT_ROOT, "idmrg/Manifest.toml")),
        "solver_module_sha256" =>
            PB.file_sha256(joinpath(PROJECT_ROOT, "idmrg/src/ProjectBIDMRG.jl")),
        "root_manifest_sha256" => PB.file_sha256(joinpath(PROJECT_ROOT, "Manifest.toml")),
        "analyzer_sha256" => PB.file_sha256(
            joinpath(PROJECT_ROOT, "scripts/analyze_phase1_idmrg_result.jl"),
        ),
        "launcher_sha256" =>
            PB.file_sha256(joinpath(PROJECT_ROOT, "slurm/run_idmrg_cpu.sh")),
        "decision_document_sha256" => PB.file_sha256(
            joinpath(PROJECT_ROOT, "docs/PHASE1_IDMRG_LIBRARY_DECISION.md"),
        ),
        "sweep_step_preparer_sha256" => PB.file_sha256(@__FILE__),
        "storage_document_sha256" => PB.file_sha256(
            joinpath(PROJECT_ROOT, "docs/PHASE1_IDMRG_STORAGE.md"),
        ),
        "working_policy_sha256" => WORKING_POLICY_SHA256,
    ),
)

control_path = joinpath(output_directory, "phase1_idmrg_sweep_step_control.toml")
ispath(control_path) && error("refusing to overwrite control: $control_path")
open(control_path, "w") do io
    TOML.print(io, control; sorted=true)
end

println("Prepared theta/pi=$PARENT_THETA_OVER_PI -> $TARGET_THETA_OVER_PI")
println("Immutable lineage root SHA-256: $LINEAGE_ROOT_SHA256")
println("Numerical seed: accepted lineage parent (no rejected state)")
println("Wrote immutable bridge: $bridge_path")
println("Bridge SHA-256: $bridge_sha256")
println("Wrote guarded control: $control_path")
println("Control SHA-256: $(PB.file_sha256(control_path))")
println("Predecessor evidence: job $PREDECESSOR_JOB_ID completed but failed the " *
    "primary-branch overlap gate; charge=$(PREDECESSOR_CHARGED_NODE_HOURS) node-hours")
println("Resources: 10 allocation logical CPUs, 4 solver-step logical CPUs, " *
    "2 Julia threads, 16G, Shared QOS")
println("Maximum forecast charge: 0.46875 node-hours")
println("Standing owner submission authorization is recorded; this preparer did not submit a job.")
