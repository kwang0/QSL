module RelaxationAnalysis
using HDF5, ITensors, ITensorMPS, ITensorInfiniteMPS, LinearAlgebra, TOML
using TriangularJ1J2ProjectB
const PB=TriangularJ1J2ProjectB

function tensor_indices(t)
    physical=only(filter(i->hastags(i,"Site"),inds(t)))
    links=filter(i->hastags(i,"Link"),inds(t))
    only(filter(i->dir(i)==ITensors.Out,links)),physical,only(filter(i->dir(i)==ITensors.In,links))
end
charges(i)=reduce(vcat,[fill(Int(val(qn,"Sz")),Int(n)) for (qn,n) in space(i)])

function read_payload(path,expected_sha,reference,control_sha,parent_sha;chi=512,tolerance=1e-8)
    PB.file_sha256(path)==expected_sha || error("payload hash mismatch: $path")
    data=h5open(path,"r") do f
        read(f,"artifact_kind")=="project_b_mpskit_solver_pilot_result" || error("payload schema")
        read(f,"schema_version")==2 && read(f,"canonical_payload") || error("canonical payload required")
        read(f,"control_sha256")==control_sha && read(f,"parent_sha256")==parent_sha || error("payload provenance mismatch")
        read(f,"algorithm")=="VUMPS" && !read(f,"continuation_accepted") || error("payload role mismatch")
        function gauge(key)
            map(1:2) do site
                left,physical,right=tensor_indices(reference.AL[site]); prefix="state/site_$site"
                for (name,index) in (("left",left),("physical",physical),("right",right))
                    read(f,"$prefix/$(name)_charges")==charges(index) || error("U1 basis changed")
                end
                if key=="AR"
                    left=addtags(left,"RelaxationRight"); right=addtags(right,"RelaxationRight")
                end
                a=ComplexF64.(read(f,"$prefix/$key")); t=ITensor(a,left,physical,right)
                norm(Array(t,left,physical,right)-a)<=5e-13*max(1,norm(a)) || error("U1 payload round trip failed")
                t
            end
        end
        centers=map(1:2) do site
            _,_,bond=tensor_indices(reference.AL[site])
            ITensor(ComplexF64.(read(f,"state/site_$site/C")),dag(bond),addtags(bond,"RelaxationRight"))
        end
        psi=InfiniteCanonicalMPS(ITensorInfiniteMPS.InfiniteMPS(gauge("AL")),
            ITensorInfiniteMPS.InfiniteMPS(centers),ITensorInfiniteMPS.InfiniteMPS(gauge("AR")))
        history=Dict(key=>read(f,"history/$key") for key in
            ("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds"))
        (;psi,history,theta=read(f,"theta_over_pi"))
    end
    PB.nsites(data.psi)==2 && PB.maxlinkdim(data.psi)==chi || error("period/chi changed")
    canonical=PB._imported_left_canonical_diagnostics(data.psi.AL,data.psi.C,data.psi.AR;tolerance)
    right_errors=Float64[]
    for site in 1:2
        t=data.psi.AR[site]; left,_,_=tensor_indices(t)
        gram=dag(prime(t,left))*t; a=Array(gram,inds(gram)...)
        push!(right_errors,norm(a-Matrix{ComplexF64}(I,size(a)...))/sqrt(size(a,1)))
        abs(norm(data.psi.C[site])-1)<=tolerance || error("center normalization failed")
    end
    maximum(right_errors)<=tolerance || error("right isometry failed")
    merge(data,(;canonical_errors=Dict("left_isometry"=>canonical.maximum_isometry_error,
        "right_isometry"=>maximum(right_errors),"center_relation"=>canonical.maximum_center_relation_error)))
end

