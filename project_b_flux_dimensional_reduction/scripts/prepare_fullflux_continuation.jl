using TOML, Dates
include("fullflux/Control.jl")
const C=FullFluxControl
length(ARGS)==1 || error("usage: prepare_fullflux_continuation.jl NEW_CONTROL")
r=C.validate_recipe(TOML.parsefile(joinpath(C.ROOT,"configs/fullflux_continuation.toml")))
previous=TOML.parsefile(joinpath(C.ROOT,"configs/controls/roundtrip_continuation_v1.toml"))
parent=previous["parent_path"]
for file in (parent,r["bridge_path"])
    record=only(filter(x->x["path"]==file,previous["inputs"]))
    C.sha(joinpath(C.ROOT,file))==record["sha256"] || error("accepted input mismatch: $file")
end
files=sort(unique(vcat(C.required_sources(),[parent,r["bridge_path"]])))
c=Dict("artifact_kind"=>"project_b_fullflux_control","schema_version"=>1,"created_utc"=>string(now(UTC)),
    "recipe"=>r,"parent_path"=>parent,"parent_energy_density_at_0p15"=>previous["parent_energy_density_at_0p15"],
    "inputs"=>[Dict("path"=>f,"sha256"=>C.sha(joinpath(C.ROOT,f))) for f in files])
C.write_toml(abspath(ARGS[1]),c); C.validate(ARGS[1])
println("Sealed control: ",abspath(ARGS[1]),"\nSHA-256: ",C.sha(ARGS[1]))
