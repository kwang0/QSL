using HDF5
using ITensors
using Test
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
    @test isabspath(settings.runtime.output_directory)
    @test PB.validate_flux_order(settings.scan.fluxes_over_pi)
    @test_throws ArgumentError PB.validate_flux_order([0.0, 0.5, 0.25])
    @test_throws ArgumentError PB.validate_flux_order([0.0, 0.0])
    @test count(==("Up"), PB.balanced_seed_states(6, "block", 1)) == 3
    @test_throws ArgumentError PB.balanced_seed_states(5, "alternating", 1)
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

@testset "Product-state construction and immutable HDF5 state" begin
    settings = load_settings(joinpath(PROJECT_ROOT, "configs", "pilot_yc6_1.toml"))
    psi = build_product_state(settings)
    @test PB.maxlinkdim(psi) == 1
    @test PB.nsites(psi) == 2
    hamiltonian = build_hamiltonian(settings.model, PB.siteinds(psi), 0.0)
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
    )
    mktempdir() do directory
        path = joinpath(directory, "state.h5")
        PB.write_state_file(path, settings, psi, hamiltonian, diagnostic, 0.0, 1)
        @test isfile(path)
        state = PB.read_state_file(path)
        @test state.circumference == 6
        @test state.shift == 1
        @test state.converged
        @test state.continuation_accepted
        @test state.J2 == settings.model.J2
        h5open(path, "r") do file
            @test haskey(file, "geometry/bonds")
            @test read(file, "geometry/mps_period") == 2
            @test read(file, "geometry/minimal_mps_period") == 2
            @test read(file, "geometry/unit_cell_is_minimal")
            @test read(file, "model/twist_gauge") == "uniform"
            @test haskey(file, "observables/schmidt_probabilities")
            @test haskey(file, "optimizer/residual_history")
            @test haskey(file, "psi")
        end
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
