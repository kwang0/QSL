# Local integration test; the producer canonicalizes but runs no optimization.
using TOML, Test
length(ARGS)==2 || error("usage: test/pilot_roundtrip.jl CONTROL FIXTURE_MANIFEST")
fixture_manifest=abspath(ARGS[2])
fixture_record=TOML.parsefile(fixture_manifest)
fixture_record["fixture_only"] && !fixture_record["optimization_performed"] || error("not an identity fixture")
include(joinpath(@__DIR__,"../scripts/analyze_mpskit_solver_pilot.jl"))
summary=TOML.parsefile(joinpath(dirname(fixture_manifest),"analysis_identity_fixture.toml"))
@testset "Accepted-parent common representation round trip" begin
    @test summary["energy_equivalence_passed"]
    @test summary["multimetric_continuity_passed"]
    @test summary["overlap_per_site"]>0.999999
    @test summary["maximum_cut_entropy_jump"]<1e-3
    @test !summary["native_gate_passed"]
    @test !summary["continuation_accepted"]
end
