include("fullflux/Control.jl")
length(ARGS) in (1,2) || error("usage: validate_fullflux_continuation.jl CONTROL [--code-only]")
length(ARGS)==1 || ARGS[2]=="--code-only" || error("unknown option")
c=FullFluxControl.validate(ARGS[1];code_only=length(ARGS)==2); r=c["recipe"]["resources"]
println(join([FullFluxControl.sha(ARGS[1]);[r[k] for k in ("forecast_node_hours","allocation_cpus","step_cpus","julia_threads","memory","time_limit","pretimeout_seconds","solver_seconds")]],'\t'))
