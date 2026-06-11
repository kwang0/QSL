using MKL
using ITensors
using ITensorMPS
using ITensorInfiniteMPS
using KrylovKit: Arnoldi, eigsolve
using HDF5
using LinearAlgebra
using Printf
using Statistics

include(
    joinpath(
        pkgdir(ITensorInfiniteMPS),
        "examples",
        "vumps",
        "src",
        "vumps_subspace_expansion.jl",
    ),
)

const DEFAULT_SCRATCH_DIR = "/pscratch/sd/k/kwang98/QSL"
const NN_DISPLACEMENTS = ((1, 0), (0, 1), (-1, 1))
const NNN_DISPLACEMENTS = ((1, 1), (-2, 1), (-1, 2))
const DEFAULT_VUMPS_TOL = 1e-5
const DEFAULT_MAX_VUMPS_ITERS = 20
const SOLVER_TOL_FLOOR = 1e-7

function default_output_dir()
    return isdir(DEFAULT_SCRATCH_DIR) ? DEFAULT_SCRATCH_DIR : "processed_data"
end

function parse_env_int(keys, default)
    for key in keys
        if haskey(ENV, key) && !isempty(strip(ENV[key]))
            return parse(Int, ENV[key])
        end
    end
    return default
end

function default_blas_threads()
    return parse_env_int(
        (
            "JULIA_NUM_BLAS_THREADS",
            "MKL_NUM_THREADS",
            "OPENBLAS_NUM_THREADS",
            "OMP_NUM_THREADS",
            "SLURM_CPUS_PER_TASK",
        ),
        min(Sys.CPU_THREADS, 256),
    )
end

function default_strided_threads()
    return parse_env_int(("ITENSOR_STRIDED_THREADS", "NDTENSORS_STRIDED_THREADS"), 1)
end

function configure_threading!(; blas_threads=default_blas_threads(), strided_threads=default_strided_threads())
    blas_threads >= 1 || error("blas_threads must be >= 1")
    strided_threads >= 1 || error("strided_threads must be >= 1")

    BLAS.set_num_threads(blas_threads)
    try
        ITensors.NDTensors.Strided.set_num_threads(strided_threads)
    catch err
        @warn "Could not set ITensors.NDTensors.Strided thread count" exception = err
    end

    active_strided_threads = try
        ITensors.NDTensors.Strided.get_num_threads()
    catch
        missing
    end
    println(
        "Threading: Julia=$(Threads.nthreads()), BLAS=$(BLAS.get_num_threads()), ITensors.Strided=$(active_strided_threads)",
    )
    return (; blas_threads=BLAS.get_num_threads(), strided_threads=active_strided_threads)
end

# Site numbering for one infinite-MPS unit cell equal to one YC column:
# row = 0:(C - 1), col = 0 is the home unit cell, col = 1 is the next cell.
function idx(row, col, C)
    return col * C + mod(row, C) + 1
end

# YC(Ly)-n identifies (row, col) with (row + Ly, col - n). Therefore
# (row + winding * Ly, col) wraps to (row, col + winding * n).
function yc_wrapped_endpoint(row, col, drow, dcol, C, yc_shift)
    raw_row = row + drow
    raw_col = col + dcol
    winding = fld(raw_row, C)
    wrapped_row = raw_row - winding * C
    wrapped_col = raw_col + winding * yc_shift
    return wrapped_row, wrapped_col, winding
end

function shifted_infinite_bond(row, row2, col2, C)
    col_shift = -min(0, col2)
    i = idx(row, col_shift, C)
    j = idx(row2, col2 + col_shift, C)
    @assert i >= 1 && j >= 1
    @assert min(i, j) <= C
    return i, j, col_shift
end

function yc_unit_cell_bonds(C, yc_shift)
    bonds = NamedTuple[]
    for (family, displacements) in ((:NN, NN_DISPLACEMENTS), (:NNN, NNN_DISPLACEMENTS))
        for row in 0:(C - 1)
            for (drow, dcol) in displacements
                row2, col2, winding = yc_wrapped_endpoint(row, 0, drow, dcol, C, yc_shift)
                i, j, col_shift = shifted_infinite_bond(row, row2, col2, C)
                push!(
                    bonds,
                    (;
                        family,
                        row,
                        col=0,
                        drow,
                        dcol,
                        row2,
                        col2,
                        winding,
                        source_site=i,
                        target_site=j,
                        col_shift,
                    ),
                )
            end
        end
    end
    return bonds
