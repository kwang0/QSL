using MKL
using ITensors
using ITensorTDVP
using CUDA
using Printf
using PyPlot
using HDF5
using LinearAlgebra
using TickTock

# Converts index into physical coordinate on triangular lattice (centers MPS site N/2 at coord (0,0))
function coord(i, C, L)
    row = ((i-1) ÷ 2) % C
    col = ((i-1) ÷ 2) ÷ C
    row -= C - 1
    col -= L/2 - 1

    a1 = [sqrt(3), 0]
    a2 = [-sqrt(3)/2, 1.5]
    x = (col .* a1) .+ (row .* a2)

    if (isodd(i))
        x .+= [-sqrt(3)/2, 0.5]
    end
    return x
end

# Convert row/col label to MPS index, with PBC in rows
# for honeycomb lattice. Odd sites are sublattice A, 
# even sites are sublattice B.
function ind(row, col, C)
    return 2 * (col * C + mod(row, C)) + 1
end

# Generate Hamiltonian of graphene Hubbard model on honeycomb lattice.
# Two basis sites are grouped together in unit cell, and connectivity of
# unit cells match that of a square lattice. "Square" lattice has 
# length L and height C, with PBC along height (cylindrical).
function graphene_model(C, L, t, U, ω_B)
    os = OpSum()

    for col in range(0,L-1)
        for row in range(0,C-1)
            index_A = ind(row, col, C)
            index_B = index_A + 1

            # Internal hopping
            os -= t, "Cdagup", index_A, "Cup", index_B
            os -= t, "Cdagup", index_B, "Cup", index_A
            os -= t, "Cdagdn", index_A, "Cdn", index_B
            os -= t, "Cdagdn", index_B, "Cdn", index_A
            
            # Vertical hopping
            os -= t, "Cdagup", index_A, "Cup", ind(row + 1, col, C) + 1
            os -= t, "Cdagup", ind(row + 1, col, C) + 1, "Cup", index_A
            os -= t, "Cdagdn", index_A, "Cdn", ind(row + 1, col, C) + 1
            os -= t, "Cdagdn", ind(row + 1, col, C) + 1, "Cdn", index_A

            # Horizontal hopping
            if (col < L-1)
                os -= t, "Cdagup", index_B, "Cup", ind(row, col + 1, C)
                os -= t, "Cdagup", ind(row, col + 1, C), "Cup", index_B
                os -= t, "Cdagdn", index_B, "Cdn", ind(row, col + 1, C)
                os -= t, "Cdagdn", ind(row, col + 1, C), "Cdn", index_B
            end

            # Hubbard/Coulomb interaction (on-site and sublattice)
            os += U, "Nup", index_A, "Ndn", index_A
            os += U, "Nup", index_B, "Ndn", index_B
            os += U, "Nup", index_A, "Nup", index_B
            os += U, "Ndn", index_A, "Ndn", index_B
            os += U, "Nup", index_A, "Ndn", index_B
            os += U, "Ndn", index_A, "Nup", index_B

            # Zeeman field
            os -= ω_B, "Nup", index_A
            os += ω_B, "Ndn", index_A
            os -= ω_B, "Nup", index_B
            os += ω_B, "Ndn", index_B
        end
    end

    return os
end

