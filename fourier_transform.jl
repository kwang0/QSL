using PyPlot
using HDF5

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

function process(C, L, J2, B, Δ1, Δ2, maxdim, δt, η)
    file = "C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_transverse_disconnectfirst_ones.h5"
    # input = "/pscratch/sd/k/kwang98/QSL/$file"
    input = "processed_data/$file"
    output = "processed_data/$file"
    # output = file
    # filename = "data_gpu/square_C$(C)_chi$(maxdim)_dt$(δt)_double_evolve.h5"

    F = h5open(input,"r")
    times = read(F, "times")
    corrs = read(F, "corrs")
    psi_norms = read(F, "psi_norms")
    psi2_norms = read(F, "psi2_norms")
    E0 = read(F, "E0")
    Zs = read(F, "Zs")
    close(F)

    # print(times[end])

    # corrs ./= psi2_norms' # Normalize correlation function

    N = C * L
    xs = zeros(2,N)
    for i in range(1,N)
        x, y = coord(i, C, L)
        xs[1,i] = x
        xs[2,i] = y
        # xs[1,i] = (i-1) ÷ C
        # xs[2,i] = (i-1) % C
    end

    # L = C^2
    interval = vcat(LinRange(0,1 - 3/L,div(L,3)))
    # interval = vcat(LinRange(0,1 - 2/L,div(L,2)))

    # Triangular lattice BZ points
    Γ = transpose([0.0,0.0])
    Y1 = transpose([2*pi/3,0.0])
    K1 = transpose([4*pi/3,0.0])
    K2 = transpose([2*pi/3,2*pi/sqrt(3)])
    M1 = transpose([0,2*pi/sqrt(3)])
    K3 = transpose([-2*pi/3,2*pi/sqrt(3)])
    K4 = transpose([-4*pi/3,0.0])
    Y2 = transpose([-2*pi/3,0.0])

    BZ_path2 = (1 .- interval) .* Γ .+ interval .* Y1
    BZ_path2 = vcat(BZ_path2, (1 .- interval) .* Y1 .+ interval .* K1)
    BZ_path2 = vcat(BZ_path2, (1 .- interval) .* K2 .+ interval .* M1)
    BZ_path2 = vcat(BZ_path2, (1 .- interval) .* M1 .+ interval .* K3)
    BZ_path2 = vcat(BZ_path2, (1 .- interval) .* K4 .+ interval .* Y2)
    BZ_path2 = vcat(BZ_path2, (1 .- interval) .* Y2 .+ interval .* Γ)


    # Square lattice BZ points
    X1 = transpose([pi,0.0])
    X2 = transpose([0.0,pi])
    M = transpose([pi,pi])

    BZ_square_path = (1 .- interval) .* Γ .+ interval .* X1
    BZ_square_path = vcat(BZ_square_path, (1 .- interval) .* X2 .+ interval .* M)

    eta = sqrt(η)
    # Pointwise multiplication
    dampening = (eta / sqrt(pi)) .* exp.(-eta^2 .* times.^2)
    corrs2 = corrs .* dampening'
    
    # Convolution
    # dampening = (eta / sqrt(pi)) .* exp.(-eta^2 .* (times .- times').^2)
    # corrs2 = corrs * dampening

    omegas = transpose(vcat(LinRange(6.0,0.0,601)))
    thetas = omegas .* times
    S = real(corrs2) * cos.(thetas) - imag(corrs2) * sin.(thetas)

    S = (δt / (pi * N)) .* cos.(BZ_path2 * xs) * S

    # pos = axs[i,j].imshow(S' ./ maximum(S), cmap="hot", interpolation="gaussian",
    #     norm=matplotlib[:colors][:LogNorm](vmin=0.0005, vmax=1))
    # x_left, x_right = axs[i,j].get_xlim()
    # y_low, y_high = axs[i,j].get_ylim()
    # axs[i,j].set_aspect(abs((x_right-x_left)/(y_low-y_high))*0.5)
    # fig.colorbar(pos, ax=axs[i,j])
    
    # plt.title(filename)
    # plt.savefig("plots_gpu/C$(C)_J$(J2)_chi$(maxdim)_dt$(δt)_eta2-$(η).png")
    # plt.savefig("plots_gpu/square_C$(C)_chi$(maxdim)_dt$(δt)_eta2-$(η)_double_evolve.png")

    G = h5open(output,"w")
    G["times"] = times
    G["corrs"] = corrs
    G["S"] = S
    G["psi_norms"] = psi_norms
    G["psi2_norms"] = psi2_norms
    G["E0"] = E0
    G["Zs"] = Zs
    close(G)
end

# C = parse(Int64, ARGS[1])
# J2 = parse(Float64, ARGS[2])
# maxdim = parse(Int64, ARGS[3])
# δt = parse(Float64, ARGS[4])
# η = parse(Float64, ARGS[5])

C = 6
L = 36
J2 = 0.12
# B = 0.0
Δ1 = 1.0
Δ2 = 1.0
maxdim = 512
δt = 0.1
η = 0.01

process(C, L, J2, 0.0, Δ1, Δ2, maxdim, δt, η)
process(C, L, J2, 0.5, Δ1, Δ2, maxdim, δt, η)
process(C, L, J2, 1.0, Δ1, Δ2, maxdim, δt, η)
process(C, L, J2, 1.5, Δ1, Δ2, maxdim, δt, η)
# process(C, L, J2, 2.0, Δ1, Δ2, maxdim, δt, η)