end

function add_twisted_heisenberg_bond!(os, J, Delta, i, j, theta, winding)
    iszero(J) && return os
    phase = cis(theta * winding)
    os += Delta * J, "Sz", i, "Sz", j
    os += 0.5 * J * phase, "S+", i, "S-", j
    os += 0.5 * J * conj(phase), "S-", i, "S+", j
    return os
end

function triangular_yc_flux_opsum(
    C,
    J1,
    J2;
    Delta1=1.0,
    Delta2=1.0,
    theta=0.0,
    yc_shift=0,
    B=0.0,
    Bperp=0.0,
    bonds=yc_unit_cell_bonds(C, yc_shift),
)
    os = OpSum()

    # ITensorInfiniteMPS currently expects a term whose minimum support starts
    # on every unit-cell site. These zero identities satisfy that requirement.
    for site in 1:C
        os += 0.0, "Id", site
    end

    for row in 0:(C - 1)
        site = idx(row, 0, C)
        if B != 0.0
            os += -B, "Sz", site
        end
        if Bperp != 0.0
            os += -Bperp, "Sx", site
        end
    end

    for bond in bonds
        if bond.family == :NN
            os = add_twisted_heisenberg_bond!(
                os,
                J1,
                Delta1,
                bond.source_site,
                bond.target_site,
                theta,
                bond.winding,
            )
        else
            os = add_twisted_heisenberg_bond!(
                os,
                J2,
                Delta2,
                bond.source_site,
                bond.target_site,
                theta,
                bond.winding,
            )
        end
    end

    return os
end

function initial_state(site)
    return isodd(site) ? "Up" : "Dn"
end

function build_sites(C; conserve_qns=true)
    if conserve_qns && isodd(C)
        error("conserve_qns=true requires an even YC circumference for the default zero-Sz unit cell")
    end
    return infsiteinds("S=1/2", C; conserve_qns, initstate=initial_state)
end

function build_hamiltonian(
    sites,
    C,
    J1,
    J2;
    Delta1,
    Delta2,
    theta,
    yc_shift,
    B,
    Bperp,
    bonds,
)
    os = triangular_yc_flux_opsum(
        C,
        J1,
        J2;
        Delta1,
        Delta2,
        theta,
        yc_shift,
        B,
        Bperp,
        bonds,
    )
    return InfiniteSum{MPO}(os, sites)
end

function run_vumps_update(
    H,
    psi;
    first_step,
    maxdim,
    cutoff,
    outer_iters_initial,
    vumps_tol,
    max_vumps_iters,
    multisite_update_alg,
    outputlevel,
)
    vumps_kwargs = (
        tol=vumps_tol,
        maxiter=max_vumps_iters,
        solver_tol=(x -> max(x / 100, SOLVER_TOL_FLOOR)),
        multisite_update_alg=multisite_update_alg,
        outputlevel=outputlevel,
    )

    if first_step
        subspace_expansion_kwargs = (cutoff=cutoff, maxdim=maxdim)
        return vumps_subspace_expansion(
            H,
            psi;
            outer_iters=outer_iters_initial,
            subspace_expansion_kwargs,
            vumps_kwargs,
        )
    end

    return tdvp(H, psi; time_step=-Inf, vumps_kwargs...)
end

function entropy_from_C(Ctensor)
    _, S, _ = svd(Ctensor, inds(Ctensor)[1])
    entropy = 0.0
    norm = 0.0
    for n in 1:dim(S, 1)
        p = real(S[n, n]^2)
        norm += p
        p > 0 && (entropy -= p * log(p))
    end
    return entropy, norm
end

function entanglement_entropies(psi)
    entropies = zeros(Float64, nsites(psi))
    norms = zeros(Float64, nsites(psi))
    for n in 1:nsites(psi)
        entropies[n], norms[n] = entropy_from_C(psi.C[n])
    end
    return entropies, norms
end

function energy_density(psi, H, C)
    terms = real.(expect(psi, H))
    return sum(terms) / C, terms
end

