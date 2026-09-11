using TOML
include("fullflux/Control.jl")
const FC=FullFluxControl
module PreviousSummary
include("summarize_roundtrip_continuation.jl")
end
const native_gate=PreviousSummary.native_gate

function collect_results(directory)
    control=joinpath(directory,"control.snapshot.toml"); c=TOML.parsefile(control); hash=FC.sha(control)
    c["artifact_kind"]=="project_b_fullflux_control" && c["schema_version"]==1 || error("control schema")
    strip(read(joinpath(directory,"control.sha256"),String))==hash || error("control reference mismatch")
    r=FC.validate_recipe(c["recipe"])
    samples=Dict{String,Any}[]; missing=String[]; incomplete=String[]; failures=String[]
    steps=joinpath(directory,"step_exit_codes.tsv")
    if isfile(steps)
        for line in readlines(steps)[2:end]
            fields=split(line,'\t')
            length(fields)==2 || error("step exit record")
            parse(Int,fields[2])==0 || push!(failures,"$(fields[1]) exited $(fields[2])")
        end
    end
    function lineage(x)
        x["control_sha256"]==hash && x["parent_sha256"]==r["parent_sha256"] && !x["continuation_accepted"] || error("lineage mismatch")
    end
    function analysis(path,manifest,cp,history,expected,refs)
        if !isfile(path); push!(missing,basename(path)); return; end
        a=TOML.parsefile(path); lineage(a)
        a["artifact_kind"]=="project_b_fullflux_analysis" && a["schema_version"]==1 || error("analysis schema")
        a["point_manifest_sha256"]==FC.sha(manifest) && a["payload_sha256"]==cp["sha256"] || error("analysis hash chain")
        all(a[k]==v for (k,v) in expected) || error("analysis metadata")
        a["iteration"]==history[end]["iteration"] && a["theta_over_pi"]==cp["theta_over_pi"] || error("analysis iteration/theta")
        a["native_error"]==history[end]["native_error"] && a["native_gate_passed"]==get(cp,"native_gate_passed",false) || error("native error mismatch")
        a["native_gate_applicable"]==(length(history)>=max(r["minimum_iterations"],r["energy_window"])) || error("gate applicability")
        a["reference_payload_sha256"]==refs || error("comparison reference hash")
        difference=abs(a["energy_density"]-history[end]["energy_density"])
        difference<=r["model_energy_tolerance"] && isapprox(difference,a["cross_library_energy_difference"];atol=1e-14) || error("energy equality")
        for key in keys(refs)
            d=a["comparisons"][key]; ref=a["reference_observables"][key]
            isapprox(maximum(abs.(a["entropy"]-ref["entropy"])),d["maximum_cut_entropy_jump"];atol=1e-12) || error("entropy comparison")
            isapprox(sqrt(sum(abs2,a["energy_terms"]-ref["energy_terms"])/2),d["energy_term_rms_jump"];atol=1e-12) || error("energy comparison")
            isapprox(sqrt(sum(abs2,a["magnetization_z"]-ref["magnetization_z"])/2),d["magnetization_rms_jump"];atol=1e-12) || error("magnetization comparison")
        end
        push!(samples,a)
    end
    for arm in FC.arms(r)
        name=arm["name"]; n=arm["iterations"]
        failure=joinpath(directory,name*"_failure.toml")
        if isfile(failure)
            f=TOML.parsefile(failure)
            f["control_sha256"]==hash && f["arm"]==name || error("failure provenance")
            push!(failures,name*": "*f["error"])
        end
        origin_path=joinpath(directory,name*"_origin.toml"); outcome_path=joinpath(directory,name*"_outcome.toml")
        if !isfile(origin_path); push!(missing,name*" origin"); push!(incomplete,name); continue; end
        origin=TOML.parsefile(origin_path); lineage(origin)
        cp=origin["payload"]; previous=cp
        cp["theta_over_pi"]==r["start_theta_over_pi"] && cp["iteration"]==0 || error("origin coordinate")
        analysis(joinpath(directory,"analysis_"*name*"_origin.toml"),origin_path,cp,origin["history"],
            Dict("arm"=>name,"stage"=>name*"_origin","point"=>0,"iteration_budget"=>0,
                "is_budget_endpoint"=>false,"cumulative_updates"=>0),Dict("accepted_parent"=>r["parent_sha256"]))
        labels=String[]; full=true
        for (j,theta) in enumerate(arm["fluxes"])
            label=name*"_point$j"; path=joinpath(directory,label*".toml")
            if !isfile(path); full=false; push!(missing,label); break; end
            push!(labels,label); p=TOML.parsefile(path); lineage(p)
            for (k,v) in Dict("stage"=>label,"arm"=>name,"point"=>j,"theta_over_pi"=>theta,
                             "iteration_budget"=>n,"delta_theta_over_pi"=>FC.actual_step(r,j),"cumulative_updates_before"=>(j-1)*n)
                p[k]==v || error("point metadata: $k")
            end
            p["origin"]==origin["payload"] && p["diagnostic_seed"]==previous || error("seed chain")
            h=p["history"]; cps=p["checkpoints"]
            length(h)==length(cps)<=n && p["budget_complete"]==(length(h)==n) || error("point completion")
            journal=readlines(joinpath(directory,label*"_history.tsv"))
            length(journal)==length(h)+1 || error("journal length")
            for (i,cp) in enumerate(cps)
                row=h[i]
                row["iteration"]==cp["iteration"]==i && row["chi"]==r["chi"] && cp["theta_over_pi"]==theta || error("checkpoint coordinate")
                all(isfinite,values(row)) && cp["native_gate_passed"]==native_gate(h[1:i],r) || error("checkpoint native gate")
                fields=split(journal[i+1],'\t')
                length(fields)==7 && fields[end]==cp["sha256"] || error("journal hash")
                all(parse(Float64,fields[k])==row[key] for (k,key) in enumerate(("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds"))) || error("journal values")
                compact=TOML.parsefile(joinpath(directory,label*"_iter$i.toml")); lineage(compact)
                all(compact[k]==v for (k,v) in cp) && compact["record"]==row && compact["diagnostic_seed"]==previous || error("checkpoint record")
            end
            for cp in FC.selected_checkpoints(p)
                i=cp["iteration"]
                analysis(joinpath(directory,"analysis_"*label*"_iter$i.toml"),path,cp,h[1:i],
                    Dict("arm"=>name,"stage"=>label,"point"=>j,"iteration_budget"=>n,"is_budget_endpoint"=>i==n,
                         "cumulative_updates"=>(j-1)*n+i,"delta_theta_over_pi"=>p["delta_theta_over_pi"]),
                    Dict("accepted_parent"=>r["parent_sha256"],"previous_flux"=>previous["sha256"]))
            end
            if !p["budget_complete"]
                full=false
                any(isfile(joinpath(directory,name*"_point$k.toml")) for k in j+1:length(arm["fluxes"])) && error("incomplete point seeded successor")
                break
            end
            previous=cps[end]
        end
        if isfile(outcome_path)
            outcome=TOML.parsefile(outcome_path); lineage(outcome)
            outcome["points"]==labels && outcome["budget_complete"]==full || error("arm outcome mismatch")
        else
            push!(missing,name*" outcome"); full=false
        end
        !full && push!(incomplete,name)
    end
    (;c,hash,samples,missing,incomplete,failures,complete=isempty(missing)&&isempty(incomplete)&&isempty(failures))
