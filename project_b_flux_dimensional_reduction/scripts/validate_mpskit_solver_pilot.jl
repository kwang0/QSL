println(stderr,"Starting pilot validation; loading Julia control checks."); flush(stderr)
include(joinpath(@__DIR__,"lib/SolverPilotControl.jl"))
using .SolverPilotControl
length(ARGS) in (1,2) || error("usage: validate_mpskit_solver_pilot.jl CONTROL [--live]")
length(ARGS)==1 || ARGS[2]=="--live" || error("unknown pilot-validation option")
c=SolverPilotControl.validate(ARGS[1];live=length(ARGS)==2 && ARGS[2]=="--live")
r=c["recipe"]["resources"]
println(join((SolverPilotControl.sha(ARGS[1]),r["forecast_node_hours"],r["allocation_cpus"],
    r["step_cpus"],r["julia_threads"],r["memory"],r["time_limit"],r["pretimeout_seconds"]),'\t'))
