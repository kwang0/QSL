using Test, TOML
include("../scripts/roundtrip/Control.jl")
const C=RoundTripControl
@testset "Coupled density and return schedule" begin
    r=C.validate_recipe(TOML.parsefile(joinpath(C.ROOT,"configs/roundtrip_continuation.toml")))
    a=C.arms(r)
    @test [x["name"] for x in a]==["n2_grid1","n1_grid2","n4_grid1","n2_grid2"]
    @test [length(x["fluxes"])*x["iterations"] for x in a]==[16,16,32,32]
    @test [x["updates_per_theta_over_pi"] for x in a]==[80,80,160,160]
    @test a[1]["fluxes"]==[0.175,0.2,0.225,0.25,0.225,0.2,0.175,0.15]
    @test a[1]["paired_forward_points"]==[-1,-1,-1,-1,3,2,1,0]
    for arm in a
        @test count(==(0.25),arm["fluxes"])==1
        @test last(arm["fluxes"])==0.15
        for j in eachindex(arm["fluxes"])
            i=arm["paired_forward_points"][j]
            i<0 && continue
            @test arm["fluxes"][j]==(i==0 ? 0.15 : arm["fluxes"][i])
        end
    end
    for (key,value) in [("turn_theta_over_pi",0.3),("automatic_promotion",true),("coarse_iteration_budgets",[4,8]),("chi",1024)]
        bad=deepcopy(r); bad[key]=value
        @test_throws ErrorException C.validate_recipe(bad)
    end
    bad=deepcopy(r); bad["continuity"]["maximum_cut_entropy_jump"]=0.2
    @test_throws ErrorException C.validate_recipe(bad)
    @test C.R.P.ProjectBAccounting.reservation(10,"16G","14:00:00").node_hours==0.546875
    for f in C.required_sources()
        endswith(f,".jl") || continue
        expression=Meta.parseall(read(joinpath(C.ROOT,f),String))
        has_error(x)=x isa Expr && (x.head in (:error,:incomplete) || any(has_error,x.args))
        has_error(expression) && println("Parse failure: ",f)
        @test !has_error(expression)
    end
end
if !isempty(ARGS)
    @testset "Sealed inputs and remaining Phase 1 budget" begin
        c=C.validate(only(ARGS))
        @test C.validate(only(ARGS);code_only=true)==c
        snap=C.R.P.ProjectBAccounting.snapshot(C.ROOT)
        C.R.P.ProjectBAccounting.assert_budget(C.ROOT,snap,c["recipe"]["resources"]["forecast_node_hours"])
        @test snap.phase1+c["recipe"]["resources"]["forecast_node_hours"]<20
        @test C.R.validate(joinpath(C.ROOT,"configs/controls/relaxation_continuation_v1.toml"))["recipe"]["end_theta_over_pi"]==0.2
    end
end
