#!/usr/bin/env julia

using TriangularJ1J2ProjectB

length(ARGS) >= 2 || error("usage: run_chi_ladder.jl CONFIG.toml CHI [CHI ...]")
settings = load_settings(first(ARGS))
maxdims = parse.(Int, ARGS[2:end])
paths = run_chi_ladder(settings, maxdims)
println("\nSaved $(length(paths)) chi-ladder states:")
foreach(path -> println(path), paths)
