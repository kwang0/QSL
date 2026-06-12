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
const DEFAULT_VUMPS_TOL = 1e-4
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

function parse_env_bool(keys, default)
    for key in keys
        if haskey(ENV, key) && !isempty(strip(ENV[key]))
            return parse_bool(ENV[key])
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
        ),
        1,
    )
end

function default_strided_threads()
    return parse_env_int(("ITENSOR_STRIDED_THREADS", "NDTENSORS_STRIDED_THREADS"), 1)
end

function default_threaded_blocksparse()
    return parse_env_bool(("ITENSOR_THREADED_BLOCKSPARSE", "NDTENSORS_THREADED_BLOCKSPARSE"), false)
end

function configure_threading!(
    ;
    blas_threads=default_blas_threads(),
    strided_threads=default_strided_threads(),
    threaded_blocksparse=default_threaded_blocksparse(),
)
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
    active_threaded_blocksparse = try
        if threaded_blocksparse
            ITensors.enable_threaded_blocksparse()
        else
            ITensors.disable_threaded_blocksparse()
        end
        ITensors.using_threaded_blocksparse()
    catch err
        @warn "Could not configure ITensors block-sparse threading" exception = err
        missing
    end
    if active_threaded_blocksparse === true &&
       (BLAS.get_num_threads() != 1 ||
        (active_strided_threads !== missing && active_strided_threads != 1))
        @warn "ITensors recommends avoiding competing threading backends with block-sparse threading; set BLAS and ITensors.Strided threads to 1 for block-sparse benchmarks."
    end
    println(
        "Threading: Julia=$(Threads.nthreads()), BLAS=$(BLAS.get_num_threads()), ITensors.Strided=$(active_strided_threads), ITensors.BlockSparse=$(active_threaded_blocksparse)",
    )
    return (;
        blas_threads=BLAS.get_num_threads(),
        strided_threads=active_strided_threads,
        threaded_blocksparse=active_threaded_blocksparse,
    )
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

function checkpoint_filename(output_dir, C, yc_shift, J2, Delta1, Delta2, theta_pi, maxdim)
    return replace(output_filename(output_dir, C, yc_shift, J2, Delta1, Delta2, theta_pi, maxdim), r"\.h5$" => "_checkpoint.h5")
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

function replace_checkpoint_file(tmp_checkpoint_file, checkpoint_file)
    if Sys.iswindows() && isfile(checkpoint_file)
        rm(checkpoint_file; force=true)
    end
    Base.Filesystem.rename(tmp_checkpoint_file, checkpoint_file)
    return nothing
end

function checkpoint_value_matches(actual, expected)
    if expected isa AbstractFloat
        return isapprox(Float64(real(actual)), Float64(expected); atol=1e-12, rtol=1e-12)
    end
    if expected isa Bool
        return Bool(actual) == expected
    end
    return actual == expected
end

function compatible_checkpoint(F; checks)
    for (name, expected) in checks
        if !haskey(F, name)
            return false, "missing $name"
        end
        actual = read(F, name)
        if !checkpoint_value_matches(actual, expected)
            return false, "$name is $actual, expected $expected"
        end
    end
    return true, ""
end

function copy_completed_vector!(dest, src, completed_flux_step, name)
    completed_flux_step == 0 && return dest
    length(src) >= completed_flux_step ||
        error("Checkpoint dataset $name has length $(length(src)), expected at least $completed_flux_step")
    dest[1:completed_flux_step] .= src[1:completed_flux_step]
    return dest
end

function copy_completed_matrix!(dest, src, completed_flux_step, name)
    completed_flux_step == 0 && return dest
    ndims(src) == 2 || error("Checkpoint dataset $name is not a matrix")
    size(src, 1) == size(dest, 1) ||
        error("Checkpoint dataset $name has first dimension $(size(src, 1)), expected $(size(dest, 1))")
    size(src, 2) >= completed_flux_step ||
        error("Checkpoint dataset $name has second dimension $(size(src, 2)), expected at least $completed_flux_step")
    dest[:, 1:completed_flux_step] .= src[:, 1:completed_flux_step]
    return dest
end

