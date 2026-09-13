using TOML, Dates
include("thread_benchmark/Control.jl")
const C=ThreadBenchmarkControl
length(ARGS)==1 || error("usage: prepare_thread_benchmark.jl NEW_CONTROL")
r=C.validate_recipe(TOML.parsefile(joinpath(C.ROOT,"configs/thread_benchmark.toml")))
c=Dict("artifact_kind"=>"project_b_vumps_thread_benchmark_control","schema_version"=>1,
    "created_utc"=>string(now(UTC)),"recipe"=>r,"seed"=>TOML.parsefile(joinpath(C.ROOT,r["seed_manifest"])),
    "inputs"=>[Dict("path"=>p,"sha256"=>C.sha(joinpath(C.ROOT,p))) for p in C.required_sources()])
C.write_toml(abspath(only(ARGS)),c); C.validate(only(ARGS))
println("Sealed ",only(ARGS),"\nSHA-256: ",C.sha(only(ARGS)),"\nRemote seed presence/hash deferred to live preflight.")
