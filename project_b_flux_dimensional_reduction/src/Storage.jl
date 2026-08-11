config_identifier(settings::ProjectSettings) = bytes2hex(sha1(settings.config_text))[1:12]

function file_sha256(path::AbstractString)
    isfile(path) || error("cannot hash missing file: $path")
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function sanitize_label(value::AbstractString)
    return replace(lowercase(value), r"[^a-z0-9_.-]+" => "_")
end

function theta_label(theta_over_pi::Real)
    sign = theta_over_pi < 0 ? "m" : "p"
    value = replace(@sprintf("%.8f", abs(Float64(theta_over_pi))), "." => "p")
    return sign * value
end

function state_file_path(
    settings::ProjectSettings,
    point_index::Integer,
    theta_over_pi::Real,
    converged::Bool;
    maxdim::Integer=settings.optimizer.maxdim,
)
    status = converged ? "accepted" : "rejected"
    geometry = sanitize_label(string(settings.model.geometry))
    branch = sanitize_label(settings.scan.branch)
    preparation = sanitize_label(settings.scan.preparation)
    direction = sanitize_label(string(settings.scan.direction))
    filename = @sprintf(
        "state_%04d_%s_%s_%s_%s_seed%d_chi%d_theta_%s_%s_%s.h5",
        point_index,
        geometry,
        branch,
        preparation,
        direction,
        settings.scan.random_seed,
        maxdim,
        theta_label(theta_over_pi),
        status,
        config_identifier(settings),
    )
    return joinpath(settings.runtime.output_directory, "states", filename)
end

function atomic_h5write(writer::Function, path::AbstractString)
    mkpath(dirname(path))
    temporary = path * ".tmp"
    ispath(path) && error("refusing to overwrite immutable artifact: $path")
    ispath(temporary) && error("stale temporary artifact exists: $temporary")
    try
        h5open(temporary, "w") do file
            writer(file)
        end
        Base.Filesystem.rename(temporary, path)
    catch
        isfile(temporary) && rm(temporary; force=true)
        rethrow()
    end
    return path
end

function write_bond_table!(file, geometry::YCGeometry, period::Integer)
    bonds = unit_cell_bonds(geometry; period)
    geometry_group = file["geometry"]
    group = create_group(geometry_group, "bonds")
    group["family"] = string.([bond.family for bond in bonds])
    for field in (
        :row,
        :col,
        :drow,
        :dcol,
        :row2,
        :col2,
        :winding,
        :source_site,
        :target_site,
        :cell_shift,
    )
        group[string(field)] = [getfield(bond, field) for bond in bonds]
    end
    group["uniform_twist_charge"] = [bond_twist_charge(bond, geometry, :uniform) for bond in bonds]
    group["seam_twist_charge"] = [bond_twist_charge(bond, geometry, :seam) for bond in bonds]
    return nothing
end

function write_schmidt_probabilities!(file, probabilities)
    observables_group = file["observables"]
    group = create_group(observables_group, "schmidt_probabilities")
    for (cut, values) in enumerate(probabilities)
        group[@sprintf("cut_%04d", cut)] = values
    end
    return nothing
end

