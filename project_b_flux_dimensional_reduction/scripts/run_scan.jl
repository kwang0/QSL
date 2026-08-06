#!/usr/bin/env julia

using TriangularJ1J2ProjectB

length(ARGS) == 1 || error("usage: run_scan.jl CONFIG.toml")
settings = load_settings(only(ARGS))
paths = run_flux_scan(settings)
println("\nSaved $(length(paths)) state artifacts:")
foreach(path -> println(path), paths)
