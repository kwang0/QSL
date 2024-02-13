using ITensors
using ITensorTDVP
using CUDA

N = 10
cutoff = 1e-12

s = siteinds("S=1/2", N)

function heisenberg(N)
    os = OpSum()
    for j in 1:(N - 1)
        os += 0.5, "S+", j, "S-", j + 1
        os += 0.5, "S-", j, "S+", j + 1
        os += "Sz", j, "Sz", j + 1
    end

    return os
end

H = cu(MPO(heisenberg(N), s))

ψ0 = cu(randomMPS(s; linkdims=10))

ψ1 = tdvp(H, -0.1im, ψ0; cutoff)