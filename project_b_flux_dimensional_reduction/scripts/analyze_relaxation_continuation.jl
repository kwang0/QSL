include(joinpath(@__DIR__,"lib/RelaxationControl.jl"))
include(joinpath(@__DIR__,"lib/RelaxationAnalysis.jl"))
using TOML
const RC=RelaxationControl
const RA=RelaxationAnalysis
function main(args)
    length(args)==3 || error("usage: analyze_relaxation_continuation.jl CONTROL COMPACT ARM")
    control_path,compact,arm=args
    c=RC.validate(control_path); hash=RC.sha(control_path); r=c["recipe"]
    parent=RA.PB.read_state_file(joinpath(RC.ROOT,c["parent_path"]))
    parent_obs=RA.observables(parent.psi,0.15)
    outcome=TOML.parsefile(joinpath(compact,arm*"_outcome.toml"))
    outcome["control_sha256"]==hash || error("outcome control mismatch")
    function load(cp)
        RA.read_payload(cp["path"],cp["sha256"],parent.psi,hash,r["parent_sha256"];
            chi=r["chi"],tolerance=r["canonical_relation_tolerance"])
    end
    for label in outcome["points"]
        point=TOML.parsefile(joinpath(compact,label*".toml"))
        point["control_sha256"]==hash && point["parent_sha256"]==r["parent_sha256"] || error("point provenance mismatch")
        previous=load(point["diagnostic_seed"])
        prevobs=RA.observables(previous.psi,previous.theta)
        for iteration in point["selected_iterations"]
            stop_file=get(ENV,"PROJECT_B_PRETIMEOUT_REQUEST_FILE","")
            !isempty(stop_file) && isfile(stop_file) && return
            cp=only(filter(x->x["iteration"]==iteration,point["checkpoints"]))
            output=joinpath(compact,"analysis_"*label*"_iter$(iteration).toml")
            if isfile(output)
                old=TOML.parsefile(output)
                old["control_sha256"]==hash && old["payload_sha256"]==cp["sha256"] || error("existing analysis provenance mismatch")
                continue
            end
            state=load(cp); theta=point["theta_over_pi"]
            state.theta==theta || error("checkpoint theta mismatch")
            for (key,values) in state.history
                values==[row[key] for row in point["history"][1:iteration]] || error("checkpoint history mismatch")
            end
            obs=RA.observables(state.psi,theta)
            energy_difference=abs(obs.energy_density-state.history["energy_density"][end])
            energy_difference<=r["model_energy_tolerance"] || error("cross-library energy mismatch")
            comparisons=Dict("accepted_parent"=>RA.compare(parent.psi,state.psi,parent_obs,obs,0.15,theta,parent,r["continuity"]),
                "previous_flux"=>RA.compare(previous.psi,state.psi,prevobs,obs,previous.theta,theta,parent,r["continuity"]))
            if iteration>point["iteration_budget"]
                unheld_cp=point["checkpoints"][point["iteration_budget"]]; unheld=load(unheld_cp)
                comparisons["before_hold"]=RA.compare(unheld.psi,state.psi,RA.observables(unheld.psi,theta),obs,theta,theta,parent,r["continuity"])
            end
            result=Dict("artifact_kind"=>"project_b_relaxation_analysis","schema_version"=>1,
                "control_sha256"=>hash,"payload_sha256"=>cp["sha256"],"point_manifest_sha256"=>RC.sha(joinpath(compact,label*".toml")),
                "parent_sha256"=>r["parent_sha256"],"arm"=>arm,"stage"=>label,"iteration"=>iteration,
                "iteration_budget"=>point["iteration_budget"],"theta_over_pi"=>theta,"step_over_pi"=>point["step_over_pi"],
                "is_budget_endpoint"=>iteration==point["iteration_budget"],"is_hold_endpoint"=>point["hold_iterations"]>0 && iteration==point["iteration_budget"]+point["hold_iterations"],
                "native_error"=>state.history["native_error"][end],"native_gate_passed"=>cp["native_gate_passed"],
                "energy_density"=>obs.energy_density,"energy_terms"=>obs.energy_terms,
                "entropy"=>obs.entropy.von_neumann,"magnetization_z"=>obs.magnetization_z,
                "cross_library_energy_difference"=>energy_difference,"canonical_errors"=>state.canonical_errors,
                "comparisons"=>comparisons,"spectra"=>RA.spectra(state.psi,theta,r["spectrum"]),
                "continuation_accepted"=>false,"interpretation"=>"Unconverged continuation diagnostic; historical native gate is reported, not required for diagnostic advance.")
            RC.write_toml(output,result)
            println("Analyzed ",label," iteration ",iteration,"; native gate=",cp["native_gate_passed"],"; accepted parent unchanged"); flush(stdout)
        end
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && main(ARGS)
