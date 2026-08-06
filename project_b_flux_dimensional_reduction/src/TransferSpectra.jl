const TRANSLATION_FIDELITY_THRESHOLD = 0.999
const SCHMIDT_DIAGONAL_WEIGHT_THRESHOLD = 0.90
const MODE_MOMENTUM_COVERAGE_THRESHOLD = 0.90
const MODE_MOMENTUM_COHERENCE_THRESHOLD = 0.90

wrap_momentum(value::Real) = mod(Float64(value) + pi, 2pi) - pi

function physical_sz_to_qn(physical_sz::Real)
    doubled = 2 * Float64(physical_sz)
    isapprox(doubled, round(doubled); atol=1e-12, rtol=0) ||
        throw(ArgumentError("physical Sz=$physical_sz does not map to an integer ITensor QN"))
    return Int(round(doubled))
end

function transfer_map_eigensolve(
    transfer_matrix,
    raw_qn_sz::Integer;
    neigs::Integer,
    tolerance::Real,
    krylov_dimension::Integer,
    random_seed::Integer,
)
    Random.seed!(random_seed)
    initial_vector = random_itensor(QN("Sz", Int(raw_qn_sz)), dag(input_inds(transfer_matrix)))
    algorithm = Arnoldi(
        ;
        krylovdim=max(Int(krylov_dimension), Int(neigs) + 2),
        tol=Float64(tolerance),
    )
    eigenvalues, eigenvectors, info = eigsolve(
        transfer_matrix,
        initial_vector,
        Int(neigs),
        :LM,
        algorithm,
    )
    info.converged >= 1 || error(
        "transfer eigensolve produced no converged eigenvalues in raw Sz sector $raw_qn_sz",
    )
    labels = [
        try
            string(flux(vector))
        catch
            ""
        end for vector in eigenvectors
    ]
    return (; eigenvalues, eigenvectors, labels, info)
end

function transfer_eigensolve(
    psi,
    raw_qn_sz::Integer;
    neigs::Integer,
    tolerance::Real,
    krylov_dimension::Integer,
    random_seed::Integer,
)
    return transfer_map_eigensolve(
        TransferMatrix(psi.AL),
        raw_qn_sz;
        neigs,
        tolerance,
        krylov_dimension,
        random_seed,
    )
end

function normalized_spectrum(raw, reference_lambda)
    isfinite(real(reference_lambda)) && isfinite(imag(reference_lambda)) && abs(reference_lambda) > 0 ||
        error("invalid neutral reference eigenvalue $reference_lambda")
    normalized = raw.eigenvalues ./ reference_lambda
    inverse_xi = -log.(abs.(normalized))
    xi = [iszero(value) ? Inf : inv(value) for value in inverse_xi]
    k_parallel = angle.(normalized)
    normres = raw.info.normres isa Number ? [Float64(raw.info.normres)] : Float64.(raw.info.normres)
    return (;
        lambdas=ComplexF64.(raw.eigenvalues),
        normalized_lambdas=ComplexF64.(normalized),
        inverse_xi=Float64.(inverse_xi),
        xi=Float64.(xi),
        k_parallel=Float64.(k_parallel),
        flux_labels=String.(raw.labels),
        krylov_converged=Int(raw.info.converged),
        krylov_residual_norms=normres,
        krylov_iterations=Int(raw.info.numiter),
        krylov_operations=Int(raw.info.numops),
    )
end

function gauge_rotated_left_tensor(
    psi,
    site::Integer,
    geometry::YCGeometry,
    theta::Real,
    source_gauge::Symbol,
)
    tensor = psi.AL[Int(site)]
    source_gauge === :uniform && return tensor
    source_gauge === :seam || throw(ArgumentError("unknown source twist gauge $source_gauge"))
    period = nsites(psi)
    period % geometry.circumference == 0 || error(
        "a seam-gauge state needs a ring-sized MPS cell before it can be transformed to uniform gauge",
    )
    coordinates = lattice_coordinates(site, geometry)
    physical_index = siteind(psi.AL, Int(site))
    rotation = op(
        "Rz",
        physical_index;
        θ=Float64(theta) * coordinates.row / geometry.circumference,
    )
    rotated = rotation * tensor
    return replaceinds(rotated, prime(physical_index) => physical_index)
end

