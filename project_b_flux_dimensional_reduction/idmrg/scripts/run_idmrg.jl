using ProjectBIDMRG

2 <= length(ARGS) <= 3 || error(
    "usage: run_idmrg.jl CONTROL.toml RESULT.h5 [CHECKPOINT.h5]",
)

control_path = abspath(ARGS[1])
result_path = abspath(ARGS[2])
resume_path = length(ARGS) == 3 ? abspath(ARGS[3]) : nothing
checkpoint_override = get(ENV, "PROJECT_B_IDMRG_CHECKPOINT_DIRECTORY", nothing)
run = ProjectBIDMRG.run_control(
    control_path;
    resume=resume_path,
    checkpoint_directory_override=checkpoint_override,
)
result = ProjectBIDMRG.write_result(result_path, run)
storage = run.control_record.raw["storage"]
lightweight = if haskey(storage, "lightweight_result_path")
    value = String(storage["lightweight_result_path"])
    lightweight_path = isabspath(value) ? value :
        normpath(joinpath(dirname(run.control_record.path), value))
    ProjectBIDMRG.write_lightweight_archive(lightweight_path, run, result)
else
    nothing
end
println("iDMRG native convergence: ", run.converged)
println("immutable result: ", result.path)
println("result SHA-256: ", result.sha256)
if lightweight !== nothing
    println("lightweight archive: ", lightweight.path)
    println("lightweight archive SHA-256: ", lightweight.sha256)
end
