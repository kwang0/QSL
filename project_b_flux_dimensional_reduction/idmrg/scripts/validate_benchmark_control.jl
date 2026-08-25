using HDF5
using ProjectBIDMRG
using TOML

1 <= length(ARGS) <= 2 || error(
    "usage: validate_benchmark_control.jl CONTROL.toml [--postprocess]",
)
postprocess_mode = length(ARGS) == 2
postprocess_mode && ARGS[2] != "--postprocess" && error("unknown validator mode")
control_path = abspath(ARGS[1])
control = TOML.parsefile(control_path)
get(control, "artifact_kind", "") == "project_b_phase1_idmrg_benchmark_control" ||
    error("not a Project B iDMRG benchmark control")
schema_version = Int(control["schema_version"])
schema_version in (1, 2, 3, 4) || error("unsupported benchmark-control schema")

const ACCEPTED_PARENT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const SCIENCE_CONTROL_SHA256 =
    "67e258ee244ddaf397d9f493a09c1a30d4a0b1e0f4a3a001e954db8f287a89d0"
const RESULT_SHA256 =
    "c7ef67c0e22b32d581fec9ed3d4f86b14182db15a1f80688c88fc311eb326116"
const LIGHTWEIGHT_SHA256 =
    "2a3b8e22d06cb3da7b5b61a5640ea3eb418c2ca51ab0ae00c31986905c209cc2"
const SACCT_SHA256 =
    "d9b7270dbad1bf4cddbc894c3146c72d47b203b2ebe3f01c6d917e4c8a60d6c8"
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

resolve(value) = isabspath(value) ? normpath(value) :
    normpath(joinpath(dirname(control_path), value))
sources = control["sources"]
source_records = (
    ("science control", "science_control_path", "science_control_sha256", SCIENCE_CONTROL_SHA256),
    ("result bridge", "result_bridge_path", "result_bridge_sha256", RESULT_SHA256),
    ("lightweight result", "lightweight_result_path", "lightweight_result_sha256", LIGHTWEIGHT_SHA256),
    ("sacct evidence", "sacct_path", "sacct_sha256", SACCT_SHA256),
    ("efficiency evidence", "efficiency_evidence_path", "efficiency_evidence_sha256", nothing),
    ("native analysis", "native_analysis_path", "native_analysis_sha256", nothing),
)
resolved_sources = Dict{String,String}()
for (label, path_key, sha_key, fixed_sha) in source_records
    path = resolve(String(sources[path_key]))
    expected = lowercase(String(sources[sha_key]))
    fixed_sha === nothing || expected == fixed_sha || error("unpinned $label hash")
    isfile(path) || error("missing $label: $path")
    ProjectBIDMRG.file_sha256(path) == expected || error("$label SHA-256 mismatch")
    resolved_sources[path_key] = path
end
sources["accepted_parent_sha256"] == ACCEPTED_PARENT_SHA256 ||
    error("benchmark changed the immutable accepted parent")

science_control = ProjectBIDMRG.load_control(resolved_sources["science_control_path"])
ProjectBIDMRG.file_sha256(science_control.path) == SCIENCE_CONTROL_SHA256 ||
    error("science-control hash mismatch")
science_control.raw["lineage"]["parent_state_sha256"] == ACCEPTED_PARENT_SHA256 ||
    error("science control changed the accepted parent")
source_bridge = ProjectBIDMRG.load_bridge(science_control.bridge_path)
seed = ProjectBIDMRG.load_result_seed(
    resolved_sources["result_bridge_path"],
    RESULT_SHA256,
    source_bridge,
)
seed.iterations == 400 || error("latest result iteration count changed")
isapprox(seed.final_fixed_point_change, 2.311348784022773e-6; atol=1e-16, rtol=1e-12) ||
    error("latest result fixed-point change changed")

