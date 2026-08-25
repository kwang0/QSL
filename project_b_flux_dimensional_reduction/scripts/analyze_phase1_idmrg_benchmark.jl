using HDF5
using Printf
using ProjectBIDMRG
using Statistics
using TOML

length(ARGS) == 4 || error(
    "usage: analyze_phase1_idmrg_benchmark.jl CONTROL.toml JOB_ID " *
    "SACCT_STEPS.tsv OUTPUT.toml",
)

control_path = abspath(ARGS[1])
job_id = ARGS[2]
sacct_path = abspath(ARGS[3])
output_path = abspath(ARGS[4])
occursin(r"^[0-9]+$", job_id) || error("invalid benchmark job id")
ispath(output_path) && error("refusing to overwrite benchmark analysis: $output_path")
control = TOML.parsefile(control_path)
benchmark = control["benchmark"]
resources = control["resources"]
storage = control["storage"]
validation = control["validation"]
resolve(value) = isabspath(value) ? normpath(value) :
    normpath(joinpath(dirname(control_path), value))
result_directory = resolve(String(storage["result_directory"]))

function read_pipe_table(path)
    lines = filter(!isempty, readlines(path))
    isempty(lines) && error("empty sacct table: $path")
    header = split(first(lines), '|'; keepempty=true)
    rows = Dict{String,Dict{String,String}}()
    for line in Iterators.drop(lines, 1)
        values = split(line, '|'; keepempty=true)
        length(values) < length(header) && continue
        row = Dict(header[index] => values[index] for index in eachindex(header))
        rows[row["JobIDRaw"]] = row
    end
    return rows
end

function parse_cpu_seconds(value)
    isempty(value) && return NaN
    day_parts = split(value, '-'; limit=2)
    days = length(day_parts) == 2 ? parse(Int, day_parts[1]) : 0
    clock = last(day_parts)
    parts = split(clock, ':')
    length(parts) == 3 || error("unrecognized sacct CPU time: $value")
    hours = parse(Int, parts[1])
    minutes = parse(Int, parts[2])
    seconds = parse(Float64, parts[3])
    return days * 86400 + hours * 3600 + minutes * 60 + seconds
end

function parse_rss_gib(value)
    isempty(value) && return NaN
    matched = match(r"^([0-9]+(?:\.[0-9]+)?)([KMGTP]?)$", value)
    matched === nothing && error("unrecognized sacct RSS: $value")
    number = parse(Float64, matched.captures[1])
    suffix = matched.captures[2]
    factor = Dict("" => 1.0, "K" => 2.0^10, "M" => 2.0^20,
        "G" => 2.0^30, "T" => 2.0^40, "P" => 2.0^50)[suffix]
    return number * factor / 2.0^30
end

function normalized_state(value)
    state = first(split(value))
    return first(split(state, '+'))
end

sacct_rows = read_pipe_table(sacct_path)
haskey(sacct_rows, job_id) || error("sacct table lacks allocation row $job_id")
allocation_row = sacct_rows[job_id]
normalized_state(allocation_row["State"]) == "COMPLETED" ||
    error("benchmark allocation did not complete")
allocation_row["ExitCode"] == "0:0" || error("benchmark allocation exit was not 0:0")