function write_optimizer_diagnostics!(
    file,
    diagnostic::VumpsDiagnostics;
    residual_tolerance::Real=diagnostic.residual_tolerance,
)
    file["optimizer/converged"] = diagnostic.converged
    file["optimizer/stop_reason"] = diagnostic.stop_reason
    file["optimizer/iterations"] = diagnostic.iterations
    file["optimizer/residual"] = diagnostic.residual
    file["optimizer/minimum_residual"] = diagnostic.minimum_residual
    file["optimizer/residual_history"] = diagnostic.residual_history
    file["optimizer/energy_left_history"] = diagnostic.energy_left_history
    file["optimizer/energy_right_history"] = diagnostic.energy_right_history
    file["optimizer/growth_dimensions"] = diagnostic.growth_dimensions
    file["optimizer/growth_stage_ends"] = diagnostic.growth_stage_ends
    file["optimizer/residual_tolerance"] = Float64(residual_tolerance)
    file["optimizer/trend_window"] = diagnostic.trend_window
    file["optimizer/recent_relative_improvement"] = diagnostic.recent_relative_improvement
    file["optimizer/log_residual_slope"] = diagnostic.log_residual_slope
    file["optimizer/log_residual_r_squared"] = diagnostic.log_residual_r_squared
    file["optimizer/projected_total_iterations"] = diagnostic.projected_total_iterations
    group = create_group(file["optimizer"], "krylov_solves")
    records = diagnostic.krylov_solves
    group["count"] = length(records)
    if !isempty(records)
        group["outer_iteration"] = [record.outer_iteration for record in records]
        group["solve_kind"] = [record.solve_kind for record in records]
        group["site"] = [record.site for record in records]
        group["requested_tolerance"] = [record.requested_tolerance for record in records]
        group["krylov_dimension"] = [record.krylov_dimension for record in records]
        group["maximum_iterations"] = [record.maximum_iterations for record in records]
        group["converged_count"] = [record.converged_count for record in records]
        group["residual_norm"] = [record.residual_norm for record in records]
        group["iterations"] = [record.iterations for record in records]
        group["operations"] = [record.operations for record in records]
        group["elapsed_seconds"] = [record.elapsed_seconds for record in records]
    end
    return nothing
end

function write_continuity_diagnostics!(file, diagnostic::BranchContinuityDiagnostics)
    file["continuation/continuity_checked"] = diagnostic.checked
    file["continuation/continuity_passed"] = diagnostic.passed
    file["continuation/continuity_reason"] = diagnostic.reason
    file["continuation/parent_theta_over_pi"] = diagnostic.parent_theta_over_pi
    file["continuation/candidate_theta_over_pi"] = diagnostic.candidate_theta_over_pi
    file["continuation/mixed_transfer_eigenvalue"] = diagnostic.mixed_transfer_eigenvalue
    file["continuation/raw_overlap_per_unit_cell"] = diagnostic.raw_overlap_per_unit_cell
    file["continuation/overlap_per_unit_cell"] = diagnostic.overlap_per_unit_cell
    file["continuation/overlap_per_site"] = diagnostic.overlap_per_site
    file["continuation/minimum_overlap_per_site"] = diagnostic.minimum_overlap_per_site
    file["continuation/overlap_krylov_converged"] = diagnostic.krylov_converged
    file["continuation/overlap_krylov_residual_norms"] = diagnostic.krylov_residual_norms
    file["continuation/overlap_krylov_iterations"] = diagnostic.krylov_iterations
    file["continuation/overlap_krylov_operations"] = diagnostic.krylov_operations
    file["continuation/energy_density_delta"] = diagnostic.energy_density_delta
    file["continuation/mean_entropy_delta"] = diagnostic.mean_entropy_delta
    file["continuation/maximum_cut_entropy_jump"] = diagnostic.maximum_cut_entropy_jump
    file["continuation/energy_term_rms_jump"] = diagnostic.energy_term_rms_jump
    file["continuation/magnetization_rms_jump"] = diagnostic.magnetization_rms_jump
    file["continuation/mean_schmidt_total_variation"] =
        diagnostic.mean_schmidt_total_variation
    return nothing
end

function read_schmidt_probabilities(file)
    haskey(file, "observables/schmidt_probabilities") || return Vector{Vector{Float64}}()
    group = file["observables/schmidt_probabilities"]
    names = sort!(String.(collect(keys(group))))
    return [Float64.(read(group, name)) for name in names]
end

function read_stored_observables(file)
    haskey(file, "observables/energy_density") || return nothing
    von_neumann = Float64.(read(file, "observables/von_neumann_entropies"))
    renyi2 = haskey(file, "observables/renyi2_entropies") ?
        Float64.(read(file, "observables/renyi2_entropies")) : fill(NaN, length(von_neumann))
    raw_norms = haskey(file, "observables/schmidt_raw_norms") ?
        Float64.(read(file, "observables/schmidt_raw_norms")) : fill(NaN, length(von_neumann))
    entropy = (;
        von_neumann,
        renyi2,
        raw_norms,
        schmidt_probabilities=read_schmidt_probabilities(file),
    )
    energy_terms = haskey(file, "observables/energy_terms") ?
        Float64.(read(file, "observables/energy_terms")) : Float64[]
    magnetization_z = haskey(file, "observables/magnetization_z") ?
        Float64.(read(file, "observables/magnetization_z")) : Float64[]
    return (;
        energy_density=Float64(read(file, "observables/energy_density")),
        energy_terms,
        energy_term_std=haskey(file, "observables/energy_term_std") ?
            Float64(read(file, "observables/energy_term_std")) : NaN,
        entropy,
        magnetization_z,
        maxlinkdim=Int(read(file, "observables/maxlinkdim")),
    )
