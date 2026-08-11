Base.@kwdef struct KrylovSolveDiagnostic
    outer_iteration::Int
    solve_kind::String
    site::Int
    requested_tolerance::Float64
    krylov_dimension::Int
    maximum_iterations::Int
    converged_count::Int
    residual_norm::Float64
    iterations::Int
    operations::Int
    elapsed_seconds::Float64
end

Base.@kwdef struct VumpsDiagnostics
    converged::Bool
    stop_reason::String
    iterations::Int
    residual::Float64
    minimum_residual::Float64
    residual_history::Vector{Float64}
    energy_left_history::Matrix{Float64}
    energy_right_history::Matrix{Float64}
    growth_dimensions::Vector{Int}
    growth_stage_ends::Vector{Int}
    residual_tolerance::Float64 = NaN
    trend_window::Int = 0
    recent_relative_improvement::Float64 = NaN
    log_residual_slope::Float64 = NaN
    log_residual_r_squared::Float64 = NaN
    projected_total_iterations::Float64 = NaN
    krylov_solves::Vector{KrylovSolveDiagnostic} = KrylovSolveDiagnostic[]
end

Base.@kwdef mutable struct KrylovInstrumentationContext
    outer_iteration::Int = 0
    krylov_dimension::Int
    maximum_iterations::Int
    record_diagnostics::Bool
    records::Vector{KrylovSolveDiagnostic} = KrylovSolveDiagnostic[]
end

# ITensorInfiniteMPS does not return the convergence records from its two
# environment linear solves. The narrowly typed methods below retain the same
# KrylovKit algorithm, but expose those records while an instrumented VUMPS
# iteration is active. Outside that scope they delegate with the package's
# original keyword arguments and defaults.
const ACTIVE_KRYLOV_CONTEXT = Ref{Union{Nothing,KrylovInstrumentationContext}}(nothing)

function with_krylov_context(f::Function, context::KrylovInstrumentationContext)
    previous = ACTIVE_KRYLOV_CONTEXT[]
    previous === nothing || error("nested VUMPS Krylov instrumentation is unsupported")
    ACTIVE_KRYLOV_CONTEXT[] = context
    try
        return f()
    finally
        ACTIVE_KRYLOV_CONTEXT[] = previous
    end
end

function krylov_residual_norm(info)
    values = info.normres
    if values isa Number
        return Float64(abs(values))
    end
    isempty(values) && return NaN
    return maximum(Float64.(abs.(values)))
end

function record_krylov_solve!(
    context::KrylovInstrumentationContext,
    solve_kind::AbstractString,
    site::Integer,
    requested_tolerance::Real,
    info,
    elapsed_seconds::Real,
)
    context.record_diagnostics || return nothing
    push!(
        context.records,
        KrylovSolveDiagnostic(
            outer_iteration=context.outer_iteration,
            solve_kind=String(solve_kind),
            site=Int(site),
            requested_tolerance=Float64(requested_tolerance),
            krylov_dimension=context.krylov_dimension,
            maximum_iterations=context.maximum_iterations,
            converged_count=Int(info.converged),
            residual_norm=krylov_residual_norm(info),
            iterations=Int(info.numiter),
            operations=Int(info.numops),
            elapsed_seconds=Float64(elapsed_seconds),
        ),
    )
    return nothing
end

function instrumented_environment_linsolve(
    solve_kind::AbstractString,
    operator,
    b,
    a0::Number,
    a1::Number;
    kwargs...,
)
    context = ACTIVE_KRYLOV_CONTEXT[]
    delegated_operator = x -> operator(x)
    if context === nothing
        return KrylovKit.linsolve(delegated_operator, b, a0, a1; kwargs...)
    end
    options = merge(
        (; kwargs...),
        (
            krylovdim=context.krylov_dimension,
            maxiter=context.maximum_iterations,
        ),
    )
    result = nothing
    elapsed = @elapsed result = KrylovKit.linsolve(
        delegated_operator,
        b,
        a0,
        a1;
        options...,
    )
    solution, info = result
    tolerance = haskey(options, :tol) ? options.tol : NaN
    record_krylov_solve!(
        context,
        solve_kind,
        getfield(operator, :n),
        tolerance,
        info,
        elapsed,
    )
    return solution, info
