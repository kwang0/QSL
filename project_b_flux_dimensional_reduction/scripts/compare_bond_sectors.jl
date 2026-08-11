#!/usr/bin/env julia

using Printf
using TriangularJ1J2ProjectB

length(ARGS) == 3 || error(
    "usage: compare_bond_sectors.jl BEFORE_STATE.h5 AFTER_STATE.h5 OUTPUT.tsv",
)

before_path = abspath(ARGS[1])
after_path = abspath(ARGS[2])
output_path = abspath(ARGS[3])
ispath(output_path) && error("refusing to overwrite existing comparison: $output_path")

before = TriangularJ1J2ProjectB.read_state_file(before_path)
after = TriangularJ1J2ProjectB.read_state_file(after_path)
before.circumference == after.circumference || error("state circumferences differ")
before.shift == after.shift || error("state YC shifts differ")
before.mps_period == after.mps_period || error("state MPS periods differ")

rows = compare_bond_sectors(before.psi, after.psi)
mkpath(dirname(output_path))
open(output_path, "w") do io
    println(
        io,
        "cut\tqn_label\tbefore_multiplicity\tafter_multiplicity\t" *
        "multiplicity_delta\tbefore_schmidt_weight\tafter_schmidt_weight\t" *
        "schmidt_weight_delta",
    )
    for row in rows
        @printf(
            io,
            "%d\t%s\t%d\t%d\t%d\t%.17g\t%.17g\t%.17g\n",
            row.cut,
            row.qn_label,
            row.before_multiplicity,
            row.after_multiplicity,
            row.multiplicity_delta,
            row.before_schmidt_weight,
            row.after_schmidt_weight,
            row.schmidt_weight_delta,
        )
    end
end

println("Bond-sector comparison: $output_path")
for cut in sort!(unique([row.cut for row in rows]))
    cut_rows = filter(row -> row.cut == cut, rows)
    before_dimension = sum(row.before_multiplicity for row in cut_rows)
    after_dimension = sum(row.after_multiplicity for row in cut_rows)
    new_sectors = count(row -> row.before_multiplicity == 0 && row.after_multiplicity > 0, cut_rows)
    removed_sectors = count(row -> row.before_multiplicity > 0 && row.after_multiplicity == 0, cut_rows)
    weight_shift = 0.5 * sum(abs(row.schmidt_weight_delta) for row in cut_rows)
    @printf(
        "Cut %d: chi %d -> %d, new sectors=%d, removed sectors=%d, sector-weight TV=%.6e\n",
        cut,
        before_dimension,
        after_dimension,
        new_sectors,
        removed_sectors,
        weight_shift,
    )
end
