#!/usr/bin/env julia

using HDF5
using TOML
using TriangularJ1J2ProjectB

length(ARGS) == 1 || error(
    "usage: validate_yc8_1_chi1024_bridge_config.jl CONFIG.toml",
)

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const ROOT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const EXPECTED_BRANCH = "primary_forward_chi512_legacy_0p1"
const EXPECTED_PREPARATION = "independent_theta0_alternating_chi512"
const EXPECTED_PROFILE = "yc8_1_primary_forward_chi1024_multimetric_20260831"
const EXPECTED_EXECUTION_PROFILE = "parallel_vumps_julia4_step8_blocksparse_20260831"
const NOMINAL_FORWARD_GRID = collect(0.15:0.025:0.45)
const FULL_FORWARD_GRID = collect(0.475:0.025:1.0)

function require_approx(actual, expected, label)
    isapprox(Float64(actual), Float64(expected); atol=1e-12, rtol=0) ||
        error("$label=$actual, expected $expected")
end

function require_state_identity(state, label)
    state.circumference == 8 && state.shift == 1 || error("$label is not YC8-1")
    state.mps_period == 2 || error("$label is not period 2")
    state.twist_gauge === :uniform || error("$label does not use uniform twist gauge")
    state.branch == EXPECTED_BRANCH || error("$label changed the primary-forward branch")
    state.preparation == EXPECTED_PREPARATION || error("$label changed preparation")
    state.seed_pattern == "alternating" || error("$label changed seed pattern")
    state.random_seed == 101 || error("$label changed random seed")
    state.continuation_accepted || error("$label is not accepted for continuation")
    state.converged || error("$label is not VUMPS converged")
    length(state.flux_history_over_pi) >= 3 || error("$label lacks the accepted lineage prefix")
    all(isapprox.(
        state.flux_history_over_pi[1:3],
        [0.0, 0.1, 0.15];
        atol=1e-12,
        rtol=0,
    )) || error("$label changed the [0.0, 0.1, 0.15] lineage prefix")
    for cut in 1:state.mps_period
        isempty(PB.bond_sector_profile(state.psi.C[cut])) &&
            error("$label lacks U(1)-resolved virtual sectors at cut $cut")
    end
    return true
end

function require_embedded_campaign_root(path)
    config_text = HDF5.h5open(path, "r") do file
        haskey(file, "config_text") || error("state lacks embedded configuration: $path")
        String(read(file, "config_text"))
    end
    embedded = TOML.parse(config_text)
    embedded_campaign = get(embedded, "campaign", Dict{String,Any}())
    get(embedded_campaign, "immutable_lineage_root_sha256", "") == ROOT_SHA256 ||
        error("state embedded configuration changed the immutable lineage root")
    return true
end

config_path = abspath(ARGS[1])
raw = TOML.parsefile(config_path)
campaign = get(raw, "campaign", Dict{String,Any}())
get(campaign, "artifact_kind", "") ==
    "project_b_yc8_1_chi1024_bridge_control" || error("unexpected campaign kind")
get(campaign, "profile", "") == EXPECTED_PROFILE || error("unexpected campaign profile")
get(campaign, "execution_profile", "") == EXPECTED_EXECUTION_PROFILE ||
    error("unexpected campaign execution profile")
get(campaign, "immutable_lineage_root_sha256", "") == ROOT_SHA256 ||
    error("immutable theta/pi=0.15 lineage root changed")
mode = String(get(campaign, "mode", "forward_bridge"))
if mode == "forward_bridge"
    Bool(get(campaign, "fixed_theta_growth_before_flux", false)) ||
        error("fixed-theta bond growth guard is disabled")
end
Bool(get(campaign, "reverse_validation_required_before_full_sweep_promotion", false)) ||
    error("reverse validation guard is disabled")
Bool(get(campaign, "overlap_is_alarm_not_single_acceptance_gate", false)) ||
    error("overlap was restored as a stand-alone acceptance gate")

policy_relative = String(get(campaign, "continuity_policy_path", ""))
policy_path = isabspath(policy_relative) ? normpath(policy_relative) :
    normpath(joinpath(PROJECT_ROOT, policy_relative))
