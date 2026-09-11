module FullFluxAnalysis
include("Control.jl")
include("../roundtrip/Analysis.jl")
using TOML
const C=FullFluxControl
const A=RoundTripAnalysis.A

function analyze_arm(control_path,compact,arm)
    c=C.validate(control_path); hash=C.sha(control_path); r=c["recipe"]
    spec=only(filter(x->x["name"]==arm,C.arms(r)))
    parent=A.PB.read_state_file(joinpath(C.ROOT,c["parent_path"]))
    parent_obs=A.observables(parent.psi,r["start_theta_over_pi"])
    load(cp)=A.read_payload(cp["path"],cp["sha256"],parent.psi,hash,r["parent_sha256"];
        chi=r["chi"],tolerance=r["canonical_relation_tolerance"])
    origin_path=joinpath(compact,arm*"_origin.toml")
    isfile(origin_path) || error("no origin available for $arm")
    origin=TOML.parsefile(origin_path)
    origin["control_sha256"]==hash && origin["parent_sha256"]==r["parent_sha256"] || error("origin provenance")
    stopped()=isfile(get(ENV,"PROJECT_B_PRETIMEOUT_REQUEST_FILE",joinpath(compact,"pretimeout.request")))
    function measure(cp,history,path,label,metadata,references)
        output=joinpath(compact,"analysis_"*label*".toml")
        if isfile(output)
            old=TOML.parsefile(output)
            old["control_sha256"]==hash && old["payload_sha256"]==cp["sha256"] && old["point_manifest_sha256"]==C.sha(path) || error("existing analysis provenance")
            return
        end
        state=load(cp); theta=cp["theta_over_pi"]
        state.theta==theta || error("payload theta")
        for (key,values) in state.history
            values==[x[key] for x in history] || error("payload history")
        end
        obs=A.observables(state.psi,theta)
        difference=abs(obs.energy_density-history[end]["energy_density"])
        difference<=r["model_energy_tolerance"] || error("energy equivalence")
        comparisons=Dict{String,Any}(); refobs=Dict{String,Any}(); refhash=Dict{String,Any}()
        allrefs=merge(Dict("accepted_parent"=>(;psi=parent.psi,obs=parent_obs,theta=r["start_theta_over_pi"],sha=r["parent_sha256"])),references)
        for (key,ref) in allrefs
            comparisons[key]=A.compare(ref.psi,state.psi,ref.obs,obs,ref.theta,theta,parent,r["continuity"])
            refobs[key]=RoundTripAnalysis.observables(ref.obs); refhash[key]=ref.sha
        end
        result=merge(Dict("artifact_kind"=>"project_b_fullflux_analysis","schema_version"=>1,
            "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"payload_sha256"=>cp["sha256"],
            "point_manifest_sha256"=>C.sha(path),"arm"=>arm,"theta_over_pi"=>theta,
            "iteration"=>history[end]["iteration"],"native_error"=>history[end]["native_error"],
            "native_gate_applicable"=>length(history)>=max(r["minimum_iterations"],r["energy_window"]),
            "native_gate_passed"=>get(cp,"native_gate_passed",false),"cross_library_energy_difference"=>difference,
            "canonical_errors"=>state.canonical_errors,"comparisons"=>comparisons,
            "reference_observables"=>refobs,"reference_payload_sha256"=>refhash,
            "spectra"=>RoundTripAnalysis.spectra(state.psi,theta,r["spectrum"]),"continuation_accepted"=>false,
            "interpretation"=>"Finite-relaxation diagnostic; inverse xi is not a Fig. 2 energy gap."),RoundTripAnalysis.observables(obs),metadata)
        C.write_toml(output,result)
        println("Analyzed ",label,"; native applicable=",result["native_gate_applicable"],"; parent continuity=",
            comparisons["accepted_parent"]["multimetric_passed"]); flush(stdout)
    end
    ref(cp)=begin s=load(cp); (;psi=s.psi,obs=A.observables(s.psi,s.theta),theta=s.theta,sha=cp["sha256"]) end
    stopped() && return
    measure(origin["payload"],origin["history"],origin_path,arm*"_origin",
        Dict("stage"=>arm*"_origin","point"=>0,"iteration_budget"=>0,"is_budget_endpoint"=>false,"cumulative_updates"=>0),Dict())
    # Completed point manifests remain usable even when a later solve failed
    # before it could write the arm outcome. Missing points remain missing.
    for j in eachindex(spec["fluxes"])
        stopped() && return
        label=arm*"_point$j"; path=joinpath(compact,label*".toml")
        isfile(path) || break
        p=TOML.parsefile(path)
        p["control_sha256"]==hash && p["parent_sha256"]==r["parent_sha256"] || error("point provenance")
        references=Dict{String,Any}("previous_flux"=>ref(p["diagnostic_seed"]))
        for cp in C.selected_checkpoints(p)
            i=cp["iteration"]
            measure(cp,p["history"][1:i],path,label*"_iter$i",
                Dict("stage"=>label,"point"=>j,"iteration_budget"=>p["iteration_budget"],
                    "is_budget_endpoint"=>i==p["iteration_budget"],"cumulative_updates"=>p["cumulative_updates_before"]+i,
                    "delta_theta_over_pi"=>p["delta_theta_over_pi"]),references)
        end
        p["budget_complete"] || break
    end
end
end
