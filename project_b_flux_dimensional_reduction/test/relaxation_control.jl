using Test, TOML
include(joinpath(@__DIR__,"../scripts/lib/RelaxationControl.jl"))
const RC=RelaxationControl
@testset "Sealed diagnostic schedule and budget" begin
    r=TOML.parsefile(joinpath(RC.ROOT,"configs/relaxation_continuation.toml"))
    @test RC.validate_recipe(r)===r
    a=RC.arms(r)
    @test [x["name"] for x in a]==["baseline","n8_grid1","n8_grid2","n16_grid1","n16_grid2","n32_grid1","n32_grid2"]
    @test a[2]["fluxes"]==[0.175,0.2]
    @test a[3]["fluxes"]==[0.1625,0.175,0.1875,0.2]
    @test all(x["hold_iterations"]==16 for x in a[2:end])
    @test RC.P.ProjectBAccounting.reservation(10,"16G","36:00:00").node_hours==1.40625
    for key in ("automatic_promotion","advance_on_turnaround")
        bad=deepcopy(r); bad[key]=true
        @test_throws ErrorException RC.validate_recipe(bad)
    end
    bad=deepcopy(r); bad["resources"]["allocation_cpus"]=8
    @test_throws ErrorException RC.validate_recipe(bad)
    @test_throws ErrorException RC.root_path(RC.ROOT,"../escape")
    mktempdir() do directory
        file=joinpath(directory,"immutable.toml")
        RC.write_toml(file,Dict("value"=>1))
        @test_throws ErrorException RC.write_toml(file,Dict("value"=>2))
        @test TOML.parsefile(file)["value"]==1
    end
    for file in RC.required_sources()
        endswith(file,".jl") || continue
        expression=Meta.parseall(read(joinpath(RC.ROOT,file),String))
        function has_error(x)
            x isa Expr && (x.head in (:error,:incomplete) || any(has_error,x.args))
        end
        has_error(expression) && println("Parse failure in ",file)
        @test !has_error(expression)
    end
end
if !isempty(ARGS)
    length(ARGS)==1 || error("optional CONTROL argument")
    @testset "Live-input structure and shared accounting" begin
        c=RC.validate(only(ARGS))
        @test RC.validate(only(ARGS);code_only=true)==c
        @test length(c["inputs"])==length(RC.required_sources())+2
        @test "output/mpskit_solver_pilot_jobs" in TOML.parsefile(joinpath(RC.ROOT,"configs/project_b_accounting.toml"))["run_roots"]
        snap=RC.P.ProjectBAccounting.snapshot(RC.ROOT)
        RC.P.ProjectBAccounting.assert_budget(RC.ROOT,snap,c["recipe"]["resources"]["forecast_node_hours"])
        @test snap.phase1+c["recipe"]["resources"]["forecast_node_hours"]<20
    end
end
