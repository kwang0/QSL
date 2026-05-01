include("triangular_gutzwiller_mps.jl")
using .TriangularGutzwillerMPS
using HDF5
using ITensors
using ITensorMPS
using MKL
using CUDA
using LinearAlgebra

ITensors.Strided.set_num_threads(1)
BLAS.set_num_threads(1)
# ITensors.enable_threaded_blocksparse(true)

C = parse(Int64, ARGS[1])
L = parse(Int64, ARGS[2])
maxdim = parse(Int64, ARGS[3])

lat = TriangularYC(C, L)
res = prepare_u1_dsl_gutzwiller_mps(
                  lat;
                  theta=0.0,
                  phi=0.0,
                  gauge=:auto,
                  maxdim=maxdim,
                  cutoff=1e-8,
                  verbose=true,
                  use_cuda=true)

corrs = correlation_matrix(res.psi_spin, "Sz", "Sz")
corrs_unprojected = correlation_matrix(res.psi_elec, "Sz", "Sz")
Zs = expect(res.psi_spin, "Sz")

file = "/pscratch/sd/k/kwang98/QSL/mps_site_centered_u1_YC_theta0_phi0_C$(C)_L$(L)_m0_chi$(maxdim).h5"
F = h5open(file, "w")
F["psi_spin"] = ITensors.cpu(res.psi_spin)
F["psi_elec"] = ITensors.cpu(res.psi_elec)
F["corrs"] = corrs
F["corrs_unprojected"] = corrs_unprojected
F["Zs"] = Zs
close(F)