end

function KrylovKit.linsolve(
    operator::ITensorInfiniteMPS.Aᴸ,
    b,
    a0::Number=0,
    a1::Number=1;
    kwargs...,
)
    return instrumented_environment_linsolve(
        "environment_left",
        operator,
        b,
        a0,
        a1;
        kwargs...,
    )
end

function KrylovKit.linsolve(
    operator::ITensorInfiniteMPS.Aᴿ,
    b,
    a0::Number=0,
    a1::Number=1;
    kwargs...,
)
    return instrumented_environment_linsolve(
        "environment_right",
        operator,
        b,
        a0,
        a1;
        kwargs...,
    )
end

function instrumented_vumps_solver(M, time_step, v0, solver_tolerance, eager=true)
    context = ACTIVE_KRYLOV_CONTEXT[]
    context === nothing && return ITensorInfiniteMPS.vumps_solver(
        M,
        time_step,
        v0,
        solver_tolerance,
        eager,
    )
    result = nothing
    elapsed = @elapsed result = KrylovKit.eigsolve(
        M,
        v0,
        1,
        :SR;
        ishermitian=true,
        tol=solver_tolerance,
        krylovdim=context.krylov_dimension,
        maxiter=context.maximum_iterations,
        eager,
    )
    eigenvalues, eigenvectors, info = result
    solve_kind = M isa ITensorInfiniteMPS.Hᶜ ? "center_C" :
        (M isa ITensorInfiniteMPS.Hᴬᶜ ? "center_AC" : "center_unknown")
    site = hasfield(typeof(M), :n) ? Int(getfield(M, :n)) : 0
    record_krylov_solve!(
        context,
        solve_kind,
        site,
        solver_tolerance,
        info,
        elapsed,
    )
    return eigenvalues[1], eigenvectors[1], info
end

function configure_threading!(runtime::RuntimeSettings)
    runtime.blas_threads >= 1 || error("BLAS thread count must be positive")
    runtime.strided_threads >= 1 || error("Strided thread count must be positive")
    BLAS.set_num_threads(runtime.blas_threads)
    try
        ITensors.NDTensors.Strided.set_num_threads(runtime.strided_threads)
    catch err
        @warn "Could not configure ITensor Strided threads" exception=(err, catch_backtrace())
    end
    blocksparse = try
        runtime.threaded_blocksparse ?
            ITensors.enable_threaded_blocksparse() : ITensors.disable_threaded_blocksparse()
        ITensors.using_threaded_blocksparse()
    catch err
        @warn "Could not configure block-sparse threading" exception=(err, catch_backtrace())
        missing
    end
    active_strided = try
        ITensors.NDTensors.Strided.get_num_threads()
    catch
        missing
    end
    println(
        "Threading: Julia=$(Threads.nthreads()), BLAS=$(BLAS.get_num_threads()), " *
        "Strided=$(active_strided), BlockSparse=$(blocksparse)",
    )
    return (; blas=BLAS.get_num_threads(), strided=active_strided, blocksparse)
end

