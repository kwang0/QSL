using Dates
using HDF5
using ITensors
using ITensorMPS
using ITensorInfiniteMPS
using Printf
using TOML
using TriangularJ1J2ProjectB

const PB = TriangularJ1J2ProjectB
const LINEAGE_ROOT_SHA256 =
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803"
const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const FIXED_POINT_CHANGE_SEMANTICS =
    "MPSKit IDMRG norm(C_new - C_old) after one complete unit-cell sweep"

theta_label(theta::Real) = (theta < 0 ? "m" : "p") *
    replace(@sprintf("%.8f", abs(Float64(theta))), "." => "p")

function tensor_indices(tensor)
    physical = only(filter(index -> hastags(index, "Site"), inds(tensor)))
    links = filter(index -> hastags(index, "Link"), inds(tensor))
    left = only(filter(index -> dir(index) == ITensors.Out, links))
    right = only(filter(index -> dir(index) == ITensors.In, links))
    return left, physical, right
end

function read_native_result(result_path)
    return HDF5.h5open(result_path, "r") do file
        String(read(file, "artifact_kind")) == "project_b_mpskit_idmrg_result_bridge" ||
            error("not a Project B MPSKit result bridge")
        parent_sha256 = String(read(file, "lineage/parent_state_sha256"))
        parent_theta = Float64(read(file, "lineage/parent_theta_over_pi"))
        target_theta = Float64(read(file, "lineage/target_theta_over_pi"))
        lineage_root_sha256 = haskey(file, "lineage/root_state_sha256") ?
            String(read(file, "lineage/root_state_sha256")) : parent_sha256
        lineage_root_sha256 == LINEAGE_ROOT_SHA256 ||
            error("result does not descend from the immutable theta/pi=0.15 lineage root")
        0.15 <= parent_theta < target_theta <= 1.0 ||
            error("result does not describe a forward Phase 1 theta step")
        schema_version = Int(read(file, "schema_version"))
        return (;
            schema_version,
            mpskit_version=String(read(file, "mpskit_version")),
            converged=Bool(read(file, "optimizer/converged")),
            iterations=Int(read(file, "optimizer/iterations")),
            final_fixed_point_change=Float64(read(
                file,
                "optimizer/final_environment_error",
            )),
            iteration=Int.(read(file, "optimizer/history/iteration")),
            fixed_point_change=Float64.(read(
                file,
                "optimizer/history/environment_error",
            )),
            energy_density=Float64.(read(file, "optimizer/history/energy_density")),
            energy_density_delta=Float64.(read(
                file,
                "optimizer/history/energy_density_delta",
            )),
            cumulative_superblock_energy_per_site=haskey(
                file,
                "optimizer/history/cumulative_superblock_energy_per_site",
            ) ? Float64.(read(
                file,
                "optimizer/history/cumulative_superblock_energy_per_site",
            )) : Float64.(read(file, "optimizer/history/energy_density")),
            discarded_weight=Float64.(read(
                file,
                "optimizer/history/discarded_weight",
            )),
            maximum_bond_dimension=Int.(read(
                file,
                "optimizer/history/maximum_bond_dimension",
            )),
            elapsed_seconds=Float64.(read(
                file,
                "optimizer/history/elapsed_seconds",
            )),
            control_path=String(read(file, "control_path")),
            control_sha256=String(read(file, "control_sha256")),
            source_bridge_path=String(read(file, "source_bridge_path")),
            source_bridge_sha256=String(read(file, "source_bridge_sha256")),
            parent_path=String(read(file, "lineage/parent_state_path")),
            parent_sha256,
            parent_theta,
            target_theta,
            lineage_root_sha256,
            numerical_seed_kind=haskey(file, "lineage/numerical_seed_kind") ?
                String(read(file, "lineage/numerical_seed_kind")) : "accepted_parent",
            numerical_seed_path=haskey(file, "lineage/numerical_seed_path") ?
                String(read(file, "lineage/numerical_seed_path")) :
                String(read(file, "lineage/parent_state_path")),
            numerical_seed_sha256=haskey(file, "lineage/numerical_seed_sha256") ?
                String(read(file, "lineage/numerical_seed_sha256")) :
                parent_sha256,
            model_equivalence_error=Float64(read(file, schema_version == 1 ?
                "validation/itensor_mpskit_parent_energy_density_difference" :
                "validation/itensor_mpskit_seed_energy_density_difference")),
            model_energy_tolerance=Float64(read(
                file,
                "validation/model_energy_density_tolerance",
            )),
        )
    end
