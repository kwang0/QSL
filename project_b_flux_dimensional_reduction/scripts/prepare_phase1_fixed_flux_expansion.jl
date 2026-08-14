#!/usr/bin/env julia

using TOML
using TriangularJ1J2ProjectB

3 <= length(ARGS) <= 4 || error(
    "usage: prepare_phase1_fixed_flux_expansion.jl PARENT_STATE.h5 " *
    "PARENT_SHA256 TARGET_MAXDIM [CONFIG_DIRECTORY]",
)

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))

parent_path = abspath(ARGS[1])
expected_sha256 = lowercase(ARGS[2])
occursin(r"^[0-9a-f]{64}$", expected_sha256) || error(
    "PARENT_SHA256 must contain 64 lowercase hexadecimal digits",
)
actual_sha256 = PB.file_sha256(parent_path)
actual_sha256 == expected_sha256 || error(
    "parent SHA-256 mismatch: expected $expected_sha256, got $actual_sha256",
)

target_maxdim = try
    parse(Int, ARGS[3])
catch
    error("TARGET_MAXDIM must be an integer")
end

parent = PB.read_state_file(parent_path)
parent.schema_version >= 3 || error("fixed-flux Phase 1 expansion requires schema-v3 lineage")
parent.converged || error("parent state is not numerically converged")
parent.continuation_accepted || error("parent state was not accepted for continuation")
parent.circumference == 8 && parent.shift == 1 || error(
    "fixed-flux Phase 1 expansion requires a YC8-1 parent",
)
parent.mps_period == 2 || error("fixed-flux Phase 1 expansion requires the minimal two-site cell")
parent.branch == "primary_forward" || error(
    "fixed-flux Phase 1 expansion requires the primary-forward branch",
)
parent.direction === :forward || error("fixed-flux Phase 1 expansion requires a forward parent")
parent.twist_gauge === :uniform || error("fixed-flux Phase 1 expansion requires uniform twist gauge")
0.0 <= parent.theta_over_pi <= 1.0 || error(
    "parent theta/pi=$(parent.theta_over_pi) lies outside the YC8-1 Phase 1 scout interval",
)
actual_parent_maxdim = PB.maxlinkdim(parent.psi)
parent.maxlinkdim == actual_parent_maxdim || error(
    "parent maxlinkdim metadata $(parent.maxlinkdim) disagrees with psi ($actual_parent_maxdim)",
)
target_maxdim > actual_parent_maxdim || error(
    "TARGET_MAXDIM=$target_maxdim must exceed the parent maxlinkdim=$actual_parent_maxdim",
)
target_maxdim <= 256 || error(
    "TARGET_MAXDIM=$target_maxdim exceeds the guarded Phase 1 launcher ceiling of 256",
)

short_hash = first(expected_sha256, 12)
theta_label = PB.theta_label(parent.theta_over_pi)
experiment_label =
    "fixed_flux_$(theta_label)_chi$(actual_parent_maxdim)_to_chi$(target_maxdim)_$short_hash"
config_directory = length(ARGS) == 4 ? abspath(ARGS[4]) : joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_test_configs",
    experiment_label,
)
output_directory = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_tests",
    "yc8_1",
    experiment_label,
    "chi$target_maxdim",
)
config_path = joinpath(
    config_directory,
    "phase1_fixed_flux_expand_chi$target_maxdim.toml",
)
ispath(config_path) && error("refusing to overwrite generated configuration: $config_path")
mkpath(config_directory)

configuration = Dict{String,Any}(
    "model" => Dict{String,Any}(
        "circumference" => parent.circumference,
        "shift" => parent.shift,
        "mps_period" => parent.mps_period,
        "twist_gauge" => string(parent.twist_gauge),
        "J1" => parent.J1,
        "J2" => parent.J2,
        "Delta1" => parent.Delta1,
        "Delta2" => parent.Delta2,
        "Bz" => parent.Bz,
    ),
    "optimizer" => Dict{String,Any}(
        "maxdim" => target_maxdim,
        "cutoff" => 1e-10,
        "residual_tol" => 1e-5,
        "max_iterations" => 360,
        "max_growth_steps" => 16,
        "solver_tol_scale" => 100.0,
        "solver_tol_floor" => 1e-10,
        "solver_krylov_dimension" => 30,
        "solver_max_iterations" => 100,
        "record_krylov_diagnostics" => true,
        "multisite_update_alg" => "sequential",
        "require_converged" => true,
        "divergence_patience" => 8,
        "divergence_factor" => 4.0,
        # The preceding expansion run was stopped during a documented
        # nonmonotone transient. This controlled test intentionally leaves the
        # generic plateau stop off and retains the catastrophic-divergence and
        # nonfinite-residual guards.
        "plateau_detection" => false,
        "plateau_warmup_iterations" => 40,
        "plateau_patience" => 32,
        "plateau_min_relative_improvement" => 5e-3,
    ),
    "scan" => Dict{String,Any}(
        "branch" => parent.branch,
        "preparation" => parent.preparation,
        "direction" => string(parent.direction),
        "lineage_policy" => "strict",
        # Keeping theta exactly fixed separates bond-space initialization from
        # the later flux-continuation question.
        "fluxes_over_pi" => [parent.theta_over_pi],
        "seed_pattern" => parent.seed_pattern,
        "random_seed" => parent.random_seed,
        # The guarded launcher requires this Phase 1 invariant. The scan engine
        # handles a same-flux expansion before interval-refinement logic, so no
        # bisection is attempted and no zero-width bracket is reported.
        "adaptive_bisection" => true,
        "minimum_step_over_pi" => 1 / 256,
        "save_rejected" => true,
        "require_parent_overlap" => true,
        "minimum_parent_overlap_per_site" => 0.99,
        "parent_overlap_tolerance" => 1e-8,
        "parent_overlap_krylov_dimension" => 16,
        "initial_state_file" => parent_path,
        "initial_state_sha256" => expected_sha256,
    ),
    "spectrum" => Dict{String,Any}(
        "physical_sz_sectors" => [0.0, 1.0],
        "neigs" => 4,
        "tolerance" => 1e-8,
        "krylov_dimension" => 16,
        "random_seed" => parent.random_seed,
    ),
    "runtime" => Dict{String,Any}(
        "output_directory" => output_directory,
        "blas_threads" => 1,
        "strided_threads" => 1,
        "threaded_blocksparse" => true,
        "output_level" => 1,
    ),
)

open(config_path, "w") do io
    println(io, "# Fixed-flux Phase 1 bond-space expansion diagnostic")
    println(io, "# Immutable accepted parent: $parent_path")
    println(io, "# Parent SHA-256: $expected_sha256")
    println(io, "# Fixed theta/pi: $(parent.theta_over_pi)")
    println(io, "# Expansion: chi $actual_parent_maxdim -> $target_maxdim")
    println(io, "# Generic plateau termination is disabled; maximum outer iterations: 360")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println(
    "Generated one fixed-flux expansion test at theta/pi=$(parent.theta_over_pi): " *
    "chi $actual_parent_maxdim -> $target_maxdim",
)
println("The parent digest was verified and the destination is $output_directory")
println("Run only this generated configuration; do not submit the earlier step-and-expand control.")
