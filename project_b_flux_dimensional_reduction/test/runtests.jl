using HDF5
using ITensors
using Test
using TOML
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))

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
    end
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
    @test !PB.minimum_step_bracket_reached(0.1875, 0.25, 0.03125)
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
    @test !PB.fixed_flux_optimizer_resume_requested(
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
        @test outcome["artifact_kind"] == "project_b_fixed_flux_expansion_outcome"
        @test outcome["status"] == "fixed_flux_expansion_numerical_failure"
        @test outcome["classification"] ==
            "iteration_limit_stalled_not_physical_endpoint"
        @test outcome["theta_over_pi"] == 0.2421875
        @test outcome["source_maxdim"] == 128
        @test outcome["requested_maxdim"] == 192
        @test outcome["result_maxdim"] == 192
        @test outcome["optimizer_max_iterations"] == 360
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
    end
end

@testset "Residual trend and plateau classification" begin
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
            @test read(file, "schema_version") == 6
            @test haskey(file, "geometry/bonds")
            @test read(file, "geometry/mps_period") == 2
            @test read(file, "geometry/minimal_mps_period") == 2
            @test read(file, "geometry/unit_cell_is_minimal")
            @test read(file, "model/twist_gauge") == "uniform"
            @test haskey(file, "observables/schmidt_probabilities")
            @test haskey(file, "optimizer/residual_history")
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
        @test length(summary_rows) == 4
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
