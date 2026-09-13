# Brief copied-worker check, without tensor libraries or numerical fixtures.
using TOML
length(ARGS)==1 || error("usage: preflight.jl PROJECT_ROOT")
root=abspath(only(ARGS))
VERSION.major==1 && VERSION.minor==12 || error("Julia 1.12.x required")
for (env,names) in ((".",["ITensors","ITensorMPS","ITensorInfiniteMPS","HDF5"]),("idmrg",["MPSKit","TensorKit","HDF5"]))
    m=TOML.parsefile(joinpath(root,env,"Manifest.toml"))
    all(haskey(only(m["deps"][name]),"version") for name in names) || error("missing package pins")
end
for p in ("scripts/thread_benchmark/export_seed.jl","idmrg/thread_benchmark/run.jl","scripts/summarize_thread_benchmark.jl")
    isfile(joinpath(root,p)) || error("missing entry point: $p")
end
println("Copied threading worker smoke passed; no numerical tests run.")
