using ProjectBIDMRG
using Test
using HDF5
using MPSKit
using TensorKit
using TOML

@testset "Julia 1.12 benchmark process timing" begin
    before = ProjectBIDMRG.process_cpu_seconds()
    measurement = ProjectBIDMRG.benchmark_timing_preflight()
    after = ProjectBIDMRG.process_cpu_seconds()
    @test isfinite(before)
    @test isfinite(after)
    @test after >= before
    @test measurement.elapsed_seconds >= 0
    @test measurement.cpu_seconds > 0
    @test isfinite(measurement.value)
end

@testset "benchmark result HDF5 I/O" begin
    io = ProjectBIDMRG.benchmark_result_io_preflight()
    @test io.bytes > 0
    @test io.mask == UInt8[0, 1]
end

@testset "U(1) bridge basis" begin
    charges = [1, -1, -1, 3]
    space = ProjectBIDMRG.u1space(charges)
    target = ProjectBIDMRG.tensor_basis_charges(space)
    permutation = ProjectBIDMRG.basis_permutation(charges, target)
    @test charges[permutation] == target
    @test sort(permutation) == collect(eachindex(charges))
end

@testset "pinned IDMRG iterator checkpoint" begin
    physical = ℂ^2
    virtual = ℂ^2
    state = InfiniteMPS([physical, physical], [virtual, virtual]; tol=1e-10)
    sz = TensorMap(ComplexF64[0.5 0; 0 -0.5], physical ← physical)
    interaction = sz ⊗ sz
    hamiltonian = InfiniteMPOHamiltonian(
        fill(physical, 2),
        [(1, 2) => interaction, (2, 3) => interaction],
    )
    algorithm = IDMRG(tol=1e-8, maxiter=1, verbosity=0)
    solver = ProjectBIDMRG.initial_solver(state, hamiltonian, algorithm)
    value = iterate(solver)
    @test value !== nothing
    (_, _, epsilon, delta), _ = value
    history = ProjectBIDMRG.history_buffers()
    ProjectBIDMRG.append_history!(
        history, solver.state.iter, epsilon, solver.state.energy, delta,
        solver.state.mps, 0.0,
    )
    @test history.energy_density == history.energy_density_delta
    @test only(history.energy_density) == Float64(real(delta) / length(solver.state.mps))
    @test only(history.cumulative_superblock_energy_per_site) ==
        Float64(real(solver.state.energy) / length(solver.state.mps))
    mktempdir() do directory
        checkpoint = ProjectBIDMRG.write_checkpoint(
            directory, solver, history, repeat("a", 64), repeat("b", 64),
        )
        @test isfile(checkpoint.path)
        resumed, resumed_history = ProjectBIDMRG.resume_solver(
            checkpoint.path, repeat("a", 64), repeat("b", 64),
        )
        @test resumed.state.iter == solver.state.iter
        @test resumed_history.iteration == history.iteration
        @test resumed_history.energy_density == history.energy_density
        @test resumed_history.cumulative_superblock_energy_per_site ==
            history.cumulative_superblock_energy_per_site

        control_path = joinpath(directory, "control.toml")
        bridge_path = joinpath(directory, "bridge.h5")
        result_path = joinpath(directory, "result.h5")
        write(control_path, "test control")
        write(bridge_path, "test bridge")
        write(result_path, "small restartable result")
        run = (;
            control_record=(; path=control_path),
            bridge=(;
                path=bridge_path,
                parent_path="accepted.h5",
                parent_sha256=repeat("c", 64),
                root_sha256=repeat("c", 64),
                root_theta=0.15,
                numerical_seed_kind="rejected_nonconverged_idmrg_result",
                numerical_seed_path="seed.h5",
                numerical_seed_sha256=repeat("d", 64),
            ),
            converged=false,
            solver,
            history,
            checkpoints=[checkpoint],
        )
        result = (;
            path=result_path,
            sha256=ProjectBIDMRG.file_sha256(result_path),
        )
        lightweight = ProjectBIDMRG.write_lightweight_archive(
            joinpath(directory, "lightweight.h5"),
            run,
            result,
        )
        @test lightweight.bytes < 100_000
        h5open(lightweight.path, "r") do file
            @test String(read(file, "artifact_kind")) ==
                "project_b_mpskit_idmrg_lightweight_archive"
            @test !Bool(read(file, "payload/full_state_included"))
            @test !Bool(read(file, "payload/solver_serialization_included"))
            @test !haskey(file, "state")
            @test !haskey(file, "solver_serialization")
            @test String.(read(file, "checkpoints/sha256")) == [checkpoint.sha256]
        end
    end
