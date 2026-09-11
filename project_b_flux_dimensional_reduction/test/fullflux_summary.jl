using Test, TOML
include("../scripts/summarize_fullflux_continuation.jl")

function fixture(dir)
    r=TOML.parsefile(joinpath(FC.ROOT,"configs/fullflux_continuation.toml"))
    control=joinpath(dir,"control.snapshot.toml")
    FC.write_toml(control,Dict("artifact_kind"=>"project_b_fullflux_control","schema_version"=>1,"recipe"=>r))
    hash=FC.sha(control); write(joinpath(dir,"control.sha256"),hash*"\n")
    lineage=Dict("control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"continuation_accepted"=>false)
    obs=Dict("energy_density"=>-.5,"entropy"=>[.2,.3],"energy_terms"=>[-.4,-.6],"magnetization_z"=>[0.,0.])
    comparison=Dict("maximum_cut_entropy_jump"=>0.,"energy_term_rms_jump"=>0.,"magnetization_rms_jump"=>0.,
        "multimetric_passed"=>true,"overlap_floor_passed"=>true,"overlap_per_site"=>1.)
    spectrum=Dict("inverse_xi"=>[.2,.3],"two_k1"=>[0.,pi],"k2"=>[0.,pi],"requested_modes_converged"=>true)
    row(i)=Dict("iteration"=>i,"native_error"=>1e-4,"energy_density"=>-.5,"chi"=>512,"wall_seconds"=>1.,"cpu_seconds"=>2.)
    function output(manifest,cp,h,meta,refs,label)
        a=merge(lineage,obs,meta,Dict("artifact_kind"=>"project_b_fullflux_analysis","schema_version"=>1,
            "payload_sha256"=>cp["sha256"],"point_manifest_sha256"=>FC.sha(manifest),
            "theta_over_pi"=>cp["theta_over_pi"],"iteration"=>h[end]["iteration"],"native_error"=>1e-4,
            "native_gate_passed"=>false,"native_gate_applicable"=>length(h)>=4,"cross_library_energy_difference"=>0.,
            "reference_payload_sha256"=>refs,"reference_observables"=>Dict(k=>obs for k in keys(refs)),
            "comparisons"=>Dict(k=>comparison for k in keys(refs)),"spectra"=>Dict("sz0"=>spectrum,"sz1"=>spectrum)))
        FC.write_toml(joinpath(dir,"analysis_"*label*".toml"),a)
    end
    for arm in FC.arms(r)
        name=arm["name"]; n=arm["iterations"]
        origin=Dict("iteration"=>0,"theta_over_pi"=>.15,"sha256"=>repeat("a",64),"path"=>"synthetic_origin")
        path=joinpath(dir,name*"_origin.toml")
        FC.write_toml(path,merge(lineage,Dict("payload"=>origin,"history"=>[row(0)])))
        output(path,origin,[row(0)],Dict("arm"=>name,"stage"=>name*"_origin","point"=>0,"iteration_budget"=>0,
            "is_budget_endpoint"=>false,"cumulative_updates"=>0),Dict("accepted_parent"=>r["parent_sha256"]),name*"_origin")
        previous=origin; labels=String[]
        for (j,theta) in enumerate(arm["fluxes"])
            label=name*"_point$j"; push!(labels,label); path=joinpath(dir,label*".toml"); h=[row(i) for i in 1:n]
            cps=[Dict("iteration"=>i,"theta_over_pi"=>theta,"sha256"=>lpad(string(n*1000+j*10+i),64,'0'),
                "path"=>"synthetic_$name.$j.$i","native_gate_passed"=>false) for i in 1:n]
            p=merge(lineage,Dict("stage"=>label,"arm"=>name,"point"=>j,"theta_over_pi"=>theta,"iteration_budget"=>n,
                "delta_theta_over_pi"=>FC.actual_step(r,j),"cumulative_updates_before"=>(j-1)*n,"origin"=>origin,
                "diagnostic_seed"=>previous,"history"=>h,"checkpoints"=>cps,"budget_complete"=>true))
            FC.write_toml(path,p)
            open(joinpath(dir,label*"_history.tsv"),"w") do io
                println(io,"iteration\tnative_error\tenergy_density\tchi\twall_seconds\tcpu_seconds\tpayload_sha256")
                for (i,cp) in enumerate(cps)
                    println(io,join((i,1e-4,-.5,512,1.,2.,cp["sha256"]),'\t'))
                    FC.write_toml(joinpath(dir,label*"_iter$i.toml"),merge(lineage,cp,Dict("record"=>h[i],"diagnostic_seed"=>previous)))
                end
            end
            output(path,last(cps),h,Dict("arm"=>name,"stage"=>label,"point"=>j,"iteration_budget"=>n,
                "is_budget_endpoint"=>true,"cumulative_updates"=>(j-1)*n+n,"delta_theta_over_pi"=>p["delta_theta_over_pi"]),
                Dict("accepted_parent"=>r["parent_sha256"],"previous_flux"=>previous["sha256"]),label*"_iter$n")
            previous=last(cps)
        end
        FC.write_toml(joinpath(dir,name*"_outcome.toml"),merge(lineage,Dict("points"=>labels,"budget_complete"=>true)))
    end
end

@testset "Full-flux completion and evidence integrity" begin
    mktempdir() do dir
        fixture(dir); d=collect_results(dir)
        @test d.complete && length(d.samples)==30 && count(x->x["theta_over_pi"]==1,d.samples)==3
        @test all(!x["native_gate_applicable"] for x in d.samples if x["arm"]=="n2")
        open(joinpath(dir,"summary.txt"),"w") do io
            redirect_stdout(()->summary(dir),io)
        end
        @test occursin("EXPERIMENT_COMPLETE=true",read(joinpath(dir,"summary.txt"),String))
        steps=joinpath(dir,"step_exit_codes.tsv"); write(steps,"step\texit_code\nanalysis_n8\t1\n")
        @test !collect_results(dir).complete
        rm(steps)
        path=joinpath(dir,"analysis_n8_point9_iter8.toml"); original=read(path,String)
        a=TOML.parsefile(path); a["reference_payload_sha256"]["previous_flux"]=repeat("b",64)
        open(io->TOML.print(io,a),path,"w")
        @test_throws ErrorException collect_results(dir)
        write(path,original)
        rm(path)
        @test !collect_results(dir).complete
        partial=Dict("checkpoints"=>[Dict("iteration"=>1)],"budget_complete"=>false)
        @test only(FC.selected_checkpoints(partial))["iteration"]==1 && isempty(FC.selected_checkpoints(Dict("checkpoints"=>[])))
    end
end
