module HeisenbergIDMRGPrototype

using ITensors
using ITensorMPS
using LinearAlgebra
using Printf
using Statistics

export exact_heisenberg_energy_density,
    exact_open_chain_energy,
    finite_dmrg_heisenberg,
    infinite_mps_available,
    run_idmrg_heisenberg,
    run_benchmark_suite,
    main

const INFINITE_MPS_LOADED = Ref(false)
const INFINITE_MPS_LOAD_ERROR = Ref{Union{Nothing,String}}(nothing)
const KRYLOVKIT_LOAD_ERROR = Ref{Union{Nothing,String}}(nothing)

try
    @eval using ITensorInfiniteMPS
    try
        @eval import KrylovKit: eigsolve
    catch err
        KRYLOVKIT_LOAD_ERROR[] = sprint(showerror, err)
    end
    @eval include(
        joinpath(
            pkgdir(ITensorInfiniteMPS),
            "examples",
            "vumps",
            "src",
            "vumps_subspace_expansion.jl",
        ),
    )
    INFINITE_MPS_LOADED[] = true
catch err
    INFINITE_MPS_LOAD_ERROR[] = sprint(showerror, err)
end

function exact_heisenberg_energy_density()
    return 0.25 - log(2)
end

function install_hint()
    return """
    ITensorInfiniteMPS.jl is required for the iDMRG/VUMPS part of this prototype.
    It is not registered, so install it with:

        julia> using Pkg
        julia> Pkg.add(url="https://github.com/ITensor/ITensorInfiniteMPS.jl.git")
        julia> Pkg.add("KrylovKit")

    The finite-DMRG benchmark path only requires ITensors.jl and ITensorMPS.jl.
    """
end

function infinite_mps_available()
    return INFINITE_MPS_LOADED[]
end

function ensure_infinite_mps_loaded!()
    INFINITE_MPS_LOADED[] && return nothing
    error("$(install_hint())\nOriginal load error:\n$(INFINITE_MPS_LOAD_ERROR[])")
end

function alternating_state(N)
    return [isodd(n) ? "Up" : "Dn" for n in 1:N]
end

function heisenberg_op_sum(N; J=1.0)
    os = OpSum()
    for j in 1:(N - 1)
        os += J, "Sz", j, "Sz", j + 1
        os += 0.5J, "S+", j, "S-", j + 1
        os += 0.5J, "S-", j, "S+", j + 1
    end
    return os
end

function two_site_heisenberg_operator(s1, s2; J=1.0)
    return J * op("Sz", s1) * op("Sz", s2) +
           0.5J * op("S+", s1) * op("S-", s2) +
           0.5J * op("S-", s1) * op("S+", s2)
end

function center_bond_energy!(psi, sites; J=1.0)
    j = div(length(sites), 2)
    orthogonalize!(psi, j)
    phi = psi[j] * psi[j + 1]
    h = two_site_heisenberg_operator(sites[j], sites[j + 1]; J)
    return real(inner(phi, apply(h, phi)))
end

function finite_dmrg_heisenberg(;
    N=64,
    J=1.0,
    maxdim=64,
    cutoff=1e-10,
    nsweeps=8,
    conserve_qns=true,
    initial_linkdim=min(maxdim, 16),
    outputlevel=0,
)
    sites = siteinds("S=1/2", N; conserve_qns)
    H = MPO(heisenberg_op_sum(N; J), sites)
    psi0 = randomMPS(sites, alternating_state(N); linkdims=initial_linkdim)

    t0 = time()
    energy_total, psi = dmrg(H, psi0; nsweeps, maxdim, cutoff, outputlevel)
    runtime_sec = time() - t0

    center_energy = center_bond_energy!(psi, sites; J)
    return (;
        method="finite_dmrg",
        N,
        J,
        maxdim,
        cutoff,
        nsweeps,
        energy_total,
        energy_per_site=energy_total / N,
        energy_per_bond=energy_total / (N - 1),
        center_bond_energy=center_energy,
        exact_energy_density=J * exact_heisenberg_energy_density(),
        center_bond_error=center_energy - J * exact_heisenberg_energy_density(),
        runtime_sec,
        psi,
    )
end

function exact_open_chain_energy(N; J=1.0)
    dim_hilbert = 1 << N
    H = zeros(Float64, dim_hilbert, dim_hilbert)
    for state in 0:(dim_hilbert - 1)
        for j in 1:(N - 1)
            bit1 = (state >> (j - 1)) & 1
            bit2 = (state >> j) & 1
            sz1 = bit1 == 1 ? 0.5 : -0.5
            sz2 = bit2 == 1 ? 0.5 : -0.5
            H[state + 1, state + 1] += J * sz1 * sz2
            if bit1 != bit2
                flipped = xor(state, (1 << (j - 1)) | (1 << j))
                H[flipped + 1, state + 1] += 0.5J
            end
        end
    end
    return eigmin(Symmetric(H))