"""
Mixed transfer matrix between an MPS and its one-site a1 translation.

The translation convention matches Hu et al. Fig. S2(d):
`A1 A2 ... ALy -> A2 A3 ... ALy A1`. Seam-gauge tensors are first rotated
to the uniform gauge, making the finite-flux translation explicitly covariant.
"""
function mixed_translation_transfer_matrix(
    psi,
    geometry::YCGeometry,
    theta::Real;
    source_gauge::Symbol=:uniform,
)
    geometry.shift == 0 || throw(
        ArgumentError("the mixed one-site transfer matrix is the YC(Ly)-0 construction"),
    )
    period = nsites(psi)
    period == geometry.circumference || error(
        "YC(Ly)-0 momentum resolution requires the minimal Ly-site MPS cell; got period $period",
    )
    ket_tensors = ITensor[
        gauge_rotated_left_tensor(psi, site, geometry, theta, source_gauge) for site in 1:period
    ]
    translated_tensors = ITensor[]
    sizehint!(translated_tensors, period)
    for site in 1:period
        source = site + 1
        tensor = gauge_rotated_left_tensor(psi, source, geometry, theta, source_gauge)
        source_physical = siteind(psi.AL, source)
        target_physical = siteind(psi.AL, site)
        push!(translated_tensors, replaceinds(tensor, source_physical => target_physical))
    end
    ket = MPS(ket_tensors)
    # Prime every link, including the open boundaries. `prime(linkinds, MPS)`
    # only sees internal finite-MPS links and would accidentally contract a
    # translated boundary with an internal ket bond.
    translated_bra = MPS([dag(prime(tensor, "Link")) for tensor in translated_tensors])
    return ITensorMap(ket, translated_bra)
end

function virtual_matrix(tensor)
    tensor_indices = collect(inds(tensor))
    unprimed = filter(index -> plev(index) == 0, tensor_indices)
    primed = filter(index -> plev(index) == 1, tensor_indices)
    length(unprimed) == 1 && length(primed) == 1 || error(
        "expected one unprimed and one primed virtual index, got $(tensor_indices)",
    )
    matrix = Array(tensor, only(unprimed), only(primed))
    return (; matrix, unprimed=only(unprimed), primed=only(primed))
end

function schmidt_translation_signature(fixed_point)
    representation = virtual_matrix(fixed_point)
    rows, columns = size(representation.matrix)
    rows == columns || return (;
        phases=ComplexF64[],
        valid=Bool[],
        diagonal_weight=0.0,
        reason="translated and original Schmidt spaces have different dimensions",
    )
    diagonal = diag(representation.matrix)
    total_weight = sum(abs2, representation.matrix)
    diagonal_weight = iszero(total_weight) ? 0.0 : sum(abs2, diagonal) / total_weight
    scale = isempty(diagonal) ? 0.0 : maximum(abs, diagonal)
    threshold = max(eps(Float64), sqrt(eps(Float64)) * scale)
    valid = abs.(diagonal) .> threshold
    phases = ComplexF64[
        valid[index] ? diagonal[index] / abs(diagonal[index]) : complex(NaN, NaN) for
        index in eachindex(diagonal)
    ]
    reason = diagonal_weight >= SCHMIDT_DIAGONAL_WEIGHT_THRESHOLD ? "ok" :
        "mixed fixed point is not sufficiently diagonal in the stored Schmidt basis"
    return (; phases, valid, diagonal_weight, reason)
end

function mode_transverse_phase(eigenvector, signature)
    isempty(signature.phases) && return (;
        canonical_k1=NaN,
        coverage=0.0,
        coherence=0.0,
        resolved=false,
    )
    matrix = virtual_matrix(eigenvector).matrix
    size(matrix, 1) == length(signature.phases) && size(matrix, 2) == length(signature.phases) ||
        return (; canonical_k1=NaN, coverage=0.0, coherence=0.0, resolved=false)
    total_weight = sum(abs2, matrix)
    iszero(total_weight) && return (;
        canonical_k1=NaN,
        coverage=0.0,
        coherence=0.0,
        resolved=false,
    )
    covered_weight = 0.0
    phase_sum = 0.0 + 0.0im
    for column in axes(matrix, 2), row in axes(matrix, 1)
        signature.valid[row] && signature.valid[column] || continue
        weight = abs2(matrix[row, column])
        covered_weight += weight
        phase_sum += weight * signature.phases[row] * conj(signature.phases[column])
    end
    coverage = covered_weight / total_weight
    coherence = iszero(covered_weight) ? 0.0 : abs(phase_sum) / covered_weight
    resolved = coverage >= MODE_MOMENTUM_COVERAGE_THRESHOLD &&
        coherence >= MODE_MOMENTUM_COHERENCE_THRESHOLD && !iszero(phase_sum)
    return (;
        canonical_k1=resolved ? wrap_momentum(angle(phase_sum)) : NaN,
        coverage,
        coherence,
        resolved,
    )
