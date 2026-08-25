@testset "benchmark accounting analysis" begin
    mktempdir() do directory
        project_root = normpath(joinpath(@__DIR__, "../.."))
        result_directory = joinpath(directory, "results")
        mkpath(result_directory)
        control_path = joinpath(directory, "benchmark_control.toml")
        science_control_path = joinpath(directory, "science_control.toml")
        bridge_path = joinpath(directory, "bridge.h5")
        seed_path = joinpath(directory, "seed.h5")
        write(science_control_path, "science control")
        write(bridge_path, "bridge")
        write(seed_path, "result seed")
        seed_sha = ProjectBIDMRG.file_sha256(seed_path)
        parent_sha = repeat("e", 64)
        control = Dict{String,Any}(
            "artifact_kind" => "project_b_phase1_idmrg_benchmark_control",
            "benchmark" => Dict(
                "julia_threads" => [2, 4, 8, 16],
                "warmup_iterations" => 1,
                "total_iterations" => 5,
            ),
            "resources" => Dict("memory" => "16G"),
            "storage" => Dict("result_directory" => "results"),
            "validation" => Dict(
                "maximum_rss_gib" => 16.0,
                "required_discarded_weight" => 0.0,
                "required_bond_dimension" => 512,
                "maximum_final_energy_density_spread" => 1e-8,
                "maximum_final_bond_matrix_update_norm_relative_spread" => 0.10,
            ),
            "sources" => Dict(
                "result_bridge_sha256" => seed_sha,
                "accepted_parent_sha256" => parent_sha,
            ),
        )
        open(control_path, "w") do io
            TOML.print(io, control; sorted=true)
        end
        measured_seconds = Dict(2 => 100.0, 4 => 60.0, 8 => 40.0, 16 => 35.0)
        for (step, threads) in enumerate((2, 4, 8, 16))
            result_path = joinpath(result_directory, "benchmark_threads_$(threads).h5")
            history = (;
                iteration=collect(1:5),
                environment_error=
                    [5e-6, 4e-6, 3e-6, 2e-6, 1e-6 * (1 + threads * 1e-4)],
                energy_density=
                    [-0.5, -0.5001, -0.5002, -0.5003, -0.510215 + threads * 1e-11],
                cumulative_superblock_energy_per_site=
                    [-0.5, -1.0001, -1.5003, -2.0006, -2.510815],
                discarded_weight=zeros(5),
                maximum_bond_dimension=fill(512, 5),
                elapsed_seconds=[120.0; fill(measured_seconds[threads], 4)],
            )
            benchmark_run = (;
                control_record=(; path=science_control_path),
                bridge=(; path=bridge_path, parent_sha256=parent_sha),
                result_seed=(; path=seed_path, sha256=seed_sha),
                history,
                iteration_cpu_seconds=fill(20.0, 5),
                initialization_elapsed_seconds=10.0,
                initialization_cpu_seconds=8.0,
                initial_fixed_point_change=6e-6,
                initial_cumulative_energy_per_site=-0.49,
                total_iterations=5,
                warmup_iterations=1,
                measured_iterations=4,
                threads,
                slurm_cpus_per_thread=2,
                runtime_julia_threads=threads,
                runtime_kernel="Linux",
                runtime_architecture="x86_64",
            )
            withenv("SLURM_JOB_ID" => "999", "SLURM_STEP_ID" => string(step - 1)) do
                ProjectBIDMRG.write_benchmark_result(
                    result_path,
                    benchmark_run,
                    control_path,
                )
            end
            h5open(result_path, "r") do file
                @test Int(read(file, "schema_version")) == 2
                @test UInt8.(read(file, "benchmark/measured_mask")) ==
                    UInt8[0, 1, 1, 1, 1]
            end
        end
        sacct_path = joinpath(directory, "sacct.tsv")
        open(sacct_path, "w") do io
            println(io, "JobIDRaw|JobName|State|ElapsedRaw|Elapsed|TimelimitRaw|NNodes|NCPUS|AllocCPUS|TotalCPU|AveCPU|MaxRSS|AveRSS|ExitCode")
            println(io, "999|bench|COMPLETED|600|00:10:00|5400|1|32|32|00:10:00||| |0:0")
            for (step, threads) in enumerate((2, 4, 8, 16))
                cpus = 2 * threads
                println(io, "999.$(step - 1)|t$threads|COMPLETED|100|00:01:40|5400|1|$cpus|$cpus|00:05:00|00:00:00|10G|10G|0:0")
            end
        end
        output_path = joinpath(directory, "analysis.toml")
        run(`$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(project_root, "idmrg")) \
            $(joinpath(project_root, "scripts/analyze_phase1_idmrg_benchmark.jl")) \
            $control_path 999 $sacct_path $output_path`)
        analysis = TOML.parsefile(output_path)
        @test analysis["all_settings_valid"]
        @test analysis["trajectory_consistent"]
        @test analysis["recommendation"]["status"] == "ready"
        @test analysis["recommendation"]["julia_threads"] == 4
        @test length(analysis["settings"]) == 4
    end
end
