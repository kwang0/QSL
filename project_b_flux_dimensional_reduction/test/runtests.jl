using HDF5
using ITensors
using Test
using TOML
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))

@testset "Phase 1 orchestration scripts parse" begin
    for relative_path in (
        joinpath("scripts", "prepare_phase1_automatic_advance.jl"),
        joinpath("scripts", "prepare_phase1_chi512_parallel_continuation.jl"),
        joinpath("scripts", "prepare_phase1_idmrg_control.jl"),
        joinpath("scripts", "prepare_phase1_idmrg_resume.jl"),
        joinpath("scripts", "analyze_phase1_idmrg_result.jl"),
        joinpath("scripts", "make_phase1_idmrg_lightweight.jl"),
        joinpath("scripts", "archive_phase1_idmrg_checkpoints.jl"),
        joinpath("scripts", "prepare_phase1_idmrg_benchmark.jl"),
        joinpath("scripts", "analyze_phase1_idmrg_benchmark.jl"),
        joinpath("scripts", "validate_yc6_1_recovery_config.jl"),
        joinpath("scripts", "validate_yc8_1_chi1024_bridge_config.jl"),
        joinpath("scripts", "prepare_yc8_1_chi1024_reverse_check.jl"),
        joinpath("scripts", "analyze_yc8_1_chi1024_forward_reverse.jl"),
        joinpath("scripts", "prepare_yc8_1_chi1024_full_sweep.jl"),
        joinpath("idmrg", "scripts", "run_idmrg.jl"),
        joinpath("idmrg", "scripts", "validate_control.jl"),
        joinpath("idmrg", "scripts", "run_benchmark.jl"),
        joinpath("idmrg", "scripts", "validate_benchmark_control.jl"),
    )
        code = read(joinpath(PROJECT_ROOT, relative_path), String)
        position = 1
        parsed = true
        while true
            expression, position = Meta.parse(code, position; greedy=true, raise=false)
            expression === nothing && break
            if expression isa Expr && expression.head === :error
                parsed = false
                break
            end
        end
        @test parsed
    end

    yc6_launcher = read(
        joinpath(PROJECT_ROOT, "slurm", "run_yc6_1_recovery_cpu.sh"),
        String,
    )
    yc6_worker = read(
        joinpath(PROJECT_ROOT, "slurm", "run_yc6_1_recovery_job.sh"),
        String,
    )
    @test occursin("--signal=\"B:USR1@\$PRETIMEOUT_SIGNAL_SECONDS\"", yc6_launcher)
    @test occursin("--licenses=scratch", yc6_launcher)
    @test occursin("trap handle_pretimeout USR1", yc6_worker)
    @test occursin("PROJECT_B_PRETIMEOUT_REQUEST_FILE", yc6_worker)
    @test occursin("PROJECT_B_OPTIMIZER_CHECKPOINT_DIRECTORY", yc6_worker)
    yc8_launcher = read(
        joinpath(PROJECT_ROOT, "slurm", "run_yc8_1_chi1024_bridge_cpu.sh"),
        String,
    )
    yc8_worker = read(
        joinpath(PROJECT_ROOT, "slurm", "run_yc8_1_chi1024_bridge_job.sh"),
        String,
    )
    @test occursin("--signal=\"B:USR1@\$PRETIMEOUT_SIGNAL_SECONDS\"", yc8_launcher)
    @test occursin("--licenses=scratch", yc8_launcher)
    @test occursin("reconciled_yc8_charge", yc8_launcher)
    @test occursin("prior YC8 run is not reconciled", yc8_launcher)
    @test occursin("readonly SOLVER_STEP_CPUS=8", yc8_launcher)
    @test occursin("readonly JULIA_THREADS=4", yc8_launcher)
    @test occursin("readonly SOLVER_STEP_CPUS=8", yc8_worker)
    @test occursin("readonly JULIA_THREADS=4", yc8_worker)
    @test occursin("--cpus-per-task=\"\$SOLVER_STEP_CPUS\"", yc8_worker)
    @test occursin("JULIA_NUM_THREADS=\"\$JULIA_THREADS\"", yc8_worker)
    @test occursin("PROJECT_B_STATE_OUTPUT_DIRECTORY", yc8_worker)
    @test occursin("PROJECT_B_OPTIMIZER_CHECKPOINT_DIRECTORY", yc8_worker)
    @test occursin("forward_full_sweep", read(
        joinpath(PROJECT_ROOT, "scripts", "validate_yc8_1_chi1024_bridge_config.jl"),
        String,
    ))
end

include("test_idmrg_native_analysis.jl")

@testset "iDMRG Hermitian fixed-point phase alignment" begin
    for phase in (2.6336300971705697e-9, 0.37, -1.11)
        raw_factor = cis(phase)
        overlap = conj(raw_factor)^2
        alignment = PB._hermitian_phase_factor(overlap)
        aligned_factor = alignment * raw_factor
        @test isapprox(abs(alignment), 1.0; atol=1e-15, rtol=0)
        @test isapprox(imag(aligned_factor), 0.0; atol=1e-14, rtol=0)
        @test isapprox(abs(real(aligned_factor)), 1.0; atol=1e-14, rtol=0)
    end
    @test_throws ErrorException PB._hermitian_phase_factor(0.0 + 0.0im)
end

@testset "Phase 1 iDMRG target bond table" begin
    geometry = YCGeometry(8, 1)
    bonds = unit_cell_bonds(geometry; period=2)
    @test length(bonds) == 12
    @test [bond.source_site for bond in bonds] == [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2]
    @test [bond.target_site for bond in bonds] == [2, 9, 8, 10, 7, 16, 3, 10, 9, 11, 8, 17]
    @test [bond_twist_charge(bond, geometry, :uniform) for bond in bonds] ==
        [1 / 8, 0, -1 / 8, 1 / 8, -1 / 4, -1 / 8,
         1 / 8, 0, -1 / 8, 1 / 8, -1 / 4, -1 / 8]
end

@testset "YC geometry and twist seam" begin
    g = YCGeometry(6, 1)
    @test string(g) == "YC6-1"
    @test minimal_mps_period(g) == 2
    @test PB.validate_bond_table(g)
    @test length(unit_cell_bonds(g)) == 12
    @test count(bond -> bond.family === :NN, unit_cell_bonds(g)) == 6
    @test count(bond -> bond.family === :NNN, unit_cell_bonds(g)) == 6
    @test length(unit_cell_bonds(g; period=6)) == 36
    for source in 1:2
        source_bonds = filter(
            bond -> mod1(PB.snake_site_index(bond.row, bond.col, g), 2) == source,
            unit_cell_bonds(g),
        )
        nn_offsets = sort([
            bond.target_site - bond.source_site for bond in source_bonds if bond.family === :NN
        ])
        nnn_offsets = sort([
            bond.target_site - bond.source_site for bond in source_bonds if bond.family === :NNN
        ])
        @test nn_offsets == sort([1, 5, 6])
        @test nnn_offsets == sort([4, 7, 11])
    end
    @test wrap_endpoint(5, 0, 1, 0, g) == (row=0, col=1, winding=1)
    @test wrap_endpoint(0, 0, -1, 1, g) == (row=5, col=0, winding=-1)
    @test cylinder_class(g) === :two_flavor
    @test expected_gapless_flavors(g) == 2
    @test predicted_crossing_over_pi(g) == 1.0

    even_even = YCGeometry(8, 0)
    @test minimal_mps_period(even_even) == 8
    @test minimal_mps_period(YCGeometry(8, 1)) == 2
    @test minimal_mps_period(YCGeometry(7, 0)) == 14
    @test PB.validate_mps_period(YCGeometry(8, 1), 8)
    @test_throws ArgumentError PB.validate_mps_period(YCGeometry(8, 1), 3)
    @test cylinder_class(even_even) === :four_flavor
    @test expected_gapless_flavors(even_even) == 4
    @test predicted_crossing_over_pi(even_even) == 2.0
    @test 2.0 in recommended_flux_schedule(even_even)
    uniform_bond = only(filter(bond -> bond.family === :NN && bond.drow == 1,
        unit_cell_bonds(even_even))[1:1])
    @test bond_twist_charge(uniform_bond, even_even, :uniform) == 1 / 8
end