end

function write_state_file(
    path::AbstractString,
    settings::ProjectSettings,
    psi,
    hamiltonian,
    diagnostic::VumpsDiagnostics,
    theta_over_pi::Real,
    point_index::Integer;
    continuation_accepted::Bool=diagnostic.converged,
    parent_state_path::AbstractString="",
    parent_state_sha256::AbstractString="",
    parent_flux_history_over_pi::AbstractVector{<:Real}=Float64[],
    continuity::BranchContinuityDiagnostics=skipped_branch_continuity(
        "continuity check not requested";
        passed=true,
    ),
    precomputed_observables=nothing,
)
    ispath(path) && error("refusing to overwrite immutable artifact: $path")
    isempty(parent_state_path) == isempty(parent_state_sha256) || error(
        "parent state path and SHA-256 must either both be set or both be empty",
    )
    all(isfinite, parent_flux_history_over_pi) || error("parent flux history is non-finite")
    flux_history = Float64.(parent_flux_history_over_pi)
    if isempty(flux_history) || !isapprox(last(flux_history), theta_over_pi; atol=1e-12, rtol=0)
        push!(flux_history, Float64(theta_over_pi))
    end
    observables = isnothing(precomputed_observables) ?
        local_observables(psi, hamiltonian) : precomputed_observables
    mps_period = nsites(psi)
    minimum_period = minimal_mps_period(settings.model.geometry)
    atomic_h5write(path) do file
        create_group(file, "geometry")
        create_group(file, "model")
        create_group(file, "optimizer")
        create_group(file, "observables")
        create_group(file, "continuation")
        file["schema_version"] = 5
        file["artifact_kind"] = "project_b_vumps_state"
        file["created_at_utc"] = string(now(UTC))
        file["config_id"] = config_identifier(settings)
        file["config_path"] = settings.config_path
        file["config_text"] = settings.config_text
        file["julia_version"] = string(VERSION)
        file["branch"] = settings.scan.branch
        file["preparation"] = settings.scan.preparation
        file["direction"] = string(settings.scan.direction)
        file["random_seed"] = settings.scan.random_seed
        file["point_index"] = Int(point_index)
        file["theta_over_pi"] = Float64(theta_over_pi)
        file["continuation_accepted"] = continuation_accepted
        file["state_present"] = true

        file["continuation/branch"] = settings.scan.branch
        file["continuation/preparation"] = settings.scan.preparation
        file["continuation/direction"] = string(settings.scan.direction)
        file["continuation/lineage_policy"] = string(settings.scan.lineage_policy)
        file["continuation/seed_pattern"] = settings.scan.seed_pattern
        file["continuation/random_seed"] = settings.scan.random_seed
        file["continuation/preparation_source"] = isempty(parent_state_path) ?
            "independent_product_state" : "checkpoint_continuation"
        file["continuation/parent_state_path"] = String(parent_state_path)
        file["continuation/parent_state_basename"] =
            isempty(parent_state_path) ? "" : basename(parent_state_path)
        file["continuation/parent_state_sha256"] = String(parent_state_sha256)
        file["continuation/parent_flux_history_over_pi"] =
            Float64.(parent_flux_history_over_pi)
        file["continuation/flux_history_over_pi"] = flux_history
        write_continuity_diagnostics!(file, continuity)

        geometry = settings.model.geometry
        file["geometry/circumference"] = geometry.circumference
        file["geometry/shift"] = geometry.shift
        file["geometry/mps_period"] = mps_period
        file["geometry/minimal_mps_period"] = minimum_period
        file["geometry/unit_cell_is_minimal"] = mps_period == minimum_period
        file["geometry/site_rows"] = [lattice_coordinates(site, geometry).row for site in 1:mps_period]
        file["geometry/site_cols"] = [lattice_coordinates(site, geometry).col for site in 1:mps_period]
        file["geometry/class"] = string(cylinder_class(geometry))
        file["geometry/predicted_crossing_over_pi"] = predicted_crossing_over_pi(geometry)
        file["geometry/expected_gapless_flavors"] = expected_gapless_flavors(geometry)
        write_bond_table!(file, geometry, mps_period)

        file["model/J1"] = settings.model.J1
        file["model/J2"] = settings.model.J2
        file["model/Delta1"] = settings.model.Delta1
        file["model/Delta2"] = settings.model.Delta2
        file["model/Bz"] = settings.model.Bz
        file["model/twist_gauge"] = string(settings.model.twist_gauge)

        file["optimizer/requested_maxdim"] = settings.optimizer.maxdim
        file["optimizer/cutoff"] = settings.optimizer.cutoff
        file["optimizer/solver_tol_scale"] = settings.optimizer.solver_tol_scale
        file["optimizer/solver_tol_floor"] = settings.optimizer.solver_tol_floor
        file["optimizer/solver_krylov_dimension"] =
            settings.optimizer.solver_krylov_dimension
        file["optimizer/solver_max_iterations"] = settings.optimizer.solver_max_iterations
        file["optimizer/record_krylov_diagnostics"] =
            settings.optimizer.record_krylov_diagnostics
        file["optimizer/plateau_detection"] = settings.optimizer.plateau_detection
        file["optimizer/plateau_warmup_iterations"] =
            settings.optimizer.plateau_warmup_iterations
        file["optimizer/plateau_patience"] = settings.optimizer.plateau_patience
        file["optimizer/plateau_min_relative_improvement"] =
            settings.optimizer.plateau_min_relative_improvement
        write_optimizer_diagnostics!(
            file,
            diagnostic;
            residual_tolerance=settings.optimizer.residual_tol,
        )

        file["observables/energy_density"] = observables.energy_density
        file["observables/energy_terms"] = observables.energy_terms
        file["observables/energy_term_std"] = observables.energy_term_std
        file["observables/von_neumann_entropies"] = observables.entropy.von_neumann
        file["observables/renyi2_entropies"] = observables.entropy.renyi2
        file["observables/schmidt_raw_norms"] = observables.entropy.raw_norms
        file["observables/magnetization_z"] = observables.magnetization_z
        file["observables/maxlinkdim"] = observables.maxlinkdim
        write_schmidt_probabilities!(file, observables.entropy.schmidt_probabilities)

        file["psi"] = psi
    end
    return (; path, state_sha256=file_sha256(path), observables, flux_history_over_pi=flux_history)
