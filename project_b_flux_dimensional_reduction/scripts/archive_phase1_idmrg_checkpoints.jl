using Dates
using HDF5
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB

2 <= length(ARGS) <= 3 || error(
    "usage: archive_phase1_idmrg_checkpoints.jl PACKAGE_DIRECTORY " *
    "/pscratch/.../RUN_DIRECTORY [--prune-source]",
)
package = abspath(ARGS[1])
scratch_run_directory = abspath(ARGS[2])
prune_source = length(ARGS) == 3
prune_source && ARGS[3] != "--prune-source" && error("unknown option: $(ARGS[3])")
startswith(scratch_run_directory, "/pscratch/") ||
    error("destination must be an explicit Perlmutter /pscratch path")
scratch_run_directory != "/pscratch" || error("refusing broad scratch target")
prune_source && get(ENV, "PROJECT_B_IDMRG_PRUNE_AUTHORIZED", "NO") != "YES" && error(
    "set PROJECT_B_IDMRG_PRUNE_AUTHORIZED=YES only after inspecting the verified archive",
)

source_directory = joinpath(package, "checkpoints")
isdir(source_directory) || error("missing source checkpoint directory: $source_directory")
destination_directory = joinpath(scratch_run_directory, "checkpoints")
mkpath(destination_directory)

source_paths = sort!(filter(
    path -> endswith(path, ".h5"),
    readdir(source_directory; join=true),
))
isempty(source_paths) && error("no source checkpoints found")
records = NamedTuple[]
for source in source_paths
    source_hash = PB.file_sha256(source)
    destination = joinpath(destination_directory, basename(source))
    if isfile(destination)
        PB.file_sha256(destination) == source_hash || error(
            "existing scratch checkpoint hash mismatch: $destination",
        )
    else
        cp(source, destination; force=false, follow_symlinks=false)
    end
    destination_hash = PB.file_sha256(destination)
    destination_hash == source_hash || error("copy verification failed: $destination")
    iteration = h5open(source, "r") do file
        String(read(file, "artifact_kind")) == "project_b_mpskit_idmrg_checkpoint" ||
            error("unexpected checkpoint artifact: $source")
        Int(read(file, "iteration"))
    end
    push!(records, (;
        name=basename(source),
        source,
        destination,
        sha256=source_hash,
        bytes=Int(stat(source).size),
        iteration,
    ))
end

manifest_path = joinpath(package, "checkpoint_archive_manifest.h5")
if isfile(manifest_path)
    h5open(manifest_path, "r") do file
        String(read(file, "artifact_kind")) ==
            "project_b_idmrg_checkpoint_archive_manifest" ||
            error("unexpected archive manifest kind")
        String.(read(file, "checkpoints/sha256")) ==
            [record.sha256 for record in records] ||
            error("existing archive manifest does not match the source checkpoints")
        String.(read(file, "checkpoints/scratch_path")) ==
            [record.destination for record in records] ||
            error("existing archive manifest points to a different scratch destination")
    end
else
    result_path = joinpath(package, "idmrg_result_bridge.h5")
    lightweight_path = joinpath(package, "idmrg_result_lightweight.h5")
    isfile(result_path) || error("missing restartable result bridge")
    isfile(lightweight_path) || error("create the lightweight archive before migration")
    try
        h5open(manifest_path * ".tmp", "w") do file
            file["schema_version"] = 1
            file["artifact_kind"] = "project_b_idmrg_checkpoint_archive_manifest"
            file["created_at_utc"] = string(now(UTC))
            file["source/package_directory"] = package
            file["source/result_path"] = result_path
            file["source/result_sha256"] = PB.file_sha256(result_path)
            file["source/lightweight_path"] = lightweight_path
            file["source/lightweight_sha256"] = PB.file_sha256(lightweight_path)
            file["scratch/run_directory"] = scratch_run_directory
            file["scratch/purge_semantics"] =
                "temporary working storage; subject to NERSC purge and not a backup"
            file["checkpoints/count"] = length(records)
            file["checkpoints/name"] = [record.name for record in records]
            file["checkpoints/source_path"] = [record.source for record in records]
            file["checkpoints/scratch_path"] = [record.destination for record in records]
            file["checkpoints/sha256"] = [record.sha256 for record in records]
            file["checkpoints/bytes"] = [record.bytes for record in records]
            file["checkpoints/iteration"] = [record.iteration for record in records]
            file["payload/checkpoint_tensors_included"] = false
            file["payload/solver_serialization_included"] = false
        end
        mv(manifest_path * ".tmp", manifest_path)
    catch
        isfile(manifest_path * ".tmp") && rm(manifest_path * ".tmp"; force=true)
        rethrow()
    end
end

if prune_source
    for record in records
        PB.file_sha256(record.destination) == record.sha256 ||
            error("scratch verification changed before pruning: $(record.destination)")
    end
    for record in records
        rm(record.source)
    end
    isempty(readdir(source_directory)) && rm(source_directory)
    println("Pruned verified home checkpoint copies; restart data remain under scratch.")
else
    println("Copied and verified checkpoints; home copies were not pruned.")
end
println("Archive manifest: $manifest_path")
println("Archive manifest SHA-256: $(PB.file_sha256(manifest_path))")
println("Scratch checkpoint directory: $destination_directory")
println("Checkpoint bytes: $(sum(record.bytes for record in records))")
