using Test, TOML, HDF5, LinearAlgebra, ITensors, ITensorMPS, ITensorInfiniteMPS
include(joinpath(@__DIR__,"../scripts/lib/RelaxationAnalysis.jl"))
const RA=RelaxationAnalysis
@testset "Canonical payload, provenance and flux momentum units" begin
    seed(n)=isodd(n) ? "Up" : "Dn"
    psi=InfMPS(infsiteinds("S=1/2",2;conserve_qns=true,initstate=seed),seed)
    mktempdir() do directory
        path=joinpath(directory,"tiny.h5")
        h5open(path,"w") do f
            f["artifact_kind"]="project_b_mpskit_solver_pilot_result"; f["schema_version"]=2
            f["canonical_payload"]=true; f["continuation_accepted"]=false
            f["algorithm"]="VUMPS"; f["control_sha256"]=repeat("a",64); f["parent_sha256"]=repeat("b",64)
            f["theta_over_pi"]=0.2
            for i in 1:2
                left,physical,right=RA.tensor_indices(psi.AL[i]); prefix="state/site_$i"
                for (key,index) in (("left",left),("physical",physical),("right",right))
                    f["$prefix/$(key)_charges"]=RA.charges(index)
                end
                for gauge in (:AL,:AR)
                    t=getproperty(psi,gauge)[i]; f["$prefix/$gauge"]=ComplexF64.(Array(t,RA.tensor_indices(t)...))
                end
                f["$prefix/C"]=ones(ComplexF64,1,1)
            end
            for key in ("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds")
                f["history/$key"]=key in ("iteration","chi") ? [1] : [0.0]
            end
        end
        hash=RA.PB.file_sha256(path)
        restored=RA.read_payload(path,hash,psi,repeat("a",64),repeat("b",64);chi=1)
        @test restored.theta==0.2
        @test maximum(values(restored.canonical_errors))<1e-12
        @test restored.history["iteration"]==[1]
        @test RA.observables(restored.psi,0.2).energy_density≈RA.observables(psi,0.2).energy_density atol=1e-12
        @test_throws ErrorException RA.read_payload(path,repeat("c",64),psi,repeat("a",64),repeat("b",64);chi=1)
        @test_throws ErrorException RA.read_payload(path,hash,psi,repeat("c",64),repeat("b",64);chi=1)
        @test_throws ErrorException RA.read_payload(path,hash,psi,repeat("a",64),repeat("b",64);chi=512)
    end
    k=0.3; theta=0.2pi
    mapped=RA.PB.momentum_from_minimal_phase(RA.PB.YCGeometry(8,1),k,theta)
    @test mapped.two_k1≈k+2theta/8 atol=1e-12
    @test mapped.k2≈4k atol=1e-12
end

if !isempty(ARGS)
    length(ARGS)==2 || error("optional full test: CONTROL IDENTITY_FIXTURE_MANIFEST")
    c=TOML.parsefile(ARGS[1]); fixture=TOML.parsefile(ARGS[2])
    fixture["fixture_only"] && !fixture["optimization_performed"] || error("not an identity fixture")
    project=normpath(joinpath(@__DIR__,".."))
    parent=RA.PB.read_state_file(joinpath(project,c["parent_path"]))
    state=RA.read_payload(fixture["result_path"],fixture["result_sha256"],parent.psi,
        RA.PB.file_sha256(ARGS[1]),c["recipe"]["parent_sha256"])
    obs=RA.observables(state.psi,0.15); parent_obs=RA.observables(parent.psi,0.15)
    comparison=RA.compare(parent.psi,state.psi,parent_obs,obs,0.15,0.15,parent,c["recipe"]["continuity"])
    spectrum=RA.spectra(state.psi,0.15,TOML.parsefile(joinpath(project,"configs/relaxation_continuation.toml"))["spectrum"])
    @testset "Full chi512 accepted-parent identity and spectra" begin
        # Recanonicalizing the historical AL bridge has a small preparation drift.
        # Compare the unchanged payload across libraries tightly, and the original
        # parent with the already declared model-equivalence tolerance.
        @test abs(obs.energy_density-fixture["history"][end]["energy_density"])<1e-10
        @test abs(obs.energy_density-parent_obs.energy_density)<c["recipe"]["model_energy_tolerance"]
        @test abs(obs.energy_density-c["parent_energy_density_at_0p15"])<c["recipe"]["model_energy_tolerance"]
        @test comparison["multimetric_passed"] && comparison["overlap_floor_passed"]
        @test comparison["overlap_per_site"]>0.999999
        @test maximum(values(state.canonical_errors))<1e-10
        @test all(s["requested_modes_converged"] for s in values(spectrum))
        @test spectrum["sz1"]["raw_qn_sz"]==2
        @test length(spectrum["sz1"]["inverse_xi"])==6
        @test abs(first(spectrum["sz0"]["inverse_xi"]))<1e-8
    end
    println("Cross-library payload energy difference: ",abs(obs.energy_density-fixture["history"][end]["energy_density"]))
    println("Recanonicalization energy drift from historical parent: ",abs(obs.energy_density-parent_obs.energy_density))
    println("Converged modes Sz0/Sz1: ",spectrum["sz0"]["krylov_converged"],"/",spectrum["sz1"]["krylov_converged"])
end
