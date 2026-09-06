"""
    canonicalize_idmrg_tensors(tensors; tol=1e-12,
                               eigenvalue_imag_tolerance=1e-9)

Convert left-canonical tensors imported from the MPSKit iDMRG bridge into an
`InfiniteCanonicalMPS`. The imported left gauge is checked explicitly and the
right gauge and center tensors are reconstructed from the transfer fixed point.
ITensorInfiniteMPS currently rejects transfer fixed
points whose leading eigenvalue has a positive relative imaginary part above
`1e-15`, even when the imaginary component is ordinary Krylov noise. This
implementation follows its polar canonicalization but:

1. requires the relative imaginary component to remain below the explicit
   `eigenvalue_imag_tolerance`;
2. removes the Arnoldi vector's arbitrary global phase using its full
   Hermitian-partner overlap rather than a potentially tiny matrix pivot;
3. Hermitian-symmetrizes the transfer fixed point before taking its square
   root; and
4. returns the measured numerical corrections for provenance.

The physical MPS tensors are not modified; only their canonical gauge is
constructed.
"""
function canonicalize_idmrg_tensors(
    tensors::AbstractVector{<:ITensor};
    tol::Real=1e-12,
    eigenvalue_imag_tolerance::Real=1e-9,
)
    raw = ITensorInfiniteMPS.InfiniteMPS(collect(tensors))
    rng = Random.Xoshiro(0x50425f49444d5247)
    candidate, diagnostics = _mixed_canonical_tolerant(
        raw;
        tol=Float64(tol),
        eigenvalue_imag_tolerance=Float64(eigenvalue_imag_tolerance),
        rng,
    )
    return candidate, diagnostics
end

function _tensor_indices_for_left_isometry(tensor::ITensor)
    physical = only(filter(index -> hastags(index, "Site"), inds(tensor)))
    links = filter(index -> hastags(index, "Link"), inds(tensor))
    left = only(filter(index -> dir(index) == ITensors.Out, links))
    right = only(filter(index -> dir(index) == ITensors.In, links))
    return left, physical, right
end

function _imported_left_canonical_diagnostics(left, centers, right; tolerance::Real)
    isometry_errors = Float64[]
    center_relation_errors = Float64[]
    for site in 1:nsites(left)
        _, _, right_index = _tensor_indices_for_left_isometry(left[site])
        gram = dag(prime(left[site], right_index)) * left[site]
        gram_indices = inds(gram)
        gram_array = Array(gram, gram_indices...)
        identity_array = Matrix{ComplexF64}(I, size(gram_array)...)
        push!(
            isometry_errors,
            norm(gram_array - identity_array) / norm(identity_array),
        )
        left_center = left[site] * centers[site]
        right_center = centers[site - 1] * right[site]
        push!(
            center_relation_errors,
            norm(left_center - right_center) / max(norm(left_center), eps(Float64)),
        )
    end
    maximum_isometry_error = maximum(isometry_errors)
    maximum_center_relation_error = maximum(center_relation_errors)
    maximum_isometry_error <= tolerance || error(
        "imported iDMRG left-isometry error $maximum_isometry_error exceeds $tolerance",
    )
    maximum_center_relation_error <= tolerance || error(
        "imported iDMRG center-relation error $maximum_center_relation_error exceeds " *
        "$tolerance",
    )
    return (;
        method="validated_imported_mpskit_left_canonical_tensors",
        tolerance=Float64(tolerance),
        isometry_errors,
        center_relation_errors,
        maximum_isometry_error,
        maximum_center_relation_error,
    )
end

function _hermitian_partner(tensor::ITensor)
    return swapinds(dag(tensor), reverse(Pair(inds(tensor)...)))
end

function _hermitian_phase_factor(phase_overlap::Number)
    magnitude = abs(phase_overlap)
    magnitude > eps(Float64) || error(
        "iDMRG transfer fixed point has an unresolved Hermitian phase",
    )
    return sqrt(phase_overlap / magnitude)
end

