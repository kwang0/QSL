using CSV
using DataFrames
using PyPlot
using HDF5

# Converts index into physical coordinate on triangular lattice
function coord(i, C)
    y = (i-1) % C
    x = (i-1) ÷ C
    if (y % 2 == 1)
        x += 0.5
    end
    y *= sqrt(3)/2
    return [x, y]
end

C = parse(Int64, ARGS[1])
J2 = parse(Float64, ARGS[2])
maxdim = parse(Int64, ARGS[3])
δt = parse(Float64, ARGS[4])

filename = "data_gpu/C$(C)_J$(J2)_chi$(maxdim)_dt$(δt)_unnormed.h5"
newfile = "data_gpu/processed_C$(C)_J$(J2)_chi$(maxdim)_dt$(δt)_unnormed.h5"

F = h5open(filename,"r")
times = read(F, "times")
corrs = read(F, "corrs")
close(F)

N = C^3
xs = zeros(2,N)
for i in range(1,N)
	x, y = coord(i, C)
	xs[1,i] = x
	xs[2,i] = y
end

Γ = transpose([0.0,0.0])
Y1 = transpose([2*pi/3,0.0])
K1 = transpose([4*pi/3,0.0])
K2 = transpose([2*pi/3,2*pi/sqrt(3)])
M1 = transpose([0,2*pi/sqrt(3)])
K3 = transpose([-2*pi/3,2*pi/sqrt(3)])
K4 = transpose([-4*pi/3,0.0])
Y2 = transpose([-2*pi/3,0.0])

interval = vcat(LinRange(0,0.99,100))

BZ_path2 = (1 .- interval) .* Γ .+ interval .* Y1
BZ_path2 = vcat(BZ_path2, (1 .- interval) .* Y1 .+ interval .* K1)
BZ_path2 = vcat(BZ_path2, (1 .- interval) .* K2 .+ interval .* M1)
BZ_path2 = vcat(BZ_path2, (1 .- interval) .* M1 .+ interval .* K3)
BZ_path2 = vcat(BZ_path2, (1 .- interval) .* K4 .+ interval .* Y2)
BZ_path2 = vcat(BZ_path2, (1 .- interval) .* Y2 .+ interval .* Γ)

eta = sqrt(0.02)
dampening = (eta / sqrt(pi)) .* exp.(-eta^2 .* times.^2)
corrs = transpose(dampening .* corrs')

omegas = transpose(vcat(LinRange(0,5.9,60)))
thetas = omegas .* times
S = real(corrs) * cos.(thetas) - imag(corrs) * sin.(thetas)

S = (δt / (pi * N)) .* cos.(BZ_path2 * xs) * S

G = h5open(newfile,"w")
G["times"] = times
G["corrs"] = corrs
G["S"] = S
close(G)