import numpy as np
import argparse
import h5py
import matplotlib.pyplot as plt
from matplotlib import colors

# Anistropy 5x5 graph

# fig, axs = plt.subplots(5,5, sharex=True, sharey=True)

# for i in range(5):
#     for j in range(5):
#         Delta1 = 0.5 + i * 0.25
#         Delta2 = 0.5 + j * 0.25

#         filename = "processed_data/C6_J0.072_1Delta{}_2Delta{}_chi512_dt0.1.h5".format(Delta1, Delta2)
#         S = h5py.File(filename, 'r')['S'][...]

#         im = axs[i,j].imshow(S / max(S.flatten()), cmap="hot", interpolation="gaussian",
#                 norm=colors.LogNorm(vmin=0.0005, vmax=1))
#         x_left, x_right = axs[i,j].get_xlim()
#         y_low, y_high = axs[i,j].get_ylim()
#         axs[i,j].set_aspect(abs((x_right-x_left)/(y_low-y_high))*0.5)

#         if i == 0:
#             axs[i,j].set(xlabel=r'$\Delta_2 = ${}'.format(Delta2))
#             axs[i,j].xaxis.set_label_position('top')
#         if i == 4:
#             axs[i,j].set(xlabel=r'$q$')
#         if j == 4:
#             axs[i,j].set(ylabel=r'$\Delta_1 = ${}'.format(Delta1))
#             axs[i,j].yaxis.set_label_position('right')
#         if j == 0:
#             axs[i,j].set(ylabel=r'$\omega$')
#         axs[i,j].set_xticks(ticks = [0,12,24,36,48,60,71], labels = [r'$\Gamma$', 
#             r'$Y_1$', r'$K$', r'$M$', r'$K$', r'$Y_1$', r'$\Gamma$'])
#         axs[i,j].set_yticks(ticks = [0,10,20], labels = ['2','1','0'])

# plt.subplots_adjust(left=0.1,
#                     bottom=0.1,
#                     right=0.9,
#                     top=0.9,
#                     wspace=0.05,
#                     hspace=0.005)

# cbar_ax = fig.add_axes([0.85, 0.15, 0.025, 0.7])
# fig.subplots_adjust(right=0.8)
# fig.colorbar(im, cax=cbar_ax)
# fig.suptitle(r'$S(q,\omega)$/$S_\mathrm{max}$ for $J_2=0.072$ and varying XXZ anisotropies')

# plt.subplot_tool()

# plt.show()


C = 6
L = 36
J2 = 0.071
B = 0.0
# Delta = 1.0
maxdim = 512
dt = 0.1

nplots = 4
# fig1, axs1 = plt.subplots(1,nplots,sharey=True)
# fig2, axs2 = plt.subplots(1,nplots,sharey=True)
fig3, axs3 = plt.subplots(4,4,sharey=False, sharex=True)

# files = []
# files.append("processed_data/C4_L{}_J{}_B{}_1Delta{}_2Delta{}_chi{}_dt{}.h5".format(L,J2,B,Delta,Delta,maxdim,dt))
# files.append("processed_data/C6_L{}_J{}_1Delta{}_2Delta{}_chi{}_dt{}.h5".format(L,J2,Delta,Delta,maxdim,dt))
# files.append("processed_data/C8_L{}_J{}_B{}_1Delta{}_2Delta{}_chi{}_dt{}.h5".format(L,J2,B,Delta,Delta,maxdim,dt))

# Bs = [[0.0,0.5],[1.0,1.5]]
Deltas = [0.75,1.0,1.25,1.5]
ops = ["longitudinal", "transverse", "transversedown","total"]
# Bs = Bs[::-1]
for i in range(4):
    for j in range(4):
        # B = Bs[i][j]
        Delta = Deltas[i]
        op = ops[j]
        # filename = files[i]
        filename = "processed_data/C{}_L{}_J{}_B{}_1Delta{}_2Delta{}_chi{}_dt{}_{}_disconnectfirst_onesitetdvp.h5".format(C,L,J2,B,Delta,Delta,maxdim,dt,op)
        # filename = "C{}_L{}_J{}_B{}_1Delta{}_2Delta{}_chi{}_dt{}_transverse_disconnectfirst.h5".format(C,L,J2,B,Delta,Delta,maxdim,dt)
        S = h5py.File(filename, 'r')['S'][...]

        S = S / max(S.flatten()) # Normalizing
        S = np.where(S < 0, 0.01, S) # WARNING: SETTING NEGATIVE VALUES TO MIN
        
        ticks = np.array([0,1,2,3,4,5,6]) * S.shape[0] * 1/6

        # im = axs1[i].plot(np.argmax(S[::-1, :],axis=0)/10)
        # if i == 0:
        #     axs1[i].set(ylabel=r'$\omega$')
        # axs1[i].set(title=r'$B=${}'.format(B))
        # axs1[i].set_xticks(ticks = range(0,int(7*L/3),int(L/3)), labels = [r'$\Gamma$', 
        #     r'$Y_1$', r'$K$', r'$M$', r'$K$', r'$Y_1$', r'$\Gamma$'])

        # im = axs2[i].plot(S[::-1, int(2*L/3) + 1] / max(S.flatten()))
        

        # im = axs2[i].plot(S[::-1, 0] / max(S.flatten()))
        # axs2[i].set_xticks(ticks = ticks, labels = ['0','1','2','3','4','5','6'])
        # axs2[i].set(xlabel=r'$\omega$')
        # axs2[i].set(title=r'$B=${}'.format(B))


        im = axs3[i,j].imshow(S, cmap="hot", interpolation="none",
                norm=colors.LogNorm(vmin=0.01, vmax=1))
        x_left, x_right = axs3[i,j].get_xlim()
        y_low, y_high = axs3[i,j].get_ylim()
        axs3[i,j].set_aspect(abs((x_right-x_left)/(y_low-y_high))*0.5)

        # if j == 0:
        #     axs3[i,j].set(ylabel=r'$\omega$')
        # if i == 1:
        #     axs3[i,j].set(xlabel=r'$q$')
        if j == 0:
            axs3[i,j].set(ylabel=r'$\Delta=${}'.format(Delta))
        if i == 3:
            axs3[i,j].set(xlabel=op)
        axs3[i,j].set_xticks(ticks = range(0,int(7*L/3),int(L/3)), labels = [r'$\Gamma$', 
            r'$Y_1$', r'$K$', r'$M$', r'$K$', r'$Y_1$', r'$\Gamma$'])
        axs3[i,j].set_yticks(ticks = ticks, labels = reversed(['0','1','2','3','4','5','6']))
        # axs3[i,j].set(title=r'$B=${}'.format(B))

# plt.subplots_adjust(left=0.1,
#                     bottom=0.1,
#                     right=0.9,
#                     top=0.9,
#                     wspace=0.05,
#                     hspace=0.005)

cbar_ax = fig3.add_axes([0.85, 0.15, 0.025, 0.7])
fig3.subplots_adjust(right=0.8)
fig3.colorbar(im, cax=cbar_ax)
# fig3.suptitle(r'$S(q,\omega)$ for varying external field in QSL phase $J_2/J_1=0.072$ (6$\times$36 cylinder, $\chi=512$)')
# fig1.suptitle(r'argmax$_\omega S(q,\omega)$ for isotropic $J_2=0.072$')
# fig2.suptitle(r'$S(q=K,\omega)$/$S_\mathrm{max}$ for isotropic $J_2=0.072$')

# plt.subplot_tool()

plt.show()