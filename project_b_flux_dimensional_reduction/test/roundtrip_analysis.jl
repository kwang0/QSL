# Exercise the inherited canonical reader, then the new sector-aware mapping.
include("relaxation_analysis.jl")
include("../scripts/roundtrip/Momentum.jl")
const M=RoundTripMomentum
@testset "Physical charge and momentum gauge shift" begin
    for k in (-3.0,-.7,0.0,2.9), theta in (0.0,.15,.25,1.0)
        neutral=M.momentum(k,theta,0); charged=M.momentum(k,theta,1)
        old=RA.PB.momentum_from_minimal_phase(RA.PB.YCGeometry(8,1),k,theta*pi)
        @test neutral.two_k1≈M.wrap(k) atol=1e-12
        @test neutral.k2≈charged.k2 atol=1e-12
        @test charged.two_k1≈old.two_k1 atol=1e-12
        @test charged.k2≈old.k2 atol=1e-12
        @test M.wrap(charged.two_k1-neutral.two_k1)≈2pi*theta/8 atol=1e-12
        @test M.momentum(k,theta,-1).two_k1≈M.wrap(k-2pi*theta/8) atol=1e-12
    end
    @test_throws ErrorException M.momentum(NaN,.2,1)
end
