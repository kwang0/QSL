using Test, Random, Serialization, TOML
include("../thread_benchmark/Benchmark.jl")
const T=ThreadBenchmark
using .ThreadBenchmark: MPSKit, TensorKit, LinearAlgebra
using MPSKit, TensorKit, LinearAlgebra
length(ARGS)==2 || error("usage: thread_benchmark.jl VALIDATION_DIR BLAS_THREADS")
directory=abspath(ARGS[1]); nt=parse(Int,ARGS[2]); BLAS.set_num_threads(nt)
@test BLAS.get_num_threads()==nt
T.B.require_exact_environment()

if Threads.nthreads()==2 && nt==1
    b=T.load_al(joinpath(directory,"real_seed_al.h5")); psi=T.import_al(b)
    @test b.chi==512
    @test maximum(values(T.canonical_errors(psi)))<1e-8
    H=T.B.build_hamiltonian(b)
    energy=T.R.SP.energy_density(psi,H,MPSKit.environments(psi,H))
    @test abs(energy-b.source_energy)<1e-6
    println("Real chi512 import energy difference: ",energy-b.source_energy)
end

# Small period-two U1 state exercises canonical restart and identical fixed-update
# trajectories under all three thread settings, without a large solver test.
Random.seed!(927)
p=Rep[U₁](1=>1,-1=>1)
v=[Rep[U₁](0=>2,2=>1,-2=>1),Rep[U₁](1=>2,-1=>2)]
seedpath=joinpath(directory,"small_canonical_seed.jls")
if !isfile(seedpath)
    @test Threads.nthreads()==2 && nt==1
    psi=InfiniteMPS(fill(p,2),v;tol=1e-12)
    serialize(seedpath,psi)
end
psi=deserialize(seedpath)
@test maximum(values(T.canonical_errors(psi)))<1e-8
entries=[(;data=convert(Array,psi.AL[i]),left_charges=T.B.tensor_basis_charges(space(psi.AL[i],1)),
    physical_charges=T.B.tensor_basis_charges(space(psi.AL[i],2)),
    right_charges=T.B.tensor_basis_charges(domain(psi.AL[i])[1])) for i in 1:2]
imported=T.import_al((;entries,chi=4))
@test all(dim(right_virtualspace(imported,i))==4 for i in 1:2)
bond=(;coupling=1.0,anisotropy=1.0,twist_charge=.25)
H=InfiniteMPOHamiltonian(fill(p,2),[(1,2)=>T.B.two_site_operator(bond,.2),(2,3)=>T.B.two_site_operator(bond,.2)])
result=T.R.fixed_updates(psi,H,4)
@test length(result.history)==4
@test all(h["chi"]==4 && isfinite(h["native_error"]) && h["wall_seconds"]>0 for h in result.history)
name="j$(Threads.nthreads())_b$nt"
T.C.write_toml(joinpath(directory,name*".toml"),Dict("history"=>result.history))
baseline=TOML.parsefile(joinpath(directory,"j2_b1.toml"))["history"]
@test all(abs(h["energy_density"]-base["energy_density"])<1e-8 &&
    isapprox(h["native_error"],base["native_error"];rtol=1e-3,atol=1e-12) for (h,base) in zip(result.history,baseline))
println("Thread setting ",name,": canonical restart and matched trajectory passed.")