end

function resolve_policy_evidence(path)
    return isabspath(path) ? normpath(path) : normpath(joinpath(PROJECT_ROOT, path))
end

function load_working_criterion(policy_path, result_path, native)
    absolute_policy = abspath(policy_path)
    policy = TOML.parsefile(absolute_policy)
    policy["artifact_kind"] == "project_b_phase1_idmrg_working_convergence_policy" ||
        error("unexpected working-convergence policy kind")
    scope = policy["scope"]
    settings = policy["native_convergence"]
    evidence = policy["latest_evidence"]
    interpretation = policy["interpretation"]
    scope["profile"] == "phase1_exploratory_working_20260824" ||
        error("working-convergence profile changed")
    Bool(scope["historical_controls_are_immutable"]) ||
        error("working policy must preserve historical controls")
    Bool(scope["historical_job_57500598_classification_is_unchanged"]) ||
        error("working policy must preserve the original job classification")
    Bool(interpretation["native_working_gate_is_not_branch_promotion"]) ||
        error("working policy must require separate branch promotion")

    function verify(path_key, sha_key)
        path = resolve_policy_evidence(String(evidence[path_key]))
        isfile(path) || error("missing working-policy evidence: $path")
        PB.file_sha256(path) == String(evidence[sha_key]) ||
            error("working-policy evidence SHA-256 mismatch: $path")
        return path
    end
    pinned_result = verify("result_path", "result_sha256")
    pinned_control = verify("original_control_path", "original_control_sha256")
    verify("original_analysis_path", "original_analysis_sha256")
    abspath(result_path) == abspath(pinned_result) ||
        error("working policy does not name this result")
    native.control_sha256 == String(evidence["original_control_sha256"]) ||
        error("result control SHA-256 differs from the working policy")
    basename(pinned_control) == basename(native.control_path) ||
        error("working policy names a different source control")

    native_settings = Dict{String,Any}(
        "minimum_iterations" => Int(settings["minimum_iterations"]),
        "energy_window" => Int(settings["energy_window"]),
        "environment_tolerance" =>
            Float64(settings["bond_matrix_update_norm_tolerance"]),
        "energy_density_span_tolerance" =>
            Float64(settings["energy_density_span_tolerance"]),
        "require_achieved_bond_dimension" =>
            Int(settings["require_achieved_bond_dimension"]),
    )
    return (;
        profile=String(scope["profile"]),
        selected_after_source_run=true,
        historical_classification_unchanged=true,
        policy_path=absolute_policy,
        policy_sha256=PB.file_sha256(absolute_policy),
        native_settings,
    )
end

function source_control_criterion(source_control)
    native = source_control["native_convergence"]
    return (;
        profile=String(get(native, "criterion_profile", "source_control_predeclared")),
        selected_after_source_run=false,
        historical_classification_unchanged=false,
        policy_path=String(get(native, "criterion_policy_path", "none")),
        policy_sha256=String(get(native, "criterion_policy_sha256", "none")),
        native_settings=native,
    )
end