HDF5.h5open(resolved_sources["native_analysis_path"], "r") do file
    String(read(file, "artifact_kind")) == "project_b_idmrg_analysis" ||
        error("unexpected native-analysis artifact")
    !Bool(read(file, "continuation_accepted")) ||
        error("benchmark seed must remain rejected")
    String(read(file, "analysis/stage")) == "native_only" ||
        error("latest result did not receive native-first analysis")
    !Bool(read(file, "optimizer/converged")) ||
        error("latest result was relabeled native-converged")
end

failed_benchmark_charge = 0.0
if schema_version == 2
    retry = control["retry"]
    retry["failed_job_id"] == "57548405" || error("retry changed failed job id")
    retry["failed_job_state"] == "FAILED" && retry["failed_job_exit_code"] == "1:0" ||
        error("retry changed failed scheduler evidence")
    retry["failure_class"] == "launcher_project_root_resolved_from_slurm_spool" ||
        error("retry changed launcher-failure classification")
    retry["scientific_iterations_completed"] == 0 &&
        retry["timing_results_produced"] == false ||
        error("failed launcher attempt may not be treated as benchmark data")
    retry_records = (
        ("failed control", "control_path", "control_sha256", FAILED_BENCHMARK_CONTROL_SHA256),
        ("failed log", "log_path", "log_sha256", FAILED_BENCHMARK_LOG_SHA256),
        ("failed summary", "sacct_path", "sacct_sha256", FAILED_BENCHMARK_SACCT_SHA256),
        ("failed steps", "steps_path", "steps_sha256", FAILED_BENCHMARK_STEPS_SHA256),
    )
    retry_paths = Dict{String,String}()
    for (label, path_key, sha_key, expected) in retry_records
        path = resolve(String(retry[path_key]))
        String(retry[sha_key]) == expected || error("unpinned $label hash")
        isfile(path) || error("missing $label: $path")
        ProjectBIDMRG.file_sha256(path) == expected || error("$label SHA-256 mismatch")
        retry_paths[path_key] = path
    end
    occursin(
        "/var/spool/slurmd/idmrg/scripts/validate_benchmark_control.jl",
        read(retry_paths["log_path"], String),
    ) || error("failed log no longer proves the Slurm-spooled path bug")
    retry["failed_job_elapsed_seconds"] == 11 || error("failed elapsed changed")
    retry["failed_job_allocated_logical_cpus"] == 32 ||
        error("failed allocation changed")
    failed_benchmark_charge = (16 / 128) * (11 / 3600)
    isapprox(
        retry["failed_job_charged_node_hours"],
        failed_benchmark_charge;
        atol=1e-15,
        rtol=0,
    ) || error("failed benchmark charge changed")
