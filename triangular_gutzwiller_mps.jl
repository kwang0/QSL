module TriangularGutzwillerMPS

using LinearAlgebra
using Printf
using ITensors
using ITensorMPS

const _HAS_CUDA = try
    @eval using CUDA
    true
catch
    false
end

export AbstractTriangularCylinder,
       TriangularXC,
       TriangularYC,
       coord,
       ind,
       nn_bonds,
       nnn_bonds,
       build_u1_dsl_hopping,
       build_u1_dsl_spin_hoppings,
       build_z2_0flux_bdg,
       build_z2_piflux_bdg,
       prepare_u1_dsl_gutzwiller_mps,
       prepare_z2_0flux_gutzwiller_mps,
       prepare_z2_piflux_gutzwiller_mps,
       gutzwiller_project_to_spin,
       has_cuda,
       to_device

# ------------------------------------------------------------------
# Basic utilities
# ------------------------------------------------------------------

abstract type AbstractTriangularCylinder end

"""
XC-cylinder triangular lattice matching the indexing convention used in
`J1_J2_triangular_gpu.jl`:
`ind(row,col,C) = col*C + mod(row,C) + 1`.
Rows wind around the cylinder, columns run along the open direction.
"""
struct TriangularXC <: AbstractTriangularCylinder
    C::Int
    L::Int
    function TriangularXC(C::Int, L::Int)
        C > 0 || error("TriangularXC requires C > 0")
        L > 0 || error("TriangularXC requires L > 0")
        new(C, L)
    end
end

"""
YC-cylinder triangular lattice.

`C` is the circumference (number of sites around the periodic direction),
`L` is the open length, and `m` is the generalized shift in the identification
used in YC2n-2m cylinders: when the row index winds by `C`, the column index is
shifted by `m`.

For `m = 0` this reduces to the ordinary YC geometry used in
`J1_J2_triangular_YC_gpu.jl`.
"""
struct TriangularYC <: AbstractTriangularCylinder
    C::Int
    L::Int
    m::Int
    function TriangularYC(C::Int, L::Int, m::Int=0)
        C > 0 || error("TriangularYC requires C > 0")
        L > 0 || error("TriangularYC requires L > 0")
        0 <= m < C || error("TriangularYC requires 0 ≤ m < C; got m=$m, C=$C")
        new(C, L, m)
    end
end

nsite(lat::AbstractTriangularCylinder) = lat.C * lat.L

vprintln(verbose::Bool, msg) = verbose && println(msg)

has_cuda() = _HAS_CUDA

to_cpu(x) = ITensors.cpu(x)

function to_device(x; use_cuda::Bool=false, verbose::Bool=true, label::AbstractString="object")
    if use_cuda
        if !_HAS_CUDA
            error("use_cuda=true was requested for $(label), but CUDA.jl could not be loaded in this environment.")
        end
        vprintln(verbose, "[to_device] Moving $(label) to CUDA device memory")
        return cu(x)
    else
        vprintln(verbose, "[to_device] Ensuring $(label) is on CPU")
        return ITensors.cpu(x)
    end
end

function resolve_mode_apply_alg(
    mode_apply_alg::Union{Nothing,Symbol,AbstractString};
    verbose::Bool = true,
    label::AbstractString = "mode applications",
)
    alg = isnothing(mode_apply_alg) ? "densitymatrix" : String(mode_apply_alg)
    if !isnothing(mode_apply_alg)
        vprintln(verbose, "[$label] Using apply(...; alg=\"$alg\")")
    end
    return alg
end

function vbond_dims(psi::MPS)
    N = length(psi)
    N <= 1 && return Int[]
    return [dim(linkind(psi, b)) for b in 1:(N - 1)]
end

function vlog_state_summary(verbose::Bool, psi::MPS, label::AbstractString)
    if verbose
        bds = vbond_dims(psi)
        maxbd = isempty(bds) ? 1 : maximum(bds)
        norm2 = real(inner(psi, psi))
        println(@sprintf("[%s] norm^2 = %.12e, max bond dim = %d", label, norm2, maxbd))
    end
    return nothing
end

# ------------------------------------------------------------------
# Geometry helpers
# ------------------------------------------------------------------

"""
Map `(row,col)` -> site index (1-based), with periodic boundary conditions in the
row/circumference direction.
"""
ind(lat::TriangularXC, row::Int, col::Int) = col * lat.C + mod(row, lat.C) + 1

function _wrapped_target(lat::TriangularXC, row::Int, col::Int)
    0 <= col < lat.L || return nothing
    q = fld(row, lat.C)
    rowm = mod(row, lat.C)
    return (i=ind(lat, rowm, col), row=rowm, col=col, winding=q)
end

function _wrapped_target(lat::TriangularYC, row::Int, col::Int)
    q = fld(row, lat.C)
    rowm = mod(row, lat.C)
    colm = col + q * lat.m
    0 <= colm < lat.L || return nothing
    return (i=colm * lat.C + rowm + 1, row=rowm, col=colm, winding=q)
end

function ind(lat::TriangularYC, row::Int, col::Int)
    t = _wrapped_target(lat, row, col)
    isnothing(t) && error("(row,col)=($row,$col) maps outside the finite YC domain for geometry $(lat)")
    return t.i
end

"""
Physical coordinate of site `i` in the XC embedding, copied from the existing
XC triangular-lattice script so the ansatz construction lines up with that
Hamiltonian path/geometry.
"""
function coord(lat::TriangularXC, i::Int)
    y = (i - 1) % lat.C
    x = (i - 1) ÷ lat.C
    if isodd(y)
        x += 0.5
    end
    x -= (lat.L / 2 - 0.5)
    y -= (lat.C - 1)
    y *= sqrt(3) / 2
    return (x, y)
end

"""
Physical coordinate of site `i` in the YC brick-wall embedding used in
`J1_J2_triangular_YC_gpu.jl`.

For generalized `m ≠ 0`, we keep the same local embedding and let `m` affect the
periodic identification and therefore the bond graph. This is sufficient for the
MPO-MPS construction and for ordering/localization along the open direction.
"""
function coord(lat::TriangularYC, i::Int)
    row = (i - 1) % lat.C
    col = (i - 1) ÷ lat.C
    x = col
    y = row
    if isodd(col)
        y += 0.5
    end
    x -= (lat.L / 2 - 1)
    y -= (lat.C - 1 + 0.5)
    x *= sqrt(3) / 2
    return (x, y)
end

xcoords(lat::AbstractTriangularCylinder) = [coord(lat, i)[1] for i in 1:nsite(lat)]

chaincoords(lat::AbstractTriangularCylinder) = Float64.(collect(1:nsite(lat)))

function localization_positions(
    lat::AbstractTriangularCylinder;
    coordinate::Symbol = :mps,
)
    if coordinate == :mps || coordinate == :site || coordinate == :chain
        return chaincoords(lat)
    elseif coordinate == :x
        return xcoords(lat)
    else
        error("Unknown localization coordinate = $coordinate; expected :mps or :x")
    end
end

function spinful_localization_positions(
    lat::AbstractTriangularCylinder;
    coordinate::Symbol = :mps,
)
    xs = localization_positions(lat; coordinate=coordinate)
    out = Vector{Float64}(undef, 2 * length(xs))
    for j in eachindex(xs)
        out[2j - 1] = xs[j]
        out[2j] = xs[j]
    end
    return out
end

# ------------------------------------------------------------------
# Bond generation
# ------------------------------------------------------------------

function _nn_bonds_meta(lat::TriangularXC)
    bonds = NamedTuple[]
    for col in 0:(lat.L - 1)
        for row in 0:(lat.C - 1)
            i = ind(lat, row, col)

            t = _wrapped_target(lat, row + 1, col)
            if !isnothing(t)
                push!(bonds, (i=i, j=t.i, kind=:vert, row=row, col=col, winding=t.winding))
            end

            if col < lat.L - 1
                t = _wrapped_target(lat, row, col + 1)
                if !isnothing(t)
                    push!(bonds, (i=i, j=t.i, kind=:horiz, row=row, col=col, winding=t.winding))
                end

                if isodd(row)
                    t = _wrapped_target(lat, row + 1, col + 1)
                    if !isnothing(t)
                        push!(bonds, (i=i, j=t.i, kind=:diag_up, row=row, col=col, winding=t.winding))
                    end
                    t = _wrapped_target(lat, row - 1, col + 1)
                    if !isnothing(t)
                        push!(bonds, (i=i, j=t.i, kind=:diag_down, row=row, col=col, winding=t.winding))
                    end
                end
            end
        end
    end
    return bonds
end

