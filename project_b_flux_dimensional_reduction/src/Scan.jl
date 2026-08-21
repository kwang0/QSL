function optimize_candidate(hamiltonian, psi, optimizer::OptimizerSettings; output_level::Integer)
    if maxlinkdim(psi) < optimizer.maxdim
        return grow_and_optimize(hamiltonian, psi, optimizer; output_level)
    elseif maxlinkdim(psi) == optimizer.maxdim
        return run_vumps_iterations(hamiltonian, psi, optimizer; output_level)
    end
    error("state chi=$(maxlinkdim(psi)) exceeds requested chi=$(optimizer.maxdim)")
end

function validate_strict_lineage(settings::ProjectSettings, state, path::AbstractString)
    state.schema_version >= 3 || error(
        "strict lineage requires a schema-v3-or-newer state: $path",
    )
    state.preparation != "legacy_unspecified" || error(
        "strict lineage requires preparation metadata: $path",
    )
    state.direction !== :unknown || error(
        "strict lineage requires a schema-v3-or-newer state with direction metadata: $path",
    )
    state.branch == settings.scan.branch || error(
        "strict lineage rejects branch $(state.branch); expected $(settings.scan.branch)",
    )
    state.preparation == settings.scan.preparation || error(
        "strict lineage rejects preparation $(state.preparation); expected " *
        settings.scan.preparation,
    )
    state.direction == settings.scan.direction || error(
        "strict lineage rejects direction $(state.direction); expected $(settings.scan.direction)",
    )
    state.random_seed == settings.scan.random_seed || error(
        "strict lineage rejects random seed $(state.random_seed); expected " *
        "$(settings.scan.random_seed)",
    )
    state.seed_pattern == settings.scan.seed_pattern || error(
        "strict lineage rejects seed pattern $(state.seed_pattern); expected " *
        settings.scan.seed_pattern,
    )
    return true
end

function evaluate_branch_continuity(
    settings::ProjectSettings,
    candidate,
    candidate_observables,
    last_accepted_theta,
    theta_over_pi::Real,
    parent_state_path::AbstractString,
    parent_state_sha256::AbstractString,
    point_index::Integer,
)
    settings.scan.require_parent_overlap || return skipped_branch_continuity(
        "parent-overlap gate disabled";
        passed=true,
        parent_theta_over_pi=something(last_accepted_theta, NaN),
        candidate_theta_over_pi=theta_over_pi,
        minimum_overlap_per_site=settings.scan.minimum_parent_overlap_per_site,
    )
    last_accepted_theta === nothing && return skipped_branch_continuity(
        "independent branch preparation has no accepted parent";
        passed=true,
        candidate_theta_over_pi=theta_over_pi,
        minimum_overlap_per_site=settings.scan.minimum_parent_overlap_per_site,
    )
    isempty(parent_state_path) && error(
        "parent-overlap gate requires an immutable accepted parent state",
    )
    actual_parent_sha256 = file_sha256(parent_state_path)
    actual_parent_sha256 == parent_state_sha256 || error(
        "accepted parent SHA-256 changed before continuity evaluation: $parent_state_path",
    )
    parent = read_state_file(parent_state_path)
    parent.continuation_accepted || error(
        "continuity parent was not accepted for continuation: $parent_state_path",
    )
    parent.observables === nothing && error(
        "continuity parent lacks stored observables: $parent_state_path",
    )
    return branch_continuity_diagnostics(
        parent.psi,
        candidate,
        parent.observables,
        candidate_observables,
        last_accepted_theta,
        theta_over_pi,
        settings.scan;
        random_seed=settings.scan.random_seed + Int(point_index),
    )
end

function validate_initial_schedule(settings::ProjectSettings, initial_theta::Real)
    first_theta = first(settings.scan.fluxes_over_pi)
    tolerance = 1e-12
    if settings.scan.direction === :forward
        first_theta + tolerance >= initial_theta || error(
            "forward schedule starts behind its initial checkpoint: " *
            "theta/pi=$first_theta < $initial_theta",
        )
    elseif settings.scan.direction === :reverse
        first_theta - tolerance <= initial_theta || error(
            "reverse schedule starts ahead of its initial checkpoint: " *
            "theta/pi=$first_theta > $initial_theta",
        )
    else
        isapprox(first_theta, initial_theta; atol=tolerance, rtol=0) || error(
            "stationary schedule does not match its initial-state flux",
        )
    end
    return true
end

function validate_state_model_compatibility(
    settings::ProjectSettings,
    state,
    label::AbstractString,
)
    state.circumference == settings.model.geometry.circumference ||
        error("$label circumference does not match configuration")
    state.shift == settings.model.geometry.shift ||
        error("$label YC shift does not match configuration")
    expected_period = model_mps_period(settings.model)
    state.mps_period == expected_period || error(
        "$label uses MPS period $(state.mps_period), but the configuration requires " *
        "$expected_period; legacy supercell states must not seed a minimal-cell production scan",
    )
    state.twist_gauge == settings.model.twist_gauge || error(
        "$label twist gauge $(state.twist_gauge) does not match configured gauge " *
        "$(settings.model.twist_gauge)",
    )
    for field in (:J1, :J2, :Delta1, :Delta2, :Bz)
        actual = getproperty(state, field)
        expected = getproperty(settings.model, field)
        isapprox(actual, expected; atol=1e-12, rtol=1e-12) ||
            error("$label $field=$actual does not match configured value $expected")
    end
    return true
end

function validate_state_flux_history(state, label::AbstractString)
    isempty(state.flux_history_over_pi) && error("$label has an empty flux history")
    isapprox(
        last(state.flux_history_over_pi),
        state.theta_over_pi;
        atol=1e-12,
        rtol=0,
    ) || error("$label flux history does not terminate at its saved flux")
    return true
end

