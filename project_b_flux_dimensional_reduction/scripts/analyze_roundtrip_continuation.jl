include("roundtrip/Analysis.jl")
length(ARGS)==3 || error("usage: analyze_roundtrip_continuation.jl CONTROL COMPACT ARM")
RoundTripAnalysis.analyze_arm(ARGS...)
