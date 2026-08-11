Base.@kwdef struct BranchContinuityDiagnostics
    checked::Bool
    passed::Bool
    reason::String
    parent_theta_over_pi::Float64 = NaN
    candidate_theta_over_pi::Float64 = NaN
    mixed_transfer_eigenvalue::ComplexF64 = complex(NaN, NaN)
    raw_overlap_per_unit_cell::Float64 = NaN
    overlap_per_unit_cell::Float64 = NaN
    overlap_per_site::Float64 = NaN
    minimum_overlap_per_site::Float64 = NaN
    krylov_converged::Int = 0
    krylov_residual_norms::Vector{Float64} = Float64[]
    krylov_iterations::Int = 0
    krylov_operations::Int = 0
    energy_density_delta::Float64 = NaN
    mean_entropy_delta::Float64 = NaN
    maximum_cut_entropy_jump::Float64 = NaN
    energy_term_rms_jump::Float64 = NaN
    magnetization_rms_jump::Float64 = NaN
    mean_schmidt_total_variation::Float64 = NaN
end

function skipped_branch_continuity(
    reason::AbstractString;
    passed::Bool,
    parent_theta_over_pi::Real=NaN,
    candidate_theta_over_pi::Real=NaN,
    minimum_overlap_per_site::Real=NaN,
)
    return BranchContinuityDiagnostics(
        checked=false,
        passed=passed,
        reason=String(reason),
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
    common = min(length(left), length(right))
    distance = common == 0 ? 0.0 :
        sum(abs, Float64.(left[1:common]) .- Float64.(right[1:common]))
    common < length(left) && (distance += sum(abs, Float64.(left[(common + 1):end])))
    common < length(right) && (distance += sum(abs, Float64.(right[(common + 1):end])))
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
    passed = parent_overlap_passes(
        overlap_per_site,
        settings.minimum_parent_overlap_per_site,
    )

    parent_entropy = Float64.(parent_observables.entropy.von_neumann)
    candidate_entropy = Float64.(candidate_observables.entropy.von_neumann)
    length(parent_entropy) == length(candidate_entropy) || error(
        "parent and candidate have different numbers of entanglement cuts",
    )
    entropy_jumps = abs.(candidate_entropy .- parent_entropy)
    reason = passed ? "ok" : @sprintf(
        "parent overlap per site %.8g is below the configured minimum %.8g",
        overlap_per_site,
        settings.minimum_parent_overlap_per_site,
    )
    return BranchContinuityDiagnostics(
        checked=true,
        passed=passed,
        reason=reason,
        parent_theta_over_pi=Float64(parent_theta_over_pi),
        candidate_theta_over_pi=Float64(candidate_theta_over_pi),
        mixed_transfer_eigenvalue=lambda,
        raw_overlap_per_unit_cell=raw_overlap_per_unit_cell,
        overlap_per_unit_cell=overlap_per_unit_cell,
        overlap_per_site=overlap_per_site,
        minimum_overlap_per_site=settings.minimum_parent_overlap_per_site,
        krylov_converged=Int(raw.info.converged),
        krylov_residual_norms=krylov_residual_vector(raw.info),
        krylov_iterations=Int(raw.info.numiter),
        krylov_operations=Int(raw.info.numops),
        energy_density_delta=Float64(
            candidate_observables.energy_density - parent_observables.energy_density,
        ),
        mean_entropy_delta=mean(candidate_entropy) - mean(parent_entropy),
        maximum_cut_entropy_jump=isempty(entropy_jumps) ? 0.0 : maximum(entropy_jumps),
        energy_term_rms_jump=rms_jump(
            parent_observables.energy_terms,
            candidate_observables.energy_terms,
        ),
        magnetization_rms_jump=rms_jump(
            parent_observables.magnetization_z,
            candidate_observables.magnetization_z,
        ),
        mean_schmidt_total_variation=mean_schmidt_total_variation(
            parent_observables,
            candidate_observables,
        ),
    )
end