end

"""Map a minimal-cell transfer phase to the Hu `(k1, k2)` convention."""
function momentum_from_minimal_phase(
    geometry::YCGeometry,
    transfer_phase::Real,
    theta::Real;
    canonical_k1=nothing,
)
    k = wrap_momentum(transfer_phase)
    Ly = geometry.circumference
    if geometry.shift == 0
        canonical_k1 === nothing && return (;
            k1=NaN,
            k1_secondary=NaN,
            two_k1=NaN,
            k2=k,
            ambiguity="k1 requires the mixed one-site transfer matrix",
        )
        k1 = wrap_momentum(Float64(canonical_k1) + Float64(theta) / Ly)
        return (;
            k1,
            k1_secondary=NaN,
            two_k1=wrap_momentum(2k1),
            k2=k,
            ambiguity="none",
        )
    elseif geometry.shift == 1
        two_k1 = wrap_momentum(k + 2 * Float64(theta) / Ly)
        k1 = wrap_momentum(k / 2 + Float64(theta) / Ly)
        return (;
            k1,
            k1_secondary=wrap_momentum(k1 + pi),
            two_k1,
            k2=wrap_momentum(k * Ly / 2),
            ambiguity="k1 is defined modulo pi",
        )
    end
    return (;
        k1=NaN,
        k1_secondary=NaN,
        two_k1=NaN,
        k2=k,
        ambiguity="momentum mapping is implemented only for YC(Ly)-0 and YC(Ly)-1",
    )
end

function prepare_momentum_context(
    psi,
    geometry::YCGeometry,
    theta::Real,
    source_gauge::Symbol;
    tolerance::Real,
    krylov_dimension::Integer,
    random_seed::Integer,
    reference_lambda,
)
    actual_period = nsites(psi)
    minimum_period = minimal_mps_period(geometry)
    if geometry.shift == 1
        available = actual_period == 2 && (source_gauge === :uniform || iszero(theta))
        reason = available ? "ok" :
            "YC(Ly)-1 requires a two-site cell in uniform gauge for Eq. (4)"
        return (;
            strategy="yc1_two_site_pure",
            available,
            reason,
            actual_period,
            minimum_period,
            source_gauge,
            mixed_raw_qn=0,
            mixed_lambda=complex(NaN, NaN),
            translation_fidelity=available ? 1.0 : 0.0,
            schmidt_diagonal_weight=NaN,
            schmidt_phases=Float64[],
            signature=nothing,
        )
    elseif geometry.shift != 0 || actual_period != geometry.circumference || isodd(geometry.circumference)
        return (;
            strategy="unsupported_geometry_or_supercell",
            available=false,
            reason="full momentum mapping currently requires even YC(Ly)-0/Ly-site or YC(Ly)-1/two-site cells",
            actual_period,
            minimum_period,
            source_gauge,
            mixed_raw_qn=0,
            mixed_lambda=complex(NaN, NaN),
            translation_fidelity=0.0,
            schmidt_diagonal_weight=NaN,
            schmidt_phases=Float64[],
            signature=nothing,
        )
    end

    mixed_map = mixed_translation_transfer_matrix(
        psi,
        geometry,
        theta;
        source_gauge,
    )
    # Translating the spin-1/2 snake by one site changes the virtual doubled-Sz
    # background by -1 in the Fig. S2(d) convention. The mixed fixed point
    # therefore lives in QN("Sz",-1), not the neutral pure-TM sector.
    mixed_raw_qn = -1
    mixed = transfer_map_eigensolve(
        mixed_map,
        mixed_raw_qn;
        neigs=1,
        tolerance,
        krylov_dimension=max(Int(krylov_dimension), 4),
        random_seed,
    )
    mixed_lambda = ComplexF64(first(mixed.eigenvalues))
    translation_fidelity = abs(mixed_lambda / reference_lambda)
    signature = schmidt_translation_signature(first(mixed.eigenvectors))
    available = translation_fidelity >= TRANSLATION_FIDELITY_THRESHOLD &&
        signature.diagonal_weight >= SCHMIDT_DIAGONAL_WEIGHT_THRESHOLD
    reason = if translation_fidelity < TRANSLATION_FIDELITY_THRESHOLD
        "state is not invariant enough under one-site circumference translation"
    elseif signature.diagonal_weight < SCHMIDT_DIAGONAL_WEIGHT_THRESHOLD
        signature.reason
    else
        "ok"
    end
    return (;
        strategy="yc0_mixed_one_site",
        available,
        reason,
        actual_period,
        minimum_period,
        source_gauge,
        mixed_raw_qn,
        mixed_lambda,
        translation_fidelity,
        schmidt_diagonal_weight=signature.diagonal_weight,
        schmidt_phases=Float64[isfinite(real(value)) ? angle(value) : NaN for value in signature.phases],
        signature,
    )
