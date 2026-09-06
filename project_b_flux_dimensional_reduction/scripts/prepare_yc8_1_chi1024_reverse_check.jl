#!/usr/bin/env julia

using HDF5
using TOML
using TriangularJ1J2ProjectB

2 <= length(ARGS) <= 3 || error(
    "usage: prepare_yc8_1_chi1024_reverse_check.jl " *
    "ACCEPTED_THETA_0P45_STATE.h5 STATE_SHA256 [CONFIG_DIRECTORY]",
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

endpoint_path = abspath(ARGS[1])
expected_sha256 = lowercase(ARGS[2])
occursin(r"^[0-9a-f]{64}$", expected_sha256) || error("invalid endpoint SHA-256")
PB.file_sha256(endpoint_path) == expected_sha256 || error("endpoint SHA-256 mismatch")
endpoint_config = HDF5.h5open(endpoint_path, "r") do file
    haskey(file, "config_text") || error("endpoint lacks embedded configuration")
    TOML.parse(String(read(file, "config_text")))
end
get(
    get(endpoint_config, "campaign", Dict{String,Any}()),
    "immutable_lineage_root_sha256",
    "",
) == ROOT_SHA256 || error("endpoint embedded configuration changed the lineage root")
endpoint = PB.read_state_file(endpoint_path)
endpoint.converged && endpoint.continuation_accepted ||
    error("reverse validation requires an accepted endpoint")
endpoint.circumference == 8 && endpoint.shift == 1 || error("endpoint is not YC8-1")
endpoint.mps_period == 2 || error("endpoint is not period 2")
endpoint.twist_gauge === :uniform || error("endpoint changed the uniform twist gauge")
endpoint.branch == "primary_forward_chi512_legacy_0p1" || error("endpoint changed branch")
endpoint.preparation == "independent_theta0_alternating_chi512" ||
    error("endpoint changed preparation")
endpoint.direction === :forward || error("endpoint is not from the forward bridge")
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

short_hash = first(expected_sha256, 12)
experiment = "chi1024_reverse_from_p0p45000000_$short_hash"
config_directory = length(ARGS) == 3 ? abspath(ARGS[3]) : joinpath(
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
config_path = joinpath(config_directory, "yc8_1_chi1024_reverse_validation.toml")
ispath(config_path) && error("refusing to overwrite generated reverse configuration")
ispath(output_directory) && error("refusing to reuse reverse-validation output")

configuration = TOML.parsefile(TEMPLATE)
campaign = configuration["campaign"]
campaign["mode"] = "reverse_validation"
campaign["fixed_theta_growth_before_flux"] = false
campaign["source_forward_endpoint_path"] = endpoint_path
campaign["source_forward_endpoint_sha256"] = expected_sha256
campaign["immutable_lineage_root_sha256"] = ROOT_SHA256
scan = configuration["scan"]
scan["direction"] = "reverse"
# Reverse transport is a consistency diagnostic and cannot become the
# primary-forward scientific lineage.
scan["lineage_policy"] = "compatible"
scan["fluxes_over_pi"] = collect(0.425:-0.025:0.15)
scan["initial_state_file"] = endpoint_path
scan["initial_state_sha256"] = expected_sha256
pop!(scan, "optimizer_checkpoint_file", nothing)
pop!(scan, "optimizer_checkpoint_sha256", nothing)
configuration["runtime"]["output_directory"] = output_directory

mkpath(config_directory)
open(config_path, "w") do io
    println(io, "# Reverse consistency check for the completed YC8-1 chi=1024 bridge")
    println(io, "# Accepted forward endpoint: $endpoint_path")
    println(io, "# Endpoint SHA-256: $expected_sha256")
    println(io, "# Diagnostic only: it cannot replace the primary-forward lineage")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println("Prepared reverse grid 0.425:-0.025:0.15 from the accepted chi=1024 endpoint.")
println("The immutable theta/pi=0.15 lineage root remains $ROOT_SHA256.")
