# Local integration fixture: canonicalize the accepted bridge, no optimization.
using ProjectBIDMRG, MPSKit, TOML
include(joinpath(@__DIR__,"../../scripts/lib/SolverPilotControl.jl"))
include(joinpath(@__DIR__,"../src/SolverPilot.jl"))
length(ARGS)==2 || error("usage: create_pilot_identity_fixture.jl CONTROL NEW_OUTPUT_DIRECTORY")
c=SolverPilotControl.validate(ARGS[1]); root=SolverPilotControl.ROOT
directory=abspath(ARGS[2]); ispath(directory) && error("fixture output exists")
b=ProjectBIDMRG.load_bridge(joinpath(root,c["recipe"]["bridge_path"]))
b=merge(b,(;target_theta=0.15))
println("Building canonical chi512 state"); flush(stdout)
psi=ProjectBIDMRG.build_state(b)
println("Building Hamiltonian and environments"); flush(stdout)
H=ProjectBIDMRG.build_hamiltonian(b)
envs=MPSKit.environments(psi,H)
println("Evaluating energy and Galerkin error"); flush(stdout)
energy=SolverPilot.energy_density(psi,H,envs)
epsilon=Float64(MPSKit.calc_galerkin(psi,H,psi,envs))
row=Dict("iteration"=>0,"native_error"=>epsilon,"energy_density"=>energy,"chi"=>512,
    "wall_seconds"=>0.0,"cpu_seconds"=>0.0)
stage=Dict("name"=>"identity_fixture","algorithm"=>"VUMPS","theta_over_pi"=>0.15)
hash=SolverPilotControl.sha(ARGS[1])
payload=SolverPilot.write_candidate(joinpath(directory,"identity.h5"),psi,b,hash,stage,[row],"no_optimization";kind="test_fixture")
record=Dict("artifact_kind"=>"project_b_mpskit_solver_pilot_stage","schema_version"=>1,
    "stage"=>"identity_fixture","algorithm"=>"VUMPS","theta_over_pi"=>0.15,
    "control_sha256"=>hash,"parent_sha256"=>b.parent_sha256,
    "result_path"=>payload.path,"result_sha256"=>payload.sha256,"history"=>[row],
    "native_gate_passed"=>false,"fixture_only"=>true,"optimization_performed"=>false)
manifest=joinpath(directory,"identity.toml")
open(io->TOML.print(io,record;sorted=true),manifest,"w")
println("Canonical MPSKit identity fixture: ",manifest)
println("Energy density: ",energy,"; reference: ",c["parent_energy_density_at_0p15"])
