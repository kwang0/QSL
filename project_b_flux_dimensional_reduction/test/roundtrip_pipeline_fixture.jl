# Synthetic interrupted RETURN at unchanged theta. Full chi512 identity tensors;
# no optimization or scientific continuation is performed by this fixture.
using Test, HDF5, TOML
include("../scripts/roundtrip/Analysis.jl")
const A=RoundTripAnalysis
const C=A.C
length(ARGS)==3 || error("usage: roundtrip_pipeline_fixture.jl CONTROL OLD_IDENTITY_MANIFEST NEW_DIRECTORY")
control,identity,output=abspath.(ARGS); c=C.validate(control); hash=C.sha(control)
old=TOML.parsefile(identity)
old["fixture_only"] && !old["optimization_performed"] || error("identity fixture required")
ispath(output) && error("fixture exists"); mkpath(output)
original=joinpath(output,"origin.h5"); cp(old["result_path"],original)
h5open(original,"r+") do f
    write(f["control_sha256"],hash); f["fixture_only"]=true
end
origin=Dict("iteration"=>0,"path"=>original,"sha256"=>C.sha(original),"theta_over_pi"=>.15)
arm="n2_grid1"; label=arm*"_point8"
C.write_toml(joinpath(output,arm*"_origin.toml"),Dict("control_sha256"=>hash,"parent_sha256"=>c["recipe"]["parent_sha256"],
    "payload"=>origin,"history"=>old["history"],"fixture_only"=>true))
returned=joinpath(output,"returned.h5"); cp(original,returned)
h5open(returned,"r+") do f
    write(f["history/iteration"],[1])
end
row=deepcopy(only(old["history"])); row["iteration"]=1
cp_record=Dict("iteration"=>1,"path"=>returned,"sha256"=>C.sha(returned),"theta_over_pi"=>.15,"native_gate_passed"=>false)
C.write_toml(joinpath(output,label*".toml"),Dict("stage"=>label,"arm"=>arm,"point"=>8,"direction"=>"return","iteration_budget"=>2,
    "step_over_pi"=>.025,"updates_per_theta_over_pi"=>80.,"cumulative_updates_before"=>14,"theta_over_pi"=>.15,
    "control_sha256"=>hash,"parent_sha256"=>c["recipe"]["parent_sha256"],"diagnostic_seed"=>origin,
    "paired_forward"=>origin,"history"=>[row],"checkpoints"=>[cp_record],"fixture_only"=>true,"budget_complete"=>false))
C.write_toml(joinpath(output,arm*"_outcome.toml"),Dict("control_sha256"=>hash,"points"=>[label],"budget_complete"=>false,"fixture_only"=>true))
A.analyze_arm(control,output,arm)
a=TOML.parsefile(joinpath(output,"analysis_"*label*"_iter1.toml"))
@testset "Full chi512 synthetic return analysis" begin
    @test !a["continuation_accepted"] && !a["native_gate_applicable"] && !a["is_budget_endpoint"]
    @test a["reference_payload_sha256"]["forward_same_flux"]==origin["sha256"]
    @test a["comparisons"]["forward_same_flux"]["overlap_per_site"]>0.999999
    @test a["comparisons"]["forward_same_flux"]["maximum_cut_entropy_jump"]<1e-10
    @test a["cross_library_energy_difference"]<1e-10
    @test all(s["requested_modes_converged"] for s in values(a["spectra"]))
    @test maximum(abs.(A.RoundTripMomentum.wrap.(a["spectra"]["sz0"]["two_k1"]-a["spectra"]["sz0"]["transfer_phase"])))<1e-12
    @test a["point_manifest_sha256"]==C.sha(joinpath(output,label*".toml"))
end
println("Full-state analysis fixture passed; no optimization. ",output)
