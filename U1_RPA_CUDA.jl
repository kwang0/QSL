"""
U(1) RPA Calculation with CUDA Acceleration
Port of Python code to Julia 1.12 with GPU support

Usage:
    julia U1_RPA_CUDA.jl
    
Or in REPL:
    include("U1_RPA_CUDA.jl")
    main()
"""

using CUDA
using LinearAlgebra
using Statistics
using PyPlot

# Enable scalar indexing warnings (helps catch performance issues)
CUDA.allowscalar(false)

# ----------------------------
# PI-FLUX MEAN-FIELD H(k): SI Eq. (3)-(4)
# ----------------------------

"""
    M_k(k1, k2) -> Matrix{ComplexF64}

2x2 sublattice matrix M_k from SI Eq. (4).
"""
function M_k(k1::T, k2::T) where T<:Real
    M_AA = 2.0 * cos(k2)
    M_BB = -M_AA
    M_AB = 1.0 + exp(-1im * k1) + exp(1im * (k2 - k1)) - exp(-1im * k2)
    return [M_AA M_AB; conj(M_AB) M_BB]
end

"""
    precompute_bands(Nk, t) -> (kvals, eps, vec)

Diagonalize the spinless 2x2 problem on a uniform grid k1,k2 in [-π, π).
Returns:
  - kvals: 1D array of grid values (length Nk)
  - eps:   (Nk, Nk, 2) eigenvalues
  - vec:   (Nk, Nk, 2, 2) eigenvectors (band index, sublattice component)
"""
function precompute_bands(Nk::Int, t::Real)
    kvals = range(-π, π, length=Nk+1)[1:Nk] |> collect
    eps = zeros(Float64, Nk, Nk, 2)
    vec = zeros(ComplexF64, Nk, Nk, 2, 2)
    
    for (i, k1) in enumerate(kvals)
        for (j, k2) in enumerate(kvals)
            H2 = t * M_k(k1, k2)
            F = eigen(Hermitian(H2))
            eps[i, j, :] = F.values
            vec[i, j, :, :] = transpose(F.vectors)  # rows are eigenvectors
        end
    end
    
    return kvals, eps, vec
end

# ----------------------------
# J_q MATRIX: SI Eq. (27)-(28)
# ----------------------------

"""
    J_matrix(q1, q2, J1, J2) -> Matrix{ComplexF64}

Compute the J_q interaction matrix.
"""
function J_matrix(q1::Real, q2::Real, J1::Real, J2::Real)
    J_AA = 2 * J1 * cos(q2) + 2 * J2 * cos(q1 - q2)
    J_AB = (J1 * (1 + exp(-1im * q1) + exp(1im * (q2 - q1)) + exp(-1im * q2))
          + J2 * (exp(1im * q2) + exp(1im * (2q2 - q1)) + exp(-1im * (q1 + q2)) + exp(-2im * q2)))
    return [J_AA J_AB; conj(J_AB) J_AA]
end

# ----------------------------
# Physical contraction vector R_q: SI Eq. (17)-(18)
# ----------------------------

"""
    R_vec(q1) -> Vector{ComplexF64}
"""
function R_vec(q1::Real)
    return ComplexF64[1.0, exp(-1im * q1 / 2.0)]
end

# ----------------------------
# Grid / snapping utilities
# ----------------------------

"""
    wrap_to_pi(x) -> Float64

Wrap angle to [-π, π).
"""
function wrap_to_pi(x::Real)
    return mod(x + π, 2π) - π
end

"""
    shift_from_q(q, Nk) -> Int

Convert a real q in [-π,π) into an integer shift s such that q ≈ s * dk.
"""
function shift_from_q(q::Real, Nk::Int)
    dk = 2π / Nk
    qw = wrap_to_pi(q)
    s = round(Int, qw / dk)
    
    # wrap s into [-Nk/2, Nk/2)
    s = mod(s, Nk)
    if s >= Nk ÷ 2
        s -= Nk
    end
    return s
end

"""
    q_from_shift(s, Nk) -> Float64
"""
function q_from_shift(s::Int, Nk::Int)
    dk = 2π / Nk
    return s * dk
end

# ----------------------------
# Fermi occupation (T=0 default)
# ----------------------------

"""
    fermi_occ(eps; mu=0.0, T=0.0) -> Array

Fermi-Dirac occupation function.
"""
function fermi_occ(eps::AbstractArray; mu::Real=0.0, T::Real=0.0)
    if T <= 0.0
        return Float64.(eps .< mu)
    end
    x = clamp.((eps .- mu) ./ T, -60.0, 60.0)
    return 1.0 ./ (exp.(x) .+ 1.0)
