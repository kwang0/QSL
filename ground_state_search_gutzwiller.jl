using MKL
using ITensors
using ITensorMPS
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
function idx(row, col, C)
    return col * C + mod(row, C) + 1
end

# Generate Hamiltonian of J1-J2 Heisenberg model on triangular lattice
# Lattice has length L and height C, with PBC along height (cylindrical).
# XC geometry.
function triangular_model(C, L, J1, J2, B=0.0, Bperp=0.0, Δ1 = 1.0, Δ2 = 1.0)
    os = OpSum()

    for col in range(0,L-1)
        for row in range(0,C-1)
            index = idx(row, col, C)

            # Applied field
            os += -B, "Sz", index
            os += -Bperp, "Sx", index
            
            # NN couplings
            os += Δ1*J1, "Sz", index, "Sz", idx(row + 1, col, C)
            os += 0.5*J1, "S+", index, "S-", idx(row + 1, col, C)
            os += 0.5*J1, "S-", index, "S+", idx(row + 1, col, C)

            if (col < L-1)
                os += Δ1*J1, "Sz", index, "Sz", idx(row, col + 1, C)
                os += 0.5*J1, "S+", index, "S-", idx(row, col + 1, C)
                os += 0.5*J1, "S-", index, "S+", idx(row, col + 1, C)

                # Odd rows
                if (row % 2 == 1)
                    os += Δ1*J1, "Sz", index, "Sz", idx(row + 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", idx(row + 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", idx(row + 1, col + 1, C)

                    os += Δ1*J1, "Sz", index, "Sz", idx(row - 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", idx(row - 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", idx(row - 1, col + 1, C)
                end
            end

            # NNN couplings
            os += Δ2*J2, "Sz", index, "Sz", idx(row + 2, col, C)
            os += 0.5*J2, "S+", index, "S-", idx(row + 2, col, C)
            os += 0.5*J2, "S-", index, "S+", idx(row + 2, col, C)

            if ((col < L-1) && (row % 2 == 0))
                os += Δ2*J2, "Sz", index, "Sz", idx(row + 1, col + 1, C)
                os += 0.5*J2, "S+", index, "S-", idx(row + 1, col + 1, C)
                os += 0.5*J2, "S-", index, "S+", idx(row + 1, col + 1, C)

                os += Δ2*J2, "Sz", index, "Sz", idx(row - 1, col + 1, C)
                os += 0.5*J2, "S+", index, "S-", idx(row - 1, col + 1, C)
                os += 0.5*J2, "S-", index, "S+", idx(row - 1, col + 1, C)
            elseif ((col < L-2) && (row % 2 == 1))
                os += Δ2*J2, "Sz", index, "Sz", idx(row + 1, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", idx(row + 1, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", idx(row + 1, col + 2, C)

                os += Δ2*J2, "Sz", index, "Sz", idx(row - 1, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", idx(row - 1, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", idx(row - 1, col + 2, C)
            end
        end
    end

    return os
end

# Generate Hamiltonian of J1-J2 Heisenberg model on triangular lattice
# Lattice has length L and height C, with PBC along height (cylindrical).
# YC geometry.
function triangular_model_YC(C, L, J1, J2, B=0.0, Bperp=0.0, Δ1 = 1.0, Δ2 = 1.0)
    os = OpSum()

    for col in range(0,L-1)
        for row in range(0,C-1)
            index = idx(row, col, C)

            # Applied field
            os += -B, "Sz", index
            os += -Bperp, "Sx", index
            
            # NN couplings
            os += Δ1*J1, "Sz", index, "Sz", idx(row + 1, col, C)
            os += 0.5*J1, "S+", index, "S-", idx(row + 1, col, C)
            os += 0.5*J1, "S-", index, "S+", idx(row + 1, col, C)

            if (col < L-1)
                os += Δ1*J1, "Sz", index, "Sz", idx(row, col + 1, C)
                os += 0.5*J1, "S+", index, "S-", idx(row, col + 1, C)
                os += 0.5*J1, "S-", index, "S+", idx(row, col + 1, C)

                # Even/odd columns
                if (col % 2 == 0)
                    os += Δ1*J1, "Sz", index, "Sz", idx(row - 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", idx(row - 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", idx(row - 1, col + 1, C)
                else
                    os += Δ1*J1, "Sz", index, "Sz", idx(row + 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", idx(row + 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", idx(row + 1, col + 1, C)
                end
            end

            # NNN couplings
            if (col < L-1)
                # Even/odd columns
                if (col % 2 == 0)
                    os += Δ2*J2, "Sz", index, "Sz", idx(row + 1, col + 1, C)
                    os += 0.5*J2, "S+", index, "S-", idx(row + 1, col + 1, C)
                    os += 0.5*J2, "S-", index, "S+", idx(row + 1, col + 1, C)

                    os += Δ2*J2, "Sz", index, "Sz", idx(row - 2, col + 1, C)
                    os += 0.5*J2, "S+", index, "S-", idx(row - 2, col + 1, C)
                    os += 0.5*J2, "S-", index, "S+", idx(row - 2, col + 1, C)
                else
                    os += Δ2*J2, "Sz", index, "Sz", idx(row + 2, col + 1, C)
                    os += 0.5*J2, "S+", index, "S-", idx(row + 2, col + 1, C)
                    os += 0.5*J2, "S-", index, "S+", idx(row + 2, col + 1, C)

                    os += Δ2*J2, "Sz", index, "Sz", idx(row - 1, col + 1, C)
                    os += 0.5*J2, "S+", index, "S-", idx(row - 1, col + 1, C)
                    os += 0.5*J2, "S-", index, "S+", idx(row - 1, col + 1, C)
                end
            end
            if (col < L-2)
                os += Δ2*J2, "Sz", index, "Sz", idx(row, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", idx(row, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", idx(row, col + 2, C)
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
            index = idx(row, col, C)
            
            # NN couplings
            os += J1, "Sz", index, "Sz", idx(row + 1, col, C)
            os += 0.5*J1, "S+", index, "S-", idx(row + 1, col, C)
            os += 0.5*J1, "S-", index, "S+", idx(row + 1, col, C)

            if (col < L-1)
                os += J1, "Sz", index, "Sz", idx(row, col + 1, C)
                os += 0.5*J1, "S+", index, "S-", idx(row, col + 1, C)
                os += 0.5*J1, "S-", index, "S+", idx(row, col + 1, C)
            end
        end
    end

    return os
end

function main(; C=4, L=6, J1=1.0, B=0.0, Bperp=0.0, Δ1=1.0, Δ2=1.0, cutoff=1f-8, maxdim=32)
    file = "u1_YC_theta0_phi0_C$(C)_L$(L)_m0_chi512.h5"
    F = h5open(file,"r")
    u1 = read(F, "psi_spin", MPS)
    close(F)

    sites = siteinds(u1)

    nsweeps = 20

    for J2 in 0.21:0.01:0.3
        GC.gc()
        println("J2 = $J2")
        filename = "/pscratch/sd/k/kwang98/QSL/ground_state_search_YC_C$(C)_L$(L)_J$(J2)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim).h5"
        H = cu(MPO(triangular_model_YC(C, L, J1, J2, B, Bperp, Δ1, Δ2), sites))
        ψ = cu(randomMPS(sites))

        E0, ψ0 = dmrg(H, ψ; nsweeps, maxdim, cutoff)
        corrs = correlation_matrix(ψ0, "Sz", "Sz")
        ψ0 = ITensors.cpu(ψ0)
        overlap = inner(u1', ψ0)
        u1_energy = inner(u1', ITensors.cpu(H), u1)

        println("E0 = $E0")
        println("Overlap = $overlap")
        println("u1_energy = $u1_energy")


        F = h5open(filename,"w")
        F["psi0"] = ψ0
        F["E0"] = E0
        F["u1_energy"] = u1_energy
        F["overlap"] = overlap
        F["corrs"] = corrs
        close(F)
    end
end

ITensors.Strided.set_num_threads(1)
BLAS.set_num_threads(1)
# ITensors.enable_threaded_blocksparse(true)

C = parse(Int64, ARGS[1])
L = parse(Int64, ARGS[2])
maxdim = parse(Int64, ARGS[3])

main(C=C, L=L, maxdim=maxdim)