function assess_native(native, native_settings)
    intensive_energy_density = native.schema_version == 1 ?
        native.energy_density_delta : native.energy_density
    cumulative_superblock_energy_per_site = native.schema_version == 1 ?
        native.energy_density : native.cumulative_superblock_energy_per_site
    history_vectors = (
        native.iteration,
        native.fixed_point_change,
        intensive_energy_density,
        native.energy_density_delta,
        cumulative_superblock_energy_per_site,
        native.discarded_weight,
        native.maximum_bond_dimension,
        native.elapsed_seconds,
    )
    history_lengths_match = all(length(values) == native.iterations for values in history_vectors)
    energy_window = Int(native_settings["energy_window"])
    minimum_iterations = Int(native_settings["minimum_iterations"])
    enough_iterations = native.iterations >= max(minimum_iterations, energy_window)
    energy_window_values = enough_iterations ?
        @view(intensive_energy_density[(end - energy_window + 1):end]) : Float64[]
    energy_span = enough_iterations ?
        maximum(energy_window_values) - minimum(energy_window_values) : Inf
    fixed_point_tolerance = Float64(native_settings["environment_tolerance"])
    energy_span_tolerance = Float64(native_settings["energy_density_span_tolerance"])
    required_chi = Int(native_settings["require_achieved_bond_dimension"])
    finite_history = history_lengths_match && all(isfinite, native.fixed_point_change) &&
        all(isfinite, intensive_energy_density) && all(isfinite, native.elapsed_seconds)
    discarded_weight_valid = history_lengths_match && all(==(0.0), native.discarded_weight)
    achieved_chi_valid = history_lengths_match &&
        all(==(required_chi), native.maximum_bond_dimension)
    final_value_matches = history_lengths_match && !isempty(native.fixed_point_change) &&
        isapprox(
            native.final_fixed_point_change,
            last(native.fixed_point_change);
            atol=1e-15,
            rtol=1e-12,
        )
    history_valid = history_lengths_match && finite_history && discarded_weight_valid &&
        achieved_chi_valid && final_value_matches
    fixed_point_gate_passed = history_valid &&
        native.final_fixed_point_change <= fixed_point_tolerance
    energy_gate_passed = history_valid && enough_iterations &&
        energy_span <= energy_span_tolerance
    final_chi_gate_passed = history_valid && enough_iterations && all(
        ==(required_chi),
        @view(native.maximum_bond_dimension[(end - energy_window + 1):end]),
    )
    converged = history_valid && enough_iterations && fixed_point_gate_passed &&
        energy_gate_passed && final_chi_gate_passed
    reasons = String[]
    history_valid || push!(reasons, "invalid_native_history")
    enough_iterations || push!(reasons, "insufficient_iterations")
    fixed_point_gate_passed || push!(reasons, "bond_matrix_update_norm_above_tolerance")
    energy_gate_passed || push!(reasons, "intensive_energy_span_above_tolerance")
    final_chi_gate_passed || push!(reasons, "required_bond_dimension_not_maintained")
    return (;
        intensive_energy_density,
        cumulative_superblock_energy_per_site,
        energy_window,
        energy_span,
        fixed_point_tolerance,
        energy_span_tolerance,
        required_chi,
        history_valid,
        enough_iterations,
        fixed_point_gate_passed,
        energy_gate_passed,
        final_chi_gate_passed,
        converged,
        reasons,
    )
end