end

# GPU version
function fermi_occ_gpu(eps::CuArray; mu::Real=0.0, T::Real=0.0)
    if T <= 0.0
        return Float64.(eps .< mu)
    end
    x = clamp.((eps .- mu) ./ T, -60.0, 60.0)
    return 1.0 ./ (exp.(x) .+ 1.0)
end

# ----------------------------
# GPU-accelerated Bubble chi0^{XY}(q,ω): SI Eq. (23)-(24)
#
# CRITICAL FIX: Julia uses column-major order, Python uses row-major.
# In column-major, linear index k corresponds to (i,j) where:
#   k = i + (j-1)*Nk  (1-indexed)
# So the first index (i) changes fastest.
# ----------------------------

"""
    bubble_chi0_matrix_shift_gpu(s1, s2, omegas, eps_gpu, vec_gpu, Nk; eta=0.03, T=0.0, mu=0.0)

Compute χ₀(ω) on GPU: returns (Nw, 2, 2) in sublattice basis (A,B).
"""
function bubble_chi0_matrix_shift_gpu(s1::Int, s2::Int, omegas::AbstractVector,
                                       eps_gpu::CuArray, vec_gpu::CuArray, Nk::Int;
                                       eta::Real=0.03, T::Real=0.0, mu::Real=0.0)
    Ktot = Nk * Nk
    nb = 2
    Nw = length(omegas)
    
    # Reshape to (K, nb) - column-major order
    eps_k = reshape(eps_gpu, Ktot, nb)
    vec_k = reshape(vec_gpu, Ktot, nb, nb)
    
    # COLUMN-MAJOR indexing:
    # Linear index k = i + (j-1)*Nk, so i changes fastest
    # ii cycles fast: [1,2,3,...,Nk,1,2,3,...,Nk,...]
    # jj cycles slow: [1,1,1,...,2,2,2,...,Nk,Nk,Nk,...]
    ii = repeat(1:Nk, outer=Nk) |> CuArray  # fast-changing (first index)
    jj = repeat(1:Nk, inner=Nk) |> CuArray  # slow-changing (second index)
    
    # Apply shifts with wrapping (1-indexed)
    ii_q = mod1.(ii .+ s1, Nk)
    jj_q = mod1.(jj .+ s2, Nk)
    
    # Column-major linear index formula
    lin_q = ii_q .+ (jj_q .- 1) .* Nk
    
    # Gather eps and vec at k+q
    eps_kq = eps_k[lin_q, :]
    vec_kq = vec_k[lin_q, :, :]
    
    # Compute matrix elements U_X^{mn}(k,q) = <m,k| P_X |n,k+q>
    # For diagonal projectors:
    # P_A selects sublattice 1: U_A[k,m,n] = conj(vec_k[k,m,1]) * vec_kq[k,n,1]
    # P_B selects sublattice 2: U_B[k,m,n] = conj(vec_k[k,m,2]) * vec_kq[k,n,2]
    
    vec_k_conj = conj.(vec_k)
    
    # vec_k_conj[:, :, 1] has shape (Ktot, nb) = (Ktot, 2)
    # We need U_A[k, m, n] = vec_k_conj[k, m, 1] * vec_kq[k, n, 1]
    # Reshape to broadcast correctly:
    # vec_k_conj[:, :, 1] -> (Ktot, nb, 1) for m dimension
    # vec_kq[:, :, 1] -> (Ktot, 1, nb) for n dimension
    
    U_A = reshape(vec_k_conj[:, :, 1], Ktot, nb, 1) .* reshape(vec_kq[:, :, 1], Ktot, 1, nb)
    U_B = reshape(vec_k_conj[:, :, 2], Ktot, nb, 1) .* reshape(vec_kq[:, :, 2], Ktot, 1, nb)
    
    # Fermi occupations
    n_k = fermi_occ_gpu(eps_k; mu=mu, T=T)
    n_kq = fermi_occ_gpu(eps_kq; mu=mu, T=T)
    
    # Energy differences: dE[k,m,n] = eps_k[k,m] - eps_kq[k,n]
    dE = reshape(eps_k, Ktot, nb, 1) .- reshape(eps_kq, Ktot, 1, nb)
    
    # Occupation differences: dn[k,m,n] = n_k[k,m] - n_kq[k,n]
    dn = reshape(n_k, Ktot, nb, 1) .- reshape(n_kq, Ktot, 1, nb)
    
    # Weight matrices
    W_AA = dn .* U_A .* conj.(U_A)
    W_AB = dn .* U_A .* conj.(U_B)
    W_BA = dn .* U_B .* conj.(U_A)
    W_BB = dn .* U_B .* conj.(U_B)
    
    # Prefactor (spin factor 2 folded in)
    pref = -1.0 / (2.0 * Ktot)
    
    # Compute chi0 for all omegas
    chi0_w = zeros(ComplexF64, Nw, 2, 2)
    
    for iw in 1:Nw
        w = omegas[iw]
        denom = w .+ dE .+ 1im * eta
        
        chi0_w[iw, 1, 1] = pref * sum(W_AA ./ denom)
        chi0_w[iw, 1, 2] = pref * sum(W_AB ./ denom)
        chi0_w[iw, 2, 1] = pref * sum(W_BA ./ denom)
        chi0_w[iw, 2, 2] = pref * sum(W_BB ./ denom)
    end
    
    return chi0_w
