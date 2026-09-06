Base.@kwdef struct BranchContinuityDiagnostics
    checked::Bool
    passed::Bool
    reason::String
    policy::String = "overlap_floor"
    fixed_flux_bond_growth::Bool = false
    parent_theta_over_pi::Float64 = NaN
    candidate_theta_over_pi::Float64 = NaN
    mixed_transfer_eigenvalue::ComplexF64 = complex(NaN, NaN)
    raw_overlap_per_unit_cell::Float64 = NaN
    overlap_per_unit_cell::Float64 = NaN
    overlap_per_site::Float64 = NaN
    minimum_overlap_per_site::Float64 = NaN
    overlap_alarm_triggered::Bool = false
    krylov_converged::Int = 0
    krylov_residual_norms::Vector{Float64} = Float64[]
    krylov_iterations::Int = 0
    krylov_operations::Int = 0
    energy_density_delta::Float64 = NaN
    mean_entropy_delta::Float64 = NaN
    maximum_cut_entropy_jump::Float64 = NaN
    maximum_cut_entropy_jump_threshold::Float64 = NaN
    entropy_gate_passed::Bool = false
    energy_term_rms_jump::Float64 = NaN
    maximum_energy_term_rms_jump::Float64 = NaN
    energy_term_gate_passed::Bool = false
    magnetization_rms_jump::Float64 = NaN
    maximum_magnetization_rms_jump::Float64 = NaN
    magnetization_gate_passed::Bool = false
    mean_schmidt_total_variation::Float64 = NaN
    maximum_mean_schmidt_total_variation::Float64 = NaN
    schmidt_gate_passed::Bool = false
    correlation_length_diagnostics_required::Bool = false
    correlation_length_diagnostics_passed::Bool = false
    correlation_length_reason::String = "not requested"
    correlation_length_physical_sz_sectors::Vector{Float64} = Float64[]
    parent_correlation_lengths::Vector{Float64} = Float64[]
    candidate_correlation_lengths::Vector{Float64} = Float64[]
    maximum_log_correlation_length_jump::Float64 = NaN
    maximum_log_correlation_length_jump_threshold::Float64 = NaN
    correlation_length_gate_passed::Bool = false
    correlation_length_krylov_converged::Int = 0
    correlation_length_krylov_residual_norms::Vector{Float64} = Float64[]
    u1_sector_diagnostics_required::Bool = false
    u1_sector_diagnostics_passed::Bool = false
    u1_sector_labels_preserved::Bool = false
    u1_sector_multiplicities_preserved::Bool = false
end

function skipped_branch_continuity(
    reason::AbstractString;
    passed::Bool,
    parent_theta_over_pi::Real=NaN,
    candidate_theta_over_pi::Real=NaN,
    minimum_overlap_per_site::Real=NaN,
    policy::AbstractString="overlap_floor",
)
    return BranchContinuityDiagnostics(
        checked=false,
        passed=passed,
        reason=String(reason),
        policy=String(policy),
        parent_theta_over_pi=Float64(parent_theta_over_pi),
        candidate_theta_over_pi=Float64(candidate_theta_over_pi),
        minimum_overlap_per_site=Float64(minimum_overlap_per_site),
    )
end

function failed_branch_continuity(
    reason::AbstractString,
    parent_theta_over_pi::Real,
    candidate_theta_over_pi::Real,
    minimum_overlap_per_site::Real,
)
    return BranchContinuityDiagnostics(
        checked=true,
        passed=false,
        reason=String(reason),
        parent_theta_over_pi=Float64(parent_theta_over_pi),
        candidate_theta_over_pi=Float64(candidate_theta_over_pi),
        minimum_overlap_per_site=Float64(minimum_overlap_per_site),
    )
end

parent_overlap_passes(overlap_per_site::Real, minimum_overlap_per_site::Real) =
    isfinite(overlap_per_site) && overlap_per_site >= minimum_overlap_per_site

