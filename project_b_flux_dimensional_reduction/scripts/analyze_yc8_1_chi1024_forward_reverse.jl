#!/usr/bin/env julia

using HDF5
using Printf
using TOML
using TriangularJ1J2ProjectB

length(ARGS) == 3 || error(
    "usage: analyze_yc8_1_chi1024_forward_reverse.jl " *
    "FORWARD_MANIFEST_DIRECTORY REVERSE_MANIFEST_DIRECTORY OUTPUT_PREFIX",
)

const PB = TriangularJ1J2ProjectB
const ROOT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"

theta_key(theta::Real) = @sprintf("%.8f", Float64(theta))

function load_manifests(directory::AbstractString, expected_direction::AbstractString)
    absolute = abspath(directory)
    isdir(absolute) || error("missing manifest directory: $absolute")
    records = Dict{String,NamedTuple}()
    for path in sort!(filter(path -> endswith(path, ".toml"), readdir(absolute; join=true)))
        raw = TOML.parsefile(path)
        get(raw, "artifact_kind", "") == "project_b_vumps_state_manifest" || continue
        Bool(raw["continuation_accepted"]) || continue
        String(raw["direction"]) == expected_direction || continue
        Int(raw["maxlinkdim"]) == 1024 || continue
        theta = Float64(raw["theta_over_pi"])
        key = theta_key(theta)
        haskey(records, key) && error("duplicate accepted $expected_direction manifest at $key")
        state_path = String(raw["full_state_path"])
        state_sha256 = lowercase(String(raw["full_state_sha256"]))
        isfile(state_path) || error("missing scratch state named by $path: $state_path")
        PB.file_sha256(state_path) == state_sha256 || error("state SHA-256 mismatch for $path")
        records[key] = (; theta, manifest_path=path, state_path, state_sha256)
    end
    isempty(records) && error("no accepted chi=1024 $expected_direction manifests in $absolute")
    return records
end

function require_state(state, direction::Symbol, theta::Real, label)
    state.converged && state.continuation_accepted || error("$label is not accepted")
    state.circumference == 8 && state.shift == 1 && state.mps_period == 2 ||
        error("$label changed YC8-1 period-2 geometry")
    state.twist_gauge === :uniform || error("$label changed uniform twist gauge")
    state.branch == "primary_forward_chi512_legacy_0p1" || error("$label changed branch")
    state.preparation == "independent_theta0_alternating_chi512" ||
        error("$label changed preparation")
    state.direction === direction || error("$label has direction $(state.direction)")
    isapprox(state.theta_over_pi, theta; atol=1e-12, rtol=0) ||
        error("$label theta mismatch")
    PB.maxlinkdim(state.psi) == 1024 || error("$label is not chi=1024")
    length(state.flux_history_over_pi) >= 3 || error("$label lacks lineage history")
    all(isapprox.(
        state.flux_history_over_pi[1:3],
        [0.0, 0.1, 0.15];
        atol=1e-12,
        rtol=0,
    )) || error("$label changed immutable lineage prefix rooted at $ROOT_SHA256")
    state.observables === nothing && error("$label lacks stored observables")
    return true
end

function require_embedded_campaign_root(path, label)
    config_text = HDF5.h5open(path, "r") do file
        haskey(file, "config_text") || error("$label lacks embedded configuration")
        String(read(file, "config_text"))
    end
    campaign = get(TOML.parse(config_text), "campaign", Dict{String,Any}())
    get(campaign, "immutable_lineage_root_sha256", "") == ROOT_SHA256 ||
        error("$label changed the immutable lineage root")
    return true
end

forward = load_manifests(ARGS[1], "forward")
reverse = load_manifests(ARGS[2], "reverse")
common = sort!(collect(intersect(keys(forward), keys(reverse)));
    by=key -> parse(Float64, key))
isempty(common) && error("forward and reverse manifests have no common theta points")

policy = PB.ScanSettings(
    branch="primary_forward_chi512_legacy_0p1",
    preparation="independent_theta0_alternating_chi512",
    direction=:stationary,
    lineage_policy=:compatible,
    fluxes_over_pi=[0.15],
    seed_pattern="alternating",
    random_seed=101,
    adaptive_bisection=false,
    require_parent_overlap=true,
    continuity_policy=:multimetric_trust_region,
    minimum_parent_overlap_per_site=0.90,
    parent_overlap_tolerance=1e-8,
    parent_overlap_krylov_dimension=32,
    maximum_cut_entropy_jump=0.10,
    maximum_energy_term_rms_jump=0.02,
    maximum_magnetization_rms_jump=0.001,
    maximum_mean_schmidt_total_variation=0.05,
    require_correlation_length_diagnostics=true,
    correlation_length_physical_sz_sectors=[0.0, 1.0],
    correlation_length_tolerance=1e-8,
    correlation_length_krylov_dimension=32,
    maximum_log_correlation_length_jump=0.05,
    fixed_flux_growth_maximum_log_correlation_length_jump=1.0,
    require_u1_sector_diagnostics=true,
)