threads_values = Int.(benchmark["julia_threads"])
warmup = Int(benchmark["warmup_iterations"])
total_iterations = Int(benchmark["total_iterations"])
memory_mb = 16 * 1024
memory_per_logical_cpu_mb = 1952
records = Dict{String,Any}[]
for threads in threads_values
    result_path = joinpath(result_directory, "benchmark_threads_$(threads).h5")
    isfile(result_path) || error("missing benchmark result: $result_path")
    record = HDF5.h5open(result_path, "r") do file
        Int(read(file, "schema_version")) == 2 ||
            error("benchmark result does not use the validated schema-2 writer")
        String(read(file, "artifact_kind")) ==
            "project_b_mpskit_idmrg_thread_benchmark" ||
            error("unexpected benchmark artifact: $result_path")
        startswith(String(read(file, "julia_version")), "1.12.") ||
            error("benchmark result did not use Julia 1.12.x")
        String(read(file, "mpskit_version")) == "0.13.13" ||
            error("benchmark result MPSKit version mismatch")
        String(read(file, "hdf5_version")) == "0.17.3" ||
            error("benchmark result HDF5 version mismatch")
        String(read(file, "tensorkit_version")) == "0.17.1" ||
            error("benchmark result TensorKit version mismatch")
        Int(read(file, "benchmark/julia_threads")) == threads ||
            error("benchmark thread label mismatch")
        Int(read(file, "runtime/julia_threads")) == threads ||
            error("benchmark Julia runtime thread count mismatch")
        String(read(file, "runtime/kernel")) == "Linux" ||
            error("benchmark result was not produced on Linux")
        String(read(file, "runtime/architecture")) == "x86_64" ||
            error("benchmark result was not produced on Perlmutter x86_64")
        String(read(file, "source/benchmark_control_sha256")) ==
            ProjectBIDMRG.file_sha256(control_path) ||
            error("benchmark-control hash mismatch")
        String(read(file, "source/result_seed_sha256")) ==
            String(control["sources"]["result_bridge_sha256"]) ||
            error("benchmark seed hash mismatch")
        String(read(file, "lineage/accepted_parent_sha256")) ==
            String(control["sources"]["accepted_parent_sha256"]) ||
            error("benchmark accepted-parent hash mismatch")
        Int(read(file, "benchmark/total_iterations")) == total_iterations ||
            error("benchmark iteration count mismatch")
        Int(read(file, "benchmark/warmup_iterations")) == warmup ||
            error("benchmark warm-up count mismatch")
        measured_mask = UInt8.(read(file, "benchmark/measured_mask"))
        measured_mask == UInt8[index > warmup for index in 1:total_iterations] ||
            error("benchmark measured-mask encoding mismatch")
        String(read(file, "benchmark/measured_mask_encoding")) ==
            "UInt8: 0=warm-up, 1=measured" ||
            error("benchmark measured-mask semantics mismatch")
        !Bool(read(file, "benchmark/full_state_payload_included")) ||
            error("benchmark result unexpectedly includes a full state")
        String(read(file, "runtime/process_cpu_time_source")) ==
            "libuv uv_getrusage user plus system process CPU time" ||
            error("benchmark process CPU timing source mismatch")
        elapsed = Float64.(read(file, "optimizer/history/elapsed_seconds"))
        cpu = Float64.(read(file, "optimizer/history/cpu_seconds"))
        fixed_point = Float64.(read(
            file,
            "optimizer/history/bond_matrix_update_norm",
        ))
        energy = Float64.(read(file, "optimizer/history/energy_density"))
        discarded = Float64.(read(file, "optimizer/history/discarded_weight"))
        maxdim = Int.(read(file, "optimizer/history/maximum_bond_dimension"))
        all(length(values) == total_iterations for values in
            (elapsed, cpu, fixed_point, energy, discarded, maxdim)) ||
            error("benchmark histories have inconsistent lengths")
        step_id = String(read(file, "runtime/slurm_step_id"))
        step_id != "none" || error("benchmark result lacks a Slurm step id")
        return (;
            result_path,
            result_sha256=ProjectBIDMRG.file_sha256(result_path),
            step_id,
            elapsed,
            cpu,
            fixed_point,
            energy,
            discarded,
            maxdim,
            initialization_elapsed=Float64(read(
                file,
                "runtime/initialization_elapsed_seconds",
            )),
        )
    end
    step_key = "$job_id.$(record.step_id)"
    haskey(sacct_rows, step_key) || error("sacct table lacks benchmark step $step_key")
    step = sacct_rows[step_key]
    normalized_state(step["State"]) == "COMPLETED" ||
        error("benchmark step $step_key did not complete")
    step["ExitCode"] == "0:0" || error("benchmark step $step_key exit was not 0:0")
    slurm_elapsed = parse(Int, step["ElapsedRaw"])
    allocated_logical_cpus = parse(Int, step["AllocCPUS"])
    allocated_logical_cpus == 2 * threads ||
        error("benchmark step $step_key CPU allocation mismatch")
    total_cpu_seconds = parse_cpu_seconds(step["TotalCPU"])
    max_rss_gib = parse_rss_gib(step["MaxRSS"])
    measured_elapsed = record.elapsed[(warmup + 1):end]
    median_seconds = median(measured_elapsed)
    mean_seconds = mean(measured_elapsed)
    memory_logical_cpus = ceil(Int, memory_mb / memory_per_logical_cpu_mb)
    charged_physical_cores = ceil(
        Int,
        max(memory_logical_cpus, allocated_logical_cpus) / 2,
    )
    projected_node_hours_per_100 = median_seconds * 100 / 3600 *
        charged_physical_cores / 128
    valid = all(isfinite, record.elapsed) && all(>=(0), record.elapsed) &&
        all(isfinite, record.cpu) && all(>=(0), record.cpu) &&
        all(isfinite, record.fixed_point) &&
        all(isfinite, record.energy) &&
        all(==(Float64(validation["required_discarded_weight"])), record.discarded) &&
        all(==(Int(validation["required_bond_dimension"])), record.maxdim) &&
        isfinite(total_cpu_seconds) &&
        isfinite(max_rss_gib) &&
        max_rss_gib < Float64(validation["maximum_rss_gib"])
    push!(records, Dict{String,Any}(
        "julia_threads" => threads,
        "slurm_step_id" => record.step_id,
        "slurm_logical_cpus" => allocated_logical_cpus,
        "charged_physical_cores_if_right_sized" => charged_physical_cores,
        "initialization_elapsed_seconds" => record.initialization_elapsed,
        "measured_iteration_seconds" => measured_elapsed,
        "median_measured_iteration_seconds" => median_seconds,
        "mean_measured_iteration_seconds" => mean_seconds,
        "iterations_per_hour" => 3600 / median_seconds,
        "projected_node_hours_per_100_iterations" => projected_node_hours_per_100,
        "slurm_step_elapsed_seconds" => slurm_elapsed,
        "slurm_total_cpu_seconds" => total_cpu_seconds,
        "scheduler_cpu_efficiency" =>
            total_cpu_seconds / (slurm_elapsed * allocated_logical_cpus),
        "julia_thread_capacity_utilization" =>
            total_cpu_seconds / (slurm_elapsed * threads),
        "max_rss_gib" => max_rss_gib,
        "final_bond_matrix_update_norm" => last(record.fixed_point),
        "final_energy_density" => last(record.energy),
        "result_path" => record.result_path,
        "result_sha256" => record.result_sha256,
        "valid" => valid,
    ))