"""
Mixed transfer map between two infinite canonical MPS unit cells.

The dominant eigenvalue magnitude is the thermodynamic overlap per unit cell.
Priming every bra link makes the result independent of the two MPS link-index
identities. Physical indices are aligned explicitly so immutable/reloaded parent
artifacts can be compared with their optimized children.
"""
function mixed_state_transfer_matrix(parent, candidate)
    period = nsites(parent)
    nsites(candidate) == period || throw(DimensionMismatch(
        "parent and candidate MPS periods differ: $period and $(nsites(candidate))",
    ))
    ket_tensors = ITensor[candidate.AL[site] for site in 1:period]
    bra_tensors = ITensor[]
    sizehint!(bra_tensors, period)
    for site in 1:period
        tensor = parent.AL[site]
        parent_physical = siteind(parent.AL, site)
        candidate_physical = siteind(candidate.AL, site)
        parent_physical == candidate_physical ||
            (tensor = replaceinds(tensor, parent_physical => candidate_physical))
        push!(bra_tensors, dag(prime(tensor, "Link")))
    end
    return ITensorMap(MPS(ket_tensors), MPS(bra_tensors))
end

function rms_jump(left::AbstractVector{<:Real}, right::AbstractVector{<:Real})
    length(left) == length(right) || return Inf
    isempty(left) && return 0.0
    return sqrt(sum(abs2, Float64.(right) .- Float64.(left)) / length(left))
end

function distribution_total_variation(
    left::AbstractVector{<:Real},
    right::AbstractVector{<:Real},
)
    # Schmidt values have no stable position across a symmetry-sector bond
    # expansion: increasing a block multiplicity can shift every later entry
    # in the serialized vector without changing the physical ordering of the
    # spectrum. Compare the unlabeled distributions by descending Schmidt
    # rank, padding the shorter spectrum with zero weight.
    left_ranked = sort(Float64.(left); rev=true)
    right_ranked = sort(Float64.(right); rev=true)
    common = min(length(left_ranked), length(right_ranked))
    distance = common == 0 ? 0.0 :
        sum(abs, left_ranked[1:common] .- right_ranked[1:common])
    common < length(left_ranked) &&
        (distance += sum(abs, left_ranked[(common + 1):end]))
    common < length(right_ranked) &&
        (distance += sum(abs, right_ranked[(common + 1):end]))
    return distance / 2
end

function mean_schmidt_total_variation(parent_observables, candidate_observables)
    parent = parent_observables.entropy.schmidt_probabilities
    candidate = candidate_observables.entropy.schmidt_probabilities
    length(parent) == length(candidate) || return Inf
    isempty(parent) && return 0.0
    distances = map(distribution_total_variation, parent, candidate)
    return mean(distances)
end

function krylov_residual_vector(info)
    return info.normres isa Number ? [Float64(info.normres)] : Float64.(info.normres)
end

function correlation_length_fingerprint(
    psi,
    physical_sz_sectors::AbstractVector{<:Real};
    tolerance::Real,
    krylov_dimension::Integer,
    random_seed::Integer,
)
    sectors = Float64.(physical_sz_sectors)
    lengths = fill(NaN, length(sectors))
    residuals = Float64[]
    converged = 0
    try
        neutral = transfer_eigensolve(
            psi,
            0;
            neigs=2,
            tolerance,
            krylov_dimension=max(Int(krylov_dimension), 6),
            random_seed,
        )
        reference_lambda = first(neutral.eigenvalues)
        solve_passed = neutral.info.converged >= 2 && length(neutral.eigenvalues) >= 2
        converged += Int(neutral.info.converged)
        append!(residuals, krylov_residual_vector(neutral.info))
        for (index, physical_sz) in pairs(sectors)
            raw_qn_sz = physical_sz_to_qn(physical_sz)
            raw = if iszero(raw_qn_sz)
                neutral
            else
                transfer_eigensolve(
                    psi,
                    raw_qn_sz;
                    neigs=1,
                    tolerance,
                    krylov_dimension=max(Int(krylov_dimension), 4),
                    random_seed=random_seed + index,
                )
            end
            if !iszero(raw_qn_sz)
                converged += Int(raw.info.converged)
                append!(residuals, krylov_residual_vector(raw.info))
                solve_passed &= raw.info.converged >= 1 && !isempty(raw.eigenvalues)
            end
            normalized = normalized_spectrum(raw, reference_lambda)
            finite_positive = filter(value -> isfinite(value) && value > 0, normalized.xi)
            if isempty(finite_positive)
                solve_passed = false
            else
                lengths[index] = maximum(finite_positive)
            end
        end
        solve_passed &= all(value -> isfinite(value) && value > 0, lengths)
        return (;
            passed=solve_passed,
            reason=solve_passed ? "ok" : "incomplete_correlation_length_eigensolve",
            physical_sz_sectors=sectors,
            correlation_lengths=lengths,
            krylov_converged=converged,
            krylov_residual_norms=residuals,
        )
    catch exception
        return (;
            passed=false,
            reason="correlation_length_eigensolve_failed: " * sprint(showerror, exception),
            physical_sz_sectors=sectors,
            correlation_lengths=lengths,
            krylov_converged=converged,
            krylov_residual_norms=residuals,
        )
    end