end

function momentum_labels(raw, normalized, context, geometry::YCGeometry, theta::Real)
    count = length(normalized.k_parallel)
    k1 = fill(NaN, count)
    k1_secondary = fill(NaN, count)
    two_k1 = fill(NaN, count)
    k2 = copy(normalized.k_parallel)
    canonical_k1 = fill(NaN, count)
    coverage = zeros(Float64, count)
    coherence = zeros(Float64, count)
    resolved = falses(count)

    if context.strategy == "yc1_two_site_pure" && context.available
        for index in 1:count
            mapped = momentum_from_minimal_phase(geometry, normalized.k_parallel[index], theta)
            k1[index] = mapped.k1
            k1_secondary[index] = mapped.k1_secondary
            two_k1[index] = mapped.two_k1
            k2[index] = mapped.k2
            canonical_k1[index] = wrap_momentum(normalized.k_parallel[index] / 2)
            coverage[index] = 1.0
            coherence[index] = 1.0
            resolved[index] = true
        end
    elseif context.strategy == "yc0_mixed_one_site" && context.available
        for index in 1:count
            mode = mode_transverse_phase(raw.eigenvectors[index], context.signature)
            canonical_k1[index] = mode.canonical_k1
            coverage[index] = mode.coverage
            coherence[index] = mode.coherence
            resolved[index] = mode.resolved
            mode.resolved || continue
            mapped = momentum_from_minimal_phase(
                geometry,
                normalized.k_parallel[index],
                theta;
                canonical_k1=mode.canonical_k1,
            )
            k1[index] = mapped.k1
            two_k1[index] = mapped.two_k1
            k2[index] = mapped.k2
        end
    end
    return (;
        pure_transfer_phase=copy(normalized.k_parallel),
        canonical_k1,
        k1,
        k1_secondary,
        two_k1,
        k2,
        momentum_weight_coverage=coverage,
        momentum_coherence=coherence,
        momentum_resolved=resolved,
    )
end

function compute_transfer_spectrum(
    psi;
    physical_sz::Real,
    reference_lambda=nothing,
    neigs::Integer=16,
    tolerance::Real=1e-10,
    krylov_dimension::Integer=max(2 * neigs, neigs + 8),
    random_seed::Integer=1,
)
    raw_qn_sz = physical_sz_to_qn(physical_sz)
    if reference_lambda === nothing
        neutral = transfer_eigensolve(
            psi,
            0;
            neigs=max(neigs, 1),
            tolerance,
            krylov_dimension,
            random_seed,
        )
        reference_lambda = first(neutral.eigenvalues)
        raw = raw_qn_sz == 0 ? neutral : transfer_eigensolve(
            psi,
            raw_qn_sz;
            neigs,
            tolerance,
            krylov_dimension,
            random_seed=random_seed + raw_qn_sz,
        )
    else
        raw = transfer_eigensolve(
            psi,
            raw_qn_sz;
            neigs,
            tolerance,
            krylov_dimension,
            random_seed=random_seed + raw_qn_sz,
        )
    end
    spectrum = normalized_spectrum(raw, reference_lambda)
    return (;
        physical_sz=Float64(physical_sz),
        raw_qn_sz,
        reference_lambda=ComplexF64(reference_lambda),
        spectrum...,
    )
end
