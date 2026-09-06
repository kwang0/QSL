#!/usr/bin/env julia

using HDF5
using TOML
using TriangularJ1J2ProjectB

4 <= length(ARGS) <= 5 || error(
    "usage: prepare_yc8_1_chi1024_full_sweep.jl " *
    "ACCEPTED_THETA_0P45_STATE.h5 STATE_SHA256 " *
    "FORWARD_REVERSE_ANALYSIS.toml ANALYSIS_SHA256 [CONFIG_DIRECTORY]",
)

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const TEMPLATE = joinpath(
    PROJECT_ROOT,
    "configs",
    "science_yc8_1_primary_forward_chi1024_bridge.toml",
)
const ROOT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"

function require_sha256(path, expected, label)
    normalized = lowercase(String(expected))
    occursin(r"^[0-9a-f]{64}$", normalized) || error("invalid $label SHA-256")
    PB.file_sha256(path) == normalized || error("$label SHA-256 mismatch")
    return normalized
end

endpoint_path = abspath(ARGS[1])
isfile(endpoint_path) || error("missing accepted theta/pi=0.45 endpoint: $endpoint_path")
endpoint_sha256 = require_sha256(endpoint_path, ARGS[2], "endpoint")
analysis_path = abspath(ARGS[3])
isfile(analysis_path) || error("missing forward/reverse analysis: $analysis_path")
analysis_sha256 = require_sha256(analysis_path, ARGS[4], "forward/reverse analysis")

endpoint_config = HDF5.h5open(endpoint_path, "r") do file
    haskey(file, "config_text") || error("endpoint lacks embedded configuration")
    TOML.parse(String(read(file, "config_text")))
end
endpoint_campaign = get(endpoint_config, "campaign", Dict{String,Any}())
get(endpoint_campaign, "immutable_lineage_root_sha256", "") == ROOT_SHA256 ||
    error("endpoint embedded configuration changed the lineage root")
get(endpoint_campaign, "mode", "") == "forward_bridge" ||
    error("full sweep must start from the accepted forward-bridge endpoint")

endpoint = PB.read_state_file(endpoint_path)
endpoint.converged && endpoint.continuation_accepted ||
    error("full sweep requires an accepted endpoint")
endpoint.circumference == 8 && endpoint.shift == 1 || error("endpoint is not YC8-1")
endpoint.mps_period == 2 || error("endpoint is not period 2")
endpoint.twist_gauge === :uniform || error("endpoint changed the uniform twist gauge")
endpoint.branch == "primary_forward_chi512_legacy_0p1" || error("endpoint changed branch")
endpoint.preparation == "independent_theta0_alternating_chi512" ||
    error("endpoint changed preparation")
endpoint.direction === :forward || error("endpoint is not on the primary-forward direction")
isapprox(endpoint.theta_over_pi, 0.45; atol=1e-12, rtol=0) ||
    error("endpoint is not theta/pi=0.45")
PB.maxlinkdim(endpoint.psi) == 1024 || error("endpoint is not chi=1024")
length(endpoint.flux_history_over_pi) >= 3 || error("endpoint lacks lineage history")
all(isapprox.(
    endpoint.flux_history_over_pi[1:3],
    [0.0, 0.1, 0.15];
    atol=1e-12,
    rtol=0,
)) || error("endpoint changed the immutable accepted lineage prefix")

analysis = TOML.parsefile(analysis_path)
get(analysis, "artifact_kind", "") ==
    "project_b_yc8_1_chi1024_forward_reverse_analysis" ||
    error("unexpected forward/reverse analysis kind")
get(analysis, "immutable_lineage_root_sha256", "") == ROOT_SHA256 ||
    error("forward/reverse analysis changed the lineage root")
Bool(get(analysis, "all_common_points_passed", false)) ||
    error("forward/reverse validation did not pass every common theta")
Int(get(analysis, "common_theta_count", 0)) == 12 ||
    error("forward/reverse validation does not cover all 12 common theta points")
isempty(get(analysis, "failed_theta_over_pi", Any[])) ||
    error("forward/reverse validation records failed theta points")
for (key, expected) in (
    ("overlap_alarm_floor_per_site", 0.90),
    ("cut_entropy_jump_threshold", 0.10),
    ("energy_term_rms_jump_threshold", 0.02),
    ("magnetization_rms_jump_threshold", 0.001),
    ("mean_schmidt_total_variation_threshold", 0.05),
    ("maximum_log_correlation_length_jump_threshold", 0.05),
)
    isapprox(Float64(analysis[key]), expected; atol=1e-12, rtol=0) ||
        error("forward/reverse analysis changed $key")
end
Float64.(analysis["correlation_length_physical_sz_sectors"]) == [0.0, 1.0] ||
    error("forward/reverse analysis changed correlation-length sectors")
comparison_path = String(analysis["comparison_table_path"])
isfile(comparison_path) || error("missing forward/reverse comparison table: $comparison_path")
PB.file_sha256(comparison_path) == lowercase(String(analysis["comparison_table_sha256"])) ||
    error("forward/reverse comparison-table SHA-256 mismatch")

short_hash = first(endpoint_sha256, 12)
experiment = "primary_forward_chi1024_full_from_p0p45000000_$short_hash"
config_directory = length(ARGS) == 5 ? abspath(ARGS[5]) : joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_generated_configs",
    experiment,
)
output_directory = joinpath(
    PROJECT_ROOT,
    "output",
    "science",
    "yc8_1",
    experiment,
    "seed_101",
    "chi1024",
)
config_path = joinpath(config_directory, "yc8_1_chi1024_primary_forward_full_sweep.toml")
ispath(config_path) && error("refusing to overwrite generated full-sweep configuration")
ispath(output_directory) && error("refusing to reuse full-sweep output")

configuration = TOML.parsefile(TEMPLATE)
campaign = configuration["campaign"]
campaign["mode"] = "forward_full_sweep"
campaign["fixed_theta_growth_before_flux"] = false
campaign["source_forward_endpoint_path"] = endpoint_path
campaign["source_forward_endpoint_sha256"] = endpoint_sha256
campaign["forward_reverse_analysis_path"] = analysis_path
campaign["forward_reverse_analysis_sha256"] = analysis_sha256
campaign["forward_reverse_comparison_path"] = comparison_path
campaign["forward_reverse_comparison_sha256"] =
    lowercase(String(analysis["comparison_table_sha256"]))
campaign["immutable_lineage_root_sha256"] = ROOT_SHA256
scan = configuration["scan"]
scan["direction"] = "forward"
scan["lineage_policy"] = "strict"
scan["fluxes_over_pi"] = collect(0.475:0.025:1.0)
scan["initial_state_file"] = endpoint_path
scan["initial_state_sha256"] = endpoint_sha256
pop!(scan, "optimizer_checkpoint_file", nothing)
pop!(scan, "optimizer_checkpoint_sha256", nothing)
configuration["runtime"]["output_directory"] = output_directory

mkpath(config_directory)
open(config_path, "w") do io
    println(io, "# Guarded YC8-1 chi=1024 primary-forward continuation to theta/pi=1")
    println(io, "# Accepted forward endpoint: $endpoint_path")
    println(io, "# Endpoint SHA-256: $endpoint_sha256")
    println(io, "# Forward/reverse decision: $analysis_path")
    println(io, "# Decision SHA-256: $analysis_sha256")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println("Prepared primary-forward grid 0.475:0.025:1.0 after passed reverse validation.")
println("The immutable theta/pi=0.15 lineage root remains $ROOT_SHA256.")
