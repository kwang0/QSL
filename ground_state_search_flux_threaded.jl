using MKL
using ITensors
using ITensorMPS
using HDF5
using LinearAlgebra
using Printf

const DEFAULT_SCRATCH_DIR = "/pscratch/sd/k/kwang98/QSL"

# Convert row/column labels to the MPS index, with periodic rows.
function idx(row, col, C)
    return col * C + mod(row, C) + 1
end

function yc_wrapped_endpoint(row, col, drow, dcol, C, yc_shift)
    raw_row = row + drow
    raw_col = col + dcol
    winding = fld(raw_row, C)
    wrapped_row = raw_row - winding * C
    wrapped_col = raw_col + winding * yc_shift
    return wrapped_row, wrapped_col, winding
end

function add_field!(os, site, B, Bperp)
    if B != 0.0
        os += -B, "Sz", site
    end
    if Bperp != 0.0
        os += -Bperp, "Sx", site
    end
    return os
end

function add_twisted_heisenberg_bond!(os, J, Delta, i, j, theta, winding)
    phase = cis(theta * winding)
    os += Delta * J, "Sz", i, "Sz", j
    os += 0.5 * J * phase, "S+", i, "S-", j
    os += 0.5 * J * conj(phase), "S-", i, "S+", j
    return os
end

function add_yc_bond!(os, C, L, row, col, drow, dcol, J, Delta, theta, yc_shift)
    i = idx(row, col, C)
    row2, col2, winding = yc_wrapped_endpoint(row, col, drow, dcol, C, yc_shift)
    if col2 < 0 || col2 >= L
        return os
    end
    j = idx(row2, col2, C)
    return add_twisted_heisenberg_bond!(os, J, Delta, i, j, theta, winding)
end

# J1-J2 triangular Heisenberg model on a finite YC cylinder.
# YC(Ly)-n identifies lattice sites related by Ly * a1 - n * a2.
# In row/column coordinates this means (row, col) == (row + Ly, col - n),
# so row-seam-crossing bonds shift their wrapped endpoint by n columns.
# Paper-style YC indexing:
#   row is the periodic direction, col is the open cylinder direction.
#   The three forward NN displacements are (1, 0), (0, 1), (-1, 1).
#   The three forward NNN displacements are (1, 1), (-2, 1), (-1, 2).
# The Aharonov-Bohm spin flux is in a boundary-seam gauge: only exchange
# terms whose row coordinate winds around the cylinder get phases.
function triangular_model_YC_flux(
    C,
    L,
    J1,
    J2;
    B=0.0,
    Bperp=0.0,
    Delta1=1.0,
    Delta2=1.0,
    theta=0.0,
    yc_shift=0,
)
    os = OpSum()

    for col in 0:(L - 1)
        for row in 0:(C - 1)
            site = idx(row, col, C)
            os = add_field!(os, site, B, Bperp)

            # Nearest neighbors.
            os = add_yc_bond!(os, C, L, row, col, 1, 0, J1, Delta1, theta, yc_shift)
            os = add_yc_bond!(os, C, L, row, col, 0, 1, J1, Delta1, theta, yc_shift)
            os = add_yc_bond!(os, C, L, row, col, -1, 1, J1, Delta1, theta, yc_shift)

            # Next-nearest neighbors.
            os = add_yc_bond!(os, C, L, row, col, 1, 1, J2, Delta2, theta, yc_shift)
            os = add_yc_bond!(os, C, L, row, col, -2, 1, J2, Delta2, theta, yc_shift)
            os = add_yc_bond!(os, C, L, row, col, -1, 2, J2, Delta2, theta, yc_shift)
        end
    end

    return os
end

function product_state(N, twosz)
    if isodd(N + twosz)
        error("N + twosz must be even; got N=$N, twosz=$twosz")
    end
    nup = div(N + twosz, 2)
    if nup < 0 || nup > N
        error("Requested twosz=$twosz is outside the spin-1/2 Hilbert space for N=$N")
    end

    state = Vector{String}(undef, N)
    ups_left = nup
    dns_left = N - nup
    for n in 1:N
        put_up = (isodd(n) && ups_left > 0) || dns_left == 0
        if put_up
            state[n] = "Up"
            ups_left -= 1
        else
            state[n] = "Dn"
            dns_left -= 1
        end
    end
    return state
