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
    y = (i-1) % C
    x = (i-1) ÷ C
    if (y % 2 == 1)
        x += 0.5
    end
    x -= (L/2 - 0.5)
    y -= (C-1)
    y *= sqrt(3)/2
    return [x, y]
end

# Convert row/col label to MPS index, with PBC in rows
function ind(row, col, C)
    return col * C + mod(row, C) + 1
end

# Generate Hamiltonian of J1-J2 Heisenberg model on triangular lattice
# Lattice has length L and height C, with PBC along height (cylindrical).
function triangular_model(C, L, J1, J2, B=0.0, Δ1 = 1.0, Δ2 = 1.0)
    os = OpSum()

    for col in range(0,L-1)
        for row in range(0,C-1)
            index = ind(row, col, C)

            # Applied field
            os += -B, "Sz", index
            
            # NN couplings
            os += Δ1*J1, "Sz", index, "Sz", ind(row + 1, col, C)
            os += 0.5*J1, "S+", index, "S-", ind(row + 1, col, C)
            os += 0.5*J1, "S-", index, "S+", ind(row + 1, col, C)

            if (col < L-1)
                os += Δ1*J1, "Sz", index, "Sz", ind(row, col + 1, C)
                os += 0.5*J1, "S+", index, "S-", ind(row, col + 1, C)
                os += 0.5*J1, "S-", index, "S+", ind(row, col + 1, C)

                # Odd rows
                if (row % 2 == 1)
                    os += Δ1*J1, "Sz", index, "Sz", ind(row + 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", ind(row + 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", ind(row + 1, col + 1, C)

                    os += Δ1*J1, "Sz", index, "Sz", ind(row - 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", ind(row - 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", ind(row - 1, col + 1, C)
                end
            end

            # NNN couplings
            os += Δ2*J2, "Sz", index, "Sz", ind(row + 2, col, C)
            os += 0.5*J2, "S+", index, "S-", ind(row + 2, col, C)
            os += 0.5*J2, "S-", index, "S+", ind(row + 2, col, C)

            if ((col < L-1) && (row % 2 == 0))
                os += Δ2*J2, "Sz", index, "Sz", ind(row + 1, col + 1, C)
                os += 0.5*J2, "S+", index, "S-", ind(row + 1, col + 1, C)
                os += 0.5*J2, "S-", index, "S+", ind(row + 1, col + 1, C)

                os += Δ2*J2, "Sz", index, "Sz", ind(row - 1, col + 1, C)
                os += 0.5*J2, "S+", index, "S-", ind(row - 1, col + 1, C)
                os += 0.5*J2, "S-", index, "S+", ind(row - 1, col + 1, C)
            elseif ((col < L-2) && (row % 2 == 1))
                os += Δ2*J2, "Sz", index, "Sz", ind(row + 1, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", ind(row + 1, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", ind(row + 1, col + 2, C)

                os += Δ2*J2, "Sz", index, "Sz", ind(row - 1, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", ind(row - 1, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", ind(row - 1, col + 2, C)
            end
        end
    end

    return os
end

# Generate Hamiltonian of J1-J2 Heisenberg model on square lattice
# Lattice has length L and height C, with PBC along height (cylindrical).
function square_model(C, L, J1=1.0)
    os = OpSum()

    for col in range(0,L-1)
        for row in range(0,C-1)
            index = ind(row, col, C)
            
            # NN couplings
            os += J1, "Sz", index, "Sz", ind(row + 1, col, C)
            os += 0.5*J1, "S+", index, "S-", ind(row + 1, col, C)
            os += 0.5*J1, "S-", index, "S+", ind(row + 1, col, C)

            if (col < L-1)
                os += J1, "Sz", index, "Sz", ind(row, col + 1, C)
                os += 0.5*J1, "S+", index, "S-", ind(row, col + 1, C)
                os += 0.5*J1, "S-", index, "S+", ind(row, col + 1, C)
            end
        end
    end

    return os
end

function main(; C=4, L=6, J1=1.0, J2=0.0, B=0.0, Δ1=1.0, Δ2=1.0, cutoff=1e-16, δt=0.1, ttotal=80, maxdim=32, component="longitudinal")
    # cu = ITensors.cpu
    
    tick()
    N = C * L

    filename = "/pscratch/sd/k/kwang98/QSL/C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_$(component)_disconnectfirst.h5"
    # filename = "C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_$(component)_disconnectfirst.h5"
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
        ψ = cu(read(F, "psi", MPS))
        ψ2 = cu(read(F, "psi2", MPS))
        ψ_norms = read(F, "psi_norms")
        ψ2_norms = read(F, "psi2_norms")
        E0 = read(F, "E0")
        Zs = read(F, "Zs")
        start_time = last(times)
        close(F)
    
        sites = siteinds(ψ)
        c = div(N, 2) # center site
        Sz_center = cu(op(op_string, sites[c]) - Zs[c] * op("Id", sites[c]))
        H = cu(MPO(triangular_model(C, L, J1, J2, B, Δ1, Δ2), sites))
    else
        sites = siteinds("S=1/2", N; conserve_qns=false)
        H = cu(MPO(triangular_model(C, L, J1, J2, B, Δ1, Δ2), sites))

        nsweeps = 10
        # state = [isodd(n) ? "Up" : "Dn" for n=1:N]
        ψ0 = cu(randomMPS(sites))

        E0, ψ = dmrg(H, ψ0; nsweeps, maxdim, cutoff)
        println("E0 = $E0")
        Zs = expect(ψ, op_string)
        M = sum(Zs)
        println("M = $M")

        Zs .*= 2

        c = div(N, 2) # center site
        Sz_center = cu(op(op_string, sites[c]) - Zs[c] * op("Id", sites[c]))
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
            push!(corr, (exp(im * E0 * t) * inner(apply(cu(2 * op(op_string,sites[i]) - Zs[i] * op("Id", sites[i])), ψ; cutoff, maxdim), ψ2)))
            # push!(corr, inner(apply(cu(2 * op("Sz",sites[i])), ψ; cutoff, maxdim), ψ2))
        end
        # orthogonalize!(ψ2, c)
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
        F["psi2"] = ITensors.cpu(ψ2)
        F["psi"] = ITensors.cpu(ψ)
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
          outputlevel=1,
          nsite=1
        )
        GC.gc()
    end

    return times, corrs
end

ITensors.Strided.set_num_threads(1)
BLAS.set_num_threads(1)
# ITensors.enable_threaded_blocksparse(true)

C = parse(Int64, ARGS[1])
L = parse(Int64, ARGS[2])
J2 = parse(Float64, ARGS[3])
B = parse(Float64, ARGS[4])
Δ = parse(Float64, ARGS[5])
maxdim = parse(Int64, ARGS[6])
δt = parse(Float64, ARGS[7])
component = ARGS[8]

main(C=C, L=L, J2=J2, B=B, Δ1=Δ, Δ2=Δ, maxdim=maxdim, δt=δt, component=component)