function _nn_bonds_meta(lat::TriangularYC)
    bonds = NamedTuple[]
    for col in 0:(lat.L - 1)
        for row in 0:(lat.C - 1)
            i = ind(lat, row, col)

            t = _wrapped_target(lat, row + 1, col)
            if !isnothing(t)
                push!(bonds, (i=i, j=t.i, kind=:vert, row=row, col=col, winding=t.winding))
            end

            if col < lat.L - 1
                t = _wrapped_target(lat, row, col + 1)
                if !isnothing(t)
                    push!(bonds, (i=i, j=t.i, kind=:horiz, row=row, col=col, winding=t.winding))
                end

                if iseven(col)
                    t = _wrapped_target(lat, row - 1, col + 1)
                    if !isnothing(t)
                        push!(bonds, (i=i, j=t.i, kind=:diag_even, row=row, col=col, winding=t.winding))
                    end
                else
                    t = _wrapped_target(lat, row + 1, col + 1)
                    if !isnothing(t)
                        push!(bonds, (i=i, j=t.i, kind=:diag_odd, row=row, col=col, winding=t.winding))
                    end
                end
            end
        end
    end
    return bonds
end

function _nnn_bonds_meta(lat::TriangularXC)
    bonds = NamedTuple[]
    for col in 0:(lat.L - 1)
        for row in 0:(lat.C - 1)
            i = ind(lat, row, col)

            t = _wrapped_target(lat, row + 2, col)
            if !isnothing(t)
                push!(bonds, (i=i, j=t.i, kind=:vert2, row=row, col=col, winding=t.winding))
            end

            if (col < lat.L - 1) && iseven(row)
                t = _wrapped_target(lat, row + 1, col + 1)
                if !isnothing(t)
                    push!(bonds, (i=i, j=t.i, kind=:diag2_up, row=row, col=col, winding=t.winding))
                end
                t = _wrapped_target(lat, row - 1, col + 1)
                if !isnothing(t)
                    push!(bonds, (i=i, j=t.i, kind=:diag2_down, row=row, col=col, winding=t.winding))
                end
            elseif (col < lat.L - 2) && isodd(row)
                t = _wrapped_target(lat, row + 1, col + 2)
                if !isnothing(t)
                    push!(bonds, (i=i, j=t.i, kind=:diag2_up2, row=row, col=col, winding=t.winding))
                end
                t = _wrapped_target(lat, row - 1, col + 2)
                if !isnothing(t)
                    push!(bonds, (i=i, j=t.i, kind=:diag2_down2, row=row, col=col, winding=t.winding))
                end
            end
        end
    end
    return bonds
end

function _nnn_bonds_meta(lat::TriangularYC)
    bonds = NamedTuple[]
    for col in 0:(lat.L - 1)
        for row in 0:(lat.C - 1)
            i = ind(lat, row, col)

            if col < lat.L - 1
                if iseven(col)
                    t = _wrapped_target(lat, row + 1, col + 1)
                    if !isnothing(t)
                        push!(bonds, (i=i, j=t.i, kind=:diag2_even_up, row=row, col=col, winding=t.winding))
                    end
                    t = _wrapped_target(lat, row - 2, col + 1)
                    if !isnothing(t)
                        push!(bonds, (i=i, j=t.i, kind=:diag2_even_down, row=row, col=col, winding=t.winding))
                    end
                else
                    t = _wrapped_target(lat, row + 2, col + 1)
                    if !isnothing(t)
                        push!(bonds, (i=i, j=t.i, kind=:diag2_odd_up, row=row, col=col, winding=t.winding))
                    end
                    t = _wrapped_target(lat, row - 1, col + 1)
                    if !isnothing(t)
                        push!(bonds, (i=i, j=t.i, kind=:diag2_odd_down, row=row, col=col, winding=t.winding))
                    end
                end
            end

            if col < lat.L - 2
                t = _wrapped_target(lat, row, col + 2)
                if !isnothing(t)
                    push!(bonds, (i=i, j=t.i, kind=:horiz2, row=row, col=col, winding=t.winding))
                end
            end
        end
    end
    return bonds
end

"""
Nearest-neighbor bonds for the triangular cylinder.

Each bond is returned as `(i, j, kind, row, col)` where `kind` labels the local
bond type and `(row,col)` refers to the origin site before the `ind(...)` mapping.
"""
function nn_bonds(lat::AbstractTriangularCylinder)
    return [(b.i, b.j, b.kind, b.row, b.col) for b in _nn_bonds_meta(lat)]
end

"""
Next-nearest-neighbor bonds for the triangular cylinder.

Each bond is returned as `(i, j, kind, row, col)`.
"""
function nnn_bonds(lat::AbstractTriangularCylinder)
    return [(b.i, b.j, b.kind, b.row, b.col) for b in _nnn_bonds_meta(lat)]
end

# ------------------------------------------------------------------
# Mean-field building blocks
# ------------------------------------------------------------------

spinup_index(site::Int) = 2 * site - 1
spindn_index(site::Int) = 2 * site

function add_mu!(h::AbstractMatrix{ComplexF64}, μ::Real)
    Ns = size(h, 1) ÷ 2
    for i in 1:Ns
        iu = spinup_index(i)
        id = spindn_index(i)
        h[iu, iu] += -μ
        h[id, id] += -μ
    end
    return h
end

function add_spin_symmetric_hopping!(
    h::AbstractMatrix{ComplexF64},
    i::Int,
    j::Int,
    tij::ComplexF64,
)
    iu = spinup_index(i)
    id = spindn_index(i)
    ju = spinup_index(j)
    jd = spindn_index(j)

    h[iu, ju] += tij
    h[ju, iu] += conj(tij)
    h[id, jd] += tij
    h[jd, id] += conj(tij)
    return h
end

function add_spin_resolved_hopping!(
    h::AbstractMatrix{ComplexF64},
    i::Int,
    j::Int,
    tij_up::ComplexF64,
    tij_dn::ComplexF64,
)
    iu = spinup_index(i)
    id = spindn_index(i)
    ju = spinup_index(j)
    jd = spindn_index(j)

    h[iu, ju] += tij_up
    h[ju, iu] += conj(tij_up)
    h[id, jd] += tij_dn
    h[jd, id] += conj(tij_dn)
    return h
end

"""
Add a real/complex singlet pairing amplitude on bond `(i,j)` in the spinful
orbital basis `[1↑,1↓,2↑,2↓,...]`.
"""
function add_singlet_pairing!(
    Δ::AbstractMatrix{ComplexF64},
    i::Int,
    j::Int,
    amp::ComplexF64,
)
    iu = spinup_index(i)
    id = spindn_index(i)
    ju = spinup_index(j)
    jd = spindn_index(j)

    if i == j
        Δ[iu, id] += amp
        Δ[id, iu] -= amp
    else
        Δ[iu, jd] += amp
        Δ[id, ju] -= amp
        Δ[ju, id] -= amp
        Δ[jd, iu] += amp
    end
    return Δ
end

function pi_flux_sign_xc(row::Int, kind::Symbol)
    if kind == :horiz && isodd(row)
        return -1.0
    else
        return 1.0
    end
end

function pi_flux_sign_yc(col::Int, kind::Symbol)
    if kind == :vert && isodd(col)
        return -1.0
    else
        return 1.0
    end
end

function bond_sign(
    lat::AbstractTriangularCylinder,
    kind::Symbol,
    row::Int,
    col::Int;
    gauge::Symbol = :auto,
)
    if gauge == :auto
        gauge = lat isa TriangularXC ? :xc_half_triangle : :yc_half_triangle
    end
    if gauge == :uniform
        return 1.0
    elseif gauge == :xc_half_triangle
        lat isa TriangularXC || error(":xc_half_triangle gauge is only defined for TriangularXC")
        return pi_flux_sign_xc(row, kind)
    elseif gauge == :yc_half_triangle
        lat isa TriangularYC || error(":yc_half_triangle gauge is only defined for TriangularYC")
        return pi_flux_sign_yc(col, kind)
    else
        error("Unknown gauge = $gauge")
    end
end

boundary_twist_phase(winding::Integer, θ::Real, ϕ::Real, spin::Symbol) =
    spin === :up ? cis(winding * (ϕ + θ / 2)) : cis(winding * (ϕ - θ / 2))

pair_twist_phase(winding::Integer, ϕ::Real) = cis(2 * winding * ϕ)