end

function dmrg_ground(H, psi; nsweeps, maxdim, cutoff, noise, outputlevel)
    if noise > 0.0
        return dmrg(H, psi; nsweeps, maxdim, cutoff, noise, outputlevel)
    end
    return dmrg(H, psi; nsweeps, maxdim, cutoff, outputlevel)
end

function dmrg_excited(H, refs, psi; nsweeps, maxdim, cutoff, noise, weight, outputlevel)
    if noise > 0.0
        return dmrg(H, refs, psi; nsweeps, maxdim, cutoff, noise, weight, outputlevel)
    end
    return dmrg(H, refs, psi; nsweeps, maxdim, cutoff, weight, outputlevel)
end

function total_twosz(psi)
    return real(sum(2 .* expect(psi, "Sz")))
end

function default_output_dir()
    return isdir(DEFAULT_SCRATCH_DIR) ? DEFAULT_SCRATCH_DIR : "processed_data"
end

function output_filename(output_dir, C, L, yc_shift, J2, Delta1, Delta2, theta_pi, maxdim, label)
    theta_label = @sprintf("%.8g", theta_pi)
    return joinpath(
        output_dir,
        "ground_state_search_flux_threaded_YC$(C)-$(yc_shift)_L$(L)_J$(J2)_1Delta$(Delta1)_2Delta$(Delta2)_thetaPi$(theta_label)_$(label)_chi$(maxdim).h5",
    )
end

function save_both_gap_results(
    filename;
    C,
    L,
    yc_shift,
    J1,
    J2,
    B,
    Bperp,
    Delta1,
    Delta2,
    theta_pi,
    fluxes,
    E0s,
    E_neutral,
    E_spin,
    neutral_gaps,
    spin_gaps,
    M0s,
    M_neutral,
    M_spin,
    neutral_overlaps,
    ground_twosz,
    spin_twosz,
    maxdim,
    cutoff,
    nsweeps,
    weight,
    psi0,
    psi_neutral,
    psi_spin,
)
    h5open(filename, "w") do F
        F["C"] = C
        F["L"] = L
        F["yc_shift"] = yc_shift
        F["J1"] = J1
        F["J2"] = J2
        F["B"] = B
        F["Bperp"] = Bperp
        F["Delta1"] = Delta1
        F["Delta2"] = Delta2
        F["theta_pi"] = theta_pi
        F["fluxes"] = fluxes
        F["fluxes_over_pi"] = fluxes ./ pi
        F["E0s"] = E0s
        F["E_neutral"] = E_neutral
        F["E_spin"] = E_spin
        F["neutral_gaps"] = neutral_gaps
        F["spin_gaps"] = spin_gaps
        F["M0s"] = M0s
        F["M_neutral"] = M_neutral
        F["M_spin"] = M_spin
        F["neutral_overlaps"] = neutral_overlaps
        F["ground_twosz"] = ground_twosz
        F["spin_twosz"] = spin_twosz
        F["maxdim"] = maxdim
        F["cutoff"] = cutoff
        F["nsweeps"] = nsweeps
        F["weight"] = weight
        F["psi0"] = psi0
        F["psi_neutral"] = psi_neutral
        F["psi_spin"] = psi_spin
    end
end

function save_single_gap_results(
    filename;
    C,
    L,
    yc_shift,
    J1,
    J2,
    B,
    Bperp,
    Delta1,
    Delta2,
    theta_pi,
    fluxes,
    E0s,
    E1s,
    gaps,
    M0s,
    M1s,
    overlaps,
    maxdim,
    cutoff,
    nsweeps,
    weight,
    psi0,
    psi1,
)
    h5open(filename, "w") do F
        F["C"] = C
        F["L"] = L
        F["yc_shift"] = yc_shift
        F["J1"] = J1
        F["J2"] = J2
        F["B"] = B
        F["Bperp"] = Bperp
        F["Delta1"] = Delta1
        F["Delta2"] = Delta2
        F["theta_pi"] = theta_pi
        F["fluxes"] = fluxes
        F["fluxes_over_pi"] = fluxes ./ pi
        F["E0s"] = E0s
        F["E1s"] = E1s
        F["gaps"] = gaps
        F["M0s"] = M0s
        F["M1s"] = M1s
        F["overlaps"] = overlaps
        F["maxdim"] = maxdim
        F["cutoff"] = cutoff
        F["nsweeps"] = nsweeps
        F["weight"] = weight
        F["psi0"] = psi0
        F["psi1"] = psi1
    end
