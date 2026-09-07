module SolverPilotControl
using TOML
include("ProjectBAccounting.jl")
include("FileIntegrity.jl")
const ROOT=normpath(joinpath(@__DIR__,"../.."))
sha(path)=FileIntegrity.file_sha256(path)
portable(path)=replace(path,'\\'=>'/')
function root_path(root, relative)
    p=normpath(joinpath(root,relative))
    startswith(portable(p),rstrip(portable(normpath(root)),'/')*"/") ||
        error("input escapes project root: $p")
    p
end
function validate_audit(recipe; root=ROOT)
    path=root_path(root,recipe["checkpoint_audit_path"])
    isfile(path) || error("missing authoritative scratch audit: $path; run the manual preflight")
    audit=TOML.parsefile(path)
    audit["artifact_kind"]=="project_b_yc8_checkpoint_audit" &&
        audit["authority"]=="owner_run_perlmutter" &&
        audit["parent_sha256"]==recipe["parent_sha256"] &&
        audit["all_requested_hashes_verified"] || error("missing authoritative scratch audit")
    for (key,source) in (("audit_script_sha256","scripts/audit_yc8_bridge_checkpoints.jl"),
            ("audit_library_sha256","scripts/lib/ReviewEvidence.jl"),
            ("audit_hash_library_sha256","scripts/lib/FileIntegrity.jl"))
        get(audit,key,"")==sha(joinpath(root,source)) || error("scratch audit code changed: $source")
    end
    expected=["4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6",
        "45e5e6cf308936e35fdcf93f4d4cd909bcea4b8b71e061964b0e119ca1ddbcd7",
        "fa4d7f01dbb7e10deb1c37bab659c07a9dba60fe63ba3e3db34c705c102b3e9b"]
    all(hash->any(a->a["sha256"]==hash && a["hash_verified"],audit["artifacts"]),expected) ||
        error("scratch audit lacks a required candidate")
    audit
end
function validate(path; root=ROOT, live=false, code_only=false, progress=stderr)
    live && code_only && error("live validation must include data hashes")
    c=TOML.parsefile(path)
    c["artifact_kind"]=="project_b_mpskit_solver_pilot_control" && c["schema_version"]==1 ||
        error("invalid pilot control")
    recipe=TOML.parsefile(joinpath(root,"configs/mpskit_solver_pilot.toml"))
    c["recipe"]==recipe || error("pilot recipe changed; prepare a new control")
    c["recipe"]["parent_sha256"]=="38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803" ||
        error("pilot cannot change the accepted parent")
    live && validate_audit(recipe;root)
    println(progress,"Verifying sealed ",code_only ? "source" : "source and data"," inputs: ",basename(path)); flush(progress)
    for record in c["inputs"]
        p=root_path(root,record["path"])
        code_only && startswith(portable(record["path"]),"output/") && continue
        if isfile(p) && filesize(p)>8*2^20
            println(progress,"  SHA-256 ",round(filesize(p)/2.0^20;digits=1)," MiB: ",basename(p)); flush(progress)
        end
        isfile(p) && sha(p)==record["sha256"] || error("pilot input hash mismatch: $p")
    end
    r=recipe["resources"]
    forecast=ProjectBAccounting.reservation(r["allocation_cpus"],r["memory"],r["time_limit"];qos=r["qos"])
    forecast.allocated_cpus==r["allocation_cpus"] || error("allocation is under-requested")
    forecast.node_hours==r["forecast_node_hours"]<=r["maximum_node_hours"]<=0.5 || error("pilot cap exceeded")
    r["step_cpus"]<=r["allocation_cpus"] || error("step exceeds allocation")
    recipe["automatic_promotion"]==false && recipe["automatic_advance"]==false || error("pilot must remain diagnostic")
    println(progress,"Sealed inputs verified"); flush(progress)
    c
end
end
