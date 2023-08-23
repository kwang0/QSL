using CSV
using DataFrames
using PyPlot
using HDF5

filename = 

F = h5open(filename,"r")
times = read(F, "times")
corrs = read(F, "corrs")

close(F)