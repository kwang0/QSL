using LinearAlgebra
using Printf

# ============================================================
# Triangular-lattice pi-flux DSL, two-site unit cell
#
# Coordinates:
#   r = x a1 + y a2
#
# Magnetic unit cell:
#   R = n1 * (2a1) + n2 * a2
#
# Sublattice basis:
#   A = site 1 = (x,y) = (2n1,   n2)
#   B = site 2 = (x,y) = (2n1+1, n2)
#
# Dirac nodes in the reduced Brillouin zone:
#   Q+ = (pi,  pi/2)
#   Q- = (pi, -pi/2)
#
# Explicit eigenvector convention:
#   e1+ = e1- = (1,0)
#   e2+ = e2- = (0,1)
#
# This script mirrors the Hermele Appendix-B PSG procedure:
#   1. build explicit nodal wavefunctions Phi
#   2. build lattice PSG operation U_S
#   3. project: M_S = Phi' U_S Phi
#   4. continuum fields transform with D_S = M_S'
# ============================================================

const L1 = 2          # number of doubled cells along 2a1
const L2 = 4          # number of cells along a2
const Ns = 2 * L1 * L2
const Nc = L1 * L2
const t = 1.0

if L2 % 4 != 0
    error("Need L2 divisible by 4 so that k2 = +/- pi/2 is allowed.")
end

if L1 % 2 != 0
    error("Need L1 even so that k1 = pi is allowed.")
end

# ------------------------------------------------------------
# Two-site pi-flux ansatz
#
# Terms are (i, j, dn1, dn2, s), meaning a hopping amplitude
# t*s from sublattice i in cell (n1,n2) to sublattice j in
# cell (n1+dn1,n2+dn2).
#
# These terms reproduce
#
#   H(k) = t [ 2 cos k2,  g(k);
#              g(k)^*,   -2 cos k2 ],
#
#   g(k) = 1 + exp(-ik1) + exp(i(k2-k1)) - exp(-ik2).
# ------------------------------------------------------------

const terms = Tuple{Int,Int,Int,Int,Int}[
    # diagonal A-A and B-B hoppings along a2
    (1, 1,  0,  1,  1),
    (2, 2,  0,  1, -1),

    # A-B hoppings
    (1, 2,  0,  0,  1),
    (1, 2, -1,  0,  1),
    (1, 2, -1,  1,  1),
    (1, 2,  0, -1, -1)
]

# ------------------------------------------------------------
# Indexing
# ------------------------------------------------------------

function site_index(n1::Int, n2::Int, sub::Int)
    n1m = mod(n1, L1)
    n2m = mod(n2, L2)
    return 2 * (n1m + L1 * n2m) + sub
end

function decode_site(r::Int)
    z = r - 1
    sub = mod(z, 2) + 1
    cell = div(z, 2)
    n1 = mod(cell, L1)
    n2 = div(cell, L1)
    return n1, n2, sub
end

function xy_from_site(r::Int)
    n1, n2, sub = decode_site(r)
    x = 2 * n1 + (sub - 1)
    y = n2
    return x, y
end

function site_from_xy(x::Int, y::Int)
    xm = mod(x, 2 * L1)
    ym = mod(y, L2)

    sub = mod(xm, 2) + 1
    n1 = div(xm - (sub - 1), 2)
    n2 = ym

    return site_index(n1, n2, sub)
end

# ------------------------------------------------------------
# Bloch Hamiltonian
# ------------------------------------------------------------

function bloch_hamiltonian(k1::Real, k2::Real)
    H = zeros(ComplexF64, 2, 2)

    for (i, j, dn1, dn2, s) in terms
        phase = exp(1im * (dn1 * k1 + dn2 * k2))
        amp = t * s * phase

        H[i, j] += amp
        H[j, i] += conj(amp)
    end

    return H
end

# Explicit eigenvectors at Q+ and Q-
eplus = ComplexF64[
    1 0;
    0 1
]

eminus = ComplexF64[
    1 0;
    0 1
]

println("Checks at Dirac points:")
@printf("  ||H(Q+) e1+|| = %.3e\n", norm(bloch_hamiltonian(pi,  pi/2) * eplus[:,1]))
@printf("  ||H(Q+) e2+|| = %.3e\n", norm(bloch_hamiltonian(pi,  pi/2) * eplus[:,2]))
@printf("  ||H(Q-) e1-|| = %.3e\n", norm(bloch_hamiltonian(pi, -pi/2) * eminus[:,1]))
@printf("  ||H(Q-) e2-|| = %.3e\n", norm(bloch_hamiltonian(pi, -pi/2) * eminus[:,2]))

