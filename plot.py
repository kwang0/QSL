import numpy as np
import argparse
import h5py
import matplotlib.pyplot as plt
from matplotlib import colors

fig, axs = plt.subplots(5,5, sharex=True, sharey=True)

for i in range(5):
    for j in range(5):
        Delta1 = 0.5 + i * 0.25
        Delta2 = 0.5 + j * 0.25

        filename = "processed_data/C6_J0.072_1Delta{}_2Delta{}_chi512_dt0.1.h5".format(Delta1, Delta2)
        S = h5py.File(filename, 'r')['S'][...]

        im = axs[i,j].imshow(S / max(S.flatten()), cmap="hot", interpolation="gaussian",
                norm=colors.LogNorm(vmin=0.0005, vmax=1))
        x_left, x_right = axs[i,j].get_xlim()
        y_low, y_high = axs[i,j].get_ylim()
        axs[i,j].set_aspect(abs((x_right-x_left)/(y_low-y_high))*0.5)

        if i == 0:
            axs[i,j].set(xlabel=r'$\Delta_2 = ${}'.format(Delta2))
            axs[i,j].xaxis.set_label_position('top')
        if i == 4:
            axs[i,j].set(xlabel=r'$q$')
        if j == 4:
            axs[i,j].set(ylabel=r'$\Delta_1 = ${}'.format(Delta1))
            axs[i,j].yaxis.set_label_position('right')
        if j == 0:
            axs[i,j].set(ylabel=r'$\omega$')
        axs[i,j].set_xticks(ticks = [0,12,24,36,48,60,71], labels = [r'$\Gamma$', 
            r'$Y_1$', r'$K$', r'$M$', r'$K$', r'$Y_1$', r'$\Gamma$'])
        axs[i,j].set_yticks(ticks = [0,10,20], labels = ['2','1','0'])

plt.subplots_adjust(left=0.1,
                    bottom=0.1,
                    right=0.9,
                    top=0.9,
                    wspace=0.05,
                    hspace=0.005)

cbar_ax = fig.add_axes([0.85, 0.15, 0.025, 0.7])
fig.subplots_adjust(right=0.8)
fig.colorbar(im, cax=cbar_ax)
fig.suptitle(r'$S(q,\omega)$/$S_\mathrm{max}$ for $J_2=0.072$ and varying XXZ anisotropies')

plt.subplot_tool()

plt.show()