function residual_trend(
    residual_history::AbstractVector{<:Real},
    residual_tolerance::Real;
    improvement_window::Integer=24,
    regression_window::Integer=100,
)
    count = length(residual_history)
    count == 0 && return (
        window=0,
        relative_improvement=NaN,
        log_slope=NaN,
        r_squared=NaN,
        projected_total_iterations=NaN,
    )
    improvement_count = min(max(Int(improvement_window), 1), max(count - 1, 1))
    relative_improvement = NaN
    if count > improvement_count
        prior_best = minimum(@view residual_history[1:(count - improvement_count)])
        recent_best = minimum(@view residual_history[(count - improvement_count + 1):count])
        if isfinite(prior_best) && prior_best > 0 && isfinite(recent_best)
            relative_improvement = (prior_best - recent_best) / prior_best
        end
    end

    window = min(count, max(Int(regression_window), 2))
    values = Float64.(residual_history[(count - window + 1):count])
    if window < 2 || any(value -> !isfinite(value) || value <= 0, values)
        return (;
            window,
            relative_improvement,
            log_slope=NaN,
            r_squared=NaN,
            projected_total_iterations=NaN,
        )
    end
    x = Float64.(1:window)
    y = log.(values)
    centered_x = x .- mean(x)
    centered_y = y .- mean(y)
    denominator = sum(abs2, centered_x)
    slope = denominator == 0 ? NaN : sum(centered_x .* centered_y) / denominator
    fitted = mean(y) .+ slope .* centered_x
    total_variation = sum(abs2, centered_y)
    r_squared = total_variation == 0 ? 1.0 :
        1 - sum(abs2, y .- fitted) / total_variation
    projected_total = if isfinite(slope) && slope < 0 && last(values) > residual_tolerance
        count + log(Float64(residual_tolerance) / last(values)) / slope
    elseif last(values) <= residual_tolerance
        Float64(count)
    else
        NaN
    end
    return (;
        window,
        relative_improvement,
        log_slope=slope,
        r_squared,
        projected_total_iterations=projected_total,
    )
end

function residual_plateau_detected(
    residual_history::AbstractVector{<:Real},
    optimizer::OptimizerSettings,
)
    optimizer.plateau_detection || return false
    count = length(residual_history)
    count >= max(optimizer.plateau_warmup_iterations, optimizer.plateau_patience + 1) ||
        return false
    split = count - optimizer.plateau_patience
    prior_best = minimum(@view residual_history[1:split])
    recent_best = minimum(@view residual_history[(split + 1):count])
    isfinite(prior_best) && prior_best > 0 && isfinite(recent_best) || return false
    recent_best > optimizer.residual_tol || return false
    relative_improvement = (prior_best - recent_best) / prior_best
    return relative_improvement < optimizer.plateau_min_relative_improvement
end

