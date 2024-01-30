using PyPlot
using HDF5

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

function process(C, L, U, ω_B, maxdim, δt, η)
    file = "C$(C)_L$(L)_U$(U)_B$(ω_B)_chi$(maxdim)_dt$(δt)_transverse.h5"
    input = "/pscratch/sd/k/kwang98/QSL/graphene/$file"
    # input = file
    output = "processed_data/graphene/$file"

    F = h5open(input,"r")
    times = read(F, "times")
    corrs = read(F, "corrs")
    psi_norms = read(F, "psi_norms")
    psi2_norms = read(F, "psi2_norms")
    close(F)

    # corrs ./= psi2_norms' # Normalize correlation function

    N = 2 * C * L
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
    corrs = corrs .* dampening'
    
    # Convolution
    # dampening = (eta / sqrt(pi)) .* exp.(-eta^2 .* (times .- times').^2)
    # corrs = corrs * dampening

    omegas = transpose(vcat(LinRange(6.0,0.0,61)))
    thetas = omegas .* times
    S = real(corrs) * cos.(thetas) - imag(corrs) * sin.(thetas)

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
    close(G)
end

# C = parse(Int64, ARGS[1])
# J2 = parse(Float64, ARGS[2])
# maxdim = parse(Int64, ARGS[3])
# δt = parse(Float64, ARGS[4])
# η = parse(Float64, ARGS[5])

C = 4
L = 6
U = 0.0
ω_B = 0.0
maxdim = 32
δt = 0.1
η = 0.01

process(C, L, U, ω_B, maxdim, δt, η)