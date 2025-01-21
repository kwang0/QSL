using MKL
using ITensors
using ITensorTDVP
using CUDA
using Printf
using PyPlot
using HDF5
using LinearAlgebra

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

function main(; C=4, L=6, J1=1.0, J2=0.0, B=0.0, Δ1=1.0, Δ2=1.0, cutoff=1e-16, maxdim=32)
    N = C * L

    filename = "/pscratch/sd/k/kwang98/QSL/ground_state_search_C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim).h5"
    sites = siteinds("S=1/2", N; conserve_qns=false)
    H = cu(MPO(triangular_model(C, L, J1, J2, B, Δ1, Δ2), sites))

    nsweeps = 20
    nsamples = 10

    Emin = 1000000

    # B_sat = 4.5
    # N_spinup = ((B * N / 2) ÷ B_sat) + (N ÷ 2) # Naive guess for magnetization
    # state = [n ≤ N_spinup ? "Up" : "Dn" for n=1:N]

    for i in 1:nsamples
        GC.gc()
        ψ = cu(randomMPS(sites))

        E0, ψ0 = dmrg(H, ψ; nsweeps, maxdim, cutoff)

        println("E0 = $E0")
        Zs = expect(ψ0, "Sz")
        Zs .*= 2
        M = sum(Zs)
        println("M = $M")
        
        if E0 < Emin
            Emin = E0

            F = h5open(filename,"w")
            F["psi0"] = ITensors.cpu(ψ0)
            F["E0"] = E0
            close(F)
        end
    end
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

main(C=C, L=L, J2=J2, B=B, Δ1=Δ, Δ2=Δ, maxdim=maxdim)