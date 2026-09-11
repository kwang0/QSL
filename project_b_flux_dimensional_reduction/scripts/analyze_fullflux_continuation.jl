include("fullflux/Analysis.jl")
length(ARGS)==3 || error("usage: analyze_fullflux_continuation.jl CONTROL COMPACT ARM")
FullFluxAnalysis.analyze_arm(ARGS...)
