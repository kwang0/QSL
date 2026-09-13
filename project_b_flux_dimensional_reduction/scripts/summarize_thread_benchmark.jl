include("thread_benchmark/Summary.jl")
length(ARGS)==1 || error("usage: summarize_thread_benchmark.jl RUN_DIRECTORY")
ThreadBenchmarkSummary.display_summary(ThreadBenchmarkSummary.summarize(abspath(only(ARGS))))