end
if schema_version in (3, 4)
    retry = control["retry"]
    retry["failed_job_id"] == "57548405" || error("first retry changed failed job id")
    retry["failed_job_state"] == "FAILED" && retry["failed_job_exit_code"] == "1:0" ||
        error("first retry changed failed scheduler evidence")
    retry["failure_class"] == "launcher_project_root_resolved_from_slurm_spool" ||
        error("first retry changed launcher-failure classification")
    retry_records = (
        ("first failed control", "control_path", "control_sha256", FAILED_BENCHMARK_CONTROL_SHA256),
        ("first failed log", "log_path", "log_sha256", FAILED_BENCHMARK_LOG_SHA256),
        ("first failed summary", "sacct_path", "sacct_sha256", FAILED_BENCHMARK_SACCT_SHA256),
        ("first failed steps", "steps_path", "steps_sha256", FAILED_BENCHMARK_STEPS_SHA256),
    )
    first_retry_paths = Dict{String,String}()
    for (label, path_key, sha_key, expected) in retry_records
        path = resolve(String(retry[path_key]))
        String(retry[sha_key]) == expected || error("unpinned $label hash")
        isfile(path) || error("missing $label: $path")
        ProjectBIDMRG.file_sha256(path) == expected || error("$label SHA-256 mismatch")
        first_retry_paths[path_key] = path
    end
    occursin(
        "/var/spool/slurmd/idmrg/scripts/validate_benchmark_control.jl",
        read(first_retry_paths["log_path"], String),
    ) || error("first failed log no longer proves the Slurm-spooled path bug")
    retry["scientific_iterations_completed"] == 0 &&
        retry["timing_results_produced"] == false ||
        error("first failed launcher attempt may not be treated as benchmark data")
    first_charge = (16 / 128) * (11 / 3600)
    isapprox(retry["failed_job_charged_node_hours"], first_charge; atol=1e-15, rtol=0) ||
        error("first failed benchmark charge changed")

    runtime_retry = control["runtime_retry"]
    runtime_retry["failed_job_id"] == "57550459" ||
        error("runtime retry changed failed job id")
    runtime_retry["failed_job_state"] == "FAILED" &&
        runtime_retry["failed_job_exit_code"] == "1:0" ||
        error("runtime retry changed failed scheduler evidence")
    runtime_retry["failure_class"] == "unsupported_julia_1p12_base_cputime_api" ||
        error("runtime retry changed compatibility-failure classification")
    runtime_retry["scientific_iterations_completed"] == 0 &&
        runtime_retry["timing_results_produced"] == false ||
        error("runtime failure may not be treated as benchmark data")
    runtime_records = (
        ("runtime failed control", "control_path", "control_sha256", RUNTIME_FAILED_BENCHMARK_CONTROL_SHA256),
        ("runtime failed log", "log_path", "log_sha256", RUNTIME_FAILED_BENCHMARK_LOG_SHA256),
        ("runtime failed summary", "sacct_path", "sacct_sha256", RUNTIME_FAILED_BENCHMARK_SACCT_SHA256),
        ("runtime failed steps", "steps_path", "steps_sha256", RUNTIME_FAILED_BENCHMARK_STEPS_SHA256),
    )
    runtime_retry_paths = Dict{String,String}()
    for (label, path_key, sha_key, expected) in runtime_records
        path = resolve(String(runtime_retry[path_key]))
        String(runtime_retry[sha_key]) == expected || error("unpinned $label hash")
        isfile(path) || error("missing $label: $path")
        ProjectBIDMRG.file_sha256(path) == expected || error("$label SHA-256 mismatch")
        runtime_retry_paths[path_key] = path
    end
    runtime_log = read(runtime_retry_paths["log_path"], String)
    occursin("UndefVarError: `cputime` not defined in `Base`", runtime_log) ||
        error("runtime failed log no longer proves the Julia 1.12 timing API bug")
    occursin("ProjectBIDMRG.jl:650", runtime_log) ||
        error("runtime failed log no longer locates the timing failure")
    runtime_retry["failed_job_elapsed_seconds"] == 202 ||
        error("runtime failed elapsed changed")
    runtime_retry["failed_job_allocated_logical_cpus"] == 32 ||
        error("runtime failed allocation changed")
    runtime_charge = (16 / 128) * (202 / 3600)
    isapprox(
        runtime_retry["failed_job_charged_node_hours"],
        runtime_charge;
        atol=1e-15,
        rtol=0,
    ) || error("runtime failed benchmark charge changed")
    failed_benchmark_charge = first_charge + runtime_charge
