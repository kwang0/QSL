#!/usr/bin/env julia

using HDF5
using TOML
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const DEFAULT_POLICY = joinpath(
    PROJECT_ROOT,
    "configs",
    "phase1_idmrg_working_convergence.toml",
)

length(ARGS) <= 1 || error(
    "usage: assess_phase1_idmrg_working_convergence.jl [POLICY.toml]",
)
policy_path = abspath(isempty(ARGS) ? DEFAULT_POLICY : ARGS[1])
policy = TOML.parsefile(policy_path)
policy["artifact_kind"] == "project_b_phase1_idmrg_working_convergence_policy" ||
    error("unexpected working-convergence policy kind")
scope = policy["scope"]
native = policy["native_convergence"]
evidence = policy["latest_evidence"]
interpretation = policy["interpretation"]

resolve(path) = isabspath(path) ? normpath(path) : normpath(joinpath(PROJECT_ROOT, path))
verify(path_key, sha_key) = begin
    path = resolve(String(evidence[path_key]))
    isfile(path) || error("missing pinned evidence: $path")
    PB.file_sha256(path) == evidence[sha_key] || error("pinned evidence hash mismatch: $path")
    path
end

result_path = verify("result_path", "result_sha256")
verify("original_control_path", "original_control_sha256")
verify("original_analysis_path", "original_analysis_sha256")

record = h5open(result_path, "r") do file
    schema_version = Int(read(file, "schema_version"))
    schema_version == 2 || error("working assessment requires schema-2 iDMRG result")
    fixed_point_path = haskey(file, "optimizer/history/bond_matrix_update_norm") ?
        "optimizer/history/bond_matrix_update_norm" :
        "optimizer/history/environment_error"
    fixed_point = Float64.(read(file, fixed_point_path))
    energy_density = Float64.(read(file, "optimizer/history/energy_density"))
    discarded_weight = Float64.(read(file, "optimizer/history/discarded_weight"))
    maximum_bond_dimension = Int.(read(file, "optimizer/history/maximum_bond_dimension"))
    iterations = Int(read(file, "optimizer/iterations"))
    (; fixed_point, energy_density, discarded_weight, maximum_bond_dimension, iterations)
end

vectors = (
    record.fixed_point,
    record.energy_density,
    record.discarded_weight,
    record.maximum_bond_dimension,
)
all(length(values) == record.iterations for values in vectors) ||
    error("result history lengths do not match optimizer iteration count")

window = Int(native["energy_window"])
minimum_iterations = Int(native["minimum_iterations"])
record.iterations >= max(window, minimum_iterations) || error("insufficient result history")
energy_span = maximum(@view(record.energy_density[(end - window + 1):end])) -
    minimum(@view(record.energy_density[(end - window + 1):end]))
final_fixed_point = last(record.fixed_point)
fixed_point_tolerance = Float64(native["bond_matrix_update_norm_tolerance"])
energy_tolerance = Float64(native["energy_density_span_tolerance"])
required_chi = Int(native["require_achieved_bond_dimension"])
fixed_point_passed = final_fixed_point <= fixed_point_tolerance
energy_passed = energy_span <= energy_tolerance
chi_passed = all(==(required_chi), record.maximum_bond_dimension)
discarded_weight_passed = !Bool(native["require_zero_one_site_discarded_weight"]) ||
    all(==(0.0), record.discarded_weight)
working_native_gate_passed = fixed_point_passed && energy_passed && chi_passed &&
    discarded_weight_passed

output_path = joinpath(
    dirname(resolve(String(evidence["original_analysis_path"]))),
    "working_convergence_assessment_$(first(String(evidence["result_sha256"]), 12)).toml",
)
ispath(output_path) && error("refusing to overwrite working assessment: $output_path")
assessment = Dict(
    "artifact_kind" => "project_b_phase1_idmrg_working_convergence_assessment",
    "schema_version" => 1,
    "policy_path" => relpath(policy_path, PROJECT_ROOT),
    "policy_sha256" => PB.file_sha256(policy_path),
    "source" => Dict(
        "result_path" => String(evidence["result_path"]),
        "result_sha256" => String(evidence["result_sha256"]),
        "original_control_sha256" => String(evidence["original_control_sha256"]),
        "original_analysis_sha256" => String(evidence["original_analysis_sha256"]),
    ),
    "criteria" => Dict(
        "profile" => String(scope["profile"]),
        "selected_after_source_run" => true,
        "bond_matrix_update_norm_tolerance" => fixed_point_tolerance,
        "energy_density_span_tolerance" => energy_tolerance,
        "energy_window" => window,
        "required_bond_dimension" => required_chi,
    ),
    "result" => Dict(
        "iterations" => record.iterations,
        "final_bond_matrix_update_norm" => final_fixed_point,
        "final_energy_density_span" => energy_span,
        "bond_matrix_update_norm_passed" => fixed_point_passed,
        "energy_density_span_passed" => energy_passed,
        "bond_dimension_passed" => chi_passed,
        "zero_one_site_discarded_weight_passed" => discarded_weight_passed,
        "working_native_gate_passed" => working_native_gate_passed,
    ),
    "interpretation" => Dict(
        "historical_classification_unchanged" =>
            Bool(scope["historical_job_57500598_classification_is_unchanged"]),
        "branch_promotion_evaluated" => false,
        "branch_promotion_required" =>
            Bool(interpretation["native_working_gate_is_not_branch_promotion"]),
        "status" => working_native_gate_passed ?
            "passes_posthoc_working_native_gate_promotion_not_evaluated" :
            "fails_posthoc_working_native_gate",
    ),
)
open(output_path, "w") do io
    TOML.print(io, assessment; sorted=true)
end

println("Working convergence assessment: $output_path")
println("Policy SHA-256: $(PB.file_sha256(policy_path))")
println("Assessment SHA-256: $(PB.file_sha256(output_path))")
println("Bond-matrix update norm: $final_fixed_point <= $fixed_point_tolerance: $fixed_point_passed")
println("Final-$window energy span: $energy_span <= $energy_tolerance: $energy_passed")
println("Working native gate passed: $working_native_gate_passed")
println("Historical classification unchanged: true")
println("Branch promotion evaluated: false")