end

function read_state_file(path::AbstractString)
    isfile(path) || error("state file does not exist: $path")
    return h5open(path, "r") do file
        haskey(file, "psi") || error("state file has no psi dataset: $path")
        artifact_kind = haskey(file, "artifact_kind") ? read(file, "artifact_kind") : ""
        artifact_kind == "project_b_vumps_state" ||
            @warn "Reading a state with an unexpected artifact kind" path artifact_kind
        psi = read(file, "psi", InfiniteCanonicalMPS)
        circumference = Int(read(file, "geometry/circumference"))
        shift = Int(read(file, "geometry/shift"))
        geometry = YCGeometry(circumference, shift)
        mps_period = haskey(file, "geometry/mps_period") ?
            Int(read(file, "geometry/mps_period")) : nsites(psi)
        minimum_period = haskey(file, "geometry/minimal_mps_period") ?
            Int(read(file, "geometry/minimal_mps_period")) : minimal_mps_period(geometry)
        twist_gauge = haskey(file, "model/twist_gauge") ?
            Symbol(String(read(file, "model/twist_gauge"))) : :seam
        branch = String(read(file, "branch"))
        preparation = haskey(file, "preparation") ?
            String(read(file, "preparation")) : "legacy_unspecified"
        direction = haskey(file, "direction") ?
            Symbol(String(read(file, "direction"))) : :unknown
        random_seed = haskey(file, "random_seed") ?
            Int(read(file, "random_seed")) : -1
        seed_pattern = haskey(file, "continuation/seed_pattern") ?
            String(read(file, "continuation/seed_pattern")) : "legacy_unspecified"
        flux_history = haskey(file, "continuation/flux_history_over_pi") ?
            Float64.(read(file, "continuation/flux_history_over_pi")) :
            [Float64(read(file, "theta_over_pi"))]
        observables = read_stored_observables(file)
        return (;
            psi,
            schema_version=haskey(file, "schema_version") ? Int(read(file, "schema_version")) : 1,
            theta_over_pi=Float64(read(file, "theta_over_pi")),
            branch,
            preparation,
            direction,
            random_seed,
            seed_pattern,
            parent_state_path=haskey(file, "continuation/parent_state_path") ?
                String(read(file, "continuation/parent_state_path")) : "",
            parent_state_sha256=haskey(file, "continuation/parent_state_sha256") ?
                String(read(file, "continuation/parent_state_sha256")) : "",
            flux_history_over_pi=flux_history,
            observables,
            circumference,
            shift,
            mps_period,
            minimum_mps_period=minimum_period,
            unit_cell_is_minimal=mps_period == minimum_period,
            twist_gauge,
            maxlinkdim=Int(read(file, "observables/maxlinkdim")),
            converged=Bool(read(file, "optimizer/converged")),
            continuation_accepted=Bool(read(file, "continuation_accepted")),
            J1=Float64(read(file, "model/J1")),
            J2=Float64(read(file, "model/J2")),
            Delta1=Float64(read(file, "model/Delta1")),
            Delta2=Float64(read(file, "model/Delta2")),
            Bz=Float64(read(file, "model/Bz")),
        )
    end