isfile(policy_path) || error("missing multimetric continuity policy: $policy_path")
policy_sha256 = lowercase(String(get(campaign, "continuity_policy_sha256", "")))
PB.file_sha256(policy_path) == policy_sha256 || error("continuity-policy SHA-256 mismatch")
policy = TOML.parsefile(policy_path)
get(policy, "artifact_kind", "") == "project_b_phase1_multimetric_continuity_policy" ||
    error("unexpected continuity-policy artifact kind")
policy["scope"]["profile"] == EXPECTED_PROFILE || error("continuity-policy profile changed")
policy["scope"]["immutable_lineage_root_sha256"] == ROOT_SHA256 ||
    error("continuity-policy lineage root changed")
policy_acceptance = policy["acceptance"]
policy_growth = policy["fixed_flux_growth"]
Bool(policy_acceptance["require_correlation_length_diagnostics"]) ||
    error("policy disabled correlation-length diagnostics")
Float64.(policy_acceptance["correlation_length_physical_sz_sectors"]) == [0.0, 1.0] ||
    error("policy correlation-length sectors changed")
Int(policy_acceptance["correlation_length_krylov_dimension"]) == 32 ||
    error("policy correlation-length Krylov dimension changed")
for (actual, expected, label) in (
    (policy_acceptance["overlap_alarm_floor_per_site"], 0.90, "policy overlap alarm"),
    (policy_acceptance["maximum_cut_entropy_jump"], 0.10, "policy entropy bound"),
    (policy_acceptance["maximum_energy_term_rms_jump"], 0.02, "policy energy bound"),
    (policy_acceptance["maximum_magnetization_rms_jump"], 0.001, "policy magnetization bound"),
    (policy_acceptance["maximum_mean_schmidt_total_variation"], 0.05, "policy Schmidt bound"),
    (policy_acceptance["correlation_length_tolerance"], 1e-8, "policy correlation-length tolerance"),
    (policy_acceptance["maximum_log_correlation_length_jump"], 0.05, "policy correlation-length bound"),
    (policy_growth["maximum_cut_entropy_jump"], 0.35, "policy growth entropy bound"),
    (policy_growth["maximum_mean_schmidt_total_variation"], 0.15, "policy growth Schmidt bound"),
    (policy_growth["maximum_log_correlation_length_jump"], 1.0, "policy growth correlation-length bound"),
)
    require_approx(actual, expected, label)
end
for (section_name, path_key, sha_key) in (
    ("smooth_calibration", "parent_state_path", "parent_state_sha256"),
    ("smooth_calibration", "candidate_state_path", "candidate_state_sha256"),
    ("smooth_calibration", "parent_spectrum_path", "parent_spectrum_sha256"),
    ("smooth_calibration", "candidate_spectrum_path", "candidate_spectrum_sha256"),
    ("discontinuous_calibration", "candidate_result_path", "candidate_result_sha256"),
    ("discontinuous_calibration", "candidate_analysis_path", "candidate_analysis_sha256"),
)
    evidence = policy[section_name]
    evidence_path = normpath(joinpath(dirname(policy_path), String(evidence[path_key])))
    isfile(evidence_path) || error("missing continuity-policy evidence: $evidence_path")
    PB.file_sha256(evidence_path) == lowercase(String(evidence[sha_key])) ||
        error("continuity-policy evidence SHA-256 mismatch: $evidence_path")
end

settings = PB.load_settings(config_path)
settings.model.geometry == PB.YCGeometry(8, 1) || error("configuration is not YC8-1")
PB.model_mps_period(settings.model) == 2 || error("configuration is not period 2")
settings.model.twist_gauge === :uniform || error("configuration changed twist gauge")
for (name, actual, expected) in (
    ("J1", settings.model.J1, 1.0),
    ("J2", settings.model.J2, 0.12),
    ("Delta1", settings.model.Delta1, 1.0),
    ("Delta2", settings.model.Delta2, 1.0),
    ("Bz", settings.model.Bz, 0.0),
)
    require_approx(actual, expected, name)
