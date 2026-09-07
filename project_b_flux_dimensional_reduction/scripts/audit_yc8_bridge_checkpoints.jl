println("Starting checkpoint audit; loading Julia/HDF5. No optimizer is run."); flush(stdout)
include(joinpath(@__DIR__,"lib/ReviewEvidence.jl"))
include(joinpath(@__DIR__,"lib/SolverPilotControl.jl"))
using .ReviewEvidence, Dates, TOML, Statistics
const R = ReviewEvidence
function main(args)
    Sys.islinux() && startswith(get(ENV,"PSCRATCH",""),"/pscratch/") ||
        error("run this read-only scratch audit manually on Perlmutter")
    if length(args)==2 && args[1]=="--control"
        control=SolverPilotControl.validate(args[2];code_only=true)
        path=SolverPilotControl.root_path(R.ROOT,control["recipe"]["checkpoint_audit_path"])
        if isfile(path)
            SolverPilotControl.validate_audit(control["recipe"])
            println("Reusing verified immutable checkpoint audit: ",path)
            return
        end
        args=[path]
    end
    length(args) in (1,2) || error("usage: audit_yc8_bridge_checkpoints.jl OUTPUT.toml [--all] | --control CONTROL")
    length(args)==1 || args[2]=="--all" || error("unknown checkpoint-audit option")
    ispath(abspath(args[1])) && error("audit report already exists; preserve and validate it through plan")
    all_checkpoints = length(args)==2 && args[2]=="--all"
    println("Verifying accepted parent and reading scalar metadata"); flush(stdout)
    parent = R.scalars(R.parent_path();verified_sha256=R.PARENT_SHA)
    manifest = TOML.parsefile(joinpath(R.ROOT,R.CANDIDATE_MANIFEST))
    sources = [(manifest["full_state_path"],manifest["full_state_sha256"],"rejected_candidate")]
    for file in sort(readdir(joinpath(R.ROOT,R.CAMPAIGN,"checkpoint_manifests");join=true))
        endswith(file,".toml") || continue
        cfg = TOML.parsefile(file); scan=get(cfg,"scan",Dict())
        hash=get(scan,"optimizer_checkpoint_sha256","")
        (all_checkpoints || hash in R.CHECKPOINT_HASHES) || continue
        scan["initial_state_sha256"]==R.PARENT_SHA || error("checkpoint lineage changed")
        push!(sources,(scan["optimizer_checkpoint_file"],hash,"optimizer_checkpoint"))
    end
    all(hash->any(x->x[2]==hash,sources),R.CHECKPOINT_HASHES) || error("missing selected checkpoint manifests")
    rows=Dict{String,Any}[]
    println("Hashing ",length(sources)," selected scratch files; --all audits the complete history.")
    flush(stdout)
    for (i,(path,hash,role)) in enumerate(sources)
        startswith(path,"/pscratch/") || error("non-scratch candidate path")
        isfile(path) || error("missing scratch artifact: $path")
        started=time()
        println("[",i,"/",length(sources),"] ",role," ",round(filesize(path)/2.0^20;digits=1)," MiB: ",basename(path))
        flush(stdout)
        R.sha(path)==hash || error("scratch SHA-256 mismatch: $path")
        r=R.scalars(path;verified_sha256=hash)
        r["parent_sha256"]==R.PARENT_SHA || error("checkpoint parent mismatch")
        r["theta_over_pi"]==0.15 && r["chi"]==1024 || error("checkpoint scope mismatch")
        r["accepted"]==false || error("diagnostic unexpectedly accepted")
        r["role"]=role; r["hash_verified"]=true
        r["entropy_mean_delta_from_parent"]=r["mean_entropy"]-parent["mean_entropy"]
        r["maximum_cut_entropy_jump_from_parent"]=maximum(abs.(r["entropy_by_cut"].-parent["entropy_by_cut"]))
        r["exceeds_declared_growth_entropy_bound"]=r["maximum_cut_entropy_jump_from_parent"]>0.35
        push!(rows,r)
        println("  verified; scalar metadata read in ",round(time()-started;digits=1)," seconds")
        flush(stdout)
    end
    data=Dict("artifact_kind"=>"project_b_yc8_checkpoint_audit","schema_version"=>1,
        "created_utc"=>string(now(UTC)),"authority"=>"owner_run_perlmutter",
        "parent_sha256"=>R.PARENT_SHA,"parent"=>parent,"artifacts"=>rows,
        "all_requested_hashes_verified"=>true,"all_checkpoints"=>all_checkpoints,
        "lineage_promotion_performed"=>false,"anchor_resume_recommended"=>false,
        "interpretation"=>"Scalar trust-region diagnostics only; no new convergence or physical endpoint claim.",
        "audit_script_sha256"=>R.sha(@__FILE__),
        "audit_library_sha256"=>R.sha(joinpath(@__DIR__,"lib/ReviewEvidence.jl")),
        "audit_hash_library_sha256"=>R.sha(joinpath(@__DIR__,"lib/FileIntegrity.jl")))
    R.write_toml(abspath(args[1]),data)
    println("Verified ",length(rows)," scratch artifacts; parent unchanged.")
    for r in rows
        println(r["role"]," iter=",r["iteration"]," residual=",r["vumps_projected_residual"],
            " max entropy jump=",r["maximum_cut_entropy_jump_from_parent"])
    end
    println("Audit: ",abspath(args[1]))
end
main(ARGS)
