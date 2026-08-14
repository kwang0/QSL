#!/usr/bin/env julia

using TOML
using TriangularJ1J2ProjectB

4 <= length(ARGS) <= 5 || error(
    "usage: prepare_phase1_fixed_flux_resume.jl ACCEPTED_PARENT.h5 " *
    "PARENT_SHA256 OPTIMIZER_CHECKPOINT.h5 CHECKPOINT_SHA256 [CONFIG_DIRECTORY]",
)

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const ADDITIONAL_ITERATIONS = 180
const RESIDUAL_TOLERANCE = 1e-5

function verified_state(path_argument::AbstractString, digest_argument::AbstractString, label)
    path = abspath(path_argument)
    expected_sha256 = lowercase(digest_argument)
    occursin(r"^[0-9a-f]{64}$", expected_sha256) || error(
        "$label SHA-256 must contain 64 lowercase hexadecimal digits",
    )
    actual_sha256 = PB.file_sha256(path)
    actual_sha256 == expected_sha256 || error(
        "$label SHA-256 mismatch: expected $expected_sha256, got $actual_sha256",
    )
    return (; path, sha256=actual_sha256, state=PB.read_state_file(path))
end

parent_record = verified_state(ARGS[1], ARGS[2], "accepted parent")
checkpoint_record = verified_state(ARGS[3], ARGS[4], "optimizer checkpoint")
parent = parent_record.state
checkpoint = checkpoint_record.state

parent.schema_version >= 3 || error("accepted parent requires schema-v3 lineage")
parent.converged || error("accepted parent is not numerically converged")
parent.continuation_accepted || error("accepted parent was not accepted for continuation")
parent.circumference == 8 && parent.shift == 1 || error(
    "fixed-flux Phase 1 resume requires a YC8-1 accepted parent",
)
parent.mps_period == 2 || error("accepted parent must use the minimal two-site cell")
parent.branch == "primary_forward" || error(
    "fixed-flux Phase 1 resume requires the primary-forward branch",
)
parent.direction === :forward || error("accepted parent must be on the forward branch")
parent.twist_gauge === :uniform || error("accepted parent must use the uniform twist gauge")

checkpoint.schema_version >= 5 || error(
    "optimizer checkpoint must be a schema-v5-or-newer diagnostic state",
)
checkpoint.converged && error("optimizer checkpoint is already converged")
checkpoint.continuation_accepted && error(
    "optimizer checkpoint is already accepted; use it directly as a continuation parent",
)
checkpoint.optimizer_stop_reason == "maximum_iterations_contracting" || error(
    "optimizer checkpoint must have stop_reason=maximum_iterations_contracting; got " *
    checkpoint.optimizer_stop_reason,
)
checkpoint.optimizer_iterations >= 1 || error("optimizer checkpoint records no iterations")
isfinite(checkpoint.optimizer_residual) || error("optimizer checkpoint residual is non-finite")
checkpoint.optimizer_residual > RESIDUAL_TOLERANCE || error(
    "optimizer checkpoint already satisfies residual tolerance $RESIDUAL_TOLERANCE",
)
isfinite(checkpoint.optimizer_minimum_residual) || error(
    "optimizer checkpoint minimum residual is non-finite",
)

for field in (
    :circumference,
    :shift,
    :mps_period,
    :twist_gauge,
    :branch,
    :preparation,
    :direction,
    :random_seed,
    :seed_pattern,
    :J1,
    :J2,
    :Delta1,
    :Delta2,
    :Bz,
)
    getproperty(checkpoint, field) == getproperty(parent, field) || error(
        "checkpoint $field=$(getproperty(checkpoint, field)) differs from accepted parent " *
        "$(getproperty(parent, field))",
    )
end
isapprox(checkpoint.theta_over_pi, parent.theta_over_pi; atol=1e-12, rtol=0) || error(
    "checkpoint and accepted parent are at different fluxes",
)
checkpoint.parent_state_sha256 == parent_record.sha256 || error(
    "checkpoint does not name the supplied accepted-parent SHA-256",
)
isempty(checkpoint.parent_state_path) && error("checkpoint lacks accepted-parent path metadata")
basename(checkpoint.parent_state_path) == basename(parent_record.path) || error(
    "checkpoint accepted-parent basename does not match the supplied parent",
)
PB.flux_histories_match(
    checkpoint.flux_history_over_pi,
    parent.flux_history_over_pi,
) || error("checkpoint flux history differs from accepted-parent lineage")

