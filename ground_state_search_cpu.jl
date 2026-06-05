using MKL
using ITensors
using ITensorMPS
using Printf
using PyPlot
using HDF5
using LinearAlgebra

function entropy_von_neumann(ψ, b)
  ψ = orthogonalize(ψ, b)
  U,S,V = svd(ψ[b], (linkinds(ψ, b-1)..., siteinds(ψ, b)...))
  SvN = 0.0
  for n=1:dim(S, 1)
    p = S[n,n]^2
    SvN -= p * log(p)
  end
  return SvN
end

# Converts index into physical coordinate on triangular lattice (centers MPS site N/2 at coord (0,0))
function coord(i, C, L)
    y = (i-1) % C
    x = (i-1) ÷ C
    if (y % 2 == 1)
        x += 0.5
    end
    x -= (L/2 - 0.5)
    y -= (C-1)
    y *= sqrt(3)/2
    return [x, y]
end

# Convert row/col label to MPS index, with PBC in rows
function idx(row, col, C)
    return col * C + mod(row, C) + 1
end

# Generate Hamiltonian of J1-J2 Heisenberg model on triangular lattice
# Lattice has length L and height C, with PBC along height (cylindrical).
# XC geometry.
function triangular_model(C, L, J1, J2, B=0.0, Bperp=0.0, Δ1 = 1.0, Δ2 = 1.0)
    os = OpSum()

    for col in range(0,L-1)
        for row in range(0,C-1)
            index = idx(row, col, C)

            # Applied field
            if (B != 0.0 || Bperp != 0.0)
                os += -B, "Sz", index
                os += -Bperp, "Sx", index
            end
            
            # NN couplings
            os += Δ1*J1, "Sz", index, "Sz", idx(row + 1, col, C)
            os += 0.5*J1, "S+", index, "S-", idx(row + 1, col, C)
            os += 0.5*J1, "S-", index, "S+", idx(row + 1, col, C)

            if (col < L-1)
                os += Δ1*J1, "Sz", index, "Sz", idx(row, col + 1, C)
                os += 0.5*J1, "S+", index, "S-", idx(row, col + 1, C)
                os += 0.5*J1, "S-", index, "S+", idx(row, col + 1, C)

                # Odd rows
                if (row % 2 == 1)
                    os += Δ1*J1, "Sz", index, "Sz", idx(row + 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", idx(row + 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", idx(row + 1, col + 1, C)

                    os += Δ1*J1, "Sz", index, "Sz", idx(row - 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", idx(row - 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", idx(row - 1, col + 1, C)
                end
            end

            # NNN couplings
            os += Δ2*J2, "Sz", index, "Sz", idx(row + 2, col, C)
            os += 0.5*J2, "S+", index, "S-", idx(row + 2, col, C)
            os += 0.5*J2, "S-", index, "S+", idx(row + 2, col, C)

            if ((col < L-1) && (row % 2 == 0))
                os += Δ2*J2, "Sz", index, "Sz", idx(row + 1, col + 1, C)
                os += 0.5*J2, "S+", index, "S-", idx(row + 1, col + 1, C)
                os += 0.5*J2, "S-", index, "S+", idx(row + 1, col + 1, C)

                os += Δ2*J2, "Sz", index, "Sz", idx(row - 1, col + 1, C)
                os += 0.5*J2, "S+", index, "S-", idx(row - 1, col + 1, C)
                os += 0.5*J2, "S-", index, "S+", idx(row - 1, col + 1, C)
            elseif ((col < L-2) && (row % 2 == 1))
                os += Δ2*J2, "Sz", index, "Sz", idx(row + 1, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", idx(row + 1, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", idx(row + 1, col + 2, C)

                os += Δ2*J2, "Sz", index, "Sz", idx(row - 1, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", idx(row - 1, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", idx(row - 1, col + 2, C)
            end
        end
    end

    return os
end

# Generate Hamiltonian of J1-J2 Heisenberg model on triangular lattice
# Lattice has length L and height C, with PBC along height (cylindrical).
# YC geometry.
function triangular_model_YC(C, L, J1, J2, B=0.0, Bperp=0.0, Δ1 = 1.0, Δ2 = 1.0)
    os = OpSum()

    for col in range(0,L-1)
        for row in range(0,C-1)
            index = idx(row, col, C)

            # Applied field
            if (B != 0.0 || Bperp != 0.0)
                os += -B, "Sz", index
                os += -Bperp, "Sx", index
            end
            
            # NN couplings
            os += Δ1*J1, "Sz", index, "Sz", idx(row + 1, col, C)
            os += 0.5*J1, "S+", index, "S-", idx(row + 1, col, C)
            os += 0.5*J1, "S-", index, "S+", idx(row + 1, col, C)

            if (col < L-1)
                os += Δ1*J1, "Sz", index, "Sz", idx(row, col + 1, C)
                os += 0.5*J1, "S+", index, "S-", idx(row, col + 1, C)
                os += 0.5*J1, "S-", index, "S+", idx(row, col + 1, C)

                # Even/odd columns
                if (col % 2 == 0)
                    os += Δ1*J1, "Sz", index, "Sz", idx(row - 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", idx(row - 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", idx(row - 1, col + 1, C)
                else
                    os += Δ1*J1, "Sz", index, "Sz", idx(row + 1, col + 1, C)
                    os += 0.5*J1, "S+", index, "S-", idx(row + 1, col + 1, C)
                    os += 0.5*J1, "S-", index, "S+", idx(row + 1, col + 1, C)
                end
            end

            # NNN couplings
            if (col < L-1)
                # Even/odd columns
                if (col % 2 == 0)
                    os += Δ2*J2, "Sz", index, "Sz", idx(row + 1, col + 1, C)
                    os += 0.5*J2, "S+", index, "S-", idx(row + 1, col + 1, C)
                    os += 0.5*J2, "S-", index, "S+", idx(row + 1, col + 1, C)

                    os += Δ2*J2, "Sz", index, "Sz", idx(row - 2, col + 1, C)
                    os += 0.5*J2, "S+", index, "S-", idx(row - 2, col + 1, C)
                    os += 0.5*J2, "S-", index, "S+", idx(row - 2, col + 1, C)
                else
                    os += Δ2*J2, "Sz", index, "Sz", idx(row + 2, col + 1, C)
                    os += 0.5*J2, "S+", index, "S-", idx(row + 2, col + 1, C)
                    os += 0.5*J2, "S-", index, "S+", idx(row + 2, col + 1, C)

                    os += Δ2*J2, "Sz", index, "Sz", idx(row - 1, col + 1, C)
                    os += 0.5*J2, "S+", index, "S-", idx(row - 1, col + 1, C)
                    os += 0.5*J2, "S-", index, "S+", idx(row - 1, col + 1, C)
                end
            end
            if (col < L-2)
                os += Δ2*J2, "Sz", index, "Sz", idx(row, col + 2, C)
                os += 0.5*J2, "S+", index, "S-", idx(row, col + 2, C)
                os += 0.5*J2, "S-", index, "S+", idx(row, col + 2, C)
            end
        end
    end

    return os
end

# Generate Hamiltonian of J1-J2 Heisenberg model on square lattice
# Lattice has length L and height C, with PBC along height (cylindrical).
function square_model(C, L, J1=1.0)
    os = OpSum()

    for col in range(0,L-1)
        for row in range(0,C-1)
            index = idx(row, col, C)
            
            # NN couplings
            os += J1, "Sz", index, "Sz", idx(row + 1, col, C)
            os += 0.5*J1, "S+", index, "S-", idx(row + 1, col, C)
            os += 0.5*J1, "S-", index, "S+", idx(row + 1, col, C)

            if (col < L-1)
                os += J1, "Sz", index, "Sz", idx(row, col + 1, C)
                os += 0.5*J1, "S+", index, "S-", idx(row, col + 1, C)
                os += 0.5*J1, "S-", index, "S+", idx(row, col + 1, C)
            end
        end
    end

    return os
end

function output_filename(C, L, J2, Δ1, Δ2, maxdim)
    output_dir = get(ENV, "QSL_OUTPUT_DIR", "/pscratch/sd/k/kwang98/QSL")
    return joinpath(output_dir, "ground_state_search_C$(C)_L$(L)_J$(J2)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim).h5")
end

function checkpoint_filename(filename)
    return endswith(filename, ".h5") ? filename[1:(end - 3)] * "_checkpoint.h5" : filename * ".checkpoint.h5"
end

function read_vector_or_empty(F, name)
    return haskey(F, name) ? collect(read(F, name)) : Float64[]
end

function parse_bool_arg(arg)
    value = lowercase(arg)
    if value in ("true", "t", "1", "yes", "y")
        return true
    elseif value in ("false", "f", "0", "no", "n")
        return false
    end
    return nothing
end

function parse_optional_args(args)
    resume = true
    initial_psi_file = nothing
    initial_psi_dataset = "psi0"

    if length(args) >= 6
        parsed_resume = parse_bool_arg(args[6])
        if isnothing(parsed_resume)
            initial_psi_file = args[6]
            length(args) >= 7 && (initial_psi_dataset = args[7])
        else
            resume = parsed_resume
            length(args) >= 7 && (initial_psi_file = args[7])
            length(args) >= 8 && (initial_psi_dataset = args[8])
        end
    end

    return (resume=resume, initial_psi_file=initial_psi_file, initial_psi_dataset=initial_psi_dataset)
end

function completed_output_exists(filename)
    if !isfile(filename)
        return false
    end

    try
        h5open(filename, "r") do F
            return haskey(F, "psi0") &&
                   haskey(F, "dmrg_checkpoint_complete") &&
                   read(F, "dmrg_checkpoint_complete") == 1
        end
    catch err
        @warn "Could not read final output file $filename; will try checkpoint if available" exception = err
        return false
    end
end

function load_initial_wavefunction(initial_psi_file, initial_psi_dataset)
    isnothing(initial_psi_file) && return nothing
    isfile(initial_psi_file) || error("Initial wavefunction file does not exist: $initial_psi_file")

    h5open(initial_psi_file, "r") do F
        if !haskey(F, initial_psi_dataset)
            error("Initial wavefunction file $initial_psi_file does not contain dataset '$initial_psi_dataset'")
        end
        return read(F, initial_psi_dataset, MPS)
    end
end

function checked_siteinds(ψ, N, source)
    length(ψ) == N || error("Wavefunction from $source has length $(length(ψ)), expected $N")
    return collect(siteinds(ψ))
end

function load_dmrg_checkpoint(checkpoint_file)
    if !isfile(checkpoint_file)
        return nothing
    end

    h5open(checkpoint_file, "r") do F
        if !haskey(F, "psi0")
            return nothing
        end

        return (
            psi = read(F, "psi0", MPS),
            completed_sweeps = haskey(F, "dmrg_completed_sweeps") ? read(F, "dmrg_completed_sweeps") : 0,
            energy = haskey(F, "E0") ? read(F, "E0") : NaN,
            sweep_energies = read_vector_or_empty(F, "sweep_energies"),
            sweep_maxerrs = read_vector_or_empty(F, "sweep_maxerrs"),
            initial_psi_file = haskey(F, "initial_psi_file") ? read(F, "initial_psi_file") : "",
            initial_psi_dataset = haskey(F, "initial_psi_dataset") ? read(F, "initial_psi_dataset") : "psi0",
        )
    end
end

function replace_checkpoint_file(tmp_checkpoint_file, checkpoint_file)
    if Sys.iswindows() && isfile(checkpoint_file)
        rm(checkpoint_file; force=true)
    end
    Base.Filesystem.rename(tmp_checkpoint_file, checkpoint_file)
    return nothing
end

function save_dmrg_checkpoint(
    checkpoint_file,
    ψ,
    completed_sweeps,
    energy,
    maxerr,
    sweep_energies,
    sweep_maxerrs;
    C,
    L,
    J1,
    J2,
    B,
    Bperp,
    Δ1,
    Δ2,
    cutoff,
    maxdim,
    nsweeps,
    initial_psi_file = "",
    initial_psi_dataset = "psi0",
)
    tmp_checkpoint_file = checkpoint_file * ".tmp"
    h5open(tmp_checkpoint_file, "w") do F
        F["psi0"] = ψ
        F["E0"] = energy
        F["dmrg_completed_sweeps"] = completed_sweeps
        F["dmrg_requested_sweeps"] = nsweeps
        F["dmrg_checkpoint_unix_time"] = time()
        F["dmrg_checkpoint_complete"] = completed_sweeps >= nsweeps ? 1 : 0
        F["final_maxerr"] = maxerr
        F["sweep_energies"] = sweep_energies
        F["sweep_maxerrs"] = sweep_maxerrs
        F["C"] = C
        F["L"] = L
        F["J1"] = J1
        F["J2"] = J2
        F["B"] = B
        F["Bperp"] = Bperp
        F["Delta1"] = Δ1
        F["Delta2"] = Δ2
        F["cutoff"] = cutoff
        F["maxdim"] = maxdim
        F["initial_psi_file"] = initial_psi_file
        F["initial_psi_dataset"] = initial_psi_dataset
    end
    replace_checkpoint_file(tmp_checkpoint_file, checkpoint_file)
    println("Saved DMRG checkpoint after sweep $completed_sweeps to $checkpoint_file")
    flush(stdout)
    return nothing
end

mutable struct CheckpointDMRGObserver <: ITensorMPS.AbstractObserver
    inner::ITensorMPS.DMRGObserver
    checkpoint_file::String
    sweep_offset::Int
    previous_sweep_energies::Vector{Float64}
    previous_sweep_maxerrs::Vector{Float64}
    checkpoint_kwargs::NamedTuple
end

function CheckpointDMRGObserver(
    checkpoint_file;
    energy_tol,
    sweep_offset = 0,
    previous_sweep_energies = Float64[],
    previous_sweep_maxerrs = Float64[],
    checkpoint_kwargs...,
)
    return CheckpointDMRGObserver(
        ITensorMPS.DMRGObserver(; energy_tol=energy_tol),
        checkpoint_file,
        sweep_offset,
        previous_sweep_energies,
        previous_sweep_maxerrs,
        (; checkpoint_kwargs...),
    )
end

function all_sweep_energies(observer::CheckpointDMRGObserver)
    return vcat(observer.previous_sweep_energies, ITensorMPS.energies(observer.inner))
end

function all_sweep_maxerrs(observer::CheckpointDMRGObserver)
    return vcat(observer.previous_sweep_maxerrs, ITensorMPS.truncerrors(observer.inner))
end

function ITensorMPS.measure!(observer::CheckpointDMRGObserver; kwargs...)
    ITensorMPS.measure!(observer.inner; kwargs...)

    if get(kwargs, :sweep_is_done, false)
        completed_sweeps = observer.sweep_offset + kwargs[:sweep]
        sweep_maxerrs = all_sweep_maxerrs(observer)
        maxerr = isempty(sweep_maxerrs) ? NaN : sweep_maxerrs[end]
        save_dmrg_checkpoint(
            observer.checkpoint_file,
            kwargs[:psi],
            completed_sweeps,
            kwargs[:energy],
            maxerr,
            all_sweep_energies(observer),
            sweep_maxerrs;
            observer.checkpoint_kwargs...,
        )
    end
    return nothing
end

function ITensorMPS.checkdone!(observer::CheckpointDMRGObserver; kwargs...)
    return ITensorMPS.checkdone!(observer.inner; kwargs...)
end

function main(;
    C=4,
    L=6,
    J1=1.0,
    J2=0.0,
    B=0.0,
    Bperp=0.0,
    Δ1=1.0,
    Δ2=1.0,
    cutoff=1e-12,
    maxdim=32,
    resume=true,
    initial_psi_file=nothing,
    initial_psi_dataset="psi0",
)
    N = C * L

    filename = output_filename(C, L, J2, Δ1, Δ2, maxdim)
    checkpoint_file = checkpoint_filename(filename)
    # filename = "/pscratch/sd/k/kwang98/QSL/ground_state_search_C$(C)_L$(L)_J$(J2)_B$(B)_Bperp$(Bperp)_1Delta$(Δ1)_2Delta$(Δ2)_chi$(maxdim).h5"

    nsweeps = 20
    energy_tol = 1e-6

    state = [isodd(n) ? "Up" : "Dn" for n=1:N]

    # B_sat = 4.5
    # N_spinup = ((B * N / 2) ÷ B_sat) + (N ÷ 2) # Naive guess for magnetization
    # state = [n ≤ N_spinup ? "Up" : "Dn" for n=1:N]

    GC.gc()
    checkpoint = (resume && !completed_output_exists(filename)) ? load_dmrg_checkpoint(checkpoint_file) : nothing
    if !isnothing(checkpoint)
        ψ = checkpoint.psi
        sites = checked_siteinds(ψ, N, checkpoint_file)
        completed_sweeps = checkpoint.completed_sweeps
        previous_sweep_energies = checkpoint.sweep_energies
        previous_sweep_maxerrs = checkpoint.sweep_maxerrs
        checkpoint_energy = checkpoint.energy
        if isnothing(initial_psi_file) && !isempty(checkpoint.initial_psi_file)
            initial_psi_file = checkpoint.initial_psi_file
            initial_psi_dataset = checkpoint.initial_psi_dataset
        end
        println("Loaded DMRG checkpoint from $checkpoint_file after $completed_sweeps completed sweeps")
        flush(stdout)
    else
        initial_ψ = load_initial_wavefunction(initial_psi_file, initial_psi_dataset)
        if isnothing(initial_ψ)
            sites = siteinds("S=1/2", N; conserve_qns=true)
            ψ = randomMPS(sites, state, linkdims = 16)
        else
            ψ = initial_ψ
            sites = checked_siteinds(ψ, N, initial_psi_file)
            println("Loaded initial wavefunction '$initial_psi_dataset' from $initial_psi_file")
            flush(stdout)
        end
        completed_sweeps = 0
        previous_sweep_energies = Float64[]
        previous_sweep_maxerrs = Float64[]
        checkpoint_energy = NaN
    end
    initial_psi_file_string = isnothing(initial_psi_file) ? "" : initial_psi_file

    H = MPO(triangular_model(C, L, J1, J2, B, Bperp, Δ1, Δ2), sites)

    remaining_sweeps = max(nsweeps - completed_sweeps, 0)
    observer = CheckpointDMRGObserver(
        checkpoint_file;
        energy_tol=energy_tol,
        sweep_offset=completed_sweeps,
        previous_sweep_energies=previous_sweep_energies,
        previous_sweep_maxerrs=previous_sweep_maxerrs,
        C,
        L,
        J1,
        J2,
        B,
        Bperp,
        Δ1,
        Δ2,
        cutoff,
        maxdim,
        nsweeps,
        initial_psi_file=initial_psi_file_string,
        initial_psi_dataset=initial_psi_dataset,
    )

    if remaining_sweeps == 0
        println("Checkpoint already has $completed_sweeps sweeps; skipping DMRG")
        flush(stdout)
        E0 = checkpoint_energy
        ψ0 = ψ
    else
        println("Running $remaining_sweeps DMRG sweeps")
        flush(stdout)
        E0, ψ0 = dmrg(H, ψ; nsweeps=remaining_sweeps, maxdim, cutoff, observer)
    end

    sweep_energies = all_sweep_energies(observer)
    sweep_maxerrs = all_sweep_maxerrs(observer)
    dmrg_completed_sweeps = length(sweep_energies)
    final_maxerr = isempty(sweep_maxerrs) ? NaN : sweep_maxerrs[end]
    H2 = inner(H, ψ0, H, ψ0)
    if isnan(E0)
        E0 = inner(ψ0, H, ψ0)
    end
    energy_variance = real(H2 - E0^2)
    energy_variance_per_site = energy_variance / N

    println("E0 = $E0")
    println("final maxerr = $final_maxerr")
    println("energy variance = $energy_variance")
    println("energy variance per site = $energy_variance_per_site")
    Zs = Array(expect(ψ0, "Sz"))

    S = entropy_von_neumann(ψ0, div(N, 2))
    println("S = $S")
    corrs = correlation_matrix(ψ0, "Sz", "Sz")

    F = h5open(filename,"w")
    F["S"] = S
    F["Zs"] = Zs
    F["corrs"] = corrs
    F["psi0"] = ψ0
    F["E0"] = E0
    F["final_maxerr"] = final_maxerr
    F["sweep_energies"] = sweep_energies
    F["sweep_maxerrs"] = sweep_maxerrs
    F["energy_variance"] = energy_variance
    F["energy_variance_per_site"] = energy_variance_per_site
    F["dmrg_completed_sweeps"] = dmrg_completed_sweeps
    F["dmrg_requested_sweeps"] = nsweeps
    F["dmrg_checkpoint_file"] = checkpoint_file
    F["dmrg_checkpoint_complete"] = 1
    F["initial_psi_file"] = initial_psi_file_string
    F["initial_psi_dataset"] = initial_psi_dataset
    close(F)
end

# ITensors.Strided.set_num_threads(1)
# BLAS.set_num_threads(256)

BLAS.set_num_threads(1)
ITensors.Strided.disable_threads()
ITensors.enable_threaded_blocksparse()

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    C = parse(Int64, ARGS[1])
    L = parse(Int64, ARGS[2])
    J2 = parse(Float64, ARGS[3])
    # Bperp = parse(Float64, ARGS[4])
    Δ = parse(Float64, ARGS[4])
    maxdim = parse(Int64, ARGS[5])
    options = parse_optional_args(ARGS)

    main(; C=C, L=L, J2=J2, Δ1=Δ, Δ2=Δ, maxdim=maxdim, options...)
end