end
if schema_version == 4
    writer_retry = control["writer_retry"]
    writer_retry["failed_job_id"] == "57574096" ||
        error("writer retry changed failed job id")
    writer_retry["failed_job_state"] == "FAILED" &&
        writer_retry["failed_job_exit_code"] == "1:0" ||
        error("writer retry changed failed scheduler evidence")
    writer_retry["failure_class"] ==
        "hdf5_bitvector_result_serialization_after_solver_updates" ||
        error("writer retry changed result-I/O-failure classification")
    writer_retry["solver_updates_completed_before_writer_failure"] == 5 ||
        error("writer retry changed completed update count")
    writer_retry["completed_thread_settings"] == 0 &&
        writer_retry["timing_results_produced"] == false &&
        writer_retry["partial_result_contains_timing_histories"] == false ||
        error("writer failure may not be treated as benchmark timing data")
    writer_records = (
        ("writer failed control", "control_path", "control_sha256", WRITER_FAILED_BENCHMARK_CONTROL_SHA256),
        ("writer failed log", "log_path", "log_sha256", WRITER_FAILED_BENCHMARK_LOG_SHA256),
        ("writer failed summary", "sacct_path", "sacct_sha256", WRITER_FAILED_BENCHMARK_SACCT_SHA256),
        ("writer failed steps", "steps_path", "steps_sha256", WRITER_FAILED_BENCHMARK_STEPS_SHA256),
        ("writer failed partial result", "partial_result_path", "partial_result_sha256", WRITER_FAILED_PARTIAL_RESULT_SHA256),
    )
    writer_retry_paths = Dict{String,String}()
    for (label, path_key, sha_key, expected) in writer_records
        path = resolve(String(writer_retry[path_key]))
        String(writer_retry[sha_key]) == expected || error("unpinned $label hash")
        isfile(path) || error("missing $label: $path")
        ProjectBIDMRG.file_sha256(path) == expected || error("$label SHA-256 mismatch")
        writer_retry_paths[path_key] = path
    end
    writer_log = read(writer_retry_paths["log_path"], String)
    occursin("no method matching strides(::BitVector)", writer_log) ||
        error("writer failed log no longer proves the HDF5 BitVector bug")
    occursin("write_benchmark_result", writer_log) ||
        error("writer failed log no longer locates the result-writer failure")
    writer_retry["failed_job_elapsed_seconds"] == 889 ||
        error("writer failed elapsed changed")
    writer_retry["failed_job_allocated_logical_cpus"] == 32 ||
        error("writer failed allocation changed")
    writer_retry["failed_step_julia_threads"] == 2 &&
        writer_retry["failed_step_allocated_logical_cpus"] == 4 &&
        writer_retry["failed_step_elapsed_seconds"] == 791 &&
        writer_retry["failed_step_max_rss_kib"] == 7327392 ||
        error("writer failed step evidence changed")
    writer_steps = read(writer_retry_paths["steps_path"], String)
    occursin(
        "57574096.0|pb1-idmrg-t2|FAILED|791|00:13:11||1|4|4|14:31.541|00:14:21|7327392K|7327392K|1:0",
        writer_steps,
    ) || error("writer failed step accounting changed")
    HDF5.h5open(writer_retry_paths["partial_result_path"], "r") do file
        Int(read(file, "schema_version")) == 1 ||
            error("writer failed partial result schema changed")
        Int(read(file, "benchmark/julia_threads")) == 2 ||
            error("writer failed partial result thread setting changed")
        Int(read(file, "benchmark/total_iterations")) == 5 ||
            error("writer failed partial result iteration count changed")
        String(read(file, "source/benchmark_control_sha256")) ==
            WRITER_FAILED_BENCHMARK_CONTROL_SHA256 ||
            error("writer failed partial result control lineage changed")
        String(read(file, "source/result_seed_sha256")) == RESULT_SHA256 ||
            error("writer failed partial result seed lineage changed")
        !haskey(file, "optimizer") ||
            error("writer failed partial result unexpectedly contains timing histories")
    end
    writer_charge = (16 / 128) * (889 / 3600)
    isapprox(
        writer_retry["failed_job_charged_node_hours"],
        writer_charge;
        atol=1e-15,
        rtol=0,
    ) || error("writer failed benchmark charge changed")
    failed_benchmark_charge += writer_charge
end

benchmark = control["benchmark"]
threads = Int.(benchmark["julia_threads"])
threads == [2, 4, 8, 16] || error("benchmark thread matrix changed")
Int(benchmark["slurm_cpus_per_julia_thread"]) == 2 ||
    error("benchmark must allocate two logical CPUs per Julia thread")
