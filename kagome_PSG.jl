using LinearAlgebra
using Printf

# ============================================================
# PSG projection using the explicit Appendix A eigenvectors
#
# Paper site labels 0,...,5 are represented here as 1,...,6.
# Column order for Phi:
#   1 = (+Q, p=1)
#   2 = (+Q, p=2)
#   3 = (-Q, p=1)
#   4 = (-Q, p=2)
# ============================================================

const L1 = 1
const L2 = 2
const Ns = 6 * L1 * L2
const Nc = L1 * L2
const t = 1.0

# Six-site doubled unit cell, in fractional coordinates (a1, a2),
# shifted so that the hexagon center is at (0,0).
basis = [
    (-1//2, -1//2),  # paper site 0
    ( 0//1, -1//2),  # paper site 1
    (-1//2,  0//1),  # paper site 2
    ( 1//2, -1//2),  # paper site 3
    ( 1//1, -1//2),  # paper site 4
    ( 1//2,  0//1)   # paper site 5
]

# Directed bonds from Eq. A1.
# Entry: (i, j, dn1, dn2, s)
# means hopping sign s from (n1,n2,i) to (n1+dn1,n2+dn2,j).
# Hamiltonian matrix element is -t*s.
bonds = [
    (1, 2,  0, 0,  1),
    (1, 3,  0, 0,  1),

    (2, 3,  0, 0,  1),
    (2, 4,  0, 0, -1),

    (3, 1,  0, 1, -1),
    (3, 5, -1, 1, -1),

    (4, 5,  0, 0,  1),
    (4, 6,  0, 0,  1),

    (5, 6,  0, 0,  1),
    (5, 1,  1, 0,  1),

    (6, 4,  0, 1,  1),
    (6, 2,  0, 1, -1)
]

# ------------------------------------------------------------
# Indexing
# ------------------------------------------------------------

function site_index(n1::Int, n2::Int, i::Int)
    n1m = mod(n1, L1)
    n2m = mod(n2, L2)
    return 6 * (n1m + L1 * n2m) + i
end

function decode_site(r::Int)
    x = r - 1
    i = mod(x, 6) + 1
    cell = div(x, 6)
    n1 = mod(cell, L1)
    n2 = div(cell, L1)
    return n1, n2, i
end

function coord_of_site(r::Int)
    n1, n2, i = decode_site(r)
    bu, bv = basis[i]
    return (2//1 * n1 + bu, 1//1 * n2 + bv)
end

function coord_to_site(coord)
    u, v = coord

    for i in 1:6
        bu, bv = basis[i]
        q1 = (u - bu) / 2
        q2 = v - bv

        if denominator(q1) == 1 && denominator(q2) == 1
            return site_index(Int(numerator(q1)), Int(numerator(q2)), i)
        end
    end

    error("Could not map coordinate " * string(coord) * " back to a kagome site.")
end

# ------------------------------------------------------------
# Explicit Appendix A eigenvectors, Eqs. A4-A7
# ------------------------------------------------------------

phase(x) = exp(1im * pi * Float64(x))

const rt2 = sqrt(2.0)
const rt6 = sqrt(6.0)

e1p = ComplexF64[
    -phase(-1//24),
     rt2 * phase(-11//24),
     phase(1//8),
     phase(-1//24),
     0,
     phase(-3//8)
] ./ rt6

e2p = ComplexF64[
    -phase(1//24),
     0,
     phase(-5//8),
    -phase(1//24),
     rt2 * phase(11//24),
     phase(-1//8)
] ./ rt6

e1m = ComplexF64[
    -phase(-1//24),
     0,
     phase(5//8),
    -phase(-1//24),
     rt2 * phase(-11//24),
     phase(1//8)
] ./ rt6

e2m = ComplexF64[
     phase(1//24),
     rt2 * phase(-13//24),
    -phase(-1//8),
    -phase(1//24),
     0,
     phase(-5//8)
] ./ rt6

# ------------------------------------------------------------
# Hamiltonian, used only for checks
# ------------------------------------------------------------

function build_realspace_hamiltonian()
    H = zeros(ComplexF64, Ns, Ns)

    for n1 in 0:L1-1, n2 in 0:L2-1
        for (i, j, dn1, dn2, s) in bonds
            r  = site_index(n1, n2, i)
            rp = site_index(n1 + dn1, n2 + dn2, j)
            amp = -t * s

            H[r, rp] += amp
            H[rp, r] += conj(amp)
        end
    end

    return H
end

function bloch_hamiltonian(kA1, kA2)
    Hk = zeros(ComplexF64, 6, 6)

    for (i, j, dn1, dn2, s) in bonds
        phase_factor = exp(1im * (dn1 * kA1 + dn2 * kA2))
        amp = -t * s * phase_factor

        Hk[i, j] += amp
        Hk[j, i] += conj(amp)
    end

    return Hk
end

H = build_realspace_hamiltonian()

EF = sqrt(3.0) - 1.0

println("Checks that explicit Appendix A vectors are eigenvectors:")
@printf("  +Q e1 residual = %.3e\n", norm(bloch_hamiltonian(0.0,  pi / 2) * e1p - EF * e1p))
@printf("  +Q e2 residual = %.3e\n", norm(bloch_hamiltonian(0.0,  pi / 2) * e2p - EF * e2p))
@printf("  -Q e1 residual = %.3e\n", norm(bloch_hamiltonian(0.0, -pi / 2) * e1m - EF * e1m))
@printf("  -Q e2 residual = %.3e\n", norm(bloch_hamiltonian(0.0, -pi / 2) * e2m - EF * e2m))

# ------------------------------------------------------------
# Real-space Dirac basis Phi
# ------------------------------------------------------------

function make_phi()
    Phi = zeros(ComplexF64, Ns, 4)

    for n1 in 0:L1-1, n2 in 0:L2-1, i in 1:6
        r = site_index(n1, n2, i)

        # Q dot R' = n2 * pi / 2, since Q dot (2a1) = 0
        # and Q dot a2 = pi / 2.
        phip = exp( 1im * n2 * pi / 2)
        phim = exp(-1im * n2 * pi / 2)

        Phi[r, 1] = phip * e1p[i] / sqrt(Nc)
        Phi[r, 2] = phip * e2p[i] / sqrt(Nc)
        Phi[r, 3] = phim * e1m[i] / sqrt(Nc)
        Phi[r, 4] = phim * e2m[i] / sqrt(Nc)
    end

    return Phi
end

Phi = make_phi()

println()
println("Phi' * Phi:")
display(Phi' * Phi)

# ------------------------------------------------------------
# Microscopic symmetry maps in fractional coordinates
# ------------------------------------------------------------

Ta1_coord(coord) = (coord[1] + 1//1, coord[2])
Ta2_coord(coord) = (coord[1], coord[2] + 1//1)
Ry_coord(coord)  = (coord[1] + coord[2], -coord[2])
R60_coord(coord) = (-coord[2], coord[1] + coord[2])

function site_map_from_coordmap(coordmap)
    smap = zeros(Int, Ns)
    for r in 1:Ns
        smap[r] = coord_to_site(coordmap(coord_of_site(r)))
    end
    return smap
end

# ------------------------------------------------------------
# Solve compensating gauge transformation pi_S(r) = +/- 1
# ------------------------------------------------------------

function build_sign_dict()
    signs = Dict{Tuple{Int,Int},Int}()

    for n1 in 0:L1-1, n2 in 0:L2-1
        for (i, j, dn1, dn2, s) in bonds
            r  = site_index(n1, n2, i)
            rp = site_index(n1 + dn1, n2 + dn2, j)

            signs[(r, rp)] = s
            signs[(rp, r)] = s
        end
    end

    return signs
end

signs = build_sign_dict()

function neighbors_of(r::Int)
    out = Int[]
    for key in keys(signs)
        a, b = key
        if a == r
            push!(out, b)
        end
    end
    return out
end

function solve_compensating_gauge(smap)
    piS = zeros(Int, Ns)
    piS[1] = 1

    queue = [1]

    while !isempty(queue)
        r = popfirst!(queue)

        for rp in neighbors_of(r)
            s1 = signs[(r, rp)]
            s2 = signs[(smap[r], smap[rp])]

            candidate = piS[r] * s1 * s2

            if piS[rp] == 0
                piS[rp] = candidate
                push!(queue, rp)
            elseif piS[rp] != candidate
                error("Inconsistent gauge assignment.")
            end
        end
    end

    if any(piS .== 0)
        error("Gauge assignment did not reach all sites.")
    end

    return piS
end

function build_US(smap, piS; igg_phase = 1.0 + 0.0im)
    U = zeros(ComplexF64, Ns, Ns)

    for r in 1:Ns
        U[smap[r], r] = igg_phase * piS[r]
    end

    return U
end

# ------------------------------------------------------------
# Project a lattice PSG operation into the Dirac subspace
# ------------------------------------------------------------

function project_symmetry(name, coordmap; igg_phase = 1.0 + 0.0im)
    println()
    println("============================================================")
    println("Symmetry: ", name)

    smap = site_map_from_coordmap(coordmap)
    piS = solve_compensating_gauge(smap)
    U = build_US(smap, piS; igg_phase = igg_phase)

    @printf("  || U H U' - H || = %.3e\n", norm(U * H * U' - H))

    # If U phi_alpha = sum_beta M[beta,alpha] phi_beta,
    # then annihilation fields transform with D = M'.
    M = Phi' * U * Phi
    D = M'

    println("  M = Phi' * U * Phi:")
    display(M)

    println("  D = M':")
    display(D)

    return D
end

D_Ta1 = project_symmetry("T_a1", Ta1_coord)
D_Ta2 = project_symmetry("T_a2", Ta2_coord)
D_Ry  = project_symmetry("R_y",  Ry_coord)

# The raw R60 comes out differing from the paper by an IGG element -1.
# Choosing igg_phase = -1 fixes that convention.
D_R60 = project_symmetry("R_pi_over_3", R60_coord; igg_phase = -1.0 + 0.0im)

# ------------------------------------------------------------
# Expected matrices in the paper's convention
# ------------------------------------------------------------

I2 = Matrix{ComplexF64}(I, 2, 2)

mu1 = ComplexF64[0 1; 1 0]
mu2 = ComplexF64[0 -1im; 1im 0]
mu3 = ComplexF64[1 0; 0 -1]

sig1 = ComplexF64[0 1; 1 0]
sig2 = ComplexF64[0 -1im; 1im 0]
sig3 = ComplexF64[1 0; 0 -1]

# Basis order is node first, Dirac spinor second:
#   (+,1), (+,2), (-,1), (-,2)
D_Ta1_expected = kron(1im * mu2, I2)
D_Ta2_expected = kron(1im * mu3, I2)

mu_ry = -(mu1 + mu3) / sqrt(2.0)
mu_R  =  (mu1 + mu2 - mu3) / sqrt(3.0)

D_Ry_expected  = kron(exp(1im * pi / 2 * mu_ry), 1im * sig1)
D_R60_expected = kron(exp(2im * pi / 3 * mu_R), exp(1im * pi / 6 * sig3))

println()
println("============================================================")
println("Comparison to expected Appendix B matrices")
@printf("  ||D_Ta1 - i mu2||                    = %.3e\n", norm(D_Ta1 - D_Ta1_expected))
@printf("  ||D_Ta2 - i mu3||                    = %.3e\n", norm(D_Ta2 - D_Ta2_expected))
@printf("  ||D_Ry  - i sigma1 exp(i pi mu_ry/2)|| = %.3e\n", norm(D_Ry - D_Ry_expected))
@printf("  ||D_R60 - exp(i pi sigma3/6) exp(2 pi i mu_R/3)|| = %.3e\n", norm(D_R60 - D_R60_expected))

# ------------------------------------------------------------
# Antiunitary time reversal, orbital part only
# ------------------------------------------------------------

println()
println("============================================================")
println("Antiunitary time reversal, orbital part only")

# Complex conjugation sends +Q to -Q.
# The full spinful time reversal also includes i sigma_spin^2.
M_T = Phi' * conj.(Phi)
D_T = M_T'

D_T_expected = kron(-1im * mu2, 1im * sig2)

println("  D_T orbital:")
display(D_T)
@printf("  ||D_T - (-i mu2)(i sigma2)|| = %.3e\n", norm(D_T - D_T_expected))

# ------------------------------------------------------------
# Projective relation checks
# ------------------------------------------------------------

I4 = Matrix{ComplexF64}(I, 4, 4)

println()
println("============================================================")
println("Projective relation checks")
@printf("  ||D_Ta1' D_Ta1 - I|| = %.3e\n", norm(D_Ta1' * D_Ta1 - I4))
@printf("  ||D_Ta2' D_Ta2 - I|| = %.3e\n", norm(D_Ta2' * D_Ta2 - I4))

# Translations anticommute projectively because of pi flux.
@printf("  ||D_Ta1 D_Ta2 + D_Ta2 D_Ta1|| = %.3e\n", norm(D_Ta1 * D_Ta2 + D_Ta2 * D_Ta1))

# A 2 pi spatial rotation gives -1 on the continuum Dirac spinor,
# which is an IGG element.
@printf("  ||D_R60^6 + I|| = %.3e\n", norm(D_R60^6 + I4))

@printf("  ||D_Ry^2 - I|| = %.3e\n", norm(D_Ry^2 - I4))