parent_maxdim = PB.maxlinkdim(parent.psi)
parent.maxlinkdim == parent_maxdim || error("accepted-parent maxlinkdim metadata is inconsistent")
checkpoint_maxdim = PB.maxlinkdim(checkpoint.psi)
checkpoint.maxlinkdim == checkpoint_maxdim || error(
    "optimizer-checkpoint maxlinkdim metadata is inconsistent",
)
checkpoint.optimizer_requested_maxdim == checkpoint_maxdim || error(
    "optimizer checkpoint requested chi=$(checkpoint.optimizer_requested_maxdim), but its " *
    "MPS has chi=$checkpoint_maxdim",
)
checkpoint_maxdim > parent_maxdim || error(
    "optimizer checkpoint chi=$checkpoint_maxdim does not exceed accepted-parent chi=$parent_maxdim",
)
checkpoint_maxdim <= 256 || error(
    "optimizer checkpoint chi=$checkpoint_maxdim exceeds the guarded Phase 1 ceiling of 256",
)

prior_iterations = checkpoint.optimizer_checkpoint_iterations
prior_iterations >= 0 || error("checkpoint prior-iteration count is negative")
cumulative_checkpoint_iterations = prior_iterations + checkpoint.optimizer_iterations
short_hash = first(checkpoint_record.sha256, 12)
theta_label = PB.theta_label(parent.theta_over_pi)
experiment_label = "fixed_flux_resume_$(theta_label)_chi$(checkpoint_maxdim)_$short_hash"
config_directory = length(ARGS) == 5 ? abspath(ARGS[5]) : joinpath(
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
    "chi$checkpoint_maxdim",
)
config_path = joinpath(
    config_directory,
    "phase1_fixed_flux_resume_chi$checkpoint_maxdim.toml",
)
ispath(config_path) && error("refusing to overwrite generated configuration: $config_path")
ispath(output_directory) && error(
    "refusing to reuse fixed-flux resume output directory: $output_directory",
)

model = PB.ModelSettings(
    geometry=PB.YCGeometry(parent.circumference, parent.shift),
    J1=parent.J1,
    J2=parent.J2,
    Delta1=parent.Delta1,
    Delta2=parent.Delta2,
    Bz=parent.Bz,
    twist_gauge=parent.twist_gauge,
    mps_period=parent.mps_period,
)
optimizer = PB.OptimizerSettings(
    maxdim=checkpoint_maxdim,
    cutoff=1e-10,
    residual_tol=RESIDUAL_TOLERANCE,
    max_iterations=ADDITIONAL_ITERATIONS,
    max_growth_steps=16,
    solver_tol_scale=100.0,
    solver_tol_floor=1e-10,
    solver_krylov_dimension=30,
    solver_max_iterations=100,
    record_krylov_diagnostics=true,
    multisite_update_alg="sequential",
    require_converged=true,
    divergence_patience=8,
    divergence_factor=4.0,
    plateau_detection=false,
    plateau_warmup_iterations=40,
    plateau_patience=32,
    plateau_min_relative_improvement=5e-3,
)
scan = PB.ScanSettings(
    branch=parent.branch,
    preparation=parent.preparation,
    direction=parent.direction,
    lineage_policy=:strict,
    fluxes_over_pi=[parent.theta_over_pi],
    seed_pattern=parent.seed_pattern,
    random_seed=parent.random_seed,
    adaptive_bisection=true,
    minimum_step_over_pi=1 / 256,
    save_rejected=true,
    require_parent_overlap=true,
    minimum_parent_overlap_per_site=0.99,
    parent_overlap_tolerance=1e-8,
    parent_overlap_krylov_dimension=16,
    initial_state_file=parent_record.path,
    initial_state_sha256=parent_record.sha256,
    optimizer_checkpoint_file=checkpoint_record.path,
    optimizer_checkpoint_sha256=checkpoint_record.sha256,
)
spectrum = PB.SpectrumSettings(
    physical_sz_sectors=[0.0, 1.0],
    neigs=4,
    tolerance=1e-8,
    krylov_dimension=16,
    random_seed=parent.random_seed,
)
runtime = PB.RuntimeSettings(
    output_directory=output_directory,
    blas_threads=1,
    strided_threads=1,
    threaded_blocksparse=true,
    output_level=1,
)