function flux_histories_match(left, right)
    length(left) == length(right) || return false
    return all(isapprox.(left, right; atol=1e-12, rtol=0))
end

function load_optimizer_checkpoint(
    settings::ProjectSettings,
    accepted_state,
    accepted_path::AbstractString,
    accepted_sha256::AbstractString,
)
    checkpoint_path = abspath(something(settings.scan.optimizer_checkpoint_file))
    expected_checkpoint_sha256 = something(settings.scan.optimizer_checkpoint_sha256)
    actual_checkpoint_sha256 = file_sha256(checkpoint_path)
    actual_checkpoint_sha256 == expected_checkpoint_sha256 || error(
        "optimizer checkpoint SHA-256 mismatch: expected $expected_checkpoint_sha256, " *
        "got $actual_checkpoint_sha256 for $checkpoint_path",
    )
    checkpoint = read_state_file(checkpoint_path)
    checkpoint.schema_version >= 5 || error(
        "optimizer-checkpoint resume requires a schema-v5-or-newer rejected state: " *
        checkpoint_path,
    )
    checkpoint.converged && error("optimizer checkpoint is already numerically converged")
    checkpoint.continuation_accepted && error(
        "optimizer checkpoint is already accepted for continuation; use it as initial_state_file",
    )
    validate_state_model_compatibility(settings, checkpoint, "optimizer checkpoint")
    validate_strict_lineage(settings, checkpoint, checkpoint_path)
    validate_state_flux_history(checkpoint, "optimizer checkpoint")
    isapprox(
        checkpoint.theta_over_pi,
        accepted_state.theta_over_pi;
        atol=1e-12,
        rtol=0,
    ) || error(
        "optimizer checkpoint theta/pi=$(checkpoint.theta_over_pi) differs from the accepted " *
        "parent theta/pi=$(accepted_state.theta_over_pi)",
    )
    isapprox(
        only(settings.scan.fluxes_over_pi),
        checkpoint.theta_over_pi;
        atol=1e-12,
        rtol=0,
    ) || error("optimizer-checkpoint resume flux must equal the checkpoint Hamiltonian flux")
    checkpoint.parent_state_sha256 == accepted_sha256 || error(
        "optimizer checkpoint does not name the configured accepted parent SHA-256",
    )
    isempty(checkpoint.parent_state_path) && error(
        "optimizer checkpoint lacks accepted-parent path metadata",
    )
    basename(checkpoint.parent_state_path) == basename(accepted_path) || error(
        "optimizer checkpoint parent basename $(basename(checkpoint.parent_state_path)) " *
        "does not match $(basename(accepted_path))",
    )
    flux_histories_match(
        checkpoint.flux_history_over_pi,
        accepted_state.flux_history_over_pi,
    ) || error("optimizer checkpoint flux history differs from the accepted parent lineage")
    actual_checkpoint_maxdim = maxlinkdim(checkpoint.psi)
    checkpoint.maxlinkdim == actual_checkpoint_maxdim || error(
        "optimizer checkpoint maxlinkdim metadata $(checkpoint.maxlinkdim) disagrees with " *
        "its MPS ($actual_checkpoint_maxdim)",
    )
    checkpoint.optimizer_requested_maxdim == settings.optimizer.maxdim || error(
        "optimizer checkpoint requested chi=$(checkpoint.optimizer_requested_maxdim), but " *
        "the resume configuration requests chi=$(settings.optimizer.maxdim)",
    )
    actual_checkpoint_maxdim == settings.optimizer.maxdim || error(
        "optimizer checkpoint has chi=$actual_checkpoint_maxdim, but the resume configuration " *
        "requests chi=$(settings.optimizer.maxdim)",
    )
    checkpoint.optimizer_stop_reason == "maximum_iterations_contracting" || error(
        "optimizer-checkpoint resume is restricted to maximum_iterations_contracting; got " *
        checkpoint.optimizer_stop_reason,
    )
    checkpoint.optimizer_iterations >= 1 || error(
        "optimizer checkpoint has no recorded outer iterations",
    )
    isfinite(checkpoint.optimizer_residual) || error(
        "optimizer checkpoint residual is not finite",
    )
    checkpoint.optimizer_residual > settings.optimizer.residual_tol || error(
        "optimizer checkpoint residual already satisfies the configured tolerance",
    )
    isapprox(
        checkpoint.optimizer_residual_tolerance,
        settings.optimizer.residual_tol;
        atol=0,
        rtol=1e-12,
    ) || error(
        "optimizer checkpoint residual tolerance " *
        "$(checkpoint.optimizer_residual_tolerance) differs from configured tolerance " *
        "$(settings.optimizer.residual_tol)",
    )
    isfinite(checkpoint.optimizer_minimum_residual) || error(
        "optimizer checkpoint minimum residual is not finite",
    )
    prior_iterations = checkpoint.optimizer_checkpoint_iterations
    prior_iterations >= 0 || error("optimizer checkpoint prior-iteration count is negative")
    cumulative_iterations = prior_iterations + checkpoint.optimizer_iterations
    cumulative_minimum_residual = isfinite(checkpoint.optimizer_checkpoint_minimum_residual) ?
        min(
            checkpoint.optimizer_minimum_residual,
            checkpoint.optimizer_checkpoint_minimum_residual,
        ) : checkpoint.optimizer_minimum_residual
    return (;
        checkpoint,
        path=checkpoint_path,
        sha256=actual_checkpoint_sha256,
        cumulative_iterations,
        residual=checkpoint.optimizer_residual,
        minimum_residual=cumulative_minimum_residual,
        stop_reason=checkpoint.optimizer_stop_reason,
    )
end