end

final_energies = Float64[record["final_energy_density"] for record in records]
final_fixed_points = Float64[record["final_bond_matrix_update_norm"] for record in records]
energy_spread = maximum(final_energies) - minimum(final_energies)
fixed_point_relative_spread = (maximum(final_fixed_points) - minimum(final_fixed_points)) /
    max(minimum(final_fixed_points), eps(Float64))
trajectory_consistent = energy_spread <=
    Float64(validation["maximum_final_energy_density_spread"]) &&
    fixed_point_relative_spread <= Float64(
        validation["maximum_final_bond_matrix_update_norm_relative_spread"],
    )
all_valid = all(Bool(record["valid"]) for record in records) && trajectory_consistent
recommendation = if all_valid
    best = records[argmin([
        Float64(record["projected_node_hours_per_100_iterations"]) for record in records
    ])]
    Dict{String,Any}(
        "status" => "ready",
        "julia_threads" => best["julia_threads"],
        "slurm_logical_cpus" => best["slurm_logical_cpus"],
        "memory" => "16G",
        "qos" => "shared",
        "selection_metric" => "minimum projected node-hours per 100 measured iterations",
        "projected_node_hours_per_100_iterations" =>
            best["projected_node_hours_per_100_iterations"],
        "automatic_science_submission" => false,
    )
else
    Dict{String,Any}(
        "status" => "blocked_inconsistent_or_invalid_benchmark",
        "automatic_science_submission" => false,
    )
end

allocation_elapsed = parse(Int, allocation_row["ElapsedRaw"])
allocation_logical_cpus = parse(Int, allocation_row["AllocCPUS"])
allocation_physical_cores = ceil(
    Int,
    max(ceil(Int, memory_mb / memory_per_logical_cpu_mb), allocation_logical_cpus) / 2,
)
calculated_benchmark_charge = allocation_elapsed / 3600 * allocation_physical_cores / 128
analysis = Dict{String,Any}(
    "artifact_kind" => "project_b_phase1_idmrg_benchmark_analysis",
    "schema_version" => 1,
    "control_path" => control_path,
    "control_sha256" => ProjectBIDMRG.file_sha256(control_path),
    "job_id" => job_id,
    "sacct_path" => sacct_path,
    "sacct_sha256" => ProjectBIDMRG.file_sha256(sacct_path),
    "allocation_elapsed_seconds" => allocation_elapsed,
    "allocation_logical_cpus" => allocation_logical_cpus,
    "allocation_charged_physical_cores" => allocation_physical_cores,
    "calculated_benchmark_node_hours" => calculated_benchmark_charge,
    "final_energy_spread" => energy_spread,
    "final_bond_matrix_update_norm_relative_spread" => fixed_point_relative_spread,
    "trajectory_consistent" => trajectory_consistent,
    "all_settings_valid" => all_valid,
    "settings" => records,
    "recommendation" => recommendation,
)
mkpath(dirname(output_path))
open(output_path, "w") do io
    TOML.print(io, analysis; sorted=true)
end

println("iDMRG thread benchmark analysis")
@printf("  calculated benchmark charge: %.6f node-hours\n", calculated_benchmark_charge)
for record in records
    @printf(
        "  %2d threads: median %.3f s/iter, %.6f node-h/100 iter, CPU efficiency %.1f%%, MaxRSS %.3f GiB\n",
        record["julia_threads"],
        record["median_measured_iteration_seconds"],
        record["projected_node_hours_per_100_iterations"],
        100 * record["scheduler_cpu_efficiency"],
        record["max_rss_gib"],
    )
end
println("  trajectory consistency: ", trajectory_consistent)
println("  recommendation status: ", recommendation["status"])
if recommendation["status"] == "ready"
    println("  recommended Julia threads: ", recommendation["julia_threads"])
    println("  recommended Slurm logical CPUs: ", recommendation["slurm_logical_cpus"])
end
println("  automatic science submission: disabled")
println("immutable benchmark analysis: $output_path")
println("analysis SHA-256: $(ProjectBIDMRG.file_sha256(output_path))")