function _right_orthogonalize_tolerant(
    psi::ITensorInfiniteMPS.InfiniteMPS;
    left_tags=ts"Left",
    right_tags=ts"Right",
    tol::Float64=1e-12,
    eigenvalue_imag_tolerance::Float64=1e-9,
    rng::Random.AbstractRNG,
)
    transfer = ITensorInfiniteMPS.TransferMatrix(psi)
    initial = random_itensor(rng, dag(ITensorInfiniteMPS.input_inds(transfer)))
    # The transfer map is completely positive, so its physical fixed point is
    # Hermitian.  Starting Arnoldi inside that invariant real-linear subspace
    # avoids retaining a slowly decaying anti-Hermitian component when the
    # leading and subleading transfer eigenvalues are close.  This improves
    # the reconstruction accuracy without relaxing the correction guard.
    initial_partner = _hermitian_partner(initial)
    initial = (initial + initial_partner) / 2
    normalize!(initial)
    # Resolve the subleading conjugate pair together with the real Perron
    # fixed point.  Asking Arnoldi for only one Schur value can leave a small
    # anti-Hermitian component even when its eigen-residual has converged.
    transfer_tolerance = min(tol, 1e-13)
    schur, vectors, values, info = KrylovKit.schursolve(
        transfer,
        initial,
        2,
        :LM,
        KrylovKit.Arnoldi(;
            tol=transfer_tolerance,
            eager=true,
            krylovdim=30,
            maxiter=200,
        ),
    )
    info.converged > 0 || error("iDMRG transfer fixed point did not converge")
    size(schur, 2) > 1 && !isapprox(schur[2, 1], 0; atol=transfer_tolerance, rtol=0) &&
        error("iDMRG transfer matrix has a non-unique largest eigenvector")
    length(values) >= 2 || error("iDMRG transfer solve did not resolve a subleading value")
    leading_magnitude_gap = abs(values[1]) - abs(values[2])
    leading_magnitude_gap > 100 * transfer_tolerance ||
        error("iDMRG transfer matrix leading-magnitude gap is unresolved")

    eigenvalue = values[1]
    fixed_point = vectors[1]
    relative_imaginary = abs(imag(eigenvalue)) / max(abs(eigenvalue), eps(Float64))
    relative_imaginary <= eigenvalue_imag_tolerance || error(
        "iDMRG transfer eigenvalue relative imaginary part $relative_imaginary " *
        "exceeds $eigenvalue_imag_tolerance",
    )

    partner = _hermitian_partner(fixed_point)
    fixed_point_norm = norm(fixed_point)
    phase_overlap = dot(fixed_point, partner) / fixed_point_norm^2
    phase_factor = _hermitian_phase_factor(phase_overlap)
    fixed_point .*= phase_factor
    partner = _hermitian_partner(fixed_point)
    hermitian_relative_correction = norm(fixed_point - partner) /
        max(norm(fixed_point), eps(Float64))
    hermitian_relative_correction <= eigenvalue_imag_tolerance || error(
        "iDMRG transfer fixed point Hermitian correction " *
        "$hermitian_relative_correction exceeds $eigenvalue_imag_tolerance",
    )
    fixed_point = (fixed_point + partner) / 2

    center = sqrt(fixed_point)
    center = replacetags(center, left_tags => right_tags; plev=1)
    center = noprime(center, right_tags)
    normalize!(center)
    centers, right, lambda = ITensorInfiniteMPS.right_orthogonalize_polar(
        psi,
        center;
        left_tags,
        right_tags,
    )
    isapprox(lambda, sqrt(real(eigenvalue)); rtol=1e-8, atol=tol) || error(
        "tolerant right canonicalization normalization mismatch",
    )
    diagnostics = (;
        eigenvalue=ComplexF64(eigenvalue),
        subleading_eigenvalue=ComplexF64(values[2]),
        leading_magnitude_gap=Float64(leading_magnitude_gap),
        relative_imaginary=Float64(relative_imaginary),
        hermitian_phase_overlap=ComplexF64(phase_overlap),
        hermitian_phase_factor=ComplexF64(phase_factor),
        hermitian_relative_correction=Float64(hermitian_relative_correction),
    )
    return centers, right, lambda, diagnostics
end

function _left_orthogonalize_tolerant(
    psi::ITensorInfiniteMPS.InfiniteMPS;
    left_tags=ts"Left",
    right_tags=ts"Right",
    tol::Float64=1e-12,
    eigenvalue_imag_tolerance::Float64=1e-9,
    rng::Random.AbstractRNG,
)
    centers, reversed_right, lambda, diagnostics = _right_orthogonalize_tolerant(
        reverse(psi);
        left_tags=right_tags,
        right_tags=left_tags,
        tol,
        eigenvalue_imag_tolerance,
        rng,
    )
    centers = reverse(centers)
    shifted = copy(centers)
    for site in 1:nsites(centers)
        shifted[site] = centers[site + 1]
    end
    return reverse(reversed_right), shifted, lambda, diagnostics
end

function _mixed_canonical_tolerant(
    psi::ITensorInfiniteMPS.InfiniteMPS;
    left_tags=ts"Left",
    right_tags=ts"Right",
    tol::Float64=1e-12,
    eigenvalue_imag_tolerance::Float64=1e-9,
    rng::Random.AbstractRNG,
)
    centers, right, lambda, right_diagnostics = _right_orthogonalize_tolerant(
        psi;
        left_tags=ts"",
        right_tags,
        tol,
        eigenvalue_imag_tolerance,
        rng,
    )
    isapprox(lambda, 1; rtol=1e-8, atol=tol) || error(
        "tolerant mixed canonicalization normalization is $lambda rather than one",
    )
    imported_left_diagnostics = _imported_left_canonical_diagnostics(
        psi,
        centers,
        right;
        tolerance=1e-10,
    )
    return ITensorInfiniteMPS.InfiniteCanonicalMPS(psi, centers, right), (;
        tolerance=tol,
        eigenvalue_imag_tolerance,
        right=right_diagnostics,
        left=imported_left_diagnostics,
        normalization=Float64(lambda),
    )
end
