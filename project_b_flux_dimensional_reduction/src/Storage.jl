config_identifier(settings::ProjectSettings) = bytes2hex(sha1(settings.config_text))[1:12]

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
    filename = @sprintf(
        "state_%04d_%s_%s_theta_%s_chi%d_%s_%s.h5",
        point_index,
        branch,
        geometry,
        theta_label(theta_over_pi),
        maxdim,
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

function write_optimizer_diagnostics!(file, diagnostic::VumpsDiagnostics)
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
    return nothing
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
)
    ispath(path) && error("refusing to overwrite immutable artifact: $path")
    observables = local_observables(psi, hamiltonian)
    mps_period = nsites(psi)
    minimum_period = minimal_mps_period(settings.model.geometry)
    atomic_h5write(path) do file
        create_group(file, "geometry")
        create_group(file, "model")
        create_group(file, "optimizer")
        create_group(file, "observables")
        file["schema_version"] = 2
        file["artifact_kind"] = "project_b_vumps_state"
        file["created_at_utc"] = string(now(UTC))
        file["config_id"] = config_identifier(settings)
        file["config_path"] = settings.config_path
        file["config_text"] = settings.config_text
        file["julia_version"] = string(VERSION)
        file["branch"] = settings.scan.branch
        file["point_index"] = Int(point_index)
        file["theta_over_pi"] = Float64(theta_over_pi)
        file["continuation_accepted"] = continuation_accepted
        file["state_present"] = true

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
        file["optimizer/residual_tolerance"] = settings.optimizer.residual_tol
        write_optimizer_diagnostics!(file, diagnostic)

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
    return (; path, observables)
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
        return (;
            psi,
            theta_over_pi=Float64(read(file, "theta_over_pi")),
            branch=String(read(file, "branch")),
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

function summarize_state_files(directory::AbstractString)
    isdir(directory) || return NamedTuple[]
    rows = NamedTuple[]
    for path in sort(filter(p -> endswith(p, ".h5"), readdir(directory; join=true)))
        row = try
            h5open(path, "r") do file
                haskey(file, "artifact_kind") || return nothing
                read(file, "artifact_kind") == "project_b_vumps_state" || return nothing
                return (;
                    path,
                    branch=String(read(file, "branch")),
                    theta_over_pi=Float64(read(file, "theta_over_pi")),
                    maxlinkdim=Int(read(file, "observables/maxlinkdim")),
                    mps_period=haskey(file, "geometry/mps_period") ?
                        Int(read(file, "geometry/mps_period")) : -1,
                    twist_gauge=haskey(file, "model/twist_gauge") ?
                        String(read(file, "model/twist_gauge")) : "seam_legacy",
                    converged=Bool(read(file, "optimizer/converged")),
                    residual=Float64(read(file, "optimizer/residual")),
                    energy_density=Float64(read(file, "observables/energy_density")),
                    mean_entropy=mean(Float64.(read(file, "observables/von_neumann_entropies"))),
                    energy_term_std=Float64(read(file, "observables/energy_term_std")),
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
