using TOML
include("roundtrip/Control.jl")
const RC=RoundTripControl

function native_gate(h,r)
    w=r["energy_window"]
    length(h)>=max(w,r["minimum_iterations"]) || return false
    tail=h[end-w+1:end]
    all(x->x["chi"]==r["chi"] && isfinite(x["native_error"]) && isfinite(x["energy_density"]),tail) &&
        tail[end]["native_error"]<=r["vumps_galerkin_tolerance"] &&
        maximum(x["energy_density"] for x in tail)-minimum(x["energy_density"] for x in tail)<=r["energy_span_tolerance"]
end
function collect_results(directory)
    control=joinpath(directory,"control.snapshot.toml"); c=TOML.parsefile(control); hash=RC.sha(control)
    c["artifact_kind"]=="project_b_roundtrip_control" && c["schema_version"]==1 || error("control schema")
    strip(read(joinpath(directory,"control.sha256"),String))==hash || error("control reference mismatch")
    r=RC.validate_recipe(c["recipe"])
    samples=Dict{String,Any}[]; missing=String[]; incomplete=String[]
    function analysis(path,manifest,cp,history,expected,refs)
        if !isfile(path); push!(missing,basename(path)); return; end
        a=TOML.parsefile(path)
        a["artifact_kind"]=="project_b_roundtrip_analysis" && a["schema_version"]==1 || error("analysis schema")
        a["control_sha256"]==hash && a["parent_sha256"]==r["parent_sha256"] && !a["continuation_accepted"] || error("analysis lineage")
        a["point_manifest_sha256"]==RC.sha(manifest) && a["payload_sha256"]==cp["sha256"] || error("analysis hash chain")
        all(a[k]==v for (k,v) in expected) || error("analysis metadata")
        a["iteration"]==history[end]["iteration"] && a["theta_over_pi"]==cp["theta_over_pi"] || error("analysis iteration/theta")
        a["native_error"]==history[end]["native_error"] && a["native_gate_passed"]==get(cp,"native_gate_passed",false) || error("analysis native error")
        a["native_gate_applicable"]==(length(history)>=max(r["minimum_iterations"],r["energy_window"])) || error("gate applicability")
        a["reference_payload_sha256"]==refs || error("analysis comparison reference hash")
        difference=abs(a["energy_density"]-history[end]["energy_density"])
        difference<=r["model_energy_tolerance"] && isapprox(difference,a["cross_library_energy_difference"];atol=1e-14) || error("analysis energy equality")
        for key in keys(refs)
            d=a["comparisons"][key]; ref=a["reference_observables"][key]
            isapprox(maximum(abs.(a["entropy"]-ref["entropy"])),d["maximum_cut_entropy_jump"];atol=1e-12) || error("entropy comparison")
            isapprox(sqrt(sum(abs2,a["energy_terms"]-ref["energy_terms"])/2),d["energy_term_rms_jump"];atol=1e-12) || error("energy comparison")
            isapprox(sqrt(sum(abs2,a["magnetization_z"]-ref["magnetization_z"])/2),d["magnetization_rms_jump"];atol=1e-12) || error("magnetization comparison")
        end
        push!(samples,a)
    end
    for arm in RC.arms(r)
        name=arm["name"]; origin_path=joinpath(directory,name*"_origin.toml"); outcome_path=joinpath(directory,name*"_outcome.toml")
        if !isfile(origin_path) || !isfile(outcome_path); push!(missing,name*" origin/outcome"); continue; end
        origin=TOML.parsefile(origin_path); outcome=TOML.parsefile(outcome_path)
        for x in (origin,outcome)
            x["control_sha256"]==hash && x["parent_sha256"]==r["parent_sha256"] && !x["continuation_accepted"] || error("origin/outcome lineage")
        end
        cp=origin["payload"]; previous=cp; forward=Dict{Int,Any}(0=>cp)
        cp["theta_over_pi"]==r["start_theta_over_pi"] && cp["iteration"]==0 || error("origin coordinate")
        analysis(joinpath(directory,"analysis_"*name*"_origin.toml"),origin_path,cp,origin["history"],
            Dict("arm"=>name,"stage"=>name*"_origin","point"=>0,"direction"=>"origin","iteration_budget"=>0,
                "is_budget_endpoint"=>false,"cumulative_updates"=>0),Dict("accepted_parent"=>r["parent_sha256"]))
        labels=outcome["points"]; expected=[name*"_point$j" for j in eachindex(arm["fluxes"])]
        length(labels)<=length(expected) && labels==expected[1:length(labels)] || error("point sequence")
        full=length(labels)==length(expected)
        for (j,label) in enumerate(labels)
            path=joinpath(directory,label*".toml")
            if !isfile(path); push!(missing,label); full=false; break; end
            p=TOML.parsefile(path); n=arm["iterations"]
            p["control_sha256"]==hash && p["parent_sha256"]==r["parent_sha256"] && !p["continuation_accepted"] || error("point lineage")
            for (k,v) in Dict("stage"=>label,"arm"=>name,"point"=>j,"direction"=>arm["directions"][j],
                             "theta_over_pi"=>arm["fluxes"][j],"iteration_budget"=>n,"step_over_pi"=>arm["step_over_pi"],
                             "updates_per_theta_over_pi"=>arm["updates_per_theta_over_pi"],"cumulative_updates_before"=>(j-1)*n)
                p[k]==v || error("point metadata: $k")
            end
            p["origin"]==origin["payload"] && p["diagnostic_seed"]==previous || error("diagnostic seed chain")
            refs=Dict("accepted_parent"=>r["parent_sha256"],"previous_flux"=>previous["sha256"])
            pair=arm["paired_forward_points"][j]
            if pair>=0
                p["paired_forward"]==forward[pair] || error("return reference chain")
                refs["forward_same_flux"]=forward[pair]["sha256"]
            else
                !haskey(p,"paired_forward") || error("unexpected return reference")
            end
            h=p["history"]; cps=p["checkpoints"]
            length(h)==length(cps)<=n && p["budget_complete"]==(length(h)==n) || error("point completion")
            journal=readlines(joinpath(directory,label*"_history.tsv"))
            length(journal)==length(h)+1 || error("journal length")
            for (i,cp) in enumerate(cps)
                row=h[i]
                row["iteration"]==cp["iteration"]==i && row["chi"]==r["chi"] && cp["theta_over_pi"]==p["theta_over_pi"] || error("checkpoint coordinate")
                all(isfinite,values(row)) && cp["native_gate_passed"]==native_gate(h[1:i],r) || error("checkpoint native gate")
                fields=split(journal[i+1],'\t')
                length(fields)==7 && fields[end]==cp["sha256"] || error("journal hash")
                all(parse(Float64,fields[k])==row[key] for (k,key) in enumerate(("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds"))) || error("journal values")
                compact=TOML.parsefile(joinpath(directory,label*"_iter$i.toml"))
                all(compact[k]==v for (k,v) in cp) && compact["record"]==row && compact["diagnostic_seed"]==previous || error("checkpoint record")
                compact["control_sha256"]==hash && compact["parent_sha256"]==r["parent_sha256"] && !compact["continuation_accepted"] || error("checkpoint lineage")
                analysis(joinpath(directory,"analysis_"*label*"_iter$i.toml"),path,cp,h[1:i],
                    Dict("arm"=>name,"stage"=>label,"point"=>j,"direction"=>p["direction"],"iteration_budget"=>n,
                        "is_budget_endpoint"=>i==n,"cumulative_updates"=>(j-1)*n+i,"step_over_pi"=>p["step_over_pi"],
                        "updates_per_theta_over_pi"=>p["updates_per_theta_over_pi"]),refs)
            end
            if !p["budget_complete"]
                full=false; j==length(labels) || error("incomplete point seeded successor")
            else
                previous=cps[end]; pair<0 && (forward[j]=previous)
            end
        end
        outcome["budget_complete"]==full || error("arm completion mismatch")
        !full && push!(incomplete,name)
    end
    (;c,hash,samples,missing,incomplete,complete=isempty(missing)&&isempty(incomplete))
