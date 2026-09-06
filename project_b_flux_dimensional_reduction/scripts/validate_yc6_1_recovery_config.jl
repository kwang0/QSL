using SHA
using TOML
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const SUPPORTED_RESIDUAL_TOLERANCES = (1e-5, 1e-4)

length(ARGS) == 1 || error("usage: validate_yc6_1_recovery_config.jl CONFIG.toml")

config_path = abspath(only(ARGS))
settings = load_settings(config_path)
raw = TOML.parsefile(config_path)

expected_fluxes = Float64.(0:10) ./ 10
expected_output_root = normpath(joinpath(@__DIR__, "..", "output", "science", "yc6_1"))

settings.model.geometry == YCGeometry(6, 1) || error("recovery requires YC6-1")
model_mps_period(settings.model) == 6 || error("recovery requires the legacy six-site MPS supercell")
settings.model.twist_gauge === :uniform || error("recovery requires the uniform twist gauge")
settings.model.J1 == 1.0 || error("unexpected J1")
settings.model.J2 == 0.12 || error("unexpected J2")
settings.model.Delta1 == 1.0 || error("unexpected Delta1")
settings.model.Delta2 == 1.0 || error("unexpected Delta2")
settings.model.Bz == 0.0 || error("unexpected Bz")

optimizer = settings.optimizer
optimizer.maxdim == 512 || error("recovery requires chi=512")
optimizer.cutoff == 1e-10 || error("unexpected cutoff")
optimizer.residual_tol in SUPPORTED_RESIDUAL_TOLERANCES || error(
    "the YC6-1 recovery VUMPS target must be one of " *
    "$(SUPPORTED_RESIDUAL_TOLERANCES)",
)
optimizer.max_iterations == 60 || error("the recovery outer-iteration cap must remain 60")
optimizer.max_growth_steps == 20 || error("unexpected growth-stage cap")
optimizer.solver_tol_scale == 100.0 || error("unexpected solver tolerance scale")
optimizer.solver_tol_floor == 1e-10 || error("unexpected solver tolerance floor")
optimizer.solver_krylov_dimension == 30 || error("unexpected solver Krylov dimension")
optimizer.solver_max_iterations == 100 || error("unexpected solver iteration cap")
optimizer.record_krylov_diagnostics || error("inner Krylov diagnostics must be recorded")
optimizer.multisite_update_alg == "sequential" || error("recovery requires sequential VUMPS")
!optimizer.restore_best_on_failure || error("rejected terminal iterates must not be silently replaced")
optimizer.require_converged || error("recovery requires numerical convergence")
optimizer.divergence_patience == 8 || error("unexpected divergence patience")
optimizer.divergence_factor == 4.0 || error("unexpected divergence factor")
optimizer.plateau_detection || error("recovery requires plateau detection")
optimizer.plateau_warmup_iterations == 40 || error("unexpected plateau warmup")
optimizer.plateau_patience == 24 || error("unexpected plateau window")
optimizer.plateau_min_relative_improvement == 0.005 || error("unexpected plateau threshold")

scan = settings.scan
scan.branch == "yc6_1_legacy_period6_recovery_chi512" || error("unexpected branch")
scan.preparation == "independent_theta0_legacy_period6_alternating" || error("unexpected preparation")
scan.direction === :forward || error("recovery must run forward")
scan.lineage_policy === :strict || error("recovery requires strict lineage")
scan.seed_pattern == "alternating" || error("recovery requires the legacy alternating seed")
scan.random_seed == 1 || error("unexpected random seed")
scan.adaptive_bisection || error("recovery requires adaptive bisection")
scan.minimum_step_over_pi == 0.00625 || error("unexpected bisection floor")
scan.save_rejected || error("rejected candidates must be immutable")
scan.require_parent_overlap || error("parent overlap must be evaluated")
scan.minimum_parent_overlap_per_site == 0.90 || error("unexpected broad continuity floor")
scan.parent_overlap_tolerance == 1e-8 || error("unexpected overlap tolerance")
scan.parent_overlap_krylov_dimension == 16 || error("unexpected overlap Krylov dimension")

startup_source = if scan.optimizer_checkpoint_file !== nothing
    length(scan.fluxes_over_pi) == 1 || error(
        "an optimizer-checkpoint resume must target exactly one theta/pi",
    )
    PB.load_or_build_initial_state(settings)
    "optimizer_checkpoint"
elseif scan.initial_state_file !== nothing
    initial = PB.load_or_build_initial_state(settings)
    initial.initial_theta === nothing && error("accepted-parent restart lacks parent theta/pi")
    first(scan.fluxes_over_pi) > initial.initial_theta || error(
        "accepted-parent YC6-1 continuation must advance beyond its parent",
    )
    "accepted_parent"
else
    scan.initial_state_sha256 === nothing || error(
        "an independent root cannot name an initial-state SHA-256",
    )
    scan.optimizer_checkpoint_sha256 === nothing || error(
        "an independent root cannot name an optimizer-checkpoint SHA-256",
    )
    scan.fluxes_over_pi == expected_fluxes || error(
        "an independent recovery root requires the complete 0.1-pi nominal grid",
    )
    "independent_root"
end

settings.spectrum.physical_sz_sectors == [0.0, 1.0] || error("both neutral and physical-Sz=1 sectors are required")
settings.runtime.blas_threads == 1 || error("BLAS must remain serial")
settings.runtime.strided_threads == 1 || error("Strided contractions must remain serial")
settings.runtime.threaded_blocksparse || error("threaded block-sparse contractions must remain enabled")
if startup_source == "independent_root"
    settings.runtime.optimizer_checkpoint_every_iterations in (0, 5) || error(
        "independent recovery checkpoint cadence must be zero (historical) or five",
    )
else
    settings.runtime.optimizer_checkpoint_every_iterations == 5 || error(
        "YC6-1 continuation and checkpoint-resume jobs require a five-iteration checkpoint cadence",
    )
end
startswith(settings.runtime.output_directory, expected_output_root * Base.Filesystem.path_separator) ||
    error("recovery output must remain under $expected_output_root")
if optimizer.residual_tol == 1e-4
    occursin("tol1e4", settings.runtime.output_directory) || error(
        "the exploratory 1e-4 profile requires a distinct tol1e4 output tree",
    )
end

config_sha256 = open(config_path, "r") do io
    bytes2hex(sha256(io))
end

println(join((
    config_sha256,
    settings.runtime.output_directory,
    scan.branch,
    scan.preparation,
    optimizer.maxdim,
    optimizer.residual_tol,
    optimizer.max_iterations,
    join(scan.fluxes_over_pi, ","),
    scan.minimum_step_over_pi,
    scan.minimum_parent_overlap_per_site,
    startup_source,
    settings.runtime.optimizer_checkpoint_every_iterations,
), '\t'))
