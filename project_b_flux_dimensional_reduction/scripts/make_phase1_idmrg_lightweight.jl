using Dates
using HDF5
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const FIRST_RESULT_SHA256 =
    "527afdf421e3411fb91f622ae0a5f8764d453f892c7752b2294913813749c8de"
const FIRST_CONTROL_SHA256 =
    "3eb0d1c9209c978f277b6704de39bc899cf2a8abce0c84f950fb204febca8369"
const FIRST_BRIDGE_SHA256 =
    "df1e402f0922937da0e266427a2bae7ce7de0fc844884ae3f747f5410fcd7d01"
const FIRST_ANALYSIS_SHA256 =
    "84730a3d0e67f2c4a6e09372c407a9d5d0e806d0357d8d6c6b712cf6aafb7a2c"

length(ARGS) == 1 || error("usage: make_phase1_idmrg_lightweight.jl PACKAGE_DIRECTORY")
package = abspath(ARGS[1])
control_path = joinpath(package, "phase1_idmrg_control.toml")
bridge_path = joinpath(package, "accepted_parent_to_mpskit_bridge.h5")
result_path = joinpath(package, "idmrg_result_bridge.h5")
analysis_path = joinpath(
    package,
    "analysis/analysis_idmrg_theta_p0p20000000_chi512_rejected_527afdf421e3.h5",
)
for (path, expected) in (
    control_path => FIRST_CONTROL_SHA256,
    bridge_path => FIRST_BRIDGE_SHA256,
    result_path => FIRST_RESULT_SHA256,
    analysis_path => FIRST_ANALYSIS_SHA256,
)
    PB.file_sha256(path) == expected || error("immutable source hash mismatch: $path")
end

checkpoint_directory = joinpath(package, "checkpoints")
checkpoint_paths = sort!(filter(
    path -> endswith(path, ".h5"),
    readdir(checkpoint_directory; join=true),
))
length(checkpoint_paths) == 16 || error("expected 16 first-run checkpoints")
checkpoint_records = map(checkpoint_paths) do path
    iteration = h5open(path, "r") do file
        String(read(file, "artifact_kind")) == "project_b_mpskit_idmrg_checkpoint" ||
            error("unexpected checkpoint artifact: $path")
        String(read(file, "control_sha256")) == FIRST_CONTROL_SHA256 ||
            error("checkpoint control hash mismatch: $path")
        String(read(file, "bridge_sha256")) == FIRST_BRIDGE_SHA256 ||
            error("checkpoint bridge hash mismatch: $path")
        Int(read(file, "iteration"))
    end
    return (;
        name=basename(path),
        path,
        sha256=PB.file_sha256(path),
        bytes=Int(stat(path).size),
        iteration,
    )
end

native = h5open(result_path, "r") do file
    return (;
        converged=Bool(read(file, "optimizer/converged")),
        iterations=Int(read(file, "optimizer/iterations")),
        final_environment_error=Float64(read(file, "optimizer/final_environment_error")),
        iteration=Int.(read(file, "optimizer/history/iteration")),
        environment_error=Float64.(read(file, "optimizer/history/environment_error")),
        energy_density=Float64.(read(file, "optimizer/history/energy_density_delta")),
        cumulative_superblock_energy_per_site=Float64.(read(
            file,
            "optimizer/history/energy_density",
        )),
        discarded_weight=Float64.(read(file, "optimizer/history/discarded_weight")),
        maximum_bond_dimension=Int.(read(
            file,
            "optimizer/history/maximum_bond_dimension",
        )),
        elapsed_seconds=Float64.(read(file, "optimizer/history/elapsed_seconds")),
        parent_path=String(read(file, "lineage/parent_state_path")),
        parent_sha256=String(read(file, "lineage/parent_state_sha256")),
    )
end

output_path = joinpath(package, "idmrg_result_lightweight.h5")
ispath(output_path) && error("refusing to overwrite lightweight archive: $output_path")
try
    h5open(output_path * ".tmp", "w") do file
        file["schema_version"] = 1
        file["artifact_kind"] = "project_b_mpskit_idmrg_lightweight_archive"
        file["created_at_utc"] = string(now(UTC))
        file["control/path"] = control_path
        file["control/sha256"] = FIRST_CONTROL_SHA256
        file["source_bridge/path"] = bridge_path
        file["source_bridge/sha256"] = FIRST_BRIDGE_SHA256
        file["lineage/accepted_parent_path"] = native.parent_path
        file["lineage/accepted_parent_sha256"] = native.parent_sha256
        file["lineage/numerical_seed_kind"] = "accepted_parent"
        file["lineage/numerical_seed_sha256"] = native.parent_sha256
        file["result/path"] = result_path
        file["result/sha256"] = FIRST_RESULT_SHA256
        file["result/bytes"] = Int(stat(result_path).size)
        file["analysis/path"] = analysis_path
        file["analysis/sha256"] = FIRST_ANALYSIS_SHA256
        file["optimizer/converged"] = native.converged
        file["optimizer/iterations"] = native.iterations
        file["optimizer/final_environment_error"] = native.final_environment_error
        file["optimizer/history/iteration"] = native.iteration
        file["optimizer/history/environment_error"] = native.environment_error
        file["optimizer/history/energy_density"] = native.energy_density
        file["optimizer/history/cumulative_superblock_energy_per_site"] =
            native.cumulative_superblock_energy_per_site
        file["optimizer/history/discarded_weight"] = native.discarded_weight
        file["optimizer/history/maximum_bond_dimension"] = native.maximum_bond_dimension
        file["optimizer/history/elapsed_seconds"] = native.elapsed_seconds
        file["checkpoints/count"] = length(checkpoint_records)
        file["checkpoints/name"] = [record.name for record in checkpoint_records]
        file["checkpoints/source_path"] = [record.path for record in checkpoint_records]
        file["checkpoints/sha256"] = [record.sha256 for record in checkpoint_records]
        file["checkpoints/bytes"] = [record.bytes for record in checkpoint_records]
        file["checkpoints/iteration"] = [record.iteration for record in checkpoint_records]
        file["checkpoints/storage_status"] =
            "legacy package-directory copies; migrate to PSCRATCH before pruning home"
        file["payload/full_state_included"] = false
        file["payload/solver_serialization_included"] = false
        file["payload/semantics"] =
            "copy_data-style compact record; full result remains a separate 16 MiB seed"
    end
    mv(output_path * ".tmp", output_path)
catch
    isfile(output_path * ".tmp") && rm(output_path * ".tmp"; force=true)
    rethrow()
end

println("Wrote lightweight first-run archive: $output_path")
println("Lightweight archive SHA-256: $(PB.file_sha256(output_path))")
println("Lightweight archive bytes: $(stat(output_path).size)")
println("Checkpoint bytes represented: $(sum(record.bytes for record in checkpoint_records))")
