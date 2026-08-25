using ProjectBIDMRG

isempty(ARGS) || error("usage: preflight_benchmark_runtime.jl")

measurement = ProjectBIDMRG.benchmark_timing_preflight()
io = ProjectBIDMRG.benchmark_result_io_preflight()
println("Benchmark executable timing preflight passed")
println("  Julia version: ", VERSION)
println("  kernel/architecture: ", Sys.KERNEL, "/", Sys.ARCH)
println("  MPSKit version: ", Base.pkgversion(ProjectBIDMRG.MPSKit))
println("  HDF5 version: ", Base.pkgversion(ProjectBIDMRG.HDF5))
println("  TensorKit version: ", Base.pkgversion(ProjectBIDMRG.TensorKit))
println("  wall seconds: ", measurement.elapsed_seconds)
println("  process CPU seconds: ", measurement.cpu_seconds)
println("Benchmark executable HDF5-result preflight passed")
println("  result bytes: ", io.bytes)
println("  measured mask: ", io.mask)