end

"""
    bubble_chi0_matrix_shift_gpu_batched(s1, s2, omegas, eps_gpu, vec_gpu, Nk; ...)

Fully batched GPU version - computes all omegas simultaneously.
Uses more memory but faster for large Nw.
"""
function bubble_chi0_matrix_shift_gpu_batched(s1::Int, s2::Int, omegas::AbstractVector,
                                               eps_gpu::CuArray, vec_gpu::CuArray, Nk::Int;
                                               eta::Real=0.03, T::Real=0.0, mu::Real=0.0)
    Ktot = Nk * Nk
    nb = 2
    Nw = length(omegas)
    
    # Reshape to (K, nb) - column-major order
    eps_k = reshape(eps_gpu, Ktot, nb)
    vec_k = reshape(vec_gpu, Ktot, nb, nb)
    
    # Column-major indexing
    ii = repeat(1:Nk, outer=Nk) |> CuArray
    jj = repeat(1:Nk, inner=Nk) |> CuArray
    ii_q = mod1.(ii .+ s1, Nk)
    jj_q = mod1.(jj .+ s2, Nk)
    lin_q = ii_q .+ (jj_q .- 1) .* Nk
    
    eps_kq = eps_k[lin_q, :]
    vec_kq = vec_k[lin_q, :, :]
    
    vec_k_conj = conj.(vec_k)
    U_A = reshape(vec_k_conj[:, :, 1], Ktot, nb, 1) .* reshape(vec_kq[:, :, 1], Ktot, 1, nb)
    U_B = reshape(vec_k_conj[:, :, 2], Ktot, nb, 1) .* reshape(vec_kq[:, :, 2], Ktot, 1, nb)
    
    n_k = fermi_occ_gpu(eps_k; mu=mu, T=T)
    n_kq = fermi_occ_gpu(eps_kq; mu=mu, T=T)
    
    dE = reshape(eps_k, Ktot, nb, 1) .- reshape(eps_kq, Ktot, 1, nb)
    dn = reshape(n_k, Ktot, nb, 1) .- reshape(n_kq, Ktot, 1, nb)
    
    W_AA = dn .* U_A .* conj.(U_A)
    W_AB = dn .* U_A .* conj.(U_B)
    W_BA = dn .* U_B .* conj.(U_A)
    W_BB = dn .* U_B .* conj.(U_B)
    
    pref = -1.0 / (2.0 * Ktot)
    
    # Broadcast over all omegas at once
    omegas_gpu = CuArray(ComplexF64.(omegas))
    
    # Expand dimensions: (Nw, 1, 1, 1) with (1, K, 2, 2)
    dE_4d = reshape(dE, 1, Ktot, nb, nb)
    W_AA_4d = reshape(W_AA, 1, Ktot, nb, nb)
    W_AB_4d = reshape(W_AB, 1, Ktot, nb, nb)
    W_BA_4d = reshape(W_BA, 1, Ktot, nb, nb)
    W_BB_4d = reshape(W_BB, 1, Ktot, nb, nb)
    omegas_4d = reshape(omegas_gpu, Nw, 1, 1, 1)
    
    # Compute denominators for all (omega, k, m, n) combinations
    denom = omegas_4d .+ dE_4d .+ 1im * eta  # (Nw, K, 2, 2)
    
    # Sum over k, m, n dimensions
    chi0_AA = pref .* dropdims(sum(W_AA_4d ./ denom, dims=(2, 3, 4)), dims=(2, 3, 4))
    chi0_AB = pref .* dropdims(sum(W_AB_4d ./ denom, dims=(2, 3, 4)), dims=(2, 3, 4))
    chi0_BA = pref .* dropdims(sum(W_BA_4d ./ denom, dims=(2, 3, 4)), dims=(2, 3, 4))
    chi0_BB = pref .* dropdims(sum(W_BB_4d ./ denom, dims=(2, 3, 4)), dims=(2, 3, 4))
    
    # Assemble into (Nw, 2, 2) array
    chi0_w = zeros(ComplexF64, Nw, 2, 2)
    chi0_w[:, 1, 1] = Array(chi0_AA)
    chi0_w[:, 1, 2] = Array(chi0_AB)
    chi0_w[:, 2, 1] = Array(chi0_BA)
    chi0_w[:, 2, 2] = Array(chi0_BB)
    
    return chi0_w
