using HDF5
using PyPlot


file = "processed_data/magnetization_data2"
F = h5open(file, "r")
Ms = read(F, "Ms")
Bs = read(F, "Bs")
close(F)

file = "processed_data/magnetization_data_perp.h5"
F = h5open(file, "r")
Mperps = read(F, "Ms")
Bperps = read(F, "Bs")
close(F)

J1 = 0.0005
μ_B = 5.788e-5
g_parallel = 3.436
g_perp = 3.037

Bs .*= J1 / (μ_B * g_parallel)
Bperps .*= J1 / (μ_B * g_perp)

Ms .*= g_parallel / 216
Mperps .*= g_perp / 216

fig,ax = plt.subplots()
ax.plot(Bs,Ms, label=latexstring("\$H\\parallel c\$"))
ax.plot(Bperps,Mperps, label=latexstring("\$H\\perp c\$"))
ax.set_xlabel(latexstring("\$\\mu_0H\\: (T)\$"))
ax.set_ylabel(latexstring("\$M\$ (\$\\mu_B/\$Yb\$^{3+}\$)"))
ax.set_title(latexstring("Magnetization data, \$J_1=\\text{0.5meV},\\: J_2/J_1=0.12,\\: \\Delta=1.35\\: (6\\times36\$ cylinder, \$\\chi=512\$)"))
ax.legend()