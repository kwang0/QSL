include("Benchmark.jl")
length(ARGS)>=1 || error("usage: run.jl prepare CONTROL COMPACT | run CONTROL NAME COMPACT")
if ARGS[1]=="prepare" && length(ARGS)==3
    ThreadBenchmark.prepare(ARGS[2],ARGS[3])
elseif ARGS[1]=="run" && length(ARGS)==4
    ThreadBenchmark.run(ARGS[2],ARGS[3],ARGS[4])
else
    error("invalid benchmark action")
end
