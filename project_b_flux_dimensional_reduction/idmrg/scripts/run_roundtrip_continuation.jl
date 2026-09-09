include("../roundtrip/Continuation.jl")
length(ARGS)==4 || error("usage: run_roundtrip_continuation.jl CONTROL ARM SCRATCH COMPACT")
RoundTripContinuation.run_arm(ARGS...;deadline=parse(Float64,get(ENV,"PROJECT_B_ROUNDTRIP_DEADLINE","Inf")),
    stop_file=get(ENV,"PROJECT_B_PRETIMEOUT_REQUEST_FILE",""))