end

@testset "native convergence" begin
    history = (
        iteration=collect(1:4),
        environment_error=[1e-3, 1e-5, 1e-7, 1e-9],
        energy_density=[-0.5, -0.5000001, -0.50000011, -0.500000111],
        maximum_bond_dimension=fill(512, 4),
    )
    control = Dict("native_convergence" => Dict(
        "minimum_iterations" => 4,
        "energy_window" => 3,
        "environment_tolerance" => 1e-8,
        "energy_density_span_tolerance" => 1e-6,
    ))
    @test ProjectBIDMRG.native_converged(history, control)
    history.environment_error[end] = 1e-6
    @test !ProjectBIDMRG.native_converged(history, control)
end

@testset "rejected result benchmark seed" begin
    mktempdir() do directory
        bridge_path = joinpath(directory, "source_bridge.h5")
        write(bridge_path, "immutable source bridge")
        charges = [1, -1]
        tensors = [
            (;
                data=zeros(ComplexF64, 2, 2, 2),
                left_charges=charges,
                physical_charges=charges,
                right_charges=charges,
            ) for _ in 1:2
        ]
        parent_sha = repeat("a", 64)
        source_bridge = (;
            path=bridge_path,
            parent_sha256=parent_sha,
            target_theta=0.2,
            period=2,
            tensors,
            numerical_seed_kind="older_seed",
            numerical_seed_path="older.h5",
            numerical_seed_sha256=repeat("b", 64),
            numerical_seed_theta=0.2,
        )
        result_path = joinpath(directory, "result.h5")
        h5open(result_path, "w") do file
            file["schema_version"] = 2
            file["artifact_kind"] = "project_b_mpskit_idmrg_result_bridge"
            file["mpskit_version"] = string(Base.pkgversion(MPSKit))
            file["source_bridge_sha256"] = ProjectBIDMRG.file_sha256(bridge_path)
            file["control_sha256"] = repeat("c", 64)
            file["lineage/parent_state_sha256"] = parent_sha
            file["lineage/target_theta_over_pi"] = 0.2
            file["optimizer/converged"] = false
            file["optimizer/iterations"] = 2
            file["optimizer/final_environment_error"] = 1e-5
            file["optimizer/history/environment_error"] = [2e-5, 1e-5]
            file["optimizer/history/energy_density"] = [-0.5, -0.5001]
            file["optimizer/history/discarded_weight"] = [0.0, 0.0]
            file["optimizer/history/maximum_bond_dimension"] = [512, 512]
            for site in 1:2
                prefix = "state/site_$site"
                file["$prefix/AL"] = tensors[site].data
                file["$prefix/left_charges"] = charges
                file["$prefix/physical_charges"] = charges
                file["$prefix/right_charges"] = charges
            end
        end
        result_sha = ProjectBIDMRG.file_sha256(result_path)
        record = ProjectBIDMRG.load_result_seed(result_path, result_sha, source_bridge)
        @test record.sha256 == result_sha
        @test record.iterations == 2
        @test record.final_fixed_point_change == 1e-5
        @test record.seed.parent_sha256 == parent_sha
        @test record.seed.numerical_seed_sha256 == result_sha
        @test record.seed.numerical_seed_kind == "rejected_nonconverged_idmrg_result"
        @test record.seed.tensors[1].left_charges == charges
    end
end

include("test_benchmark_analysis.jl")
