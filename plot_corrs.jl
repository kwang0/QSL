using HDF5
using PyPlot
using PyCall
@pyimport matplotlib.widgets as widgets

function ind(row, col, C)
    return col * C + mod(row, C) + 1
end

filename = "processed_data/C6_L36_J0.043_B0.0_1Delta1.0_2Delta1.0_chi512_dt0.1_longitudinal_gssearched_YC_1f10.h5"
# filename = "processed_data/C6_L36_J0.043_B0.0_1Delta1.0_2Delta1.0_chi512_dt0.1_longitudinal_gssearched.h5"

F = h5open(filename,"r")
times = read(F, "times")
corrs = read(F, "corrs")
Zs = read(F, "Zs")
close(F)

C = 6
L = 36
c = size(corrs, 1) ÷ 2 # Center site
num_times = size(corrs, 2)

corrs = reshape(real.(corrs), C, L, num_times)

# initial slice index
idx0 = 1
cbar_min = -0.2
cbar_max = 0.2

# create figure and main axes
fig, ax = subplots()
# show the first slice
img = ax.imshow(corrs[:, :, idx0], cmap="RdBu_r", vmin=cbar_min, vmax=cbar_max, origin="lower")
ax.set_title("Slice $idx0 of $num_times")

# create an axes for the slider: [left, bottom, width, height] in fraction of figure
ax_slider = fig.add_axes([0.25, 0.05, 0.50, 0.03])

# make the slider: name "Slice", range 1→K, initial value idx0
slider = widgets.Slider(
    ax_slider,            # the axes to draw the slider in
    "Slice",              # slider label
    1,                  # minimum value
    num_times,                    # maximum value
    valinit=idx0,         # initial value
    valfmt="%0.0f"        # format as integer
)

# define what happens when the slider value changes
function update(val)
    i = Int(round(val))
    img.set_data(corrs[:, :, i])        # update image data
    ax.set_title("Slice $i of $num_times")     # update title (optional)
    fig.canvas.draw_idle()             # redraw
end

# connect the slider to the update function
slider.on_changed(update)

# display
fig.tight_layout()
show()
