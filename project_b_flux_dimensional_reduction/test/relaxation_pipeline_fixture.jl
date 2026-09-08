# End-to-end analysis fixture. It contains one imported state and NO optimization.
using Test, HDF5, TOML
include(joinpath(@__DIR__,"../scripts/analyze_relaxation_continuation.jl"))
length(ARGS)==3 || error("usage: relaxation_pipeline_fixture.jl CONTROL OLD_IDENTITY_MANIFEST NEW_DIRECTORY")
control,identity,output=abspath.(ARGS)
c=RC.validate(control); hash=RC.sha(control); old=TOML.parsefile(identity)
old["fixture_only"] && !old["optimization_performed"] || error("identity fixture required")
ispath(output) && error("fixture directory already exists")
mkpath(output); cp(control,joinpath(output,"control.snapshot.toml"))
write(joinpath(output,"control.sha256"),hash*"\n")
payload=joinpath(output,"identity.h5"); cp(old["result_path"],payload)
# A one-record interrupted-point fixture exercises the production analysis schema.
h5open(payload,"r+") do f
    write(f["control_sha256"],hash)
    write(f["history/iteration"],[1])
    f["fixture_only"]=true
end
row=deepcopy(only(old["history"])); row["iteration"]=1
record=Dict("iteration"=>1,"path"=>payload,"sha256"=>RC.sha(payload),"theta_over_pi"=>0.15,"native_gate_passed"=>false)
point=Dict("artifact_kind"=>"project_b_relaxation_point","schema_version"=>1,
    "stage"=>"baseline_point1","arm"=>"baseline","point"=>1,"algorithm"=>"VUMPS","theta_over_pi"=>0.15,
    "step_over_pi"=>0.0,"iteration_budget"=>32,"hold_iterations"=>0,
    "control_sha256"=>hash,"parent_sha256"=>c["recipe"]["parent_sha256"],
    "diagnostic_seed"=>record,"history"=>[row],"checkpoints"=>[record],"selected_iterations"=>[1],
    "budget_complete"=>false,"continuation_accepted"=>false,"fixture_only"=>true)
RC.write_toml(joinpath(output,"baseline_point1.toml"),point)
RC.write_toml(joinpath(output,"baseline_outcome.toml"),Dict("artifact_kind"=>"project_b_relaxation_arm_outcome",
    "control_sha256"=>hash,"arm"=>"baseline","points"=>["baseline_point1"],"budget_complete"=>false,
    "continuation_accepted"=>false,"fixture_only"=>true))
main([control,output,"baseline"])
a=TOML.parsefile(joinpath(output,"analysis_baseline_point1_iter1.toml"))
@testset "Production analysis on an interrupted identity fixture" begin
    @test !a["native_gate_passed"] && !a["continuation_accepted"]
    @test !a["is_budget_endpoint"] && !a["is_hold_endpoint"]
    @test a["comparisons"]["accepted_parent"]["multimetric_passed"]
    @test a["comparisons"]["previous_flux"]["overlap_per_site"]>0.999999
    @test a["cross_library_energy_difference"]<1e-10
    @test all(s["requested_modes_converged"] for s in values(a["spectra"]))
    @test a["point_manifest_sha256"]==RC.sha(joinpath(output,"baseline_point1.toml"))
end
println("Analysis fixture complete (no optimization): ",output)
