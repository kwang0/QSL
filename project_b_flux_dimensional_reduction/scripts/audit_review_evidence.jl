include(joinpath(@__DIR__,"lib/ReviewEvidence.jl"))
using .ReviewEvidence, Dates, TOML, Statistics
const R=ReviewEvidence
function main(args)
    length(args)==1 || error("usage: audit_review_evidence.jl OUTPUT_DIRECTORY")
    output=abspath(only(args))
    ispath(output) && error("use a new immutable audit directory")
    rows=Dict{String,Any}[]; seen=Set{String}()
    for relative in ("output/phase1","output/phase1_tests","output/science","output/phase1_idmrg")
        directory=joinpath(R.ROOT,relative)
        isdir(directory) || continue
        for (dir,dirs,files) in walkdir(directory)
            filter!(d->!occursin("checkpoint",d),dirs)
            for file in sort(files)
                occursin(r"^(state_|analysis_).*\.h5$",file) || continue
                path=joinpath(dir,file); hash=R.sha(path)
                hash in seen && continue
                r=R.scalars(path;verified_sha256=hash); r["path"]=relpath(path,R.ROOT)
                push!(rows,r); push!(seen,hash)
            end
        end
    end
    sort!(rows;by=r->(r["branch"],r["theta_over_pi"],r["sha256"]))
    byhash=Dict(r["sha256"]=>r for r in rows)
    for r in rows
        predecessor=get(byhash,r["parent_sha256"],nothing)
        eligible=r["accepted"] && r["continuity_checked"] && r["continuity_passed"] &&
            !isnothing(predecessor) && predecessor["accepted"] &&
            predecessor["chi"]==r["chi"] && predecessor["period"]==r["period"]
        r["fidelity_susceptibility_qualified"]=eligible
        eligible || (r["finite_step_fidelity_susceptibility_per_radian2"]=NaN)
    end
    parent=R.scalars(R.parent_path())
    manifest=TOML.parsefile(joinpath(R.ROOT,R.CANDIDATE_MANIFEST))
    logpath=joinpath(R.ROOT,"output/yc8_1_chi1024_bridge_jobs/20260901T021845Z-yc8-1-chi1024-forward_bridge/logs/scan-57801654.out")
    log=read(logpath,String)
    # Match completed outer VUMPS summaries; the original transcript is hashed.
    matches=collect(eachmatch(r"VUMPS iteration \d+: chi=1024 residual=([0-9.eE+-]+) target=[0-9.eE+-]+ time=([0-9.eE+-]+)s",log))
    residuals=[parse(Float64,m[1]) for m in matches]
    timings=[parse(Float64,m[2]) for m in matches]
    length(residuals)==60 || error("expected 60 completed outer iterations in the pinned transcript")
    trends=Dict{String,Any}[]
    for window in (10,20,30,60)
        length(residuals)>=window || continue
        tr=R.trend(residuals[end-window+1:end])
        push!(trends,Dict("window"=>window,"log_residual_slope"=>tr.slope,"r_squared"=>tr.r_squared,
            "median_seconds_per_iteration"=>median(timings[end-window+1:end])))
    end
    notes=["Local mirror is retrospective, not scheduler or scratch authority.",
        "D=abs(e1-e2) is defined only for period 2; unavailable values are NaN or empty.",
        "Stored xi is in complete MPS transfer-cell units; multiply by period for snake-site spacing, not axial cylinder distance.",
        "Finite-step fidelity susceptibility uses radians and is missing at fixed flux or unchecked overlap.",
        "Period-6 scalar repetition does not prove gauge-equivalent period-2 tensors.",
        "Cross-flux or cross-chi energy differences are not topological-sector splittings.",
        "Neither the rejected iDMRG state nor the chi1024 candidate is an accepted lineage parent."]
    R.write_toml(joinpath(output,"audit.toml"),Dict("artifact_kind"=>"project_b_review_evidence_audit",
        "created_utc"=>string(now(UTC)),"authority"=>"retrospective_local_mirror",
        "script_sha256"=>R.sha(@__FILE__),"states"=>rows,"notes"=>notes,
        "candidate_manifest_path"=>R.CANDIDATE_MANIFEST,
        "candidate_manifest_sha256"=>R.sha(joinpath(R.ROOT,R.CANDIDATE_MANIFEST)),
        "candidate_full_state_verified"=>false,
        "candidate_entropy_mean_delta_lower_bound"=>manifest["mean_von_neumann_entropy"]-parent["mean_entropy"],
        "residual_log_sha256"=>R.sha(logpath),"matched_outer_residuals"=>length(residuals),"trends"=>trends))
    open(joinpath(output,"lineages.tsv"),"w") do io
        keys=["sha256","parent_sha256","branch","theta_over_pi","chi","period","accepted","energy_density",
            "dimerization","mean_entropy","vumps_projected_residual","overlap_per_site",
            "finite_step_fidelity_susceptibility_per_radian2","path"]
        println(io,join(keys,'\t'))
        for row in rows; println(io,join((row[k] for k in keys),'\t')); end
    end
    println("Audited ",length(rows)," unique artifacts; ",length(residuals)," outer residuals.")
    println(joinpath(output,"audit.toml"))
end
main(ARGS)