end

function spectrum_sector_name(physical_sz::Real)
    text = replace(@sprintf("%.8g", physical_sz), "-" => "m", "." => "p", "+" => "")
    return "sz_" * text
end

function spectrum_file_path(state_path::AbstractString, output_directory::AbstractString)
    stem = splitext(basename(state_path))[1]
    return joinpath(output_directory, "spectra", "spectrum_" * stem * ".h5")
end

function write_spectrum_group!(group, result)
    group["physical_sz"] = result.physical_sz
    group["raw_qn_sz"] = result.raw_qn_sz
    group["reference_lambda"] = result.reference_lambda
    group["lambdas"] = result.lambdas
    group["normalized_lambdas"] = result.normalized_lambdas
    group["inverse_xi"] = result.inverse_xi
    group["xi"] = result.xi
    group["k_parallel"] = result.k_parallel
    group["pure_transfer_phase"] = result.pure_transfer_phase
    group["canonical_k1"] = result.canonical_k1
    group["k1"] = result.k1
    group["k1_secondary"] = result.k1_secondary
    group["two_k1"] = result.two_k1
    group["k2"] = result.k2
    group["momentum_weight_coverage"] = result.momentum_weight_coverage
    group["momentum_coherence"] = result.momentum_coherence
    # HDF5 cannot write Julia's packed BitVector directly.
    group["momentum_resolved"] = UInt8.(result.momentum_resolved)
    group["flux_labels"] = result.flux_labels
    group["krylov_converged"] = result.krylov_converged
    group["krylov_residual_norms"] = result.krylov_residual_norms
    group["krylov_iterations"] = result.krylov_iterations
    group["krylov_operations"] = result.krylov_operations
    return nothing
end

