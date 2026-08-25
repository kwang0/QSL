using Dates
using HDF5
using ProjectBIDMRG
using TOML

const RESULT_SHA256 =
    "c7ef67c0e22b32d581fec9ed3d4f86b14182db15a1f80688c88fc311eb326116"
const LIGHTWEIGHT_SHA256 =
    "2a3b8e22d06cb3da7b5b61a5640ea3eb418c2ca51ab0ae00c31986905c209cc2"
const SCIENCE_CONTROL_SHA256 =
    "67e258ee244ddaf397d9f493a09c1a30d4a0b1e0f4a3a001e954db8f287a89d0"
const SACCT_SHA256 =
    "d9b7270dbad1bf4cddbc894c3146c72d47b203b2ebe3f01c6d917e4c8a60d6c8"
const ACCEPTED_PARENT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const FAILED_BENCHMARK_CONTROL_SHA256 =
    "486aeef1919a2c3848ac32307d282cb0e9b6fd03121dce14756605e654cb7292"
const FAILED_BENCHMARK_LOG_SHA256 =
    "d42b9b7abcc74ae725556bd9e6d1f3c9b02a497b72931d01e6f6e6247f3c084a"
const FAILED_BENCHMARK_SACCT_SHA256 =
    "953915a51ded26c9fc52a2c4741ca0856dba9d4623d882a1d1b296ad56ebda2a"
const FAILED_BENCHMARK_STEPS_SHA256 =
    "9bdc7aa996626bcdd3b49c289af6b0e18df98a07927bbc72fbfff5733127e43b"
const RUNTIME_FAILED_BENCHMARK_CONTROL_SHA256 =
    "4e21b2f61e5e93bdcd2b891c16a49670521a114ece2a451641a4e8a55bb7deec"
const RUNTIME_FAILED_BENCHMARK_LOG_SHA256 =
    "80203e47c1f1162236695c8d6de0427a3f94c1f2d98b946509daf6a9cf134ef4"
const RUNTIME_FAILED_BENCHMARK_SACCT_SHA256 =
    "0ab0a1f933a25ce3da816820532e4d21fd04319c74b9b7107a11ad9b0087ce01"
const RUNTIME_FAILED_BENCHMARK_STEPS_SHA256 =
    "ad2a5038c9fdb75a7f968b52473dabea34d2d4872de093cb58f133e855a91747"
const WRITER_FAILED_BENCHMARK_CONTROL_SHA256 =
    "1cbfc097ccd16385411e2b5aca80de088b1b7791e453d0108799e8981d62868a"
const WRITER_FAILED_BENCHMARK_LOG_SHA256 =
    "e8e2ac082f51fcd112073984e9628c7399baf61f0732ccec314160eb614a005b"
const WRITER_FAILED_BENCHMARK_SACCT_SHA256 =
    "14abc583b58899e6374a689274e54700b10f137330063d71e49be8c4e01080b7"
const WRITER_FAILED_BENCHMARK_STEPS_SHA256 =
    "50af3a0078a31fdf8d4f41862500e18146dc148941828d398b4f6e6772ca81eb"
const WRITER_FAILED_PARTIAL_RESULT_SHA256 =
    "4e44fcd19e7eef01e22f680d6af07ec42f752aca9b9c4d094f3026f58c18b74c"
const FAILED_BENCHMARK_JOB_ID = "57548405"
const RUNTIME_FAILED_BENCHMARK_JOB_ID = "57550459"
const WRITER_FAILED_BENCHMARK_JOB_ID = "57574096"
const FAILED_PACKAGE_NAME = "theta_p0p20000000_chi512_threads_from_c7ef67c0e22b"
const RUNTIME_FAILED_PACKAGE_NAME =
    "theta_p0p20000000_chi512_threads_retry_after_57548405_c7ef67c0e22b"
const WRITER_FAILED_PACKAGE_NAME =
    "theta_p0p20000000_chi512_threads_retry_after_57550459_c7ef67c0e22b"