function load_or_build_initial_state(settings::ProjectSettings)
    if settings.scan.initial_state_file === nothing
        return (;
            psi=build_product_state(settings),
            initial_theta=nothing,
            parent_state_path="",
            parent_state_sha256="",
            parent_maxdim=0,
            flux_history_over_pi=Float64[],
            optimizer_checkpoint_path="",
            optimizer_checkpoint_sha256="",
            optimizer_checkpoint_iterations=0,
            optimizer_checkpoint_residual=NaN,
            optimizer_checkpoint_minimum_residual=NaN,
            optimizer_checkpoint_stop_reason="",
        )
    end
    initial_path = abspath(settings.scan.initial_state_file)
    actual_initial_sha256 = file_sha256(initial_path)
    expected_initial_sha256 = settings.scan.initial_state_sha256
    settings.scan.lineage_policy === :strict && expected_initial_sha256 === nothing && error(
        "strict restart lineage requires an expected initial-state SHA-256",
    )
    if expected_initial_sha256 !== nothing
        actual_initial_sha256 == expected_initial_sha256 || error(
            "initial state SHA-256 mismatch: expected $expected_initial_sha256, " *
            "got $actual_initial_sha256 for $initial_path",
        )
    end
    state = read_state_file(initial_path)
    state.converged || error("initial state is not converged")
    state.continuation_accepted || error("initial state was not accepted for continuation")
    validate_state_model_compatibility(settings, state, "initial state")
    settings.scan.lineage_policy === :strict &&
        validate_strict_lineage(settings, state, initial_path)
    validate_state_flux_history(state, "initial state")
    validate_initial_schedule(settings, state.theta_over_pi)
    checkpoint = settings.scan.optimizer_checkpoint_file === nothing ? nothing :
        load_optimizer_checkpoint(settings, state, initial_path, actual_initial_sha256)
    return (;
        psi=checkpoint === nothing ? state.psi : checkpoint.checkpoint.psi,
        initial_theta=state.theta_over_pi,
        parent_state_path=initial_path,
        parent_state_sha256=actual_initial_sha256,
        parent_maxdim=maxlinkdim(state.psi),
        flux_history_over_pi=copy(state.flux_history_over_pi),
        optimizer_checkpoint_path=checkpoint === nothing ? "" : checkpoint.path,
        optimizer_checkpoint_sha256=checkpoint === nothing ? "" : checkpoint.sha256,
        optimizer_checkpoint_iterations=checkpoint === nothing ? 0 :
            checkpoint.cumulative_iterations,
        optimizer_checkpoint_residual=checkpoint === nothing ? NaN : checkpoint.residual,
        optimizer_checkpoint_minimum_residual=checkpoint === nothing ? NaN :
            checkpoint.minimum_residual,
        optimizer_checkpoint_stop_reason=checkpoint === nothing ? "" :
            checkpoint.stop_reason,
    )
end

function insert_refinement!(queue::Vector{Float64}, last_theta::Float64, target_theta::Float64)
    midpoint = (last_theta + target_theta) / 2
    pushfirst!(queue, target_theta)
    pushfirst!(queue, midpoint)
    return midpoint
end

function minimum_step_bracket_reached(
    last_accepted_theta::Real,
    rejected_theta::Real,
    minimum_step_over_pi::Real,
)
    width = abs(Float64(rejected_theta) - Float64(last_accepted_theta))
    tolerance = max(1e-12, 16 * eps(max(abs(Float64(rejected_theta)), 1.0)))
    return width <= Float64(minimum_step_over_pi) + tolerance
end

function fixed_flux_expansion_requested(
    last_accepted_theta,
    candidate_theta::Real,
    source_maxdim::Integer,
    requested_maxdim::Integer,
)
    last_accepted_theta === nothing && return false
    requested_maxdim > source_maxdim || return false
    return isapprox(
        Float64(candidate_theta),
        Float64(last_accepted_theta);
        atol=1e-12,
        rtol=0,
    )
end

function fixed_flux_optimizer_resume_requested(
    last_accepted_theta,
    candidate_theta::Real,
    optimizer_checkpoint_path::AbstractString,
)
    last_accepted_theta === nothing && return false
    isempty(optimizer_checkpoint_path) && return false
    return isapprox(
        Float64(candidate_theta),
        Float64(last_accepted_theta);
        atol=1e-12,
        rtol=0,
    )
end

function numerical_continuation_classification(diagnostic::VumpsDiagnostics)
    diagnostic.stop_reason == "residual_plateau" &&
        return "numerical_plateau_not_physical_endpoint"
    diagnostic.stop_reason == "maximum_iterations_contracting" &&
        return "iteration_limit_while_contracting_not_physical_endpoint"
    diagnostic.stop_reason == "maximum_iterations_stalled" &&
        return "iteration_limit_stalled_not_physical_endpoint"
    diagnostic.stop_reason == "diverging_residual" &&
        return "numerical_divergence_not_physical_endpoint"
    return "numerical_not_physical_endpoint"
end