end

# ----------------------------
# CPU fallback for bubble calculation
# ----------------------------

function bubble_chi0_matrix_shift_cpu(s1::Int, s2::Int, omegas::AbstractVector,
                                       eps::Array, vec::Array, Nk::Int;
                                       eta::Real=0.03, T::Real=0.0, mu::Real=0.0)
    Ktot = Nk * Nk
    nb = 2
    Nw = length(omegas)
    
    eps_k = reshape(eps, Ktot, nb)
    vec_k = reshape(vec, Ktot, nb, nb)
    
    # Column-major indexing (1-indexed)
    ii = repeat(1:Nk, outer=Nk)
    jj = repeat(1:Nk, inner=Nk)
    ii_q = mod1.(ii .+ s1, Nk)
    jj_q = mod1.(jj .+ s2, Nk)
    lin_q = ii_q .+ (jj_q .- 1) .* Nk
    
    eps_kq = eps_k[lin_q, :]
    vec_kq = vec_k[lin_q, :, :]
    
    vec_k_conj = conj.(vec_k)
    U_A = reshape(vec_k_conj[:, :, 1], Ktot, nb, 1) .* reshape(vec_kq[:, :, 1], Ktot, 1, nb)
    U_B = reshape(vec_k_conj[:, :, 2], Ktot, nb, 1) .* reshape(vec_kq[:, :, 2], Ktot, 1, nb)
    
    n_k = fermi_occ(eps_k; mu=mu, T=T)
    n_kq = fermi_occ(eps_kq; mu=mu, T=T)
    
    dE = reshape(eps_k, Ktot, nb, 1) .- reshape(eps_kq, Ktot, 1, nb)
    dn = reshape(n_k, Ktot, nb, 1) .- reshape(n_kq, Ktot, 1, nb)
    
    W_AA = dn .* U_A .* conj.(U_A)
    W_AB = dn .* U_A .* conj.(U_B)
    W_BA = dn .* U_B .* conj.(U_A)
    W_BB = dn .* U_B .* conj.(U_B)
    
    pref = -1.0 / (2.0 * Ktot)
    
    chi0_w = zeros(ComplexF64, Nw, 2, 2)
    
    @inbounds for iw in 1:Nw
        w = omegas[iw]
        denom = w .+ dE .+ 1im * eta
        chi0_w[iw, 1, 1] = pref * sum(W_AA ./ denom)
        chi0_w[iw, 1, 2] = pref * sum(W_AB ./ denom)
        chi0_w[iw, 2, 1] = pref * sum(W_BA ./ denom)
        chi0_w[iw, 2, 2] = pref * sum(W_BB ./ denom)
    end
    
    return chi0_w
end

# ----------------------------
# RPA susceptibility: SI Eq. (36)
# ----------------------------

"""
    rpa_chi(chi0, Jq) -> Matrix{ComplexF64}

Compute RPA susceptibility: χ = χ₀ (I + 2 J_q χ₀)⁻¹
"""
function rpa_chi(chi0::AbstractMatrix, Jq::AbstractMatrix)
    I2 = Matrix{ComplexF64}(I, 2, 2)
    return chi0 * inv(I2 + 2.0 * (Jq * chi0))
end

# ----------------------------
# Path construction
# ----------------------------

