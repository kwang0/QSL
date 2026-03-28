using HDF5
using Glob

# Copying data excluding large memory MPSs for easier transfer to local machine

for input in glob("ground_state_search_YC*.h5", "/pscratch/sd/k/kwang98/QSL/")
output = "processed_data/" * basename(input)

F = h5open(input,"r")
G = h5open(output,"w")
for s in keys(F)
	if (s != "psi0")
		G[s] = read(F,s)
	end
end

close(F)
close(G)

end
