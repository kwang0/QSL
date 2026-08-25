@testset "iDMRG native failure skips ITensor promotion conversion" begin
    mktempdir() do directory
        control_path = joinpath(directory, "control.toml")
        control = Dict{String,Any}(
            "lineage" => Dict(
                "branch" => "primary_forward_chi512_legacy_0p1",
                "direction" => "forward",
            ),
            "model" => Dict(
                "circumference" => 8,
                "shift" => 1,
                "mps_period" => 2,
                "J1" => 1.0,
                "J2" => 0.12,
                "Delta1" => 1.0,
                "Delta2" => 1.0,
                "Bz" => 0.0,
                "twist_gauge" => "uniform",
            ),
            "native_convergence" => Dict(
                "minimum_iterations" => 4,
                "energy_window" => 4,
                "environment_tolerance" => 1e-8,
                "energy_density_span_tolerance" => 1e-9,
                "require_achieved_bond_dimension" => 512,
            ),
        )
        open(control_path, "w") do io
            TOML.print(io, control; sorted=true)
        end
        control_sha = PB.file_sha256(control_path)
        result_path = joinpath(directory, "result.h5")
        fixed_point_change = [4e-6, 3e-6, 2e-6, 1e-6]
        energy = [-0.5, -0.5000000001, -0.5000000002, -0.5000000003]
        h5open(result_path, "w") do file
            file["schema_version"] = 2
            file["artifact_kind"] = "project_b_mpskit_idmrg_result_bridge"
            file["mpskit_version"] = "0.13.13"
            file["control_path"] = "/remote/$(basename(control_path))"
            file["control_sha256"] = control_sha
            file["source_bridge_path"] = "/remote/bridge.h5"
            file["source_bridge_sha256"] = repeat("b", 64)
            file["lineage/parent_state_path"] = "/remote/accepted.h5"
            file["lineage/parent_state_sha256"] =
                "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
            file["lineage/parent_theta_over_pi"] = 0.15
            file["lineage/target_theta_over_pi"] = 0.2
            file["lineage/numerical_seed_kind"] = "rejected_nonconverged_idmrg_result"
            file["lineage/numerical_seed_path"] = "/remote/seed.h5"
            file["lineage/numerical_seed_sha256"] = repeat("c", 64)
            file["optimizer/converged"] = false
            file["optimizer/iterations"] = 4
            file["optimizer/final_environment_error"] = last(fixed_point_change)
            file["optimizer/history/iteration"] = collect(1:4)
            file["optimizer/history/environment_error"] = fixed_point_change
            file["optimizer/history/energy_density"] = energy
            file["optimizer/history/energy_density_delta"] = energy
            file["optimizer/history/cumulative_superblock_energy_per_site"] = energy
            file["optimizer/history/discarded_weight"] = zeros(4)
            file["optimizer/history/maximum_bond_dimension"] = fill(512, 4)
            file["optimizer/history/elapsed_seconds"] = ones(4)
            file["validation/itensor_mpskit_seed_energy_density_difference"] = 1e-12
            file["validation/model_energy_density_tolerance"] = 1e-6
            # Deliberately omit all state tensors. Native rejection must happen first.
        end
        result_sha = PB.file_sha256(result_path)
        output_directory = joinpath(directory, "analysis")
        missing_parent = joinpath(directory, "intentionally_missing_parent.h5")
        run(`$(Base.julia_cmd()) --startup-file=no --project=$PROJECT_ROOT \
            $(joinpath(PROJECT_ROOT, "scripts/analyze_phase1_idmrg_result.jl")) \
            $result_path $missing_parent $output_directory`)
        output_path = joinpath(
            output_directory,
            "analysis_idmrg_theta_p0p20000000_chi512_rejected_$(first(result_sha, 12)).h5",
        )
        @test isfile(output_path)
        h5open(output_path, "r") do file
            @test String(read(file, "analysis/stage")) == "native_only"
            @test !Bool(read(file, "continuation_accepted"))
            @test !Bool(read(file, "optimizer/converged"))
            @test !Bool(read(file, "analysis/post_native_itensor_conversion_ran"))
            @test String(read(file, "continuation/status")) ==
                "not_evaluated_after_native_failure"
            @test !haskey(file, "observables")
            @test !haskey(file, "psi")
        end
    end
end