function write_bracketed_scan_outcome(
    settings::ProjectSettings,
    diagnostic::VumpsDiagnostics,
    continuity::BranchContinuityDiagnostics,
    last_accepted_theta::Real,
    rejected_theta::Real,
    point_index::Integer,
    accepted_state_path::AbstractString,
    accepted_state_sha256::AbstractString,
    rejected_state_path::AbstractString,
    rejected_state_sha256::AbstractString,
)
    output_path = joinpath(settings.runtime.output_directory, "scan_outcome.toml")
    ispath(output_path) && error("refusing to overwrite immutable scan outcome: $output_path")
    temporary_path = output_path * ".tmp"
    ispath(temporary_path) && error("stale temporary scan outcome exists: $temporary_path")
    left, right = minmax(Float64(last_accepted_theta), Float64(rejected_theta))
    continuity_loss = diagnostic.converged && continuity.checked && !continuity.passed
    data = Dict{String,Any}(
        "schema_version" => 4,
        "artifact_kind" => "project_b_flux_scan_outcome",
        "created_at_utc" => string(now(UTC)),
        "status" => continuity_loss ?
            "branch_continuity_loss_bracketed" : "numerical_continuation_loss_bracketed",
        "classification" => continuity_loss ?
            "possible_basin_jump_not_physical_endpoint" :
            numerical_continuation_classification(diagnostic),
        "config_id" => config_identifier(settings),
        "config_path" => settings.config_path,
        "geometry" => string(settings.model.geometry),
        "branch" => settings.scan.branch,
        "preparation" => settings.scan.preparation,
        "direction" => string(settings.scan.direction),
        "random_seed" => settings.scan.random_seed,
        "requested_maxdim" => settings.optimizer.maxdim,
        "point_index" => Int(point_index),
        "last_accepted_theta_over_pi" => Float64(last_accepted_theta),
        "rejected_theta_over_pi" => Float64(rejected_theta),
        "bracket_left_theta_over_pi" => left,
        "bracket_right_theta_over_pi" => right,
        "bracket_width_over_pi" => right - left,
        "minimum_step_over_pi" => settings.scan.minimum_step_over_pi,
        "residual" => diagnostic.residual,
        "minimum_residual" => diagnostic.minimum_residual,
        "optimizer_terminal_residual" => diagnostic.terminal_residual,
        "optimizer_best_iteration" => diagnostic.best_iteration,
        "optimizer_returned_iteration" => diagnostic.returned_iteration,
        "optimizer_restored_best_on_failure" => diagnostic.restored_best_on_failure,
        "optimizer_multisite_update_alg" => settings.optimizer.multisite_update_alg,
        "optimizer_restore_best_on_failure_enabled" =>
            settings.optimizer.restore_best_on_failure,
        "residual_tolerance" => settings.optimizer.residual_tol,
        "optimizer_stop_reason" => diagnostic.stop_reason,
        "optimizer_iterations" => diagnostic.iterations,
        "optimizer_trend_window" => diagnostic.trend_window,
        "optimizer_recent_relative_improvement" =>
            diagnostic.recent_relative_improvement,
        "optimizer_log_residual_slope" => diagnostic.log_residual_slope,
        "optimizer_log_residual_r_squared" => diagnostic.log_residual_r_squared,
        "optimizer_projected_total_iterations" => diagnostic.projected_total_iterations,
        "optimizer_krylov_solve_count" => length(diagnostic.krylov_solves),
        "continuity_checked" => continuity.checked,
        "continuity_passed" => continuity.passed,
        "continuity_reason" => continuity.reason,
        "parent_overlap_per_unit_cell" => continuity.overlap_per_unit_cell,
        "parent_overlap_per_site" => continuity.overlap_per_site,
        "minimum_parent_overlap_per_site" => continuity.minimum_overlap_per_site,
        "energy_density_delta" => continuity.energy_density_delta,
        "mean_entropy_delta" => continuity.mean_entropy_delta,
        "maximum_cut_entropy_jump" => continuity.maximum_cut_entropy_jump,
        "energy_term_rms_jump" => continuity.energy_term_rms_jump,
        "magnetization_rms_jump" => continuity.magnetization_rms_jump,
        "mean_schmidt_total_variation" => continuity.mean_schmidt_total_variation,
        "accepted_state_path" => String(accepted_state_path),
        "accepted_state_sha256" => String(accepted_state_sha256),
        "rejected_state_path" => String(rejected_state_path),
        "rejected_state_sha256" => String(rejected_state_sha256),
    )
    try
        open(temporary_path, "w") do io
            TOML.print(io, data; sorted=true)
        end
        Base.Filesystem.rename(temporary_path, output_path)
    catch
        isfile(temporary_path) && rm(temporary_path; force=true)
        rethrow()
    end
    return output_path
end