rows = NamedTuple[]
for key in common
    forward_record = forward[key]
    reverse_record = reverse[key]
    theta = forward_record.theta
    forward_state = PB.read_state_file(forward_record.state_path)
    reverse_state = PB.read_state_file(reverse_record.state_path)
    require_state(forward_state, :forward, theta, "forward state at $key")
    require_state(reverse_state, :reverse, theta, "reverse state at $key")
    require_embedded_campaign_root(forward_record.state_path, "forward state at $key")
    require_embedded_campaign_root(reverse_record.state_path, "reverse state at $key")
    diagnostic = PB.branch_continuity_diagnostics(
        forward_state.psi,
        reverse_state.psi,
        forward_state.observables,
        reverse_state.observables,
        theta,
        theta,
        policy;
        random_seed=101 + length(rows),
    )
    push!(rows, (;
        theta_over_pi=theta,
        passed=diagnostic.passed,
        reason=diagnostic.reason,
        overlap_per_site=diagnostic.overlap_per_site,
        overlap_alarm=diagnostic.overlap_alarm_triggered,
        energy_density_delta=diagnostic.energy_density_delta,
        maximum_cut_entropy_jump=diagnostic.maximum_cut_entropy_jump,
        energy_term_rms_jump=diagnostic.energy_term_rms_jump,
        magnetization_rms_jump=diagnostic.magnetization_rms_jump,
        mean_schmidt_total_variation=diagnostic.mean_schmidt_total_variation,
        parent_correlation_lengths=join(diagnostic.parent_correlation_lengths, ","),
        candidate_correlation_lengths=join(diagnostic.candidate_correlation_lengths, ","),
        maximum_log_correlation_length_jump=
            diagnostic.maximum_log_correlation_length_jump,
        correlation_length_gate_passed=diagnostic.correlation_length_gate_passed,
        u1_sector_labels_preserved=diagnostic.u1_sector_labels_preserved,
        u1_sector_multiplicities_preserved=
            diagnostic.u1_sector_multiplicities_preserved,
        forward_state_path=forward_record.state_path,
        forward_state_sha256=forward_record.state_sha256,
        reverse_state_path=reverse_record.state_path,
        reverse_state_sha256=reverse_record.state_sha256,
    ))
end

prefix = abspath(ARGS[3])
tsv_path = prefix * ".tsv"
summary_path = prefix * ".toml"
for path in (tsv_path, summary_path)
    ispath(path) && error("refusing to overwrite forward/reverse analysis: $path")
end
mkpath(dirname(prefix))
open(tsv_path, "w") do io
    println(io, join(propertynames(first(rows)), '\t'))
    for row in rows
        println(io, join((getproperty(row, name) for name in propertynames(row)), '\t'))
    end
end

summary = Dict{String,Any}(
    "schema_version" => 1,
    "artifact_kind" => "project_b_yc8_1_chi1024_forward_reverse_analysis",
    "immutable_lineage_root_sha256" => ROOT_SHA256,
    "common_theta_count" => length(rows),
    "all_common_points_passed" => all(row.passed for row in rows),
    "failed_theta_over_pi" => [row.theta_over_pi for row in rows if !row.passed],
    "minimum_overlap_per_site" => minimum(row.overlap_per_site for row in rows),
    "maximum_cut_entropy_jump" => maximum(row.maximum_cut_entropy_jump for row in rows),
    "maximum_energy_term_rms_jump" => maximum(row.energy_term_rms_jump for row in rows),
    "maximum_magnetization_rms_jump" => maximum(row.magnetization_rms_jump for row in rows),
    "maximum_mean_schmidt_total_variation" =>
        maximum(row.mean_schmidt_total_variation for row in rows),
    "maximum_log_correlation_length_jump" =>
        maximum(row.maximum_log_correlation_length_jump for row in rows),
    "overlap_alarm_floor_per_site" => 0.90,
    "cut_entropy_jump_threshold" => 0.10,
    "energy_term_rms_jump_threshold" => 0.02,
    "magnetization_rms_jump_threshold" => 0.001,
    "mean_schmidt_total_variation_threshold" => 0.05,
    "maximum_log_correlation_length_jump_threshold" => 0.05,
    "correlation_length_physical_sz_sectors" => [0.0, 1.0],
    "comparison_table_path" => tsv_path,
    "comparison_table_sha256" => PB.file_sha256(tsv_path),
)
open(summary_path, "w") do io
    TOML.print(io, summary; sorted=true)
end

println("forward/reverse common theta points: $(length(rows))")
println("all multimetric comparisons passed: $(summary["all_common_points_passed"])")
println("table: $tsv_path")
println("summary: $summary_path")
