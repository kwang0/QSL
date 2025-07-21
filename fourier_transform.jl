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

# Converts index into physical coordinate on YC triangular lattice (centers MPS site N/2 at coord (0,0))
function coord_YC(i, C, L)
    y = (i-1) % C
    x = (i-1) ÷ C
    if (x % 2 == 1)
        y += 0.5
    end
    x -= (L/2 - 1)
    y -= (C-1+0.5)
    x *= sqrt(3)/2
    return [x, y]
end

function process(C, L, J2, B, Δ1, Δ2, g_perp, g_parallel, maxdim, δt, η, T_cutoff=Inf64)
    # file = "C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_longitudinal_gssearched.h5"
    file = "C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_longitudinal_gssearched_YC.h5"
    # input = "/pscratch/sd/k/kwang98/QSL/$file"
    input = "processed_data/$file"
    output = "processed_data/$file"
    # output = file

    F = h5open(input,"r")
    times = read(F, "times")
    corrs = read(F, "corrs")
    Ss = read(F, "Ss")
    psi_norms = read(F, "psi_norms")
    psi2_norms = read(F, "psi2_norms")
    E0 = read(F, "E0")
    Zs = read(F, "Zs")
    close(F)

    corrs2 = corrs[:, times .< T_cutoff]
    times2 = times[times .< T_cutoff]

    # c = size(corrs2, 1) ÷ 2 # Center site
    # corrs2 .+= Zs[c] .* Zs # Disconnected correlation

    if T_cutoff == Inf64
        T_cutoff = times2[end]
    end

    # input = "/pscratch/sd/k/kwang98/QSL/C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_longitudinal_gssearched_twositetdvp.h5"
    # F = h5open(input,"r")
    # long_times = read(F, "times")
    # long_corrs = read(F, "corrs")
    # long_Ss = read(F, "Ss")
    # long_psi_norms = read(F, "psi_norms")
    # long_psi2_norms = read(F, "psi2_norms")
    # long_E0 = read(F, "E0")
    # long_Zs = read(F, "Zs")
    # close(F)

    # input = "/pscratch/sd/k/kwang98/QSL/C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_transverse_gssearched_twositetdvp.h5"
    # F = h5open(input,"r")
    # trans_times = read(F, "times")
    # trans_corrs = read(F, "corrs")
    # trans_Ss = read(F, "Ss")
    # trans_psi_norms = read(F, "psi_norms")
    # trans_psi2_norms = read(F, "psi2_norms")
    # trans_E0 = read(F, "E0")
    # trans_Zs = read(F, "Zs")
    # close(F)

    # input = "/pscratch/sd/k/kwang98/QSL/C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_transversedown_gssearched_twositetdvp.h5"
    # F = h5open(input,"r")
    # transdown_times = read(F, "times")
    # transdown_corrs = read(F, "corrs")
    # transdown_Ss = read(F, "Ss")
    # transdown_psi_norms = read(F, "psi_norms")
    # transdown_psi2_norms = read(F, "psi2_norms")
    # transdown_E0 = read(F, "E0")
    # transdown_Zs = read(F, "Zs")
    # close(F)

    # min_length = minimum(length, [long_times, trans_times, transdown_times])
    # times = long_times[1:min_length]
    # corrs = (g_perp^2 .* long_corrs[:,1:min_length]) .+ (0.25 * g_parallel^2 .* (trans_corrs[:,1:min_length] .+ transdown_corrs[:,1:min_length]))

    N = C * L
    xs = zeros(2,N)
    for i in range(1,N)
        # x, y = coord(i, C, L)
        x, y = coord_YC(i, C, L)
        xs[1,i] = x
        xs[2,i] = y
        # xs[1,i] = (i-1) ÷ C
        # xs[2,i] = (i-1) % C
    end

    # L = C^2
    interval = vcat(LinRange(0,1 - 3/L,div(L,3))) # XC
    interval2 = vcat(LinRange(0,2/3,3))

    # Triangular lattice BZ points
    Γ = transpose([0.0,0.0])
    Y1 = transpose([2*pi/3,0.0])
    K1 = transpose([4*pi/3,0.0])
    K2 = transpose([2*pi/3,2*pi/sqrt(3)])
    M1 = transpose([0,2*pi/sqrt(3)])
    K3 = transpose([-2*pi/3,2*pi/sqrt(3)])
    K4 = transpose([-4*pi/3,0.0])
    Y2 = transpose([-2*pi/3,0.0])

    # BZ_path2 = (1 .- interval) .* Γ .+ interval .* Y1
    # BZ_path2 = vcat(BZ_path2, (1 .- interval) .* Y1 .+ interval .* K1)
    # BZ_path2 = vcat(BZ_path2, (1 .- interval) .* K2 .+ interval .* M1)
    # BZ_path2 = vcat(BZ_path2, (1 .- interval) .* M1 .+ interval .* Γ)
    # BZ_path2 = vcat(BZ_path2, M1)

    # BZ_path2 = vcat(BZ_path2, (1 .- interval) .* M1 .+ interval .* K3)
    # BZ_path2 = vcat(BZ_path2, (1 .- interval) .* K4 .+ interval .* Y2)
    # BZ_path2 = vcat(BZ_path2, (1 .- interval) .* Y2 .+ interval .* Γ)

    BZ_path2 = vcat(LinRange(0,1 - 2/L,div(L,2))) .* transpose([2*pi/sqrt(3),0]) # YC L=36

    # Square lattice BZ points
    # X1 = transpose([pi,0.0])
    # X2 = transpose([0.0,pi])
    # M = transpose([pi,pi])

    # BZ_square_path = (1 .- interval) .* Γ .+ interval .* X1
    # BZ_square_path = vcat(BZ_square_path, (1 .- interval) .* X2 .+ interval .* M)

    # eta = sqrt(η)
    if η == 0.0
        η = 1/2 * (2 * pi / T_cutoff)
    end 
    # Pointwise multiplication
    dampening = (η / sqrt(pi)) .* exp.(-η^2 .* times2.^2)
    corrs2 = corrs2 .* dampening'

    # corrs2 = corrs # No dampening
    
    # Convolution
    # dampening = (eta / sqrt(pi)) .* exp.(-eta^2 .* (times .- times').^2)
    # corrs2 = corrs * dampening

    # omegas = transpose(vcat(LinRange(3.0, 0.0, round(Int64, 3 * (T_cutoff / (2*pi))))))
    # omegas = transpose(vcat(LinRange(3, 0.0, round(Int64,T_cutoff/2+1))))
    omegas = transpose(vcat(LinRange(3, 0.0, 31)))
    thetas = omegas .* times2
    S = real(corrs2) * cos.(thetas) - imag(corrs2) * sin.(thetas)

    S = (δt / (pi * N)) .* cos.(BZ_path2 * xs) * S

    S ./= maximum(S)
    S[S .< 0] .= 0.01

    # pos = axs[i,j].imshow(S' ./ maximum(S), cmap="hot", interpolation="gaussian",
    #     norm=matplotlib[:colors][:LogNorm](vmin=0.0005, vmax=1))
    # x_left, x_right = axs[i,j].get_xlim()
    # y_low, y_high = axs[i,j].get_ylim()
    # axs[i,j].set_aspect(abs((x_right-x_left)/(y_low-y_high))*0.5)
    # fig.colorbar(pos, ax=axs[i,j])
    
    # plt.title(filename)
    # plt.savefig("plots_gpu/C$(C)_J$(J2)_chi$(maxdim)_dt$(δt)_eta2-$(η).png")
    # plt.savefig("plots_gpu/square_C$(C)_chi$(maxdim)_dt$(δt)_eta2-$(η)_double_evolve.png")

    # output = "processed_data/C$(C)_L$(L)_J$(J2)_B$(B)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim)_dt$(δt)_total_gssearched_twositetdvp.h5"

    G = h5open(output,"w")
    G["times"] = times
    G["corrs"] = corrs
    G["S"] = S
    G["Ss"] = Ss
    G["psi_norms"] = psi_norms
    G["psi2_norms"] = psi2_norms
    G["E0"] = E0
    G["Zs"] = Zs
    close(G)

    # G = h5open(output,"w")
    # G["times"] = times
    # G["corrs"] = corrs
    # G["S"] = S
    # G["long_times"] = long_times
    # G["long_corrs"] = long_corrs
    # G["long_Ss"] = long_Ss
    # G["long_psi_norms"] = long_psi_norms
    # G["long_psi2_norms"] = long_psi2_norms
    # G["long_E0"] = long_E0
    # G["long_Zs"] = long_Zs
    # G["trans_times"] = trans_times
    # G["trans_corrs"] = trans_corrs
    # G["trans_Ss"] = trans_Ss
    # G["trans_psi_norms"] = trans_psi_norms
    # G["trans_psi2_norms"] = trans_psi2_norms
    # G["trans_E0"] = trans_E0
    # G["trans_Zs"] = trans_Zs
    # G["transdown_times"] = transdown_times
    # G["transdown_corrs"] = transdown_corrs
    # G["transdown_Ss"] = transdown_Ss
    # G["transdown_psi_norms"] = transdown_psi_norms
    # G["transdown_psi2_norms"] = transdown_psi2_norms
    # G["transdown_E0"] = transdown_E0
    # G["transdown_Zs"] = transdown_Zs
    # close(G)
end

# C = parse(Int64, ARGS[1])
# J2 = parse(Float64, ARGS[2])
# maxdim = parse(Int64, ARGS[3])
# δt = parse(Float64, ARGS[4])
# η = parse(Float64, ARGS[5])

C = 6
L = 36
J2 = 0.043
B = 0.0
Δ = 1.0
maxdim = 512
δt = 0.1
η = 0.1
g_perp = 3.04
g_parallel = 3.44
T_cutoff = 50.0

process(C, L, J2, 0.0, Δ, Δ, g_perp, g_parallel, maxdim, δt, η, T_cutoff)
# process(C, L, J2, 0.8, Δ, Δ, g_perp, g_parallel, maxdim, δt, η)
# process(C, L, J2, 1.6, Δ, Δ, g_perp, g_parallel, maxdim, δt, η)
# process(C, L, J2, 2.4, Δ, Δ, g_perp, g_parallel, maxdim, δt, η)
# process(C, L, J2, 3.2, Δ, Δ, g_perp, g_parallel, maxdim, δt, η)
