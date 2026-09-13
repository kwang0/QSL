# Replay the tiny numerical fixture through the compact production summary.
# The chi1024 metadata below is synthetic; no scientific state is created.
using Test, TOML, Statistics
include("../scripts/thread_benchmark/Summary.jl")
const S=ThreadBenchmarkSummary
const C=S.C
length(ARGS)==2 || error("usage: thread_benchmark_records.jl VALIDATION_DIR CONTROL")
fixture,control=abspath.(ARGS)
directory=joinpath(fixture,"compact_replay"); ispath(directory) && error("fixture output exists")
mkpath(joinpath(directory,"metrics"))
cp(control,joinpath(directory,"control.snapshot.toml"))
c=TOML.parsefile(control); hash=C.sha(control); seed_sha=c["seed"]["source_sha256"]
common=Dict("control_sha256"=>hash,"source_seed_sha256"=>seed_sha,"scientific_promotion"=>false)
C.write_toml(joinpath(directory,"export.toml"),merge(common,Dict("bridge_sha256"=>repeat("a",64))))
C.write_toml(joinpath(directory,"seed.toml"),merge(common,Dict(
    "artifact_kind"=>"project_b_thread_benchmark_canonical_seed","bridge_sha256"=>repeat("a",64),
    "canonical_seed_sha256"=>repeat("b",64),"energy_density"=>0.,
    "julia_version"=>string(VERSION),"canonical_errors"=>Dict("left"=>1e-15,"right"=>1e-15,"center"=>1e-15))))

function journal(name,history)
    path=joinpath(directory,name*".tsv")
    open(path,"w") do io
        println(io,"iteration\tmeasured\tenergy_density\tnative_error\tchi\twall_seconds\tcpu_seconds")
        for h in history
            println(io,join((h[k] for k in ("iteration","measured","energy_density","native_error","chi","wall_seconds","cpu_seconds")),'\t'))
        end
    end
    C.sha(path)
end
rewrite(path,data)=open(io->TOML.print(io,data;sorted=true),path,"w")
for setting in c["recipe"]["settings"]
    name=setting["name"]; history=TOML.parsefile(joinpath(fixture,name*".toml"))["history"]
    for h in history; h["chi"]=1024; h["measured"]=h["iteration"]>1; end
    record=merge(common,Dict("artifact_kind"=>"project_b_vumps_thread_benchmark_result","schema_version"=>1,
        "setting"=>setting,"canonical_seed_sha256"=>repeat("b",64),"initial_energy_density"=>0.,
        "complete"=>true,"stop_reason"=>"fixed_budget_complete","history"=>history,
        "journal_sha256"=>journal(name,history),"julia_threads"=>setting["julia_threads"],
        "blas_threads"=>setting["blas_threads"],"step_cpus"=>16,"blas_backend"=>"fixture",
        "julia_version"=>string(VERSION)))
    C.write_toml(joinpath(directory,name*".toml"),record)
    write(joinpath(directory,"metrics",name*".time"),"Maximum resident set size (kbytes): 1048576\n")
end
write(joinpath(directory,"step_exit_codes.tsv"),"step\texit_code\nexport\t0\nprepare\t0\nj2_b1\t0\nj2_b4\t0\nj1_b8\t0\n")

@testset "compact timing replay" begin
    summary=S.summarize(directory)
    @test summary["complete"] && length(summary["settings"])==3
    @test first(summary["settings"])["speedup_over_j2_b1"]==1
    @test all(r["peak_process_rss_gib"]==1 for r in summary["settings"])
    S.display_summary(summary)
    # A validly rehashed journal with a changed trajectory must not win on speed.
    path=joinpath(directory,"j2_b4.toml"); saved=TOML.parsefile(path); bad=deepcopy(saved)
    bad["history"][2]["energy_density"]+=1e-4
    bad["journal_sha256"]=journal("j2_b4",bad["history"]); rewrite(path,bad)
    @test_throws "incomparable energy trajectories" S.summarize(directory)
    journal("j2_b4",saved["history"]); rewrite(path,saved)
    steps=joinpath(directory,"step_exit_codes.tsv"); saved_steps=read(steps,String)
    write(steps,replace(saved_steps,"j1_b8\t0"=>"j1_b8\t1"))
    @test_throws "failed worker step" S.summarize(directory)
    write(steps,saved_steps)
end
