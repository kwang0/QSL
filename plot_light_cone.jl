using HDF5
using PyPlot

function ind(row, col, C)
    return col * C + mod(row, C) + 1
end

filename = "processed_data/C6_L36_J0.043_B0.0_1Delta1.0_2Delta1.0_chi512_dt0.1_longitudinal_gssearched.h5"

F = h5open(filename,"r")
times = read(F, "times")
corrs = read(F, "corrs")
Zs = read(F, "Zs")
close(F)

C = 6
L = 36
c = div(C*L, 2) # center site

# corrs .+= Zs[c] .* Zs # Disconected correlation

corrs .*= 3/4 # Correct normalization of Paulis and sum over three directions
corrs = conj.(corrs) # Match correlation function to the one in the paper

NN_inds = 6:6:215
NN_corrs = corrs[NN_inds, :]
L = size(NN_corrs,1)

cbar_min = -0.1
cbar_max = 0.1

# create a 2×2 grid for NN and NNN correlations
fig, axes = subplots(2, 2, sharey=true, constrained_layout=true)
# unpack axes array
ax1 = axes[1, 1]
ax2 = axes[1, 2]
ax3 = axes[2, 1]
ax4 = axes[2, 2]
# Plot heat map matching target style
im = ax1.imshow(
    real.(NN_corrs)', interpolation="nearest", origin="lower",
    extent=(1, L, 0, times[end]), aspect="auto",
    cmap="RdBu_r", vmin=cbar_min, vmax=cbar_max
)
# axis labels
ax1.set_ylabel(L"t")

# Imaginary part heat map
im2 = ax2.imshow(
    imag.(NN_corrs)', interpolation="nearest", origin="lower",
    extent=(1, L, 0, times[end]), aspect="auto",
    cmap="RdBu_r", vmin=cbar_min, vmax=cbar_max
)


############################### NNN correlations ##################################


# compute NNN indices with explicit globals to avoid soft-scope warnings
row = 0
col = 1
NNN_inds = Int[]
while col < 35
    push!(NNN_inds, ind(row, col, C))
    if row % 2 == 0
        global row += 1
        global col += 1
    else
        global row += 1
        global col += 2
    end
end

NNN_corrs = corrs[NNN_inds, :]
NNN_corrs += NNN_corrs[end:-1:1, :] # Symmetrize NNN correlations
NNN_corrs ./= 2
L = size(NNN_corrs,1)

# filename = "processed_data/C6_L36_J0.043_B0.0_1Delta1.0_2Delta1.0_chi512_dt0.1_longitudinal_gssearched_YC.h5"

# F = h5open(filename,"r")
# times = read(F, "times")
# corrs = read(F, "corrs")
# Zs = read(F, "Zs")
# close(F)

# # corrs .+= Zs[c] .* Zs # Disconected correlation

# corrs .*= 3/4
# corrs = conj.(corrs) # Match correlation function to the one in the paper

# # NNN_inds = 12:12:216
# NNN_inds = 103:1:108
# NNN_corrs = corrs[NNN_inds, :]
# L = size(NNN_corrs,1)

# cbar_min = -0.01
# cbar_max = 0.01

# NNN real-part heat map
im3 = ax3.imshow(
    real.(NNN_corrs)', interpolation="nearest", origin="lower",
    extent=(1, L, 0, times[end]), aspect="auto",
    cmap="RdBu_r", vmin=cbar_min, vmax=cbar_max
)
ax3.set_ylabel(L"t")
ax3.set_xlabel(L"r")

# NNN imaginary-part heat map
im4 = ax4.imshow(
    imag.(NNN_corrs)', interpolation="nearest", origin="lower",
    extent=(1, L, 0, times[end]), aspect="auto",
    cmap="RdBu_r", vmin=cbar_min, vmax=cbar_max
)
ax4.set_xlabel(L"r")


# Shared colorbars above columns
cbar1 = fig.colorbar(im, ax=[ax1, ax3], orientation="horizontal", pad=0.05, location="top")
cbar1.set_label("Re[G(r,t)]")
cbar1.set_ticks([cbar_min, 0.0, cbar_max])
cbar2 = fig.colorbar(im2, ax=[ax2, ax4], orientation="horizontal", pad=0.05, location="top")
cbar2.set_label("Im[G(r,t)]")
cbar2.set_ticks([cbar_min, 0.0, cbar_max])

# fig.tight_layout()  # Not needed with constrained_layout