function write_fixed_flux_expansion_outcome(
    settings::ProjectSettings,
    diagnostic::VumpsDiagnostics,
    continuity::BranchContinuityDiagnostics,
    theta_over_pi::Real,
    point_index::Integer,
    source_maxdim::Integer,
    result_maxdim::Integer,
    source_state_path::AbstractString,
    source_state_sha256::AbstractString,
    candidate_state_path::AbstractString,
    candidate_state_sha256::AbstractString,
)
    output_path = joinpath(settings.runtime.output_directory, "scan_outcome.toml")
    ispath(output_path) && error("refusing to overwrite immutable scan outcome: $output_path")
    temporary_path = output_path * ".tmp"
    ispath(temporary_path) && error("stale temporary scan outcome exists: $temporary_path")
    continuity_loss = diagnostic.converged && continuity.checked && !continuity.passed
    data = Dict{String,Any}(
        "schema_version" => 2,
        "artifact_kind" => "project_b_fixed_flux_expansion_outcome",
        "created_at_utc" => string(now(UTC)),
        "status" => continuity_loss ?
            "fixed_flux_expansion_continuity_rejected" :
            "fixed_flux_expansion_numerical_failure",
        "classification" => continuity_loss ?
            "possible_basin_jump_not_physical_endpoint" :
            numerical_continuation_classification(diagnostic),
        "physical_endpoint" => false,
        "continuation_accepted" => false,
        "config_id" => config_identifier(settings),
        "config_path" => settings.config_path,
        "geometry" => string(settings.model.geometry),
        "branch" => settings.scan.branch,
        "preparation" => settings.scan.preparation,
        "direction" => string(settings.scan.direction),
        "random_seed" => settings.scan.random_seed,
        "point_index" => Int(point_index),
        "theta_over_pi" => Float64(theta_over_pi),
        "source_maxdim" => Int(source_maxdim),
        "requested_maxdim" => settings.optimizer.maxdim,
        "result_maxdim" => Int(result_maxdim),
        "residual" => diagnostic.residual,
        "minimum_residual" => diagnostic.minimum_residual,
        "optimizer_terminal_residual" => diagnostic.terminal_residual,
        "optimizer_best_iteration" => diagnostic.best_iteration,
        "optimizer_returned_iteration" => diagnostic.returned_iteration,
        "optimizer_restored_best_on_failure" => diagnostic.restored_best_on_failure,
        "optimizer_multisite_update_alg" => settings.optimizer.multisite_update_alg,
        "optimizer_restore_best_on_failure_enabled" =>
            settings.optimizer.restore_best_on_failure,
        "residual_tolerance" => settings.optimizer.residual_tol,
        "optimizer_stop_reason" => diagnostic.stop_reason,
        "optimizer_iterations" => diagnostic.iterations,
        "optimizer_max_iterations" => settings.optimizer.max_iterations,
        "optimizer_plateau_detection" => settings.optimizer.plateau_detection,
        "optimizer_trend_window" => diagnostic.trend_window,
        "optimizer_recent_relative_improvement" =>
            diagnostic.recent_relative_improvement,
        "optimizer_log_residual_slope" => diagnostic.log_residual_slope,
        "optimizer_log_residual_r_squared" => diagnostic.log_residual_r_squared,
        "optimizer_projected_total_iterations" => diagnostic.projected_total_iterations,
        "optimizer_krylov_solve_count" => length(diagnostic.krylov_solves),
        "continuity_checked" => continuity.checked,
        "continuity_passed" => continuity.passed,
        "continuity_reason" => continuity.reason,
        "parent_overlap_per_unit_cell" => continuity.overlap_per_unit_cell,
        "parent_overlap_per_site" => continuity.overlap_per_site,
        "minimum_parent_overlap_per_site" => continuity.minimum_overlap_per_site,
        "energy_density_delta" => continuity.energy_density_delta,
        "mean_entropy_delta" => continuity.mean_entropy_delta,
        "maximum_cut_entropy_jump" => continuity.maximum_cut_entropy_jump,
        "energy_term_rms_jump" => continuity.energy_term_rms_jump,
        "magnetization_rms_jump" => continuity.magnetization_rms_jump,
        "mean_schmidt_total_variation" => continuity.mean_schmidt_total_variation,
        "source_state_path" => String(source_state_path),
        "source_state_sha256" => String(source_state_sha256),
        "candidate_state_path" => String(candidate_state_path),
        "candidate_state_sha256" => String(candidate_state_sha256),
    )
    try
        open(temporary_path, "w") do io
            TOML.print(io, data; sorted=true)
        end
        Base.Filesystem.rename(temporary_path, output_path)
    catch
        isfile(temporary_path) && rm(temporary_path; force=true)
        rethrow()
    end
    return output_path
end

function write_fixed_flux_optimizer_resume_outcome(
    settings::ProjectSettings,
    diagnostic::VumpsDiagnostics,
    continuity::BranchContinuityDiagnostics,
    theta_over_pi::Real,
    point_index::Integer,
    accepted_parent_maxdim::Integer,
    checkpoint_maxdim::Integer,
    result_maxdim::Integer,
    checkpoint_iterations::Integer,
    checkpoint_residual::Real,
    checkpoint_minimum_residual::Real,
    checkpoint_stop_reason::AbstractString,
    accepted_parent_state_path::AbstractString,
    accepted_parent_state_sha256::AbstractString,
    optimizer_checkpoint_path::AbstractString,
    optimizer_checkpoint_sha256::AbstractString,
    candidate_state_path::AbstractString,
    candidate_state_sha256::AbstractString,
)
    output_path = joinpath(settings.runtime.output_directory, "scan_outcome.toml")
    ispath(output_path) && error("refusing to overwrite immutable scan outcome: $output_path")
    temporary_path = output_path * ".tmp"
    ispath(temporary_path) && error("stale temporary scan outcome exists: $temporary_path")
    continuity_loss = diagnostic.converged && continuity.checked && !continuity.passed
    data = Dict{String,Any}(
        "schema_version" => 2,
        "artifact_kind" => "project_b_fixed_flux_optimizer_resume_outcome",
        "created_at_utc" => string(now(UTC)),
        "status" => continuity_loss ?
            "fixed_flux_optimizer_resume_continuity_rejected" :
            "fixed_flux_optimizer_resume_numerical_failure",
        "classification" => continuity_loss ?
            "possible_basin_jump_not_physical_endpoint" :
            numerical_continuation_classification(diagnostic),
        "physical_endpoint" => false,
        "continuation_accepted" => false,
        "config_id" => config_identifier(settings),
        "config_path" => settings.config_path,
        "geometry" => string(settings.model.geometry),
        "branch" => settings.scan.branch,
        "preparation" => settings.scan.preparation,
        "direction" => string(settings.scan.direction),
        "random_seed" => settings.scan.random_seed,
        "point_index" => Int(point_index),
        "theta_over_pi" => Float64(theta_over_pi),
        "accepted_parent_maxdim" => Int(accepted_parent_maxdim),
        "checkpoint_maxdim" => Int(checkpoint_maxdim),
        "requested_maxdim" => settings.optimizer.maxdim,
        "result_maxdim" => Int(result_maxdim),
        "checkpoint_cumulative_iterations" => Int(checkpoint_iterations),
        "checkpoint_residual" => Float64(checkpoint_residual),
        "checkpoint_minimum_residual" => Float64(checkpoint_minimum_residual),
        "checkpoint_stop_reason" => String(checkpoint_stop_reason),
        "optimizer_additional_iterations" => diagnostic.iterations,
        "optimizer_cumulative_iterations" => checkpoint_iterations + diagnostic.iterations,
        "residual" => diagnostic.residual,
        "minimum_residual" => min(
            Float64(checkpoint_minimum_residual),
            diagnostic.minimum_residual,
        ),
        "optimizer_terminal_residual" => diagnostic.terminal_residual,
        "optimizer_best_iteration" => diagnostic.best_iteration,
        "optimizer_returned_iteration" => diagnostic.returned_iteration,
        "optimizer_restored_best_on_failure" => diagnostic.restored_best_on_failure,
        "optimizer_multisite_update_alg" => settings.optimizer.multisite_update_alg,
        "optimizer_restore_best_on_failure_enabled" =>
            settings.optimizer.restore_best_on_failure,
        "residual_tolerance" => settings.optimizer.residual_tol,
        "optimizer_stop_reason" => diagnostic.stop_reason,
        "optimizer_max_iterations" => settings.optimizer.max_iterations,
        "optimizer_plateau_detection" => settings.optimizer.plateau_detection,
        "optimizer_trend_window" => diagnostic.trend_window,
        "optimizer_recent_relative_improvement" =>
            diagnostic.recent_relative_improvement,
        "optimizer_log_residual_slope" => diagnostic.log_residual_slope,
        "optimizer_log_residual_r_squared" => diagnostic.log_residual_r_squared,
        "optimizer_projected_total_iterations" => diagnostic.projected_total_iterations,
        "optimizer_projected_cumulative_iterations" =>
            checkpoint_iterations + diagnostic.projected_total_iterations,
        "optimizer_krylov_solve_count" => length(diagnostic.krylov_solves),
        "continuity_checked" => continuity.checked,
        "continuity_passed" => continuity.passed,
        "continuity_reason" => continuity.reason,
        "parent_overlap_per_unit_cell" => continuity.overlap_per_unit_cell,
        "parent_overlap_per_site" => continuity.overlap_per_site,
        "minimum_parent_overlap_per_site" => continuity.minimum_overlap_per_site,
        "energy_density_delta" => continuity.energy_density_delta,
        "mean_entropy_delta" => continuity.mean_entropy_delta,
        "maximum_cut_entropy_jump" => continuity.maximum_cut_entropy_jump,
        "energy_term_rms_jump" => continuity.energy_term_rms_jump,
        "magnetization_rms_jump" => continuity.magnetization_rms_jump,
        "mean_schmidt_total_variation" => continuity.mean_schmidt_total_variation,
        "accepted_parent_state_path" => String(accepted_parent_state_path),
        "accepted_parent_state_sha256" => String(accepted_parent_state_sha256),
        "optimizer_checkpoint_path" => String(optimizer_checkpoint_path),
        "optimizer_checkpoint_sha256" => String(optimizer_checkpoint_sha256),
        "candidate_state_path" => String(candidate_state_path),
        "candidate_state_sha256" => String(candidate_state_sha256),
    )
    try
        open(temporary_path, "w") do io
            TOML.print(io, data; sorted=true)
        end
        Base.Filesystem.rename(temporary_path, output_path)
    catch
        isfile(temporary_path) && rm(temporary_path; force=true)
        rethrow()
    end
    return output_path