end

function expect_two_site_mpo(psi, h, bond)
    n1, n2 = bond
    phi = psi.AL[n1] * psi.AL[n2] * psi.C[n2]
    return real(inner(phi, apply(contract(h), phi)))
end

function transfer_matrix_spectrum(psi; neigs=8, tol=1e-10)
    if !isdefined(@__MODULE__, :eigsolve)
        error(
            "eigsolve is not available. Add KrylovKit as a direct dependency with `Pkg.add(\"KrylovKit\")`, then rerun the iDMRG benchmark.\nOriginal load error:\n$(KRYLOVKIT_LOAD_ERROR[])",
        )
    end
    T = TransferMatrix(psi.AL)
    v0 = random_itensor(dag(input_inds(T)))
    lambdas, vecs, info = eigsolve(T, v0, neigs, :LM; tol)
    lambda0 = lambdas[1]
    normalized_lambdas = lambdas ./ lambda0
    correlation_lengths = map(eachindex(normalized_lambdas)) do n
        n == 1 && return Inf
        lambda_abs = abs(normalized_lambdas[n])
        return -1 / log(lambda_abs)
    end
    momenta = angle.(normalized_lambdas)
    return (; lambdas, normalized_lambdas, correlation_lengths, momenta, info, vecs)
end

function run_idmrg_heisenberg(;
    maxdim=64,
    cutoff=1e-8,
    max_vumps_iters=50,
    vumps_tol=1e-8,
    outer_iters=4,
    conserve_qns=true,
    neigs=8,
    transfer_tol=1e-10,
)
    ensure_infinite_mps_loaded!()

    Ncell = 2
    initstate(n) = isodd(n) ? "Up" : "Dn"
    sites = infsiteinds("S=1/2", Ncell; conserve_qns, initstate)
    psi0 = InfMPS(sites, initstate)
    model = Model("heisenberg")
    H = InfiniteSum{MPO}(model, sites)

    vumps_kwargs = (tol=vumps_tol, maxiter=max_vumps_iters, solver_tol=(x -> x / 1000))
    subspace_expansion_kwargs = (cutoff=cutoff, maxdim=maxdim)

    t0 = time()
    psi = vumps_subspace_expansion(
        H,
        psi0;
        outer_iters,
        subspace_expansion_kwargs,
        vumps_kwargs,
    )
    runtime_sec = time() - t0

    bond_energies = [expect_two_site_mpo(psi, H[bond], bond) for bond in ((1, 2), (2, 3))]
    energy_density = mean(bond_energies)
    sz = [real(expect(psi, "Sz", n)) for n in 1:Ncell]
    transfer = transfer_matrix_spectrum(psi; neigs, tol=transfer_tol)

    return (;
        method="idmrg_vumps",
        Ncell,
        maxdim,
        cutoff,
        max_vumps_iters,
        vumps_tol,
        outer_iters,
        energy_density,
        bond_energies,
        exact_energy_density=exact_heisenberg_energy_density(),
        energy_error=energy_density - exact_heisenberg_energy_density(),
        sz,
        transfer,
        runtime_sec,
        psi,
    )
end

function csv_value(x)
    x isa AbstractFloat && !isfinite(x) && return string(x)
    x isa Real && return @sprintf("%.16g", x)
    return string(x)
end

function write_benchmark_csv(filename, rows)
    headers = [
        "method",
        "N",
        "maxdim",
        "energy_density",
        "energy_error",
        "center_bond_energy",
        "xi1",
        "lambda1_abs",
        "momentum1",
        "runtime_sec",
        "status",
    ]
    open(filename, "w") do io
        println(io, join(headers, ","))
        for row in rows
            println(io, join((csv_value(row[h]) for h in headers), ","))
        end
    end
    return filename
end

function row_from_finite(result)
    return Dict(
        "method" => result.method,
        "N" => result.N,
        "maxdim" => result.maxdim,
        "energy_density" => result.energy_per_site,
        "energy_error" => result.energy_per_site - result.exact_energy_density,
        "center_bond_energy" => result.center_bond_energy,
        "xi1" => NaN,
        "lambda1_abs" => NaN,
        "momentum1" => NaN,
        "runtime_sec" => result.runtime_sec,
        "status" => "ok",
    )
end

function row_from_idmrg(result)
    xi1 = length(result.transfer.correlation_lengths) >= 2 ?
          result.transfer.correlation_lengths[2] :
          NaN
    lambda1_abs = length(result.transfer.normalized_lambdas) >= 2 ?
                  abs(result.transfer.normalized_lambdas[2]) :
                  NaN
    momentum1 = length(result.transfer.momenta) >= 2 ? result.transfer.momenta[2] : NaN
    return Dict(
        "method" => result.method,
        "N" => result.Ncell,
        "maxdim" => result.maxdim,
        "energy_density" => result.energy_density,
        "energy_error" => result.energy_error,
        "center_bond_energy" => result.energy_density,
        "xi1" => xi1,
        "lambda1_abs" => lambda1_abs,
        "momentum1" => momentum1,
        "runtime_sec" => result.runtime_sec,
        "status" => "ok",
    )