end

function summary(directory)
    d=collect_results(directory); r=d.c["recipe"]
    println("EXPERIMENT_COMPLETE=",d.complete)
    println("Three diagnostic forward scans; accepted parent unchanged. Control: ",d.hash)
    println("Analyzed states: ",length(d.samples),"/",FC.expected_analyses(r),"; missing: ",join(d.missing,", "),"; incomplete: ",join(d.incomplete,", "))
    !isempty(d.failures) && println("Run failures: ",join(d.failures,"; "))
    println("arm\ttheta/pi\tupdates\tGalerkin\tnative_applicable\tnative_pass\tparent_continuity\tprevious_continuity\tenergy\tmean_entropy\tmax_abs_Sz\te1-e2\tmin_inverse_xi_Sz1\ttransfer_modes_converged")
    passed(c)=c["multimetric_passed"]&&c["overlap_floor_passed"]
    for a in d.samples
        comparisons=a["comparisons"]
        println(join((a["arm"],a["theta_over_pi"],a["cumulative_updates"],a["native_error"],a["native_gate_applicable"],a["native_gate_passed"],
            passed(comparisons["accepted_parent"]),haskey(comparisons,"previous_flux") ? passed(comparisons["previous_flux"]) : "origin",
            a["energy_density"],sum(a["entropy"])/length(a["entropy"]),maximum(abs.(a["magnetization_z"])),a["energy_terms"][1]-a["energy_terms"][2],
            minimum(a["spectra"]["sz1"]["inverse_xi"]),all(s["requested_modes_converged"] for s in values(a["spectra"]))),'\t'))
    end
    println("\nSz=1 spectra for qualitative Fig. 3 inspection (recorded eigenvalue order; not tracked branches):")
    println("arm\ttheta/pi\tmode\tinverse_xi_per_period2_cell\t2k1/pi\tk2/pi\ttransfer_modes_converged")
    for a in d.samples
        s=a["spectra"]["sz1"]
        for i in eachindex(s["inverse_xi"])
            println(join((a["arm"],a["theta_over_pi"],i,s["inverse_xi"][i],s["two_k1"][i]/pi,mod(s["k2"][i],2pi)/pi,s["requested_modes_converged"]),'\t'))
        end
    end
    println("Continuity and native failures are diagnostics; they do not stop this finite schedule or promote states. Inverse xi is not a Fig. 2 energy gap.")
    d
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("usage: summarize_fullflux_continuation.jl RUN_DIRECTORY")
    summary(only(ARGS))
end
