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

function run_vumps_iterations(hamiltonian, psi, optimizer::OptimizerSettings; output_level::Integer=1)
    n = nsites(psi)
    epsilon_left = fill(optimizer.residual_tol, n)
    epsilon_right = fill(optimizer.residual_tol, n)
    residual_history = sizehint!(Float64[], optimizer.max_iterations)
    energy_left_buffer = Matrix{Float64}(undef, n, optimizer.max_iterations)
    energy_right_buffer = Matrix{Float64}(undef, n, optimizer.max_iterations)
    solver_tolerance = x -> max(x / optimizer.solver_tol_scale, optimizer.solver_tol_floor)
    stop_reason = "maximum_iterations"

    for iteration in 1:optimizer.max_iterations
        elapsed = @elapsed begin
            psi, (energy_left, energy_right) = ITensorInfiniteMPS.tdvp_iteration(
                ITensorInfiniteMPS.vumps_solver,
                hamiltonian,
                psi;
                (ϵᴸ!)=epsilon_left,
                (ϵᴿ!)=epsilon_right,
                multisite_update_alg=optimizer.multisite_update_alg,
                solver_tol=solver_tolerance,
                time_step=-Inf,
                eager=true,
            )
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
    )
    return psi, diagnostics
end

function merge_diagnostics(stages::AbstractVector{VumpsDiagnostics}, growth_dimensions::Vector{Int})
    isempty(stages) && error("cannot merge an empty diagnostic list")
    residuals = reduce(vcat, (stage.residual_history for stage in stages))
    left = reduce(hcat, (stage.energy_left_history for stage in stages))
    right = reduce(hcat, (stage.energy_right_history for stage in stages))
    stage_ends = cumsum([length(stage.residual_history) for stage in stages])
    final = last(stages)
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
        multisite_update_alg=optimizer.multisite_update_alg,
        require_converged=optimizer.require_converged,
        divergence_patience=optimizer.divergence_patience,
        divergence_factor=optimizer.divergence_factor,
    )
end