end

optimizer = settings.optimizer
optimizer.maxdim == 1024 || error("bridge must target chi=1024")
require_approx(optimizer.residual_tol, 1e-4, "VUMPS outer residual tolerance")
optimizer.max_iterations == 60 || error("outer-iteration cap changed")
optimizer.max_growth_steps == 20 || error("growth-step cap changed")
optimizer.solver_krylov_dimension == 40 || error("inner Krylov dimension changed")
optimizer.solver_max_iterations == 120 || error("inner iteration cap changed")
optimizer.record_krylov_diagnostics || error("inner-solver diagnostics are required")
optimizer.multisite_update_alg == "parallel" || error("bridge must use parallel VUMPS")
optimizer.restore_best_on_failure || error("best-iterate preservation is required")
optimizer.require_converged || error("numerical convergence gate is required")

scan = settings.scan
scan.branch == EXPECTED_BRANCH || error("branch changed")
scan.preparation == EXPECTED_PREPARATION || error("preparation changed")
scan.seed_pattern == "alternating" && scan.random_seed == 101 ||
    error("seed identity changed")
scan.require_parent_overlap || error("continuity diagnostics are disabled")
scan.continuity_policy === :multimetric_trust_region ||
    error("multimetric trust-region policy is required")
require_approx(scan.minimum_parent_overlap_per_site, 0.90, "overlap alarm floor")
require_approx(scan.maximum_cut_entropy_jump, 0.10, "cut-entropy bound")
require_approx(
    scan.fixed_flux_growth_maximum_cut_entropy_jump,
    0.35,
    "fixed-flux-growth cut-entropy bound",
)
require_approx(scan.maximum_energy_term_rms_jump, 0.02, "energy-pattern bound")
require_approx(scan.maximum_magnetization_rms_jump, 0.001, "magnetization bound")
require_approx(
    scan.maximum_mean_schmidt_total_variation,
    0.05,
    "Schmidt-distribution bound",
)
require_approx(
    scan.fixed_flux_growth_maximum_mean_schmidt_total_variation,
    0.15,
    "fixed-flux-growth Schmidt-distribution bound",
)
scan.require_correlation_length_diagnostics ||
    error("correlation-length diagnostics are required")
scan.correlation_length_physical_sz_sectors == [0.0, 1.0] ||
    error("correlation-length Sz sectors changed")
require_approx(scan.correlation_length_tolerance, 1e-8, "correlation-length tolerance")
scan.correlation_length_krylov_dimension == 32 ||
    error("correlation-length Krylov dimension changed")
require_approx(
    scan.maximum_log_correlation_length_jump,
    0.05,
    "correlation-length log-jump bound",
)
require_approx(
    scan.fixed_flux_growth_maximum_log_correlation_length_jump,
    1.0,
    "fixed-flux-growth correlation-length log-jump bound",
)
scan.require_u1_sector_diagnostics || error("U(1) virtual-sector diagnostics are required")
scan.adaptive_bisection || error("adaptive refinement is required")
require_approx(scan.minimum_step_over_pi, 0.00625, "minimum adaptive step")
settings.runtime.optimizer_checkpoint_every_iterations == 2 ||
    error("scratch-checkpoint cadence changed")
settings.runtime.blas_threads == 1 || error("BLAS threading must remain disabled")
settings.runtime.strided_threads == 1 || error("Strided threading must remain disabled")
settings.runtime.threaded_blocksparse || error("BlockSparse threading must remain enabled")

scan.initial_state_file === nothing && error("initial state is required")
scan.initial_state_sha256 === nothing && error("initial-state SHA-256 is required")
initial_path = scan.initial_state_file
initial_sha256 = scan.initial_state_sha256
PB.file_sha256(initial_path) == initial_sha256 || error("initial-state SHA-256 mismatch")
initial = PB.read_state_file(initial_path)
require_state_identity(initial, "initial state")