const PACKAGE_NAME =
    "theta_p0p20000000_chi512_threads_retry_after_57574096_c7ef67c0e22b"

project_root = normpath(joinpath(@__DIR__, ".."))
source_package = joinpath(
    project_root,
    "output/phase1_idmrg/yc8_1/theta_p0p20000000_resume_from_527afdf421e3",
)
source_paths = Dict(
    "science_control_path" => joinpath(source_package, "phase1_idmrg_control_v2.toml"),
    "result_bridge_path" => joinpath(source_package, "idmrg_result_bridge.h5"),
    "lightweight_result_path" => joinpath(source_package, "idmrg_result_lightweight.h5"),
    "sacct_path" => joinpath(source_package, "sacct-57500598.tsv"),
    "efficiency_evidence_path" => joinpath(
        source_package,
        "sacct-efficiency-57500598.tsv",
    ),
    "native_analysis_path" => joinpath(
        source_package,
        "analysis/analysis_idmrg_theta_p0p20000000_chi512_rejected_c7ef67c0e22b.h5",
    ),
)
for (key, path) in source_paths
    isfile(path) || error("missing $key: $path")
end
for (key, expected) in (
    "science_control_path" => SCIENCE_CONTROL_SHA256,
    "result_bridge_path" => RESULT_SHA256,
    "lightweight_result_path" => LIGHTWEIGHT_SHA256,
    "sacct_path" => SACCT_SHA256,
)
    ProjectBIDMRG.file_sha256(source_paths[key]) == expected ||
        error("immutable source hash mismatch: $(source_paths[key])")
end

failed_package = joinpath(
    project_root,
    "output/phase1_idmrg/benchmarks",
    FAILED_PACKAGE_NAME,
)
failed_paths = Dict(
    "control_path" => joinpath(failed_package, "phase1_idmrg_benchmark_control.toml"),
    "log_path" => joinpath(failed_package, "logs/benchmark-$FAILED_BENCHMARK_JOB_ID.out"),
    "sacct_path" => joinpath(failed_package, "sacct-$FAILED_BENCHMARK_JOB_ID.tsv"),
    "steps_path" => joinpath(failed_package, "sacct-steps-$FAILED_BENCHMARK_JOB_ID.tsv"),
)
for (key, expected) in (
    "control_path" => FAILED_BENCHMARK_CONTROL_SHA256,
    "log_path" => FAILED_BENCHMARK_LOG_SHA256,
    "sacct_path" => FAILED_BENCHMARK_SACCT_SHA256,
    "steps_path" => FAILED_BENCHMARK_STEPS_SHA256,
)
    path = failed_paths[key]
    isfile(path) || error("missing failed benchmark evidence: $path")
    ProjectBIDMRG.file_sha256(path) == expected ||
        error("failed benchmark evidence hash mismatch: $path")
end
failed_log = read(failed_paths["log_path"], String)
occursin("/var/spool/slurmd/idmrg/scripts/validate_benchmark_control.jl", failed_log) ||
    error("failed benchmark log no longer proves the Slurm-spooled path bug")
failed_summary = only(readlines(failed_paths["sacct_path"]))
occursin("57548405|pb1-idmrg-bench|FAILED|11|90|1|32|1:0", failed_summary) ||
    error("failed benchmark summary accounting changed")
isdir(joinpath(failed_package, "results")) &&
    !isempty(readdir(joinpath(failed_package, "results"))) &&
    error("failed benchmark unexpectedly produced timing results")