@testset "Hu momentum mappings" begin
    yc8_1 = momentum_from_minimal_phase(YCGeometry(8, 1), 0.0, pi)
    @test isapprox(yc8_1.k1, pi / 8; atol=1e-12)
    @test isapprox(yc8_1.k1_secondary, -7pi / 8; atol=1e-12)
    @test isapprox(yc8_1.two_k1, pi / 4; atol=1e-12)
    @test iszero(yc8_1.k2)

    yc8_0 = momentum_from_minimal_phase(
        YCGeometry(8, 0),
        -pi / 5,
        pi;
        canonical_k1=pi / 3,
    )
    @test isapprox(yc8_0.k1, 11pi / 24; atol=1e-12)
    @test isapprox(yc8_0.k2, -pi / 5; atol=1e-12)

    virtual = Index(2, "Link")
    translated_virtual = prime(virtual)
    fixed_point = ITensor(ComplexF64, virtual, translated_virtual)
    fixed_point[virtual => 1, translated_virtual => 1] = 1.0
    fixed_point[virtual => 2, translated_virtual => 2] = 1.0im
    signature = PB.schmidt_translation_signature(fixed_point)
    @test isapprox(signature.diagonal_weight, 1.0; atol=1e-12)
    mode_tensor = ITensor(virtual, translated_virtual)
    mode_tensor[virtual => 2, translated_virtual => 1] = 1.0
    mode = PB.mode_transverse_phase(mode_tensor, signature)
    @test mode.resolved
    @test isapprox(mode.canonical_k1, pi / 2; atol=1e-12)
end