end

function run_trajectory_cpu(;
    C,
    L,
    J1,
    J2,
    B,
    Bperp,
    Delta1,
    Delta2,
    yc_shift,
    output_dir,
    theta_pi,
    nflux,
    nsweeps,
    maxdim,
    cutoff,
    weight,
    noise,
    ground_twosz,
    spin_twosz,
    initial_linkdim,
    conserve_qns,
    outputlevel,
)
    N = C * L
    theta_final = pi * theta_pi
    fluxes = nflux == 1 ? [theta_final] : collect(range(0.0, theta_final; length=nflux))

    sites = siteinds("S=1/2", N; conserve_qns)
    ground_state = product_state(N, ground_twosz)
    spin_state = product_state(N, spin_twosz)
    psi0 = randomMPS(sites, ground_state; linkdims=initial_linkdim)
    psi_neutral = randomMPS(sites, ground_state; linkdims=initial_linkdim)
    psi_spin = randomMPS(sites, spin_state; linkdims=initial_linkdim)

    E0s = zeros(Float64, length(fluxes))
    E_neutral = zeros(Float64, length(fluxes))
    E_spin = zeros(Float64, length(fluxes))
    neutral_gaps = zeros(Float64, length(fluxes))
    spin_gaps = zeros(Float64, length(fluxes))
    M0s = zeros(Float64, length(fluxes))
    M_neutral = zeros(Float64, length(fluxes))
    M_spin = zeros(Float64, length(fluxes))
    neutral_overlaps = fill(NaN, length(fluxes))

    for (k, theta) in enumerate(fluxes)
        println("Flux step $k / $(length(fluxes)): theta = $theta ($(theta / pi) * pi)")
        H = MPO(
            triangular_model_YC_flux(
                C,
                L,
                J1,
                J2;
                B,
                Bperp,
                Delta1,
                Delta2,
                theta,
                yc_shift,
            ),
            sites,
        )

        E0, psi0 = dmrg_ground(
            H,
            psi0;
            nsweeps,
            maxdim,
            cutoff,
            noise,
            outputlevel,
        )

        Eneu, psi_neutral = dmrg_excited(
            H,
            [psi0],
            psi_neutral;
            nsweeps,
            maxdim,
            cutoff,
            noise,
            weight,
            outputlevel,
        )
        neutral_overlaps[k] = abs(inner(psi0, psi_neutral))

        Espin, psi_spin = dmrg_ground(
            H,
            psi_spin;
            nsweeps,
            maxdim,
            cutoff,
            noise,
            outputlevel,
        )

        E0s[k] = E0
        E_neutral[k] = Eneu
        E_spin[k] = Espin
        neutral_gaps[k] = Eneu - E0
        spin_gaps[k] = Espin - E0
        M0s[k] = total_twosz(psi0)
        M_neutral[k] = total_twosz(psi_neutral)
        M_spin[k] = total_twosz(psi_spin)

        println("E0 = $(E0s[k])")
        println("E neutral = $(E_neutral[k])")
        println("E spin = $(E_spin[k])")
        println("neutral gap = $(neutral_gaps[k])")
        println("spin gap = $(spin_gaps[k])")
        println("2Sz ground = $(M0s[k])")
        println("2Sz neutral = $(M_neutral[k])")
        println("2Sz spin = $(M_spin[k])")

        theta_step_pi = theta / pi
        filename = output_filename(output_dir, C, L, yc_shift, J2, Delta1, Delta2, theta_step_pi, maxdim, "bothgaps")
        save_both_gap_results(
            filename;
            C,
            L,
            yc_shift,
            J1,
            J2,
            B,
            Bperp,
            Delta1,
            Delta2,
            theta_pi=theta_step_pi,
            fluxes=fluxes[1:k],
            E0s=E0s[1:k],
            E_neutral=E_neutral[1:k],
            E_spin=E_spin[1:k],
            neutral_gaps=neutral_gaps[1:k],
            spin_gaps=spin_gaps[1:k],
            M0s=M0s[1:k],
            M_neutral=M_neutral[1:k],
            M_spin=M_spin[1:k],
            neutral_overlaps=neutral_overlaps[1:k],
            ground_twosz,
            spin_twosz,
            maxdim,
            cutoff,
            nsweeps,
            weight,
            psi0,
            psi_neutral,
            psi_spin,
        )
        println("Saved trajectory through theta/pi = $theta_step_pi to $filename")
    end

    return (;
        fluxes,
        E0s,
        E_neutral,
        E_spin,
        neutral_gaps,
        spin_gaps,
        M0s,
        M_neutral,
        M_spin,
        neutral_overlaps,
        psi0,
        psi_neutral,
        psi_spin,
    )
