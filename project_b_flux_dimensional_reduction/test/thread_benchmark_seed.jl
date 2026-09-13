# One real saved-state export; no optimization or transfer solve.
using Test
include("../scripts/thread_benchmark/Seed.jl")
const S=ThreadBenchmarkSeed
length(ARGS)==1 || error("provide a fresh local validation directory")
directory=abspath(only(ARGS)); ispath(directory) && error("validation directory exists")
parent=joinpath(S.C.ROOT,"output/phase1/yc8_1/primary_forward_chi512_legacy_0p1/seed_101/chi512/states/state_0001_yc8-1_primary_forward_chi512_legacy_0p1_independent_theta0_alternating_chi512_forward_seed101_chi512_theta_p0p00000000_accepted_12126bd1b66b.h5")
expected="95255fbe3a590505902bd0061d7d9d9f14f8ecd7ca3e4eac1aacfc5c7fe72d0b"
exported=S.export_al(joinpath(directory,"real_seed_al.h5"),parent,expected,repeat("f",64))
@test exported.source.maxlinkdim==512
@test S.C.sha(parent)==expected
println("Real chi512 zero-flux seed exported without optimization.")