function transfer_matrix_spectrum(psi; neigs=16, tol=1e-10, krylovdim=max(neigs + 8, 2 * neigs))
    T = TransferMatrix(psi.AL)
    v0 = random_itensor(dag(input_inds(T)))
    alg = Arnoldi(; krylovdim=max(krylovdim, neigs + 2), tol)
    lambdas, vecs, _ = eigsolve(T, v0, neigs, :LM, alg)
    lambda0 = lambdas[1]
    normalized = lambdas ./ lambda0
    inverse_xi = map(eachindex(normalized)) do n
        n == 1 && return 0.0
        return -log(abs(normalized[n]))
    end
    xi = map(inverse_xi) do x
        iszero(x) ? Inf : inv(x)
    end
    momenta = angle.(normalized)
    flux_labels = String[]
    for v in vecs
        label = try
            string(flux(v))
        catch
            ""
        end
        push!(flux_labels, label)
    end
    return (; lambdas, normalized, inverse_xi, xi, momenta, flux_labels)
end

function output_filename(output_dir, C, yc_shift, J2, Delta1, Delta2, theta_pi, maxdim)
    theta_label = @sprintf("%.8g", theta_pi)
    return joinpath(
        output_dir,
        "ground_state_search_flux_threaded_vumps_YC$(C)-$(yc_shift)_J$(J2)_1Delta$(Delta1)_2Delta$(Delta2)_thetaPi$(theta_label)_chi$(maxdim).h5",
    )
end

function write_bond_table!(F, bonds)
    group = create_group(F, "unit_cell_bonds")
    group["family"] = string.([b.family for b in bonds])
    group["row"] = [b.row for b in bonds]
    group["drow"] = [b.drow for b in bonds]
    group["dcol"] = [b.dcol for b in bonds]
    group["row2"] = [b.row2 for b in bonds]
    group["col2"] = [b.col2 for b in bonds]
    group["winding"] = [b.winding for b in bonds]
    group["source_site"] = [b.source_site for b in bonds]
    group["target_site"] = [b.target_site for b in bonds]
    group["col_shift"] = [b.col_shift for b in bonds]
    return nothing
end

function save_results(
    filename;
    C,
    J1,
    J2,
    yc_shift,
    B,
    Bperp,
    Delta1,
    Delta2,
    theta_pi,
    fluxes,
    energy_densities,
    energy_terms,
    entropies,
    entropy_norms,
    maxlinkdims,
    transfer_lambdas,
    transfer_normalized_lambdas,
    transfer_inverse_xi,
    transfer_xi,
    transfer_momenta,
    transfer_flux_labels,
    maxdim,
    cutoff,
    vumps_tol,
    max_vumps_iters,
    outer_iters_initial,
    conserve_qns,
    blas_threads,
    strided_threads,
    bonds,
)
    h5open(filename, "w") do F
        F["C"] = C
        F["J1"] = J1
        F["J2"] = J2
        F["yc_shift"] = yc_shift
        F["B"] = B
        F["Bperp"] = Bperp
        F["Delta1"] = Delta1
        F["Delta2"] = Delta2
        F["theta_pi"] = theta_pi
        F["fluxes"] = fluxes
        F["fluxes_over_pi"] = fluxes ./ pi
        F["energy_densities"] = energy_densities
        F["energy_terms"] = energy_terms
        F["entropies"] = entropies
        F["entropy_norms"] = entropy_norms
        F["maxlinkdims"] = maxlinkdims
        F["transfer_lambdas"] = transfer_lambdas
        F["transfer_normalized_lambdas"] = transfer_normalized_lambdas
        F["transfer_inverse_xi"] = transfer_inverse_xi
        F["transfer_xi"] = transfer_xi
        F["transfer_momenta"] = transfer_momenta
        F["transfer_flux_labels"] = transfer_flux_labels
        F["maxdim"] = maxdim
        F["cutoff"] = cutoff
        F["vumps_tol"] = vumps_tol
        F["max_vumps_iters"] = max_vumps_iters
        F["solver_tol_scale"] = 100.0
        F["solver_tol_floor"] = SOLVER_TOL_FLOOR
        F["outer_iters_initial"] = outer_iters_initial
        F["conserve_qns"] = conserve_qns
        F["blas_threads"] = blas_threads
        if strided_threads !== missing
            F["strided_threads"] = strided_threads
        end
        write_bond_table!(F, bonds)
    end
    return filename