end

function run_trajectory_gpu(;
    C,
    L,
    J1,
    J2,
    B,
    Bperp,
    Delta1,
    Delta2,
    yc_shift,
    output_dir,
    theta_pi,
    nflux,
    nsweeps,
    maxdim,
    cutoff,
    weight,
    noise,
    outputlevel,
)
    N = C * L
    theta_final = pi * theta_pi
    fluxes = nflux == 1 ? [theta_final] : collect(range(0.0, theta_final; length=nflux))

    sites = siteinds("S=1/2", N; conserve_qns=false)
    psi0 = cu(randomMPS(sites))
    psi1 = cu(randomMPS(sites))

    E0s = zeros(Float64, length(fluxes))
    E1s = zeros(Float64, length(fluxes))
    gaps = zeros(Float64, length(fluxes))
    M0s = zeros(Float64, length(fluxes))
    M1s = zeros(Float64, length(fluxes))
    overlaps = fill(NaN, length(fluxes))

    for (k, theta) in enumerate(fluxes)
        println("Flux step $k / $(length(fluxes)): theta = $theta ($(theta / pi) * pi)")
        H = cu(
            MPO(
                triangular_model_YC_flux(
                    C,
                    L,
                    J1,
                    J2;
                    B,
                    Bperp,
                    Delta1,
                    Delta2,
                    theta,
                    yc_shift,
                ),
                sites,
            ),
        )

        E0, psi0 = dmrg_ground(
            H,
            psi0;
            nsweeps,
            maxdim,
            cutoff,
            noise,
            outputlevel,
        )

        E1, psi1 = dmrg_excited(
            H,
            [psi0],
            psi1;
            nsweeps,
            maxdim,
            cutoff,
            noise,
            weight,
            outputlevel,
        )

        psi0_cpu = ITensors.cpu(psi0)
        psi1_cpu = ITensors.cpu(psi1)
        E0s[k] = E0
        E1s[k] = E1
        gaps[k] = E1 - E0
        M0s[k] = total_twosz(psi0_cpu)
        M1s[k] = total_twosz(psi1_cpu)
        overlaps[k] = abs(inner(psi0, psi1))

        println("E0 = $(E0s[k])")
        println("E1 = $(E1s[k])")
        println("gap = $(gaps[k])")
        println("2Sz ground = $(M0s[k])")
        println("2Sz excited = $(M1s[k])")

        theta_step_pi = theta / pi
        filename = output_filename(output_dir, C, L, yc_shift, J2, Delta1, Delta2, theta_step_pi, maxdim, "gap")
        save_single_gap_results(
            filename;
            C,
            L,
            yc_shift,
            J1,
            J2,
            B,
            Bperp,
            Delta1,
            Delta2,
            theta_pi=theta_step_pi,
            fluxes=fluxes[1:k],
            E0s=E0s[1:k],
            E1s=E1s[1:k],
            gaps=gaps[1:k],
            M0s=M0s[1:k],
            M1s=M1s[1:k],
            overlaps=overlaps[1:k],
            maxdim,
            cutoff,
            nsweeps,
            weight,
            psi0=psi0_cpu,
            psi1=psi1_cpu,
        )
        println("Saved GPU trajectory through theta/pi = $theta_step_pi to $filename")
    end

    return (;
        fluxes,
        E0s,
        E1s,
        gaps,
        M0s,
        M1s,
        overlaps,
        psi0=ITensors.cpu(psi0),
        psi1=ITensors.cpu(psi1),
    )
