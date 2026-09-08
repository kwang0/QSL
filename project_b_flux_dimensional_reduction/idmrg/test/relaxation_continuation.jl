using Test, Random, ProjectBIDMRG, MPSKit, TensorKit, LinearAlgebra, HDF5, TOML
include(joinpath(@__DIR__,"../src/RelaxationContinuation.jl"))
const R=RelaxationContinuation
@testset "Fixed iteration diagnostic and continuous hold" begin
    Random.seed!(927)
    p=Rep[U₁](1=>1,-1=>1)
    v=[Rep[U₁](0=>2,2=>1,-2=>1),Rep[U₁](1=>2,-1=>2)]
    initial=InfiniteMPS(fill(p,2),v;tol=1e-12)
    bond=(;coupling=1.0,anisotropy=1.0,twist_charge=0.25)
    H(theta)=InfiniteMPOHamiltonian(fill(p,2),[(1,2)=>ProjectBIDMRG.two_site_operator(bond,theta),(2,3)=>ProjectBIDMRG.two_site_operator(bond,theta)])
    captured=Ref{Any}()
    result=R.fixed_updates(deepcopy(initial),H(0.2),6;on_record=(x,e,row,h)->(row["iteration"]==3 && (captured[]=deepcopy(x))))
    @test result.reason=="fixed_budget_complete"
    @test [r["iteration"] for r in result.history]==collect(1:6)
    @test all(r["chi"]==4 for r in result.history)
    @test result.history[end]["energy_density"]≈R.SP.energy_density(result.psi,H(0.2),MPSKit.environments(result.psi,H(0.2))) atol=1e-10
    three=R.fixed_updates(deepcopy(initial),H(0.2),3)
    @test [x["native_error"] for x in three.history]≈[x["native_error"] for x in result.history[1:3]] rtol=1e-7
    @test R.SP.energy_density(captured[],H(0.2),MPSKit.environments(captured[],H(0.2)))≈three.history[end]["energy_density"] atol=1e-10
    next=R.fixed_updates(deepcopy(three.psi),H(0.225),2)
    @test length(next.history)==2
    @test isfinite(next.epsilon)
    seen=Ref(0)
    stopped=R.fixed_updates(deepcopy(initial),H(0.2),6;stop_requested=()->seen[]>=2,on_record=(args...)->(seen[]+=1))
    @test length(stopped.history)==2 && stopped.reason=="graceful_stop"
    @test isempty(R.fixed_updates(initial,H(0.2),6;deadline=0).history)
    recipe=TOML.parsefile(joinpath(@__DIR__,"../../configs/relaxation_continuation.toml"))
    @test length(R.RC.arms(recipe))==7
    @test sum(length(a["fluxes"])*a["iterations"]+a["hold_iterations"] for a in R.RC.arms(recipe))==464
    @test R.RC.validate_recipe(recipe)===recipe
    bad=deepcopy(recipe); bad["automatic_promotion"]=true
    @test_throws ErrorException R.RC.validate_recipe(bad)
    bad=deepcopy(recipe); bad["iteration_budgets"]=[8,16,64]
    @test_throws ErrorException R.RC.validate_recipe(bad)
    rows=[Dict("iteration"=>i,"native_error"=>e) for (i,e) in enumerate([8.0,4,2,2.01,2.2,2.3,2.4,1.0])]
    @test R.turnaround(rows,recipe)==7
    @test R.selected_iterations(rows,4,recipe)==[3,4,7,8]
    @test R.selected_iterations(rows[1:2],4,recipe)==[2]
    @test R.selected_iterations([],4,recipe)==[]
    bridge=(;parent_sha256=repeat("a",64),tensors=[
        (;left_charges=ProjectBIDMRG.tensor_basis_charges(space(t,1)),
          physical_charges=ProjectBIDMRG.tensor_basis_charges(space(t,2)),
          right_charges=ProjectBIDMRG.tensor_basis_charges(domain(t)[1])) for t in result.psi.AL])
    mktempdir() do directory
        path=joinpath(directory,"checkpoint.h5")
        stage=Dict("algorithm"=>"VUMPS","theta_over_pi"=>0.2)
        cp=R.SP.write_candidate(path,result.psi,bridge,repeat("b",64),stage,result.history,"fixed_iteration_diagnostic";kind="checkpoint")
        @test cp.sha256==ProjectBIDMRG.file_sha256(path)
        h5open(path,"r") do f
            @test read(f,"history/iteration")==collect(1:6)
            @test !read(f,"continuation_accepted")
        end
        @test_throws ErrorException R.SP.write_candidate(path,result.psi,bridge,repeat("b",64),stage,result.history,"duplicate")
    end
end
