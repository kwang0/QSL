function optimize_candidate(hamiltonian, psi, optimizer::OptimizerSettings; output_level::Integer)
    if maxlinkdim(psi) < optimizer.maxdim
        return grow_and_optimize(hamiltonian, psi, optimizer; output_level)
    elseif maxlinkdim(psi) == optimizer.maxdim
        return run_vumps_iterations(hamiltonian, psi, optimizer; output_level)
    end
    error("state chi=$(maxlinkdim(psi)) exceeds requested chi=$(optimizer.maxdim)")
end

function load_or_build_initial_state(settings::ProjectSettings)
    if settings.scan.initial_state_file === nothing
        return build_product_state(settings), nothing
    end
    state = read_state_file(settings.scan.initial_state_file)
    state.converged || error("initial state is not converged")
    state.continuation_accepted || error("initial state was not accepted for continuation")
    state.circumference == settings.model.geometry.circumference ||
        error("initial state circumference does not match configuration")
    state.shift == settings.model.geometry.shift ||
        error("initial state YC shift does not match configuration")
    expected_period = model_mps_period(settings.model)
    state.mps_period == expected_period || error(
        "initial state uses MPS period $(state.mps_period), but the configuration requires " *
        "$expected_period; legacy supercell states must not seed a minimal-cell production scan",
    )
    state.twist_gauge == settings.model.twist_gauge || error(
        "initial state twist gauge $(state.twist_gauge) does not match configured gauge " *
        "$(settings.model.twist_gauge)",
    )
    for field in (:J1, :J2, :Delta1, :Delta2, :Bz)
        actual = getproperty(state, field)
        expected = getproperty(settings.model, field)
        isapprox(actual, expected; atol=1e-12, rtol=1e-12) ||
            error("initial state $field=$actual does not match configured value $expected")
    end
    return state.psi, state.theta_over_pi
end

function insert_refinement!(queue::Vector{Float64}, last_theta::Float64, target_theta::Float64)
    midpoint = (last_theta + target_theta) / 2
    pushfirst!(queue, target_theta)
    pushfirst!(queue, midpoint)
    return midpoint
end

function run_flux_scan(settings::ProjectSettings)
    configure_threading!(settings.runtime)
    mkpath(settings.runtime.output_directory)
    psi, initial_theta = load_or_build_initial_state(settings)
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
        println(
            "\nPoint $point_index: branch=$(settings.scan.branch), geometry=$(settings.model.geometry), " *
            "theta/pi=$theta_over_pi, chi=$(settings.optimizer.maxdim)",
        )
        hamiltonian = build_hamiltonian(settings.model, siteinds(psi), theta_over_pi)
        candidate, diagnostic = optimize_candidate(
            hamiltonian,
            psi,
            settings.optimizer;
            output_level=settings.runtime.output_level,
        )
        converged = diagnostic.converged
        path = state_file_path(settings, point_index, theta_over_pi, converged)
        if converged || settings.scan.save_rejected
            saved = write_state_file(
                path,
                settings,
                candidate,
                hamiltonian,
                diagnostic,
                theta_over_pi,
                point_index;
                continuation_accepted=converged || !settings.optimizer.require_converged,
            )
            push!(output_paths, saved.path)
            @printf(
                "Saved %s point: E=%.12f, mean(S)=%.8f, residual=%.4e -> %s\n",
                converged ? "converged" : "rejected",
                saved.observables.energy_density,
                mean(saved.observables.entropy.von_neumann),
                diagnostic.residual,
                saved.path,
            )
        end

        if converged || !settings.optimizer.require_converged
            psi = candidate
            last_accepted_theta = theta_over_pi
            continue
        end

        can_refine = settings.scan.adaptive_bisection && last_accepted_theta !== nothing &&
            abs(theta_over_pi - last_accepted_theta) > settings.scan.minimum_step_over_pi
        interval = last_accepted_theta === nothing ? (NaN, theta_over_pi) :
            (Float64(last_accepted_theta), Float64(theta_over_pi))
        if can_refine && !(interval in attempted)
            push!(attempted, interval)
            midpoint = insert_refinement!(queue, interval[1], interval[2])
            @warn "VUMPS point rejected; bisecting continuation interval" interval midpoint residual=diagnostic.residual
            continue
        end
        error(
            "VUMPS did not converge at theta/pi=$theta_over_pi (residual=$(diagnostic.residual), " *
            "tolerance=$(settings.optimizer.residual_tol)); refusing to continue from an invalid state",
        )
    end
    return output_paths
end

function run_chi_ladder(settings::ProjectSettings, maxdims::AbstractVector{<:Integer})
    isempty(maxdims) && throw(ArgumentError("chi ladder cannot be empty"))
    issorted(maxdims) || throw(ArgumentError("chi ladder must be sorted in increasing order"))
    length(settings.scan.fluxes_over_pi) == 1 ||
        throw(ArgumentError("chi-ladder configuration must contain exactly one flux"))
    configure_threading!(settings.runtime)
    psi, initial_theta = load_or_build_initial_state(settings)
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
        )
        push!(paths, saved.path)
        diagnostic.converged || error(
            "chi ladder stopped at chi=$maxdim with residual=$(diagnostic.residual)",
        )
    end
    return paths
end
