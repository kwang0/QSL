using Test
include("../scripts/summarize_roundtrip_continuation.jl")
@testset "Missing arms and native gate applicability" begin
    r=TOML.parsefile(joinpath(RC.ROOT,"configs/roundtrip_continuation.toml"))
    mktempdir() do dir
        control=joinpath(dir,"control.snapshot.toml")
        RC.write_toml(control,Dict("artifact_kind"=>"project_b_roundtrip_control","schema_version"=>1,"recipe"=>r))
        write(joinpath(dir,"control.sha256"),RC.sha(control)*"\n")
        d=collect_results(dir)
        @test !d.complete && length(d.missing)==4 && isempty(d.samples)
        write(joinpath(dir,"control.sha256"),repeat("a",64))
        @test_throws ErrorException collect_results(dir)
    end
    h=[Dict("chi"=>512,"native_error"=>1e-6,"energy_density"=>-.5) for i in 1:4]
    @test !native_gate(h[1:2],r)
    @test native_gate(h,r)
    h[end]["native_error"]=1e-4
    @test !native_gate(h,r)
    x=Dict("lambda_real"=>[.8,.6],"lambda_imag"=>[.1,-.2])
    y=Dict("lambda_real"=>[.6,.8],"lambda_imag"=>[-.2,.1])
    @test spectrum_distance(x,y)==0
    y["lambda_real"][1]+=.01
    @test spectrum_distance(x,y)≈.01
end