runtime_failed_package = joinpath(
    project_root,
    "output/phase1_idmrg/benchmarks",
    RUNTIME_FAILED_PACKAGE_NAME,
)
runtime_failed_paths = Dict(
    "control_path" => joinpath(
        runtime_failed_package,
        "phase1_idmrg_benchmark_control.toml",
    ),
    "log_path" => joinpath(
        runtime_failed_package,
        "logs/benchmark-$RUNTIME_FAILED_BENCHMARK_JOB_ID.out",
    ),
    "sacct_path" => joinpath(
        runtime_failed_package,
        "sacct-$RUNTIME_FAILED_BENCHMARK_JOB_ID.tsv",
    ),
    "steps_path" => joinpath(
        runtime_failed_package,
        "sacct-steps-$RUNTIME_FAILED_BENCHMARK_JOB_ID.tsv",
    ),
)
for (key, expected) in (
    "control_path" => RUNTIME_FAILED_BENCHMARK_CONTROL_SHA256,
    "log_path" => RUNTIME_FAILED_BENCHMARK_LOG_SHA256,
    "sacct_path" => RUNTIME_FAILED_BENCHMARK_SACCT_SHA256,
    "steps_path" => RUNTIME_FAILED_BENCHMARK_STEPS_SHA256,
)
    path = runtime_failed_paths[key]
    isfile(path) || error("missing runtime-failed benchmark evidence: $path")
    ProjectBIDMRG.file_sha256(path) == expected ||
        error("runtime-failed benchmark evidence hash mismatch: $path")
end
runtime_failed_log = read(runtime_failed_paths["log_path"], String)
occursin("UndefVarError: `cputime` not defined in `Base`", runtime_failed_log) ||
    error("runtime-failed log no longer proves the Julia 1.12 timing API bug")
runtime_failed_summary = only(readlines(runtime_failed_paths["sacct_path"]))
occursin("57550459|pb1-idmrg-bench|FAILED|202|90|1|32|1:0", runtime_failed_summary) ||
    error("runtime-failed benchmark summary accounting changed")
isdir(joinpath(runtime_failed_package, "results")) &&
    !isempty(readdir(joinpath(runtime_failed_package, "results"))) &&
    error("runtime-failed benchmark unexpectedly produced timing results")

writer_failed_package = joinpath(
    project_root,
    "output/phase1_idmrg/benchmarks",
    WRITER_FAILED_PACKAGE_NAME,
)
writer_failed_paths = Dict(
    "control_path" => joinpath(
        writer_failed_package,
        "phase1_idmrg_benchmark_control.toml",
    ),
    "log_path" => joinpath(
        writer_failed_package,
        "logs/benchmark-$WRITER_FAILED_BENCHMARK_JOB_ID.out",
    ),
    "sacct_path" => joinpath(
        writer_failed_package,
        "sacct-$WRITER_FAILED_BENCHMARK_JOB_ID.tsv",
    ),
    "steps_path" => joinpath(
        writer_failed_package,
        "sacct-steps-$WRITER_FAILED_BENCHMARK_JOB_ID.tsv",
    ),
    "partial_result_path" => joinpath(
        writer_failed_package,
        "results/benchmark_threads_2.h5.tmp",
    ),
)
for (key, expected) in (
    "control_path" => WRITER_FAILED_BENCHMARK_CONTROL_SHA256,
    "log_path" => WRITER_FAILED_BENCHMARK_LOG_SHA256,
    "sacct_path" => WRITER_FAILED_BENCHMARK_SACCT_SHA256,
    "steps_path" => WRITER_FAILED_BENCHMARK_STEPS_SHA256,
    "partial_result_path" => WRITER_FAILED_PARTIAL_RESULT_SHA256,
)
    path = writer_failed_paths[key]
    isfile(path) || error("missing writer-failed benchmark evidence: $path")
    ProjectBIDMRG.file_sha256(path) == expected ||
        error("writer-failed benchmark evidence hash mismatch: $path")
end
writer_failed_log = read(writer_failed_paths["log_path"], String)
occursin("no method matching strides(::BitVector)", writer_failed_log) ||
    error("writer-failed log no longer proves the HDF5 BitVector failure")
occursin("write_benchmark_result", writer_failed_log) ||
    error("writer-failed log no longer locates the result-writer failure")
writer_failed_summary = only(readlines(writer_failed_paths["sacct_path"]))
occursin("57574096|pb1-idmrg-bench|FAILED|889|90|1|32|1:0", writer_failed_summary) ||
    error("writer-failed benchmark summary accounting changed")
