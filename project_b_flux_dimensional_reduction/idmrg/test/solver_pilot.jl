using ProjectBIDMRG, MPSKit, TensorKit, Test, HDF5, LinearAlgebra, Random
include(joinpath(@__DIR__,"../src/SolverPilot.jl"))
const SP=SolverPilot
const IB=ProjectBIDMRG
@testset "U1 solver pilot, stop and immutable tensor export" begin
    Random.seed!(731)
    p=Rep[U₁](1=>1,-1=>1)
    v=[Rep[U₁](0=>2,2=>1,-2=>1),Rep[U₁](1=>2,-1=>2)]
    initial=InfiniteMPS(fill(p,2),v;tol=1e-10)
    bond=(;coupling=1.0,anisotropy=1.0,twist_charge=0.0)
    H=InfiniteMPOHamiltonian(fill(p,2),[(1,2)=>IB.two_site_operator(bond,0.0),(2,3)=>IB.two_site_operator(bond,0.0)])
    bridge=(;parent_sha256=repeat("a",64),tensors=[
        (;left_charges=IB.tensor_basis_charges(space(t,1)),
          physical_charges=IB.tensor_basis_charges(space(t,2)),
          right_charges=IB.tensor_basis_charges(domain(t)[1])) for t in initial.AL])
    for algorithm in ("VUMPS","GradientGrassmann")
        completed=Ref(0)
        result=SP.solve_kernel(copy(initial),H,algorithm;maxiter=3,tolerance=1e-12,
            stop_requested=()->completed[]>0,on_record=(x,e,row,h)->(completed[]+=1))
        @test length(result.history)==1
        @test result.reason=="graceful_stop"
        @test all(isfinite(r["energy_density"]) for r in result.history)
        @test result.history[end]["energy_density"]<=result.initial_energy+1e-8
        @test result.history[end]["energy_density"]≈SP.energy_density(result.psi,H,MPSKit.environments(result.psi,H)) atol=1e-8
        mktempdir() do dir
            path=joinpath(dir,"candidate.h5")
            stage=Dict("algorithm"=>algorithm,"theta_over_pi"=>0.0)
            artifact=SP.write_candidate(path,result.psi,bridge,repeat("b",64),stage,result.history,result.reason)
            @test artifact.sha256==IB.file_sha256(path)
            h5open(path,"r") do f
                @test read(f,"history/native_error")==[result.history[1]["native_error"]]
                @test read(f,"continuation_accepted")==false
                for site in 1:2
                    data=read(f,"state/site_$site/AL")
                    tensor=IB.bridge_tensor(merge(bridge.tensors[site],(;data)))
                    @test norm(tensor-result.psi.AL[site])<1e-12
                    ar=IB.bridge_tensor(merge(bridge.tensors[site],(;data=read(f,"state/site_$site/AR"))))
                    @test norm(ar-result.psi.AR[site])<1e-12
                    entry=bridge.tensors[site]
                    perm=IB.basis_permutation(entry.right_charges,IB.tensor_basis_charges(space(result.psi.C[site],1)))
                    @test norm(read(f,"state/site_$site/C")[perm,perm]-convert(Array,result.psi.C[site]))<1e-12
                end
            end
            @test_throws ErrorException SP.write_candidate(path,result.psi,bridge,repeat("b",64),stage,result.history,result.reason)
        end
    end
    stopped=SP.solve_kernel(copy(initial),H,"VUMPS";stop_requested=()->true)
    @test isempty(stopped.history)
    @test stopped.reason=="stop_before_iteration"
end