end

function main(;
    C=6,
    L=36,
    J1=1.0,
    J2=0.12,
    B=0.0,
    Bperp=0.0,
    Delta1=1.0,
    Delta2=1.0,
    yc_shift=0,
    theta_pi=1.0,
    nflux=9,
    nsweeps=10,
    cutoff=1e-10,
    maxdim=512,
    weight=20.0,
    noise=0.0,
    ground_twosz=0,
    spin_twosz=2,
    initial_linkdim=16,
    conserve_qns=true,
    use_gpu=false,
    output_dir=default_output_dir(),
    outputlevel=1,
)
    if !use_gpu && Bperp != 0.0
        error("Bperp uses Sx and breaks total Sz conservation; this CPU script always uses QN sectors")
    end
    if use_gpu
        @eval using CUDA
    end
    BLAS.set_num_threads(use_gpu ? 1 : 256)

    mkpath(output_dir)
    label = use_gpu ? "gap" : "bothgaps"
    final_filename = output_filename(output_dir, C, L, yc_shift, J2, Delta1, Delta2, theta_pi, maxdim, label)

    println("Writing flux-threading trajectory files to $output_dir")
    GC.gc()
    if use_gpu
        result = run_trajectory_gpu(;
            C,
            L,
            J1,
            J2,
            B,
            Bperp,
            Delta1,
            Delta2,
            yc_shift,
            output_dir,
            theta_pi,
            nflux,
            nsweeps,
            maxdim,
            cutoff,
            weight,
            noise,
            outputlevel,
        )
        println("Final E0 = $(result.E0s[end])")
        println("Final gap = $(result.gaps[end])")
    else
        result = run_trajectory_cpu(;
            C,
            L,
            J1,
            J2,
            B,
            Bperp,
            Delta1,
            Delta2,
            yc_shift,
            output_dir,
            theta_pi,
            nflux,
            nsweeps,
            maxdim,
            cutoff,
            weight,
            noise,
            ground_twosz,
            spin_twosz,
            initial_linkdim,
            conserve_qns,
            outputlevel,
        )
        println("Final E0 = $(result.E0s[end])")
        println("Final neutral gap = $(result.neutral_gaps[end])")
        println("Final spin gap = $(result.spin_gaps[end])")
    end
    return final_filename
end

ITensors.Strided.set_num_threads(1)

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) < 6
        error(
            "Usage: julia ground_state_search_flux_threaded.jl C L J2 Delta theta_over_pi maxdim [nflux=9] [nsweeps=10] [yc_shift=0] [use_gpu=false] [output_dir]",
        )
    end

    C = parse(Int, ARGS[1])
    L = parse(Int, ARGS[2])
    J2 = parse(Float64, ARGS[3])
    Delta = parse(Float64, ARGS[4])
    theta_pi = parse(Float64, ARGS[5])
    maxdim = parse(Int, ARGS[6])
    nflux = length(ARGS) >= 7 ? parse(Int, ARGS[7]) : 9
    nsweeps = length(ARGS) >= 8 ? parse(Int, ARGS[8]) : 10
    yc_shift = 0
    use_gpu = false
    output_dir = default_output_dir()
    if length(ARGS) >= 9
        parsed_shift = tryparse(Int, ARGS[9])
        if parsed_shift === nothing
            use_gpu = lowercase(ARGS[9]) in ("1", "true", "t", "yes", "y")
            output_dir = length(ARGS) >= 10 ? ARGS[10] : default_output_dir()
        else
            yc_shift = parsed_shift
            if length(ARGS) >= 10
                parsed_gpu = lowercase(ARGS[10]) in ("1", "true", "t", "yes", "y", "0", "false", "f", "no", "n")
                if parsed_gpu
                    use_gpu = lowercase(ARGS[10]) in ("1", "true", "t", "yes", "y")
                    output_dir = length(ARGS) >= 11 ? ARGS[11] : default_output_dir()
                else
                    output_dir = ARGS[10]
                end
            end
        end
    end

    main(;
        C,
        L,
        J2,
        Delta1=Delta,
        Delta2=Delta,
        yc_shift,
        theta_pi,
        maxdim,
        nflux,
        nsweeps,
        use_gpu,
        output_dir,
    )
end
