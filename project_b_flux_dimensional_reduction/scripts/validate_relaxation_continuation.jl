include(joinpath(@__DIR__,"lib/RelaxationControl.jl"))
length(ARGS) in (1,2) || error("usage: validate_relaxation_continuation.jl CONTROL [--code-only]")
length(ARGS)==1 || ARGS[2]=="--code-only" || error("unknown validation option")
c=RelaxationControl.validate(ARGS[1];code_only=length(ARGS)==2)
r=c["recipe"]["resources"]
println(join((RelaxationControl.sha(ARGS[1]),r["forecast_node_hours"],r["allocation_cpus"],
    r["step_cpus"],r["julia_threads"],r["memory"],r["time_limit"],r["pretimeout_seconds"]),'\t'))