@testset "Configuration and seed validation" begin
    settings = load_settings(joinpath(PROJECT_ROOT, "configs", "pilot_yc6_1.toml"))
    @test settings.model.geometry.circumference == 6
    @test settings.model.geometry.shift == 1
    @test settings.optimizer.require_converged
    @test settings.optimizer.multisite_update_alg == "sequential"
    @test !settings.optimizer.restore_best_on_failure
    @test settings.spectrum.physical_sz_sectors == [0.0, 1.0]
    @test settings.scan.direction === :forward
    @test settings.scan.preparation == "default"
    @test settings.scan.lineage_policy === :compatible
    @test isabspath(settings.runtime.output_directory)
    @test PB.validate_flux_order(settings.scan.fluxes_over_pi)
    @test_throws ArgumentError PB.validate_flux_order([0.0, 0.5, 0.25])
    @test_throws ArgumentError PB.validate_flux_order([0.0, 0.0])
    @test count(==("Up"), PB.balanced_seed_states(6, "block", 1)) == 3
    @test_throws ArgumentError PB.balanced_seed_states(5, "alternating", 1)

    phase1_specs = [
        ("phase1_yc8_1_forward_chi128.toml", 1, :forward, [0.0, 0.5, 0.75, 0.875, 1.0]),
        ("phase1_yc8_1_reverse_chi128.toml", 1, :reverse, [1.0, 0.875, 0.75, 0.5, 0.0]),
        ("phase1_yc8_0_forward_chi128.toml", 0, :forward, [0.0, 1.0, 1.5, 1.75, 2.0]),
        ("phase1_yc8_0_reverse_chi128.toml", 0, :reverse, [2.0, 1.75, 1.5, 1.0, 0.0]),
    ]
    for (filename, shift, direction, fluxes) in phase1_specs
        phase1 = load_settings(joinpath(PROJECT_ROOT, "configs", filename))
        @test phase1.model.geometry == YCGeometry(8, shift)
        @test model_mps_period(phase1.model) == (shift == 0 ? 8 : 2)
        @test phase1.optimizer.maxdim == 128
        @test phase1.optimizer.residual_tol == 1e-5
        @test phase1.optimizer.solver_krylov_dimension == 30
        @test phase1.optimizer.solver_max_iterations == 100
        @test !phase1.optimizer.record_krylov_diagnostics
        @test !phase1.optimizer.plateau_detection
        @test phase1.scan.direction === direction
        @test phase1.scan.lineage_policy === :strict
        @test phase1.scan.fluxes_over_pi == fluxes
        @test phase1.scan.require_parent_overlap
        @test phase1.scan.minimum_parent_overlap_per_site == 0.99
        @test phase1.scan.parent_overlap_tolerance == 1e-8
        @test phase1.scan.parent_overlap_krylov_dimension == 16
        @test phase1.runtime.threaded_blocksparse
        @test phase1.runtime.blas_threads == 1
        @test phase1.runtime.strided_threads == 1
        state_path = PB.state_file_path(phase1, 1, first(fluxes), true)
        @test occursin(lowercase(string(phase1.model.geometry)), state_path)
        @test occursin(PB.sanitize_label(phase1.scan.preparation), state_path)
        @test occursin(string(direction), state_path)
        @test occursin("seed$(phase1.scan.random_seed)", state_path)
        @test occursin("chi128", state_path)
        scratch_state_directory = joinpath(tempdir(), "project-b-state-routing-test")
        withenv("PROJECT_B_STATE_OUTPUT_DIRECTORY" => scratch_state_directory) do
            routed = PB.state_file_path(phase1, 1, first(fluxes), true)
            @test dirname(routed) == scratch_state_directory
        end
    end
    chi512 = load_settings(joinpath(
        PROJECT_ROOT,
        "configs",
        "phase1_yc8_1_forward_chi512_legacy_0p1.toml",
    ))
    @test chi512.model.geometry == YCGeometry(8, 1)
    @test model_mps_period(chi512.model) == 2
    @test chi512.optimizer.maxdim == 512
    @test chi512.optimizer.residual_tol == 1e-5
    @test chi512.optimizer.max_iterations == 180
    @test chi512.optimizer.max_growth_steps == 20
    @test chi512.optimizer.record_krylov_diagnostics
    @test chi512.optimizer.multisite_update_alg == "sequential"
    @test !chi512.optimizer.restore_best_on_failure
    @test chi512.optimizer.plateau_detection
    @test chi512.optimizer.plateau_warmup_iterations == 40
    @test chi512.optimizer.plateau_patience == 32
    @test chi512.scan.branch == "primary_forward_chi512_legacy_0p1"
    @test chi512.scan.preparation == "independent_theta0_alternating_chi512"
    @test chi512.scan.direction === :forward
    @test chi512.scan.fluxes_over_pi == Float64.(0:10) ./ 10
    @test chi512.scan.minimum_step_over_pi == 0.1
    @test chi512.scan.require_parent_overlap
    @test chi512.scan.minimum_parent_overlap_per_site == 0.99
    @test chi512.runtime.threaded_blocksparse
    @test occursin("chi512", chi512.runtime.output_directory)
    yc6_recovery = load_settings(joinpath(
        PROJECT_ROOT,
        "configs",
        "science_yc6_1_legacy_period6_chi512.toml",
    ))
    @test yc6_recovery.model.geometry == YCGeometry(6, 1)
    @test model_mps_period(yc6_recovery.model) == 6
    @test yc6_recovery.optimizer.maxdim == 512
    @test yc6_recovery.optimizer.residual_tol == 1e-5
    @test yc6_recovery.optimizer.max_iterations == 60
    @test yc6_recovery.optimizer.record_krylov_diagnostics
    @test yc6_recovery.optimizer.multisite_update_alg == "sequential"
    @test !yc6_recovery.optimizer.restore_best_on_failure
    @test yc6_recovery.optimizer.plateau_detection
    @test yc6_recovery.scan.branch == "yc6_1_legacy_period6_recovery_chi512"
    @test yc6_recovery.scan.preparation ==
        "independent_theta0_legacy_period6_alternating"
    @test yc6_recovery.scan.lineage_policy === :strict
    @test yc6_recovery.scan.fluxes_over_pi == Float64.(0:10) ./ 10
    @test yc6_recovery.scan.minimum_step_over_pi == 0.00625
    @test yc6_recovery.scan.require_parent_overlap
    @test yc6_recovery.scan.minimum_parent_overlap_per_site == 0.90
    @test yc6_recovery.runtime.threaded_blocksparse
    @test yc6_recovery.runtime.optimizer_checkpoint_every_iterations == 0
    yc6_continuation = load_settings(joinpath(
        PROJECT_ROOT,
        "configs",
        "science_yc6_1_legacy_period6_chi512_after_57629467.toml",
    ))
    @test yc6_continuation.scan.fluxes_over_pi ==
        [0.35, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    @test yc6_continuation.scan.initial_state_sha256 ==
        "741261e9fdef75b3793837f2b26f3daac4515c491baab622fc1e8d1e2c8bfe45"
    @test yc6_continuation.scan.optimizer_checkpoint_file === nothing
    @test yc6_continuation.runtime.optimizer_checkpoint_every_iterations == 5
    @test occursin(
        "legacy_period6_recovery_after_57629467",
        yc6_continuation.runtime.output_directory,
    )
    yc6_relaxed = load_settings(joinpath(
        PROJECT_ROOT,
        "configs",
        "science_yc6_1_legacy_period6_chi512_tol1e4_after_p0p3375.toml",
    ))
    @test yc6_relaxed.optimizer.residual_tol == 1e-4
    @test yc6_relaxed.optimizer.max_iterations == 60
    @test yc6_relaxed.scan.fluxes_over_pi ==
        [0.35, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    @test yc6_relaxed.scan.initial_state_sha256 ==
        "ac239341c6b4103e4bbeae2a2468d4fd9253d5db1fbbd0d6d7b5448f9e85234b"
    @test yc6_relaxed.scan.optimizer_checkpoint_file === nothing
    @test yc6_relaxed.runtime.optimizer_checkpoint_every_iterations == 5
    @test occursin("tol1e4", yc6_relaxed.runtime.output_directory)
    yc8_chi1024 = load_settings(joinpath(
        PROJECT_ROOT,
        "configs",
        "science_yc8_1_primary_forward_chi1024_bridge.toml",
    ))
    @test yc8_chi1024.model.geometry == YCGeometry(8, 1)
    @test model_mps_period(yc8_chi1024.model) == 2
    @test yc8_chi1024.optimizer.maxdim == 1024
    @test yc8_chi1024.optimizer.residual_tol == 1e-4
    @test yc8_chi1024.optimizer.multisite_update_alg == "parallel"
    @test yc8_chi1024.optimizer.restore_best_on_failure
    @test yc8_chi1024.scan.fluxes_over_pi == collect(0.15:0.025:0.45)
    @test yc8_chi1024.scan.continuity_policy === :multimetric_trust_region
    @test yc8_chi1024.scan.minimum_parent_overlap_per_site == 0.90
    @test yc8_chi1024.scan.maximum_cut_entropy_jump == 0.10
    @test yc8_chi1024.scan.fixed_flux_growth_maximum_cut_entropy_jump == 0.35
    @test yc8_chi1024.scan.maximum_energy_term_rms_jump == 0.02
    @test yc8_chi1024.scan.maximum_magnetization_rms_jump == 0.001
    @test yc8_chi1024.scan.maximum_mean_schmidt_total_variation == 0.05
    @test yc8_chi1024.scan.fixed_flux_growth_maximum_mean_schmidt_total_variation == 0.15
    @test yc8_chi1024.scan.require_correlation_length_diagnostics
    @test yc8_chi1024.scan.correlation_length_physical_sz_sectors == [0.0, 1.0]
    @test yc8_chi1024.scan.correlation_length_tolerance == 1e-8
    @test yc8_chi1024.scan.correlation_length_krylov_dimension == 32
    @test yc8_chi1024.scan.maximum_log_correlation_length_jump == 0.05
    @test yc8_chi1024.scan.fixed_flux_growth_maximum_log_correlation_length_jump == 1.0
    @test yc8_chi1024.scan.require_u1_sector_diagnostics
    @test yc8_chi1024.runtime.optimizer_checkpoint_every_iterations == 2
    recovery = load_settings(joinpath(
        PROJECT_ROOT,
        "configs",
        "phase1_yc8_1_forward_recovery_from_0p21875_chi128.toml",
    ))
    @test recovery.scan.branch == "primary_forward"
    @test recovery.scan.preparation == "independent_theta0_alternating"
    @test recovery.scan.direction === :forward
    @test recovery.scan.lineage_policy === :strict
    @test recovery.scan.random_seed == 101
    @test recovery.scan.fluxes_over_pi ==
        [0.234375, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]
    @test recovery.scan.minimum_step_over_pi == 0.0078125
    @test endswith(
        something(recovery.scan.initial_state_file),
        "state_0008_yc8-1_primary_forward_independent_theta0_alternating_forward_" *
        "seed101_chi128_theta_p0p21875000_accepted_c6ca08289c23.h5",
    )
    @test recovery.scan.initial_state_sha256 ==
        "492cc6fbc578b02f30a11ff621daa96475bf717b14e75653b388dd089de5415f"
    @test occursin("primary_forward_recovery_from_0p21875", recovery.runtime.output_directory)
    recovery_2 = load_settings(joinpath(
        PROJECT_ROOT,
        "configs",
        "phase1_yc8_1_forward_recovery_from_0p2265625_chi128.toml",
    ))
    @test recovery_2.optimizer.max_iterations == 200
    @test recovery_2.optimizer.residual_tol == 1e-5
    @test recovery_2.scan.require_parent_overlap
    @test recovery_2.scan.minimum_parent_overlap_per_site == 0.99
    @test recovery_2.scan.minimum_step_over_pi == 0.00390625
    @test first(recovery_2.scan.fluxes_over_pi) == 0.234375
    @test endswith(
        something(recovery_2.scan.initial_state_file),
        "state_0002_yc8-1_primary_forward_independent_theta0_alternating_forward_" *
        "seed101_chi128_theta_p0p22656250_accepted_ed13a5f3d4dd.h5",
    )
    @test recovery_2.scan.initial_state_sha256 ==
        "ed7f06fc7a463d3810aa745c456fdc945795e5bc0984d0c3b244008ed0d3a25e"
    @test occursin("primary_forward_recovery_from_0p2265625", recovery_2.runtime.output_directory)
    recovery_3 = load_settings(joinpath(
        PROJECT_ROOT,
        "configs",
        "phase1_yc8_1_forward_recovery_from_0p23828125_chi128.toml",
    ))
    @test recovery_3.optimizer.max_iterations == 360
    @test recovery_3.optimizer.record_krylov_diagnostics
    @test recovery_3.optimizer.plateau_detection
    @test recovery_3.optimizer.plateau_warmup_iterations == 40
    @test recovery_3.optimizer.plateau_patience == 32
    @test recovery_3.optimizer.solver_krylov_dimension == 30
    @test first(recovery_3.scan.fluxes_over_pi) == 0.2421875
    @test endswith(
        something(recovery_3.scan.initial_state_file),
        "state_0004_yc8-1_primary_forward_independent_theta0_alternating_forward_" *
        "seed101_chi128_theta_p0p23828125_accepted_1f5d14a8fd65.h5",
    )
    @test recovery_3.scan.initial_state_sha256 ==
        "b6b54e47f894158f291e0f9851bce4fdc2322e31a49d3b79155acf21059ebeee"

    mktempdir() do directory
        raw = TOML.parsefile(joinpath(
            PROJECT_ROOT,
            "configs",
            "phase1_yc8_1_forward_chi128.toml",
        ))
        raw["scan"]["fluxes_over_pi"] = [0.2421875]
        raw["scan"]["initial_state_file"] = "accepted.h5"
        raw["scan"]["initial_state_sha256"] = repeat("a", 64)
        raw["scan"]["optimizer_checkpoint_file"] = "checkpoint.h5"
        raw["scan"]["optimizer_checkpoint_sha256"] = repeat("b", 64)
        raw["runtime"]["output_directory"] = "resume-output"
        config_path = joinpath(directory, "resume.toml")
        open(config_path, "w") do io
            TOML.print(io, raw; sorted=true)
        end
        resume = load_settings(config_path)
        @test resume.scan.optimizer_checkpoint_file ==
            joinpath(directory, "checkpoint.h5")
        @test resume.scan.optimizer_checkpoint_sha256 == repeat("b", 64)
        @test resume.scan.initial_state_file == joinpath(directory, "accepted.h5")

        delete!(raw["scan"], "optimizer_checkpoint_sha256")
        invalid_path = joinpath(directory, "invalid-resume.toml")
        open(invalid_path, "w") do io
            TOML.print(io, raw; sorted=true)
        end
        @test_throws ArgumentError load_settings(invalid_path)

        raw = TOML.parsefile(joinpath(
            PROJECT_ROOT,
            "configs",
            "phase1_yc8_1_forward_chi128.toml",
        ))
        raw["optimizer"]["multisite_update_alg"] = "unsupported"
        invalid_algorithm_path = joinpath(directory, "invalid-algorithm.toml")
        open(invalid_algorithm_path, "w") do io
            TOML.print(io, raw; sorted=true)
        end
        @test_throws ArgumentError load_settings(invalid_algorithm_path)
    end
end

@testset "Finite-entanglement scaling" begin
    central_charge = 1.5
    xi = [10.0, 25.0, 70.0, 180.0]
    entropy = 0.7 .+ (central_charge / 6) .* log.(xi)
    local_rows = local_central_charges([64, 128, 256, 512], entropy, xi)
    @test all(row -> isapprox(row.c_eff, central_charge; atol=1e-12), local_rows)
    fit = fit_central_charge(entropy, xi)
    @test isapprox(fit.central_charge, central_charge; atol=1e-12)
    @test isapprox(fit.r_squared, 1.0; atol=1e-12)
end

@testset "Basin-change diagnostics" begin
    rows = diagnose_series(
        [0.0, 0.4, 0.5];
        energy_density=[-0.5, -0.51, -0.51001],
        mean_entropy=[1.0, 1.1, 1.5],
        leading_inverse_xi=[0.8, 0.5, 0.52],
        energy_term_std=[0.1, 0.05, 0.001],
        residual=[1e-8, 1e-3, 2e-3],
        residual_tolerance=1e-5,
    )
    @test first(rows).left_theta_over_pi == 0.4
    @test first(rows).right_theta_over_pi == 0.5
    @test first(rows).residual_ratio == 200.0
end

@testset "Adaptive continuation bracket classification" begin
    @test PB.minimum_step_bracket_reached(0.21875, 0.25, 0.03125)
    @test PB.minimum_step_bracket_reached(0.25, 0.21875, 0.03125)
    @test PB.minimum_step_bracket_reached(0.3, 0.4, 0.1)
    @test PB.minimum_step_bracket_reached(0.1, 0.15, 0.05)
    @test PB.minimum_step_bracket_reached(0.15, 0.2, 0.05)
    @test !PB.minimum_step_bracket_reached(0.1875, 0.25, 0.03125)
end

@testset "Guarded chi-512 campaign automation" begin
    @test PB.phase1_next_nominal_fluxes(0.1) == Float64.(2:10) ./ 10
    @test PB.phase1_next_nominal_fluxes(0.15) == Float64.(2:10) ./ 10
    @test PB.phase1_next_nominal_fluxes(1.0) == Float64[]
    @test PB.phase1_refined_forward_schedule(0.1, 0.2) ==
        vcat([0.15], Float64.(2:10) ./ 10)
    @test PB.phase1_refined_forward_schedule(0.2, 0.3) ==
        vcat([0.25], Float64.(3:10) ./ 10)
    @test_throws ArgumentError PB.phase1_refined_forward_schedule(0.2, 0.1)
    @test PB.phase1_contracting_retry_cap(180, 308.0) == 360
    @test PB.phase1_contracting_retry_cap(360, 650.0) == 720
    @test PB.phase1_contracting_retry_cap(180, NaN) == 360
    converged_record = PB.KrylovSolveDiagnostic(
        outer_iteration=1,
        solve_kind="environment_left",
        site=1,
        requested_tolerance=1e-8,
        krylov_dimension=30,
        maximum_iterations=100,
        converged_count=1,
        residual_norm=1e-10,
        iterations=4,
        operations=7,
        elapsed_seconds=0.1,
    )
    failed_record = PB.KrylovSolveDiagnostic(
        outer_iteration=1,
        solve_kind="center_C",
        site=1,
        requested_tolerance=1e-8,
        krylov_dimension=30,
        maximum_iterations=100,
        converged_count=0,
        residual_norm=1e-4,
        iterations=100,
        operations=130,
        elapsed_seconds=1.0,
    )
    diagnostic_with(records) = PB.VumpsDiagnostics(
        converged=true,
        stop_reason="converged",
        iterations=1,
        residual=1e-6,
        minimum_residual=1e-6,
        residual_history=[1e-6],
        energy_left_history=zeros(2, 1),
        energy_right_history=zeros(2, 1),
        growth_dimensions=[512],
        growth_stage_ends=[1],
        residual_tolerance=1e-5,
        krylov_solves=records,
    )
    @test PB.all_recorded_krylov_solves_converged(diagnostic_with([converged_record]))
    @test !PB.all_recorded_krylov_solves_converged(diagnostic_with(KrylovSolveDiagnostic[]))
    @test !PB.all_recorded_krylov_solves_converged(
        diagnostic_with([converged_record, failed_record]),
    )

    common = (
        scheduler_state="COMPLETED",
        job_exit_code=0,
        has_accepted_parent=true,
        parent_theta_over_pi=0.1,
        parent_inner_solves_converged=true,
        candidate_inner_solves_converged=true,
    )
    clean = PB.phase1_advance_policy(; common...)
    @test clean.action === :continue_schedule
    completed = PB.phase1_advance_policy(; common..., parent_theta_over_pi=1.0)
    @test completed.action === :complete
    refined = PB.phase1_advance_policy(
        ;
        common...,
        outcome_kind="flux_scan",
        outcome_status="numerical_continuation_loss_bracketed",
        classification="numerical_divergence_not_physical_endpoint",
        optimizer_stop_reason="diverging_residual",
        bracket_width_over_pi=0.1,
    )
    @test refined.action === :refine_interval
    floor = PB.phase1_advance_policy(
        ;
        common...,
        outcome_kind="flux_scan",
        outcome_status="numerical_continuation_loss_bracketed",
        classification="numerical_divergence_not_physical_endpoint",
        optimizer_stop_reason="diverging_residual",
        bracket_width_over_pi=0.05,
    )
    @test floor.action === :manual_review
    contracting = PB.phase1_advance_policy(
        ;
        common...,
        outcome_kind="flux_scan",
        outcome_status="numerical_continuation_loss_bracketed",
        classification="iteration_limit_while_contracting_not_physical_endpoint",
        optimizer_stop_reason="maximum_iterations_contracting",
        bracket_width_over_pi=0.05,
        current_max_iterations=180,
    )
    @test contracting.action === :retry_contracting
    continuity = PB.phase1_advance_policy(
        ;
        common...,
        outcome_kind="flux_scan",
        outcome_status="branch_continuity_loss_bracketed",
        classification="possible_basin_jump_not_physical_endpoint",
        optimizer_stop_reason="converged",
        bracket_width_over_pi=0.1,
    )
    @test continuity.action === :manual_review
    inner_failure = PB.phase1_advance_policy(
        ;
        common...,
        outcome_kind="flux_scan",
        outcome_status="numerical_continuation_loss_bracketed",
        classification="numerical_divergence_not_physical_endpoint",
        optimizer_stop_reason="diverging_residual",
        bracket_width_over_pi=0.1,
        candidate_inner_solves_converged=false,
    )
    @test inner_failure.action === :manual_review
    timeout = PB.phase1_advance_policy(
        scheduler_state="TIMEOUT",
        job_exit_code=nothing,
        has_accepted_parent=true,
        parent_theta_over_pi=0.4,
        parent_inner_solves_converged=true,
    )
    @test timeout.action === :continue_schedule
    failed = PB.phase1_advance_policy(
        scheduler_state="FAILED",
        job_exit_code=1,
        has_accepted_parent=true,
        parent_theta_over_pi=0.4,
    )
    @test failed.action === :manual_review

    final_success = PB.phase1_final_vumps_control_policy(
        scheduler_state="COMPLETED",
        job_exit_code=0,
        reached_target=true,
    )
    @test final_success.action === :manual_review
    @test occursin("converged", final_success.reason)
    final_numerical_failure = PB.phase1_final_vumps_control_policy(
        scheduler_state="COMPLETED",
        job_exit_code=0,
        reached_target=false,
        outcome_kind="flux_scan",
    )
    @test final_numerical_failure.action === :manual_review
    @test occursin("iDMRG", final_numerical_failure.reason)
    final_infrastructure_failure = PB.phase1_final_vumps_control_policy(
        scheduler_state="TIMEOUT",
        job_exit_code=nothing,
        reached_target=false,
    )
    @test final_infrastructure_failure.action === :manual_review
    @test occursin("scheduler", final_infrastructure_failure.reason)
end

@testset "Fixed-flux expansion classification" begin
    @test PB.fixed_flux_expansion_requested(0.2421875, 0.2421875, 128, 192)
    @test PB.fixed_flux_expansion_requested(0.2421875, 0.2421875 + 1e-13, 128, 192)
    @test !PB.fixed_flux_expansion_requested(nothing, 0.2421875, 128, 192)
    @test !PB.fixed_flux_expansion_requested(0.2421875, 0.24609375, 128, 192)
    @test !PB.fixed_flux_expansion_requested(0.2421875, 0.2421875, 192, 192)
    @test PB.fixed_flux_optimizer_resume_requested(
        0.2421875,
        0.2421875,
        "/test/rejected-checkpoint.h5",
    )
    @test PB.fixed_flux_optimizer_resume_requested(
        0.2421875,
        0.24609375,
        "/test/rejected-checkpoint.h5",
    )
    @test !PB.fixed_flux_optimizer_resume_requested(0.2421875, 0.2421875, "")

    base = load_settings(joinpath(PROJECT_ROOT, "configs", "phase1_yc8_1_forward_chi128.toml"))
    diagnostic = PB.VumpsDiagnostics(
        converged=false,
        stop_reason="maximum_iterations_stalled",
        iterations=360,
        residual=3e-5,
        minimum_residual=2e-5,
        residual_history=[2e-5, 3e-5],
        energy_left_history=zeros(2, 2),
        energy_right_history=zeros(2, 2),
        growth_dimensions=[128, 192],
        growth_stage_ends=[360],
        residual_tolerance=1e-5,
    )
    continuity = PB.skipped_branch_continuity(
        "VUMPS residual gate failed before parent-overlap evaluation";
        passed=false,
        parent_theta_over_pi=0.2421875,
        candidate_theta_over_pi=0.2421875,
        minimum_overlap_per_site=0.99,
    )
    mktempdir() do directory
        settings = ProjectSettings(
            model=base.model,
            optimizer=OptimizerSettings(
                maxdim=192,
                residual_tol=1e-5,
                max_iterations=360,
                record_krylov_diagnostics=true,
                plateau_detection=false,
            ),
            scan=base.scan,
            spectrum=base.spectrum,
            runtime=RuntimeSettings(output_directory=directory),
            config_path="/test/fixed-flux.toml",
            config_text="# fixed-flux test fixture\n",
        )
        path = PB.write_fixed_flux_expansion_outcome(
            settings,
            diagnostic,
            continuity,
            0.2421875,
            1,
            128,
            192,
            "/test/accepted-parent.h5",
            repeat("a", 64),
            "/test/rejected-candidate.h5",
            repeat("b", 64),
        )
        outcome = TOML.parsefile(path)
        @test outcome["schema_version"] == 2
        @test outcome["artifact_kind"] == "project_b_fixed_flux_expansion_outcome"
        @test outcome["status"] == "fixed_flux_expansion_numerical_failure"
        @test outcome["classification"] ==
            "iteration_limit_stalled_not_physical_endpoint"
        @test outcome["theta_over_pi"] == 0.2421875
        @test outcome["source_maxdim"] == 128
        @test outcome["requested_maxdim"] == 192
        @test outcome["result_maxdim"] == 192
        @test outcome["optimizer_max_iterations"] == 360
        @test outcome["optimizer_terminal_residual"] == 3e-5
        @test outcome["optimizer_returned_iteration"] == 360
        @test outcome["optimizer_multisite_update_alg"] == "sequential"
        @test !outcome["optimizer_restore_best_on_failure_enabled"]
        @test !outcome["optimizer_plateau_detection"]
        @test !outcome["physical_endpoint"]
        @test !outcome["continuation_accepted"]
        @test_throws ErrorException PB.write_fixed_flux_expansion_outcome(
            settings,
            diagnostic,
            continuity,
            0.2421875,
            1,
            128,
            192,
            "/test/accepted-parent.h5",
            repeat("a", 64),
            "/test/rejected-candidate.h5",
            repeat("b", 64),
        )

        resume_directory = joinpath(directory, "resume")
        mkpath(resume_directory)
        resume_settings = ProjectSettings(
            model=settings.model,
            optimizer=settings.optimizer,
            scan=settings.scan,
            spectrum=settings.spectrum,
            runtime=RuntimeSettings(output_directory=resume_directory),
            config_path="/test/fixed-flux-resume.toml",
            config_text="# fixed-flux optimizer resume fixture\n",
        )
        resume_path = PB.write_fixed_flux_optimizer_resume_outcome(
            resume_settings,
            diagnostic,
            continuity,
            0.2421875,
            1,
            128,
            192,
            192,
            360,
            2.332663e-5,
            2.332663e-5,
            "maximum_iterations_contracting",
            "/test/accepted-parent.h5",
            repeat("a", 64),
            "/test/rejected-checkpoint.h5",
            repeat("b", 64),
            "/test/rejected-resume.h5",
            repeat("c", 64),
        )
        resume_outcome = TOML.parsefile(resume_path)
        @test resume_outcome["artifact_kind"] ==
            "project_b_fixed_flux_optimizer_resume_outcome"
        @test resume_outcome["status"] ==
            "fixed_flux_optimizer_resume_numerical_failure"
        @test resume_outcome["checkpoint_cumulative_iterations"] == 360
        @test resume_outcome["result_maxdim"] == 192
        @test resume_outcome["optimizer_additional_iterations"] == 360
        @test resume_outcome["optimizer_cumulative_iterations"] == 720
        @test resume_outcome["optimizer_checkpoint_sha256"] == repeat("b", 64)
        @test !resume_outcome["physical_endpoint"]

        pretimeout_directory = joinpath(directory, "pretimeout")
        mkpath(pretimeout_directory)
        pretimeout_settings = ProjectSettings(
            model=settings.model,
            optimizer=settings.optimizer,
            scan=settings.scan,
            spectrum=settings.spectrum,
            runtime=RuntimeSettings(output_directory=pretimeout_directory),
            config_path="/test/pretimeout.toml",
            config_text="# pretimeout fixture\n",
        )
        pretimeout_diagnostic = PB.checkpoint_diagnostic(
            diagnostic,
            "pretimeout_checkpoint",
        )
        pretimeout_path = PB.write_pretimeout_scan_outcome(
            pretimeout_settings,
            0.35,
            1,
            pretimeout_diagnostic,
            "/test/accepted-parent.h5",
            repeat("a", 64),
            (
                path="/test/checkpoint.h5",
                sha256=repeat("d", 64),
                resume_configuration="/test/resume.toml",
            ),
        )
        pretimeout_outcome = TOML.parsefile(pretimeout_path)
        @test pretimeout_outcome["status"] == "pretimeout_checkpointed"
        @test pretimeout_outcome["classification"] ==
            "scheduler_boundary_not_scientific_endpoint"
        @test pretimeout_outcome["optimizer_checkpoint_sha256"] == repeat("d", 64)
        @test pretimeout_outcome["resume_configuration"] == "/test/resume.toml"
    end
end

@testset "Residual trend and plateau classification" begin
    @test PB.best_residual_iteration([3.0, 1.0, 2.0]) == 2
    @test PB.best_residual_iteration([NaN, Inf, 2.0]) == 3
    @test PB.best_residual_iteration(Float64[]) == 0
    @test PB.should_restore_best_on_failure(true, "diverging_residual", 13, 32)
    @test !PB.should_restore_best_on_failure(false, "diverging_residual", 13, 32)
    @test !PB.should_restore_best_on_failure(true, "converged", 13, 32)
    @test !PB.should_restore_best_on_failure(true, "diverging_residual", 32, 32)
    resized_optimizer = PB.optimizer_with_maxdim(
        OptimizerSettings(
            maxdim=512,
            multisite_update_alg="parallel",
            restore_best_on_failure=true,
        ),
        256,
    )
    @test resized_optimizer.maxdim == 256
    @test resized_optimizer.multisite_update_alg == "parallel"
    @test resized_optimizer.restore_best_on_failure
    contracting = 3.4e-5 .* 0.996 .^ (0:199)
    trend = PB.residual_trend(contracting, 1e-5; improvement_window=24)
    @test trend.relative_improvement > 0.05
    @test trend.log_slope < 0
    @test trend.r_squared > 0.999
    @test trend.projected_total_iterations > 200
    contracting_optimizer = OptimizerSettings(
        maxdim=128,
        residual_tol=1e-5,
        plateau_detection=true,
        plateau_warmup_iterations=30,
        plateau_patience=24,
        plateau_min_relative_improvement=5e-3,
    )
    @test !PB.residual_plateau_detected(contracting, contracting_optimizer)

    rebounding = vcat(range(1.1e-4, 8.3e-5; length=8), fill(9.0e-5, 32))
    @test PB.residual_plateau_detected(rebounding, contracting_optimizer)
    diagnostic = PB.VumpsDiagnostics(
        converged=false,
        stop_reason="maximum_iterations_contracting",
        iterations=length(contracting),
        residual=last(contracting),
        minimum_residual=minimum(contracting),
        residual_history=collect(contracting),
        energy_left_history=zeros(2, length(contracting)),
        energy_right_history=zeros(2, length(contracting)),
        growth_dimensions=[128],
        growth_stage_ends=[length(contracting)],
    )
    @test PB.numerical_continuation_classification(diagnostic) ==
        "iteration_limit_while_contracting_not_physical_endpoint"
    staged = PB.VumpsDiagnostics(
        converged=false,
        stop_reason="maximum_iterations_contracting",
        iterations=2,
        residual=0.5,
        minimum_residual=0.5,
        residual_history=[1.0, 0.5],
        energy_left_history=zeros(1, 2),
        energy_right_history=zeros(1, 2),
        growth_dimensions=[2],
        growth_stage_ends=[2],
        residual_tolerance=0.1,
        projected_total_iterations=4.0,
    )
    merged = PB.merge_diagnostics([staged, staged], [2, 2])
    @test merged.iterations == 4
    @test merged.projected_total_iterations == 6.0
    @test merged.terminal_residual == 0.5
    @test merged.best_iteration == 0
    @test merged.returned_iteration == 4
    @test !merged.restored_best_on_failure
end

@testset "Parent-overlap acceptance rule" begin
    @test PB.parent_overlap_passes(0.999, 0.99)
    @test PB.parent_overlap_passes(0.99, 0.99)
    @test !PB.parent_overlap_passes(0.989999, 0.99)
    @test !PB.parent_overlap_passes(NaN, 0.99)
    @test iszero(PB.distribution_total_variation(
        [0.7, 0.2, 0.1],
        [0.1, 0.7, 0.2, 0.0],
    ))
    @test isapprox(
        PB.distribution_total_variation([0.7, 0.2, 0.1], [0.6, 0.3, 0.1]),
        0.1;
        atol=1e-12,
    )
end

@testset "Product-state construction and immutable HDF5 state" begin
    settings = load_settings(joinpath(PROJECT_ROOT, "configs", "pilot_yc6_1.toml"))
    psi = build_product_state(settings)
    @test PB.maxlinkdim(psi) == 1
    @test PB.nsites(psi) == 2
    sector_rows = compare_bond_sectors(psi, psi)
    @test !isempty(sector_rows)
    @test all(row -> iszero(row.multiplicity_delta), sector_rows)
    @test all(row -> iszero(row.schmidt_weight_delta), sector_rows)
    for cut in 1:PB.nsites(psi)
        @test isapprox(
            sum(row.before_schmidt_weight for row in sector_rows if row.cut == cut),
            1.0;
            atol=1e-12,
        )
    end
    hamiltonian = build_hamiltonian(settings.model, PB.siteinds(psi), 0.0)
    observables = PB.local_observables(psi, hamiltonian)
    overlap_settings = ScanSettings(
        branch=settings.scan.branch,
        preparation=settings.scan.preparation,
        direction=:forward,
        lineage_policy=:strict,
        fluxes_over_pi=[0.0, 0.25],
        seed_pattern=settings.scan.seed_pattern,
        random_seed=settings.scan.random_seed,
        require_parent_overlap=true,
        minimum_parent_overlap_per_site=0.99,
        parent_overlap_tolerance=1e-10,
        parent_overlap_krylov_dimension=4,
    )
    continuity = PB.branch_continuity_diagnostics(
        psi,
        psi,
        observables,
        observables,
        0.0,
        0.0,
        overlap_settings,
    )
    @test continuity.checked
    @test continuity.passed
    @test isapprox(continuity.overlap_per_unit_cell, 1.0; atol=1e-10)
    @test isapprox(continuity.overlap_per_site, 1.0; atol=1e-10)
    @test iszero(continuity.mean_schmidt_total_variation)
    multimetric_settings = ScanSettings(
        branch=settings.scan.branch,
        preparation=settings.scan.preparation,
        direction=:forward,
        lineage_policy=:strict,
        fluxes_over_pi=[0.0, 0.25],
        seed_pattern=settings.scan.seed_pattern,
        random_seed=settings.scan.random_seed,
        require_parent_overlap=true,
        continuity_policy=:multimetric_trust_region,
        minimum_parent_overlap_per_site=0.90,
        parent_overlap_tolerance=1e-10,
        parent_overlap_krylov_dimension=4,
        maximum_cut_entropy_jump=0.10,
        maximum_energy_term_rms_jump=0.02,
        maximum_magnetization_rms_jump=0.001,
        maximum_mean_schmidt_total_variation=0.05,
        require_u1_sector_diagnostics=true,
    )
    shifted_observables = merge(
        observables,
        (energy_terms=observables.energy_terms .+ 0.10,),
    )
    multimetric_failure = PB.branch_continuity_diagnostics(
        psi,
        psi,
        observables,
        shifted_observables,
        0.0,
        0.0,
        multimetric_settings,
    )
    @test !multimetric_failure.passed
    @test !multimetric_failure.energy_term_gate_passed
    @test multimetric_failure.u1_sector_diagnostics_passed
    @test !multimetric_failure.overlap_alarm_triggered
    @test multimetric_failure.reason == "failed_local_energy_pattern"
    krylov_record = PB.KrylovSolveDiagnostic(
        outer_iteration=1,
        solve_kind="center_C",
        site=1,
        requested_tolerance=1e-8,
        krylov_dimension=30,
        maximum_iterations=100,
        converged_count=1,
        residual_norm=1e-9,
        iterations=2,
        operations=12,
        elapsed_seconds=0.25,
    )
    diagnostic = PB.VumpsDiagnostics(
        converged=true,
        stop_reason="test_fixture",
        iterations=1,
        residual=0.0,
        minimum_residual=0.0,
        residual_history=[0.0],
        energy_left_history=zeros(2, 1),
        energy_right_history=zeros(2, 1),
        growth_dimensions=[1],
        growth_stage_ends=[1],
        residual_tolerance=settings.optimizer.residual_tol,
        trend_window=1,
        recent_relative_improvement=NaN,
        log_residual_slope=NaN,
        log_residual_r_squared=NaN,
        projected_total_iterations=1.0,
        krylov_solves=[krylov_record],
    )
    mktempdir() do directory
        path = joinpath(directory, "state.h5")
        PB.write_state_file(
            path,
            settings,
            psi,
            hamiltonian,
            diagnostic,
            0.0,
            1;
            continuity,
            precomputed_observables=observables,
        )
        @test isfile(path)
        state = PB.read_state_file(path)
        @test state.circumference == 6
        @test state.shift == 1
        @test state.converged
        @test state.continuation_accepted
        @test state.J2 == settings.model.J2
        @test state.preparation == "default"
        @test state.direction === :forward
        @test state.random_seed == 1
        @test state.seed_pattern == "alternating"
        @test state.flux_history_over_pi == [0.0]
        @test state.optimizer_terminal_residual == 0.0
        @test state.optimizer_best_iteration == 0
        @test state.optimizer_returned_iteration == 1
        @test !state.optimizer_restored_best_on_failure
        @test state.optimizer_multisite_update_alg == "sequential"
        @test !state.optimizer_restore_best_on_failure_enabled
        @test isempty(state.parent_state_path)
        @test isempty(state.parent_state_sha256)
        parent_sha256 = PB.file_sha256(path)
        @test length(parent_sha256) == 64
        checkpoint_diagnostic = PB.VumpsDiagnostics(
            converged=false,
            stop_reason="maximum_iterations_contracting",
            iterations=360,
            residual=2.3e-5,
            minimum_residual=2.3e-5,
            residual_history=[3.0e-5, 2.3e-5],
            energy_left_history=zeros(2, 2),
            energy_right_history=zeros(2, 2),
            growth_dimensions=[1],
            growth_stage_ends=[360],
            residual_tolerance=1e-5,
            trend_window=2,
            recent_relative_improvement=0.2,
            log_residual_slope=-0.01,
            log_residual_r_squared=1.0,
            projected_total_iterations=484.0,
        )
        checkpoint_settings = ProjectSettings(
            model=settings.model,
            optimizer=OptimizerSettings(
                maxdim=1,
                residual_tol=1e-5,
                max_iterations=360,
                record_krylov_diagnostics=true,
                plateau_detection=false,
            ),
            scan=settings.scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# contracting checkpoint fixture\n",
        )
        checkpoint_path = joinpath(directory, "checkpoint.h5")
        PB.write_state_file(
            checkpoint_path,
            checkpoint_settings,
            psi,
            hamiltonian,
            checkpoint_diagnostic,
            0.0,
            1;
            continuation_accepted=false,
            parent_state_path=path,
            parent_state_sha256=parent_sha256,
            parent_flux_history_over_pi=[0.0],
            precomputed_observables=observables,
        )
        checkpoint_sha256 = PB.file_sha256(checkpoint_path)
        checkpoint_state = PB.read_state_file(checkpoint_path)
        @test !checkpoint_state.converged
        @test !checkpoint_state.continuation_accepted
        @test checkpoint_state.optimizer_stop_reason == "maximum_iterations_contracting"
        @test checkpoint_state.optimizer_iterations == 360
        @test checkpoint_state.optimizer_requested_maxdim == 1
        strict_scan = ScanSettings(
            branch=settings.scan.branch,
            preparation="default",
            direction=:forward,
            lineage_policy=:strict,
            fluxes_over_pi=[0.0, 0.25],
            seed_pattern="alternating",
            random_seed=1,
            initial_state_file=path,
            initial_state_sha256=parent_sha256,
        )
        strict_settings = ProjectSettings(
            model=settings.model,
            optimizer=settings.optimizer,
            scan=strict_scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# strict restart fixture\n",
        )
        initial = PB.load_or_build_initial_state(strict_settings)
        @test initial.initial_theta == 0.0
        @test initial.parent_state_path == path
        @test initial.flux_history_over_pi == [0.0]
        resume_scan = ScanSettings(
            branch=settings.scan.branch,
            preparation="default",
            direction=:forward,
            lineage_policy=:strict,
            fluxes_over_pi=[0.0],
            seed_pattern="alternating",
            random_seed=1,
            initial_state_file=path,
            initial_state_sha256=parent_sha256,
            optimizer_checkpoint_file=checkpoint_path,
            optimizer_checkpoint_sha256=checkpoint_sha256,
        )
        resume_settings = ProjectSettings(
            model=settings.model,
            optimizer=OptimizerSettings(
                maxdim=1,
                residual_tol=1e-5,
                max_iterations=180,
                record_krylov_diagnostics=true,
                plateau_detection=false,
            ),
            scan=resume_scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# optimizer resume fixture\n",
        )
        resumed_initial = PB.load_or_build_initial_state(resume_settings)
        @test resumed_initial.parent_state_path == path
        @test resumed_initial.parent_state_sha256 == parent_sha256
        @test resumed_initial.parent_maxdim == 1
        @test resumed_initial.optimizer_checkpoint_path == checkpoint_path
        @test resumed_initial.optimizer_checkpoint_sha256 == checkpoint_sha256
        @test resumed_initial.optimizer_checkpoint_iterations == 360
        @test resumed_initial.optimizer_checkpoint_residual == 2.3e-5

        target_checkpoint_path = joinpath(directory, "target-checkpoint.h5")
        target_checkpoint_diagnostic = PB.checkpoint_diagnostic(
            checkpoint_diagnostic,
            "growth_stage_checkpoint",
        )
        growth_checkpoint_settings = ProjectSettings(
            model=settings.model,
            optimizer=OptimizerSettings(
                maxdim=2,
                residual_tol=1e-5,
                max_iterations=180,
                record_krylov_diagnostics=true,
                plateau_detection=false,
            ),
            scan=settings.scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# growth-stage checkpoint fixture\n",
        )
        PB.write_state_file(
            target_checkpoint_path,
            growth_checkpoint_settings,
            psi,
            build_hamiltonian(settings.model, PB.siteinds(psi), 0.25),
            target_checkpoint_diagnostic,
            0.25,
            2;
            continuation_accepted=false,
            parent_state_path=path,
            parent_state_sha256=parent_sha256,
            parent_flux_history_over_pi=[0.0],
            precomputed_observables=observables,
        )
        target_checkpoint_sha256 = PB.file_sha256(target_checkpoint_path)
        target_checkpoint_state = PB.read_state_file(target_checkpoint_path)
        @test target_checkpoint_state.parent_flux_history_over_pi == [0.0]
        @test target_checkpoint_state.flux_history_over_pi == [0.0, 0.25]
        scratch_checkpoint_directory = joinpath(directory, "scratch-checkpoints")
        withenv(
            "PROJECT_B_OPTIMIZER_CHECKPOINT_DIRECTORY" =>
                scratch_checkpoint_directory,
        ) do
            routed_checkpoint_path = PB.optimizer_checkpoint_file_path(
                checkpoint_settings,
                2,
                0.25,
                target_checkpoint_diagnostic,
            )
            @test dirname(routed_checkpoint_path) == scratch_checkpoint_directory
        end
        target_resume_scan = ScanSettings(
            branch=settings.scan.branch,
            preparation="default",
            direction=:forward,
            lineage_policy=:strict,
            fluxes_over_pi=[0.25],
            seed_pattern="alternating",
            random_seed=1,
            initial_state_file=path,
            initial_state_sha256=parent_sha256,
            optimizer_checkpoint_file=target_checkpoint_path,
            optimizer_checkpoint_sha256=target_checkpoint_sha256,
        )
        target_resume_settings = ProjectSettings(
            model=settings.model,
            optimizer=growth_checkpoint_settings.optimizer,
            scan=target_resume_scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# target-flux checkpoint fixture\n",
        )
        target_resumed_initial = PB.load_or_build_initial_state(target_resume_settings)
        @test target_resumed_initial.initial_theta == 0.0
        @test target_resumed_initial.optimizer_checkpoint_path == target_checkpoint_path
        @test target_resumed_initial.psi !== nothing

        yc6_checkpoint_settings = load_settings(joinpath(
            PROJECT_ROOT,
            "configs",
            "science_yc6_1_legacy_period6_chi512_after_57629467.toml",
        ))
        generated_resume_path = PB.write_optimizer_resume_configuration(
            yc6_checkpoint_settings,
            target_checkpoint_path,
            target_checkpoint_sha256,
            0.35,
            something(yc6_checkpoint_settings.scan.initial_state_file),
            something(yc6_checkpoint_settings.scan.initial_state_sha256),
            manifest_directory=directory,
        )
        generated_resume = TOML.parsefile(generated_resume_path)
        @test generated_resume["scan"]["fluxes_over_pi"] == [0.35]
        @test generated_resume["scan"]["optimizer_checkpoint_sha256"] ==
            target_checkpoint_sha256
        @test generated_resume["scan"]["optimizer_checkpoint_file"] ==
            abspath(target_checkpoint_path)
        @test generated_resume["runtime"]["optimizer_checkpoint_every_iterations"] == 5
        @test occursin(
            "resumes",
            generated_resume["runtime"]["output_directory"],
        )
        @test dirname(generated_resume_path) == directory

        wrong_checkpoint_scan = ScanSettings(
            branch=resume_scan.branch,
            preparation=resume_scan.preparation,
            direction=resume_scan.direction,
            lineage_policy=resume_scan.lineage_policy,
            fluxes_over_pi=resume_scan.fluxes_over_pi,
            seed_pattern=resume_scan.seed_pattern,
            random_seed=resume_scan.random_seed,
            initial_state_file=path,
            initial_state_sha256=parent_sha256,
            optimizer_checkpoint_file=checkpoint_path,
            optimizer_checkpoint_sha256=repeat("0", 64),
        )
        wrong_checkpoint_settings = ProjectSettings(
            model=resume_settings.model,
            optimizer=resume_settings.optimizer,
            scan=wrong_checkpoint_scan,
            spectrum=resume_settings.spectrum,
            runtime=resume_settings.runtime,
            config_path=resume_settings.config_path,
            config_text=resume_settings.config_text * "\n# wrong checkpoint hash\n",
        )
        @test_throws ErrorException PB.load_or_build_initial_state(wrong_checkpoint_settings)
        mismatched_scan = ScanSettings(
            branch=settings.scan.branch,
            preparation="different_preparation",
            direction=:forward,
            lineage_policy=:strict,
            fluxes_over_pi=[0.0, 0.25],
            seed_pattern="alternating",
            random_seed=1,
            initial_state_file=path,
            initial_state_sha256=parent_sha256,
        )
        mismatched_settings = ProjectSettings(
            model=settings.model,
            optimizer=settings.optimizer,
            scan=mismatched_scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# mismatched restart fixture\n",
        )
        @test_throws ErrorException PB.load_or_build_initial_state(mismatched_settings)
        wrong_hash_scan = ScanSettings(
            branch=settings.scan.branch,
            preparation="default",
            direction=:forward,
            lineage_policy=:strict,
            fluxes_over_pi=[0.0, 0.25],
            seed_pattern="alternating",
            random_seed=1,
            initial_state_file=path,
            initial_state_sha256=repeat("0", 64),
        )
        wrong_hash_settings = ProjectSettings(
            model=settings.model,
            optimizer=settings.optimizer,
            scan=wrong_hash_scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# wrong hash fixture\n",
        )
        @test_throws ErrorException PB.load_or_build_initial_state(wrong_hash_settings)
        missing_hash_scan = ScanSettings(
            branch=settings.scan.branch,
            preparation="default",
            direction=:forward,
            lineage_policy=:strict,
            fluxes_over_pi=[0.0, 0.25],
            seed_pattern="alternating",
            random_seed=1,
            initial_state_file=path,
        )
        missing_hash_settings = ProjectSettings(
            model=settings.model,
            optimizer=settings.optimizer,
            scan=missing_hash_scan,
            spectrum=settings.spectrum,
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# missing hash fixture\n",
        )
        @test_throws ErrorException PB.load_or_build_initial_state(missing_hash_settings)
        h5open(path, "r") do file
            @test read(file, "schema_version") == 7
            @test haskey(file, "geometry/bonds")
            @test read(file, "geometry/mps_period") == 2
            @test read(file, "geometry/minimal_mps_period") == 2
            @test read(file, "geometry/unit_cell_is_minimal")
            @test read(file, "model/twist_gauge") == "uniform"
            @test haskey(file, "observables/schmidt_probabilities")
            @test haskey(file, "optimizer/residual_history")
            @test read(file, "optimizer/terminal_residual") == 0.0
            @test read(file, "optimizer/best_iteration") == 0
            @test read(file, "optimizer/returned_iteration") == 1
            @test !read(file, "optimizer/restored_best_on_failure")
            @test read(file, "optimizer/multisite_update_alg") == "sequential"
            @test !read(file, "optimizer/restore_best_on_failure_enabled")
            @test read(file, "optimizer/krylov_solves/count") == 1
            @test read(file, "optimizer/krylov_solves/solve_kind") == ["center_C"]
            @test read(file, "optimizer/krylov_solves/krylov_dimension") == [30]
            @test read(file, "optimizer/projected_total_iterations") == 1.0
            @test read(file, "preparation") == "default"
            @test read(file, "direction") == "forward"
            @test read(file, "random_seed") == 1
            @test read(file, "continuation/seed_pattern") == "alternating"
            @test read(file, "continuation/preparation_source") ==
                "independent_product_state"
            @test isempty(read(file, "optimizer/restart_checkpoint_path"))
            @test read(file, "continuation/flux_history_over_pi") == [0.0]
            @test read(file, "continuation/continuity_checked")
            @test read(file, "continuation/continuity_passed")
            @test isapprox(read(file, "continuation/overlap_per_site"), 1.0; atol=1e-10)
            @test haskey(file, "continuation/mean_schmidt_total_variation")
            @test haskey(file, "continuation/maximum_log_correlation_length_jump")
            @test !read(file, "continuation/correlation_length_diagnostics_required")
            @test haskey(file, "psi")
        end
        child_path = joinpath(directory, "child.h5")
        PB.write_state_file(
            child_path,
            settings,
            psi,
            build_hamiltonian(settings.model, PB.siteinds(psi), 0.25),
            diagnostic,
            0.25,
            2;
            parent_state_path=path,
            parent_state_sha256=parent_sha256,
            parent_flux_history_over_pi=[0.0],
        )
        child = PB.read_state_file(child_path)
        @test child.parent_state_path == path
        @test child.parent_state_sha256 == parent_sha256
        @test child.flux_history_over_pi == [0.0, 0.25]
        resumed_path = joinpath(directory, "resumed.h5")
        PB.write_state_file(
            resumed_path,
            resume_settings,
            psi,
            hamiltonian,
            diagnostic,
            0.0,
            1;
            parent_state_path=path,
            parent_state_sha256=parent_sha256,
            parent_flux_history_over_pi=[0.0],
            optimizer_checkpoint_path=checkpoint_path,
            optimizer_checkpoint_sha256=checkpoint_sha256,
            optimizer_checkpoint_iterations=
                resumed_initial.optimizer_checkpoint_iterations,
            optimizer_checkpoint_residual=
                resumed_initial.optimizer_checkpoint_residual,
            optimizer_checkpoint_minimum_residual=
                resumed_initial.optimizer_checkpoint_minimum_residual,
            optimizer_checkpoint_stop_reason=
                resumed_initial.optimizer_checkpoint_stop_reason,
            continuity,
            precomputed_observables=observables,
        )
        resumed_state = PB.read_state_file(resumed_path)
        @test resumed_state.optimizer_checkpoint_path == checkpoint_path
        @test resumed_state.optimizer_checkpoint_sha256 == checkpoint_sha256
        @test resumed_state.optimizer_checkpoint_iterations == 360
        h5open(resumed_path, "r") do file
            @test read(file, "continuation/preparation_source") ==
                "optimizer_checkpoint_resume"
            @test read(file, "optimizer/restart_checkpoint_iterations") == 360
            @test read(file, "optimizer/restart_checkpoint_stop_reason") ==
                "maximum_iterations_contracting"
        end
        summary_rows = summarize_state_files(directory; include_hashes=true)
        @test length(summary_rows) == 5
        @test all(row -> row.geometry == "YC6-1", summary_rows)
        @test all(row -> length(row.state_sha256) == 64, summary_rows)
        spectroscopy_settings = ProjectSettings(
            model=settings.model,
            optimizer=settings.optimizer,
            scan=settings.scan,
            spectrum=SpectrumSettings(
                physical_sz_sectors=[0.0],
                neigs=1,
                tolerance=1e-8,
                krylov_dimension=4,
                random_seed=1,
            ),
            runtime=settings.runtime,
            config_path=settings.config_path,
            config_text=settings.config_text * "\n# neutral schema test\n",
        )
        spectrum_path = PB.postprocess_state_spectrum(
            path,
            spectroscopy_settings;
            output_directory=directory,
        )
        h5open(spectrum_path, "r") do file
            @test read(file, "schema_version") == 2
            @test read(file, "momentum/strategy") == "yc1_two_site_pure"
            @test read(file, "momentum/analysis_available")
            @test read(file, "transverse_momentum_resolved")
            @test read(file, "sectors/sz_0/momentum_resolved") == [true]
            @test haskey(file, "sectors/sz_0/k1_secondary")
        end
        @test_throws ErrorException PB.write_state_file(
            path,
            settings,
            psi,
            hamiltonian,
            diagnostic,
            0.0,
            1,
        )
    end
end


@testset "YC0 mixed translation construction" begin
    settings = load_settings(joinpath(PROJECT_ROOT, "configs", "hu_yc8_0_forward.toml"))
    psi = build_product_state(settings)
    @test PB.nsites(psi) == 8
    mixed = mixed_translation_transfer_matrix(
        psi,
        settings.model.geometry,
        0.0;
        source_gauge=settings.model.twist_gauge,
    )
    @test length(PB.input_inds(mixed)) == 2
    @test length(PB.output_inds(mixed)) == 2
end

if get(ENV, "PROJECT_B_RUN_VUMPS_SMOKE", "0") == "1"
    @testset "One-iteration VUMPS API smoke test" begin
        settings = load_settings(joinpath(PROJECT_ROOT, "configs", "pilot_yc6_1.toml"))
        psi = build_product_state(settings)
        hamiltonian = build_hamiltonian(settings.model, PB.siteinds(psi), 0.0)
        optimizer = OptimizerSettings(
            maxdim=2,
            cutoff=1e-8,
            residual_tol=1e-2,
            max_iterations=1,
            max_growth_steps=1,
            record_krylov_diagnostics=true,
        )
        expanded = PB.subspace_expansion(psi, hamiltonian; maxdim=2, cutoff=1e-8)
        optimized, diagnostic = PB.run_vumps_iterations(
            hamiltonian,
            expanded,
            optimizer;
            output_level=0,
        )
        @test diagnostic.iterations == 1
        @test isfinite(diagnostic.residual)
        @test !isempty(diagnostic.krylov_solves)
        @test Set(record.solve_kind for record in diagnostic.krylov_solves) == Set([
            "environment_left",
            "environment_right",
            "center_C",
            "center_AC",
        ])
        parallel_optimizer = OptimizerSettings(
            maxdim=2,
            cutoff=1e-8,
            residual_tol=1e-2,
            max_iterations=1,
            max_growth_steps=1,
            record_krylov_diagnostics=true,
            multisite_update_alg="parallel",
            restore_best_on_failure=true,
        )
        _, parallel_diagnostic = PB.run_vumps_iterations(
            hamiltonian,
            expanded,
            parallel_optimizer;
            output_level=0,
        )
        @test parallel_diagnostic.iterations == 1
        @test isfinite(parallel_diagnostic.residual)
        @test parallel_diagnostic.terminal_residual == parallel_diagnostic.residual
        @test parallel_diagnostic.best_iteration == 1
        @test parallel_diagnostic.returned_iteration == 1
        @test !parallel_diagnostic.restored_best_on_failure
        @test !isempty(parallel_diagnostic.krylov_solves)
        neutral = compute_transfer_spectrum(
            optimized;
            physical_sz=0.0,
            neigs=2,
            tolerance=1e-6,
            krylov_dimension=8,
            random_seed=1,
        )
        triplet = compute_transfer_spectrum(
            optimized;
            physical_sz=1.0,
            neigs=1,
            tolerance=1e-6,
            krylov_dimension=8,
            random_seed=1,
        )
        @test length(neutral.inverse_xi) == 2
        @test triplet.raw_qn_sz == 2
        @test triplet.flux_labels == ["QN(\"Sz\",2)"]
    end
end
