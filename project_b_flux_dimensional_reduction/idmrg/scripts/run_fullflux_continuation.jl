include("../fullflux/Continuation.jl")
length(ARGS)==4 || error("usage: run_fullflux_continuation.jl CONTROL ARM SCRATCH COMPACT")
try
    FullFluxContinuation.run_arm(ARGS...;deadline=parse(Float64,get(ENV,"PROJECT_B_FULLFLUX_DEADLINE","Inf")),
        stop_file=get(ENV,"PROJECT_B_PRETIMEOUT_REQUEST_FILE",""))
catch e
    C=FullFluxContinuation.C
    C.write_toml(joinpath(ARGS[4],ARGS[2]*"_failure.toml"),Dict("artifact_kind"=>"project_b_fullflux_failure",
        "control_sha256"=>C.sha(ARGS[1]),"arm"=>ARGS[2],"error"=>sprint(showerror,e),"continuation_accepted"=>false))
    rethrow()
end
