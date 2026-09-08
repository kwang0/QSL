using Test, TOML
include(joinpath(@__DIR__,"../scripts/summarize_relaxation_continuation.jl"))
@testset "Compact replay, incomplete work and spectral comparison" begin
    mktempdir() do directory
        r=TOML.parsefile(joinpath(RC.ROOT,"configs/relaxation_continuation.toml"))
        control=joinpath(directory,"control.snapshot.toml")
        RC.write_toml(control,Dict("artifact_kind"=>"project_b_relaxation_continuation_control","schema_version"=>1,"recipe"=>r))
        hash=RC.sha(control); write(joinpath(directory,"control.sha256"),hash*"\n")
        data=collect_results(directory)
        @test length(data.missing)==7
        for n in (8,16)
            arm="n$(n)_grid1"; label=arm*"_point1"
            cp=Dict("sha256"=>repeat("a",64))
            point=Dict("control_sha256"=>hash,"selected_iterations"=>[n],"checkpoints"=>[cp for _ in 1:n])
            point_path=joinpath(directory,label*".toml"); RC.write_toml(point_path,point)
            RC.write_toml(joinpath(directory,arm*"_outcome.toml"),Dict("control_sha256"=>hash,"continuation_accepted"=>false,
                "budget_complete"=>false,"points"=>[label]))
            spectrum=Dict("lambda_real"=>[0.9,0.8],"lambda_imag"=>[0.1,-0.1],"inverse_xi"=>[0.1,0.2],"requested_modes_converged"=>false)
            a=Dict("control_sha256"=>hash,"point_manifest_sha256"=>RC.sha(point_path),"payload_sha256"=>repeat("a",64),
                "continuation_accepted"=>false,"is_budget_endpoint"=>true,"is_hold_endpoint"=>false,
                "arm"=>arm,"theta_over_pi"=>0.175,"iteration"=>n,"iteration_budget"=>n,"step_over_pi"=>0.025,
                "native_error"=>1e-4,"native_gate_passed"=>false,"energy_density"=>-0.5,"entropy"=>[1.0,1.1],
                "comparisons"=>Dict("accepted_parent"=>Dict("multimetric_passed"=>true,"overlap_floor_passed"=>true,
                    "overlap_per_site"=>0.9999,"maximum_cut_entropy_jump"=>0.001)),"spectra"=>Dict("sz1"=>spectrum))
            RC.write_toml(joinpath(directory,"analysis_"*label*"_iter$(n).toml"),a)
        end
        data=collect_results(directory)
        @test length(data.results)==2 && length(data.missing)==5 && length(data.incomplete)==2
        x=data.results[1]["spectra"]["sz1"]; y=deepcopy(x)
        y["lambda_real"]=reverse(y["lambda_real"]); y["lambda_imag"]=reverse(y["lambda_imag"])
        @test spectrum_distance(x,y)==0
        y["lambda_real"] .+= 0.001
        @test spectrum_distance(x,y)≈0.001 atol=1e-14
        capture=joinpath(directory,"summary.txt")
        open(capture,"w") do io
            redirect_stdout(io) do; summary(directory); end
        end
        message=read(capture,String)
        @test occursin("n8_grid1\tn16_grid1\t0.175",message)
        @test occursin("missing outputs: 5",message)
        @test occursin("false",message) # unconverged requested modes are exposed
        open(io->write(io,"\n# altered\n"),joinpath(directory,"n8_grid1_point1.toml"),"a")
        @test_throws ErrorException collect_results(directory)
    end
end