function hlin_plus(q1, q2)
    return t * ComplexF64[
        -2q2                      (-1 + 1im) * q1 + 2q2;
        (-1 - 1im) * q1 + 2q2      2q2
    ]
end

function hlin_minus(q1, q2)
    return t * ComplexF64[
        2q2                       (1 + 1im) * q1 - 2q2;
        (1 - 1im) * q1 - 2q2      -2q2
    ]
end

eps = 1e-6

dH1_plus_num  = (bloch_hamiltonian(pi + eps, pi/2) - bloch_hamiltonian(pi - eps, pi/2)) / (2eps)
dH2_plus_num  = (bloch_hamiltonian(pi, pi/2 + eps) - bloch_hamiltonian(pi, pi/2 - eps)) / (2eps)

dH1_minus_num = (bloch_hamiltonian(pi + eps, -pi/2) - bloch_hamiltonian(pi - eps, -pi/2)) / (2eps)
dH2_minus_num = (bloch_hamiltonian(pi, -pi/2 + eps) - bloch_hamiltonian(pi, -pi/2 - eps)) / (2eps)

dH1_plus_exact  = hlin_plus(1.0, 0.0)
dH2_plus_exact  = hlin_plus(0.0, 1.0)
dH1_minus_exact = hlin_minus(1.0, 0.0)
dH2_minus_exact = hlin_minus(0.0, 1.0)

println()
println("Linearization checks:")
@printf("  +Q: ||dH/dk1 - formula|| = %.3e\n", norm(dH1_plus_num - dH1_plus_exact))
@printf("  +Q: ||dH/dk2 - formula|| = %.3e\n", norm(dH2_plus_num - dH2_plus_exact))
@printf("  -Q: ||dH/dk1 - formula|| = %.3e\n", norm(dH1_minus_num - dH1_minus_exact))
@printf("  -Q: ||dH/dk2 - formula|| = %.3e\n", norm(dH2_minus_num - dH2_minus_exact))

# ------------------------------------------------------------
# Real-space Hamiltonian
# ------------------------------------------------------------

function build_realspace_hamiltonian()
    H = zeros(ComplexF64, Ns, Ns)

    for n1 in 0:L1-1, n2 in 0:L2-1
        for (i, j, dn1, dn2, s) in terms
            r  = site_index(n1, n2, i)
            rp = site_index(n1 + dn1, n2 + dn2, j)

            H[r, rp] += t * s
            H[rp, r] += t * s
        end
    end

    return H
end

H = build_realspace_hamiltonian()

# ------------------------------------------------------------
# Real-space Dirac wavefunctions Phi
#
# Column order:
#   1 = (+Q, A)
#   2 = (+Q, B)
#   3 = (-Q, A)
#   4 = (-Q, B)
# ------------------------------------------------------------

function make_phi()
    Phi = zeros(ComplexF64, Ns, 4)

    for n1 in 0:L1-1, n2 in 0:L2-1
        phase_plus  = exp(1im * (pi * n1 +  pi/2 * n2))
        phase_minus = exp(1im * (pi * n1 + -pi/2 * n2))

        rA = site_index(n1, n2, 1)
        rB = site_index(n1, n2, 2)

        Phi[rA, 1] = phase_plus  / sqrt(Nc)
        Phi[rB, 2] = phase_plus  / sqrt(Nc)
        Phi[rA, 3] = phase_minus / sqrt(Nc)
        Phi[rB, 4] = phase_minus / sqrt(Nc)
    end

    return Phi
end

Phi = make_phi()