# Exercise the full HDF5 lineage/checkpoint validator before creating a config.
validation_settings = PB.ProjectSettings(
    model=model,
    optimizer=optimizer,
    scan=scan,
    spectrum=spectrum,
    runtime=runtime,
    config_path=config_path,
    config_text="# pre-write fixed-flux optimizer-resume validation\n",
)
loaded = PB.load_or_build_initial_state(validation_settings)
loaded.parent_state_sha256 == parent_record.sha256 || error("accepted-parent validation failed")
loaded.optimizer_checkpoint_sha256 == checkpoint_record.sha256 || error(
    "optimizer-checkpoint validation failed",
)

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
        "maxdim" => optimizer.maxdim,
        "cutoff" => optimizer.cutoff,
        "residual_tol" => optimizer.residual_tol,
        "max_iterations" => optimizer.max_iterations,
        "max_growth_steps" => optimizer.max_growth_steps,
        "solver_tol_scale" => optimizer.solver_tol_scale,
        "solver_tol_floor" => optimizer.solver_tol_floor,
        "solver_krylov_dimension" => optimizer.solver_krylov_dimension,
        "solver_max_iterations" => optimizer.solver_max_iterations,
        "record_krylov_diagnostics" => optimizer.record_krylov_diagnostics,
        "multisite_update_alg" => optimizer.multisite_update_alg,
        "require_converged" => optimizer.require_converged,
        "divergence_patience" => optimizer.divergence_patience,
        "divergence_factor" => optimizer.divergence_factor,
        "plateau_detection" => optimizer.plateau_detection,
        "plateau_warmup_iterations" => optimizer.plateau_warmup_iterations,
        "plateau_patience" => optimizer.plateau_patience,
        "plateau_min_relative_improvement" =>
            optimizer.plateau_min_relative_improvement,
    ),
    "scan" => Dict{String,Any}(
        "branch" => scan.branch,
        "preparation" => scan.preparation,
        "direction" => string(scan.direction),
        "lineage_policy" => string(scan.lineage_policy),
        "fluxes_over_pi" => scan.fluxes_over_pi,
        "seed_pattern" => scan.seed_pattern,
        "random_seed" => scan.random_seed,
        "adaptive_bisection" => scan.adaptive_bisection,
        "minimum_step_over_pi" => scan.minimum_step_over_pi,
        "save_rejected" => scan.save_rejected,
        "require_parent_overlap" => scan.require_parent_overlap,
        "minimum_parent_overlap_per_site" => scan.minimum_parent_overlap_per_site,
        "parent_overlap_tolerance" => scan.parent_overlap_tolerance,
        "parent_overlap_krylov_dimension" => scan.parent_overlap_krylov_dimension,
        "initial_state_file" => parent_record.path,
        "initial_state_sha256" => parent_record.sha256,
        "optimizer_checkpoint_file" => checkpoint_record.path,
        "optimizer_checkpoint_sha256" => checkpoint_record.sha256,
    ),
    "spectrum" => Dict{String,Any}(
        "physical_sz_sectors" => spectrum.physical_sz_sectors,
        "neigs" => spectrum.neigs,
        "tolerance" => spectrum.tolerance,
        "krylov_dimension" => spectrum.krylov_dimension,
        "random_seed" => spectrum.random_seed,
    ),
    "runtime" => Dict{String,Any}(
        "output_directory" => output_directory,
        "blas_threads" => runtime.blas_threads,
        "strided_threads" => runtime.strided_threads,
        "threaded_blocksparse" => runtime.threaded_blocksparse,
        "output_level" => runtime.output_level,
    ),
)

mkpath(config_directory)
open(config_path, "w") do io
    println(io, "# Isolated fixed-flux continuation of a contracting VUMPS checkpoint")
    println(io, "# Accepted lineage parent: $(parent_record.path)")
    println(io, "# Accepted parent SHA-256: $(parent_record.sha256)")
    println(io, "# Numerical optimizer seed only: $(checkpoint_record.path)")
    println(io, "# Optimizer checkpoint SHA-256: $(checkpoint_record.sha256)")
    println(io, "# Fixed theta/pi: $(parent.theta_over_pi)")
    println(io, "# Prior outer iterations through checkpoint: $cumulative_checkpoint_iterations")
    println(io, "# Additional outer-iteration cap: $ADDITIONAL_ITERATIONS")
    println(io, "# The rejected checkpoint is not promoted to accepted branch lineage.")
    TOML.print(io, configuration; sorted=true)
end

println(config_path)
println(
    "Generated one fixed-flux chi=$checkpoint_maxdim optimizer resume at " *
    "theta/pi=$(parent.theta_over_pi)",
)
println(
    "The accepted parent and rejected checkpoint digests were verified; the checkpoint " *
    "contributes $cumulative_checkpoint_iterations prior iterations and the new cap is " *
    "$ADDITIONAL_ITERATIONS.",
)
println("Run only this generated configuration, inspect it with plan, and submit it once.")
