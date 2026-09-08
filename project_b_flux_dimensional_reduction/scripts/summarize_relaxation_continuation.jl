using TOML, Printf
include(joinpath(@__DIR__,"lib/RelaxationControl.jl"))
const RC=RelaxationControl
function collect_results(directory)
    control=joinpath(directory,"control.snapshot.toml"); c=TOML.parsefile(control); hash=RC.sha(control)
    c["artifact_kind"]=="project_b_relaxation_continuation_control" && c["schema_version"]==1 || error("run control schema mismatch")
    strip(read(joinpath(directory,"control.sha256"),String))==hash || error("run control hash mismatch")
    RC.validate_recipe(c["recipe"])
    results=Dict{String,Any}[]; missing=String[]; incomplete=String[]
    for arm in RC.arms(c["recipe"])
        name=arm["name"]; outcome_path=joinpath(directory,name*"_outcome.toml")
        if !isfile(outcome_path); push!(missing,name*" outcome"); continue; end
        outcome=TOML.parsefile(outcome_path)
        outcome["control_sha256"]==hash && !outcome["continuation_accepted"] || error("outcome provenance mismatch")
        !outcome["budget_complete"] && push!(incomplete,name)
        for label in outcome["points"]
            path=joinpath(directory,label*".toml"); point=TOML.parsefile(path)
            point["control_sha256"]==hash || error("point provenance mismatch")
            for i in point["selected_iterations"]
                analysis=joinpath(directory,"analysis_"*label*"_iter$(i).toml")
                if !isfile(analysis); push!(missing,label*" iteration $i analysis"); continue; end
                a=TOML.parsefile(analysis)
                a["control_sha256"]==hash && a["point_manifest_sha256"]==RC.sha(path) || error("analysis provenance mismatch")
                a["payload_sha256"]==point["checkpoints"][i]["sha256"] && !a["continuation_accepted"] || error("checkpoint provenance mismatch")
                push!(results,a)
            end
        end
    end
    (;c,hash,results,missing,incomplete)
end
function spectrum_distance(a,b)
    x=complex.(a["lambda_real"],a["lambda_imag"]); y=complex.(b["lambda_real"],b["lambda_imag"])
    max(maximum(minimum(abs(z-w) for w in y) for z in x),maximum(minimum(abs(w-z) for z in x) for w in y))
end
function summary(directory)
    data=collect_results(directory)
    println("Diagnostic continuation; no accepted lineage changes.")
    println("Control: ",data.hash)
    println("Analyzed samples: ",length(data.results),"; missing outputs: ",length(data.missing),"; incomplete arms: ",join(data.incomplete,", "))
    println("arm\ttheta/pi\titeration\tsample\tGalerkin\tnative_gate\tparent_continuity\tparent_overlap\tmax_entropy_jump\tmin_inverse_xi_Sz1\tall_Sz1_modes_converged")
    for a in data.results
        d=a["comparisons"]["accepted_parent"]; s=a["spectra"]["sz1"]
        kind=a["is_budget_endpoint"] ? "budget" : a["is_hold_endpoint"] ? "hold" : "selected"
        println(join((a["arm"],a["theta_over_pi"],a["iteration"],kind,a["native_error"],a["native_gate_passed"],
            d["multimetric_passed"]&&d["overlap_floor_passed"],d["overlap_per_site"],d["maximum_cut_entropy_jump"],
            minimum(s["inverse_xi"]),s["requested_modes_converged"]),'\t'))
    end
    println("\nMatched fixed-budget endpoints (absolute differences; no acceptance threshold inferred):")
    println("first_arm\tsecond_arm\ttheta/pi\tabs_energy_difference\tmax_cut_entropy_difference\tSz1_complex_spectrum_distance\tall_requested_modes_converged")
    endpoints=filter(a->a["is_budget_endpoint"] && a["arm"]!="baseline",data.results)
    for i in eachindex(endpoints),j in i+1:length(endpoints)
        a,b=endpoints[i],endpoints[j]
        a["theta_over_pi"]==b["theta_over_pi"] || continue
        # Compare step refinement at fixed N, or adjacent doubling at fixed step.
        (a["iteration_budget"]==b["iteration_budget"] ||
            (a["step_over_pi"]==b["step_over_pi"] && b["iteration_budget"]==2a["iteration_budget"])) || continue
        x,y=a["spectra"]["sz1"],b["spectra"]["sz1"]
        println(join((a["arm"],b["arm"],a["theta_over_pi"],abs(a["energy_density"]-b["energy_density"]),
            maximum(abs.(a["entropy"]-b["entropy"])),spectrum_distance(x,y),
            x["requested_modes_converged"]&&y["requested_modes_converged"]),'\t'))
    end
    for item in data.missing; println("MISSING: ",item); end
    println("Inverse correlation lengths use complete period-2 transfer cells; they are not Fig. 2 energy gaps.")
    println("A residual turnaround alone is not convergence or proof of branch loss.")
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("usage: summarize_relaxation_continuation.jl RUN_DIRECTORY")
    summary(ARGS[1])
end