function write_common!(
    file,
    native,
    assessment,
    source_control,
    result_path,
    result_sha256,
    parent_argument,
    criterion,
)
    model = source_control["model"]
    lineage = source_control["lineage"]
    file["schema_version"] = 2
    file["artifact_kind"] = "project_b_idmrg_analysis"
    file["created_at_utc"] = string(now(UTC))
    file["solver_library"] = "MPSKit"
    file["solver_library_version"] = native.mpskit_version
    file["solver_algorithm"] = "one_site_idmrg"
    file["branch"] = String(lineage["branch"])
    file["direction"] = String(lineage["direction"])
    file["theta_over_pi"] = native.target_theta
    file["lineage/parent_state_path"] = native.parent_path
    file["lineage/local_parent_argument"] = parent_argument
    file["lineage/parent_state_sha256"] = native.parent_sha256
    file["lineage/parent_theta_over_pi"] = native.parent_theta
    file["lineage/overlap_reference_sha256"] = native.parent_sha256
    file["lineage/root_state_sha256"] = native.lineage_root_sha256
    file["lineage/root_theta_over_pi"] = 0.15
    file["lineage/numerical_seed_kind"] = native.numerical_seed_kind
    file["lineage/numerical_seed_path"] = native.numerical_seed_path
    file["lineage/numerical_seed_sha256"] = native.numerical_seed_sha256
    file["source/result_bridge_path"] = result_path
    file["source/result_bridge_sha256"] = result_sha256
    file["source/control_path"] = native.control_path
    file["source/control_sha256"] = native.control_sha256
    file["source/import_bridge_path"] = native.source_bridge_path
    file["source/import_bridge_sha256"] = native.source_bridge_sha256
    file["source/analyzer_sha256"] = PB.file_sha256(@__FILE__)
    file["geometry/circumference"] = Int(model["circumference"])
    file["geometry/shift"] = Int(model["shift"])
    file["geometry/mps_period"] = Int(model["mps_period"])
    for key in ("J1", "J2", "Delta1", "Delta2", "Bz")
        file["model/$key"] = Float64(model[key])
    end
    file["model/twist_gauge"] = String(model["twist_gauge"])
    file["optimizer/source_recorded_converged"] = native.converged
    file["optimizer/converged"] = assessment.converged
    file["optimizer/iterations"] = native.iterations
    file["optimizer/final_environment_error"] = native.final_fixed_point_change
    file["optimizer/final_bond_matrix_update_norm"] = native.final_fixed_point_change
    file["optimizer/fixed_point_change_semantics"] = FIXED_POINT_CHANGE_SEMANTICS
    file["optimizer/history/iteration"] = native.iteration
    file["optimizer/history/environment_error"] = native.fixed_point_change
    file["optimizer/history/bond_matrix_update_norm"] = native.fixed_point_change
    file["optimizer/history/energy_density"] = assessment.intensive_energy_density
    file["optimizer/history/energy_density_delta"] = native.energy_density_delta
    file["optimizer/history/cumulative_superblock_energy_per_site"] =
        assessment.cumulative_superblock_energy_per_site
    file["optimizer/history/energy_density_semantics"] =
        "MPSKit IDMRG superblock-energy increment divided by the period"
    file["optimizer/history/source_schema1_energy_semantics_corrected"] =
        native.schema_version == 1
    file["optimizer/history/discarded_weight"] = native.discarded_weight
    file["optimizer/history/maximum_bond_dimension"] = native.maximum_bond_dimension
    file["optimizer/history/elapsed_seconds"] = native.elapsed_seconds
    file["optimizer/discarded_weight_semantics"] =
        "exactly zero: one-site fixed-space IDMRG performs no SVD truncation"
    file["validation/native_history_valid"] = assessment.history_valid
    file["validation/native_minimum_iterations_passed"] = assessment.enough_iterations
    file["validation/native_fixed_point_change_passed"] =
        assessment.fixed_point_gate_passed
    file["validation/native_energy_density_span_passed"] = assessment.energy_gate_passed
    file["validation/native_achieved_chi_passed"] = assessment.final_chi_gate_passed
    file["validation/native_energy_density_span"] = assessment.energy_span
    file["validation/native_bond_matrix_update_norm_tolerance"] =
        assessment.fixed_point_tolerance
    file["validation/native_environment_tolerance_legacy_name"] =
        assessment.fixed_point_tolerance
    file["validation/native_energy_density_span_tolerance"] =
        assessment.energy_span_tolerance
    file["validation/itensor_mpskit_seed_energy_density_difference"] =
        native.model_equivalence_error
    file["validation/model_energy_density_tolerance"] = native.model_energy_tolerance
    file["criterion/profile"] = criterion.profile
    file["criterion/selected_after_source_run"] = criterion.selected_after_source_run
    file["criterion/historical_classification_unchanged"] =
        criterion.historical_classification_unchanged
    file["criterion/policy_path"] = criterion.policy_path
    file["criterion/policy_sha256"] = criterion.policy_sha256
end

function write_native_only_analysis(
    output_path,
    native,
    assessment,
    source_control,
    result_path,
    result_sha256,
    parent_argument,
    reasons,
    criterion,
    ;
    stage="native_only",
    post_native_itensor_conversion_required=false,
    post_native_itensor_conversion_ran=false,
)
    PB.atomic_h5write(output_path) do file
        write_common!(
            file,
            native,
            assessment,
            source_control,
            result_path,
            result_sha256,
            parent_argument,
            criterion,
        )
        file["continuation_accepted"] = false
        file["analysis/stage"] = stage
        file["analysis/post_native_itensor_conversion_required"] =
            post_native_itensor_conversion_required
        file["analysis/post_native_itensor_conversion_ran"] =
            post_native_itensor_conversion_ran
        file["analysis/rejection_reasons"] = reasons
        file["continuation/gates_evaluated"] = false
        file["continuation/status"] = "not_evaluated_after_native_failure"
        file["validation/common_vumps_projected_residual_ran"] = false
        file["validation/common_vumps_projected_residual"] = NaN
        file["state/full_tensor_payload_included"] = false
        file["state/omission_reason"] =
            "native-ineligible numerical candidate; full seed remains in the result bridge"
    end
end