Int(benchmark["warmup_iterations"]) == 1 || error("warm-up count changed")
Int(benchmark["measured_iterations"]) == 4 || error("measured count changed")
Int(benchmark["total_iterations"]) == 5 || error("total benchmark iterations changed")
benchmark["independent_restarts"] == true || error("benchmark settings share state")
benchmark["writes_checkpoints"] == false || error("benchmark may not write checkpoints")

analysis_validation = control["validation"]
analysis_validation["required_bond_dimension"] == 512 ||
    error("benchmark chi validation changed")
analysis_validation["required_discarded_weight"] == 0.0 ||
    error("benchmark discarded-weight validation changed")
analysis_validation["maximum_final_energy_density_spread"] == 1e-8 ||
    error("benchmark trajectory energy gate changed")
analysis_validation["maximum_final_bond_matrix_update_norm_relative_spread"] == 0.10 ||
    error("benchmark fixed-point trajectory gate changed")
analysis_validation["maximum_rss_gib"] == 16.0 ||
    error("benchmark memory validation changed")

resources = control["resources"]
resources["system"] == "perlmutter" && resources["constraint"] == "cpu" ||
    error("benchmark platform changed")
resources["qos"] == "shared" || error("benchmark must use Shared QOS")
resources["nodes"] == 1 && resources["tasks"] == 1 ||
    error("benchmark resource shape changed")
resources["cpus_per_task"] == 32 || error("benchmark allocation must be 32 logical CPUs")
resources["memory"] == "16G" || error("benchmark memory guard changed")
resources["time_limit"] == "01:30:00" || error("benchmark time guard changed")
resources["maximum_jobs"] == 1 || error("benchmark one-job guard changed")
isapprox(resources["maximum_new_node_hours"], 0.1875; atol=1e-12, rtol=0) ||
    error("benchmark charge ceiling changed")
resources["cpu_binding"] == "cores" || error("benchmark CPU binding changed")

accounting = control["accounting"]
accounting["previous_job_id"] == "57500598" || error("latest job id changed")
accounting["previous_job_state"] == "COMPLETED" || error("latest job not completed")
accounting["previous_job_exit_code"] == "0:0" || error("latest job exit changed")
accounting["previous_job_elapsed_seconds"] == 31715 || error("latest elapsed changed")
isapprox(
    accounting["previous_job_charged_node_hours"],
    31715 / 3600;
    atol=1e-12,
    rtol=0,
) || error("latest regular-QOS charge changed")
prior_phase1 = Float64(accounting["prior_phase1_charged_node_hours"])
prior_project = Float64(accounting["prior_project_charged_node_hours"])
expected_prior_phase1 = 12.105379774922222 + failed_benchmark_charge
expected_prior_project = 13.199812774922222 + failed_benchmark_charge
isapprox(prior_phase1, expected_prior_phase1; atol=5e-10, rtol=0) ||
    error("Phase 1 total changed")
isapprox(prior_project, expected_prior_project; atol=5e-10, rtol=0) ||
    error("project total changed")
prior_phase1 + resources["maximum_new_node_hours"] <=
    accounting["phase1_ceiling_node_hours"] || error("benchmark exceeds Phase 1 ceiling")
prior_project + resources["maximum_new_node_hours"] <=
    accounting["project_ceiling_node_hours"] || error("benchmark exceeds project ceiling")

authorization = control["authorization"]
authorization["requires_explicit_submit_command"] == true ||
    error("benchmark submit authorization changed")
authorization["automatic_science_submission_allowed"] == false ||
    error("benchmark may not trigger a science submission")

