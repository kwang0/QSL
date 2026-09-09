using Test, Random, MPSKit, TensorKit, ProjectBIDMRG
include("../roundtrip/Continuation.jl")
const RT=RoundTripContinuation
@testset "Endpoint propagation and interruption" begin
    arm=Dict("fluxes"=>[0.2,0.25,0.2,0.15],"iterations"=>2)
    seeds=Int[]; points=Int[]
    solve(x,j,theta,n)=(push!(seeds,x); (;psi=x+j,history=fill(j,n)))
    r=RT.follow_path(10,arm;solve,record=(j,r,full)->push!(points,j))
    @test r.complete && r.completed==4 && r.psi==20
    @test seeds==[10,11,13,16] # return carries outward endpoint, never the origin
    @test points==[1,2,3,4]
    empty!(seeds); empty!(points)
    partial(x,j,theta,n)=(push!(seeds,x); (;psi=x+j,history=fill(j,j==2 ? 1 : n)))
    r=RT.follow_path(10,arm;solve=partial,record=(j,r,full)->push!(points,j))
    @test !r.complete && r.completed==1
    @test seeds==[10,11] && points==[1,2]
end
@testset "Actual VUMPS forward-and-return kernel" begin
    Random.seed!(927)
    p=Rep[U₁](1=>1,-1=>1)
    v=[Rep[U₁](0=>2,2=>1,-2=>1),Rep[U₁](1=>2,-1=>2)]
    psi=InfiniteMPS(fill(p,2),v;tol=1e-12)
    bond=(;coupling=1.0,anisotropy=1.0,twist_charge=0.25)
    H(theta)=InfiniteMPOHamiltonian(fill(p,2),[(1,2)=>ProjectBIDMRG.two_site_operator(bond,theta),(2,3)=>ProjectBIDMRG.two_site_operator(bond,theta)])
    arm=Dict("fluxes"=>[0.175,0.2,0.175,0.15],"iterations"=>2)
    records=Any[]
    result=RT.follow_path(psi,arm;solve=(x,j,theta,n)->RT.R.fixed_updates(x,H(theta),n),record=(j,r,full)->push!(records,r))
    @test result.complete && length(records)==4
    @test all([row["iteration"] for row in x.history]==[1,2] for x in records)
    @test all(row["chi"]==4 && isfinite(row["native_error"]) for x in records for row in x.history)
    @test result.psi===records[end].psi
    @test RT.R.SP.energy_density(result.psi,H(.15),MPSKit.environments(result.psi,H(.15)))≈records[end].history[end]["energy_density"] atol=1e-10
end
