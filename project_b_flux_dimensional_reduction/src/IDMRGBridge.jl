"""
    canonicalize_idmrg_tensors(tensors; tol=1e-12,
                               eigenvalue_imag_tolerance=1e-9)

Convert left-canonical tensors imported from the MPSKit iDMRG bridge into an
`InfiniteCanonicalMPS`. ITensorInfiniteMPS currently rejects transfer fixed
points whose leading eigenvalue has a positive relative imaginary part above
`1e-15`, even when the imaginary component is ordinary Krylov noise. This
implementation follows its polar canonicalization but:

1. requires the relative imaginary component to remain below the explicit
   `eigenvalue_imag_tolerance`;
2. Hermitian-symmetrizes the transfer fixed point before taking its square
   root; and
3. returns the measured numerical corrections for provenance.

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

function _hermitian_partner(tensor::ITensor)
    return swapinds(dag(tensor), reverse(Pair(inds(tensor)...)))
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
    schur, vectors, values, info = KrylovKit.schursolve(
        transfer,
        initial,
        1,
        :LM,
        KrylovKit.Arnoldi(; tol, eager=true),
    )
    info.converged > 0 || error("iDMRG transfer fixed point did not converge")
    size(schur, 2) > 1 && schur[2, 1] != 0 &&
        error("iDMRG transfer matrix has a non-unique largest eigenvector")

    eigenvalue = values[1]
    fixed_point = vectors[1]
    relative_imaginary = abs(imag(eigenvalue)) / max(abs(eigenvalue), eps(Float64))
    relative_imaginary <= eigenvalue_imag_tolerance || error(
        "iDMRG transfer eigenvalue relative imaginary part $relative_imaginary " *
        "exceeds $eigenvalue_imag_tolerance",
    )

    pivot = fixed_point[1, 1]
    iszero(pivot) || (fixed_point .*= conj(sign(pivot)))
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
        relative_imaginary=Float64(relative_imaginary),
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
    _, right, _, right_diagnostics = _right_orthogonalize_tolerant(
        psi;
        left_tags=ts"",
        right_tags,
        tol,
        eigenvalue_imag_tolerance,
        rng,
    )
    left, centers, lambda, left_diagnostics = _left_orthogonalize_tolerant(
        right;
        left_tags,
        right_tags,
        tol,
        eigenvalue_imag_tolerance,
        rng,
    )
    isapprox(lambda, 1; rtol=1e-8, atol=tol) || error(
        "tolerant mixed canonicalization normalization is $lambda rather than one",
    )
    return ITensorInfiniteMPS.InfiniteCanonicalMPS(left, centers, right), (;
        tolerance=tol,
        eigenvalue_imag_tolerance,
        right=right_diagnostics,
        left=left_diagnostics,
    )
end