startup_source = "accepted_parent"
if mode == "forward_bridge"
    scan.direction === :forward || error("forward bridge changed direction")
    scan.lineage_policy === :strict || error("forward bridge requires strict lineage")
    initial.direction === :forward || error("forward bridge initial state is not forward")
    if scan.optimizer_checkpoint_file === nothing
        initial_sha256 == ROOT_SHA256 || error("new bridge must start from the immutable parent")
        require_approx(initial.theta_over_pi, 0.15, "initial theta/pi")
        length(scan.fluxes_over_pi) == length(NOMINAL_FORWARD_GRID) && all(isapprox.(
            scan.fluxes_over_pi,
            NOMINAL_FORWARD_GRID;
            atol=1e-12,
            rtol=0,
        )) || error("nominal 0.15:0.025:0.45 bridge grid changed")
        PB.maxlinkdim(initial.psi) == 512 || error("anchor is not chi=512")
    else
        length(scan.fluxes_over_pi) == 1 || error("checkpoint resume must isolate one theta")
        startup_source = "optimizer_checkpoint"
        scan.optimizer_checkpoint_sha256 === nothing &&
            error("optimizer-checkpoint SHA-256 is required")
        checkpoint_path = scan.optimizer_checkpoint_file
        checkpoint_sha256 = scan.optimizer_checkpoint_sha256
        PB.file_sha256(checkpoint_path) == checkpoint_sha256 ||
            error("optimizer-checkpoint SHA-256 mismatch")
        PB.load_or_build_initial_state(settings)
    end
elseif mode == "reverse_validation"
    scan.direction === :reverse || error("reverse validation changed direction")
    scan.lineage_policy === :compatible ||
        error("reverse validation must remain diagnostic, not strict forward lineage")
    scan.optimizer_checkpoint_file === nothing ||
        error("fresh reverse validation cannot start from an optimizer checkpoint")
    require_approx(initial.theta_over_pi, 0.45, "reverse endpoint theta/pi")
    PB.maxlinkdim(initial.psi) == 1024 || error("reverse endpoint is not chi=1024")
    require_embedded_campaign_root(initial_path)
    length(scan.fluxes_over_pi) == 12 || error("reverse validation grid length changed")
    all(isapprox.(
        scan.fluxes_over_pi,
        collect(0.425:-0.025:0.15);
        atol=1e-12,
        rtol=0,
    )) || error("reverse 0.425:-0.025:0.15 grid changed")
    startup_source = "accepted_forward_endpoint"