model()=PB.ModelSettings(geometry=PB.YCGeometry(8,1),mps_period=2,twist_gauge=:uniform)
observables(psi,theta)=PB.local_observables(psi,PB.build_hamiltonian(model(),siteinds(only,psi),theta))
function compare(reference,candidate,refobs,obs,ref_theta,theta,parent,p)
    scan=PB.ScanSettings(branch=parent.branch,preparation=parent.preparation,direction=:stationary,
        lineage_policy=:strict,fluxes_over_pi=[theta],require_parent_overlap=true,
        continuity_policy=:multimetric_trust_region,minimum_parent_overlap_per_site=p["minimum_overlap_per_site"],
        maximum_cut_entropy_jump=p["maximum_cut_entropy_jump"],maximum_energy_term_rms_jump=p["maximum_energy_term_rms_jump"],
        maximum_magnetization_rms_jump=p["maximum_magnetization_rms_jump"],
        maximum_mean_schmidt_total_variation=p["maximum_mean_schmidt_total_variation"],
        maximum_log_correlation_length_jump=p["maximum_log_correlation_length_jump"],
        require_u1_sector_diagnostics=true,require_correlation_length_diagnostics=true,
        parent_overlap_krylov_dimension=32,correlation_length_krylov_dimension=32,random_seed=101)
    d=PB.branch_continuity_diagnostics(reference,candidate,refobs,obs,ref_theta,theta,scan)
    Dict("multimetric_passed"=>d.passed,"overlap_per_site"=>d.overlap_per_site,
        "overlap_floor_passed"=>PB.parent_overlap_passes(d.overlap_per_site,p["minimum_overlap_per_site"]),
        "maximum_cut_entropy_jump"=>d.maximum_cut_entropy_jump,
        "energy_term_rms_jump"=>d.energy_term_rms_jump,
        "magnetization_rms_jump"=>d.magnetization_rms_jump,
        "mean_schmidt_total_variation"=>d.mean_schmidt_total_variation,
        "maximum_log_correlation_length_jump"=>d.maximum_log_correlation_length_jump,
        "u1_sector_diagnostics_passed"=>d.u1_sector_diagnostics_passed,
        "u1_sector_labels_preserved"=>d.u1_sector_labels_preserved,
        "u1_sector_multiplicities_preserved"=>d.u1_sector_multiplicities_preserved,
        "correlation_length_diagnostics_passed"=>d.correlation_length_diagnostics_passed,
        "correlation_length_reason"=>d.correlation_length_reason,
        "correlation_length_physical_sz_sectors"=>d.correlation_length_physical_sz_sectors,
        "reference_correlation_lengths"=>d.parent_correlation_lengths,
        "candidate_correlation_lengths"=>d.candidate_correlation_lengths,
        "correlation_length_krylov_residual_norms"=>d.correlation_length_krylov_residual_norms,
        "overlap_krylov_residual_norms"=>d.krylov_residual_norms)
end

function spectra(psi,theta,r)
    result=Dict{String,Any}(); reference=nothing
    for sz in r["physical_sz"]
        s=PB.compute_transfer_spectrum(psi;physical_sz=sz,reference_lambda=reference,
            neigs=r["neigs"],tolerance=r["tolerance"],krylov_dimension=r["krylov_dimension"],random_seed=r["random_seed"])
        reference=s.reference_lambda
        abs(reference-1)<=1e-7 || error("transfer normalization differs from one")
        count=min(length(s.lambdas),r["neigs"])
        maps=[PB.momentum_from_minimal_phase(PB.YCGeometry(8,1),k,pi*theta) for k in s.k_parallel[1:count]]
        result["sz$(sz)"]=Dict("physical_sz"=>sz,"raw_qn_sz"=>s.raw_qn_sz,
            "lambda_real"=>real.(s.normalized_lambdas[1:count]),"lambda_imag"=>imag.(s.normalized_lambdas[1:count]),
            "inverse_xi"=>s.inverse_xi[1:count],"transfer_phase"=>s.k_parallel[1:count],
            "two_k1"=>[x.two_k1 for x in maps],"k2"=>[x.k2 for x in maps],
            "krylov_converged"=>s.krylov_converged,"krylov_residual_norms"=>s.krylov_residual_norms,
            "requested_modes_converged"=>s.krylov_converged>=r["neigs"],"units"=>r["units"],
            "interpretation"=>"Transfer spectrum of a diagnostic state; not an energy gap.")
    end
    result
end
end
