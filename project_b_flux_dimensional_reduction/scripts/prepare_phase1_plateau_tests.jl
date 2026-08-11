#!/usr/bin/env julia

using TOML
using TriangularJ1J2ProjectB

3 <= length(ARGS) <= 4 || error(
    "usage: prepare_phase1_plateau_tests.jl PARENT_STATE.h5 PARENT_SHA256 " *
    "TARGET_THETA_OVER_PI [CONFIG_DIRECTORY]",
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

target_theta = try
    parse(Float64, ARGS[3])
catch
    error("TARGET_THETA_OVER_PI must be a finite decimal")
end
isfinite(target_theta) || error("TARGET_THETA_OVER_PI must be finite")

parent = PB.read_state_file(parent_path)
parent.converged || error("parent state is not numerically converged")
parent.continuation_accepted || error("parent state was not accepted for continuation")
parent.circumference == 8 && parent.shift == 1 || error("tests require a YC8-1 parent")
parent.mps_period == 2 || error("tests require the minimal two-site YC8-1 MPS cell")
parent.branch == "primary_forward" || error("tests require the primary-forward branch")
parent.direction === :forward || error("tests require a forward parent")
parent.theta_over_pi < target_theta <= 1.0 || error(
    "target must lie ahead of parent theta/pi=$(parent.theta_over_pi) and at or below 1.0",
)
actual_parent_chi = PB.maxlinkdim(parent.psi)
parent.maxlinkdim == actual_parent_chi || error(
    "parent maxlinkdim metadata $(parent.maxlinkdim) disagrees with psi ($actual_parent_chi)",
)
actual_parent_chi == 128 || error("tests require an accepted chi=128 parent")

short_hash = first(expected_sha256, 12)
parent_label = PB.theta_label(parent.theta_over_pi)
target_label = PB.theta_label(target_theta)
experiment_label = "from_$(parent_label)_to_$(target_label)_$short_hash"
config_directory = length(ARGS) == 4 ? abspath(ARGS[4]) : joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_test_configs",
    experiment_label,
)
output_root = joinpath(
    PROJECT_ROOT,
    "output",
    "phase1_tests",
    "yc8_1",
    experiment_label,
)
mkpath(config_directory)

function make_config(
    name::String,
    maxdim::Int;
    solver_tol_scale::Float64=100.0,
    solver_tol_floor::Float64=1e-10,
    solver_krylov_dimension::Int=30,
)
    return Dict{String,Any}(
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
            "maxdim" => maxdim,
            "cutoff" => 1e-10,
            "residual_tol" => 1e-5,
            "max_iterations" => 360,
            "max_growth_steps" => 16,
            "solver_tol_scale" => solver_tol_scale,
            "solver_tol_floor" => solver_tol_floor,
            "solver_krylov_dimension" => solver_krylov_dimension,
            "solver_max_iterations" => 100,
            "record_krylov_diagnostics" => true,
            "multisite_update_alg" => "sequential",
            "require_converged" => true,
            "divergence_patience" => 8,
            "divergence_factor" => 4.0,
            "plateau_detection" => true,
            "plateau_warmup_iterations" => 40,
            "plateau_patience" => 32,
            "plateau_min_relative_improvement" => 5e-3,
        ),
        "scan" => Dict{String,Any}(
            "branch" => parent.branch,
            "preparation" => parent.preparation,
            "direction" => string(parent.direction),
            "lineage_policy" => "strict",
            "fluxes_over_pi" => [target_theta],
            "seed_pattern" => parent.seed_pattern,
            "random_seed" => parent.random_seed,
            "adaptive_bisection" => true,
            # Equal to the requested interval so this remains a controlled
            # one-point test instead of silently adding another variable.
            "minimum_step_over_pi" => target_theta - parent.theta_over_pi,
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
            "output_directory" => joinpath(output_root, name, "chi$maxdim"),
            "blas_threads" => 1,
            "strided_threads" => 1,
            "threaded_blocksparse" => true,
            "output_level" => 1,
        ),
    )
end

specifications = [
    (
        filename="phase1_plateau_baseline_chi128.toml",
        name="baseline_recorded",
        maxdim=128,
        solver_tol_scale=100.0,
        solver_tol_floor=1e-10,
        solver_krylov_dimension=30,
    ),
    (
        filename="phase1_plateau_inner_krylov_chi128.toml",
        name="tight_inner_krylov",
        maxdim=128,
        solver_tol_scale=1000.0,
        solver_tol_floor=1e-12,
        solver_krylov_dimension=64,
    ),
    (
        filename="phase1_plateau_expand_chi192.toml",
        name="bond_expansion",
        maxdim=192,
        solver_tol_scale=100.0,
        solver_tol_floor=1e-10,
        solver_krylov_dimension=30,
    ),
    (
        filename="phase1_plateau_expand_chi256.toml",
        name="bond_expansion",
        maxdim=256,
        solver_tol_scale=100.0,
        solver_tol_floor=1e-10,
        solver_krylov_dimension=30,
    ),
]

for specification in specifications
    path = joinpath(config_directory, specification.filename)
    ispath(path) && error("refusing to overwrite generated configuration: $path")
    open(path, "w") do io
        println(io, "# Generated from immutable accepted parent $parent_path")
        println(io, "# Parent SHA-256: $expected_sha256")
        println(io, "# Controlled target theta/pi: $target_theta")
        TOML.print(
            io,
            make_config(
                specification.name,
                specification.maxdim;
                solver_tol_scale=specification.solver_tol_scale,
                solver_tol_floor=specification.solver_tol_floor,
                solver_krylov_dimension=specification.solver_krylov_dimension,
            );
            sorted=true,
        )
    end
    println(path)
end

println("Generated four isolated tests from parent $parent_path to theta/pi=$target_theta")
println("Run the recorded baseline first and reconcile it before considering a control.")
