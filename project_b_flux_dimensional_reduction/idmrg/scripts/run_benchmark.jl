using ProjectBIDMRG
using TOML

length(ARGS) == 3 || error(
    "usage: run_benchmark.jl BENCHMARK_CONTROL.toml JULIA_THREADS RESULT.h5",
)

benchmark_control_path = abspath(ARGS[1])
threads = parse(Int, ARGS[2])
result_path = abspath(ARGS[3])
control = TOML.parsefile(benchmark_control_path)
get(control, "artifact_kind", "") == "project_b_phase1_idmrg_benchmark_control" ||
    error("not a Project B iDMRG benchmark control")
benchmark = control["benchmark"]
threads in Int.(benchmark["julia_threads"]) ||
    error("thread count is not authorized by the benchmark control")

resolve(value) = isabspath(value) ? normpath(value) :
    normpath(joinpath(dirname(benchmark_control_path), value))
sources = control["sources"]
run = ProjectBIDMRG.run_benchmark(
    resolve(String(sources["science_control_path"])),
    resolve(String(sources["result_bridge_path"])),
    String(sources["result_bridge_sha256"]);
    total_iterations=Int(benchmark["total_iterations"]),
    warmup_iterations=Int(benchmark["warmup_iterations"]),
    expected_threads=threads,
    slurm_cpus_per_thread=Int(benchmark["slurm_cpus_per_julia_thread"]),
)
result = ProjectBIDMRG.write_benchmark_result(
    result_path,
    run,
    benchmark_control_path,
)
println("iDMRG benchmark Julia threads: $threads")
println("benchmark result: ", result.path)
println("benchmark result SHA-256: ", result.sha256)
println("benchmark result bytes: ", result.bytes)