end

function run_flux_scan(settings::ProjectSettings)
    configure_threading!(settings.runtime)
    mkpath(settings.runtime.output_directory)
    initial = load_or_build_initial_state(settings)
    psi = initial.psi
    initial_theta = initial.initial_theta
    parent_state_path = initial.parent_state_path
    parent_state_sha256 = initial.parent_state_sha256
    parent_maxdim = initial.parent_maxdim
    flux_history = initial.flux_history_over_pi
    optimizer_checkpoint_path = initial.optimizer_checkpoint_path
    optimizer_checkpoint_sha256 = initial.optimizer_checkpoint_sha256
    optimizer_checkpoint_iterations = initial.optimizer_checkpoint_iterations
    optimizer_checkpoint_residual = initial.optimizer_checkpoint_residual
    optimizer_checkpoint_minimum_residual =
        initial.optimizer_checkpoint_minimum_residual
    optimizer_checkpoint_stop_reason = initial.optimizer_checkpoint_stop_reason
    if !isempty(optimizer_checkpoint_path)
        println(
            "Optimizer-checkpoint resume: accepted parent=$(parent_state_path), " *
            "numerical seed=$(optimizer_checkpoint_path), " *
            "prior outer iterations=$optimizer_checkpoint_iterations",
        )
    end
    queue = copy(settings.scan.fluxes_over_pi)
    if initial_theta !== nothing && !isapprox(first(queue), initial_theta; atol=1e-12, rtol=0)
        @warn "Initial-state flux differs from first scheduled flux" initial_theta first_flux=first(queue)
    end
    last_accepted_theta = initial_theta
    output_paths = String[]
    attempted = Set{Tuple{Float64,Float64}}()
    point_index = 0

    while !isempty(queue)
        theta_over_pi = popfirst!(queue)
        point_index += 1
        source_maxdim = maxlinkdim(psi)
        fixed_flux_expansion = fixed_flux_expansion_requested(
            last_accepted_theta,
            theta_over_pi,
            source_maxdim,
            settings.optimizer.maxdim,
        )
        fixed_flux_optimizer_resume = fixed_flux_optimizer_resume_requested(
            last_accepted_theta,
            theta_over_pi,
            optimizer_checkpoint_path,
        )
        println(
            "\nPoint $point_index: branch=$(settings.scan.branch), geometry=$(settings.model.geometry), " *
            "preparation=$(settings.scan.preparation), direction=$(settings.scan.direction), " *
            "seed=$(settings.scan.random_seed), theta/pi=$theta_over_pi, " *
            "chi=$(settings.optimizer.maxdim)",
        )
        hamiltonian = build_hamiltonian(settings.model, siteinds(psi), theta_over_pi)
        candidate, diagnostic = optimize_candidate(
            hamiltonian,
            psi,
            settings.optimizer;
            output_level=settings.runtime.output_level,
        )
        candidate_observables = local_observables(candidate, hamiltonian)
        inner_solver_eligible = !settings.optimizer.record_krylov_diagnostics ||
            all_recorded_krylov_solves_converged(diagnostic)
        numerically_eligible =
            (diagnostic.converged || !settings.optimizer.require_converged) &&
            inner_solver_eligible
        continuity = numerically_eligible ? evaluate_branch_continuity(
            settings,
            candidate,
            candidate_observables,
            last_accepted_theta,
            theta_over_pi,
            parent_state_path,
            parent_state_sha256,
            point_index,
        ) : skipped_branch_continuity(
            inner_solver_eligible ?
                "VUMPS residual gate failed before parent-overlap evaluation" :
                "an inner Krylov solve failed before parent-overlap evaluation";
            passed=false,
            parent_theta_over_pi=something(last_accepted_theta, NaN),
            candidate_theta_over_pi=theta_over_pi,
            minimum_overlap_per_site=settings.scan.minimum_parent_overlap_per_site,
        )
        accepted = numerically_eligible && continuity.passed
        path = state_file_path(settings, point_index, theta_over_pi, accepted)
        saved = nothing
        if accepted || settings.scan.save_rejected
            saved = write_state_file(
                path,
                settings,
                candidate,
                hamiltonian,
                diagnostic,
                theta_over_pi,
                point_index;
                continuation_accepted=accepted,
                parent_state_path,
                parent_state_sha256,
                parent_flux_history_over_pi=flux_history,
                optimizer_checkpoint_path,
                optimizer_checkpoint_sha256,
                optimizer_checkpoint_iterations,
                optimizer_checkpoint_residual,
                optimizer_checkpoint_minimum_residual,
                optimizer_checkpoint_stop_reason,
                continuity,
                precomputed_observables=candidate_observables,
            )
            push!(output_paths, saved.path)
            @printf(
                "Saved %s point: E=%.12f, mean(S)=%.8f, residual=%.4e -> %s\n",
                accepted ? "converged" :
                    (!inner_solver_eligible ? "inner-solver-rejected" :
                     (diagnostic.converged ? "continuity-rejected" : "rejected")),
                saved.observables.energy_density,
                mean(saved.observables.entropy.von_neumann),
                diagnostic.residual,
                saved.path,
            )
            println("State SHA-256: $(saved.state_sha256)")
        end
        if continuity.checked
            @printf(
                "Parent continuity: overlap/cell=%.10g, overlap/site=%.10g, minimum=%.10g, passed=%s, deltaE=%.4e, deltaS=%.4e\n",
                continuity.overlap_per_unit_cell,
                continuity.overlap_per_site,
                continuity.minimum_overlap_per_site,
                continuity.passed,
                continuity.energy_density_delta,
                continuity.mean_entropy_delta,
            )
        end
        if fixed_flux_optimizer_resume
            println(
                "Optimizer-checkpoint progress: prior=$optimizer_checkpoint_iterations, " *
                "additional=$(diagnostic.iterations), cumulative=" *
                "$(optimizer_checkpoint_iterations + diagnostic.iterations)",
            )
        end

        if accepted
            psi = candidate
            last_accepted_theta = theta_over_pi
            if saved !== nothing
                parent_state_path = abspath(saved.path)
                parent_state_sha256 = saved.state_sha256
                flux_history = saved.flux_history_over_pi
            elseif isempty(flux_history) ||
                    !isapprox(last(flux_history), theta_over_pi; atol=1e-12, rtol=0)
                push!(flux_history, theta_over_pi)
            end
            continue
        end

        if fixed_flux_optimizer_resume
            saved === nothing && error(
                "cannot classify a fixed-flux optimizer-resume failure without a saved " *
                "candidate state",
            )
            outcome_path = write_fixed_flux_optimizer_resume_outcome(
                settings,
                diagnostic,
                continuity,
                theta_over_pi,
                point_index,
                parent_maxdim,
                source_maxdim,
                maxlinkdim(candidate),
                optimizer_checkpoint_iterations,
                optimizer_checkpoint_residual,
                optimizer_checkpoint_minimum_residual,
                optimizer_checkpoint_stop_reason,
                parent_state_path,
                parent_state_sha256,
                optimizer_checkpoint_path,
                optimizer_checkpoint_sha256,
                saved.path,
                saved.state_sha256,
            )
            if diagnostic.converged && continuity.checked && !continuity.passed
                @warn "Fixed-flux optimizer resume failed the branch-continuity gate" theta_over_pi checkpoint_iterations=optimizer_checkpoint_iterations additional_iterations=diagnostic.iterations overlap_per_site=continuity.overlap_per_site minimum_overlap_per_site=continuity.minimum_overlap_per_site outcome_path
            else
                @warn "Fixed-flux optimizer resume ended without numerical acceptance" theta_over_pi checkpoint_iterations=optimizer_checkpoint_iterations additional_iterations=diagnostic.iterations cumulative_iterations=optimizer_checkpoint_iterations + diagnostic.iterations residual=diagnostic.residual tolerance=settings.optimizer.residual_tol stop_reason=diagnostic.stop_reason outcome_path
            end
            break
        end

        if fixed_flux_expansion
            saved === nothing && error(
                "cannot classify a fixed-flux expansion failure without a saved candidate state",
            )
            outcome_path = write_fixed_flux_expansion_outcome(
                settings,
                diagnostic,
                continuity,
                theta_over_pi,
                point_index,
                source_maxdim,
                maxlinkdim(candidate),
                parent_state_path,
                parent_state_sha256,
                saved.path,
                saved.state_sha256,
            )
            if diagnostic.converged && continuity.checked && !continuity.passed
                @warn "Fixed-flux expansion failed the branch-continuity gate" theta_over_pi source_maxdim requested_maxdim=settings.optimizer.maxdim result_maxdim=maxlinkdim(candidate) overlap_per_site=continuity.overlap_per_site minimum_overlap_per_site=continuity.minimum_overlap_per_site outcome_path
            else
                @warn "Fixed-flux expansion ended without numerical acceptance" theta_over_pi source_maxdim requested_maxdim=settings.optimizer.maxdim result_maxdim=maxlinkdim(candidate) residual=diagnostic.residual tolerance=settings.optimizer.residual_tol stop_reason=diagnostic.stop_reason outcome_path
            end
            break
        end

        can_refine = inner_solver_eligible && settings.scan.adaptive_bisection &&
            last_accepted_theta !== nothing &&
            !minimum_step_bracket_reached(
                last_accepted_theta,
                theta_over_pi,
                settings.scan.minimum_step_over_pi,
            )
        interval = last_accepted_theta === nothing ? (NaN, theta_over_pi) :
            (Float64(last_accepted_theta), Float64(theta_over_pi))
        if can_refine && !(interval in attempted)
            push!(attempted, interval)
            midpoint = insert_refinement!(queue, interval[1], interval[2])
            @warn "Continuation point rejected; bisecting interval" interval midpoint residual=diagnostic.residual continuity_reason=continuity.reason
            continue
        end
        bracketed_loss = settings.scan.adaptive_bisection &&
            last_accepted_theta !== nothing &&
            minimum_step_bracket_reached(
                last_accepted_theta,
                theta_over_pi,
                settings.scan.minimum_step_over_pi,
            )
        if bracketed_loss
            saved === nothing && error(
                "cannot classify a bracketed continuation loss without a saved rejected state",
            )
            outcome_path = write_bracketed_scan_outcome(
                settings,
                diagnostic,
                continuity,
                last_accepted_theta,
                theta_over_pi,
                point_index,
                parent_state_path,
                parent_state_sha256,
                saved.path,
                saved.state_sha256,
            )
            if diagnostic.converged && continuity.checked && !continuity.passed
                @warn "Branch-continuity loss bracketed at configured resolution" interval residual=diagnostic.residual overlap_per_site=continuity.overlap_per_site minimum_overlap_per_site=continuity.minimum_overlap_per_site outcome_path
            elseif diagnostic.stop_reason == "maximum_iterations_contracting"
                @warn "Iteration-limited continuation bracketed while the residual was still contracting" interval residual=diagnostic.residual tolerance=settings.optimizer.residual_tol recent_relative_improvement=diagnostic.recent_relative_improvement projected_total_iterations=diagnostic.projected_total_iterations outcome_path
            else
                @warn "Numerical continuation loss bracketed at configured resolution" interval residual=diagnostic.residual tolerance=settings.optimizer.residual_tol outcome_path
            end
            break
        end
        inner_solver_eligible || error(
            "continuation rejected at theta/pi=$theta_over_pi because at least one " *
            "recorded inner Krylov solve did not converge; refusing automatic " *
            "refinement or continuation",
        )
        error(
            "continuation rejected at theta/pi=$theta_over_pi " *
            "(residual=$(diagnostic.residual), tolerance=$(settings.optimizer.residual_tol), " *
            "continuity=$(continuity.reason)); refusing to seed the next point",
        )
    end
    return output_paths