elseif mode == "forward_full_sweep"
    scan.direction === :forward || error("full sweep changed direction")
    scan.lineage_policy === :strict || error("full sweep requires strict lineage")
    initial.direction === :forward || error("full-sweep initial state is not forward")
    PB.maxlinkdim(initial.psi) == 1024 || error("full-sweep initial state is not chi=1024")
    require_embedded_campaign_root(initial_path)

    source_endpoint_path = abspath(String(campaign["source_forward_endpoint_path"]))
    source_endpoint_sha256 = lowercase(String(campaign["source_forward_endpoint_sha256"]))
    isfile(source_endpoint_path) || error("missing full-sweep source endpoint")
    PB.file_sha256(source_endpoint_path) == source_endpoint_sha256 ||
        error("full-sweep source-endpoint SHA-256 mismatch")
    source_endpoint = PB.read_state_file(source_endpoint_path)
    require_state_identity(source_endpoint, "full-sweep source endpoint")
    require_approx(source_endpoint.theta_over_pi, 0.45, "full-sweep source theta/pi")
    PB.maxlinkdim(source_endpoint.psi) == 1024 ||
        error("full-sweep source endpoint is not chi=1024")
    require_embedded_campaign_root(source_endpoint_path)

    analysis_path = abspath(String(campaign["forward_reverse_analysis_path"]))
    analysis_sha256 = lowercase(String(campaign["forward_reverse_analysis_sha256"]))
    isfile(analysis_path) || error("missing forward/reverse decision record")
    PB.file_sha256(analysis_path) == analysis_sha256 ||
        error("forward/reverse decision SHA-256 mismatch")
    analysis = TOML.parsefile(analysis_path)
    get(analysis, "artifact_kind", "") ==
        "project_b_yc8_1_chi1024_forward_reverse_analysis" ||
        error("unexpected forward/reverse decision kind")
    get(analysis, "immutable_lineage_root_sha256", "") == ROOT_SHA256 ||
        error("forward/reverse decision changed the lineage root")
    Bool(get(analysis, "all_common_points_passed", false)) ||
        error("forward/reverse decision did not pass")
    Int(get(analysis, "common_theta_count", 0)) == 12 ||
        error("forward/reverse decision has incomplete theta coverage")
    isempty(get(analysis, "failed_theta_over_pi", Any[])) ||
        error("forward/reverse decision records failed theta points")
    for (key, expected) in (
        ("overlap_alarm_floor_per_site", 0.90),
        ("cut_entropy_jump_threshold", 0.10),
        ("energy_term_rms_jump_threshold", 0.02),
        ("magnetization_rms_jump_threshold", 0.001),
        ("mean_schmidt_total_variation_threshold", 0.05),
        ("maximum_log_correlation_length_jump_threshold", 0.05),
    )
        require_approx(analysis[key], expected, "forward/reverse $key")
    end
    Float64.(analysis["correlation_length_physical_sz_sectors"]) == [0.0, 1.0] ||
        error("forward/reverse decision changed correlation-length sectors")
    comparison_path = abspath(String(campaign["forward_reverse_comparison_path"]))
    comparison_sha256 = lowercase(String(campaign["forward_reverse_comparison_sha256"]))
    isfile(comparison_path) || error("missing forward/reverse comparison table")
    PB.file_sha256(comparison_path) == comparison_sha256 ||
        error("forward/reverse comparison-table SHA-256 mismatch")
    String(analysis["comparison_table_path"]) == comparison_path ||
        error("full-sweep campaign and decision name different comparison tables")
    lowercase(String(analysis["comparison_table_sha256"])) == comparison_sha256 ||
        error("full-sweep campaign and decision name different comparison hashes")

    if scan.optimizer_checkpoint_file === nothing
        initial_sha256 == source_endpoint_sha256 ||
            error("fresh full sweep must start from the accepted theta/pi=0.45 endpoint")
        require_approx(initial.theta_over_pi, 0.45, "full-sweep initial theta/pi")
        length(scan.fluxes_over_pi) == length(FULL_FORWARD_GRID) && all(isapprox.(
            scan.fluxes_over_pi,
            FULL_FORWARD_GRID;
            atol=1e-12,
            rtol=0,
        )) || error("full 0.475:0.025:1.0 grid changed")
        startup_source = "validated_forward_endpoint"
    else
        length(scan.fluxes_over_pi) == 1 ||
            error("full-sweep checkpoint resume must isolate one theta")
        startup_source = "optimizer_checkpoint"
        scan.optimizer_checkpoint_sha256 === nothing &&
            error("optimizer-checkpoint SHA-256 is required")
        checkpoint_path = scan.optimizer_checkpoint_file
        checkpoint_sha256 = scan.optimizer_checkpoint_sha256
        PB.file_sha256(checkpoint_path) == checkpoint_sha256 ||
            error("optimizer-checkpoint SHA-256 mismatch")
        PB.load_or_build_initial_state(settings)
    end
else
    error("unsupported campaign mode: $mode")
end

output = settings.runtime.output_directory
occursin(joinpath("output", "science", "yc8_1"), output) ||
    error("compact output directory escaped output/science/yc8_1")
config_sha256 = PB.file_sha256(config_path)
fluxes = join(scan.fluxes_over_pi, ",")
fields = (
    config_sha256,
    output,
    scan.branch,
    scan.preparation,
    string(optimizer.maxdim),
    string(optimizer.residual_tol),
    string(optimizer.max_iterations),
    fluxes,
    string(scan.minimum_step_over_pi),
    string(scan.minimum_parent_overlap_per_site),
    startup_source,
    string(settings.runtime.optimizer_checkpoint_every_iterations),
    mode,
    optimizer.multisite_update_alg,
    EXPECTED_EXECUTION_PROFILE,
)
println(join(fields, '\t'))
