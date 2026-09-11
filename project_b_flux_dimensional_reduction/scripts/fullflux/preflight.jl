# Fast copied-worker smoke check. No tensor libraries, numerical fixtures or solves.
using TOML
length(ARGS)==1 || error("usage: preflight.jl PROJECT_ROOT")
root=abspath(only(ARGS))
VERSION.major==1 && VERSION.minor==12 || error("Julia 1.12.x required; found $VERSION")
for (environment,packages) in ((".",["ITensors","ITensorMPS","ITensorInfiniteMPS","HDF5"]),
                             ("idmrg",["MPSKit","TensorKit","HDF5"]))
    manifest=TOML.parsefile(joinpath(root,environment,"Manifest.toml"))
    for name in packages
        entries=manifest["deps"][name]
        haskey(only(entries),"version") || error("missing pinned package: $name")
    end
end
for file in ("idmrg/scripts/run_fullflux_continuation.jl","scripts/analyze_fullflux_continuation.jl")
    isfile(joinpath(root,file)) || error("missing entry point: $file")
end
println("Copied fullflux worker smoke passed: Julia ",VERSION,"; pinned manifests and entry points present. No numerical tests run.")
