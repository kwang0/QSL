#!/usr/bin/env julia

using HDF5
using Printf

1 <= length(ARGS) <= 2 || error(
    "usage: summarize_krylov_diagnostics.jl STATE.h5 [OUTPUT.tsv]",
)

state_path = abspath(ARGS[1])
isfile(state_path) || error("state file does not exist: $state_path")

rows = h5open(state_path, "r") do file
    path = "optimizer/krylov_solves"
    haskey(file, path) || error("state has no instrumented Krylov diagnostics")
    group = file[path]
    count = Int(read(group, "count"))
    count > 0 || return NamedTuple[]
    outer_iteration = Int.(read(group, "outer_iteration"))
    solve_kind = String.(read(group, "solve_kind"))
    site = Int.(read(group, "site"))
    requested_tolerance = Float64.(read(group, "requested_tolerance"))
    krylov_dimension = Int.(read(group, "krylov_dimension"))
    maximum_iterations = Int.(read(group, "maximum_iterations"))
    converged_count = Int.(read(group, "converged_count"))
    residual_norm = Float64.(read(group, "residual_norm"))
    iterations = Int.(read(group, "iterations"))
    operations = Int.(read(group, "operations"))
    elapsed_seconds = Float64.(read(group, "elapsed_seconds"))
    all(length(values) == count for values in (
        outer_iteration,
        solve_kind,
        site,
        requested_tolerance,
        krylov_dimension,
        maximum_iterations,
        converged_count,
        residual_norm,
        iterations,
        operations,
        elapsed_seconds,
    )) || error("Krylov diagnostic arrays have inconsistent lengths")
    return [
        (;
            outer_iteration=outer_iteration[index],
            solve_kind=solve_kind[index],
            site=site[index],
            requested_tolerance=requested_tolerance[index],
            krylov_dimension=krylov_dimension[index],
            maximum_iterations=maximum_iterations[index],
            converged_count=converged_count[index],
            residual_norm=residual_norm[index],
            iterations=iterations[index],
            operations=operations[index],
            elapsed_seconds=elapsed_seconds[index],
        ) for index in 1:count
    ]
end

if length(ARGS) == 2
    output_path = abspath(ARGS[2])
    ispath(output_path) && error("refusing to overwrite existing table: $output_path")
    mkpath(dirname(output_path))
    open(output_path, "w") do io
        println(
            io,
            "outer_iteration\tsolve_kind\tsite\trequested_tolerance\t" *
            "krylov_dimension\tmaximum_iterations\tconverged_count\t" *
            "residual_norm\titerations\toperations\telapsed_seconds",
        )
        for row in rows
            @printf(
                io,
                "%d\t%s\t%d\t%.17g\t%d\t%d\t%d\t%.17g\t%d\t%d\t%.17g\n",
                row.outer_iteration,
                row.solve_kind,
                row.site,
                row.requested_tolerance,
                row.krylov_dimension,
                row.maximum_iterations,
                row.converged_count,
                row.residual_norm,
                row.iterations,
                row.operations,
                row.elapsed_seconds,
            )
        end
    end
    println("Detailed Krylov table: $output_path")
end

println("State: $state_path")
println("Recorded Krylov solves: $(length(rows))")
for kind in sort!(unique([row.solve_kind for row in rows]))
    kind_rows = filter(row -> row.solve_kind == kind, rows)
    failures = count(row -> row.converged_count < 1, kind_rows)
    worst_residual = maximum(row -> row.residual_norm, kind_rows)
    maximum_iterations = maximum(row -> row.iterations, kind_rows)
    maximum_operations = maximum(row -> row.operations, kind_rows)
    total_seconds = sum(row -> row.elapsed_seconds, kind_rows)
    @printf(
        "%s: solves=%d, unconverged=%d, worst residual=%.6e, max iterations=%d, max operations=%d, total time=%.2fs\n",
        kind,
        length(kind_rows),
        failures,
        worst_residual,
        maximum_iterations,
        maximum_operations,
        total_seconds,
    )
end
