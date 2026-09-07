using Test, LinearAlgebra, ITensors, ITensorMPS, ITensorInfiniteMPS
using TriangularJ1J2ProjectB
const RP=TriangularJ1J2ProjectB

# Independent spin-basis construction: no production bond/OpSum helpers.
function reference_cylinder(N,Ly,shift,theta; J2=0.12,Delta1=0.8,Delta2=0.7,Bz=0.17)
    H=zeros(ComplexF64,2^N,2^N)
    for bits in 0:2^N-1
        for source in 1:N
            b=(bits>>(source-1))&1
            H[bits+1,bits+1]-=Bz*(0.5-b)
            row=(source-1)%Ly; col=(source-1)÷Ly
            for (J,D,steps) in ((1.0,Delta1,((1,0),(0,1),(-1,1))),
                    (J2,Delta2,((1,1),(-2,1),(-1,2))))
                for (dr,dc) in steps
                    turns=fld(row+dr,Ly)
                    target=(col+dc+turns*shift)*Ly+mod(row+dr,Ly)+1
                    1<=target<=N || continue
                    t=(bits>>(target-1))&1
                    H[bits+1,bits+1]+=J*D*(0.5-b)*(0.5-t)
                    b==t && continue
                    flipped=xor(bits,(1<<(source-1))|(1<<(target-1)))
                    H[flipped+1,bits+1]+=J/2*cis((b==1 ? 1 : -1)*theta*dr/Ly)
                end
            end
        end
    end
    H
end
function production_cylinder(N,Ly,shift,theta)
    model=RP.ModelSettings(geometry=RP.YCGeometry(Ly,shift),mps_period=N,Delta1=0.8,Delta2=0.7,Bz=0.17)
    bonds=filter(b->1<=b.source_site<=N && 1<=b.target_site<=N,RP.unit_cell_bonds(model.geometry;period=N))
    sites=siteinds("S=1/2",N;conserve_qns=false)
    ops=RP.triangular_flux_opsum(model,theta;period=N,bonds)
    ITensors.set_warn_order(18)
    tensor=try
        prod(MPO(ops,sites))
    finally
        ITensors.reset_warn_order()
    end
    reshape(Array(tensor,prime.(sites)...,dag.(sites)...),2^N,2^N)
end
@testset "Independent finite-cylinder Hamiltonian and gauge" begin
    for shift in (0,1)
        N=8; Ly=4; theta=0.31pi
        H=production_cylinder(N,Ly,shift,theta)
        reference=reference_cylinder(N,Ly,shift,theta)
        @test norm(H-reference)<1e-11
        @test norm(H-H')<1e-11
        @test norm(production_cylinder(N,Ly,shift,-theta)-conj(H))<1e-11
        @test eigvals(Hermitian(H))≈eigvals(Hermitian(production_cylinder(N,Ly,shift,theta+2pi))) atol=1e-11
        # This is a finite-Hamiltonian spectrum test, not a 2pi test of an adiabatic branch.
    end
end
@testset "Known distinct product states" begin
    settings=RP.load_settings(joinpath(@__DIR__,"../configs/pilot_yc6_1.toml"))
    a=RP.build_product_state(settings)
    scan=RP.ScanSettings(branch="distinct_test",fluxes_over_pi=[0.0],seed_pattern="alternating_shifted",
        require_parent_overlap=true,minimum_parent_overlap_per_site=0.99,
        parent_overlap_krylov_dimension=4)
    b=RP.build_product_state(RP.ProjectSettings(model=settings.model,optimizer=settings.optimizer,
        scan=scan,spectrum=settings.spectrum,runtime=settings.runtime,
        config_path=settings.config_path,config_text=settings.config_text))
    obs_a=RP.local_observables(a,RP.build_hamiltonian(settings.model,RP.siteinds(a),0.0))
    obs_b=RP.local_observables(b,RP.build_hamiltonian(settings.model,RP.siteinds(b),0.0))
    d=RP.branch_continuity_diagnostics(a,b,obs_a,obs_b,0.0,0.0,scan)
    @test d.checked
    @test d.overlap_per_site<1e-10
    @test !d.passed
end
@testset "VUMPS decreases a nonzero projected residual" begin
    settings=RP.load_settings(joinpath(@__DIR__,"../configs/pilot_yc6_1.toml"))
    psi=RP.build_product_state(settings)
    H=RP.build_hamiltonian(settings.model,RP.siteinds(psi),0.0)
    expanded=RP.subspace_expansion(psi,H;maxdim=4,cutoff=1e-8)
    optimizer=RP.OptimizerSettings(maxdim=4,max_iterations=5,residual_tol=1e-10,
        require_converged=false,record_krylov_diagnostics=false)
    _,d=RP.run_vumps_iterations(H,expanded,optimizer;output_level=0)
    @test length(d.residual_history)>=2
    @test first(d.residual_history)>0
    @test all(isfinite,d.residual_history)
    @test minimum(d.residual_history[2:end])<first(d.residual_history)
end
