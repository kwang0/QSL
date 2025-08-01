import numpy as np
import argparse
import h5py
import matplotlib.pyplot as plt
from matplotlib import colors

C = 6
L = 36
J2 = 0.043
B = 0.0
Delta = 1.0
maxdim = 512
dt = 0.1
op = "longitudinal"

fig, axs = plt.subplots()

filename = "processed_data/C{}_L{}_J{}_B{}_1Delta{}_2Delta{}_chi{}_dt{}_{}_gssearched.h5".format(C,L,J2,B,Delta,Delta,maxdim,dt,op)
S_XC = h5py.File(filename, 'r')['S'][...]
filename = "processed_data/C{}_L{}_J{}_B{}_1Delta{}_2Delta{}_chi{}_dt{}_{}_gssearched_YC_1f10.h5".format(C,L,J2,B,Delta,Delta,maxdim,dt,op)
S_YC = h5py.File(filename, 'r')['S'][...]
# S = S[20:,0:36]

S = np.concatenate((S_XC, S_YC[:,-1::-1]), axis=1)

S = S / max(S.flatten()) # Normalizing
S = np.where(S < 0, 0.01, S) # WARNING: SETTING NEGATIVE VALUES TO MIN

ticks = np.array([0,1,2,3]) * (S.shape[0]-1) * 1/3

im = axs.imshow(S, cmap="hot", interpolation="nearest",
        norm=colors.LogNorm(vmin=0.01, vmax=1))
x_left, x_right = axs.get_xlim()
y_low, y_high = axs.get_ylim()
axs.set_aspect(abs((x_right-x_left)/(y_low-y_high)))

axs.set(ylabel=r'$\omega$')
axs.set(xlabel=r'$q$')

axs.set_xticks(ticks = range(0,int(4*L/3),int(L/3)), labels = [r'$\Gamma$', 
    r'$Y_1$', r'$K$', r'$M$'])
axs.set_yticks(ticks = ticks, labels = reversed(['0','1','2','3']))
plt.tight_layout()

cbar_ax = fig.add_axes([0.85, 0.15, 0.025, 0.7])
fig.subplots_adjust(right=0.8)
fig.colorbar(im, cax=cbar_ax)
# fig.suptitle(r'Magnetic cross-section for varying $B||c$ in QSL phase $J_2/J_1=0.12,\Delta=1.35$ (6$\times$36 cylinder, $\chi=512$)')

plt.show()