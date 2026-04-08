using HDF5
using Glob

# Copying data excluding large memory MPSs for easier transfer to local machine

# for input in glob("ground_state_search_YC*.h5", "/pscratch/sd/k/kwang98/QSL/")
for input in glob("*u1_YC*.h5", "./")
output = "processed_data/" * basename(input)

F = h5open(input,"r")
G = h5open(output,"w")
for s in keys(F)
	if (s != "psi0" && s != "psi_spin" && s != "psi_elec")
		G[s] = read(F,s)
	end
end

close(F)
close(G)

end
