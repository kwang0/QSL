include(joinpath(@__DIR__, "lib", "ProjectBAccounting.jl"))
using .ProjectBAccounting, Printf

function main(args)
    isempty(args) && error("usage: project_b_accounting.jl audit|guard|reconcile [--live] [FORECAST] | forecast CPUS MEMORY TIME [QOS]")
    action = popfirst!(args)
    if action == "forecast"
        length(args) in (3,4) || error("forecast requires CPUS MEMORY HH:MM:SS [QOS]")
        r = ProjectBAccounting.reservation(parse(Int,args[1]),args[2],args[3]; qos=get(args,4,"shared"))
        @printf("%d\t%.12f\n", r.allocated_cpus,r.node_hours)
        return
    end
    live = "--live" in args
    filter!(!=("--live"), args)
    forecast = isempty(args) ? 0.0 : parse(Float64, only(args))
    root = normpath(joinpath(@__DIR__, ".."))
    s = ProjectBAccounting.snapshot(root; live)
    if action == "ledger"
        println(s.phase1, '|', join(unique(vcat(s.missing,s.nonterminal,s.unreconciled)), ','))
        return
    end
    if action == "reconcile"
        ProjectBAccounting.reconcile(root,s)
        s = ProjectBAccounting.snapshot(root; live)
    end
    action in ("audit","guard","reconcile") || error("unknown action $action")
    action != "guard" && print(ProjectBAccounting.table(s))
    @printf("Phase 1: %.12f; remaining: %.12f; new reservation: %.12f\n",s.phase1,s.policy["phase1_ceiling_node_hours"]-s.phase1,forecast)
    @printf("Project B: %.12f (includes estimated Phase 0 %.6f)\n",s.total,s.policy["phase0_estimated_node_hours"])
    println("Authority: ",live ? "live Perlmutter" : "retrospective local mirror")
    for d in ProjectBAccounting.discrepancies(root,s)
        println("Charge correction job ",d.id,": ",d.old," -> ",d.corrected,"; recorded=",d.applied)
    end
    action == "guard" && ProjectBAccounting.assert_budget(root,s,forecast)
end

try
    main(copy(ARGS))
catch e
    showerror(stderr,e); println(stderr); exit(1)
end