function main(; C=4, L=6, t=2/3, U=0.1, ω_B=0.1, cutoff=1e-16, δt=0.1, ttotal=80, maxdim=32, component="longitudinal")
    tick()
    N = 2 * C * L

    filename = "/pscratch/sd/k/kwang98/QSL/graphene/C$(C)_L$(L)_U$(U)_B$(ω_B)_chi$(maxdim)_dt$(δt)_$(component).h5"
    # filename = "C$(C)_L$(L)_U$(U)_B$(ω_B)_chi$(maxdim)_dt$(δt)_$(component).h5"
    if component == "longitudinal"
        op_string = "Sz"
    elseif component == "transverse"
        op_string = "S-"
    end
    # filename = "data_gpu/square_C$(C)_chi$(maxdim)_dt$(δt).h5"
    if (isfile(filename))
        F = h5open(filename,"r")
        times = read(F, "times")
        corrs = read(F, "corrs")
        ψ = read(F, "psi", MPS)
        ψ2 = read(F, "psi2", MPS)
        ψ_norms = read(F, "psi_norms")
        ψ2_norms = read(F, "psi2_norms")
        E0 = read(F, "E0")
        Zs = read(F, "Zs")
        start_time = last(times)
        close(F)
    
        sites = siteinds(ψ)
        c = div(N, 2) # center site (B)
        Sz_center = op(op_string, sites[c]) - Zs[c] * op("Id", sites[c])
        H = MPO(graphene_model(C, L, t, U, ω_B), sites)
    else
        sites = siteinds("Electron", N; conserve_nf=true, conserve_sz=false)
        H = MPO(graphene_model(C, L, t, U, ω_B), sites)

        nsweeps = 10
        state = [isodd(n) ? "Up" : "Dn" for n=1:N]
        ψ0 = MPS(sites, state)

        E0, ψ = dmrg(H, ψ0; nsweeps, maxdim, cutoff)
        println("E0 = $E0")
        Zs = expect(ψ, op_string)
        M = sum(Zs)
        println("M = $M")

        Zs .*= 2

        c = N # center site
        Sz_center = op(op_string, sites[c]) - Zs[c] * op("Id", sites[c])
        orthogonalize!(ψ, c)
        ψ2 = apply(2 * Sz_center, ψ; cutoff, maxdim)

        times = Float64[]
        corrs = []
        ψ_norms = Float64[]
        ψ2_norms = Float64[]
        start_time = 0.0
    end

    for t in start_time:δt:ttotal
        corr = ComplexF64[]
        for i in range(1,N)
            # orthogonalize!(ψ, i)
            # orthogonalize!(ψ2, i)
            push!(corr, (exp(im * E0 * t) * inner(apply(2 * op(op_string, sites[i]) - Zs[i] * op("Id", sites[i]), ψ; cutoff, maxdim), ψ2)))
            # push!(corr, inner(apply(cuITensor(2 * op("Sz",sites[i])), ψ; cutoff, maxdim), ψ2))
        end
        orthogonalize!(ψ2, c)
        println("Time = $t")
        flush(stdout)
        push!(times, t)
        t == 0.0 ? corrs = corr : corrs = hcat(corrs, corr)
        push!(ψ_norms, norm(ψ))
        push!(ψ2_norms, norm(ψ2))
    
        # Writing to data file
        F = h5open(filename,"w")
        F["times"] = times
        F["corrs"] = corrs
        F["psi2"] = ψ2
        F["psi"] = ψ
        F["E0"] = E0
        F["Zs"] = Zs
        F["psi_norms"] = ψ_norms
        F["psi2_norms"] = ψ2_norms
        close(F)
    
        t≈ttotal && break

        # Stop simulations before HPC limit to ensure no corruption of data writing
        if peektimer() > (23.5 * 60 * 60)
            break
        end
    
        # ψ = basis_extend(ψ, H_real; cutoff, extension_krylovdim=2)
        # if (maxlinkdim(ψ2) < 100)
        #   ψ2 = basis_extend(ψ2, H_real; cutoff, extension_krylovdim=2)
        # end
    
        # ψ = tdvp(H, -im * δt, ψ;
        # nsweeps=1,
        # reverse_step=true,
        # normalize=false,
        # maxdim=maxdim,
        # cutoff=cutoff,
        # outputlevel=1
        # )

        ψ2 = tdvp(H, -im * δt, ψ2;
          nsweeps=1,
          reverse_step=true,
          normalize=false,
          maxdim=maxdim,
          cutoff=cutoff,
          outputlevel=1
        )
        GC.gc()
    end

    return times, corrs
end

ITensors.Strided.set_num_threads(1)
BLAS.set_num_threads(256)
# ITensors.enable_threaded_blocksparse(true)

C = parse(Int64, ARGS[1])
L = parse(Int64, ARGS[2])
U = parse(Float64, ARGS[3])
ω_B = parse(Float64, ARGS[4])
maxdim = parse(Int64, ARGS[5])
δt = parse(Float64, ARGS[6])
component = ARGS[7]

main(C=C, L=L, U=U, ω_B=ω_B, maxdim=maxdim, δt=δt, component=component)