function run_vumps_iterations(
    hamiltonian,
    psi,
    optimizer::OptimizerSettings;
    output_level::Integer=1,
)
    n = nsites(psi)
    epsilon_left = fill(optimizer.residual_tol, n)
    epsilon_right = fill(optimizer.residual_tol, n)
    residual_history = sizehint!(Float64[], optimizer.max_iterations)
    energy_left_buffer = Matrix{Float64}(undef, n, optimizer.max_iterations)
    energy_right_buffer = Matrix{Float64}(undef, n, optimizer.max_iterations)
    solver_tolerance = x -> max(x / optimizer.solver_tol_scale, optimizer.solver_tol_floor)
    stop_reason = "maximum_iterations"
    custom_krylov = optimizer.record_krylov_diagnostics ||
        optimizer.solver_krylov_dimension != 30 ||
        optimizer.solver_max_iterations != 100
    context = KrylovInstrumentationContext(
        krylov_dimension=optimizer.solver_krylov_dimension,
        maximum_iterations=optimizer.solver_max_iterations,
        record_diagnostics=optimizer.record_krylov_diagnostics,
    )

    for iteration in 1:optimizer.max_iterations
        context.outer_iteration = iteration
        elapsed = @elapsed begin
            step = function ()
                return ITensorInfiniteMPS.tdvp_iteration(
                    custom_krylov ? instrumented_vumps_solver : ITensorInfiniteMPS.vumps_solver,
                    hamiltonian,
                    psi;
                    (ϵᴸ!)=epsilon_left,
                    (ϵᴿ!)=epsilon_right,
                    multisite_update_alg=optimizer.multisite_update_alg,
                    solver_tol=solver_tolerance,
                    time_step=-Inf,
                    eager=true,
                )
            end
            result = custom_krylov ? with_krylov_context(step, context) : step()
            psi, (energy_left, energy_right) = result
            length(energy_left) == n || error("VUMPS left-energy vector size changed")
            length(energy_right) == n || error("VUMPS right-energy vector size changed")
            energy_left_buffer[:, iteration] .= real.(energy_left)
            energy_right_buffer[:, iteration] .= real.(energy_right)
        end
        residual = max(maximum(epsilon_left), maximum(epsilon_right))
        push!(residual_history, residual)
        output_level > 0 && @printf(
            "VUMPS iteration %d: chi=%d residual=%.6e target=%.3e time=%.2fs\n",
            iteration,
            maxlinkdim(psi),
            residual,
            optimizer.residual_tol,
            elapsed,
        )
        if !isfinite(residual)
            stop_reason = "nonfinite_residual"
            break
        elseif residual <= optimizer.residual_tol
            stop_reason = "converged"
            break
        elseif residual_plateau_detected(residual_history, optimizer)
            stop_reason = "residual_plateau"
            output_level > 0 && @printf(
                "VUMPS plateau detector stopped at iteration %d after less than %.3g relative improvement over %d iterations.\n",
                iteration,
                optimizer.plateau_min_relative_improvement,
                optimizer.plateau_patience,
            )
            break
        elseif length(residual_history) >= optimizer.divergence_patience
            window = @view residual_history[(end - optimizer.divergence_patience + 1):end]
            historical_minimum = minimum(@view residual_history[1:(end - optimizer.divergence_patience + 1)])
            if minimum(window) > optimizer.divergence_factor * historical_minimum &&
               last(window) > 100 * optimizer.residual_tol
                stop_reason = "diverging_residual"
                break
            end
        end
    end

    trend = residual_trend(
        residual_history,
        optimizer.residual_tol;
        improvement_window=optimizer.plateau_patience,
    )
    if stop_reason == "maximum_iterations"
        stop_reason = isfinite(trend.relative_improvement) &&
            trend.relative_improvement >= optimizer.plateau_min_relative_improvement &&
            isfinite(trend.log_slope) && trend.log_slope < 0 ?
            "maximum_iterations_contracting" : "maximum_iterations_stalled"
        if output_level > 0 && stop_reason == "maximum_iterations_contracting"
            @printf(
                "VUMPS reached its iteration cap while still contracting: recent improvement=%.3g, projected tolerance iteration=%.1f (log-fit R^2=%.5f).\n",
                trend.relative_improvement,
                trend.projected_total_iterations,
                trend.r_squared,
            )
        end
    end

    residual = isempty(residual_history) ? Inf : last(residual_history)
    iterations = length(residual_history)
    diagnostics = VumpsDiagnostics(
        converged=residual <= optimizer.residual_tol,
        stop_reason=stop_reason,
        iterations=iterations,
        residual=residual,
        minimum_residual=isempty(residual_history) ? Inf : minimum(residual_history),
        residual_history=residual_history,
        energy_left_history=copy(@view energy_left_buffer[:, 1:iterations]),
        energy_right_history=copy(@view energy_right_buffer[:, 1:iterations]),
        growth_dimensions=[maxlinkdim(psi)],
        growth_stage_ends=[length(residual_history)],
        residual_tolerance=optimizer.residual_tol,
        trend_window=trend.window,
        recent_relative_improvement=trend.relative_improvement,
        log_residual_slope=trend.log_slope,
        log_residual_r_squared=trend.r_squared,
        projected_total_iterations=trend.projected_total_iterations,
        krylov_solves=context.records,
    )
    return psi, diagnostics
end