"""
Spin-rotation-invariant U(1) Dirac/π-flux parent state on the triangular cylinder.

Returns the *site-only* hopping matrix `h0` (size `Ns x Ns`) for one spin species.
To include distinct up/down boundary twists, use `build_u1_dsl_spin_hoppings`.
"""
function build_u1_dsl_hopping(
    lat::AbstractTriangularCylinder;
    t1::Real = 1.0,
    t2::Real = 0.0,
    μ::Real = 0.0,
    gauge::Symbol = :auto,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    Ns = nsite(lat)
    vprintln(verbose, @sprintf("[build_u1_dsl_hopping] Building one-spin U(1) hopping matrix on %s with C=%d, L=%d, Ns=%d",
        string(typeof(lat)), lat.C, lat.L, Ns))
    if lat isa TriangularYC
        vprintln(verbose, @sprintf("[build_u1_dsl_hopping] YC shift m = %d", lat.m))
    end
    vprintln(verbose, @sprintf("[build_u1_dsl_hopping] Parameters: t1=%.6f, t2=%.6f, mu=%.6f, gauge=%s", t1, t2, μ, String(gauge)))
    h0 = zeros(ComplexF64, Ns, Ns)

    for i in 1:Ns
        h0[i, i] += -μ
    end

    nbonds1 = _nn_bonds_meta(lat)
    vprintln(verbose, @sprintf("[build_u1_dsl_hopping] Adding %d NN bonds", length(nbonds1)))
    for b in nbonds1
        s = bond_sign(lat, b.kind, b.row, b.col; gauge=gauge)
        tij = ComplexF64(t1 * s)
        h0[b.i, b.j] += tij
        h0[b.j, b.i] += conj(tij)
    end

    if abs(t2) > 0
        nbonds2 = _nnn_bonds_meta(lat)
        vprintln(verbose, @sprintf("[build_u1_dsl_hopping] Adding %d NNN bonds", length(nbonds2)))
        for b in nbonds2
            h0[b.i, b.j] += ComplexF64(t2)
            h0[b.j, b.i] += ComplexF64(t2)
        end
    end

    vprintln(verbose, @sprintf("[build_u1_dsl_hopping] Done. Hermiticity check ||h-h^dag|| = %.3e", norm(h0 - h0')))
    return h0
end

"""
Spin-resolved U(1) Dirac/π-flux parent state including a spin twist `theta` and
an emergent gauge flux `phi` through the cylinder.

The seam-crossing hopping amplitudes pick up the phases
`exp(i * winding * (phi ± theta/2))` for spin up/down, matching the
boundary-condition structure discussed in He et al. (2017).
"""
function build_u1_dsl_spin_hoppings(
    lat::AbstractTriangularCylinder;
    t1::Real = 1.0,
    t2::Real = 0.0,
    μ::Real = 0.0,
    theta::Real = 0.0,
    phi::Real = 0.0,
    gauge::Symbol = :auto,
    verbose::Bool = true,
)
    Ns = nsite(lat)
    vprintln(verbose, @sprintf("[build_u1_dsl_spin_hoppings] Building spin-resolved U(1) hoppings on %s with C=%d, L=%d, Ns=%d",
        string(typeof(lat)), lat.C, lat.L, Ns))
    if lat isa TriangularYC
        vprintln(verbose, @sprintf("[build_u1_dsl_spin_hoppings] YC shift m = %d", lat.m))
    end
    vprintln(verbose, @sprintf("[build_u1_dsl_spin_hoppings] Parameters: t1=%.6f, t2=%.6f, mu=%.6f, theta=%.6f, phi=%.6f, gauge=%s",
        t1, t2, μ, theta, phi, String(gauge)))

    h_up = zeros(ComplexF64, Ns, Ns)
    h_dn = zeros(ComplexF64, Ns, Ns)
    for i in 1:Ns
        h_up[i, i] += -μ
        h_dn[i, i] += -μ
    end

    nbonds1 = _nn_bonds_meta(lat)
    vprintln(verbose, @sprintf("[build_u1_dsl_spin_hoppings] Adding %d NN bonds", length(nbonds1)))
    for b in nbonds1
        s = bond_sign(lat, b.kind, b.row, b.col; gauge=gauge)
        pup = boundary_twist_phase(b.winding, theta, phi, :up)
        pdn = boundary_twist_phase(b.winding, theta, phi, :down)
        tij_up = ComplexF64(t1 * s * pup)
        tij_dn = ComplexF64(t1 * s * pdn)
        h_up[b.i, b.j] += tij_up
        h_up[b.j, b.i] += conj(tij_up)
        h_dn[b.i, b.j] += tij_dn
        h_dn[b.j, b.i] += conj(tij_dn)
    end

    if abs(t2) > 0
        nbonds2 = _nnn_bonds_meta(lat)
        vprintln(verbose, @sprintf("[build_u1_dsl_spin_hoppings] Adding %d NNN bonds", length(nbonds2)))
        for b in nbonds2
            pup = boundary_twist_phase(b.winding, theta, phi, :up)
            pdn = boundary_twist_phase(b.winding, theta, phi, :down)
            tij_up = ComplexF64(t2 * pup)
            tij_dn = ComplexF64(t2 * pdn)
            h_up[b.i, b.j] += tij_up
            h_up[b.j, b.i] += conj(tij_up)
            h_dn[b.i, b.j] += tij_dn
            h_dn[b.j, b.i] += conj(tij_dn)
        end
    end

    vprintln(verbose, @sprintf("[build_u1_dsl_spin_hoppings] Done. Hermiticity checks ||h↑-h↑^dag|| = %.3e, ||h↓-h↓^dag|| = %.3e",
        norm(h_up - h_up'), norm(h_dn - h_dn')))
    return h_up, h_dn
end

"""
Z2 state #1 of Lu 2016 (dual to the bosonic 0-flux Schwinger-boson ansatz).

This is implemented as a practical symmetric representative:
- uniform NN hopping `t1`
- optional NNN hopping `t2`
- onsite chemical potential `μ`
- real singlet pairings on onsite / NN / NNN with amplitudes `Δ0, Δ1, Δ2`

A seam-crossing bond picks up `exp(i*(phi ± theta/2))` in the hopping channel.
For the singlet pairing channel the spin flux cancels, while the gauge flux enters
as `exp(i*2phi)`. For the Z2 sectors of interest, `phi = 0` or `π`, so the pair
amplitude remains unchanged.
"""
function build_z2_0flux_bdg(
    lat::AbstractTriangularCylinder;
    t1::Real = 1.0,
    t2::Real = 0.0,
    μ::Real = 0.0,
    Δ0::Real = 0.0,
    Δ1::Real = 0.25,
    Δ2::Real = 0.0,
    theta::Real = 0.0,
    phi::Real = 0.0,
    verbose::Bool = true,
)
    Ns = nsite(lat)
    vprintln(verbose, @sprintf("[build_z2_0flux_bdg] Building Z2 #1 BdG matrices on %s with C=%d, L=%d, Ns=%d",
        string(typeof(lat)), lat.C, lat.L, Ns))
    if lat isa TriangularYC
        vprintln(verbose, @sprintf("[build_z2_0flux_bdg] YC shift m = %d", lat.m))
    end
    vprintln(verbose, @sprintf("[build_z2_0flux_bdg] Parameters: t1=%.6f, t2=%.6f, mu=%.6f, Δ0=%.6f, Δ1=%.6f, Δ2=%.6f, theta=%.6f, phi=%.6f",
        t1, t2, μ, Δ0, Δ1, Δ2, theta, phi))
    h = zeros(ComplexF64, 2 * Ns, 2 * Ns)
    Δ = zeros(ComplexF64, 2 * Ns, 2 * Ns)

    add_mu!(h, μ)

    nbonds1 = _nn_bonds_meta(lat)
    vprintln(verbose, @sprintf("[build_z2_0flux_bdg] Adding %d NN bonds", length(nbonds1)))
    for b in nbonds1
        pup = boundary_twist_phase(b.winding, theta, phi, :up)
        pdn = boundary_twist_phase(b.winding, theta, phi, :down)
        add_spin_resolved_hopping!(h, b.i, b.j, ComplexF64(t1 * pup), ComplexF64(t1 * pdn))
        if abs(Δ1) > 0
            add_singlet_pairing!(Δ, b.i, b.j, ComplexF64(Δ1 * pair_twist_phase(b.winding, phi)))
        end
    end

    if abs(t2) > 0 || abs(Δ2) > 0
        nbonds2 = _nnn_bonds_meta(lat)
        vprintln(verbose, @sprintf("[build_z2_0flux_bdg] Adding %d NNN bonds", length(nbonds2)))
        for b in nbonds2
            if abs(t2) > 0
                pup = boundary_twist_phase(b.winding, theta, phi, :up)
                pdn = boundary_twist_phase(b.winding, theta, phi, :down)
                add_spin_resolved_hopping!(h, b.i, b.j, ComplexF64(t2 * pup), ComplexF64(t2 * pdn))
            end
            if abs(Δ2) > 0
                add_singlet_pairing!(Δ, b.i, b.j, ComplexF64(Δ2 * pair_twist_phase(b.winding, phi)))
            end
        end
    end

    if abs(Δ0) > 0
        vprintln(verbose, "[build_z2_0flux_bdg] Adding onsite pairing on all sites")
        for i in 1:Ns
            add_singlet_pairing!(Δ, i, i, ComplexF64(Δ0))
        end
    end

    vprintln(verbose, @sprintf("[build_z2_0flux_bdg] Done. ||h-h^dag|| = %.3e, ||Δ+Δ^T|| = %.3e", norm(h - h'), norm(Δ + transpose(Δ))))
    return h, Δ
end

"""
Z2 state #20 of Lu 2016 (dual to the bosonic π-flux Schwinger-boson ansatz).

Practical symmetric representative:
- π-flux U(1) Dirac parent hopping with amplitude `tπ`
- onsite `τ^3` term as chemical potential `μ`
- symmetry-allowed real singlet NN pairing `Δ1`

This follows Lu's Table I and Sec. III.B: #20 is the unique symmetric,
fully gapped Z2 state in the neighborhood of the π-flux algebraic spin liquid.
"""
function build_z2_piflux_bdg(
    lat::AbstractTriangularCylinder;
    tπ::Real = 1.0,
    μ::Real = 0.0,
    Δ1::Real = 0.35,
    theta::Real = 0.0,
    phi::Real = 0.0,
    gauge::Symbol = :auto,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    Ns = nsite(lat)
    vprintln(verbose, @sprintf("[build_z2_piflux_bdg] Building Z2 #20 BdG matrices on %s with C=%d, L=%d, Ns=%d",
        string(typeof(lat)), lat.C, lat.L, Ns))
    if lat isa TriangularYC
        vprintln(verbose, @sprintf("[build_z2_piflux_bdg] YC shift m = %d", lat.m))
    end
    vprintln(verbose, @sprintf("[build_z2_piflux_bdg] Parameters: tπ=%.6f, mu=%.6f, Δ1=%.6f, theta=%.6f, phi=%.6f, gauge=%s",
        tπ, μ, Δ1, theta, phi, String(gauge)))
    h = zeros(ComplexF64, 2 * Ns, 2 * Ns)
    Δ = zeros(ComplexF64, 2 * Ns, 2 * Ns)

    add_mu!(h, μ)

    nbonds1 = _nn_bonds_meta(lat)
    vprintln(verbose, @sprintf("[build_z2_piflux_bdg] Adding %d NN bonds", length(nbonds1)))
    for b in nbonds1
        s = bond_sign(lat, b.kind, b.row, b.col; gauge=gauge)
        pup = boundary_twist_phase(b.winding, theta, phi, :up)
        pdn = boundary_twist_phase(b.winding, theta, phi, :down)
        add_spin_resolved_hopping!(h, b.i, b.j, ComplexF64(tπ * s * pup), ComplexF64(tπ * s * pdn))
        if abs(Δ1) > 0
            add_singlet_pairing!(Δ, b.i, b.j, ComplexF64(Δ1 * pair_twist_phase(b.winding, phi)))
        end
    end

    vprintln(verbose, @sprintf("[build_z2_piflux_bdg] Done. ||h-h^dag|| = %.3e, ||Δ+Δ^T|| = %.3e", norm(h - h'), norm(Δ + transpose(Δ))))
    return h, Δ
end

# ------------------------------------------------------------------
# Orbital localization and ordering
# ------------------------------------------------------------------

"""
Projected-position localization for a Slater determinant A where columns are
occupied single-particle orbitals in the *site* basis.
"""
function localize_slater_orbitals(
    A::AbstractMatrix{ComplexF64},
    xpos::AbstractVector{<:Real},
)
    Xproj = A' * Diagonal(ComplexF64.(xpos)) * A
    loc = eigen(Hermitian((Xproj + Xproj') / 2))
    A_loc = A * loc.vectors
    return A_loc, real(loc.values)
end

"""
Projected-position localization for BdG quasihole columns `[V; U]`, using the
particle-hole symmetric projected position matrix
X̃ = V† X V + U† X U.
"""
function localize_bdg_modes(
    V::AbstractMatrix{ComplexF64},
    U::AbstractMatrix{ComplexF64},
    xpos_spinful::AbstractVector{<:Real},
)
    X = Diagonal(ComplexF64.(xpos_spinful))
    Xproj = V' * X * V + U' * X * U
    loc = eigen(Hermitian((Xproj + Xproj') / 2))
    return V * loc.vectors, U * loc.vectors, real(loc.values)
end

"""
Left-meet-right ordering used in the MPO-MPS literature:
leftmost mode, rightmost mode, second-leftmost, second-rightmost, ...
"""
function left_meet_right_order(centers::AbstractVector{<:Real})
    p = sortperm(collect(centers))
    out = Int[]
    i = 1
    j = length(p)
    while i <= j
        push!(out, p[i])
        if i < j
            push!(out, p[j])
        end
        i += 1
        j -= 1
    end
    return out
end

strip_index(lat::AbstractTriangularCylinder, site::Int) = mod(site - 1, lat.C) + 1

function dominant_strip_labels(
    lat::AbstractTriangularCylinder,
    mode_weights::AbstractMatrix{<:Number},
)
    Ns = nsite(lat)
    @assert size(mode_weights, 1) == Ns
    nmode = size(mode_weights, 2)
    strip_weights = zeros(Float64, lat.C, nmode)
    for site in 1:Ns
        strip = strip_index(lat, site)
        for m in 1:nmode
            strip_weights[strip, m] += abs2(mode_weights[site, m])
        end
    end
    return [argmax(view(strip_weights, :, m)) for m in 1:nmode]
end

function strip_by_strip_order(
    lat::AbstractTriangularCylinder,
    centers::AbstractVector{<:Real},
    strip_labels::AbstractVector{<:Integer},
)
    length(centers) == length(strip_labels) || error("Need one strip label per mode")
    out = Int[]
    for strip in 1:lat.C
        modes = findall(==(strip), strip_labels)
        isempty(modes) && continue
        local_ord = left_meet_right_order(centers[modes])
        append!(out, modes[local_ord])
    end
    return out
end

function resolve_mode_order(
    lat::AbstractTriangularCylinder,
    ordering::Symbol,
    centers::AbstractVector{<:Real};
    strip_labels::Union{Nothing,AbstractVector{<:Integer}} = nothing,
)
    if ordering == :left_meet_right
        return left_meet_right_order(centers)
    elseif ordering == :strip_by_strip || ordering == :strip_left_meet_right
        isnothing(strip_labels) && error("ordering=$ordering requires strip labels")
        return strip_by_strip_order(lat, centers, strip_labels)
    else
        return collect(1:length(centers))
    end
end

# ------------------------------------------------------------------
# MPO for a generic odd fermionic mode
# ------------------------------------------------------------------

"""
Build the bond-dimension-2 MPO for a generic fermionic mode operator

d† = Σ_j [u↑[j] c†_{j↑} + u↓[j] c†_{j↓} + v↑[j] c_{j↑} + v↓[j] c_{j↓}]

using the standard Jordan-Wigner-string form
(0 1) ∏_j [[I,0],[O_j,F_j]] (1 0)^T.

The input `sites` must be ITensors `"Electron"` sites.
"""
function linear_mode_mpo(
    sites::Vector{<:Index};
    u_up::AbstractVector{<:Number},
    u_dn::AbstractVector{<:Number},
    v_up::AbstractVector{<:Number} = zeros(ComplexF64, length(sites)),
    v_dn::AbstractVector{<:Number} = zeros(ComplexF64, length(sites)),
)
    N = length(sites)
    @assert length(u_up) == N
    @assert length(u_dn) == N
    @assert length(v_up) == N
    @assert length(v_dn) == N

    W = MPO(N)

    if N == 1
        s = sites[1]
        O1 = ComplexF64(u_up[1]) * op("Cdagup", s) +
             ComplexF64(u_dn[1]) * op("Cdagdn", s) +
             ComplexF64(v_up[1]) * op("Cup", s) +
             ComplexF64(v_dn[1]) * op("Cdn", s)
        W[1] = O1
        return W
    end

    links = [Index(2, "mode-link,$j") for j in 1:(N - 1)]

    for j in 1:N
        s = sites[j]
        sp = prime(s)

        Oj = ComplexF64(u_up[j]) * op("Cdagup", s) +
             ComplexF64(u_dn[j]) * op("Cdagdn", s) +
             ComplexF64(v_up[j]) * op("Cup", s) +
             ComplexF64(v_dn[j]) * op("Cdn", s)
        Fj = op("F", s)
        Idj = op("Id", s)

        if j == 1
            r = links[1]
            T = ITensor(ComplexF64, sp, s, r)
            T += Oj * onehot(r => 1)
            T += Fj * onehot(r => 2)
            W[j] = T
        elseif j == N
            l = links[N - 1]
            T = ITensor(ComplexF64, sp, s, l)
            T += Idj * onehot(l => 1)
            T += Oj * onehot(l => 2)
            W[j] = T
        else
            l = links[j - 1]
            r = links[j]
            T = ITensor(ComplexF64, sp, s, l, r)
            T += Idj * onehot(l => 1, r => 1)
            T += Oj * onehot(l => 2, r => 1)
            T += Fj * onehot(l => 2, r => 2)
            W[j] = T
        end
    end

    return W
end

function drop_site_primes!(psi::MPS)
    for j in 1:length(psi)
        psi[j] = noprime(psi[j])
    end
    return psi
end

function apply_mode!(
    psi::MPS,
    W::MPO;
    cutoff::Real = 1e-10,
    maxdim::Int = 2000,
    alg = "densitymatrix",
    normalize_each_step::Bool = true,
    verbose::Bool = true,
    label::AbstractString = "mode",
)
    vprintln(verbose, @sprintf("[apply_mode!] Applying %s with alg=%s, cutoff=%.1e, maxdim=%d", label, string(alg), cutoff, maxdim))
    vlog_state_summary(verbose, psi, label * " before")
    psi = apply(W, psi; alg=alg, cutoff=cutoff, maxdim=maxdim)
    drop_site_primes!(psi)
    if normalize_each_step
        normalize!(psi)
        vprintln(verbose, @sprintf("[apply_mode!] Normalized state after %s", label))
    end
    vlog_state_summary(verbose, psi, label * " after")
    return psi
end

function apply_mode_pair!(
    psi::MPS,
    W1::MPO,
    W2::MPO;
    cutoff::Real = 1e-10,
    maxdim::Int = 2000,
    alg = "densitymatrix",
    normalize_each_step::Bool = true,
    verbose::Bool = true,
    label1::AbstractString = "mode 1",
    label2::AbstractString = "mode 2",
    pair_label::AbstractString = "mode pair",
)
    if alg != "naive"
        psi = apply_mode!(
            psi,
            W1;
            cutoff=cutoff,
            maxdim=maxdim,
            alg=alg,
            normalize_each_step=normalize_each_step,
            verbose=verbose,
            label=label1,
        )
        psi = apply_mode!(
            psi,
            W2;
            cutoff=cutoff,
            maxdim=maxdim,
            alg=alg,
            normalize_each_step=normalize_each_step,
            verbose=verbose,
            label=label2,
        )
        return psi
    end

    vprintln(verbose, @sprintf("[apply_mode_pair!] Applying %s and %s with alg=%s, cutoff=%.1e, maxdim=%d", label1, label2, string(alg), cutoff, maxdim))
    vlog_state_summary(verbose, psi, pair_label * " before")
    psi = apply(W1, psi; alg=alg, truncate=false)
    drop_site_primes!(psi)
    psi = apply(W2, psi; alg=alg, truncate=false)
    drop_site_primes!(psi)
    truncate!(psi; cutoff=cutoff, maxdim=maxdim)
    if normalize_each_step
        normalize!(psi)
        vprintln(verbose, @sprintf("[apply_mode_pair!] Normalized state after %s", pair_label))
    end
    vlog_state_summary(verbose, psi, pair_label * " after")
    return psi
end

# ------------------------------------------------------------------
# Gutzwiller projection
# ------------------------------------------------------------------

"""
Project an MPS on `"Electron"` sites into the singly-occupied physical spin-1/2
subspace and map it to `"S=1/2"` sites.

Local map:
|Up⟩   -> |Up⟩
|Dn⟩   -> |Dn⟩
|Emp⟩  -> 0
|UpDn⟩ -> 0
"""
function project_electron_tensor_to_spin(A::ITensor, s_e::Index, s_s::Index)
    hasind(A, s_e) || error("project_electron_tensor_to_spin expected the electron site index to be present in the tensor.")

    P = ITensor(ComplexF64, s_s, s_e)
    P[s_s => "Up", s_e => "Up"] = 1
    P[s_s => "Dn", s_e => "Dn"] = 1

    others = [i for i in inds(A) if i != s_e]
    return permute(P * A, s_s, others...)
end

function resolve_spin_sites(
    N::Int;
    spin_sites::Union{Nothing,AbstractVector{<:Index}} = nothing,
    verbose::Bool = true,
)
    if isnothing(spin_sites)
        vprintln(verbose, @sprintf("[resolve_spin_sites] Creating fresh S=1/2 site indices for N=%d", N))
        return siteinds("S=1/2", N; conserve_qns=false)
    end

    length(spin_sites) == N || error("Provided spin_sites has length $(length(spin_sites)) but expected $N.")
    for (j, s) in enumerate(spin_sites)
        dim(s) == 2 || error("Provided spin_sites[$j] has dimension $(dim(s)), expected 2 for S=1/2 sites.")
    end
    vprintln(verbose, "[resolve_spin_sites] Using caller-provided spin site indices")
    return collect(spin_sites)
end

function gutzwiller_project_to_spin(
    psi_e::MPS,
    elec_sites::Vector{<:Index};
    spin_sites::Union{Nothing,AbstractVector{<:Index}} = nothing,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    N = length(elec_sites)
    vprintln(verbose, @sprintf("[gutzwiller_project_to_spin] Projecting %d electron sites to spin-1/2", N))
    spin_sites = resolve_spin_sites(N; spin_sites=spin_sites, verbose=verbose)

    if use_cuda
        vprintln(verbose, "[gutzwiller_project_to_spin] Moving electron MPS to CPU for local projection")
    end
    psi_e_cpu = to_device(psi_e; use_cuda=false, verbose=false, label="electron MPS for projection")

    psi_s = MPS(spin_sites)
    for j in 1:N
        vprintln(verbose, @sprintf("[gutzwiller_project_to_spin] Projecting site %d/%d", j, N))
        psi_s[j] = project_electron_tensor_to_spin(psi_e_cpu[j], elec_sites[j], spin_sites[j])
    end
    psi_s = to_device(psi_s; use_cuda=use_cuda, verbose=verbose, label="projected spin MPS")
    normalize!(psi_s)
    vlog_state_summary(verbose, psi_s, "gutzwiller projected spin state")
    return psi_s, spin_sites
end

# ------------------------------------------------------------------
# Slater determinant preparation
# ------------------------------------------------------------------

function prepare_slater_electron_mps(
    lat::AbstractTriangularCylinder,
    h0::AbstractMatrix{ComplexF64};
    localize::Bool = true,
    localize_coordinate::Symbol = :mps,
    ordering::Symbol = :left_meet_right,
    cutoff::Real = 1e-10,
    maxdim::Int = 2000,
    normalize_each_step::Bool = true,
    mode_apply_alg::Union{Nothing,Symbol,AbstractString} = nothing,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    Ns = nsite(lat)
    vprintln(verbose, @sprintf("[prepare_slater_electron_mps] Preparing Slater MPS on %s with C=%d, L=%d, Ns=%d", string(typeof(lat)), lat.C, lat.L, Ns))
    @assert size(h0, 1) == Ns && size(h0, 2) == Ns
    @assert iseven(Ns) "Need an even number of sites for the spin-singlet half-filled U(1) state."

    nfill = Ns ÷ 2

    vprintln(verbose, "[prepare_slater_electron_mps] Diagonalizing one-body Hamiltonian")
    eig = eigen(Hermitian((h0 + h0') / 2))
    p = sortperm(real(eig.values))
    A = Matrix{ComplexF64}(eig.vectors[:, p[1:nfill]])

    locpos = localization_positions(lat; coordinate=localize_coordinate)
    centers = copy(locpos[1:nfill])
    if localize
        vprintln(verbose, "[prepare_slater_electron_mps] Localizing occupied orbitals by projected position in $(localize_coordinate) coordinates")
        A, centers = localize_slater_orbitals(A, locpos)
    else
        centers = [real(dot(A[:, m], Diagonal(locpos) * A[:, m])) for m in 1:nfill]
    end

    strip_labels = dominant_strip_labels(lat, A)
    ord = resolve_mode_order(lat, ordering, centers; strip_labels=strip_labels)
    vprintln(verbose, @sprintf("[prepare_slater_electron_mps] nfill per spin = %d", nfill))
    vprintln(verbose, "[prepare_slater_electron_mps] Orbital application order = $(ord)")
    vprintln(verbose, "[prepare_slater_electron_mps] Orbital strip labels = $(strip_labels)")

    resolved_mode_apply_alg = resolve_mode_apply_alg(
        mode_apply_alg;
        verbose=verbose,
        label="prepare_slater_electron_mps",
    )
    elec_sites = siteinds("Electron", Ns; conserve_qns=false)
    psi = MPS(elec_sites, fill("Emp", Ns))
    psi = to_device(psi; use_cuda=use_cuda, verbose=verbose, label="initial Slater electron MPS")
    vlog_state_summary(verbose, psi, "initial electron vacuum")

    zerosN = zeros(ComplexF64, Ns)
    for (k, m) in enumerate(ord)
        vprintln(verbose, @sprintf("[prepare_slater_electron_mps] Filling orbital %d/%d (mode index %d, center=%.6f in %s coordinates)", k, length(ord), m, centers[m], String(localize_coordinate)))
        coeff = A[:, m]

        Wup = linear_mode_mpo(
            elec_sites;
            u_up=coeff,
            u_dn=zerosN,
            v_up=zerosN,
            v_dn=zerosN,
        )
        Wup = to_device(Wup; use_cuda=use_cuda, verbose=verbose, label=@sprintf("Slater orbital %d/%d spin-up MPO", k, length(ord)))
        Wdn = linear_mode_mpo(
            elec_sites;
            u_up=zerosN,
            u_dn=coeff,
            v_up=zerosN,
            v_dn=zerosN,
        )
        Wdn = to_device(Wdn; use_cuda=use_cuda, verbose=verbose, label=@sprintf("Slater orbital %d/%d spin-down MPO", k, length(ord)))
        psi = apply_mode_pair!(
            psi,
            Wup,
            Wdn;
            cutoff=cutoff,
            maxdim=maxdim,
            alg=resolved_mode_apply_alg,
            normalize_each_step=normalize_each_step,
            verbose=verbose,
            label1=@sprintf("Slater orbital %d/%d spin-up", k, length(ord)),
            label2=@sprintf("Slater orbital %d/%d spin-down", k, length(ord)),
            pair_label=@sprintf("Slater orbital %d/%d pair", k, length(ord)),
        )
    end

    vlog_state_summary(verbose, psi, "final Slater electron state")
    return psi, elec_sites, Dict(
        :occupied_orbitals => A,
        :centers => centers,
        :localize_coordinate => localize_coordinate,
        :strip_labels => strip_labels,
        :order => ord,
    )
end

function unpack_spinful_slater_mode(
    coeff::AbstractVector{<:Number},
    Ns::Int,
)
    u_up = zeros(ComplexF64, Ns)
    u_dn = zeros(ComplexF64, Ns)
    for j in 1:Ns
        u_up[j] = ComplexF64(coeff[spinup_index(j)])
        u_dn[j] = ComplexF64(coeff[spindn_index(j)])
    end
    return u_up, u_dn
end

function prepare_spin_resolved_slater_electron_mps(
    lat::AbstractTriangularCylinder,
    h_up::AbstractMatrix{ComplexF64},
    h_dn::AbstractMatrix{ComplexF64};
    localize::Bool = true,
    localize_coordinate::Symbol = :mps,
    ordering::Symbol = :left_meet_right,
    cutoff::Real = 1e-10,
    maxdim::Int = 2000,
    normalize_each_step::Bool = true,
    mode_apply_alg::Union{Nothing,Symbol,AbstractString} = nothing,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    Ns = nsite(lat)
    @assert size(h_up, 1) == Ns && size(h_up, 2) == Ns
    @assert size(h_dn, 1) == Ns && size(h_dn, 2) == Ns
    @assert iseven(Ns) "Need an even number of sites for the spin-singlet half-filled U(1) state."
    nfill = Ns ÷ 2

    vprintln(verbose, @sprintf("[prepare_spin_resolved_slater_electron_mps] Preparing spin-resolved Slater MPS on %s with C=%d, L=%d, Ns=%d", string(typeof(lat)), lat.C, lat.L, Ns))
    vprintln(verbose, @sprintf("[prepare_spin_resolved_slater_electron_mps] nfill↑ = nfill↓ = %d", nfill))

    if isapprox(h_up, h_dn; atol=1e-12, rtol=1e-10)
        vprintln(verbose, "[prepare_spin_resolved_slater_electron_mps] Up/down hopping matrices match; using the shared-orbital Slater builder for better numerical stability")
        shared_mode_apply_alg = mode_apply_alg
        if isnothing(shared_mode_apply_alg) && use_cuda
            shared_mode_apply_alg = "naive"
            vprintln(verbose, "[prepare_spin_resolved_slater_electron_mps] Shared spin sector on CUDA; using apply(...; alg=\"naive\") with one truncation per orbital pair to avoid the phi=pi density-matrix GPU instability")
        end
        psi, elec_sites, info0 = prepare_slater_electron_mps(
            lat,
            Matrix{ComplexF64}(h_up);
            localize=localize,
            localize_coordinate=localize_coordinate,
            ordering=ordering,
            cutoff=cutoff,
            maxdim=maxdim,
            normalize_each_step=normalize_each_step,
            mode_apply_alg=shared_mode_apply_alg,
            use_cuda=use_cuda,
            verbose=verbose,
        )

        A = Matrix{ComplexF64}(info0[:occupied_orbitals])
        centers = collect(info0[:centers])
        orbital_strip_labels = collect(info0[:strip_labels])
        orbital_order = collect(info0[:order])
        mode_metadata = NamedTuple[]
        mode_strip_labels = Int[]
        for m in orbital_order
            push!(mode_metadata, (spin=:up, mode=m, center=centers[m]))
            push!(mode_strip_labels, orbital_strip_labels[m])
            push!(mode_metadata, (spin=:dn, mode=m, center=centers[m]))
            push!(mode_strip_labels, orbital_strip_labels[m])
        end

        info = merge(
            info0,
            Dict(
                :occupied_orbitals_up => A,
                :occupied_orbitals_dn => copy(A),
                :centers_up => centers,
                :centers_dn => copy(centers),
                :localize_coordinate => localize_coordinate,
                :mode_strip_labels => mode_strip_labels,
                :mode_order => collect(1:length(mode_metadata)),
                :mode_metadata => mode_metadata,
                :shared_spin_sector => true,
            ),
        )
        return psi, elec_sites, info
    end

    eig_up = eigen(Hermitian((h_up + h_up') / 2))
    p_up = sortperm(real(eig_up.values))
    A_up = Matrix{ComplexF64}(eig_up.vectors[:, p_up[1:nfill]])

    eig_dn = eigen(Hermitian((h_dn + h_dn') / 2))
    p_dn = sortperm(real(eig_dn.values))
    A_dn = Matrix{ComplexF64}(eig_dn.vectors[:, p_dn[1:nfill]])

    locpos = localization_positions(lat; coordinate=localize_coordinate)
    if localize
        vprintln(verbose, "[prepare_spin_resolved_slater_electron_mps] Localizing occupied orbitals in each spin sector in $(localize_coordinate) coordinates")
        A_up, centers_up = localize_slater_orbitals(A_up, locpos)
        A_dn, centers_dn = localize_slater_orbitals(A_dn, locpos)
    else
        centers_up = [real(dot(A_up[:, m], Diagonal(locpos) * A_up[:, m])) for m in 1:nfill]
        centers_dn = [real(dot(A_dn[:, m], Diagonal(locpos) * A_dn[:, m])) for m in 1:nfill]
    end

    strip_labels_up = dominant_strip_labels(lat, A_up)
    strip_labels_dn = dominant_strip_labels(lat, A_dn)
    modes = NamedTuple[]
    mode_strip_labels = Int[]
    for m in 1:nfill
        push!(modes, (spin=:up, mode=m, center=centers_up[m]))
        push!(mode_strip_labels, strip_labels_up[m])
        push!(modes, (spin=:dn, mode=m, center=centers_dn[m]))
        push!(mode_strip_labels, strip_labels_dn[m])
    end
    ord = resolve_mode_order(lat, ordering, [m.center for m in modes]; strip_labels=mode_strip_labels)
    vprintln(verbose, "[prepare_spin_resolved_slater_electron_mps] Mode application order = $(ord)")
    vprintln(verbose, "[prepare_spin_resolved_slater_electron_mps] Mode strip labels = $(mode_strip_labels)")

    auto_mode_apply_alg = mode_apply_alg
    if isnothing(auto_mode_apply_alg) && use_cuda
        auto_mode_apply_alg = "naive"
        vprintln(verbose, "[prepare_spin_resolved_slater_electron_mps] CUDA spin-resolved mode applications are using apply(...; alg=\"naive\") because the density-matrix path becomes NaN for twisted spin sectors on this backend")
    end
    resolved_mode_apply_alg = resolve_mode_apply_alg(
        auto_mode_apply_alg;
        verbose=verbose,
        label="prepare_spin_resolved_slater_electron_mps",
    )
    elec_sites = siteinds("Electron", Ns; conserve_qns=false)
    psi = MPS(elec_sites, fill("Emp", Ns))
    psi = to_device(psi; use_cuda=use_cuda, verbose=verbose, label="initial spin-resolved electron MPS")
    vlog_state_summary(verbose, psi, "initial electron vacuum")

    zerosN = zeros(ComplexF64, Ns)
    for (k, idx) in enumerate(ord)
        mode = modes[idx]
        coeff = mode.spin === :up ? A_up[:, mode.mode] : A_dn[:, mode.mode]
        if mode.spin === :up
            u_up = ComplexF64.(coeff)
            u_dn = zerosN
        else
            u_up = zerosN
            u_dn = ComplexF64.(coeff)
        end
        W = linear_mode_mpo(
            elec_sites;
            u_up=u_up,
            u_dn=u_dn,
            v_up=zerosN,
            v_dn=zerosN,
        )
        W = to_device(W; use_cuda=use_cuda, verbose=verbose, label=@sprintf("spin-resolved Slater mode %d/%d MPO", k, length(ord)))
        psi = apply_mode!(
            psi,
            W;
            cutoff=cutoff,
            maxdim=maxdim,
            alg=resolved_mode_apply_alg,
            normalize_each_step=normalize_each_step,
            verbose=verbose,
            label=@sprintf("spin-resolved %s mode %d/%d (center=%.6f in %s coordinates)", String(mode.spin), k, length(ord), mode.center, String(localize_coordinate)),
        )
    end

    vlog_state_summary(verbose, psi, "final spin-resolved Slater electron state")
    return psi, elec_sites, Dict(
        :occupied_orbitals_up => A_up,
        :occupied_orbitals_dn => A_dn,
        :centers_up => centers_up,
        :centers_dn => centers_dn,
        :localize_coordinate => localize_coordinate,
        :mode_strip_labels => mode_strip_labels,
        :mode_order => ord,
        :mode_metadata => modes,
    )
end

# ------------------------------------------------------------------
# BdG preparation
# ------------------------------------------------------------------

"""
Diagonalize the BdG matrix
H_BdG = [ h   Δ
         -Δ* -hᵀ ]
and return the negative-energy quasihole columns `[V; U]`.
"""
function bdg_quasiholes(
    h::AbstractMatrix{ComplexF64},
    Δ::AbstractMatrix{ComplexF64};
    verbose::Bool = true,
)
    Ng = size(h, 1)
    @assert size(h, 2) == Ng
    @assert size(Δ, 1) == Ng && size(Δ, 2) == Ng

    vprintln(verbose, @sprintf("[bdg_quasiholes] Diagonalizing BdG matrix of size %d x %d on CPU", 2 * Ng, 2 * Ng))
    Hbdg = [h Δ; -conj(Δ) -transpose(h)]
    eig = eigen(Hermitian((Hbdg + Hbdg') / 2))
    p = sortperm(real(eig.values))
    neg = p[1:Ng]
    V = Matrix{ComplexF64}(eig.vectors[1:Ng, neg])
    U = Matrix{ComplexF64}(eig.vectors[(Ng + 1):(2 * Ng), neg])
    evals = real(eig.values[neg])
    vprintln(verbose, @sprintf("[bdg_quasiholes] Retained %d negative-energy quasiholes. Energy window: [%.6e, %.6e]", length(evals), minimum(evals), maximum(evals)))
    return evals, V, U
end

function unpack_spinful_mode(
    Vcol::AbstractVector{<:Number},
    Ucol::AbstractVector{<:Number},
    Ns::Int,
)
    u_up = zeros(ComplexF64, Ns)
    u_dn = zeros(ComplexF64, Ns)
    v_up = zeros(ComplexF64, Ns)
    v_dn = zeros(ComplexF64, Ns)
    for j in 1:Ns
        iu = spinup_index(j)
        id = spindn_index(j)
        u_up[j] = ComplexF64(Vcol[iu])
        u_dn[j] = ComplexF64(Vcol[id])
        v_up[j] = ComplexF64(Ucol[iu])
        v_dn[j] = ComplexF64(Ucol[id])
    end
    return u_up, u_dn, v_up, v_dn
end

function prepare_bdg_electron_mps(
    lat::AbstractTriangularCylinder,
    h::AbstractMatrix{ComplexF64},
    Δ::AbstractMatrix{ComplexF64};
    localize::Bool = true,
    localize_coordinate::Symbol = :mps,
    ordering::Symbol = :left_meet_right,
    cutoff::Real = 1e-10,
    maxdim::Int = 2000,
    normalize_each_step::Bool = true,
    mode_apply_alg::Union{Nothing,Symbol,AbstractString} = nothing,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    Ns = nsite(lat)
    Ng = 2 * Ns
    vprintln(verbose, @sprintf("[prepare_bdg_electron_mps] Preparing BdG MPS on %s with C=%d, L=%d, Ns=%d, spinful dimension=%d", string(typeof(lat)), lat.C, lat.L, Ns, Ng))
    @assert size(h, 1) == Ng && size(h, 2) == Ng
    @assert size(Δ, 1) == Ng && size(Δ, 2) == Ng

    evals, V, U = bdg_quasiholes(h, Δ; verbose=verbose)

    locpos_spinful = spinful_localization_positions(lat; coordinate=localize_coordinate)
    if localize
        vprintln(verbose, "[prepare_bdg_electron_mps] Localizing quasihole modes by projected position in $(localize_coordinate) coordinates")
        V, U, centers = localize_bdg_modes(V, U, locpos_spinful)
    else
        centers = [real(dot(V[:, m], Diagonal(locpos_spinful) * V[:, m]) +
                        dot(U[:, m], Diagonal(locpos_spinful) * U[:, m])) for m in 1:Ng]
    end

    site_weights = zeros(Float64, Ns, Ng)
    for j in 1:Ns
        iu = spinup_index(j)
        id = spindn_index(j)
        for m in 1:Ng
            site_weights[j, m] = abs2(V[iu, m]) + abs2(V[id, m]) + abs2(U[iu, m]) + abs2(U[id, m])
        end
    end
    strip_labels = dominant_strip_labels(lat, site_weights)
    ord = resolve_mode_order(lat, ordering, centers; strip_labels=strip_labels)
    vprintln(verbose, "[prepare_bdg_electron_mps] Quasihole application order = $(ord)")
    vprintln(verbose, "[prepare_bdg_electron_mps] Quasihole strip labels = $(strip_labels)")

    resolved_mode_apply_alg = resolve_mode_apply_alg(
        mode_apply_alg;
        verbose=verbose,
        label="prepare_bdg_electron_mps",
    )
    elec_sites = siteinds("Electron", Ns; conserve_qns=false)
    psi = MPS(elec_sites, fill("Emp", Ns))
    psi = to_device(psi; use_cuda=use_cuda, verbose=verbose, label="initial BdG electron MPS")
    vlog_state_summary(verbose, psi, "initial electron vacuum")

    for (k, m) in enumerate(ord)
        vprintln(verbose, @sprintf("[prepare_bdg_electron_mps] Applying quasihole %d/%d (mode index %d, center=%.6f in %s coordinates, E=%.6e)", k, length(ord), m, centers[m], String(localize_coordinate), evals[min(m, length(evals))]))
        u_up, u_dn, v_up, v_dn = unpack_spinful_mode(V[:, m], U[:, m], Ns)
        Wm = linear_mode_mpo(
            elec_sites;
            u_up=u_up,
            u_dn=u_dn,
            v_up=v_up,
            v_dn=v_dn,
        )
        Wm = to_device(Wm; use_cuda=use_cuda, verbose=verbose, label=@sprintf("BdG quasihole %d/%d MPO", k, length(ord)))
        psi = apply_mode!(
            psi,
            Wm;
            cutoff=cutoff,
            maxdim=maxdim,
            alg=resolved_mode_apply_alg,
            normalize_each_step=normalize_each_step,
            verbose=verbose,
            label=@sprintf("BdG quasihole %d/%d", k, length(ord)),
        )
    end

    vlog_state_summary(verbose, psi, "final BdG electron state")
    return psi, elec_sites, Dict(
        :quasihole_energies => evals,
        :V => V,
        :U => U,
        :centers => centers,
        :localize_coordinate => localize_coordinate,
        :strip_labels => strip_labels,
        :order => ord,
    )
end

# ------------------------------------------------------------------
# Public top-level constructors
# ------------------------------------------------------------------

"""
Prepare the U(1) Dirac/π-flux Gutzwiller-projected MPS on a triangular cylinder.

The optional `theta` and `phi` keywords implement the boundary-condition phases
for spinons around the cylinder seam:
- spin-up hopping sees `phi + theta/2`
- spin-down hopping sees `phi - theta/2`

For `theta = phi = 0`, the original spin-symmetric XC implementation is used.
"""
function prepare_u1_dsl_gutzwiller_mps(
    lat::AbstractTriangularCylinder;
    spin_sites::Union{Nothing,AbstractVector{<:Index}} = nothing,
    t1::Real = 1.0,
    t2::Real = 0.0,
    μ::Real = 0.0,
    theta::Real = 0.0,
    phi::Real = 0.0,
    localize::Bool = true,
    localize_coordinate::Symbol = :mps,
    ordering::Symbol = :left_meet_right,
    cutoff::Real = 1e-10,
    maxdim::Int = 2000,
    normalize_each_step::Bool = true,
    mode_apply_alg::Union{Nothing,Symbol,AbstractString} = nothing,
    gauge::Symbol = :auto,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    vprintln(verbose, "[prepare_u1_dsl_gutzwiller_mps] Starting U(1) DSL preparation")
    vprintln(verbose, "[prepare_u1_dsl_gutzwiller_mps] Execution device for MPS/MPO contractions: " * (use_cuda ? (_HAS_CUDA ? "CUDA GPU" : "CUDA requested but unavailable") : "CPU"))
    if iszero(theta) && iszero(phi)
        h0 = build_u1_dsl_hopping(lat; t1=t1, t2=t2, μ=μ, gauge=gauge, verbose=verbose)
        psi_e, sites_e, info = prepare_slater_electron_mps(
            lat,
            h0;
            localize=localize,
            localize_coordinate=localize_coordinate,
            ordering=ordering,
            cutoff=cutoff,
            maxdim=maxdim,
            normalize_each_step=normalize_each_step,
            mode_apply_alg=mode_apply_alg,
            use_cuda=use_cuda,
            verbose=verbose,
        )
        info = merge(info, Dict(:theta => theta, :phi => phi, :geometry => lat, :gauge => gauge, :h0 => h0))
    else
        h_up, h_dn = build_u1_dsl_spin_hoppings(lat; t1=t1, t2=t2, μ=μ, theta=theta, phi=phi, gauge=gauge, verbose=verbose)
        psi_e, sites_e, info = prepare_spin_resolved_slater_electron_mps(
            lat,
            h_up,
            h_dn;
            localize=localize,
            localize_coordinate=localize_coordinate,
            ordering=ordering,
            cutoff=cutoff,
            maxdim=maxdim,
            normalize_each_step=normalize_each_step,
            mode_apply_alg=mode_apply_alg,
            use_cuda=use_cuda,
            verbose=verbose,
        )
        info = merge(info, Dict(:theta => theta, :phi => phi, :geometry => lat, :gauge => gauge, :h_up => h_up, :h_dn => h_dn))
    end
    psi_s, sites_s = gutzwiller_project_to_spin(
        psi_e,
        sites_e;
        spin_sites=spin_sites,
        use_cuda=use_cuda,
        verbose=verbose,
    )
    vprintln(verbose, "[prepare_u1_dsl_gutzwiller_mps] Finished U(1) DSL preparation")
    return (psi_spin=psi_s, sites_spin=sites_s, psi_elec=psi_e, sites_elec=sites_e, info=info)
end

"""
Prepare the symmetric Z2 spin liquid #1 of Lu 2016 (bosonic 0-flux dual).
"""
function prepare_z2_0flux_gutzwiller_mps(
    lat::AbstractTriangularCylinder;
    spin_sites::Union{Nothing,AbstractVector{<:Index}} = nothing,
    t1::Real = 1.0,
    t2::Real = 0.0,
    μ::Real = 0.0,
    Δ0::Real = 0.0,
    Δ1::Real = 0.25,
    Δ2::Real = 0.0,
    theta::Real = 0.0,
    phi::Real = 0.0,
    localize::Bool = true,
    localize_coordinate::Symbol = :mps,
    ordering::Symbol = :left_meet_right,
    cutoff::Real = 1e-10,
    maxdim::Int = 2000,
    normalize_each_step::Bool = true,
    mode_apply_alg::Union{Nothing,Symbol,AbstractString} = nothing,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    vprintln(verbose, "[prepare_z2_0flux_gutzwiller_mps] Starting Z2 0-flux (#1) preparation")
    vprintln(verbose, "[prepare_z2_0flux_gutzwiller_mps] Execution device for MPS/MPO contractions: " * (use_cuda ? (_HAS_CUDA ? "CUDA GPU" : "CUDA requested but unavailable") : "CPU"))
    h, Δ = build_z2_0flux_bdg(lat; t1=t1, t2=t2, μ=μ, Δ0=Δ0, Δ1=Δ1, Δ2=Δ2, theta=theta, phi=phi, verbose=verbose)
    psi_e, sites_e, info = prepare_bdg_electron_mps(
        lat,
        h,
        Δ;
        localize=localize,
        localize_coordinate=localize_coordinate,
        ordering=ordering,
        cutoff=cutoff,
        maxdim=maxdim,
        normalize_each_step=normalize_each_step,
        mode_apply_alg=mode_apply_alg,
        use_cuda=use_cuda,
        verbose=verbose,
    )
    psi_s, sites_s = gutzwiller_project_to_spin(
        psi_e,
        sites_e;
        spin_sites=spin_sites,
        use_cuda=use_cuda,
        verbose=verbose,
    )
    vprintln(verbose, "[prepare_z2_0flux_gutzwiller_mps] Finished Z2 0-flux (#1) preparation")
    return (psi_spin=psi_s, sites_spin=sites_s, psi_elec=psi_e, sites_elec=sites_e,
            info=merge(info, Dict(:h => h, :Δ => Δ, :theta => theta, :phi => phi, :geometry => lat)))
end

"""
Prepare the symmetric Z2 spin liquid #20 of Lu 2016 (bosonic π-flux dual).
"""
function prepare_z2_piflux_gutzwiller_mps(
    lat::AbstractTriangularCylinder;
    spin_sites::Union{Nothing,AbstractVector{<:Index}} = nothing,
    tπ::Real = 1.0,
    μ::Real = 0.0,
    Δ1::Real = 0.35,
    theta::Real = 0.0,
    phi::Real = 0.0,
    localize::Bool = true,
    localize_coordinate::Symbol = :mps,
    ordering::Symbol = :left_meet_right,
    cutoff::Real = 1e-10,
    maxdim::Int = 2000,
    normalize_each_step::Bool = true,
    mode_apply_alg::Union{Nothing,Symbol,AbstractString} = nothing,
    gauge::Symbol = :auto,
    use_cuda::Bool = false,
    verbose::Bool = true,
)
    vprintln(verbose, "[prepare_z2_piflux_gutzwiller_mps] Starting Z2 pi-flux (#20) preparation")
    vprintln(verbose, "[prepare_z2_piflux_gutzwiller_mps] Execution device for MPS/MPO contractions: " * (use_cuda ? (_HAS_CUDA ? "CUDA GPU" : "CUDA requested but unavailable") : "CPU"))
    h, Δ = build_z2_piflux_bdg(lat; tπ=tπ, μ=μ, Δ1=Δ1, theta=theta, phi=phi, gauge=gauge, verbose=verbose)
    psi_e, sites_e, info = prepare_bdg_electron_mps(
        lat,
        h,
        Δ;
        localize=localize,
        localize_coordinate=localize_coordinate,
        ordering=ordering,
        cutoff=cutoff,
        maxdim=maxdim,
        normalize_each_step=normalize_each_step,
        mode_apply_alg=mode_apply_alg,
        use_cuda=use_cuda,
        verbose=verbose,
    )
    psi_s, sites_s = gutzwiller_project_to_spin(
        psi_e,
        sites_e;
        spin_sites=spin_sites,
        use_cuda=use_cuda,
        verbose=verbose,
    )
    vprintln(verbose, "[prepare_z2_piflux_gutzwiller_mps] Finished Z2 pi-flux (#20) preparation")
    return (psi_spin=psi_s, sites_spin=sites_s, psi_elec=psi_e, sites_elec=sites_e,
            info=merge(info, Dict(:h => h, :Δ => Δ, :theta => theta, :phi => phi, :geometry => lat, :gauge => gauge)))
end

end # module