end

function branch_continuity_diagnostics(
    parent,
    candidate,
    parent_observables,
    candidate_observables,
    parent_theta_over_pi::Real,
    candidate_theta_over_pi::Real,
    settings::ScanSettings;
    random_seed::Integer=settings.random_seed,
)
    transfer = mixed_state_transfer_matrix(parent, candidate)
    raw = transfer_map_eigensolve(
        transfer,
        0;
        neigs=1,
        tolerance=settings.parent_overlap_tolerance,
        krylov_dimension=settings.parent_overlap_krylov_dimension,
        random_seed,
    )
    lambda = ComplexF64(first(raw.eigenvalues))
    raw_overlap_per_unit_cell = abs(lambda)
    isfinite(raw_overlap_per_unit_cell) || error(
        "mixed parent-candidate transfer eigenvalue is non-finite: $lambda",
    )
    raw_overlap_per_unit_cell <= 1 + 1e-5 || error(
        "mixed parent-candidate overlap exceeds one by more than canonicalization noise: " *
        "$raw_overlap_per_unit_cell",
    )
    overlap_per_unit_cell = clamp(raw_overlap_per_unit_cell, 0.0, 1.0)
    overlap_per_site = overlap_per_unit_cell^(1 / nsites(candidate))
    overlap_floor_passed = parent_overlap_passes(
        overlap_per_site,
        settings.minimum_parent_overlap_per_site,
    )

    parent_entropy = Float64.(parent_observables.entropy.von_neumann)
    candidate_entropy = Float64.(candidate_observables.entropy.von_neumann)
    length(parent_entropy) == length(candidate_entropy) || error(
        "parent and candidate have different numbers of entanglement cuts",
    )
    entropy_jumps = abs.(candidate_entropy .- parent_entropy)
    maximum_cut_entropy_jump = isempty(entropy_jumps) ? 0.0 : maximum(entropy_jumps)
    energy_term_rms_jump = rms_jump(
        parent_observables.energy_terms,
        candidate_observables.energy_terms,
    )
    magnetization_rms_jump = rms_jump(
        parent_observables.magnetization_z,
        candidate_observables.magnetization_z,
    )
    schmidt_total_variation = mean_schmidt_total_variation(
        parent_observables,
        candidate_observables,
    )
    fixed_flux_bond_growth = isapprox(
        Float64(parent_theta_over_pi),
        Float64(candidate_theta_over_pi);
        atol=1e-12,
        rtol=0,
    ) && parent_observables.maxlinkdim != candidate_observables.maxlinkdim
    entropy_threshold = fixed_flux_bond_growth ?
        settings.fixed_flux_growth_maximum_cut_entropy_jump :
        settings.maximum_cut_entropy_jump
    schmidt_threshold = fixed_flux_bond_growth ?
        settings.fixed_flux_growth_maximum_mean_schmidt_total_variation :
        settings.maximum_mean_schmidt_total_variation
    correlation_length_threshold = fixed_flux_bond_growth ?
        settings.fixed_flux_growth_maximum_log_correlation_length_jump :
        settings.maximum_log_correlation_length_jump
    entropy_gate_passed = isfinite(maximum_cut_entropy_jump) &&
        maximum_cut_entropy_jump <= entropy_threshold
    energy_term_gate_passed = isfinite(energy_term_rms_jump) &&
        energy_term_rms_jump <= settings.maximum_energy_term_rms_jump
    magnetization_gate_passed = isfinite(magnetization_rms_jump) &&
        magnetization_rms_jump <= settings.maximum_magnetization_rms_jump
    schmidt_gate_passed = isfinite(schmidt_total_variation) &&
        schmidt_total_variation <= schmidt_threshold

    correlation_sectors = settings.correlation_length_physical_sz_sectors
    parent_correlation = (;
        passed=false,
        reason="not requested",
        physical_sz_sectors=copy(correlation_sectors),
        correlation_lengths=fill(NaN, length(correlation_sectors)),
        krylov_converged=0,
        krylov_residual_norms=Float64[],
    )
    candidate_correlation = parent_correlation
    maximum_log_correlation_length_jump = NaN
    correlation_length_diagnostics_passed = false
    correlation_length_reason = "not requested"
    if settings.require_correlation_length_diagnostics
        parent_correlation = correlation_length_fingerprint(
            parent,
            correlation_sectors;
            tolerance=settings.correlation_length_tolerance,
            krylov_dimension=settings.correlation_length_krylov_dimension,
            random_seed=random_seed + 10_000,
        )
        candidate_correlation = correlation_length_fingerprint(
            candidate,
            correlation_sectors;
            tolerance=settings.correlation_length_tolerance,
            krylov_dimension=settings.correlation_length_krylov_dimension,
            random_seed=random_seed + 20_000,
        )
        correlation_length_diagnostics_passed =
            parent_correlation.passed && candidate_correlation.passed
        if correlation_length_diagnostics_passed
            maximum_log_correlation_length_jump = maximum(abs.(log.(
                candidate_correlation.correlation_lengths ./
                    parent_correlation.correlation_lengths,
            )))
            correlation_length_reason = "ok"
        else
            correlation_length_reason = join(
                filter(!=("ok"), [parent_correlation.reason, candidate_correlation.reason]),
                "; ",
            )
        end
    end
    correlation_length_gate_passed = !settings.require_correlation_length_diagnostics ||
        (correlation_length_diagnostics_passed &&
         isfinite(maximum_log_correlation_length_jump) &&
         maximum_log_correlation_length_jump <= correlation_length_threshold)

    sector_rows = compare_bond_sectors(parent, candidate)
    u1_sector_diagnostics_passed = !isempty(sector_rows) && all(
        row -> row.before_multiplicity >= 0 && row.after_multiplicity >= 0 &&
            isfinite(row.before_schmidt_weight) && isfinite(row.after_schmidt_weight),
        sector_rows,
    )
    u1_sector_labels_preserved = u1_sector_diagnostics_passed && all(
        row -> (row.before_multiplicity == 0) == (row.after_multiplicity == 0),
        sector_rows,
    )
    u1_sector_multiplicities_preserved = u1_sector_diagnostics_passed && all(
        row -> row.before_multiplicity == row.after_multiplicity,
        sector_rows,
    )
    sector_gate_passed = !settings.require_u1_sector_diagnostics ||
        u1_sector_diagnostics_passed

    passed = if settings.continuity_policy === :overlap_floor
        overlap_floor_passed
    elseif settings.continuity_policy === :multimetric_trust_region
        entropy_gate_passed && energy_term_gate_passed && magnetization_gate_passed &&
            schmidt_gate_passed && correlation_length_gate_passed && sector_gate_passed
    else
        error("unsupported continuity policy: $(settings.continuity_policy)")
    end
    failures = String[]
    settings.continuity_policy === :overlap_floor && !overlap_floor_passed && push!(
        failures,
        "overlap_floor",
    )
    if settings.continuity_policy === :multimetric_trust_region
        entropy_gate_passed || push!(failures, "cut_entropy_jump")
        energy_term_gate_passed || push!(failures, "local_energy_pattern")
        magnetization_gate_passed || push!(failures, "local_magnetization")
        schmidt_gate_passed || push!(failures, "schmidt_distribution")
        correlation_length_gate_passed || push!(failures, "correlation_length")
        sector_gate_passed || push!(failures, "u1_sector_diagnostics")
    end
    overlap_alarm = !overlap_floor_passed
    reason = if passed
        overlap_alarm ? "passed_multimetric_gates_with_overlap_alarm" : "ok"
    else
        "failed_" * join(failures, "+")
    end
    return BranchContinuityDiagnostics(
        checked=true,
        passed=passed,
        reason=reason,
        policy=String(settings.continuity_policy),
        fixed_flux_bond_growth=fixed_flux_bond_growth,
        parent_theta_over_pi=Float64(parent_theta_over_pi),
        candidate_theta_over_pi=Float64(candidate_theta_over_pi),
        mixed_transfer_eigenvalue=lambda,
        raw_overlap_per_unit_cell=raw_overlap_per_unit_cell,
        overlap_per_unit_cell=overlap_per_unit_cell,
        overlap_per_site=overlap_per_site,
        minimum_overlap_per_site=settings.minimum_parent_overlap_per_site,
        overlap_alarm_triggered=overlap_alarm,
        krylov_converged=Int(raw.info.converged),
        krylov_residual_norms=krylov_residual_vector(raw.info),
        krylov_iterations=Int(raw.info.numiter),
        krylov_operations=Int(raw.info.numops),
        energy_density_delta=Float64(
            candidate_observables.energy_density - parent_observables.energy_density,
        ),
        mean_entropy_delta=mean(candidate_entropy) - mean(parent_entropy),
        maximum_cut_entropy_jump=maximum_cut_entropy_jump,
        maximum_cut_entropy_jump_threshold=entropy_threshold,
        entropy_gate_passed=entropy_gate_passed,
        energy_term_rms_jump=energy_term_rms_jump,
        maximum_energy_term_rms_jump=settings.maximum_energy_term_rms_jump,
        energy_term_gate_passed=energy_term_gate_passed,
        magnetization_rms_jump=magnetization_rms_jump,
        maximum_magnetization_rms_jump=settings.maximum_magnetization_rms_jump,
        magnetization_gate_passed=magnetization_gate_passed,
        mean_schmidt_total_variation=schmidt_total_variation,
        maximum_mean_schmidt_total_variation=schmidt_threshold,
        schmidt_gate_passed=schmidt_gate_passed,
        correlation_length_diagnostics_required=
            settings.require_correlation_length_diagnostics,
        correlation_length_diagnostics_passed=correlation_length_diagnostics_passed,
        correlation_length_reason=correlation_length_reason,
        correlation_length_physical_sz_sectors=copy(correlation_sectors),
        parent_correlation_lengths=parent_correlation.correlation_lengths,
        candidate_correlation_lengths=candidate_correlation.correlation_lengths,
        maximum_log_correlation_length_jump=maximum_log_correlation_length_jump,
        maximum_log_correlation_length_jump_threshold=correlation_length_threshold,
        correlation_length_gate_passed=correlation_length_gate_passed,
        correlation_length_krylov_converged=
            parent_correlation.krylov_converged + candidate_correlation.krylov_converged,
        correlation_length_krylov_residual_norms=vcat(
            parent_correlation.krylov_residual_norms,
            candidate_correlation.krylov_residual_norms,
        ),
        u1_sector_diagnostics_required=settings.require_u1_sector_diagnostics,
        u1_sector_diagnostics_passed=u1_sector_diagnostics_passed,
        u1_sector_labels_preserved=u1_sector_labels_preserved,
        u1_sector_multiplicities_preserved=u1_sector_multiplicities_preserved,
    )
end