println()
println("Phi' * Phi:")
display(Phi' * Phi)

@printf("  ||H Phi|| = %.3e\n", norm(H * Phi))

# ------------------------------------------------------------
# Utility for readable output
# ------------------------------------------------------------

function chop_matrix(A; tol=1e-10, digits=3)
    B = similar(A)
    for ind in eachindex(A)
        z = A[ind]
        re = abs(real(z)) < tol ? 0.0 : real(z)
        im = abs(imag(z)) < tol ? 0.0 : imag(z)
        B[ind] = round(re; digits=digits) + 1im * round(im; digits=digits)
    end
    return B
end

# ------------------------------------------------------------
# Build sign dictionary for lattice bonds
# ------------------------------------------------------------

function put_sign!(dict, r, rp, s)
    if haskey(dict, (r, rp)) && dict[(r, rp)] != s
        error("Contradictory bond sign encountered.")
    end
    dict[(r, rp)] = s
end

function build_sign_dict()
    signs = Dict{Tuple{Int,Int},Int}()

    for n1 in 0:L1-1, n2 in 0:L2-1
        for (i, j, dn1, dn2, s) in terms
            r  = site_index(n1, n2, i)
            rp = site_index(n1 + dn1, n2 + dn2, j)

            put_sign!(signs, r,  rp, s)
            put_sign!(signs, rp, r,  s)
        end
    end

    return signs
end

const signs = build_sign_dict()

function build_neighbors()
    neigh = [Int[] for _ in 1:Ns]

    for key in keys(signs)
        r, rp = key
        push!(neigh[r], rp)
    end

    return neigh
end

const neighbors = build_neighbors()

# ------------------------------------------------------------
# Space-group coordinate maps
#
# T1:     (x,y) -> (x+1,y)
# T2:     (x,y) -> (x,y+1)
# C3:     120-degree rotation about a site
# sigma:  mirror across the a1 axis
# C6:     60-degree rotation about a site
#
# C3 is particle-space in this gauge.
# sigma and C6 require a particle-hole SU(2) gauge operation.
# ------------------------------------------------------------

T1_coord(x::Int, y::Int) = (x + 1, y)
T2_coord(x::Int, y::Int) = (x, y + 1)
C3_coord(x::Int, y::Int) = (-x - y, x)
sigma_coord(x::Int, y::Int) = (x + y, -y)
C6_coord(x::Int, y::Int) = (-y, x + y)

function site_map_from_coordmap(coordmap)
    smap = zeros(Int, Ns)

    for r in 1:Ns
        x, y = xy_from_site(r)
        xp, yp = coordmap(x, y)
        smap[r] = site_from_xy(xp, yp)
    end

    return smap
end

# ------------------------------------------------------------
# Solve compensating gauge transformation.
#
# link_sign = +1:
#   ordinary particle-space U(1) PSG operation
#
# link_sign = -1:
#   operation also uses a global particle-hole SU(2) gauge
#   rotation, which sends tau_z -> -tau_z in Nambu space.
#
# Constraint:
#   s_{S(r),S(r')} = link_sign * pi(r) * s_{r,r'} * pi(r')
# ------------------------------------------------------------

function solve_gauge(smap, link_sign::Int)
    piS = zeros(Int, Ns)
    piS[1] = 1

    queue = [1]

    while !isempty(queue)
        r = popfirst!(queue)

        for rp in neighbors[r]
            if !haskey(signs, (smap[r], smap[rp]))
                error("Mapped bond is absent; the coordinate map is not a symmetry of the bond graph.")
            end

            sorig = signs[(r, rp)]
            simage = signs[(smap[r], smap[rp])]

            candidate = piS[r] * sorig * link_sign * simage

            if piS[rp] == 0
                piS[rp] = candidate
                push!(queue, rp)
            elseif piS[rp] != candidate
                error("Inconsistent gauge assignment.")
            end
        end
    end

    if any(piS .== 0)
        error("Gauge assignment did not reach every site.")
    end

    return piS
end

# ------------------------------------------------------------
# Particle-space projection
#
# This is the direct analogue of the kagome Appendix-B
# calculation for symmetries that act as f_r -> pi_r f_{S(r)}.
# In this gauge, T1, T2, and C3 work this way.
# ------------------------------------------------------------

function build_particle_U(smap, piS)
    U = zeros(ComplexF64, Ns, Ns)

    for r in 1:Ns
        U[smap[r], r] = piS[r]
    end

    return U
end

function project_particle_symmetry(name, coordmap)
    println()
    println("============================================================")
    println("Particle-space symmetry: ", name)

    smap = site_map_from_coordmap(coordmap)
    piS = solve_gauge(smap, +1)
    U = build_particle_U(smap, piS)

    @printf("  ||U H U' - H|| = %.3e\n", norm(U * H * U' - H))

    M = Phi' * U * Phi
    D = M'

    println("  D = M':")
    display(chop_matrix(D))

    return D
end

D_T1 = project_particle_symmetry("T1", T1_coord)
D_T2 = project_particle_symmetry("T2", T2_coord)
D_C3 = project_particle_symmetry("C3", C3_coord)

I4 = Matrix{ComplexF64}(I, 4, 4)

println()
println("Particle-space PSG checks:")
@printf("  ||D_T1' D_T1 - I||       = %.3e\n", norm(D_T1' * D_T1 - I4))
@printf("  ||D_T2' D_T2 - I||       = %.3e\n", norm(D_T2' * D_T2 - I4))
@printf("  ||D_T1 D_T2 + D_T2 D_T1|| = %.3e\n", norm(D_T1 * D_T2 + D_T2 * D_T1))
@printf("  ||D_C3^3 - I||           = %.3e\n", norm(D_C3^3 - I4))

# ------------------------------------------------------------
# Nambu projection for full point group
#
# The two-site triangular pi-flux ansatz has point-group
# operations that can require a particle-hole SU(2) gauge
# transformation. This is still a two-site unit cell.
#
# Nambu spinor:
#   eta_r = (f_r, f_r^dagger)
#
# Link matrix:
#   U_rr' = s_rr' tau_z
#
# A global i tau_x sends tau_z -> -tau_z.
# Therefore sigma and C6 use link_sign = -1.
# ------------------------------------------------------------

const tau0 = ComplexF64[1 0; 0 1]
const taux = ComplexF64[0 1; 1 0]
const tauz = ComplexF64[1 0; 0 -1]

const G_particle = tau0
const G_ph = 1im * taux

function build_nambu_hamiltonian()
    Hn = zeros(ComplexF64, 2 * Ns, 2 * Ns)

    for kv in signs
        r, rp = kv.first
        s = kv.second

        Hn[(2r-1):(2r), (2rp-1):(2rp)] .= s * tauz
    end

    return Hn
end

Hnambu = build_nambu_hamiltonian()

function make_xi()
    Xi = zeros(ComplexF64, 2 * Ns, 8)

    for r in 1:Ns
        for p in 1:4
            Xi[2r - 1, p] = Phi[r, p]
            Xi[2r, 4 + p] = conj(Phi[r, p])
        end
    end

    return Xi
end

Xi = make_xi()

println()
println("Xi' * Xi:")
display(chop_matrix(Xi' * Xi))

function build_nambu_U(smap, piS, link_sign::Int)
    U = zeros(ComplexF64, 2 * Ns, 2 * Ns)

    G0 = link_sign == +1 ? G_particle : G_ph

    for r in 1:Ns
        rp = smap[r]
        U[(2rp-1):(2rp), (2r-1):(2r)] .= piS[r] * G0
    end

    return U
end

function project_nambu_symmetry(name, coordmap, link_sign::Int)
    println()
    println("============================================================")
    println("Nambu PSG symmetry: ", name)

    smap = site_map_from_coordmap(coordmap)
    piS = solve_gauge(smap, link_sign)
    U = build_nambu_U(smap, piS, link_sign)

    @printf("  ||U Hn U' - Hn|| = %.3e\n", norm(U * Hnambu * U' - Hnambu))

    M = Xi' * U * Xi
    D = M'

    println("  D = M':")
    display(chop_matrix(D))

    return D
end

D_T1_n = project_nambu_symmetry("T1", T1_coord, +1)
D_T2_n = project_nambu_symmetry("T2", T2_coord, +1)
D_C3_n = project_nambu_symmetry("C3", C3_coord, +1)
D_sigma_n = project_nambu_symmetry("sigma", sigma_coord, -1)
D_C6_n = project_nambu_symmetry("C6", C6_coord, -1)

I8 = Matrix{ComplexF64}(I, 8, 8)

println()
println("Nambu PSG checks:")
@printf("  ||D_T1' D_T1 - I||         = %.3e\n", norm(D_T1_n' * D_T1_n - I8))
@printf("  ||D_T2' D_T2 - I||         = %.3e\n", norm(D_T2_n' * D_T2_n - I8))
@printf("  ||D_T1 D_T2 + D_T2 D_T1||  = %.3e\n", norm(D_T1_n * D_T2_n + D_T2_n * D_T1_n))
@printf("  ||D_C3^3 - I||             = %.3e\n", norm(D_C3_n^3 - I8))

# With this representative, sigma^2 and C6^6 are -1 IGG elements.
@printf("  ||D_sigma^2 + I||          = %.3e\n", norm(D_sigma_n^2 + I8))
@printf("  ||D_C6^6 + I||             = %.3e\n", norm(D_C6_n^6 + I8))
# Put triangular translation PSG into the kagome-like canonical basis.

I2 = Matrix{ComplexF64}(I, 2, 2)

mu1 = ComplexF64[0 1; 1 0]
mu2 = ComplexF64[0 -1im; 1im 0]
mu3 = ComplexF64[1 0; 0 -1]

sig2 = ComplexF64[0 -1im; 1im 0]
A = 1im * sig2

W = zeros(ComplexF64, 4, 4)
W[1:2, 1:2] .= I2
W[3:4, 3:4] .= A

D_T1_canonical = W * D_T1 * W'
D_T2_canonical = W * D_T2 * W'

D_T1_expected = kron(1im * mu2, I2)
D_T2_expected = kron(1im * mu3, I2)

println()
println("Canonical-basis translation checks:")
@printf("  ||W D_T1 W' - i mu2|| = %.3e\n", norm(D_T1_canonical - D_T1_expected))
@printf("  ||W D_T2 W' - i mu3|| = %.3e\n", norm(D_T2_canonical - D_T2_expected))