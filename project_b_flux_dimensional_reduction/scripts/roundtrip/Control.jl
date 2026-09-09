module RoundTripControl
using TOML
include("../lib/RelaxationControl.jl")
const R=RelaxationControl
const ROOT=R.ROOT
const sha=R.sha
const write_toml=R.write_toml

function arms(r)
    result=Dict{String,Any}[]
    for coarse_n in r["coarse_iteration_budgets"], (grid,step) in enumerate(r["steps_over_pi"])
        count=round(Int,(r["turn_theta_over_pi"]-r["start_theta_over_pi"])/step)
        isapprox(r["start_theta_over_pi"]+count*step,r["turn_theta_over_pi"];atol=1e-12) || error("nonintegral grid")
        forward=[round(r["start_theta_over_pi"]+i*step;digits=10) for i in 1:count]
        back=[round(r["turn_theta_over_pi"]-i*step;digits=10) for i in 1:count]
        n=coarse_n÷grid
        push!(result,Dict("name"=>"n$(n)_grid$(grid)","iterations"=>n,"step_over_pi"=>step,
            "updates_per_theta_over_pi"=>n/step,"fluxes"=>vcat(forward,back),
            "directions"=>vcat(fill("forward",count),fill("return",count)),
            # Zero denotes the imported origin. The turning point is updated once.
            "paired_forward_points"=>vcat(fill(-1,count),collect(count-1:-1:0))))
    end
    result
end

function validate_recipe(r)
    base=TOML.parsefile(joinpath(ROOT,"configs/relaxation_continuation.toml"))
    r["artifact_kind"]=="project_b_roundtrip_recipe" && r["schema_version"]==1 || error("recipe schema")
    for key in ("parent_sha256","bridge_path","algorithm","chi","random_seed","minimum_iterations","energy_window",
                "energy_span_tolerance","vumps_galerkin_tolerance","canonical_relation_tolerance","model_energy_tolerance","continuity")
        r[key]==base[key] || error("unmatched scientific setting: $key")
    end
    r["start_theta_over_pi"]==0.15 && r["turn_theta_over_pi"]==0.25 || error("unbudgeted flux range")
    r["steps_over_pi"]==[0.025,0.0125] && r["coarse_iteration_budgets"]==[2,4] || error("unbudgeted update density")
    !r["automatic_promotion"] && r["diagnostic_advance_without_native_convergence"] || error("diagnostic policy changed")
    r["checkpoint_every"]==1 && r["analyze_every_iteration"] && r["endpoint_holds"]==0 || error("sampling policy changed")
    for key in keys(base["spectrum"])
        r["spectrum"][key]==base["spectrum"][key] || error("spectrum policy changed: $key")
    end
    r["spectrum"]["momentum_mapping"]=="YC8-1 charge-aware: 2k1=wrap(k+2*Sz*theta/8), k2=wrap(4*k)" || error("momentum convention changed")
    sum(length(a["fluxes"])*a["iterations"] for a in arms(r))==96 || error("iteration budget")
    resources=r["resources"]
    for key in ("qos","allocation_cpus","step_cpus","julia_threads","blas_threads","memory","pretimeout_seconds")
        resources[key]==base["resources"][key] || error("unbenchmarked resource: $key")
    end
    resources["time_limit"]=="14:00:00" && resources["solver_seconds"]==43200 || error("deadline changed")
    f=R.P.ProjectBAccounting.reservation(resources["allocation_cpus"],resources["memory"],resources["time_limit"];qos=resources["qos"])
    f.allocated_cpus==10 && f.node_hours==resources["forecast_node_hours"]==0.546875 || error("reservation changed")
    resources["maximum_node_hours"]==0.55 && f.node_hours<=resources["maximum_node_hours"] || error("cap exceeded")
    r
end

function required_sources(root=ROOT)
    # Keep completed controls reproducible: new modules live outside their
    # top-level directory enumeration. Include all inherited runtime inputs.
    extra=["configs/roundtrip_continuation.toml","scripts/audit_project_context.jl",
        "scripts/prepare_roundtrip_continuation.jl","scripts/validate_roundtrip_continuation.jl",
        "scripts/analyze_roundtrip_continuation.jl","scripts/summarize_roundtrip_continuation.jl",
        "idmrg/scripts/run_roundtrip_continuation.jl","idmrg/roundtrip/Continuation.jl",
        "scripts/roundtrip/Control.jl","scripts/roundtrip/Analysis.jl","scripts/roundtrip/Momentum.jl",
        "slurm/run_roundtrip_continuation_cpu.sh","slurm/run_roundtrip_continuation_job.sh",
        "test/roundtrip_control.jl","test/roundtrip_analysis.jl","test/roundtrip_summary.jl",
        "idmrg/test/roundtrip_continuation.jl","test/roundtrip_pipeline_fixture.jl",
        "test/test_roundtrip_launcher.sh","test/test_roundtrip_git_delivery.sh"]
    sort(unique(vcat(R.required_sources(root),extra)))
end

function validate(path;root=ROOT,code_only=false)
    c=TOML.parsefile(path)
    c["artifact_kind"]=="project_b_roundtrip_control" && c["schema_version"]==1 || error("control schema")
    r=validate_recipe(c["recipe"])
    r==TOML.parsefile(joinpath(root,"configs/roundtrip_continuation.toml")) || error("recipe differs; seal new control")
    expected=sort(unique(vcat(required_sources(root),[r["bridge_path"],c["parent_path"]])))
    sort([x["path"] for x in c["inputs"]])==expected || error("incomplete or duplicate input pins")
    only(filter(x->x["path"]==c["parent_path"],c["inputs"]))["sha256"]==R.PARENT_SHA || error("parent mismatch")
    for item in c["inputs"]
        code_only && startswith(item["path"],"output/") && continue
        p=R.root_path(root,item["path"])
        isfile(p) && sha(p)==item["sha256"] || error("roundtrip input hash mismatch: $p")
    end
    c
end
end
