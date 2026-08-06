#!/usr/bin/env julia

using TriangularJ1J2ProjectB

length(ARGS) >= 1 || error("usage: run_spectrum.jl CONFIG.toml [STATE.h5 ...]")
settings = load_settings(first(ARGS))
state_paths = if length(ARGS) > 1
    ARGS[2:end]
else
    rows = summarize_state_files(joinpath(settings.runtime.output_directory, "states"))
    [row.path for row in rows if row.converged]
end
isempty(state_paths) && error("no converged state files found")

for state_path in state_paths
    output_path = postprocess_state_spectrum(state_path, settings)
    println(output_path)
end