"""
    build_path(points_k12, n_per_segment) -> (path, ticks)

Build a path through high-symmetry points.
Returns ticks as 0-indexed to match Python.
"""
function build_path(points_k12::Vector{<:Tuple}, n_per_segment::Int)
    pts = Tuple{Float64, Float64}[]
    ticks = Int[0]  # 0-indexed like Python
    
    for i in 1:(length(points_k12) - 1)
        a1, a2 = points_k12[i]
        b1, b2 = points_k12[i + 1]
        for s in 0:(n_per_segment - 1)
            u = s / n_per_segment
            push!(pts, (a1 * (1 - u) + b1 * u, a2 * (1 - u) + b2 * u))
        end
        push!(ticks, length(pts))
    end
    push!(pts, points_k12[end])
    
    return pts, ticks
end

# ----------------------------
# Main driver: compute S0 and/or S_RPA on a path
# ----------------------------

"""
    compute_S_on_path_gpu(path, omegas, eps, vec, Nk, J1, J2; eta=0.03, use_batched=false)

Compute structure factors on GPU along a path.
"""
function compute_S_on_path_gpu(path::Vector{<:Tuple}, omegas::AbstractVector,
                                eps::Array, vec::Array, Nk::Int,
                                J1::Real, J2::Real;
                                eta::Real=0.03, use_batched::Bool=false)
    Nq = length(path)
    Nw = length(omegas)
    
    S = zeros(Float64, Nq, Nw)
    S_rpa = zeros(Float64, Nq, Nw)
    
    I2 = Matrix{ComplexF64}(I, 2, 2)
    
    # Transfer data to GPU
    eps_gpu = CuArray(eps)
    vec_gpu = CuArray(vec)
    
    bubble_func = use_batched ? bubble_chi0_matrix_shift_gpu_batched : bubble_chi0_matrix_shift_gpu
    
    @info "Computing structure factors for $(Nq) q-points..."
    
    for (iq, (q1, q2)) in enumerate(path)
        if iq % 50 == 0
            @info "  Processing q-point $iq / $Nq"
        end
        
        s1 = shift_from_q(q1, Nk)
        s2 = shift_from_q(q2, Nk)
        
        chi0_w = bubble_func(s1, s2, omegas, eps_gpu, vec_gpu, Nk; eta=eta)
        
        Jq = J_matrix(q1, q2, J1, J2)
        R = R_vec(q1)
        
        # S0 and RPA for all omegas
        # Note: R' is the adjoint (conjugate transpose) of R, giving R^H
        # S = Im(R^H * chi0 * R)
        for iw in 1:Nw
            chi0 = chi0_w[iw, :, :]
            S[iq, iw] = imag(R' * chi0 * R)
            
            # RPA
            M = I2 + 2.0 * (Jq * chi0)
            chi_rpa = chi0 * inv(M)
            S_rpa[iq, iw] = imag(R' * chi_rpa * R)
        end
    end
    
    return S, S_rpa
end

"""
    compute_S_on_path_cpu(path, omegas, eps, vec, Nk, J1, J2; eta=0.03)

Compute structure factors on CPU along a path (fallback).
"""
function compute_S_on_path_cpu(path::Vector{<:Tuple}, omegas::AbstractVector,
                                eps::Array, vec::Array, Nk::Int,
                                J1::Real, J2::Real;
                                eta::Real=0.03)
    Nq = length(path)
    Nw = length(omegas)
    
    S = zeros(Float64, Nq, Nw)
    S_rpa = zeros(Float64, Nq, Nw)
    
    I2 = Matrix{ComplexF64}(I, 2, 2)
    
    @info "Computing structure factors (CPU) for $(Nq) q-points..."
    
    Threads.@threads for iq in 1:Nq
        q1, q2 = path[iq]
        
        s1 = shift_from_q(q1, Nk)
        s2 = shift_from_q(q2, Nk)
        
        chi0_w = bubble_chi0_matrix_shift_cpu(s1, s2, omegas, eps, vec, Nk; eta=eta)
        
        Jq = J_matrix(q1, q2, J1, J2)
        R = R_vec(q1)
        
        # S = Im(R^H * chi0 * R) where R^H is conjugate transpose
        for iw in 1:Nw
            chi0 = chi0_w[iw, :, :]
            S[iq, iw] = imag(R' * chi0 * R)
            
            M = I2 + 2.0 * (Jq * chi0)
            chi_rpa = chi0 * inv(M)
            S_rpa[iq, iw] = imag(R' * chi_rpa * R)
        end
    end
    
    return S, S_rpa
end

# ----------------------------
# Plotting (using PyPlot - same as Python matplotlib)
# ----------------------------

"""
    plot_intensity(S, omega_vals, tick_positions, tick_labels, title_str; vmax_val=10.0, rescale_to_vmax=true)

Plot the structure factor intensity using PyPlot (matplotlib).
"""
function plot_intensity(S::Matrix, omega_vals::AbstractVector, tick_positions::Vector{Int},
                        tick_labels::Vector{String}, title_str::String;
                        vmax_val::Real=10.0, rescale_to_vmax::Bool=true)
    Splot = copy(S)
    Splot[Splot .< 0] .= 0.0
    
    if rescale_to_vmax
        p995 = quantile(vec(Splot), 0.995)
        if p995 > 0
            Splot .*= (vmax_val / p995)
        end
    end
    
    PyPlot.figure(figsize=(10, 4))
    PyPlot.imshow(
        Splot',  # Transpose to match Python
        origin="lower",
        aspect="auto",
        extent=[0, size(Splot, 1) - 1, omega_vals[1], omega_vals[end]],
        vmin=0.0,
        vmax=vmax_val,
        interpolation="bicubic"
    )
    PyPlot.colorbar()
    PyPlot.xticks(tick_positions, tick_labels)
    PyPlot.xlabel("q-path index")
    PyPlot.ylabel("ω / J₁")
    PyPlot.title(title_str)
    PyPlot.tight_layout()
    
    return PyPlot.gcf()
end

# ----------------------------
# Main function
# ----------------------------

function main(; use_gpu::Bool=true, use_batched::Bool=false)
    # Parameters (Fig. 2 top panel uses J2/J1 = 0.09 and t/J1 = 0.395)
    J1 = 1.0
    J2 = 0.09
    t = 0.395
    
    Nk = 96
    eta = 0.005
    w_max = 2.6
    Nw = 500
    omegas = collect(range(0.0, w_max, length=Nw))
    
    @info "Parameters: J1=$J1, J2=$J2, t=$t, Nk=$Nk, eta=$eta"
    
    # Check for CUDA
    has_cuda = CUDA.functional()
    if use_gpu && !has_cuda
        @warn "CUDA not available, falling back to CPU"
        use_gpu = false
    end
    
    if use_gpu
        @info "Using GPU: $(CUDA.name(CUDA.device()))"
    else
        @info "Using CPU with $(Threads.nthreads()) threads"
    end
    
    # Precompute bands
    @info "Precomputing band structure..."
    @time kvals, eps, vec = precompute_bands(Nk, t)
    
    # High-symmetry path (M-Y-Γ-X-K-M'-X-Y)
    pts = [
        (0.0, π),              # M
        (0.0, π / 2.0),        # Y
        (0.0, 0.0),            # Γ
        (4π/3, π/3),           # X
        (8π/3, 2π/3),          # K
        (2π, π),               # M'
        (4π/3, π/3),           # X
        (π, 0.0),              # Y
    ]
    # pts = [
    #     (0.0, π),              # M
    #     (0.0, π / 2.0),        # Y
    #     (0.0, 0.0),            # Γ
    #     (2π/3, 2π/3),          # X
    #     (4π/3, 4π/3),          # K
    #     (2π, π),               # M'
    #     (2π/3, 2π/3),          # X
    #     (0.0, π/2.0),          # Y
    # ]
    labels = ["M", "Y", "Γ", "X", "K", "M'", "X", "Y"]
    path, ticks = build_path(pts, 100)
    
    # Compute structure factors
    @info "Computing structure factors..."
    if use_gpu
        @time S0, S_rpa = compute_S_on_path_gpu(path, omegas, eps, vec, Nk, J1, J2; 
                                                 eta=eta, use_batched=use_batched)
    else
        @time S0, S_rpa = compute_S_on_path_cpu(path, omegas, eps, vec, Nk, J1, J2; eta=eta)
    end
    
    # Plot results
    @info "Generating plots..."
    
    # Plot 1: Free fermion
    fig1 = plot_intensity(S0, omegas, ticks, labels, "Free fermion structure factor (χ₀)")
    display(fig1)
    
    # Plot 2: RPA
    fig2 = plot_intensity(S_rpa, omegas, ticks, labels, 
                          "RPA structure factor, J₂/J₁=$(J2/J1), t/J₁=$(t/J1), Nk=$Nk, η=$eta")
    display(fig2)
    
    # Save to files
    fig1.savefig("S0_free_fermion.png", dpi=150)
    fig2.savefig("S_rpa.png", dpi=150)
    @info "Plots saved to S0_free_fermion.png and S_rpa.png"
    
    return S0, S_rpa
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
