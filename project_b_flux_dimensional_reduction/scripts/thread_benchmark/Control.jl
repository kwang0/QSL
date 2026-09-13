module ThreadBenchmarkControl
using TOML, Dates
include("../lib/SolverPilotControl.jl")
const P=SolverPilotControl
const ROOT=P.ROOT
const sha=P.sha
const SEED_SHA="4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6"
const PARENT_SHA="38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"

function write_toml(path,data)
    ispath(path) && error("immutable output exists: $path")
    mkpath(dirname(path)); tmp=path*".tmp"
    ispath(tmp) && error("stale output temporary: $tmp")
    open(tmp,"w") do io; TOML.print(io,data;sorted=true); end
    mv(tmp,path); path
end

function validate_recipe(r)
    r["artifact_kind"]=="project_b_vumps_thread_benchmark_recipe" && r["schema_version"]==1 || error("recipe schema")
    r["chi"]==1024 && r["theta_over_pi"]==0.15 && r["algorithm"]=="VUMPS" || error("benchmark representation changed")
    r["warmup_iterations"]==1 && r["measured_iterations"]==3 && r["random_seed"]==101 || error("benchmark work changed")
    !r["automatic_promotion"] && !r["automatic_advance"] || error("benchmark cannot promote or advance")
    [(s["name"],s["julia_threads"],s["blas_threads"]) for s in r["settings"]]==
        [("j2_b1",2,1),("j2_b4",2,4),("j1_b8",1,8)] || error("unmatched thread settings")
    for (key,value) in (("initial_energy_match_tolerance",1e-10),("trajectory_energy_match_tolerance",1e-8),
                        ("trajectory_error_match_rtol",1e-3),("canonical_tolerance",1e-8))
        r[key]==value || error("benchmark comparison tolerance changed: $key")
    end
    a=r["resources"]
    a["qos"]=="shared" && a["allocation_cpus"]==34 && a["step_cpus"]==16 && a["memory"]=="64G" || error("resource recipe")
    a["time_limit"]=="06:00:00" && a["pretimeout_seconds"]==300 || error("time recipe")
    f=P.ProjectBAccounting.reservation(a["allocation_cpus"],a["memory"],a["time_limit"];qos=a["qos"])
    f.allocated_cpus==34 && f.node_hours==a["forecast_node_hours"]==0.796875 || error("reservation mismatch")
    r
end

function required_sources(root=ROOT)
    files=["Project.toml","Manifest.toml","idmrg/Project.toml","idmrg/Manifest.toml",
        "configs/thread_benchmark.toml","configs/seeds/thread_benchmark_chi1024.toml","configs/project_b_accounting.toml",
        "scripts/prepare_thread_benchmark.jl","scripts/validate_thread_benchmark.jl","scripts/summarize_thread_benchmark.jl",
        "scripts/project_b_accounting.jl","scripts/audit_project_context.jl",
        "slurm/lib/project_b_resources.sh","slurm/run_thread_benchmark_cpu.sh","slurm/run_thread_benchmark_job.sh"]
    for directory in ("src","scripts/lib","idmrg/src","scripts/thread_benchmark","idmrg/thread_benchmark")
        append!(files,[replace(joinpath(directory,f),'\\'=>'/') for f in readdir(joinpath(root,directory)) if endswith(f,".jl")])
    end
    sort(unique(files))
end

function validate(path;root=ROOT,live=false)
    c=TOML.parsefile(path)
    c["artifact_kind"]=="project_b_vumps_thread_benchmark_control" && c["schema_version"]==1 || error("control schema")
    r=validate_recipe(c["recipe"])
    r==TOML.parsefile(joinpath(root,"configs/thread_benchmark.toml")) || error("recipe changed; seal a successor")
    c["seed"]==TOML.parsefile(P.root_path(root,r["seed_manifest"])) || error("seed manifest changed")
    s=c["seed"]
    s["source_sha256"]==SEED_SHA && s["accepted_parent_sha256"]==PARENT_SHA &&
        s["role"]=="rejected_candidate_timing_only" && s["chi"]==1024 && s["theta_over_pi"]==0.15 || error("seed role changed")
    sort([x["path"] for x in c["inputs"]])==required_sources(root) || error("incomplete or duplicate source pins")
    for x in c["inputs"]
        p=P.root_path(root,x["path"])
        isfile(p) && sha(p)==x["sha256"] || error("source hash mismatch: $p")
    end
    if live
        Sys.islinux() || error("live seed validation requires Perlmutter Linux")
        scratch=get(ENV,"PSCRATCH",""); startswith(scratch,"/pscratch/") || error("PSCRATCH is unavailable")
        p=s["source_path"]
        isfile(p) || error("missing historical chi1024 scratch seed: $p; no job submitted")
        startswith(realpath(p),rstrip(realpath(scratch),'/')*"/") || error("seed is outside current PSCRATCH")
        sha(p)==s["source_sha256"] || error("historical chi1024 seed hash mismatch")
    end
    c
end
end