if schema_version in (3, 4)
    runtime_compatibility = control["runtime_compatibility"]
    runtime_compatibility["julia_compat"] == "1.12" ||
        error("benchmark Julia compatibility changed")
    runtime_compatibility["process_cpu_time_source"] ==
        "libuv uv_getrusage user plus system process CPU time" ||
        error("benchmark process CPU timing source changed")
    runtime_compatibility["executable_timing_preflight_required"] == true ||
        error("benchmark executable timing preflight was disabled")
    if schema_version == 4
        runtime_compatibility["required_mpskit_version"] == "0.13.13" ||
            error("benchmark MPSKit pin changed")
        runtime_compatibility["required_hdf5_version"] == "0.17.3" ||
            error("benchmark HDF5 pin changed")
        runtime_compatibility["required_tensorkit_version"] == "0.17.1" ||
            error("benchmark TensorKit pin changed")
        runtime_compatibility["required_compute_kernel"] == "Linux" ||
            error("benchmark compute kernel changed")
        runtime_compatibility["required_compute_architecture"] == "x86_64" ||
            error("benchmark compute architecture changed")
        runtime_compatibility["executable_result_io_preflight_required"] == true ||
            error("benchmark executable result-I/O preflight was disabled")
        runtime_compatibility["result_measured_mask_encoding"] ==
            "UInt8: 0=warm-up, 1=measured" ||
            error("benchmark result mask encoding changed")
    end
end

project_root = normpath(joinpath(@__DIR__, "../.."))
provenance = control["provenance"]
provenance_paths = Dict(
    "idmrg_project_sha256" => joinpath(project_root, "idmrg/Project.toml"),
    "idmrg_manifest_sha256" => joinpath(project_root, "idmrg/Manifest.toml"),
    "solver_module_sha256" => joinpath(project_root, "idmrg/src/ProjectBIDMRG.jl"),
    "benchmark_runner_sha256" => joinpath(project_root, "idmrg/scripts/run_benchmark.jl"),
    "benchmark_validator_sha256" => @__FILE__,
    "benchmark_worker_sha256" => joinpath(project_root, "slurm/run_idmrg_benchmark_job.sh"),
    "benchmark_launcher_sha256" => joinpath(project_root, "slurm/run_idmrg_benchmark_cpu.sh"),
    "benchmark_analyzer_sha256" => joinpath(project_root, "scripts/analyze_phase1_idmrg_benchmark.jl"),
    "benchmark_preparer_sha256" => joinpath(project_root, "scripts/prepare_phase1_idmrg_benchmark.jl"),
)
if schema_version in (3, 4)
    provenance_paths["benchmark_runtime_preflight_sha256"] =
        joinpath(project_root, "idmrg/scripts/preflight_benchmark_runtime.jl")
end
for (key, path) in provenance_paths
    expected = lowercase(String(provenance[key]))
    occursin(r"^[0-9a-f]{64}$", expected) || error("invalid provenance digest: $key")
    if !postprocess_mode
        ProjectBIDMRG.file_sha256(path) == expected ||
            error("pinned benchmark provenance mismatch for $path")
    end
end

storage = control["storage"]
result_directory = resolve(String(storage["result_directory"]))
analysis_path = resolve(String(storage["analysis_path"]))
fields = (
    ProjectBIDMRG.file_sha256(control_path),
    resolved_sources["science_control_path"],
    resolved_sources["result_bridge_path"],
    join(string.(threads), ","),
    string(benchmark["slurm_cpus_per_julia_thread"]),
    string(benchmark["warmup_iterations"]),
    string(benchmark["measured_iterations"]),
    string(benchmark["total_iterations"]),
    result_directory,
    analysis_path,
    string(resources["nodes"]),
    string(resources["cpus_per_task"]),
    String(resources["memory"]),
    String(resources["time_limit"]),
    String(resources["qos"]),
    string(resources["maximum_new_node_hours"]),
    string(prior_phase1),
    string(accounting["phase1_ceiling_node_hours"]),
    string(prior_project),
    string(accounting["project_ceiling_node_hours"]),
)
println(join(fields, '\t'))
