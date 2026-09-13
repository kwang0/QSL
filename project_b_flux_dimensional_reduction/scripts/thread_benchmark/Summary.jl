module ThreadBenchmarkSummary
using TOML, Statistics, Printf
include("Control.jl")
const C=ThreadBenchmarkControl

function summarize(directory;check_worker=true)
    path=joinpath(directory,"control.snapshot.toml"); c=TOML.parsefile(path); r=C.validate_recipe(c["recipe"]); hash=C.sha(path)
    c["artifact_kind"]=="project_b_vumps_thread_benchmark_control" && c["schema_version"]==1 || error("control schema")
    c["seed"]["source_sha256"]==C.SEED_SHA && c["seed"]["role"]=="rejected_candidate_timing_only" || error("source seed role")
    seedpath=joinpath(directory,"seed.toml"); seed=TOML.parsefile(seedpath)
    seed["artifact_kind"]=="project_b_thread_benchmark_canonical_seed" && !seed["scientific_promotion"] || error("canonical seed role")
    seed["control_sha256"]==hash && seed["source_seed_sha256"]==c["seed"]["source_sha256"] || error("seed provenance")
    export_record=TOML.parsefile(joinpath(directory,"export.toml"))
    export_record["source_seed_sha256"]==seed["source_seed_sha256"] && !export_record["scientific_promotion"] || error("export seed role")
    export_record["control_sha256"]==hash && export_record["bridge_sha256"]==seed["bridge_sha256"] || error("export provenance")
    maximum(values(seed["canonical_errors"]))<=r["canonical_tolerance"] || error("seed canonical validation failed")
    results=[TOML.parsefile(joinpath(directory,s["name"]*".toml")) for s in r["settings"]]
    baseline=first(results); rows=Dict{String,Any}[]
    for (a,setting) in zip(results,r["settings"])
        a["artifact_kind"]=="project_b_vumps_thread_benchmark_result" && a["schema_version"]==1 || error("result schema")
        a["complete"] && a["stop_reason"]=="fixed_budget_complete" && !a["scientific_promotion"] || error("incomplete benchmark")
        a["control_sha256"]==hash && a["setting"]==setting || error("result control/setting mismatch")
        a["source_seed_sha256"]==seed["source_seed_sha256"] && a["canonical_seed_sha256"]==seed["canonical_seed_sha256"] || error("different timing seed")
        (a["julia_threads"],a["blas_threads"],a["step_cpus"])==(setting["julia_threads"],setting["blas_threads"],r["resources"]["step_cpus"]) || error("runtime threads differ")
        abs(a["initial_energy_density"]-seed["energy_density"])<=r["initial_energy_match_tolerance"] || error("initial energy mismatch")
        a["blas_backend"]==baseline["blas_backend"] && a["julia_version"]==seed["julia_version"] || error("runtime changed")
        history=a["history"]; length(history)==4 || error("update count")
        journal=joinpath(directory,setting["name"]*".tsv")
        C.sha(journal)==a["journal_sha256"] || error("journal hash mismatch")
        lines=readlines(journal); length(lines)==5 || error("journal row count")
        for (i,h) in enumerate(history)
            h["iteration"]==i && h["measured"]==(i>r["warmup_iterations"]) && h["chi"]==r["chi"] || error("history schedule")
            h["wall_seconds"]>0 && h["cpu_seconds"]>=0 && all(isfinite(h[k]) for k in ("energy_density","native_error","wall_seconds","cpu_seconds")) || error("invalid timing/trajectory")
            fields=split(lines[i+1],'\t')
            parse(Int,fields[1])==i && parse(Bool,fields[2])==h["measured"] && parse(Int,fields[5])==h["chi"] || error("journal metadata")
            all(parse(Float64,fields[j])==h[k] for (j,k) in ((3,"energy_density"),(4,"native_error"),(6,"wall_seconds"),(7,"cpu_seconds"))) || error("journal values")
            ref=baseline["history"][i]
            abs(h["energy_density"]-ref["energy_density"])<=r["trajectory_energy_match_tolerance"] || error("incomparable energy trajectories")
            isapprox(h["native_error"],ref["native_error"];rtol=r["trajectory_error_match_rtol"],atol=1e-12) || error("incomparable residual trajectories")
        end
        measured=filter(h->h["measured"],history); times=[h["wall_seconds"] for h in measured]
        metrics=read(joinpath(directory,"metrics",setting["name"]*".time"),String)
        rss=match(r"Maximum resident set size \(kbytes\):\s*(\d+)",metrics)
        isnothing(rss) && error("missing process peak RSS")
        push!(rows,Dict("name"=>setting["name"],"mean_seconds"=>mean(times),"median_seconds"=>median(times),
            "minimum_seconds"=>minimum(times),"maximum_seconds"=>maximum(times),
            "peak_process_rss_gib"=>parse(Int,rss[1])/2.0^20,
            "effective_cpu_cores"=>sum(h["cpu_seconds"] for h in measured)/sum(times),
            "projected_node_hours_per_100_updates_at_64G"=>100mean(times)/3600*r["resources"]["allocation_cpus"]/256))
    end
    if check_worker
        status=Dict(split(line,'\t') for line in readlines(joinpath(directory,"step_exit_codes.tsv"))[2:end])
        Set(keys(status))==Set(["export","prepare",[s["name"] for s in r["settings"]]...]) || error("missing worker steps")
        all(==("0"),values(status)) || error("failed worker step")
    end
    fastest=rows[argmin([x["mean_seconds"] for x in rows])]["name"]
    for row in rows; row["speedup_over_j2_b1"]=first(rows)["mean_seconds"]/row["mean_seconds"]; end
    Dict("complete"=>true,"control_sha256"=>hash,"canonical_seed_sha256"=>seed["canonical_seed_sha256"],
        "fastest_measured_setting"=>fastest,"settings"=>rows,"source_theta_over_pi"=>r["theta_over_pi"],
        "interpretation"=>"Three measured updates per setting on a rejected chi1024 seed; provisional performance comparison, not convergence or a zero-flux preparation.")
end

function display_summary(s)
    println("BENCHMARK_COMPLETE=",s["complete"])
    println("Same canonical seed and matching numerical trajectories: PASS")
    println("setting\tmean_seconds\trange_seconds\teffective_cores\tpeak_RSS_GiB\tspeedup\tnode_hours_per_100_at_64G")
    for r in s["settings"]
        @printf("%s\t%.3f\t%.3f..%.3f\t%.3f\t%.3f\t%.3f\t%.6f\n",r["name"],r["mean_seconds"],
            r["minimum_seconds"],r["maximum_seconds"],r["effective_cpu_cores"],r["peak_process_rss_gib"],r["speedup_over_j2_b1"],r["projected_node_hours_per_100_updates_at_64G"])
    end
    println("Fastest measured setting: ",s["fastest_measured_setting"])
    println(s["interpretation"])
end
end