function merge_diagnostics(stages::AbstractVector{VumpsDiagnostics}, growth_dimensions::Vector{Int})
    isempty(stages) && error("cannot merge an empty diagnostic list")
    residuals = reduce(vcat, (stage.residual_history for stage in stages))
    left = reduce(hcat, (stage.energy_left_history for stage in stages))
    right = reduce(hcat, (stage.energy_right_history for stage in stages))
    stage_ends = cumsum([length(stage.residual_history) for stage in stages])
    krylov_solves = KrylovSolveDiagnostic[]
    iteration_offset = 0
    for stage in stages
        for record in stage.krylov_solves
            push!(
                krylov_solves,
                KrylovSolveDiagnostic(
                    outer_iteration=iteration_offset + record.outer_iteration,
                    solve_kind=record.solve_kind,
                    site=record.site,
                    requested_tolerance=record.requested_tolerance,
                    krylov_dimension=record.krylov_dimension,
                    maximum_iterations=record.maximum_iterations,
                    converged_count=record.converged_count,
                    residual_norm=record.residual_norm,
                    iterations=record.iterations,
                    operations=record.operations,
                    elapsed_seconds=record.elapsed_seconds,
                ),
            )
        end
        iteration_offset += stage.iterations
    end
    final = last(stages)
    prior_iterations = length(residuals) - final.iterations
    projected_total_iterations = isfinite(final.projected_total_iterations) ?
        prior_iterations + final.projected_total_iterations : final.projected_total_iterations
    return VumpsDiagnostics(
        converged=final.converged,
        stop_reason=final.stop_reason,
        iterations=length(residuals),
        residual=last(residuals),
        minimum_residual=minimum(residuals),
        residual_history=residuals,
        energy_left_history=left,
        energy_right_history=right,
        growth_dimensions=growth_dimensions,
        growth_stage_ends=collect(stage_ends),
        residual_tolerance=final.residual_tolerance,
        trend_window=final.trend_window,
        recent_relative_improvement=final.recent_relative_improvement,
        log_residual_slope=final.log_residual_slope,
        log_residual_r_squared=final.log_residual_r_squared,
        projected_total_iterations=projected_total_iterations,
        krylov_solves=krylov_solves,
    )
end

function grow_and_optimize(hamiltonian, psi, optimizer::OptimizerSettings; output_level::Integer=1)
    stages = VumpsDiagnostics[]
    dimensions = Int[maxlinkdim(psi)]
    for growth_step in 1:optimizer.max_growth_steps
        old_dimension = maxlinkdim(psi)
        if old_dimension < optimizer.maxdim
            psi = subspace_expansion(
                psi,
                hamiltonian;
                maxdim=optimizer.maxdim,
                cutoff=optimizer.cutoff,
            )
        end
        new_dimension = maxlinkdim(psi)
        push!(dimensions, new_dimension)
        output_level > 0 && println(
            "Growth stage $growth_step: chi $old_dimension -> $new_dimension (target $(optimizer.maxdim))",
        )
        psi, diagnostic = run_vumps_iterations(
            hamiltonian,
            psi,
            optimizer;
            output_level,
        )
        push!(stages, diagnostic)
        new_dimension >= optimizer.maxdim && break
        if new_dimension == old_dimension
            @warn "Subspace expansion did not increase the bond dimension" old_dimension optimizer.maxdim
            break
        end
    end
    return psi, merge_diagnostics(stages, dimensions)
end

function optimizer_with_maxdim(optimizer::OptimizerSettings, maxdim::Integer)
    return OptimizerSettings(
        maxdim=Int(maxdim),
        cutoff=optimizer.cutoff,
        residual_tol=optimizer.residual_tol,
        max_iterations=optimizer.max_iterations,
        max_growth_steps=optimizer.max_growth_steps,
        solver_tol_scale=optimizer.solver_tol_scale,
        solver_tol_floor=optimizer.solver_tol_floor,
        solver_krylov_dimension=optimizer.solver_krylov_dimension,
        solver_max_iterations=optimizer.solver_max_iterations,
        record_krylov_diagnostics=optimizer.record_krylov_diagnostics,
        multisite_update_alg=optimizer.multisite_update_alg,
        require_converged=optimizer.require_converged,
        divergence_patience=optimizer.divergence_patience,
        divergence_factor=optimizer.divergence_factor,
        plateau_detection=optimizer.plateau_detection,
        plateau_warmup_iterations=optimizer.plateau_warmup_iterations,
        plateau_patience=optimizer.plateau_patience,
        plateau_min_relative_improvement=optimizer.plateau_min_relative_improvement,
    )
end