function postprocess_state_spectrum(
    state_path::AbstractString,
    settings::ProjectSettings;
    output_directory::AbstractString=settings.runtime.output_directory,
)
    state = read_state_file(state_path)
    state.converged || error("refusing spectroscopy on unconverged state: $state_path")
    state.continuation_accepted ||
        error("refusing spectroscopy on a state rejected for continuation: $state_path")
    state.circumference == settings.model.geometry.circumference ||
        error("state circumference does not match spectroscopy configuration")
    state.shift == settings.model.geometry.shift ||
        error("state YC shift does not match spectroscopy configuration")
    expected_period = model_mps_period(settings.model)
    state.mps_period == expected_period || error(
        "state MPS period $(state.mps_period) does not match the configured paper-compatible period " *
        "$expected_period; regenerate the state instead of unfolding a supercell spectrum",
    )
    state.twist_gauge == settings.model.twist_gauge || error(
        "state twist gauge $(state.twist_gauge) does not match configured gauge " *
        "$(settings.model.twist_gauge)",
    )
    output_path = spectrum_file_path(state_path, output_directory)
    ispath(output_path) && error("refusing to overwrite immutable artifact: $output_path")
    spectrum_settings = settings.spectrum
    neutral_raw = transfer_eigensolve(
        state.psi,
        0;
        neigs=spectrum_settings.neigs,
        tolerance=spectrum_settings.tolerance,
        krylov_dimension=spectrum_settings.krylov_dimension,
        random_seed=spectrum_settings.random_seed,
    )
    reference_lambda = first(neutral_raw.eigenvalues)
    theta = pi * state.theta_over_pi
    momentum_context = prepare_momentum_context(
        state.psi,
        settings.model.geometry,
        theta,
        state.twist_gauge;
        tolerance=spectrum_settings.tolerance,
        krylov_dimension=spectrum_settings.krylov_dimension,
        random_seed=spectrum_settings.random_seed + 10_000,
        reference_lambda,
    )
    results = Dict{Float64,Any}()
    for physical_sz in spectrum_settings.physical_sz_sectors
        raw_qn_sz = physical_sz_to_qn(physical_sz)
        raw = raw_qn_sz == 0 ? neutral_raw : transfer_eigensolve(
            state.psi,
            raw_qn_sz;
            neigs=spectrum_settings.neigs,
            tolerance=spectrum_settings.tolerance,
            krylov_dimension=spectrum_settings.krylov_dimension,
            random_seed=spectrum_settings.random_seed + abs(raw_qn_sz),
        )
        normalized = normalized_spectrum(raw, reference_lambda)
        momenta = momentum_labels(
            raw,
            normalized,
            momentum_context,
            settings.model.geometry,
            theta,
        )
        results[physical_sz] = (;
            physical_sz,
            raw_qn_sz,
            reference_lambda=ComplexF64(reference_lambda),
            normalized...,
            momenta...,
        )
    end

    atomic_h5write(output_path) do file
        create_group(file, "geometry")
        create_group(file, "model")
        create_group(file, "momentum")
        sectors_group = create_group(file, "sectors")
        file["schema_version"] = 2
        file["artifact_kind"] = "project_b_transfer_spectrum"
        file["created_at_utc"] = string(now(UTC))
        file["config_id"] = config_identifier(settings)
        file["config_path"] = settings.config_path
        file["source_state_path"] = abspath(state_path)
        file["source_state_basename"] = basename(state_path)
        file["theta_over_pi"] = state.theta_over_pi
        file["branch"] = state.branch
        file["preparation"] = state.preparation
        file["direction"] = string(state.direction)
        file["random_seed"] = state.random_seed
        file["geometry/circumference"] = state.circumference
        file["geometry/shift"] = state.shift
        file["geometry/mps_period"] = state.mps_period
        file["geometry/minimal_mps_period"] = state.minimum_mps_period
        file["geometry/unit_cell_is_minimal"] = state.unit_cell_is_minimal
        file["model/J1"] = state.J1
        file["model/J2"] = state.J2
        file["model/Delta1"] = state.Delta1
        file["model/Delta2"] = state.Delta2
        file["model/Bz"] = state.Bz
        file["model/twist_gauge"] = string(state.twist_gauge)
        file["maxlinkdim"] = state.maxlinkdim
        file["momentum_convention"] =
            "Hu supplement: YC-0 mixed T[a1] plus (k1+theta/Ly,k2); " *
            "YC-1 two-site pure T with 2k1=k+2theta/Ly and k2=kLy/2"
        file["momentum/strategy"] = momentum_context.strategy
        file["momentum/analysis_available"] = momentum_context.available
        file["momentum/reason"] = momentum_context.reason
        file["momentum/source_twist_gauge"] = string(momentum_context.source_gauge)
        file["momentum/mixed_translation_raw_qn"] = momentum_context.mixed_raw_qn
        file["momentum/mixed_translation_lambda"] = momentum_context.mixed_lambda
        file["momentum/translation_fidelity"] = momentum_context.translation_fidelity
        file["momentum/schmidt_diagonal_weight"] = momentum_context.schmidt_diagonal_weight
        file["momentum/schmidt_translation_phases"] = momentum_context.schmidt_phases
        file["momentum/translation_fidelity_threshold"] = TRANSLATION_FIDELITY_THRESHOLD
        file["momentum/schmidt_diagonal_weight_threshold"] = SCHMIDT_DIAGONAL_WEIGHT_THRESHOLD
        file["momentum/mode_coverage_threshold"] = MODE_MOMENTUM_COVERAGE_THRESHOLD
        file["momentum/mode_coherence_threshold"] = MODE_MOMENTUM_COHERENCE_THRESHOLD
        for physical_sz in sort!(collect(keys(results)))
            group = create_group(sectors_group, spectrum_sector_name(physical_sz))
            write_spectrum_group!(group, results[physical_sz])
        end
        all_resolved = all(
            result -> all(result.momentum_resolved),
            values(results),
        )
        file["transverse_momentum_resolved"] = momentum_context.available && all_resolved
    end
    return output_path