function load_vumps_checkpoint(
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
    nflux,
    maxdim,
    conserve_qns,
    neigs,
)
    isfile(filename) || return nothing

    h5open(filename, "r") do F
        if !haskey(F, "psi")
            @warn "Ignoring checkpoint without psi state" filename
            return nothing
        end
        compatible, reason = compatible_checkpoint(
            F;
            checks=(
                ("C", C),
                ("J1", J1),
                ("J2", J2),
                ("yc_shift", yc_shift),
                ("B", B),
                ("Bperp", Bperp),
                ("Delta1", Delta1),
                ("Delta2", Delta2),
                ("theta_pi", theta_pi),
                ("nflux", nflux),
                ("maxdim", maxdim),
                ("conserve_qns", conserve_qns),
                ("neigs", neigs),
            ),
        )
        if !compatible
            @warn "Ignoring incompatible checkpoint" filename reason
            return nothing
        end

        completed_flux_step = haskey(F, "completed_flux_step") ? Int(read(F, "completed_flux_step")) : 0
        0 <= completed_flux_step <= nflux ||
            error("Checkpoint completed_flux_step=$completed_flux_step is outside 0:$nflux")

        return (;
            psi=read(F, "psi", InfiniteCanonicalMPS),
            completed_flux_step,
            energy_densities=haskey(F, "energy_densities") ? read(F, "energy_densities") : Float64[],
            energy_terms=haskey(F, "energy_terms") ? read(F, "energy_terms") : zeros(Float64, C, 0),
            entropies=haskey(F, "entropies") ? read(F, "entropies") : zeros(Float64, C, 0),
            entropy_norms=haskey(F, "entropy_norms") ? read(F, "entropy_norms") : zeros(Float64, C, 0),
            maxlinkdims=haskey(F, "maxlinkdims") ? Int.(read(F, "maxlinkdims")) : Int[],
            transfer_lambdas=haskey(F, "transfer_lambdas") ? read(F, "transfer_lambdas") : fill(complex(NaN, NaN), neigs, 0),
            transfer_normalized_lambdas=haskey(F, "transfer_normalized_lambdas") ? read(F, "transfer_normalized_lambdas") : fill(complex(NaN, NaN), neigs, 0),
            transfer_inverse_xi=haskey(F, "transfer_inverse_xi") ? read(F, "transfer_inverse_xi") : zeros(Float64, neigs, 0),
            transfer_xi=haskey(F, "transfer_xi") ? read(F, "transfer_xi") : zeros(Float64, neigs, 0),
            transfer_momenta=haskey(F, "transfer_momenta") ? read(F, "transfer_momenta") : zeros(Float64, neigs, 0),
            transfer_flux_labels=haskey(F, "transfer_flux_labels") ? read(F, "transfer_flux_labels") : fill("", neigs, 0),
        )
    end
end

function restore_checkpoint_data!(
    checkpoint,
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
)
    completed_flux_step = checkpoint.completed_flux_step
    copy_completed_vector!(energy_densities, checkpoint.energy_densities, completed_flux_step, "energy_densities")
    copy_completed_matrix!(energy_terms, checkpoint.energy_terms, completed_flux_step, "energy_terms")
    copy_completed_matrix!(entropies, checkpoint.entropies, completed_flux_step, "entropies")
    copy_completed_matrix!(entropy_norms, checkpoint.entropy_norms, completed_flux_step, "entropy_norms")
    copy_completed_vector!(maxlinkdims, checkpoint.maxlinkdims, completed_flux_step, "maxlinkdims")
    copy_completed_matrix!(transfer_lambdas, checkpoint.transfer_lambdas, completed_flux_step, "transfer_lambdas")
    copy_completed_matrix!(
        transfer_normalized_lambdas,
        checkpoint.transfer_normalized_lambdas,
        completed_flux_step,
        "transfer_normalized_lambdas",
    )
    copy_completed_matrix!(transfer_inverse_xi, checkpoint.transfer_inverse_xi, completed_flux_step, "transfer_inverse_xi")
    copy_completed_matrix!(transfer_xi, checkpoint.transfer_xi, completed_flux_step, "transfer_xi")
    copy_completed_matrix!(transfer_momenta, checkpoint.transfer_momenta, completed_flux_step, "transfer_momenta")
    copy_completed_matrix!(transfer_flux_labels, checkpoint.transfer_flux_labels, completed_flux_step, "transfer_flux_labels")
    return completed_flux_step
end

