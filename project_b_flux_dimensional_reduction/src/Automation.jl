const PHASE1_CHI512_NOMINAL_GRID = Float64.(0:10) ./ 10
const PHASE1_CHI512_MINIMUM_STEP_OVER_PI = 0.05
const PHASE1_CHI512_MAX_AUTOMATIC_ITERATIONS = 720

function phase1_next_nominal_fluxes(
    parent_theta_over_pi::Real;
    grid::AbstractVector{<:Real}=PHASE1_CHI512_NOMINAL_GRID,
)
    theta = Float64(parent_theta_over_pi)
    tolerance = max(1e-12, 16 * eps(max(abs(theta), 1.0)))
    return Float64[value for value in grid if value > theta + tolerance]
end

function phase1_refined_forward_schedule(
    parent_theta_over_pi::Real,
    rejected_theta_over_pi::Real;
    grid::AbstractVector{<:Real}=PHASE1_CHI512_NOMINAL_GRID,
)
    parent = Float64(parent_theta_over_pi)
    rejected = Float64(rejected_theta_over_pi)
    rejected > parent || throw(ArgumentError(
        "automatic Phase 1 refinement requires a forward interval",
    ))
    midpoint = round((parent + rejected) / 2; digits=12)
    remaining = phase1_next_nominal_fluxes(parent; grid)
    schedule = Float64[midpoint]
    for theta in remaining
        theta + 1e-12 >= rejected || continue
        isapprox(theta, midpoint; atol=1e-12, rtol=0) || push!(schedule, theta)
    end
    return schedule
end

function phase1_contracting_retry_cap(
    current_max_iterations::Integer,
    projected_total_iterations::Real;
    maximum::Integer=PHASE1_CHI512_MAX_AUTOMATIC_ITERATIONS,
)
    current = Int(current_max_iterations)
    limit = Int(maximum)
    current >= 1 || throw(ArgumentError("current_max_iterations must be positive"))
    limit >= current || throw(ArgumentError("maximum must not be below the current cap"))
    doubled = 2 * current
    projected = isfinite(projected_total_iterations) ?
        ceil(Int, 1.1 * Float64(projected_total_iterations)) : doubled
    return min(limit, max(doubled, projected))
end

function phase1_final_vumps_control_policy(;
    scheduler_state::AbstractString,
    job_exit_code::Union{Nothing,Integer},
    reached_target::Bool,
    outcome_kind::AbstractString="none",
)
    state = uppercase(String(scheduler_state))
    if startswith(state, "COMPLETED") && job_exit_code == 0 &&
            reached_target && outcome_kind == "none"
        return (
            action=:manual_review,
            reason="the final chi-512 parallel VUMPS control converged at theta/pi=0.15; " *
                "review it before promoting a solver change",
        )
    end
    if outcome_kind in ("flux_scan", "operator_termination")
        return (
            action=:manual_review,
            reason="the final chi-512 parallel VUMPS control failed numerically at " *
                "theta/pi=0.15; end the VUMPS campaign and begin the documented iDMRG pivot",
        )
    end
    return (
        action=:manual_review,
        reason="the final chi-512 parallel VUMPS control ended without a conclusive " *
            "numerical result; diagnose the scheduler or implementation before an iDMRG pivot",
    )
end

function phase1_advance_policy(;
    scheduler_state::AbstractString,
    job_exit_code::Union{Nothing,Integer},
    has_accepted_parent::Bool,
    parent_theta_over_pi::Real=NaN,
    parent_inner_solves_converged::Bool=true,
    outcome_kind::AbstractString="none",
    outcome_status::AbstractString="",
    classification::AbstractString="",
    optimizer_stop_reason::AbstractString="",
    bracket_width_over_pi::Real=NaN,
    current_max_iterations::Integer=180,
    projected_total_iterations::Real=NaN,
    candidate_inner_solves_converged::Bool=true,
    minimum_step_over_pi::Real=PHASE1_CHI512_MINIMUM_STEP_OVER_PI,
    target_theta_over_pi::Real=1.0,
)
    state = uppercase(String(scheduler_state))
    infrastructure_failure = any(prefix -> startswith(state, prefix), (
        "TIMEOUT",
        "NODE_FAIL",
        "PREEMPTED",
        "BOOT_FAIL",
        "REVOKED",
    ))
    if infrastructure_failure
        has_accepted_parent || return (
            action=:manual_review,
            reason="infrastructure failure occurred before an accepted restart parent was saved",
        )
        parent_inner_solves_converged || return (
            action=:manual_review,
            reason="the latest accepted parent contains a recorded unconverged inner solve",
        )
        return (
            action=:continue_schedule,
            reason="resume the remaining nominal grid from the latest immutable accepted state",
        )
    end

    startswith(state, "COMPLETED") || return (
        action=:manual_review,
        reason="scheduler state $scheduler_state is not an automatically recoverable terminal state",
    )
    job_exit_code == 0 || return (
        action=:manual_review,
        reason="the completed allocation did not record a successful scan-process exit",
    )
    has_accepted_parent || return (
        action=:manual_review,
        reason="the run has no immutable accepted state from which to continue",
    )
    parent_inner_solves_converged || return (
        action=:manual_review,
        reason="the latest accepted parent contains a recorded unconverged inner solve",
    )

    if outcome_kind == "none"
        if isapprox(
            Float64(parent_theta_over_pi),
            Float64(target_theta_over_pi);
            atol=1e-12,
            rtol=0,
        )
            return (action=:complete, reason="the accepted lineage reached the campaign target")
        end
        return (
            action=:continue_schedule,
            reason="the scheduled points completed cleanly and nominal targets remain",
        )
    end

    occursin("continuity", lowercase(String(outcome_status))) && return (
        action=:manual_review,
        reason="a parent-overlap continuity failure must not be advanced automatically",
    )
    candidate_inner_solves_converged || return (
        action=:manual_review,
        reason="the rejected candidate contains a recorded unconverged inner solve",
    )

    if outcome_kind == "flux_scan"
        if optimizer_stop_reason == "maximum_iterations_contracting"
            if current_max_iterations >= PHASE1_CHI512_MAX_AUTOMATIC_ITERATIONS
                return (
                    action=:manual_review,
                    reason="the contracting retry already reached the automatic 720-iteration cap",
                )
            end
            return (
                action=:retry_contracting,
                reason="rerun the target from the accepted parent with a data-driven iteration cap",
            )
        end
        numerical_refinement = classification in (
            "numerical_divergence_not_physical_endpoint",
            "numerical_plateau_not_physical_endpoint",
            "iteration_limit_stalled_not_physical_endpoint",
            "numerical_not_physical_endpoint",
        )
        width = Float64(bracket_width_over_pi)
        threshold = Float64(minimum_step_over_pi)
        if numerical_refinement && isfinite(width) &&
           width > threshold + max(1e-12, 16 * eps(max(abs(width), 1.0)))
            return (
                action=:refine_interval,
                reason="halve the failed continuation interval and retain the remaining nominal grid",
            )
        end
        return (
            action=:manual_review,
            reason="the numerical failure is already at the approved minimum step or has no safe automatic transition",
        )
    end

    return (
        action=:manual_review,
        reason="outcome type $outcome_kind is outside the automatic chi-512 campaign policy",
    )
end
