using HDF5, ITensors, ITensorMPS, ITensorInfiniteMPS, TOML, Statistics, LinearAlgebra
using TriangularJ1J2ProjectB
include(joinpath(@__DIR__,"lib/SolverPilotControl.jl"))
const PB=TriangularJ1J2ProjectB
function tensor_indices(t)
    physical=only(filter(i->hastags(i,"Site"),inds(t)))
    links=filter(i->hastags(i,"Link"),inds(t))
    only(filter(i->dir(i)==ITensors.Out,links)),physical,only(filter(i->dir(i)==ITensors.In,links))
end
charges(i)=reduce(vcat,[fill(Int(val(qn,"Sz")),Int(n)) for (qn,n) in space(i)])
function main(args)
    length(args)==2 || error("usage: analyze_mpskit_solver_pilot.jl CONTROL STAGE_MANIFEST")
    control=SolverPilotControl.validate(args[1]); recipe=control["recipe"]
    stage=TOML.parsefile(args[2]); hash=SolverPilotControl.sha(args[1])
    stage["control_sha256"]==hash || error("control hash differs from solver result")
    result=stage["result_path"]; PB.file_sha256(result)==stage["result_sha256"] || error("result hash mismatch")
    parent=PB.read_state_file(joinpath(SolverPilotControl.ROOT,control["parent_path"]))
    candidate=h5open(result,"r") do f
        read(f,"artifact_kind")=="project_b_mpskit_solver_pilot_result" || error("wrong result kind")
        read(f,"schema_version")==2 && read(f,"canonical_payload") || error("full canonical pilot payload required")
        read(f,"control_sha256")==hash && read(f,"parent_sha256")==recipe["parent_sha256"] || error("lineage mismatch")
        read(f,"algorithm")==stage["algorithm"] && read(f,"theta_over_pi")==stage["theta_over_pi"] ||
            error("stage does not match payload")
        for key in ("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds")
            read(f,"history/$key")==[r[key] for r in stage["history"]] || error("history does not match payload")
        end
        function read_gauge(gauge)
            map(1:2) do site
                reference=parent.psi.AL[site]
                left,physical,right=tensor_indices(reference); prefix="state/site_$site"
                for (key,index) in (("left",left),("physical",physical),("right",right))
                    read(f,"$prefix/$(key)_charges")==charges(index) || error("U1 basis changed at site $site")
                end
                data=ComplexF64.(read(f,"$prefix/$gauge"))
                if gauge==:AR
                    left=addtags(left,"PilotRight"); right=addtags(right,"PilotRight")
                end
                t=ITensor(data,left,physical,right)
                norm(Array(t,left,physical,right)-data)<=5e-13*max(norm(data),1) || error("tensor round trip failed")
                t
            end
        end
        centers=map(1:2) do site
            _,_,bond=tensor_indices(parent.psi.AL[site])
            left=dag(bond); right=addtags(bond,"PilotRight")
            expected=read(f,"state/site_$site/right_charges")
            charges(left)==expected && charges(right)==expected || error("center U1 basis changed")
            data=ComplexF64.(read(f,"state/site_$site/C"))
            ITensor(data,left,right)
        end
        InfiniteCanonicalMPS(ITensorInfiniteMPS.InfiniteMPS(read_gauge(:AL)),
            ITensorInfiniteMPS.InfiniteMPS(centers),ITensorInfiniteMPS.InfiniteMPS(read_gauge(:AR)))
    end
    canonical=PB._imported_left_canonical_diagnostics(candidate.AL,candidate.C,candidate.AR;
        tolerance=recipe["canonical_relation_tolerance"])
    right_errors=Float64[]
    for site in 1:2
        tensor=candidate.AR[site]; left,_,_=tensor_indices(tensor)
        gram=dag(prime(tensor,left))*tensor
        a=Array(gram,inds(gram)...)
        push!(right_errors,norm(a-Matrix{ComplexF64}(I,size(a)...))/sqrt(size(a,1)))
        abs(norm(candidate.C[site])-1)<=recipe["canonical_relation_tolerance"] || error("center normalization failed")
    end
    maximum(right_errors)<=recipe["canonical_relation_tolerance"] || error("right isometry failed")
    PB.nsites(candidate)==2 && PB.maxlinkdim(candidate)==512 || error("import changed period or chi")
    model=PB.ModelSettings(geometry=PB.YCGeometry(8,1),mps_period=2,twist_gauge=:uniform)
    theta=stage["theta_over_pi"]
    observables=PB.local_observables(candidate,PB.build_hamiltonian(model,siteinds(only,candidate),theta))
    parent_obs=PB.local_observables(parent.psi,PB.build_hamiltonian(model,siteinds(only,parent.psi),0.15))
    p=recipe["continuity"]
    scan=PB.ScanSettings(branch=parent.branch,preparation=parent.preparation,direction=:stationary,
        lineage_policy=:strict,fluxes_over_pi=[theta],require_parent_overlap=true,
        continuity_policy=:multimetric_trust_region,minimum_parent_overlap_per_site=p["minimum_overlap_per_site"],
        maximum_cut_entropy_jump=p["maximum_cut_entropy_jump"],maximum_energy_term_rms_jump=p["maximum_energy_term_rms_jump"],
        maximum_magnetization_rms_jump=p["maximum_magnetization_rms_jump"],
        maximum_mean_schmidt_total_variation=p["maximum_mean_schmidt_total_variation"],
        maximum_log_correlation_length_jump=p["maximum_log_correlation_length_jump"],
        require_u1_sector_diagnostics=true,require_correlation_length_diagnostics=true,
        parent_overlap_krylov_dimension=32,correlation_length_krylov_dimension=32,random_seed=101)
    d=PB.branch_continuity_diagnostics(parent.psi,candidate,parent_obs,observables,0.15,theta,scan)
    h=stage["history"]; w=recipe["energy_window"]
    tolerance=recipe[stage["algorithm"]=="VUMPS" ? "vumps_galerkin_tolerance" : "grassmann_gradient_tolerance"]
    native=length(h)>=max(w,recipe["minimum_iterations"]) && h[end]["iteration"]>=recipe["minimum_iterations"] &&
        all(r->r["chi"]==512 && isfinite(r["energy_density"]) && isfinite(r["native_error"]),h[end-w+1:end]) &&
        h[end]["native_error"]<=tolerance &&
        maximum(r["energy_density"] for r in h[end-w+1:end])-minimum(r["energy_density"] for r in h[end-w+1:end])<=recipe["energy_span_tolerance"]
    native==stage["native_gate_passed"] || error("native classification differs from payload history")
    energy_difference=abs(observables.energy_density-last(stage["history"])["energy_density"])
    energy_equal=energy_difference<=recipe["model_energy_tolerance"]
    overlap_pass=PB.parent_overlap_passes(d.overlap_per_site,p["minimum_overlap_per_site"])
    eligible=native && d.passed && overlap_pass && energy_equal
    output=joinpath(dirname(args[2]),"analysis_"*stage["stage"]*".h5")
    PB.atomic_h5write(output) do f
        f["schema_version"]=1; f["artifact_kind"]="project_b_mpskit_solver_pilot_analysis"
        f["source/result_sha256"]=stage["result_sha256"]; f["source/control_sha256"]=hash
        f["lineage/parent_state_sha256"]=recipe["parent_sha256"]
        f["algorithm"]=stage["algorithm"]; f["theta_over_pi"]=theta
        f["branch"]=parent.branch; f["geometry/mps_period"]=2
        f["continuation_accepted"]=false; f["diagnostic/eligible_for_owner_review"]=eligible
        f["diagnostic/native_gate_passed"]=native; f["diagnostic/overlap_floor_passed"]=overlap_pass
        f["diagnostic/cross_library_energy_difference"]=energy_difference
        f["diagnostic/cross_library_energy_passed"]=energy_equal
        f["diagnostic/correlation_length_units"]="complete MPS transfer cells"
        f["diagnostic/maximum_left_isometry_error"]=canonical.maximum_isometry_error
        f["diagnostic/maximum_right_isometry_error"]=maximum(right_errors)
        f["diagnostic/maximum_center_relation_error"]=canonical.maximum_center_relation_error
        f["observables/energy_density"]=observables.energy_density
        f["observables/energy_terms"]=observables.energy_terms
        f["observables/von_neumann_entropies"]=observables.entropy.von_neumann
        f["observables/magnetization_z"]=observables.magnetization_z
        f["observables/maxlinkdim"]=observables.maxlinkdim
        PB.write_schmidt_probabilities!(f,observables.entropy.schmidt_probabilities)
        PB.write_continuity_diagnostics!(f,d)
    end
    summary=Dict("artifact_kind"=>"project_b_mpskit_pilot_analysis_summary","stage"=>stage["stage"],
        "analysis_path"=>output,"analysis_sha256"=>PB.file_sha256(output),
        "native_gate_passed"=>native,"multimetric_continuity_passed"=>d.passed,
        "overlap_floor_passed"=>overlap_pass,"overlap_per_site"=>d.overlap_per_site,
        "energy_density"=>observables.energy_density,"energy_equivalence_passed"=>energy_equal,
        "maximum_cut_entropy_jump"=>d.maximum_cut_entropy_jump,
        "eligible_for_owner_review"=>eligible,"continuation_accepted"=>false,
        "interpretation"=>"A failed diagnostic does not establish a physical spinodal; no automatic lineage promotion.")
    path=joinpath(dirname(args[2]),"analysis_"*stage["stage"]*".toml")
    ispath(path) && error("immutable analysis summary exists")
    open(io->TOML.print(io,summary;sorted=true),path,"w")
    println("Pilot ",stage["stage"],": eligible for review=",eligible,"; accepted lineage unchanged.")
end
main(ARGS)