writer_failed_steps = read(writer_failed_paths["steps_path"], String)
occursin(
    "57574096.0|pb1-idmrg-t2|FAILED|791|00:13:11||1|4|4|14:31.541|00:14:21|7327392K|7327392K|1:0",
    writer_failed_steps,
) || error("writer-failed benchmark step accounting changed")
isfile(joinpath(writer_failed_package, "results/benchmark_threads_2.h5")) &&
    error("writer-failed benchmark unexpectedly produced a final timing result")
HDF5.h5open(writer_failed_paths["partial_result_path"], "r") do file
    Int(read(file, "schema_version")) == 1 ||
        error("writer-failed partial result schema changed")
    String(read(file, "artifact_kind")) ==
        "project_b_mpskit_idmrg_thread_benchmark" ||
        error("writer-failed partial result kind changed")
    Int(read(file, "benchmark/julia_threads")) == 2 ||
        error("writer-failed partial result thread setting changed")
    Int(read(file, "benchmark/total_iterations")) == 5 ||
        error("writer-failed partial result iteration count changed")
    String(read(file, "source/benchmark_control_sha256")) ==
        WRITER_FAILED_BENCHMARK_CONTROL_SHA256 ||
        error("writer-failed partial result control lineage changed")
    String(read(file, "source/result_seed_sha256")) == RESULT_SHA256 ||
        error("writer-failed partial result seed lineage changed")
    !haskey(file, "optimizer") ||
        error("writer-failed partial result unexpectedly contains timing histories")
end

timing_preflight = ProjectBIDMRG.benchmark_timing_preflight()
timing_preflight.cpu_seconds > 0 || error("executable process CPU timing preflight failed")
result_io_preflight = ProjectBIDMRG.benchmark_result_io_preflight()
result_io_preflight.bytes > 0 || error("executable benchmark-result I/O preflight failed")
result_io_preflight.mask == UInt8[0, 1] ||
    error("benchmark-result I/O preflight returned the wrong mask encoding")

native_analysis_sha256 = ProjectBIDMRG.file_sha256(source_paths["native_analysis_path"])
HDF5.h5open(source_paths["native_analysis_path"], "r") do file
    String(read(file, "artifact_kind")) == "project_b_idmrg_analysis" ||
        error("unexpected latest analysis artifact")
    String(read(file, "source/result_bridge_sha256")) == RESULT_SHA256 ||
        error("latest analysis does not describe job 57500598")
    String(read(file, "analysis/stage")) == "native_only" ||
        error("latest result did not receive native-first analysis")
    !Bool(read(file, "continuation_accepted")) ||
        error("latest result must remain rejected")
    !Bool(read(file, "optimizer/converged")) ||
        error("latest result must remain native-nonconverged")
    isapprox(
        Float64(read(file, "optimizer/final_bond_matrix_update_norm")),
        2.311348784022773e-6;
        atol=1e-16,
        rtol=1e-12,
    ) || error("latest fixed-point change changed")
end

efficiency_lines = readlines(source_paths["efficiency_evidence_path"])
length(efficiency_lines) == 5 || error("unexpected efficiency-evidence row count")
occursin("57500598.0|env|COMPLETED|08:48:27|128|1-17:54:26", last(efficiency_lines)) ||
    error("latest solver-step accounting changed")
efficiency_sha256 = ProjectBIDMRG.file_sha256(source_paths["efficiency_evidence_path"])

output_directory = joinpath(
    project_root,
    "output/phase1_idmrg/benchmarks",
    PACKAGE_NAME,
)
mkpath(output_directory)
control_path = joinpath(output_directory, "phase1_idmrg_benchmark_control.toml")
ispath(control_path) && error("refusing to overwrite benchmark control: $control_path")
relative_sources = Dict(
    key => relpath(path, output_directory) for (key, path) in source_paths
)
relative_failed = Dict(
    key => relpath(path, output_directory) for (key, path) in failed_paths
)
relative_runtime_failed = Dict(
    key => relpath(path, output_directory) for (key, path) in runtime_failed_paths
)
relative_writer_failed = Dict(
    key => relpath(path, output_directory) for (key, path) in writer_failed_paths
)

