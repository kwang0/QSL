#!/usr/bin/env julia

using Printf
using TriangularJ1J2ProjectB

length(ARGS) in (2, 3) || error(
    "usage: compare_phase1_branches.jl PRIMARY_STATE_DIRECTORY COMPETING_STATE_DIRECTORY [OUTPUT.tsv]",
)

primary_rows = summarize_state_files(ARGS[1]; include_hashes=true)
competing_rows = summarize_state_files(ARGS[2]; include_hashes=true)
isempty(primary_rows) && error("no primary state artifacts found under $(ARGS[1])")
isempty(competing_rows) && error("no competing state artifacts found under $(ARGS[2])")

function preparation_signature(rows)
    signatures = unique(
        (
            row.geometry,
            row.branch,
            row.preparation,
            row.direction,
            row.random_seed,
        ) for row in rows
    )
    length(signatures) == 1 || error(
        "a comparison directory mixes branch/preparation/direction/seed identities: $signatures",
    )
    return only(signatures)
end

primary_signature = preparation_signature(primary_rows)
competing_signature = preparation_signature(competing_rows)
first(primary_signature) == first(competing_signature) || error(
    "cannot compare different geometries: $(first(primary_signature)) and " *
    "$(first(competing_signature))",
)
primary_signature != competing_signature || error(
    "primary and competing directories have the same preparation signature; " *
    "an independent basin diagnostic is required",
)

function representative(rows, theta_over_pi)
    candidates = filter(
        row -> isapprox(row.theta_over_pi, theta_over_pi; atol=1e-12, rtol=0),
        rows,
    )
    isempty(candidates) && return nothing
    # Prefer a state that passed both numerical convergence and parent-overlap
    # continuity. Multiple rejected attempts are ranked only by residual.
    sort!(candidates; by=row -> (!row.continuation_accepted, row.residual))
    return first(candidates)
end

theta_values = sort!(unique!(vcat(
    [row.theta_over_pi for row in primary_rows],
    [row.theta_over_pi for row in competing_rows],
)))

function cell(row, field, fallback)
    row === nothing && return fallback
    return getproperty(row, field)
end

const ROW_FORMAT = Printf.Format(
    "%s\t%.10g\t%s\t%s\t%s\t%d\t%d\t%s\t%.8e\t%.14g\t%.10g\t%.8e\t%s\t" *
    "%s\t%s\t%s\t%d\t%d\t%s\t%.8e\t%.14g\t%.10g\t%.8e\t%s\t" *
    "%.8e\t%.8e\t%s\t%s\n",
)

function emit_report(io)
    println(
        io,
        "geometry\ttheta_over_pi\tprimary_branch\tprimary_preparation\tprimary_direction\t" *
        "primary_seed\tprimary_chi\tprimary_accepted\tprimary_residual\tprimary_energy\t" *
        "primary_entropy\tprimary_energy_term_std\tprimary_state_sha256\t" *
        "competing_branch\tcompeting_preparation\tcompeting_direction\t" *
        "competing_seed\tcompeting_chi\tcompeting_accepted\tcompeting_residual\t" *
        "competing_energy\tcompeting_entropy\tcompeting_energy_term_std\t" *
        "competing_state_sha256\tdelta_energy_competing_minus_primary\t" *
        "delta_entropy_competing_minus_primary\tenergy_order\tclassification",
    )
    for theta_over_pi in theta_values
        primary = representative(primary_rows, theta_over_pi)
        competing = representative(competing_rows, theta_over_pi)
        both_accepted = primary !== nothing && competing !== nothing &&
            primary.continuation_accepted && competing.continuation_accepted
        delta_energy = both_accepted ?
            competing.energy_density - primary.energy_density : NaN
        delta_entropy = both_accepted ?
            competing.mean_entropy - primary.mean_entropy : NaN
        energy_scale = both_accepted ?
            max(abs(primary.energy_density), abs(competing.energy_density), 1.0) : 1.0
        energy_order = if !both_accepted
            "not_comparable"
        elseif abs(delta_energy) <= 1e-10 * energy_scale
            "tied_within_1e-10_relative"
        elseif delta_energy > 0
            "primary_lower"
        else
            "competing_lower"
        end
        classification = if both_accepted
            "paired_accepted_branches_identity_check_required"
        elseif primary === nothing || !primary.continuation_accepted
            competing === nothing || !competing.continuation_accepted ?
                "neither_preparation_accepted" :
                "primary_missing_or_rejected"
        else
            "competing_missing_or_rejected"
        end
        Printf.format(
            io,
            ROW_FORMAT,
            first(primary_signature),
            theta_over_pi,
            cell(primary, :branch, "missing"),
            cell(primary, :preparation, "missing"),
            cell(primary, :direction, "missing"),
            cell(primary, :random_seed, -1),
            cell(primary, :maxlinkdim, -1),
            cell(primary, :continuation_accepted, false),
            cell(primary, :residual, NaN),
            cell(primary, :energy_density, NaN),
            cell(primary, :mean_entropy, NaN),
            cell(primary, :energy_term_std, NaN),
            cell(primary, :state_sha256, ""),
            cell(competing, :branch, "missing"),
            cell(competing, :preparation, "missing"),
            cell(competing, :direction, "missing"),
            cell(competing, :random_seed, -1),
            cell(competing, :maxlinkdim, -1),
            cell(competing, :continuation_accepted, false),
            cell(competing, :residual, NaN),
            cell(competing, :energy_density, NaN),
            cell(competing, :mean_entropy, NaN),
            cell(competing, :energy_term_std, NaN),
            cell(competing, :state_sha256, ""),
            delta_energy,
            delta_entropy,
            energy_order,
            classification,
        )
    end
end

if length(ARGS) == 3
    output_path = abspath(ARGS[3])
    mkpath(dirname(output_path))
    ispath(output_path) && error("refusing to overwrite branch comparison: $output_path")
    open(emit_report, output_path, "w")
    println(output_path)
else
    emit_report(stdout)
end
