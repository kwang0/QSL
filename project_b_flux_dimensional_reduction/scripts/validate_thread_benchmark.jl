include("thread_benchmark/Control.jl")
const C=ThreadBenchmarkControl
1<=length(ARGS)<=2 || error("usage: validate_thread_benchmark.jl CONTROL [--live]")
length(ARGS)==1 || ARGS[2]=="--live" || error("unknown validation option")
c=C.validate(ARGS[1];live=length(ARGS)==2); r=c["recipe"]["resources"]
println(join((C.sha(ARGS[1]),r["forecast_node_hours"],r["allocation_cpus"],r["step_cpus"],
    r["memory"],r["time_limit"],r["pretimeout_seconds"]),'\t'))