end

function summarize_state_files(directory::AbstractString; include_hashes::Bool=false)
    isdir(directory) || return NamedTuple[]
    rows = NamedTuple[]
    for path in sort(filter(p -> endswith(p, ".h5"), readdir(directory; join=true)))
        row = try
            h5open(path, "r") do file
                haskey(file, "artifact_kind") || return nothing
                read(file, "artifact_kind") == "project_b_vumps_state" || return nothing
                circumference = Int(read(file, "geometry/circumference"))
                shift = Int(read(file, "geometry/shift"))
                return (;
                    path,
                    geometry=string(YCGeometry(circumference, shift)),
                    circumference,
                    shift,
                    branch=String(read(file, "branch")),
                    preparation=haskey(file, "preparation") ?
                        String(read(file, "preparation")) : "legacy_unspecified",
                    direction=haskey(file, "direction") ?
                        String(read(file, "direction")) : "unknown",
                    random_seed=haskey(file, "random_seed") ?
                        Int(read(file, "random_seed")) : -1,
                    theta_over_pi=Float64(read(file, "theta_over_pi")),
                    maxlinkdim=Int(read(file, "observables/maxlinkdim")),
                    mps_period=haskey(file, "geometry/mps_period") ?
                        Int(read(file, "geometry/mps_period")) : -1,
                    twist_gauge=haskey(file, "model/twist_gauge") ?
                        String(read(file, "model/twist_gauge")) : "seam_legacy",
                    converged=Bool(read(file, "optimizer/converged")),
                    continuation_accepted=Bool(read(file, "continuation_accepted")),
                    residual=Float64(read(file, "optimizer/residual")),
                    energy_density=Float64(read(file, "observables/energy_density")),
                    mean_entropy=mean(Float64.(read(file, "observables/von_neumann_entropies"))),
                    energy_term_std=Float64(read(file, "observables/energy_term_std")),
                    parent_state_path=haskey(file, "continuation/parent_state_path") ?
                        String(read(file, "continuation/parent_state_path")) : "",
                    parent_state_sha256=haskey(file, "continuation/parent_state_sha256") ?
                        String(read(file, "continuation/parent_state_sha256")) : "",
                    continuity_checked=haskey(file, "continuation/continuity_checked") ?
                        Bool(read(file, "continuation/continuity_checked")) : false,
                    continuity_passed=haskey(file, "continuation/continuity_passed") ?
                        Bool(read(file, "continuation/continuity_passed")) : true,
                    parent_overlap_per_site=haskey(file, "continuation/overlap_per_site") ?
                        Float64(read(file, "continuation/overlap_per_site")) : NaN,
                    flux_history_over_pi=haskey(file, "continuation/flux_history_over_pi") ?
                        Float64.(read(file, "continuation/flux_history_over_pi")) :
                        [Float64(read(file, "theta_over_pi"))],
                    state_sha256=include_hashes ? file_sha256(path) : "",
                )
            end
        catch err
            @warn "Skipping unreadable state file" path exception=(err, catch_backtrace())
            nothing
        end
        row !== nothing && push!(rows, row)
    end
    return rows
end