end
passed(d)=d["multimetric_passed"]&&d["overlap_floor_passed"]
function spectrum_distance(x,y)
    a=complex.(x["lambda_real"],x["lambda_imag"]); b=complex.(y["lambda_real"],y["lambda_imag"])
    max(maximum(minimum(abs(z-w) for w in b) for z in a),maximum(minimum(abs(z-w) for w in a) for z in b))
end
function summary(directory)
    data=collect_results(directory)
    println("EXPERIMENT_COMPLETE=",data.complete)
    println("Diagnostic forward-and-return loop; accepted parent unchanged. Control: ",data.hash)
    println("Analyzed states: ",length(data.samples),"/100; missing: ",join(data.missing,", "),"; incomplete arms: ",join(data.incomplete,", "))
    endpoints=filter(a->a["is_budget_endpoint"],data.samples)
    println("arm\tdirection\ttheta/pi\tcumulative_updates\tGalerkin\tnative_gate_applicable\tnative_gate\tparent_continuity\tparent_overlap\tmax_entropy_jump\tmax_abs_Sz\te1-e2\tmin_inverse_xi_Sz1\tall_transfer_modes_converged")
    for a in endpoints
        d=a["comparisons"]["accepted_parent"]
        println(join((a["arm"],a["direction"],a["theta_over_pi"],a["cumulative_updates"],a["native_error"],a["native_gate_applicable"],a["native_gate_passed"],
            passed(d),d["overlap_per_site"],d["maximum_cut_entropy_jump"],maximum(abs.(a["magnetization_z"])),a["energy_terms"][1]-a["energy_terms"][2],
            minimum(a["spectra"]["sz1"]["inverse_xi"]),all(s["requested_modes_converged"] for s in values(a["spectra"]))),'\t'))
    end
    println("\nSame-flux return versus forward (0.15 compares to the imported origin):")
    println("arm\ttheta/pi\toverlap\tabs_energy_difference\tmax_entropy_difference\tmagnetization_rms_difference\tSz1_complex_spectrum_distance\tcontinuity\tmodes_converged")
    for a in filter(a->a["direction"]=="return",endpoints)
        d=a["comparisons"]["forward_same_flux"]
        candidates=filter(x->x["arm"]==a["arm"] && x["payload_sha256"]==a["reference_payload_sha256"]["forward_same_flux"],data.samples)
        if isempty(candidates)
            println("MISSING paired forward analysis: ",a["stage"]); continue
        end
        ref=only(candidates)
        println(join((a["arm"],a["theta_over_pi"],d["overlap_per_site"],abs(a["energy_density"]-ref["energy_density"]),d["maximum_cut_entropy_jump"],
            d["magnetization_rms_jump"],spectrum_distance(a["spectra"]["sz1"],ref["spectra"]["sz1"]),passed(d),
            all(s["requested_modes_converged"] for x in (a,ref) for s in values(x["spectra"]))),'\t'))
    end
    println("\nEqual update-density pairs and same-grid density doubling:")
    println("first_arm\tsecond_arm\tdirection\ttheta/pi\tequal_density\tabs_energy_difference\tmax_entropy_difference\tSz1_complex_spectrum_distance\tmodes_converged")
    for i in eachindex(endpoints),j in i+1:length(endpoints)
        a,b=endpoints[i],endpoints[j]
        a["theta_over_pi"]==b["theta_over_pi"] && a["direction"]==b["direction"] || continue
        equal=a["updates_per_theta_over_pi"]==b["updates_per_theta_over_pi"]
        equal || a["step_over_pi"]==b["step_over_pi"] || continue
        println(join((a["arm"],b["arm"],a["direction"],a["theta_over_pi"],equal,abs(a["energy_density"]-b["energy_density"]),maximum(abs.(a["entropy"]-b["entropy"])),
            spectrum_distance(a["spectra"]["sz1"],b["spectra"]["sz1"]),all(s["requested_modes_converged"] for x in (a,b) for s in values(x["spectra"]))),'\t'))
    end
    println("Native gate requires four records at unchanged flux; it is inapplicable to shorter histories. No relaxed production threshold is adopted.")
    println("Spectral distance is a nearest-complex-eigenvalue set distance, not mode tracking or an acceptance threshold. Inverse xi uses period-2 transfer cells, not energy-gap units.")
    data
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("usage: summarize_roundtrip_continuation.jl RUN_DIRECTORY")
    summary(only(ARGS))
end
