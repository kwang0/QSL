module RelaxationControl
using TOML
include("SolverPilotControl.jl")
const P = SolverPilotControl
const ROOT = P.ROOT
const PARENT_SHA = "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
sha(path) = P.sha(path)
root_path(root, path) = P.root_path(root, path)

function arms(r)
    result = [Dict{String,Any}("name"=>"baseline", "iterations"=>r["baseline_iterations"],
        "fluxes"=>[r["start_theta_over_pi"]], "hold_iterations"=>0, "step_over_pi"=>0.0)]
    for n in r["iteration_budgets"], (j, step) in enumerate(r["steps_over_pi"])
        count = round(Int, (r["end_theta_over_pi"]-r["start_theta_over_pi"])/step)
        isapprox(r["start_theta_over_pi"]+count*step,r["end_theta_over_pi"];atol=1e-12) || error("nonintegral flux grid")
        push!(result, Dict("name"=>"n$(n)_grid$(j)", "iterations"=>n,
            "fluxes"=>[round(r["start_theta_over_pi"]+k*step;digits=10) for k in 1:count],
            "hold_iterations"=>r["hold_iterations"], "step_over_pi"=>step))
    end
    result
end

function validate_recipe(r)
    r["artifact_kind"]=="project_b_relaxation_continuation_recipe" && r["schema_version"]==1 || error("recipe schema")
    r["parent_sha256"]==PARENT_SHA && r["chi"]==512 && r["algorithm"]=="VUMPS" || error("representation/parent changed")
    r["random_seed"]==101 || error("unmatched random seed")
    r["start_theta_over_pi"]==0.15 && r["end_theta_over_pi"]==0.20 || error("unbudgeted flux range")
    r["steps_over_pi"]==[0.025,0.0125] && r["iteration_budgets"]==[8,16,32] || error("unbudgeted schedule")
    r["baseline_iterations"]==32 && r["hold_iterations"]==16 && r["checkpoint_every"]==1 || error("checkpoint/budget recipe")
    !r["automatic_promotion"] && r["diagnostic_advance_without_native_convergence"] && !r["advance_on_turnaround"] || error("diagnostic policy changed")
    total=sum(length(a["fluxes"])*a["iterations"]+a["hold_iterations"] for a in arms(r))
    total==464 || error("unbudgeted iteration count")
    resources=r["resources"]
    f=P.ProjectBAccounting.reservation(resources["allocation_cpus"],resources["memory"],resources["time_limit"];qos=resources["qos"])
    f.allocated_cpus==resources["allocation_cpus"]==10 || error("CPU/memory rounding changed")
    f.node_hours==resources["forecast_node_hours"]<=resources["maximum_node_hours"]<=1.5 || error("reservation exceeds cap")
    resources["step_cpus"]==4 && resources["julia_threads"]==2 && resources["blas_threads"]==1 || error("unbenchmarked threading")
    0<resources["solver_seconds"]<=P.ProjectBAccounting.seconds(resources["time_limit"])-3600 || error("missing analysis margin")
    r
end

function required_sources(root=ROOT)
    files=["Project.toml","Manifest.toml","idmrg/Project.toml","idmrg/Manifest.toml",
        "configs/relaxation_continuation.toml","configs/project_b_accounting.toml",
        "slurm/lib/project_b_resources.sh","slurm/run_relaxation_continuation_cpu.sh","slurm/run_relaxation_continuation_job.sh",
        "scripts/project_b_accounting.jl","scripts/prepare_relaxation_continuation.jl",
        "scripts/validate_relaxation_continuation.jl","scripts/analyze_relaxation_continuation.jl",
        "scripts/summarize_relaxation_continuation.jl","idmrg/scripts/run_relaxation_continuation.jl",
        "idmrg/test/relaxation_continuation.jl","test/relaxation_analysis.jl"]
    for directory in ("src","scripts/lib","idmrg/src")
        append!(files,[replace(joinpath(directory,f),'\\'=>'/') for f in readdir(joinpath(root,directory)) if endswith(f,".jl")])
    end
    sort(unique(files))
end

function validate(path;root=ROOT,code_only=false)
    c=TOML.parsefile(path)
    c["artifact_kind"]=="project_b_relaxation_continuation_control" && c["schema_version"]==1 || error("control schema")
    r=validate_recipe(c["recipe"])
    r==TOML.parsefile(joinpath(root,"configs/relaxation_continuation.toml")) || error("recipe changed; seal a new control")
    expected=sort(unique(vcat(required_sources(root),[r["bridge_path"],c["parent_path"]])))
    sort([x["path"] for x in c["inputs"]])==expected || error("incomplete or duplicated sealed inputs")
    for x in c["inputs"]
        code_only && startswith(x["path"],"output/") && continue
        p=root_path(root,x["path"])
        isfile(p) && sha(p)==x["sha256"] || error("relaxation input hash mismatch: $p")
    end
    only(filter(x->x["path"]==c["parent_path"],c["inputs"]))["sha256"]==PARENT_SHA || error("parent hash mismatch")
    c
end

function write_toml(path, data)
    ispath(path) && error("immutable artifact exists: $path")
    mkpath(dirname(path)); tmp=path*".tmp"
    ispath(tmp) && error("stale temporary artifact: $tmp")
    open(io->TOML.print(io,data;sorted=true),tmp,"w")
    mv(tmp,path)
    path
end
end
