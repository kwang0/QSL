using Test

include("heisenberg_idmrg_prototype.jl")
using .HeisenbergIDMRGPrototype

@testset "Heisenberg iDMRG prototype" begin
    @test isapprox(exact_open_chain_energy(2), -0.75; atol=1e-12)

    finite = finite_dmrg_heisenberg(;
        N=8,
        maxdim=32,
        cutoff=1e-12,
        nsweeps=8,
        conserve_qns=true,
        outputlevel=0,
    )
    exact_finite = exact_open_chain_energy(8)
    @test isapprox(finite.energy_total, exact_finite; atol=1e-6)
    @test finite.center_bond_energy < 0
    @test isfinite(finite.runtime_sec)

    rows = run_benchmark_suite(;
        maxdims=[8],
        finite_N=8,
        finite_nsweeps=4,
        output="heisenberg_idmrg_test_benchmark.csv",
        run_idmrg=false,
    )
    @test length(rows) == 1
    @test rows[1]["method"] == "finite_dmrg"
    @test isfile("heisenberg_idmrg_test_benchmark.csv")
    rm("heisenberg_idmrg_test_benchmark.csv"; force=true)

    if infinite_mps_available()
        idmrg = run_idmrg_heisenberg(;
            maxdim=64,
            cutoff=1e-10,
            max_vumps_iters=50,
            vumps_tol=1e-8,
            outer_iters=6,
            neigs=8,
            transfer_tol=1e-10,
        )
        @test isfinite(idmrg.energy_density)
        exact_N8_density = exact_finite / 8
        @test exact_heisenberg_energy_density() < idmrg.energy_density < exact_N8_density
        @test abs(idmrg.energy_density - exact_heisenberg_energy_density()) < 1e-4
        @test abs((finite.energy_per_site - idmrg.energy_density) - (exact_N8_density - exact_heisenberg_energy_density())) < 1e-4
        @test isapprox(abs(idmrg.transfer.normalized_lambdas[1]), 1; atol=1e-8)
        @test length(idmrg.transfer.correlation_lengths) >= 2
    else
        @info "Skipping iDMRG/VUMPS smoke test because ITensorInfiniteMPS.jl is not installed."
        @test true
    end
end
