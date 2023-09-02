using MKL
using ITensors
using ITensorTDVP
using ITensorGPU
using CUDA
using Printf
using PyPlot
using HDF5
using LinearAlgebra

# Converts index into physical coordinate on triangular lattice (centers MPS site N/2 at coord (0,0))
function coord(i, C)
    y = i % C
    x = i ÷ C
    if (y % 2 == 1)
        x += 0.5
    end
    y *= sqrt(3)/2
    x -= C^2 / 2
    return [x, y]
end

# Convert row/col label to MPS index, with PBC in rows
function ind(row, col, C)
    return col * C + mod(row, C) + 1
end

# Generate Hamiltonian of J1-J2 Heisenberg model on triangular lattice
# Lattice has length L and height C, with PBC along height (cylindrical).
function triangular_model(C, L, J1, J2)
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

                # Odd rows
                if (row % 2 == 1)
                    os += J1, "Sz", index, "Sz", ind(row + 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", ind(row + 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", ind(row + 1, col + 1, C)

                    os += J1, "Sz", index, "Sz", ind(row - 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", ind(row - 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", ind(row - 1, col + 1, C)
                end
            end

            # NNN couplings
            os += J2, "Sz", index, "Sz", ind(row + 2, col, C)
            os += 0.5*J2, "S+", index, "S-", ind(row + 2, col, C)
            os += 0.5*J2, "S-", index, "S+", ind(row + 2, col, C)

            if ((col < L-1) && (row % 2 == 0))
                os += J2, "Sz", index, "Sz", ind(row + 1, col + 1, C)
                os += 0.5*J2, "S+", index, "S-", ind(row + 1, col + 1, C)
                os += 0.5*J2, "S-", index, "S+", ind(row + 1, col + 1, C)

                os += J2, "Sz", index, "Sz", ind(row - 1, col + 1, C)
                os += 0.5*J2, "S+", index, "S-", ind(row - 1, col + 1, C)
                os += 0.5*J2, "S-", index, "S+", ind(row - 1, col + 1, C)
            elseif ((col < L-2) && (row % 2 == 1))
                os += J2, "Sz", index, "Sz", ind(row + 1, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", ind(row + 1, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", ind(row + 1, col + 2, C)

                os += J2, "Sz", index, "Sz", ind(row - 1, col + 2, C)
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

function main(; C=4, J1=1, J2=0, cutoff=1e-16, δt=0.1, ttotal=40, maxdim=32)
    L = C^2
    N = C * L
    
    sites = siteinds("S=1/2", N; conserve_qns=false)
    H = cuMPO(MPO(square_model(C, L, J1), sites))

    nsweeps = 5
    state = [isodd(n) ? "Up" : "Dn" for n=1:N]
    ψ0 = cuMPS(MPS(sites, state))

    E0, ψ = dmrg(H, ψ0; nsweeps, maxdim, cutoff)

    c = div(N, 2) # center site
    Sz_center = cuITensor(op("Sz",sites[c]))
    orthogonalize!(ψ, c)
    ψ2 = apply(2 * Sz_center, ψ; cutoff, maxdim)

    times = Float64[]
    corrs = []
    ψ_norms = Float64[]
    ψ2_norms = Float64[]
    start_time = 0.0

    filename = "data_gpu/C$(C)_J$(J2)_chi$(maxdim)_dt$(δt)_unnormed.h5"
    # filename = "data_gpu/square_C$(C)_chi$(maxdim)_dt$(δt).h5"
    for t in start_time:δt:ttotal
        corr = ComplexF64[]
        for i in range(1,N)
            orthogonalize!(ψ, i)
            orthogonalize!(ψ2, i)
            push!(corr, exp(im * E0 * t) * inner(apply(cuITensor(2 * op("Sz",sites[i])), ψ; cutoff, maxdim), ψ2))
            # push!(corr, inner(apply(cuITensor(2 * op("Sz",sites[i])), ψ; cutoff, maxdim), ψ2))
        end
        orthogonalize!(ψ2, c)
        println("$t")
        flush(stdout)
        push!(times, t)
        push!(corrs, corr)
        push!(ψ_norms, norm(ψ))
        push!(ψ2_norms, norm(ψ2))
    
        # Writing to data file
        F = h5open(filename,"w")
        F["times"] = times
        F["corrs"] = hcat(corrs...)
        # F["psi"] = ψ
        # F["psi2"] = ψ2
        F["psi_norms"] = ψ_norms
        F["psi2_norms"] = ψ2_norms
        F["E0"] = E0
        close(F)
    
        t≈ttotal && break
    
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
    end

    return times, corrs
end

gpu = cu

ITensors.Strided.set_num_threads(1)
BLAS.set_num_threads(1)
# ITensors.enable_threaded_blocksparse(true)

C = parse(Int64, ARGS[1])
J2 = parse(Float64, ARGS[2])
maxdim = parse(Int64, ARGS[3])
δt = parse(Float64, ARGS[4])

main(C=C, J2=J2, maxdim=maxdim, δt=δt)