previous_charge = 31715 / 3600
failed_benchmark_charge = (16 / 128) * (11 / 3600)
runtime_failed_benchmark_charge = (16 / 128) * (202 / 3600)
writer_failed_benchmark_charge = (16 / 128) * (889 / 3600)
total_failed_benchmark_charge = failed_benchmark_charge +
    runtime_failed_benchmark_charge + writer_failed_benchmark_charge
prior_phase1 = 3.2956575527 + previous_charge + total_failed_benchmark_charge
prior_project = 4.3900905527 + previous_charge + total_failed_benchmark_charge
control = Dict{String,Any}(
    "artifact_kind" => "project_b_phase1_idmrg_benchmark_control",
    "schema_version" => 4,
    "created_at_utc" => string(now(UTC)),
    "purpose" =>
        "retry right-sizing MPSKit one-site iDMRG after two pre-solver failures and one post-update result-writer failure",
    "sources" => Dict(
        "science_control_path" => relative_sources["science_control_path"],
        "science_control_sha256" => SCIENCE_CONTROL_SHA256,
        "result_bridge_path" => relative_sources["result_bridge_path"],
        "result_bridge_sha256" => RESULT_SHA256,
        "lightweight_result_path" => relative_sources["lightweight_result_path"],
        "lightweight_result_sha256" => LIGHTWEIGHT_SHA256,
        "sacct_path" => relative_sources["sacct_path"],
        "sacct_sha256" => SACCT_SHA256,
        "efficiency_evidence_path" => relative_sources["efficiency_evidence_path"],
        "efficiency_evidence_sha256" => efficiency_sha256,
        "native_analysis_path" => relative_sources["native_analysis_path"],
        "native_analysis_sha256" => native_analysis_sha256,
        "accepted_parent_sha256" => ACCEPTED_PARENT_SHA256,
        "result_status" => "rejected_native_nonconverged_benchmark_seed_only",
        "result_is_lineage_parent" => false,
    ),
    "retry" => Dict(
        "failed_job_id" => FAILED_BENCHMARK_JOB_ID,
        "failed_job_state" => "FAILED",
        "failed_job_exit_code" => "1:0",
        "failed_job_elapsed_seconds" => 11,
        "failed_job_allocated_logical_cpus" => 32,
        "failed_job_charged_node_hours" => failed_benchmark_charge,
        "failure_class" => "launcher_project_root_resolved_from_slurm_spool",
        "scientific_iterations_completed" => 0,
        "timing_results_produced" => false,
        "control_path" => relative_failed["control_path"],
        "control_sha256" => FAILED_BENCHMARK_CONTROL_SHA256,
        "log_path" => relative_failed["log_path"],
        "log_sha256" => FAILED_BENCHMARK_LOG_SHA256,
        "sacct_path" => relative_failed["sacct_path"],
        "sacct_sha256" => FAILED_BENCHMARK_SACCT_SHA256,
        "steps_path" => relative_failed["steps_path"],
        "steps_sha256" => FAILED_BENCHMARK_STEPS_SHA256,
        "corrective_action" =>
            "explicit project-root argument plus worker preflight and spooled-script regression test",
    ),
    "runtime_retry" => Dict(
        "failed_job_id" => RUNTIME_FAILED_BENCHMARK_JOB_ID,
        "failed_job_state" => "FAILED",
        "failed_job_exit_code" => "1:0",
        "failed_job_elapsed_seconds" => 202,
        "failed_job_allocated_logical_cpus" => 32,
        "failed_job_charged_node_hours" => runtime_failed_benchmark_charge,
        "failure_class" => "unsupported_julia_1p12_base_cputime_api",
        "scientific_iterations_completed" => 0,
        "timing_results_produced" => false,
        "control_path" => relative_runtime_failed["control_path"],
        "control_sha256" => RUNTIME_FAILED_BENCHMARK_CONTROL_SHA256,
        "log_path" => relative_runtime_failed["log_path"],
        "log_sha256" => RUNTIME_FAILED_BENCHMARK_LOG_SHA256,
        "sacct_path" => relative_runtime_failed["sacct_path"],
        "sacct_sha256" => RUNTIME_FAILED_BENCHMARK_SACCT_SHA256,
        "steps_path" => relative_runtime_failed["steps_path"],
        "steps_sha256" => RUNTIME_FAILED_BENCHMARK_STEPS_SHA256,
        "corrective_action" =>
            "libuv process CPU timing plus executable Julia-1.12 runtime preflight",
    ),
    "writer_retry" => Dict(
        "failed_job_id" => WRITER_FAILED_BENCHMARK_JOB_ID,
        "failed_job_state" => "FAILED",
        "failed_job_exit_code" => "1:0",
        "failed_job_elapsed_seconds" => 889,
        "failed_job_allocated_logical_cpus" => 32,
        "failed_step_julia_threads" => 2,
        "failed_step_allocated_logical_cpus" => 4,
        "failed_step_elapsed_seconds" => 791,
        "failed_step_max_rss_kib" => 7327392,
        "failed_job_charged_node_hours" => writer_failed_benchmark_charge,
        "failure_class" =>
            "hdf5_bitvector_result_serialization_after_solver_updates",
        "solver_updates_completed_before_writer_failure" => 5,
        "completed_thread_settings" => 0,
        "timing_results_produced" => false,
        "partial_result_contains_timing_histories" => false,
        "control_path" => relative_writer_failed["control_path"],
        "control_sha256" => WRITER_FAILED_BENCHMARK_CONTROL_SHA256,
        "log_path" => relative_writer_failed["log_path"],
        "log_sha256" => WRITER_FAILED_BENCHMARK_LOG_SHA256,
        "sacct_path" => relative_writer_failed["sacct_path"],
        "sacct_sha256" => WRITER_FAILED_BENCHMARK_SACCT_SHA256,
        "steps_path" => relative_writer_failed["steps_path"],
        "steps_sha256" => WRITER_FAILED_BENCHMARK_STEPS_SHA256,
        "partial_result_path" => relative_writer_failed["partial_result_path"],
        "partial_result_sha256" => WRITER_FAILED_PARTIAL_RESULT_SHA256,
        "corrective_action" =>
            "dense UInt8 measured mask, atomic temporary cleanup, exact HDF5 writer-readback preflight, and analyzer test using real writer output",
    ),
    "runtime_compatibility" => Dict(
        "julia_compat" => "1.12",
        "required_mpskit_version" => "0.13.13",
        "required_hdf5_version" => "0.17.3",
        "required_tensorkit_version" => "0.17.1",
        "required_compute_kernel" => "Linux",
        "required_compute_architecture" => "x86_64",
        "process_cpu_time_source" =>
            "libuv uv_getrusage user plus system process CPU time",
        "executable_timing_preflight_required" => true,
        "executable_result_io_preflight_required" => true,
        "result_measured_mask_encoding" => "UInt8: 0=warm-up, 1=measured",
    ),
    "benchmark" => Dict(
        "julia_threads" => [2, 4, 8, 16],
        "slurm_cpus_per_julia_thread" => 2,
        "warmup_iterations" => 1,
        "measured_iterations" => 4,
        "total_iterations" => 5,
        "independent_restarts" => true,
        "writes_checkpoints" => false,
        "writes_full_state" => false,
        "selection_metric" => "minimum projected Shared-QOS node-hours per 100 iterations",
    ),
    "validation" => Dict(
        "maximum_final_energy_density_spread" => 1e-8,
        "maximum_final_bond_matrix_update_norm_relative_spread" => 0.10,
        "required_bond_dimension" => 512,
        "required_discarded_weight" => 0.0,
        "maximum_rss_gib" => 16.0,
    ),
    "resources" => Dict(
        "system" => "perlmutter",
        "constraint" => "cpu",
        "qos" => "shared",
        "nodes" => 1,
        "tasks" => 1,
        "cpus_per_task" => 32,
        "memory" => "16G",
        "time_limit" => "01:30:00",
        "maximum_new_node_hours" => 0.1875,
        "maximum_jobs" => 1,
        "cpu_binding" => "cores",
    ),
    "accounting" => Dict(
        "previous_job_id" => "57500598",
        "previous_job_state" => "COMPLETED",
        "previous_job_exit_code" => "0:0",
        "previous_job_elapsed_seconds" => 31715,
        "previous_job_charged_node_hours" => previous_charge,
        "previous_job_solver_step_allocated_logical_cpus" => 128,
        "previous_job_solver_step_total_cpu_seconds" => 150866,
        "previous_job_solver_step_max_rss_kib" => 10096448,
        "prior_phase1_charged_node_hours" => prior_phase1,
        "phase1_ceiling_node_hours" => 20.0,
        "prior_project_charged_node_hours" => prior_project,
        "project_ceiling_node_hours" => 150.0,
    ),
    "storage" => Dict(
        "result_directory" => "results",
        "analysis_path" => "benchmark_analysis.toml",
        "checkpoint_directory" => "none",
        "scratch_required" => false,
        "home_payload" => "small timing records, log, control, and sacct evidence only",
    ),
    "authorization" => Dict(
        "requires_explicit_submit_command" => true,
        "automatic_science_submission_allowed" => false,
        "automatic_state_promotion_allowed" => false,
    ),
    "nersc_policy" => Dict(
        "shared_charging_url" => "https://docs.nersc.gov/jobs/policy/",
        "shared_resource_formula_url" => "https://docs.nersc.gov/jobs/examples/#shared",
        "cpu_affinity_url" => "https://docs.nersc.gov/jobs/affinity/",
        "logical_cpus_per_physical_core" => 2,
        "physical_cores_per_cpu_node" => 128,
        "memory_per_logical_cpu_mb" => 1952,
    ),
    "provenance" => Dict(
        "idmrg_project_sha256" =>
            ProjectBIDMRG.file_sha256(joinpath(project_root, "idmrg/Project.toml")),
        "idmrg_manifest_sha256" =>
            ProjectBIDMRG.file_sha256(joinpath(project_root, "idmrg/Manifest.toml")),
        "solver_module_sha256" => ProjectBIDMRG.file_sha256(
            joinpath(project_root, "idmrg/src/ProjectBIDMRG.jl"),
        ),
        "benchmark_runner_sha256" => ProjectBIDMRG.file_sha256(
            joinpath(project_root, "idmrg/scripts/run_benchmark.jl"),
        ),
        "benchmark_runtime_preflight_sha256" => ProjectBIDMRG.file_sha256(
            joinpath(project_root, "idmrg/scripts/preflight_benchmark_runtime.jl"),
        ),
        "benchmark_validator_sha256" => ProjectBIDMRG.file_sha256(
            joinpath(project_root, "idmrg/scripts/validate_benchmark_control.jl"),
        ),
        "benchmark_worker_sha256" => ProjectBIDMRG.file_sha256(
            joinpath(project_root, "slurm/run_idmrg_benchmark_job.sh"),
        ),
        "benchmark_launcher_sha256" => ProjectBIDMRG.file_sha256(
            joinpath(project_root, "slurm/run_idmrg_benchmark_cpu.sh"),
        ),
        "benchmark_analyzer_sha256" => ProjectBIDMRG.file_sha256(
            joinpath(project_root, "scripts/analyze_phase1_idmrg_benchmark.jl"),
        ),
        "benchmark_preparer_sha256" => ProjectBIDMRG.file_sha256(@__FILE__),
    ),
)
open(control_path, "w") do io
    TOML.print(io, control; sorted=true)
end

println("Wrote guarded iDMRG thread benchmark control: $control_path")
println("Control SHA-256: $(ProjectBIDMRG.file_sha256(control_path))")
println("Benchmark settings: Julia threads 2,4,8,16; one warm-up plus four measured iterations")
println("Shared-QOS maximum forecast: 0.1875 node-hours")
println("No checkpoints or full-state outputs will be written")
println("No job was submitted")
