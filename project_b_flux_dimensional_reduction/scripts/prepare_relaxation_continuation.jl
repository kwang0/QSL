using TOML, Dates
include(joinpath(@__DIR__,"lib/RelaxationControl.jl"))
const RC=RelaxationControl
length(ARGS)==1 || error("usage: prepare_relaxation_continuation.jl NEW_CONTROL")
r=RC.validate_recipe(TOML.parsefile(joinpath(RC.ROOT,"configs/relaxation_continuation.toml")))
previous=TOML.parsefile(joinpath(RC.ROOT,"configs/controls/solver_pilot_control_v2.toml"))
parent=previous["parent_path"]
# The accepted bridge is inherited by hash, not by a newest-file heuristic.
for file in (parent,r["bridge_path"])
    record=only(filter(x->x["path"]==file,previous["inputs"]))
    RC.sha(joinpath(RC.ROOT,file))==record["sha256"] || error("historical input hash differs: $file")
end
files=sort(unique(vcat(RC.required_sources(),[parent,r["bridge_path"]])))
c=Dict("artifact_kind"=>"project_b_relaxation_continuation_control","schema_version"=>1,
    "created_utc"=>string(now(UTC)),"recipe"=>r,"parent_path"=>parent,
    "parent_energy_density_at_0p15"=>previous["parent_energy_density_at_0p15"],
    "inputs"=>[Dict("path"=>f,"sha256"=>RC.sha(joinpath(RC.ROOT,f))) for f in files])
RC.write_toml(abspath(ARGS[1]),c)
RC.validate(ARGS[1])
println("Sealed control: ",abspath(ARGS[1]),"\nSHA-256: ",RC.sha(ARGS[1]))