end

function run_chi_ladder(settings::ProjectSettings, maxdims::AbstractVector{<:Integer})
    isempty(maxdims) && throw(ArgumentError("chi ladder cannot be empty"))
    issorted(maxdims) || throw(ArgumentError("chi ladder must be sorted in increasing order"))
    length(settings.scan.fluxes_over_pi) == 1 ||
        throw(ArgumentError("chi-ladder configuration must contain exactly one flux"))
    settings.scan.optimizer_checkpoint_file === nothing || throw(ArgumentError(
        "optimizer checkpoints are supported only by an isolated flux scan, not a chi ladder",
    ))
    configure_threading!(settings.runtime)
    initial = load_or_build_initial_state(settings)
    psi = initial.psi
    initial_theta = initial.initial_theta
    parent_state_path = initial.parent_state_path
    parent_state_sha256 = initial.parent_state_sha256
    flux_history = initial.flux_history_over_pi
    theta_over_pi = only(settings.scan.fluxes_over_pi)
    initial_theta !== nothing && !isapprox(initial_theta, theta_over_pi; atol=1e-12, rtol=0) &&
        error("initial-state flux does not match chi-ladder flux")
    hamiltonian = build_hamiltonian(settings.model, siteinds(psi), theta_over_pi)
    paths = String[]
    for (index, maxdim) in enumerate(maxdims)
        optimizer = optimizer_with_maxdim(settings.optimizer, maxdim)
        psi, diagnostic = optimize_candidate(
            hamiltonian,
            psi,
            optimizer;
            output_level=settings.runtime.output_level,
        )
        ladder_settings = ProjectSettings(
            model=settings.model,
            optimizer=optimizer,
            scan=settings.scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# runtime chi override = $maxdim\n",
        )
        path = state_file_path(
            ladder_settings,
            index,
            theta_over_pi,
            diagnostic.converged;
            maxdim,
        )
        saved = write_state_file(
            path,
            ladder_settings,
            psi,
            hamiltonian,
            diagnostic,
            theta_over_pi,
            index;
            continuation_accepted=diagnostic.converged,
            parent_state_path,
            parent_state_sha256,
            parent_flux_history_over_pi=flux_history,
        )
        push!(paths, saved.path)
        parent_state_path = abspath(saved.path)
        parent_state_sha256 = saved.state_sha256
        flux_history = saved.flux_history_over_pi
        diagnostic.converged || error(
            "chi ladder stopped at chi=$maxdim with residual=$(diagnostic.residual)",
        )
    end
    return paths
end
