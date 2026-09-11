module FullFluxControl
using TOML
include("../roundtrip/Control.jl")
const RT=RoundTripControl
const ROOT=RT.ROOT
const sha=RT.sha
const write_toml=RT.write_toml

arms(r)=[Dict("name"=>"n$n","iterations"=>n,"fluxes"=>r["fluxes_over_pi"]) for n in r["iteration_budgets"]]
expected_analyses(r)=length(arms(r))*(1+length(r["fluxes_over_pi"]))
selected_checkpoints(p)=isempty(p["checkpoints"]) ? [] : [last(p["checkpoints"])]
actual_step(r,j)=r["fluxes_over_pi"][j]-(j==1 ? r["start_theta_over_pi"] : r["fluxes_over_pi"][j-1])

function validate_recipe(r;root=ROOT)
    base=TOML.parsefile(joinpath(root,"configs/roundtrip_continuation.toml"))
    r["artifact_kind"]=="project_b_fullflux_recipe" && r["schema_version"]==1 || error("recipe schema")
    for key in ("parent_sha256","bridge_path","algorithm","chi","random_seed","minimum_iterations","energy_window",
                "energy_span_tolerance","vumps_galerkin_tolerance","canonical_relation_tolerance","model_energy_tolerance","continuity","spectrum")
        r[key]==base[key] || error("unmatched scientific setting: $key")
    end
    r["start_theta_over_pi"]==0.15 && r["fluxes_over_pi"]==collect(2:10)./10 || error("unbudgeted flux grid")
    r["step_over_pi"]==0.1 && r["iteration_budgets"]==[2,4,8] || error("unbudgeted update schedule")
    !r["automatic_promotion"] && r["diagnostic_advance_without_native_convergence"] &&
        r["diagnostic_advance_without_continuity_pass"] || error("diagnostic policy changed")
    r["checkpoint_every"]==1 && !r["analyze_every_iteration"] && r["analyze_origin"] &&
        r["endpoint_holds"]==0 && !r["return_leg"] || error("sampling policy changed")
    sum(length(a["fluxes"])*a["iterations"] for a in arms(r))==126 || error("update budget")
    resources=r["resources"]
    for key in ("qos","allocation_cpus","step_cpus","julia_threads","blas_threads","memory","pretimeout_seconds")
        resources[key]==base["resources"][key] || error("unbenchmarked resource: $key")
    end
    resources["time_limit"]=="48:00:00" && resources["solver_seconds"]==172800 || error("deadline changed")
    f=RT.R.P.ProjectBAccounting.reservation(resources["allocation_cpus"],resources["memory"],resources["time_limit"];qos=resources["qos"])
    f.allocated_cpus==10 && f.node_hours==resources["forecast_node_hours"]==1.875 || error("reservation changed")
    resources["maximum_node_hours"]==1.875 && f.node_hours<=resources["maximum_node_hours"] || error("cap exceeded")
    r
end

function required_sources(root=ROOT)
    extra=["configs/fullflux_continuation.toml","scripts/fullflux/Control.jl","scripts/fullflux/Analysis.jl",
        "scripts/fullflux/preflight.jl","scripts/prepare_fullflux_continuation.jl","scripts/validate_fullflux_continuation.jl",
        "scripts/analyze_fullflux_continuation.jl","scripts/summarize_fullflux_continuation.jl",
        "idmrg/fullflux/Continuation.jl","idmrg/scripts/run_fullflux_continuation.jl",
        "slurm/run_fullflux_continuation_cpu.sh","slurm/run_fullflux_continuation_job.sh"]
    sort(unique(vcat(RT.required_sources(root),extra)))
end

function validate(path;root=ROOT,code_only=false)
    c=TOML.parsefile(path)
    c["artifact_kind"]=="project_b_fullflux_control" && c["schema_version"]==1 || error("control schema")
    r=validate_recipe(c["recipe"];root)
    r==TOML.parsefile(joinpath(root,"configs/fullflux_continuation.toml")) || error("recipe differs; seal new control")
    expected=sort(unique(vcat(required_sources(root),[r["bridge_path"],c["parent_path"]])))
    sort([x["path"] for x in c["inputs"]])==expected || error("incomplete or duplicate input pins")
    only(filter(x->x["path"]==c["parent_path"],c["inputs"]))["sha256"]==r["parent_sha256"] || error("parent mismatch")
    for item in c["inputs"]
        code_only && startswith(item["path"],"output/") && continue
        p=RT.R.root_path(root,item["path"])
        isfile(p) && sha(p)==item["sha256"] || error("fullflux input hash mismatch: $p")
    end
    c
end
end