function save_vumps_checkpoint(
    filename,
    psi,
    completed_flux_step;
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
    neigs,
    transfer_tol,
    threaded_blocksparse,
)
    tmp_checkpoint_file = filename * ".tmp"
    h5open(tmp_checkpoint_file, "w") do F
        F["vumps_checkpoint_version"] = 1
        F["completed_flux_step"] = completed_flux_step
        F["vumps_checkpoint_complete"] = completed_flux_step >= length(fluxes) ? 1 : 0
        F["vumps_checkpoint_unix_time"] = time()
        F["psi"] = psi
        F["C"] = C
        F["J1"] = J1
        F["J2"] = J2
        F["yc_shift"] = yc_shift
        F["B"] = B
        F["Bperp"] = Bperp
        F["Delta1"] = Delta1
        F["Delta2"] = Delta2
        F["theta_pi"] = theta_pi
        F["nflux"] = length(fluxes)
        F["fluxes"] = fluxes
        F["fluxes_over_pi"] = fluxes ./ pi
        F["energy_densities"] = energy_densities[1:completed_flux_step]
        F["energy_terms"] = energy_terms[:, 1:completed_flux_step]
        F["entropies"] = entropies[:, 1:completed_flux_step]
        F["entropy_norms"] = entropy_norms[:, 1:completed_flux_step]
        F["maxlinkdims"] = maxlinkdims[1:completed_flux_step]
        F["transfer_lambdas"] = transfer_lambdas[:, 1:completed_flux_step]
        F["transfer_normalized_lambdas"] = transfer_normalized_lambdas[:, 1:completed_flux_step]
        F["transfer_inverse_xi"] = transfer_inverse_xi[:, 1:completed_flux_step]
        F["transfer_xi"] = transfer_xi[:, 1:completed_flux_step]
        F["transfer_momenta"] = transfer_momenta[:, 1:completed_flux_step]
        F["transfer_flux_labels"] = transfer_flux_labels[:, 1:completed_flux_step]
        F["maxdim"] = maxdim
        F["cutoff"] = cutoff
        F["vumps_tol"] = vumps_tol
        F["max_vumps_iters"] = max_vumps_iters
        F["solver_tol_scale"] = 100.0
        F["solver_tol_floor"] = SOLVER_TOL_FLOOR
        F["outer_iters_initial"] = outer_iters_initial
        F["conserve_qns"] = conserve_qns
        F["neigs"] = neigs
        F["transfer_tol"] = transfer_tol
        if threaded_blocksparse !== missing
            F["threaded_blocksparse"] = threaded_blocksparse
        end
    end
    replace_checkpoint_file(tmp_checkpoint_file, filename)
    return filename
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
    threaded_blocksparse,
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
        if threaded_blocksparse !== missing
            F["threaded_blocksparse"] = threaded_blocksparse
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
    threaded_blocksparse=default_threaded_blocksparse(),
    resume=true,
    checkpoint_file=nothing,
    gc_after_save=true,
)
    if conserve_qns && Bperp != 0.0
        error("Bperp uses Sx and breaks Sz conservation; set conserve_qns=false")
    end

    mkpath(output_dir)
    threading = configure_threading!(; blas_threads, strided_threads, threaded_blocksparse)

    theta_final = pi * theta_pi
    fluxes = nflux == 1 ? [theta_final] : collect(range(0.0, theta_final; length=nflux))

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
    checkpoint_file = isnothing(checkpoint_file) ? checkpoint_filename(output_dir, C, yc_shift, J2, Delta1, Delta2, theta_pi, maxdim) : checkpoint_file
    mkpath(dirname(checkpoint_file))

    psi = nothing
    completed_flux_step = 0
    if resume
        checkpoint = load_vumps_checkpoint(
            checkpoint_file;
            C,
            J1,
            J2,
            yc_shift,
            B,
            Bperp,
            Delta1,
            Delta2,
            theta_pi,
            nflux,
            maxdim,
            conserve_qns,
            neigs,
        )
        if checkpoint !== nothing
            psi = checkpoint.psi
            completed_flux_step = restore_checkpoint_data!(
                checkpoint,
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
            )
            println("Resuming from checkpoint $checkpoint_file after flux step $completed_flux_step / $nflux")
        else
            println("No compatible checkpoint found at $checkpoint_file; starting from theta/pi = 0.0")
        end
    else
        println("Resume disabled; starting from theta/pi = 0.0")
    end

    if psi === nothing
        sites = build_sites(C; conserve_qns)
        psi = InfMPS(sites, initial_state)
    else
        sites = siteinds(psi)
    end

    if completed_flux_step >= nflux
        println("Checkpoint already contains all $nflux flux step(s); nothing to do.")
        return (;
            filename=final_filename,
            checkpoint_file,
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

    for k in (completed_flux_step + 1):nflux
        theta = fluxes[k]
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
            first_step=(completed_flux_step == 0 && k == 1),
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
            threaded_blocksparse=threading.threaded_blocksparse,
            bonds,
        )
        println("Saved trajectory through theta/pi = $theta_step_pi to $filename")
        save_vumps_checkpoint(
            checkpoint_file,
            psi,
            k;
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
            neigs,
            transfer_tol,
            threaded_blocksparse=threading.threaded_blocksparse,
        )
        println("Saved VUMPS checkpoint through flux step $k / $nflux to $checkpoint_file")

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
        checkpoint_file,
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
      julia ground_state_search_flux_threaded_vumps.jl C J2 theta_over_pi maxdim [nflux=9] [yc_shift=0] [cutoff=1e-10] [vumps_tol=1e-4] [max_vumps_iters=20] [neigs=16] [output_dir] [threaded_blocksparse=false] [resume=true] [checkpoint_file=auto]

    Examples:
      julia ground_state_search_flux_threaded_vumps.jl 8 0.12 2.0 512 17 0
      julia ground_state_search_flux_threaded_vumps.jl 8 0.12 1.0 512 17 1

    theta_over_pi is in units of pi. YC(Ly)-n is selected by C=Ly and yc_shift=n.
    Default threading follows the ITensors CPU guidance used here: BLAS=1, ITensors.Strided=1, and block-sparse threading off unless explicitly enabled.
    With resume=true, an existing compatible checkpoint resumes from the next unfinished flux step.
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
    threaded_blocksparse = length(ARGS) >= 12 ? parse_bool(ARGS[12]) : default_threaded_blocksparse()
    resume = length(ARGS) >= 13 ? parse_bool(ARGS[13]) : true
    checkpoint_file = length(ARGS) >= 14 && !isempty(strip(ARGS[14])) ? ARGS[14] : nothing

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
        threaded_blocksparse,
        resume,
        checkpoint_file,
    )
end