function read_candidate_tensors(result_path, parent)
    return HDF5.h5open(result_path, "r") do file
        map(1:2) do site
            reference = parent.psi.AL[site]
            left, physical, right = tensor_indices(reference)
            data = ComplexF64.(read(file, "state/site_$site/AL"))
            size(data) == (dim(left), dim(physical), dim(right)) ||
                error("result tensor dimensions changed at site $site")
            tensor = ITensor(data, left, physical, right)
            norm(Array(tensor, left, physical, right) - data) <=
                5e-13 * max(norm(data), 1) ||
                error("TensorKit-to-ITensor round trip failed at site $site")
            tensor
        end
    end
end

function main()
    length(ARGS) in (3, 4) || error(
        "usage: analyze_phase1_idmrg_result.jl RESULT_BRIDGE.h5 " *
        "ACCEPTED_PARENT.h5 OUTPUT_DIRECTORY [WORKING_POLICY.toml]",
    )
    result_path = abspath(ARGS[1])
    parent_path = abspath(ARGS[2])
    output_directory = abspath(ARGS[3])
    native = read_native_result(result_path)
    local_control_path = joinpath(dirname(result_path), basename(native.control_path))
    isfile(local_control_path) || error("missing local source control: $local_control_path")
    PB.file_sha256(local_control_path) == native.control_sha256 ||
        error("local source-control SHA-256 mismatch")
    source_control = TOML.parsefile(local_control_path)
    lineage = source_control["lineage"]
    String(lineage["parent_state_sha256"]) == native.parent_sha256 ||
        error("source control and result parent SHA-256 differ")
    isapprox(
        Float64(lineage["parent_theta_over_pi"]),
        native.parent_theta;
        atol=1e-12,
        rtol=0,
    ) || error("source control and result parent theta differ")
    isapprox(
        Float64(lineage["target_theta_over_pi"]),
        native.target_theta;
        atol=1e-12,
        rtol=0,
    ) || error("source control and result target theta differ")
    criterion = length(ARGS) == 4 ?
        load_working_criterion(ARGS[4], result_path, native) :
        source_control_criterion(source_control)
    native_settings = criterion.native_settings
    assessment = assess_native(native, native_settings)
    result_sha256 = PB.file_sha256(result_path)
    status = "rejected"
    status_prefix = criterion.selected_after_source_run ? "working_" : ""
    analysis_revision_suffix = criterion.selected_after_source_run ?
        "_$(first(PB.file_sha256(@__FILE__), 12))" : ""
    mkpath(output_directory)
    output_path = joinpath(
        output_directory,
        "analysis_idmrg_theta_$(theta_label(native.target_theta))_chi512_" *
        "$(status_prefix)$(status)_$(first(result_sha256, 12))" *
        "$(analysis_revision_suffix).h5",
    )

    model_equivalence_passed =
        native.model_equivalence_error <= native.model_energy_tolerance
    native_reasons = copy(assessment.reasons)
    model_equivalence_passed || push!(native_reasons, "model_equivalence_gate_failed")
    if !assessment.converged || !model_equivalence_passed
        write_native_only_analysis(
            output_path,
            native,
            assessment,
            source_control,
            result_path,
            result_sha256,
            parent_path,
            native_reasons,
            criterion,
        )
        println("iDMRG state status: rejected")
        println("analysis stage: native only; ITensor promotion conversion skipped")
        println("source-recorded native convergence: ", native.converged)
        println("recomputed native convergence: ", assessment.converged)
        println("final MPSKit bond-matrix update norm: ", native.final_fixed_point_change)
        println("bond-matrix update-norm tolerance: ", assessment.fixed_point_tolerance)
        println("final-window intensive energy span: ", assessment.energy_span)
        println("intensive-energy-span tolerance: ", assessment.energy_span_tolerance)
        println("rejection reasons: ", join(native_reasons, ", "))
        println("immutable analysis: $output_path")
        println("analysis SHA-256: $(PB.file_sha256(output_path))")
        return
    end

    PB.file_sha256(parent_path) == native.parent_sha256 || error("parent SHA-256 mismatch")
    parent = PB.read_state_file(parent_path)
    tensors = read_candidate_tensors(result_path, parent)
    candidate = nothing
    canonicalization = nothing
    try
        candidate, canonicalization = PB.canonicalize_idmrg_tensors(
            tensors;
            tol=1e-12,
            eigenvalue_imag_tolerance=1e-9,
        )
    catch exception
        conversion_reason = "itensor_canonicalization_failed: " * sprint(showerror, exception)
        output_path = joinpath(
            output_directory,
            "analysis_idmrg_theta_$(theta_label(native.target_theta))_chi512_" *
            "$(status_prefix)conversion_rejected_$(first(result_sha256, 12))_" *
            "$(first(PB.file_sha256(@__FILE__), 12)).h5",
        )
        write_native_only_analysis(
            output_path,
            native,
            assessment,
            source_control,
            result_path,
            result_sha256,
            parent_path,
            [conversion_reason],
            criterion,
            ;
            stage="promotion_blocked_conversion_failure",
            post_native_itensor_conversion_required=true,
            post_native_itensor_conversion_ran=true,
        )
        println("iDMRG state status: rejected")
        println("analysis stage: native gates passed; ITensor promotion conversion failed")
        println(conversion_reason)
        println("immutable analysis: $output_path")
        println("analysis SHA-256: $(PB.file_sha256(output_path))")
        return
    end
    nsites(candidate) == 2 || error("canonical import changed the period")
    maxlinkdim(candidate) == 512 || error("canonical import changed chi")

    model = PB.ModelSettings(
        geometry=PB.YCGeometry(8, 1),
        J1=1.0,
        J2=0.12,
        Delta1=1.0,
        Delta2=1.0,
        Bz=0.0,
        twist_gauge=:uniform,
        mps_period=2,
    )
    hamiltonian = PB.build_hamiltonian(
        model,
        siteinds(only, candidate),
        native.target_theta,
    )
    observables = PB.local_observables(candidate, hamiltonian)
    scan = PB.ScanSettings(
        branch=parent.branch,
        preparation=parent.preparation,
        direction=:stationary,
        lineage_policy=:strict,
        fluxes_over_pi=[native.target_theta],
        seed_pattern=parent.seed_pattern,
        random_seed=101,
        adaptive_bisection=false,
        minimum_step_over_pi=0.05,
        save_rejected=true,
        require_parent_overlap=true,
        minimum_parent_overlap_per_site=0.99,
        parent_overlap_tolerance=1e-8,
        parent_overlap_krylov_dimension=16,
    )
    continuity = PB.branch_continuity_diagnostics(
        parent.psi,
        candidate,
        parent.observables,
        observables,
        native.parent_theta,
        native.target_theta,
        scan,
    )
    sector_rows = PB.compare_bond_sectors(parent.psi, candidate)
    probe_ran = false
    probe_residual = NaN
    if continuity.passed
        probe_optimizer = PB.OptimizerSettings(
            maxdim=512,
            residual_tol=1e-5,
            max_iterations=1,
            max_growth_steps=1,
            require_converged=false,
            multisite_update_alg="sequential",
        )
        _, probe = PB.run_vumps_iterations(
            hamiltonian,
            copy(candidate),
            probe_optimizer;
            output_level=1,
        )
        probe_ran = true
        probe_residual = probe.residual
    end
    eligible = continuity.passed && probe_ran && isfinite(probe_residual)
    status = eligible ? "accepted" : "rejected"
    output_path = joinpath(
        output_directory,
        "analysis_idmrg_theta_$(theta_label(native.target_theta))_chi512_" *
        "$(status_prefix)$(status)_$(first(result_sha256, 12))" *
        "$(analysis_revision_suffix).h5",
    )

    PB.atomic_h5write(output_path) do file
        write_common!(
            file,
            native,
            assessment,
            source_control,
            result_path,
            result_sha256,
            parent_path,
            criterion,
        )
        file["continuation_accepted"] = eligible
        file["analysis/stage"] = "full_promotion_analysis"
        file["analysis/post_native_itensor_conversion_required"] = true
        file["analysis/post_native_itensor_conversion_ran"] = true
        file["validation/common_vumps_projected_residual_ran"] = probe_ran
        file["validation/common_vumps_projected_residual"] = probe_residual
        file["validation/common_vumps_projected_residual_semantics"] =
            probe_ran ?
            "one discarded sequential VUMPS update used only as a common stationarity probe" :
            "skipped after the independent parent-overlap continuity gate failed"
        file["validation/canonicalization/eigenvalue_imag_tolerance"] =
            canonicalization.eigenvalue_imag_tolerance
        file["validation/canonicalization/right_eigenvalue_relative_imaginary"] =
            canonicalization.right.relative_imaginary
        file["validation/canonicalization/right_subleading_eigenvalue"] =
            canonicalization.right.subleading_eigenvalue
        file["validation/canonicalization/right_leading_magnitude_gap"] =
            canonicalization.right.leading_magnitude_gap
        file["validation/canonicalization/right_hermitian_phase_overlap"] =
            canonicalization.right.hermitian_phase_overlap
        file["validation/canonicalization/right_hermitian_phase_factor"] =
            canonicalization.right.hermitian_phase_factor
        file["validation/canonicalization/right_hermitian_relative_correction"] =
            canonicalization.right.hermitian_relative_correction
        file["validation/canonicalization/left_method"] =
            canonicalization.left.method
        file["validation/canonicalization/left_tolerance"] =
            canonicalization.left.tolerance
        file["validation/canonicalization/left_isometry_errors"] =
            canonicalization.left.isometry_errors
        file["validation/canonicalization/left_center_relation_errors"] =
            canonicalization.left.center_relation_errors
        file["validation/canonicalization/left_maximum_isometry_error"] =
            canonicalization.left.maximum_isometry_error
        file["validation/canonicalization/left_maximum_center_relation_error"] =
            canonicalization.left.maximum_center_relation_error
        file["validation/canonicalization/normalization"] =
            canonicalization.normalization
        file["observables/energy_density"] = observables.energy_density
        file["observables/energy_terms"] = observables.energy_terms
        file["observables/energy_term_std"] = observables.energy_term_std
        file["observables/von_neumann_entropies"] = observables.entropy.von_neumann
        file["observables/renyi2_entropies"] = observables.entropy.renyi2
        file["observables/schmidt_raw_norms"] = observables.entropy.raw_norms
        file["observables/magnetization_z"] = observables.magnetization_z
        file["observables/maxlinkdim"] = observables.maxlinkdim
        PB.write_schmidt_probabilities!(file, observables.entropy.schmidt_probabilities)
        PB.write_continuity_diagnostics!(file, continuity)
        file["continuation/gates_evaluated"] = true
        file["continuation/status"] = continuity.passed ? "passed" : "failed"
        file["sectors/cut"] = [row.cut for row in sector_rows]
        file["sectors/qn_label"] = [row.qn_label for row in sector_rows]
        file["sectors/before_multiplicity"] = [row.before_multiplicity for row in sector_rows]
        file["sectors/after_multiplicity"] = [row.after_multiplicity for row in sector_rows]
        file["sectors/before_schmidt_weight"] = [row.before_schmidt_weight for row in sector_rows]
        file["sectors/after_schmidt_weight"] = [row.after_schmidt_weight for row in sector_rows]
        file["state/full_tensor_payload_included"] = eligible
        file["state/omission_reason"] = eligible ? "not omitted" :
            "post-native branch gate failed; retain the result bridge as a numerical seed"
        if eligible
            file["preparation"] = parent.preparation
            file["random_seed"] = parent.random_seed
            file["geometry/minimal_mps_period"] = 2
            file["geometry/unit_cell_is_minimal"] = true
            file["optimizer/requested_maxdim"] = 512
            file["optimizer/stop_reason"] = criterion.selected_after_source_run ?
                "working_native_and_branch_gates_passed" :
                "predeclared_native_and_branch_gates_passed"
            file["continuation/parent_state_path"] = native.parent_path
            file["continuation/parent_state_sha256"] = native.parent_sha256
            file["continuation/seed_pattern"] = parent.seed_pattern
            file["continuation/preparation_source"] = "mpskit_idmrg_continuation"
            file["continuation/flux_history_over_pi"] =
                vcat(parent.flux_history_over_pi, [native.target_theta])
            file["psi"] = candidate
        end
    end

    println("iDMRG state status: $status")
    println("analysis stage: full post-native promotion analysis")
    println("source-recorded native convergence: ", native.converged)
    println("recomputed native convergence: ", assessment.converged)
    println("final MPSKit bond-matrix update norm: ", native.final_fixed_point_change)
    println("final-window intensive energy span: ", assessment.energy_span)
    println("parent overlap per site: ", continuity.overlap_per_site)
    println("parent-overlap continuity reason: ", continuity.reason)
    println("common VUMPS projected residual probe ran: ", probe_ran)
    probe_ran && println("common VUMPS projected residual probe: ", probe_residual)
    println("immutable analysis: $output_path")
    println("analysis SHA-256: $(PB.file_sha256(output_path))")
end

main()
