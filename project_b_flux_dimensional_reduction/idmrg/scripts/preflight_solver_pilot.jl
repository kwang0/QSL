println("Loading the isolated MPSKit environment; first-use compilation can take several minutes."); flush(stdout)
using ProjectBIDMRG, MPSKit, TensorKit, LinearAlgebra
include(joinpath(@__DIR__,"../src/SolverPilot.jl"))
ProjectBIDMRG.require_exact_environment()
physical=ℂ^2; virtual=ℂ^2
sz=TensorMap(ComplexF64[0.5 0;0 -0.5],physical←physical)
sx=TensorMap(ComplexF64[0 0.5;0.5 0],physical←physical)
H=InfiniteMPOHamiltonian(fill(physical,2),[(1,2)=>sz⊗sz,(2,3)=>sz⊗sz,(1,)=>0.3sx,(2,)=>0.3sx])
for algorithm in ("VUMPS","GradientGrassmann")
    println("Executable preflight: ",algorithm," on a tiny test state (two iterations)"); flush(stdout)
    psi=InfiniteMPS(fill(physical,2),fill(virtual,2);tol=1e-10)
    result=SolverPilot.solve_kernel(psi,H,algorithm;maxiter=2,tolerance=1e-10)
    !isempty(result.history) && all(r->isfinite(r["native_error"]),result.history) ||
        error("pilot kernel preflight failed")
end
println("Executable preflight: HDF5 I/O"); flush(stdout)
ProjectBIDMRG.benchmark_result_io_preflight()
println("Solver pilot executable preflight passed: VUMPS, GradientGrassmann, HDF5 I/O")