end

function run_benchmark_suite(;
    maxdims=[8, 16, 32],
    finite_N=64,
    finite_nsweeps=8,
    output="heisenberg_idmrg_benchmark.csv",
    run_idmrg=true,
)
    rows = Dict{String,Any}[]
    for maxdim in maxdims
        println("Running finite DMRG benchmark: N=$finite_N, maxdim=$maxdim")
        finite = finite_dmrg_heisenberg(; N=finite_N, maxdim, nsweeps=finite_nsweeps)
        push!(rows, row_from_finite(finite))
    end

    if run_idmrg
        if !infinite_mps_available()
            @warn "Skipping iDMRG/VUMPS benchmarks because ITensorInfiniteMPS.jl is not installed.\n$(install_hint())"
            push!(
                rows,
                Dict(
                    "method" => "idmrg_vumps",
                    "N" => 2,
                    "maxdim" => maximum(maxdims),
                    "energy_density" => NaN,
                    "energy_error" => NaN,
                    "center_bond_energy" => NaN,
                    "xi1" => NaN,
                    "lambda1_abs" => NaN,
                    "momentum1" => NaN,
                    "runtime_sec" => 0.0,
                    "status" => "missing_ITensorInfiniteMPS",
                ),
            )
        else
            for maxdim in maxdims
                println("Running iDMRG/VUMPS benchmark: unit cell=2, maxdim=$maxdim")
                idmrg = run_idmrg_heisenberg(; maxdim)
                push!(rows, row_from_idmrg(idmrg))
            end
        end
    end

    write_benchmark_csv(output, rows)
    println("Wrote benchmark results to $output")
    return rows
end

function parse_int_list(s)
    return parse.(Int, split(s, ","))
end

function usage()
    return """
    Usage:
      julia heisenberg_idmrg_prototype.jl benchmark [maxdims=8,16,32] [finite_N=64] [output_csv=heisenberg_idmrg_benchmark.csv]
      julia heisenberg_idmrg_prototype.jl finite [N=64] [maxdim=64] [nsweeps=8]
      julia heisenberg_idmrg_prototype.jl idmrg [maxdim=64]

    Notes:
      - The finite command runs standard finite DMRG as a reference.
      - The idmrg command requires ITensorInfiniteMPS.jl.
      - The benchmark command writes a CSV with energy and transfer-matrix diagnostics.
    """
end

function main(args=ARGS)
    command = isempty(args) ? "benchmark" : lowercase(args[1])
    if command == "benchmark"
        maxdims = length(args) >= 2 ? parse_int_list(args[2]) : [8, 16, 32]
        finite_N = length(args) >= 3 ? parse(Int, args[3]) : 64
        output = length(args) >= 4 ? args[4] : "heisenberg_idmrg_benchmark.csv"
        run_benchmark_suite(; maxdims, finite_N, output)
    elseif command == "finite"
        N = length(args) >= 2 ? parse(Int, args[2]) : 64
        maxdim = length(args) >= 3 ? parse(Int, args[3]) : 64
        nsweeps = length(args) >= 4 ? parse(Int, args[4]) : 8
        result = finite_dmrg_heisenberg(; N, maxdim, nsweeps, outputlevel=1)
        @printf("finite DMRG E/N        = %.16f\n", result.energy_per_site)
        @printf("finite center bond E   = %.16f\n", result.center_bond_energy)
        @printf("Bethe ansatz E density = %.16f\n", result.exact_energy_density)
        @printf("center-bond error      = %.6e\n", result.center_bond_error)
    elseif command == "idmrg"
        maxdim = length(args) >= 2 ? parse(Int, args[2]) : 64
        result = run_idmrg_heisenberg(; maxdim)
        @printf("iDMRG/VUMPS E density  = %.16f\n", result.energy_density)
        @printf("Bethe ansatz E density = %.16f\n", result.exact_energy_density)
        @printf("energy error           = %.6e\n", result.energy_error)
        if length(result.transfer.correlation_lengths) >= 2
            @printf("leading xi             = %.16f\n", result.transfer.correlation_lengths[2])
            @printf("leading momentum       = %.16f\n", result.transfer.momenta[2])
        end
    else
        error(usage())
    end
end

end

if abspath(PROGRAM_FILE) == @__FILE__
    using .HeisenbergIDMRGPrototype
    HeisenbergIDMRGPrototype.main(ARGS)
end