end

function fill_transfer_column!(dest, values, k)
    dest[:, k] .= eltype(dest) <: Complex ? complex(NaN, NaN) : NaN
    n = min(size(dest, 1), length(values))
    dest[1:n, k] .= values[1:n]
    return dest
end

function run_trajectory(;
    C=8,
    J1=1.0,
    J2=0.12,
    Delta1=1.0,
    Delta2=1.0,
    yc_shift=0,
    B=0.0,
    Bperp=0.0,
    theta_pi=2.0,
    nflux=9,
    maxdim=512,
    cutoff=1e-10,
    vumps_tol=DEFAULT_VUMPS_TOL,
    max_vumps_iters=DEFAULT_MAX_VUMPS_ITERS,
    outer_iters_initial=max(1, ceil(Int, log2(maxdim))),
    multisite_update_alg="sequential",
    conserve_qns=true,
    neigs=16,
    transfer_tol=1e-10,
    output_dir=default_output_dir(),
    outputlevel=1,
    blas_threads=default_blas_threads(),
    strided_threads=default_strided_threads(),
    gc_after_save=true,
)
    if conserve_qns && Bperp != 0.0
        error("Bperp uses Sx and breaks Sz conservation; set conserve_qns=false")
    end

    mkpath(output_dir)
    threading = configure_threading!(; blas_threads, strided_threads)

    theta_final = pi * theta_pi
    fluxes = nflux == 1 ? [theta_final] : collect(range(0.0, theta_final; length=nflux))

    sites = build_sites(C; conserve_qns)
    psi = InfMPS(sites, initial_state)
    bonds = yc_unit_cell_bonds(C, yc_shift)

    energy_densities = zeros(Float64, nflux)
    energy_terms = zeros(Float64, C, nflux)
    entropies = zeros(Float64, C, nflux)
    entropy_norms = zeros(Float64, C, nflux)
    maxlinkdims = zeros(Int, nflux)
    transfer_lambdas = fill(complex(NaN, NaN), neigs, nflux)
    transfer_normalized_lambdas = fill(complex(NaN, NaN), neigs, nflux)
    transfer_inverse_xi = fill(NaN, neigs, nflux)
    transfer_xi = fill(NaN, neigs, nflux)
    transfer_momenta = fill(NaN, neigs, nflux)
    transfer_flux_labels = fill("", neigs, nflux)

    final_filename = output_filename(
        output_dir,
        C,
        yc_shift,
        J2,
        Delta1,
        Delta2,
        theta_pi,
        maxdim,
    )

    for (k, theta) in enumerate(fluxes)
        theta_step_pi = theta / pi
        println("Flux step $k / $nflux: theta/pi = $theta_step_pi")
        H = build_hamiltonian(
            sites,
            C,
            J1,
            J2;
            Delta1,
            Delta2,
            theta,
            yc_shift,
            B,
            Bperp,
            bonds,
        )

        psi = run_vumps_update(
            H,
            psi;
            first_step=(k == 1),
            maxdim,
            cutoff,
            outer_iters_initial,
            vumps_tol,
            max_vumps_iters,
            multisite_update_alg,
            outputlevel,
        )

        edens, eterms = energy_density(psi, H, C)
        S, Snorms = entanglement_entropies(psi)
        spectrum = transfer_matrix_spectrum(psi; neigs, tol=transfer_tol)

        energy_densities[k] = edens
        energy_terms[:, k] .= eterms
        entropies[:, k] .= S
        entropy_norms[:, k] .= Snorms
        maxlinkdims[k] = maxlinkdim(psi)
        fill_transfer_column!(transfer_lambdas, spectrum.lambdas, k)
        fill_transfer_column!(transfer_normalized_lambdas, spectrum.normalized, k)
        fill_transfer_column!(transfer_inverse_xi, spectrum.inverse_xi, k)
        fill_transfer_column!(transfer_xi, spectrum.xi, k)
        fill_transfer_column!(transfer_momenta, spectrum.momenta, k)
        nlabels = min(neigs, length(spectrum.flux_labels))
        transfer_flux_labels[1:nlabels, k] .= spectrum.flux_labels[1:nlabels]

        println("energy density = $edens")
        println("mean entanglement entropy = $(mean(S))")
        println("maxlinkdim = $(maxlinkdims[k])")
        if length(spectrum.inverse_xi) >= 2
            println("leading inverse xi = $(spectrum.inverse_xi[2])")
            println("leading momentum = $(spectrum.momenta[2])")
            println("leading transfer flux label = $(spectrum.flux_labels[2])")
        end

        filename = output_filename(
            output_dir,
            C,
            yc_shift,
            J2,
            Delta1,
            Delta2,
            theta_step_pi,
            maxdim,
        )
        save_results(
            filename;
            C,
            J1,
            J2,
            yc_shift,
            B,
            Bperp,
            Delta1,
            Delta2,
            theta_pi=theta_step_pi,
            fluxes=fluxes[1:k],
            energy_densities=energy_densities[1:k],
            energy_terms=energy_terms[:, 1:k],
            entropies=entropies[:, 1:k],
            entropy_norms=entropy_norms[:, 1:k],
            maxlinkdims=maxlinkdims[1:k],
            transfer_lambdas=transfer_lambdas[:, 1:k],
            transfer_normalized_lambdas=transfer_normalized_lambdas[:, 1:k],
            transfer_inverse_xi=transfer_inverse_xi[:, 1:k],
            transfer_xi=transfer_xi[:, 1:k],
            transfer_momenta=transfer_momenta[:, 1:k],
            transfer_flux_labels=transfer_flux_labels[:, 1:k],
            maxdim,
            cutoff,
            vumps_tol,
            max_vumps_iters,
            outer_iters_initial,
            conserve_qns,
            blas_threads=threading.blas_threads,
            strided_threads=threading.strided_threads,
            bonds,
        )
        println("Saved trajectory through theta/pi = $theta_step_pi to $filename")

        H = nothing
        spectrum = nothing
        eterms = nothing
        S = nothing
        Snorms = nothing
        if gc_after_save
            GC.gc()
        end
    end

    return (;
        filename=final_filename,
        fluxes,
        energy_densities,
        energy_terms,
        entropies,
        maxlinkdims,
        transfer_lambdas,
        transfer_inverse_xi,
        transfer_momenta,
        psi,
    )