# Compact schema fixture: explicit synthetic records, no tensor calculations.
function fixture(dir)
    r=TOML.parsefile(joinpath(RC.ROOT,"configs/roundtrip_continuation.toml"))
    control=joinpath(dir,"control.snapshot.toml")
    RC.write_toml(control,Dict("artifact_kind"=>"project_b_roundtrip_control","schema_version"=>1,"recipe"=>r))
    hash=RC.sha(control); write(joinpath(dir,"control.sha256"),hash*"\n")
    obs=Dict("energy_density"=>-.5,"entropy"=>[.2,.3],"energy_terms"=>[-.4,-.6],"magnetization_z"=>[0.,0.])
    d=Dict("maximum_cut_entropy_jump"=>0.,"energy_term_rms_jump"=>0.,"magnetization_rms_jump"=>0.,
        "multimetric_passed"=>true,"overlap_floor_passed"=>true,"overlap_per_site"=>1.)
    spectrum=Dict("lambda_real"=>[.8,.6],"lambda_imag"=>[.1,-.2],"inverse_xi"=>[.2,.3],"requested_modes_converged"=>true)
    row(i)=Dict("iteration"=>i,"native_error"=>1e-4,"energy_density"=>-.5,"chi"=>512,"wall_seconds"=>1.,"cpu_seconds"=>2.)
    function output(manifest,cp,h,meta,refs,label)
        a=merge(Dict("artifact_kind"=>"project_b_roundtrip_analysis","schema_version"=>1,"control_sha256"=>hash,
            "parent_sha256"=>r["parent_sha256"],"continuation_accepted"=>false,"payload_sha256"=>cp["sha256"],
            "point_manifest_sha256"=>RC.sha(manifest),"theta_over_pi"=>cp["theta_over_pi"],"iteration"=>h[end]["iteration"],
            "native_error"=>1e-4,"native_gate_passed"=>false,"native_gate_applicable"=>length(h)>=4,"cross_library_energy_difference"=>0.,
            "reference_payload_sha256"=>refs,"reference_observables"=>Dict(k=>obs for k in keys(refs)),
            "comparisons"=>Dict(k=>d for k in keys(refs)),"spectra"=>Dict("sz0"=>spectrum,"sz1"=>spectrum)),obs,meta)
        RC.write_toml(joinpath(dir,"analysis_"*label*".toml"),a)
    end
    for arm in RC.arms(r)
        name=arm["name"]; origin=Dict("iteration"=>0,"theta_over_pi"=>.15,"sha256"=>repeat("a",64),"path"=>"synthetic_origin")
        path=joinpath(dir,name*"_origin.toml")
        RC.write_toml(path,Dict("control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"continuation_accepted"=>false,"payload"=>origin,"history"=>[row(0)]))
        output(path,origin,[row(0)],Dict("arm"=>name,"stage"=>name*"_origin","point"=>0,"direction"=>"origin","iteration_budget"=>0,
            "is_budget_endpoint"=>false,"cumulative_updates"=>0),Dict("accepted_parent"=>r["parent_sha256"]),name*"_origin")
        previous=origin; forwards=Dict{Int,Any}(0=>origin); labels=String[]
        for j in eachindex(arm["fluxes"])
            label=name*"_point$j"; push!(labels,label); path=joinpath(dir,label*".toml"); n=arm["iterations"]
            h=[row(i) for i in 1:n]
            cps=[Dict("iteration"=>i,"theta_over_pi"=>arm["fluxes"][j],"sha256"=>lpad(string(j*10+i),64,'0'),
                "path"=>"synthetic_$j.$i","native_gate_passed"=>false) for i in 1:n]
            p=Dict("stage"=>label,"arm"=>name,"point"=>j,"direction"=>arm["directions"][j],"theta_over_pi"=>arm["fluxes"][j],
                "iteration_budget"=>n,"step_over_pi"=>arm["step_over_pi"],"updates_per_theta_over_pi"=>arm["updates_per_theta_over_pi"],
                "cumulative_updates_before"=>(j-1)*n,"origin"=>origin,"diagnostic_seed"=>previous,"history"=>h,"checkpoints"=>cps,
                "budget_complete"=>true,"control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"continuation_accepted"=>false)
            refs=Dict("accepted_parent"=>r["parent_sha256"],"previous_flux"=>previous["sha256"])
            pair=arm["paired_forward_points"][j]
            if pair>=0; p["paired_forward"]=forwards[pair]; refs["forward_same_flux"]=forwards[pair]["sha256"]; end
            RC.write_toml(path,p)
            open(joinpath(dir,label*"_history.tsv"),"w") do io
                println(io,"iteration\tnative_error\tenergy_density\tchi\twall_seconds\tcpu_seconds\tpayload_sha256")
                for (i,cp) in enumerate(cps)
                    println(io,join((i,1e-4,-.5,512,1.,2.,cp["sha256"]),'\t'))
                    RC.write_toml(joinpath(dir,label*"_iter$i.toml"),merge(cp,Dict("record"=>h[i],"diagnostic_seed"=>previous,
                        "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"continuation_accepted"=>false)))
                    output(path,cp,h[1:i],Dict("arm"=>name,"stage"=>label,"point"=>j,"direction"=>p["direction"],"iteration_budget"=>n,
                        "is_budget_endpoint"=>i==n,"cumulative_updates"=>(j-1)*n+i,"step_over_pi"=>p["step_over_pi"],
                        "updates_per_theta_over_pi"=>p["updates_per_theta_over_pi"]),refs,label*"_iter$i")
                end
            end
            previous=cps[end]; pair<0 && (forwards[j]=previous)
        end
        RC.write_toml(joinpath(dir,name*"_outcome.toml"),Dict("points"=>labels,"budget_complete"=>true,
            "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"continuation_accepted"=>false))
    end
end
@testset "Complete replay, same-flux pairing and tamper rejection" begin
    mktempdir() do dir
        fixture(dir)
        d=collect_results(dir)
        @test d.complete && length(d.samples)==100
        @test count(x->x["is_budget_endpoint"],d.samples)==48
        open(joinpath(dir,"summary.txt"),"w") do io
            redirect_stdout(io) do
                @test summary(dir).complete
            end
        end
        @test occursin("Same-flux return",read(joinpath(dir,"summary.txt"),String))
        path=joinpath(dir,"analysis_n2_grid1_point8_iter2.toml"); original=read(path,String)
        a=TOML.parsefile(path); a["reference_payload_sha256"]["forward_same_flux"]=repeat("b",64)
        open(io->TOML.print(io,a),path,"w")
        @test_throws ErrorException collect_results(dir)
        write(path,original)
        a=TOML.parsefile(path); a["point_manifest_sha256"]=repeat("b",64)
        open(io->TOML.print(io,a),path,"w")
        @test_throws ErrorException collect_results(dir)
        write(path,original)
        rm(joinpath(dir,"analysis_n2_grid1_origin.toml"))
        @test !collect_results(dir).complete
        open(joinpath(dir,"partial.txt"),"w") do io
            redirect_stdout(io) do
                @test !summary(dir).complete
            end
        end
    end
end