end

function parse_bool(s)
    return lowercase(s) in ("1", "true", "t", "yes", "y")
end

function usage()
    return """
    Usage:
      julia ground_state_search_flux_threaded_vumps.jl C J2 theta_over_pi maxdim [nflux=9] [yc_shift=0] [cutoff=1e-10] [vumps_tol=1e-5] [max_vumps_iters=20] [neigs=16] [output_dir]

    Examples:
      julia ground_state_search_flux_threaded_vumps.jl 8 0.12 2.0 512 17 0
      julia ground_state_search_flux_threaded_vumps.jl 8 0.12 1.0 512 17 1

    theta_over_pi is in units of pi. YC(Ly)-n is selected by C=Ly and yc_shift=n.
    """
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 4
        error(usage())
    end

    C = parse(Int, ARGS[1])
    J2 = parse(Float64, ARGS[2])
    theta_pi = parse(Float64, ARGS[3])
    maxdim = parse(Int, ARGS[4])
    nflux = length(ARGS) >= 5 ? parse(Int, ARGS[5]) : 9
    yc_shift = length(ARGS) >= 6 ? parse(Int, ARGS[6]) : 0
    cutoff = length(ARGS) >= 7 ? parse(Float64, ARGS[7]) : 1e-10
    vumps_tol = length(ARGS) >= 8 ? parse(Float64, ARGS[8]) : DEFAULT_VUMPS_TOL
    max_vumps_iters = length(ARGS) >= 9 ? parse(Int, ARGS[9]) : DEFAULT_MAX_VUMPS_ITERS
    neigs = length(ARGS) >= 10 ? parse(Int, ARGS[10]) : 16
    output_dir = length(ARGS) >= 11 ? ARGS[11] : default_output_dir()

    run_trajectory(;
        C,
        J2,
        theta_pi,
        maxdim,
        nflux,
        yc_shift,
        cutoff,
        vumps_tol,
        max_vumps_iters,
        neigs,
        output_dir,
    )
end
