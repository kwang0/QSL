module ProjectBIDMRG

using Dates
using HDF5
using LinearAlgebra
using MPSKit
using SHA
using Serialization
using TOML
using TensorKit

const BRIDGE_SCHEMA_VERSIONS = (1, 2, 3)
const REQUIRED_MPSKIT_VERSION = v"0.13.13"
const REQUIRED_HDF5_VERSION = v"0.17.3"
const REQUIRED_TENSORKIT_VERSION = v"0.17.1"

export load_control, load_bridge, build_state, build_hamiltonian, run_control,
    write_result, write_lightweight_archive, file_sha256, native_converged,
    load_result_seed, run_benchmark, write_benchmark_result,
    benchmark_timing_preflight, benchmark_result_io_preflight

file_sha256(path::AbstractString) = open(path, "r") do io
    bytes2hex(sha256(io))
end

function require_exact_environment()
    VERSION.major == 1 && VERSION.minor == 12 || error(
        "Project B requires Julia 1.12.x; loaded $VERSION",
    )
    Base.pkgversion(MPSKit) == REQUIRED_MPSKIT_VERSION || error(
        "Project B pins MPSKit $REQUIRED_MPSKIT_VERSION; loaded $(Base.pkgversion(MPSKit))",
    )
    Base.pkgversion(HDF5) == REQUIRED_HDF5_VERSION || error(
        "Project B pins HDF5 $REQUIRED_HDF5_VERSION; loaded $(Base.pkgversion(HDF5))",
    )
    Base.pkgversion(TensorKit) == REQUIRED_TENSORKIT_VERSION || error(
        "Project B pins TensorKit $REQUIRED_TENSORKIT_VERSION; " *
        "loaded $(Base.pkgversion(TensorKit))",
    )
    return true
end

# Julia 1.12 has no `Base.cputime`. Use libuv's public process-rusage API,
# which is bundled with Julia on both macOS and Perlmutter Linux. Keep the C
# layout explicit so the benchmark records user plus system CPU time rather
# than relabeling wall time as CPU time.
struct UVTimeval
    seconds::Int64
    microseconds::Int32
end

struct UVRUsage
    user_time::UVTimeval
    system_time::UVTimeval
    counters::NTuple{14,UInt64}
end

function process_cpu_seconds()
    usage = Ref{UVRUsage}()
    status = ccall(:uv_getrusage, Cint, (Ref{UVRUsage},), usage)
    status == 0 || error("uv_getrusage failed with status $status")
    value = usage[]
    return Float64(value.user_time.seconds + value.system_time.seconds) +
        Float64(value.user_time.microseconds + value.system_time.microseconds) / 1e6
end

function measure_wall_and_cpu(f::F) where {F}
    cpu_start = process_cpu_seconds()
    value = nothing
    elapsed_seconds = @elapsed value = f()
    cpu_seconds = process_cpu_seconds() - cpu_start
    isfinite(elapsed_seconds) && elapsed_seconds >= 0 ||
        error("benchmark wall timer returned an invalid duration")
    isfinite(cpu_seconds) && cpu_seconds >= 0 ||
        error("benchmark process CPU timer returned an invalid duration")
    return (; value, elapsed_seconds, cpu_seconds)
end

function benchmark_timing_preflight()
    require_exact_environment()
    measurement = measure_wall_and_cpu() do
        accumulator = 0.0
        for index in 1:250_000
            accumulator += sin(index)
        end
        accumulator
    end
    measurement.cpu_seconds > 0 ||
        error("benchmark process CPU timer did not advance during executable preflight")
    isfinite(measurement.value) || error("benchmark timing preflight returned a non-finite value")
    return measurement
end

function load_control(path::AbstractString)
    absolute = abspath(path)
    raw = TOML.parsefile(absolute)
    get(raw, "artifact_kind", "") == "project_b_phase1_idmrg_control" ||
        error("not a Project B iDMRG control file: $absolute")
    get(raw, "schema_version", 0) in (1, 2, 3) || error("unsupported control schema")
    bridge = raw["bridge"]
    bridge_path = isabspath(bridge["path"]) ? bridge["path"] :
        normpath(joinpath(dirname(absolute), bridge["path"]))
    isfile(bridge_path) || error("missing bridge file: $bridge_path")
    file_sha256(bridge_path) == lowercase(bridge["sha256"]) ||
        error("bridge SHA-256 mismatch")
    return (; path=absolute, raw, bridge_path=abspath(bridge_path))
end

function read_string(file, name)
    return String(read(file, name))
end

function load_bridge(path::AbstractString)
    return h5open(path, "r") do file
        schema_version = Int(read(file, "schema_version"))
        schema_version in BRIDGE_SCHEMA_VERSIONS ||
            error("unsupported bridge schema")
        read_string(file, "artifact_kind") == "project_b_itensor_mpskit_bridge" ||
            error("unexpected bridge artifact kind")
        period = Int(read(file, "geometry/mps_period"))
        period == 2 || error("Project B iDMRG control requires period 2")
        tensors = map(1:period) do site
            prefix = "state/site_$site"
            (;
                data=ComplexF64.(read(file, "$prefix/AL")),
                left_charges=Int.(read(file, "$prefix/left_charges")),
                physical_charges=Int.(read(file, "$prefix/physical_charges")),
                right_charges=Int.(read(file, "$prefix/right_charges")),
            )
        end
        families = String.(read(file, "model/bonds/family"))
        sources = Int.(read(file, "model/bonds/source_site"))
        targets = Int.(read(file, "model/bonds/target_site"))
        couplings = Float64.(read(file, "model/bonds/coupling"))
        anisotropies = Float64.(read(file, "model/bonds/anisotropy"))
        twist_charges = Float64.(read(file, "model/bonds/twist_charge"))
        bonds = map(eachindex(sources)) do i
            (;
                family=families[i],
                source=sources[i],
                target=targets[i],
                coupling=couplings[i],
                anisotropy=anisotropies[i],
                twist_charge=twist_charges[i],
            )
        end
        energy_reference_path = schema_version == 2 ?
            "validation/seed_energy_density_at_target" :
            "validation/parent_energy_density_at_target"
        parent_sha256 = read_string(file, "lineage/parent_state_sha256")
        parent_path = read_string(file, "lineage/parent_state_path")
        numerical_seed_path = schema_version == 2 ?
            read_string(file, "lineage/numerical_seed_path") : parent_path
        numerical_seed_sha256 = schema_version == 2 ?
            read_string(file, "lineage/numerical_seed_sha256") : parent_sha256
        parent_theta = Float64(read(file, "lineage/parent_theta_over_pi"))
        return (;
            schema_version,
            path=abspath(path),
            parent_path,
            parent_sha256,
            parent_theta,
            root_sha256=haskey(file, "lineage/root_state_sha256") ?
                read_string(file, "lineage/root_state_sha256") : parent_sha256,
            root_theta=haskey(file, "lineage/root_theta_over_pi") ?
                Float64(read(file, "lineage/root_theta_over_pi")) : parent_theta,
            target_theta=Float64(read(file, "model/target_theta_over_pi")),
            parent_energy=Float64(read(file, energy_reference_path)),
            numerical_seed_kind=schema_version == 2 ?
                read_string(file, "lineage/numerical_seed_kind") : "accepted_parent",
            numerical_seed_path,
            numerical_seed_sha256,
            numerical_seed_theta=schema_version == 2 ?
                Float64(read(file, "lineage/numerical_seed_theta_over_pi")) : parent_theta,
            model_energy_tolerance=Float64(read(
                file,
                "validation/model_energy_density_tolerance",
            )),
            period,
            tensors,
            bonds,
        )
    end
end

function u1space(charges::AbstractVector{<:Integer})
    counts = Dict{Int,Int}()
    for charge in charges
        counts[Int(charge)] = get(counts, Int(charge), 0) + 1
    end
    return Rep[U₁]((charge => counts[charge] for charge in sort!(collect(keys(counts))))...)
end

function tensor_basis_charges(space)
    charges = Int[]
    for sector in sectors(space)
        append!(charges, fill(Int(getfield(sector, :charge)), dim(space, sector)))
    end
    return charges
end

function basis_permutation(source::AbstractVector{<:Integer}, target::AbstractVector{<:Integer})
    length(source) == length(target) || error("basis dimensions differ")
    queues = Dict{Int,Vector{Int}}()
    for (position, charge) in pairs(source)
        push!(get!(queues, Int(charge), Int[]), position)
    end
    consumed = Dict{Int,Int}()
    permutation = Int[]
    for charge in target
        q = Int(charge)
        position = get(consumed, q, 0) + 1
        haskey(queues, q) && position <= length(queues[q]) ||
            error("charge multiplicities differ for U(1) sector $q")
        push!(permutation, queues[q][position])
        consumed[q] = position
    end
    return permutation
end

function bridge_tensor(entry)
    left = u1space(entry.left_charges)
    physical = u1space(entry.physical_charges)
    right = u1space(entry.right_charges)
    pleft = basis_permutation(entry.left_charges, tensor_basis_charges(left))
    pphysical = basis_permutation(entry.physical_charges, tensor_basis_charges(physical))
    pright = basis_permutation(entry.right_charges, tensor_basis_charges(right))
    data = entry.data[pleft, pphysical, pright]
    tensor = TensorMap(data, left ⊗ physical ← right)
    roundtrip = convert(Array, tensor)[
        invperm(pleft), invperm(pphysical), invperm(pright)
    ]
    norm(roundtrip - entry.data) <= 5e-13 * max(norm(entry.data), 1) ||
        error("ITensor-to-TensorKit basis conversion failed its exact round trip")
    return tensor
end

function build_state(bridge; tol::Real=1e-12, maxiter::Integer=2_000)
    tensors = bridge_tensor.(bridge.tensors)
    state = InfiniteMPS(tensors; tol=Float64(tol), maxiter=Int(maxiter))
    length(state) == bridge.period || error("MPSKit changed the unit-cell period")
    all(dim(right_virtualspace(state, i)) == 512 for i in 1:bridge.period) ||
        error("import did not preserve chi 512")
    return state
end

function spin_operators()
    physical = Rep[U₁](1 => 1, -1 => 1)
    order = tensor_basis_charges(physical)
    position = Dict(charge => only(findall(==(charge), order)) for charge in (-1, 1))
    sz = zeros(ComplexF64, 2, 2)
    sp = zeros(ComplexF64, 2, 2)
    sm = zeros(ComplexF64, 2, 2)
    sz[position[1], position[1]] = 0.5
    sz[position[-1], position[-1]] = -0.5
    sp[position[1], position[-1]] = 1
    sm[position[-1], position[1]] = 1
    # S+ and S- carry charge, so use their neutral products below rather than
    # constructing them as standalone symmetry-preserving TensorMaps.
    return (; physical, order, sz, sp, sm)
end

function two_site_operator(bond, theta_over_pi::Real)
    operators = spin_operators()
    phase = cis(pi * Float64(theta_over_pi) * bond.twist_charge)
    data = zeros(ComplexF64, 2, 2, 2, 2)
    for source_out in 1:2, target_out in 1:2,
            source_in in 1:2, target_in in 1:2
        data[source_out, target_out, source_in, target_in] = bond.coupling * (
            bond.anisotropy * operators.sz[source_out, source_in] *
                operators.sz[target_out, target_in] +
            0.5 * phase * operators.sp[source_out, source_in] *
                operators.sm[target_out, target_in] +
            0.5 * conj(phase) * operators.sm[source_out, source_in] *
                operators.sp[target_out, target_in]
        )
    end
    # Keep the source/target axes explicit. A naive `reshape(kron(...))` in
    # Julia's column-major order swaps the two sites and conjugates the twist.
    return TensorMap(data, operators.physical ⊗ operators.physical ←
        operators.physical ⊗ operators.physical)
end

function build_hamiltonian(bridge)
    lattice = fill(spin_operators().physical, bridge.period)
    terms = Pair[]
    for bond in bridge.bonds
        push!(terms, (bond.source, bond.target) => two_site_operator(bond, bridge.target_theta))
    end
    return InfiniteMPOHamiltonian(lattice, terms)
end

function native_converged(history, control)
    native = control["native_convergence"]
    minimum_iterations = Int(native["minimum_iterations"])
    window = Int(native["energy_window"])
    length(history.iteration) >= max(minimum_iterations, window) || return false
    last(history.environment_error) <= Float64(native["environment_tolerance"]) || return false
    energies = @view history.energy_density[(end - window + 1):end]
    maximum(energies) - minimum(energies) <= Float64(native["energy_density_span_tolerance"]) ||
        return false
    return all(==(512), @view history.maximum_bond_dimension[(end - window + 1):end])
end

function initial_solver(state, hamiltonian, algorithm)
    envs = MPSKit.environments(state, hamiltonian)
    epsilon = Float64(MPSKit.calc_galerkin(state, hamiltonian, state, envs))
    energy = MPSKit.expectation_value(state, hamiltonian, envs)
    timer = MPSKit.TimerOutput("Project B IDMRG")
    MPSKit.disable_timer!(timer)
    solver_state = MPSKit.IDMRGState(state, hamiltonian, envs, 0, epsilon, energy, timer)
    return MPSKit.IterativeSolver(algorithm, solver_state)
end

function history_buffers()
    return (;
        iteration=Int[],
        environment_error=Float64[],
        energy_density=Float64[],
        energy_density_delta=Float64[],
        cumulative_superblock_energy_per_site=Float64[],
        discarded_weight=Float64[],
        maximum_bond_dimension=Int[],
        elapsed_seconds=Float64[],
    )
end

function append_history!(history, iteration, epsilon, energy, delta, state, elapsed)
    push!(history.iteration, Int(iteration))
    push!(history.environment_error, Float64(epsilon))
    # In pinned MPSKit 0.13.13, the one-site IDMRG iterator reports ΔE from
    # the growing superblock energy.  The period-normalized increment is the
    # intensive energy density; state.energy itself is cumulative and must not
    # be used in the native stationarity window.
    intensive_energy_density = Float64(real(delta) / length(state))
    push!(history.energy_density, intensive_energy_density)
    push!(history.energy_density_delta, intensive_energy_density)
    push!(
        history.cumulative_superblock_energy_per_site,
        Float64(real(energy) / length(state)),
    )
    # One-site iDMRG changes no bond space and performs no SVD truncation.
    push!(history.discarded_weight, 0.0)
    push!(history.maximum_bond_dimension,
        maximum(dim(right_virtualspace(state, i)) for i in 1:length(state)))
    push!(history.elapsed_seconds, Float64(elapsed))
    return history
end

function serialize_solver(solver)
    io = IOBuffer()
    serialize(io, solver)
    return take!(io)
end

function checkpoint_path(directory::AbstractString, iteration::Integer)
    return joinpath(directory, "checkpoint_iteration_$(lpad(iteration, 4, '0')).h5")
end

function write_checkpoint(directory, solver, history, control_sha256, bridge_sha256)
    mkpath(directory)
    path = checkpoint_path(directory, solver.state.iter)
    ispath(path) && error("refusing to overwrite immutable checkpoint: $path")
    bytes = serialize_solver(solver)
    h5open(path * ".tmp", "w") do file
        file["schema_version"] = 2
        file["artifact_kind"] = "project_b_mpskit_idmrg_checkpoint"
        file["created_at_utc"] = string(now(UTC))
        file["mpskit_version"] = string(Base.pkgversion(MPSKit))
        file["control_sha256"] = control_sha256
        file["bridge_sha256"] = bridge_sha256
        file["iteration"] = solver.state.iter
        file["solver_serialization"] = bytes
        for name in propertynames(history)
            file["history/$(String(name))"] = getproperty(history, name)
        end
    end
    mv(path * ".tmp", path)
    return (;
        path=abspath(path),
        sha256=file_sha256(path),
        iteration=Int(solver.state.iter),
        bytes=Int(stat(path).size),
    )
end

function resume_solver(path, control_sha256, bridge_sha256)
    return h5open(path, "r") do file
        read_string(file, "artifact_kind") == "project_b_mpskit_idmrg_checkpoint" ||
            error("not an iDMRG checkpoint")
        read_string(file, "mpskit_version") == string(REQUIRED_MPSKIT_VERSION) ||
            error("checkpoint MPSKit version mismatch")
        read_string(file, "control_sha256") == control_sha256 ||
            error("checkpoint control hash mismatch")
        read_string(file, "bridge_sha256") == bridge_sha256 ||
            error("checkpoint bridge hash mismatch")
        solver = deserialize(IOBuffer(Vector{UInt8}(read(file, "solver_serialization"))))
        history = history_buffers()
        for name in propertynames(history)
            history_path = "history/$(String(name))"
            if haskey(file, history_path)
                append!(getproperty(history, name), read(file, history_path))
            elseif name == :cumulative_superblock_energy_per_site
                append!(
                    history.cumulative_superblock_energy_per_site,
                    fill(NaN, length(history.iteration)),
                )
            else
                error("checkpoint is missing $history_path")
            end
        end
        return solver, history
    end
end

function run_control(
    control_path::AbstractString;
    resume::Union{Nothing,AbstractString}=nothing,
    checkpoint_directory_override::Union{Nothing,AbstractString}=nothing,
)
    require_exact_environment()
    control_record = load_control(control_path)
    control = control_record.raw
    lineage = control["lineage"]
    bridge = load_bridge(control_record.bridge_path)
    bridge.parent_sha256 == lineage["parent_state_sha256"] ||
        error("control/bridge parent hash mismatch")
    if Int(control["schema_version"]) == 2
        bridge.numerical_seed_sha256 == lineage["numerical_seed_sha256"] ||
            error("control/bridge numerical-seed hash mismatch")
        bridge.numerical_seed_kind == lineage["numerical_seed_kind"] ||
            error("control/bridge numerical-seed classification mismatch")
    end
    if haskey(lineage, "root_state_sha256")
        bridge.root_sha256 == lineage["root_state_sha256"] ||
            error("control/bridge lineage-root hash mismatch")
    end
    control_parent_theta = Float64(lineage["parent_theta_over_pi"])
    control_target_theta = Float64(lineage["target_theta_over_pi"])
    isapprox(bridge.parent_theta, control_parent_theta; atol=1e-12, rtol=0) ||
        error("control/bridge parent theta mismatch")
    isapprox(bridge.target_theta, control_target_theta; atol=1e-12, rtol=0) ||
        error("control/bridge target theta mismatch")
    0.0 <= control_parent_theta < control_target_theta <= 1.0 ||
        error("control does not describe a forward theta step")
    control_sha = file_sha256(control_record.path)
    bridge_sha = file_sha256(bridge.path)
    algorithm = IDMRG(
        tol=Float64(control["native_convergence"]["environment_tolerance"]),
        maxiter=Int(control["solver"]["maximum_iterations"]),
        verbosity=Int(control["solver"]["verbosity"]),
    )
    validation_state = build_state(bridge)
    validation_hamiltonian = build_hamiltonian(bridge)
    validation_solver = initial_solver(validation_state, validation_hamiltonian, algorithm)
    initial_energy_density = Float64(
        real(validation_solver.state.energy) / length(validation_state),
    )
    model_equivalence_error = abs(initial_energy_density - bridge.parent_energy)
    model_equivalence_error <= bridge.model_energy_tolerance || error(
        "ITensor/MPSKit seed Hamiltonian equivalence failed: energy-density difference " *
        "$model_equivalence_error exceeds $(bridge.model_energy_tolerance)",
    )
    solver, history = if resume === nothing
        candidate_solver = validation_solver
        candidate_solver, history_buffers()
    else
        resume_solver(abspath(resume), control_sha, bridge_sha)
    end
    checkpoints = NamedTuple[]
    maximum_iterations = Int(control["solver"]["maximum_iterations"])
    checkpoint_every = Int(control["storage"]["checkpoint_every_iterations"])
    storage_backend = String(get(control["storage"], "backend", "package_directory"))
    if storage_backend == "perlmutter_scratch" && checkpoint_directory_override === nothing
        error("scratch-backed control requires an explicit checkpoint-directory override")
    end
    checkpoint_value = checkpoint_directory_override === nothing ?
        String(control["storage"]["checkpoint_directory"]) :
        String(checkpoint_directory_override)
    checkpoint_directory = isabspath(checkpoint_value) ? normpath(checkpoint_value) :
        normpath(joinpath(dirname(control_record.path), checkpoint_value))
    if checkpoint_directory_override !== nothing && !isabspath(checkpoint_value)
        error("checkpoint-directory override must be absolute")
    end
    while solver.state.iter < maximum_iterations
        value = nothing
        elapsed = @elapsed value = iterate(solver)
        value === nothing && break
        (_, _, epsilon, delta), _ = value
        append_history!(history, solver.state.iter, epsilon, solver.state.energy,
            delta, solver.state.mps, elapsed)
        if solver.state.iter % checkpoint_every == 0 || native_converged(history, control)
            push!(checkpoints, write_checkpoint(
                checkpoint_directory, solver, history, control_sha, bridge_sha,
            ))
        end
        native_converged(history, control) && break
    end
    return (; control_record, bridge, solver, history, checkpoints, model_equivalence_error,
        converged=native_converged(history, control))
end

function state_in_bridge_order(tensor, entry)
    data = convert(Array, tensor)
    left = space(tensor, 1)
    physical = space(tensor, 2)
    right = domain(tensor)[1]
    pleft = basis_permutation(entry.left_charges, tensor_basis_charges(left))
    pphysical = basis_permutation(entry.physical_charges, tensor_basis_charges(physical))
    pright = basis_permutation(entry.right_charges, tensor_basis_charges(right))
    return data[invperm(pleft), invperm(pphysical), invperm(pright)]
end

function write_result(path::AbstractString, run)
    ispath(path) && error("refusing to overwrite immutable result: $path")
    temporary = path * ".tmp"
    mkpath(dirname(path))
    h5open(temporary, "w") do file
        file["schema_version"] = 2
        file["artifact_kind"] = "project_b_mpskit_idmrg_result_bridge"
        file["created_at_utc"] = string(now(UTC))
        file["mpskit_version"] = string(Base.pkgversion(MPSKit))
        file["control_path"] = run.control_record.path
        file["control_sha256"] = file_sha256(run.control_record.path)
        file["source_bridge_path"] = run.bridge.path
        file["source_bridge_sha256"] = file_sha256(run.bridge.path)
        file["lineage/parent_state_path"] = run.bridge.parent_path
        file["lineage/parent_state_sha256"] = run.bridge.parent_sha256
        file["lineage/parent_theta_over_pi"] = run.bridge.parent_theta
        file["lineage/root_state_sha256"] = run.bridge.root_sha256
        file["lineage/root_theta_over_pi"] = run.bridge.root_theta
        file["lineage/target_theta_over_pi"] = run.bridge.target_theta
        file["lineage/numerical_seed_kind"] = run.bridge.numerical_seed_kind
        file["lineage/numerical_seed_path"] = run.bridge.numerical_seed_path
        file["lineage/numerical_seed_sha256"] = run.bridge.numerical_seed_sha256
        file["lineage/numerical_seed_theta_over_pi"] = run.bridge.numerical_seed_theta
        file["optimizer/algorithm"] = "MPSKit.IDMRG one-site"
        file["optimizer/converged"] = run.converged
        file["optimizer/iterations"] = run.solver.state.iter
        file["optimizer/final_environment_error"] = run.solver.state.ϵ
        file["validation/itensor_mpskit_parent_energy_density_difference"] =
            run.model_equivalence_error
        file["validation/itensor_mpskit_seed_energy_density_difference"] =
            run.model_equivalence_error
        file["validation/model_energy_density_tolerance"] =
            run.bridge.model_energy_tolerance
        file["optimizer/discarded_weight_semantics"] =
            "exactly zero: one-site fixed-space IDMRG performs no SVD truncation"
        for name in propertynames(run.history)
            file["optimizer/history/$(String(name))"] = getproperty(run.history, name)
        end
        for site in 1:run.bridge.period
            file["state/site_$site/AL"] = state_in_bridge_order(
                run.solver.state.mps.AL[site], run.bridge.tensors[site],
            )
            file["state/site_$site/left_charges"] = run.bridge.tensors[site].left_charges
            file["state/site_$site/physical_charges"] = run.bridge.tensors[site].physical_charges
            file["state/site_$site/right_charges"] = run.bridge.tensors[site].right_charges
        end
    end
    mv(temporary, path)
    return (; path=abspath(path), sha256=file_sha256(path))
end

function write_lightweight_archive(path::AbstractString, run, result)
    ispath(path) && error("refusing to overwrite immutable lightweight archive: $path")
    temporary = path * ".tmp"
    mkpath(dirname(path))
    h5open(temporary, "w") do file
        file["schema_version"] = 1
        file["artifact_kind"] = "project_b_mpskit_idmrg_lightweight_archive"
        file["created_at_utc"] = string(now(UTC))
        file["control/path"] = run.control_record.path
        file["control/sha256"] = file_sha256(run.control_record.path)
        file["source_bridge/path"] = run.bridge.path
        file["source_bridge/sha256"] = file_sha256(run.bridge.path)
        file["lineage/accepted_parent_path"] = run.bridge.parent_path
        file["lineage/accepted_parent_sha256"] = run.bridge.parent_sha256
        file["lineage/root_state_sha256"] = run.bridge.root_sha256
        file["lineage/root_theta_over_pi"] = run.bridge.root_theta
        file["lineage/numerical_seed_kind"] = run.bridge.numerical_seed_kind
        file["lineage/numerical_seed_path"] = run.bridge.numerical_seed_path
        file["lineage/numerical_seed_sha256"] = run.bridge.numerical_seed_sha256
        file["result/path"] = result.path
        file["result/sha256"] = result.sha256
        file["result/bytes"] = Int(stat(result.path).size)
        file["optimizer/converged"] = run.converged
        file["optimizer/iterations"] = Int(run.solver.state.iter)
        file["optimizer/final_environment_error"] = Float64(run.solver.state.ϵ)
        for name in propertynames(run.history)
            file["optimizer/history/$(String(name))"] = getproperty(run.history, name)
        end
        file["checkpoints/count"] = length(run.checkpoints)
        if !isempty(run.checkpoints)
            file["checkpoints/path"] = [record.path for record in run.checkpoints]
            file["checkpoints/sha256"] = [record.sha256 for record in run.checkpoints]
            file["checkpoints/iteration"] = [record.iteration for record in run.checkpoints]
            file["checkpoints/bytes"] = [record.bytes for record in run.checkpoints]
        end
        file["payload/full_state_included"] = false
        file["payload/solver_serialization_included"] = false
        file["payload/semantics"] =
            "compact home-side manifest; full checkpoints remain at their recorded paths"
    end
    mv(temporary, path)
    return (;
        path=abspath(path),
        sha256=file_sha256(path),
        bytes=Int(stat(path).size),
    )
end

"""
Load a completed MPSKit result as a benchmark-only numerical seed while keeping
the accepted theta/pi=0.15 parent and the original Hamiltonian bridge intact.
No lineage promotion is implied by this conversion.
"""
function load_result_seed(
    path::AbstractString,
    expected_sha256::AbstractString,
    source_bridge,
)
    absolute = abspath(path)
    isfile(absolute) || error("missing benchmark seed result: $absolute")
    actual_sha256 = file_sha256(absolute)
    actual_sha256 == lowercase(expected_sha256) ||
        error("benchmark seed result SHA-256 mismatch")
    return h5open(absolute, "r") do file
        read_string(file, "artifact_kind") == "project_b_mpskit_idmrg_result_bridge" ||
            error("benchmark seed is not a Project B MPSKit result")
        Int(read(file, "schema_version")) == 2 ||
            error("benchmark seed requires result schema 2")
        read_string(file, "mpskit_version") == string(REQUIRED_MPSKIT_VERSION) ||
            error("benchmark seed MPSKit version mismatch")
        read_string(file, "source_bridge_sha256") == file_sha256(source_bridge.path) ||
            error("benchmark seed source-bridge hash mismatch")
        read_string(file, "lineage/parent_state_sha256") == source_bridge.parent_sha256 ||
            error("benchmark seed changed the accepted parent")
        isapprox(
            Float64(read(file, "lineage/target_theta_over_pi")),
            source_bridge.target_theta;
            atol=1e-12,
            rtol=0,
        ) || error("benchmark seed target theta mismatch")
        Bool(read(file, "optimizer/converged")) &&
            error("benchmark seed must remain explicitly nonconverged")
        tensors = map(1:source_bridge.period) do site
            prefix = "state/site_$site"
            entry = (;
                data=ComplexF64.(read(file, "$prefix/AL")),
                left_charges=Int.(read(file, "$prefix/left_charges")),
                physical_charges=Int.(read(file, "$prefix/physical_charges")),
                right_charges=Int.(read(file, "$prefix/right_charges")),
            )
            reference = source_bridge.tensors[site]
            entry.left_charges == reference.left_charges ||
                error("benchmark seed changed left U(1) charges at site $site")
            entry.physical_charges == reference.physical_charges ||
                error("benchmark seed changed physical U(1) charges at site $site")
            entry.right_charges == reference.right_charges ||
                error("benchmark seed changed right U(1) charges at site $site")
            size(entry.data) == size(reference.data) ||
                error("benchmark seed changed tensor dimensions at site $site")
            entry
        end
        iterations = Int(read(file, "optimizer/iterations"))
        fixed_point_change = Float64.(read(file, "optimizer/history/environment_error"))
        energy_density = Float64.(read(file, "optimizer/history/energy_density"))
        discarded_weight = Float64.(read(file, "optimizer/history/discarded_weight"))
        maximum_bond_dimension = Int.(read(
            file,
            "optimizer/history/maximum_bond_dimension",
        ))
        all(length(values) == iterations for values in (
            fixed_point_change,
            energy_density,
            discarded_weight,
            maximum_bond_dimension,
        )) || error("benchmark seed has inconsistent native histories")
        all(==(0.0), discarded_weight) ||
            error("benchmark seed changed one-site discarded-weight semantics")
        all(==(512), maximum_bond_dimension) ||
            error("benchmark seed did not maintain chi 512")
        seed = merge(source_bridge, (;
            tensors,
            numerical_seed_kind="rejected_nonconverged_idmrg_result",
            numerical_seed_path=absolute,
            numerical_seed_sha256=actual_sha256,
            numerical_seed_theta=source_bridge.target_theta,
        ))
        return (;
            seed,
            path=absolute,
            sha256=actual_sha256,
            control_sha256=read_string(file, "control_sha256"),
            iterations,
            final_fixed_point_change=Float64(read(
                file,
                "optimizer/final_environment_error",
            )),
            final_energy_density=last(energy_density),
        )
    end
end

function run_benchmark(
    science_control_path::AbstractString,
    result_seed_path::AbstractString,
    result_seed_sha256::AbstractString;
    total_iterations::Integer,
    warmup_iterations::Integer,
    expected_threads::Integer,
    slurm_cpus_per_thread::Integer=2,
)
    require_exact_environment()
    Threads.nthreads() == expected_threads || error(
        "benchmark expected $expected_threads Julia threads, got $(Threads.nthreads())",
    )
    total_iterations > warmup_iterations >= 1 ||
        error("benchmark requires at least one warm-up and one measured iteration")
    slurm_cpus_per_thread == 2 ||
        error("Perlmutter benchmark requires two Slurm logical CPUs per Julia thread")
    control_record = load_control(science_control_path)
    bridge = load_bridge(control_record.bridge_path)
    result_seed = load_result_seed(result_seed_path, result_seed_sha256, bridge)
    result_seed.control_sha256 == file_sha256(control_record.path) ||
        error("benchmark seed was not produced by the pinned science control")
    algorithm = IDMRG(
        tol=Float64(control_record.raw["native_convergence"]["environment_tolerance"]),
        maxiter=Int(total_iterations),
        verbosity=0,
    )
    initialization = measure_wall_and_cpu() do
        state = build_state(result_seed.seed)
        hamiltonian = build_hamiltonian(result_seed.seed)
        initial_solver(state, hamiltonian, algorithm)
    end
    solver = initialization.value
    initialization_elapsed_seconds = initialization.elapsed_seconds
    initialization_cpu_seconds = initialization.cpu_seconds
    initial_fixed_point_change = solver.state.ϵ
    initial_cumulative_energy_per_site = Float64(
        real(solver.state.energy) / length(solver.state.mps),
    )
    GC.gc()
    history = history_buffers()
    iteration_cpu_seconds = Float64[]
    for _ in 1:Int(total_iterations)
        measurement = measure_wall_and_cpu(() -> iterate(solver))
        value = measurement.value
        elapsed = measurement.elapsed_seconds
        push!(iteration_cpu_seconds, measurement.cpu_seconds)
        value === nothing && error("iDMRG iterator ended before benchmark completion")
        (_, _, epsilon, delta), _ = value
        append_history!(
            history,
            solver.state.iter,
            epsilon,
            solver.state.energy,
            delta,
            solver.state.mps,
            elapsed,
        )
    end
    return (;
        control_record,
        bridge,
        result_seed,
        solver,
        history,
        iteration_cpu_seconds,
        initialization_elapsed_seconds,
        initialization_cpu_seconds,
        initial_fixed_point_change,
        initial_cumulative_energy_per_site,
        total_iterations=Int(total_iterations),
        warmup_iterations=Int(warmup_iterations),
        measured_iterations=Int(total_iterations - warmup_iterations),
        threads=Int(expected_threads),
        slurm_cpus_per_thread=Int(slurm_cpus_per_thread),
    )
end

function write_benchmark_result(path::AbstractString, run, benchmark_control_path)
    ispath(path) && error("refusing to overwrite immutable benchmark result: $path")
    temporary = path * ".tmp"
    ispath(temporary) && error("refusing to overwrite stale benchmark temporary file: $temporary")
    run.warmup_iterations + run.measured_iterations == run.total_iterations ||
        error("benchmark warm-up and measured counts do not match total iterations")
    history_fields = (
        run.history.iteration,
        run.history.environment_error,
        run.history.energy_density,
        run.history.cumulative_superblock_energy_per_site,
        run.history.discarded_weight,
        run.history.maximum_bond_dimension,
        run.history.elapsed_seconds,
        run.iteration_cpu_seconds,
    )
    all(length(values) == run.total_iterations for values in history_fields) ||
        error("benchmark result histories do not match total iterations")
    mkpath(dirname(path))
    try
        h5open(temporary, "w") do file
            file["schema_version"] = 2
            file["artifact_kind"] = "project_b_mpskit_idmrg_thread_benchmark"
            file["created_at_utc"] = string(now(UTC))
            file["julia_version"] = string(VERSION)
            file["mpskit_version"] = string(Base.pkgversion(MPSKit))
            file["hdf5_version"] = string(Base.pkgversion(HDF5))
            file["tensorkit_version"] = string(Base.pkgversion(TensorKit))
            file["source/benchmark_control_path"] = abspath(benchmark_control_path)
            file["source/benchmark_control_sha256"] = file_sha256(benchmark_control_path)
            file["source/science_control_path"] = run.control_record.path
            file["source/science_control_sha256"] = file_sha256(run.control_record.path)
            file["source/import_bridge_path"] = run.bridge.path
            file["source/import_bridge_sha256"] = file_sha256(run.bridge.path)
            file["source/result_seed_path"] = run.result_seed.path
            file["source/result_seed_sha256"] = run.result_seed.sha256
            file["lineage/accepted_parent_sha256"] = run.bridge.parent_sha256
            file["lineage/numerical_seed_kind"] =
                "rejected_nonconverged_idmrg_result_benchmark_only"
            file["lineage/numerical_seed_is_parent"] = false
            file["benchmark/julia_threads"] = run.threads
            file["benchmark/slurm_cpus_per_thread"] = run.slurm_cpus_per_thread
            file["benchmark/slurm_logical_cpus"] =
                run.threads * run.slurm_cpus_per_thread
            file["benchmark/total_iterations"] = run.total_iterations
            file["benchmark/warmup_iterations"] = run.warmup_iterations
            file["benchmark/measured_iterations"] = run.measured_iterations
            file["benchmark/measured_mask"] = UInt8[
                index > run.warmup_iterations for index in 1:run.total_iterations
            ]
            file["benchmark/measured_mask_encoding"] = "UInt8: 0=warm-up, 1=measured"
            file["benchmark/full_state_payload_included"] = false
            file["runtime/julia_threads"] = hasproperty(run, :runtime_julia_threads) ?
                Int(run.runtime_julia_threads) : Threads.nthreads()
            file["runtime/system_cpu_threads"] = Sys.CPU_THREADS
            file["runtime/hostname"] = gethostname()
            file["runtime/kernel"] = hasproperty(run, :runtime_kernel) ?
                String(run.runtime_kernel) : string(Sys.KERNEL)
            file["runtime/architecture"] = hasproperty(run, :runtime_architecture) ?
                String(run.runtime_architecture) : string(Sys.ARCH)
            file["runtime/slurm_job_id"] = get(ENV, "SLURM_JOB_ID", "none")
            file["runtime/slurm_step_id"] = get(ENV, "SLURM_STEP_ID", "none")
            file["runtime/initialization_elapsed_seconds"] =
                run.initialization_elapsed_seconds
            file["runtime/initialization_cpu_seconds"] = run.initialization_cpu_seconds
            file["runtime/process_cpu_time_source"] =
                "libuv uv_getrusage user plus system process CPU time"
            file["optimizer/initial_fixed_point_change"] = run.initial_fixed_point_change
            file["optimizer/initial_cumulative_superblock_energy_per_site"] =
                run.initial_cumulative_energy_per_site
            file["optimizer/fixed_point_change_semantics"] =
                "MPSKit IDMRG norm(C_new - C_old) after one complete unit-cell sweep"
            file["optimizer/history/iteration"] = run.history.iteration
            file["optimizer/history/bond_matrix_update_norm"] =
                run.history.environment_error
            file["optimizer/history/energy_density"] = run.history.energy_density
            file["optimizer/history/cumulative_superblock_energy_per_site"] =
                run.history.cumulative_superblock_energy_per_site
            file["optimizer/history/discarded_weight"] = run.history.discarded_weight
            file["optimizer/history/maximum_bond_dimension"] =
                run.history.maximum_bond_dimension
            file["optimizer/history/elapsed_seconds"] = run.history.elapsed_seconds
            file["optimizer/history/cpu_seconds"] = run.iteration_cpu_seconds
        end
        mv(temporary, path)
    catch
        ispath(temporary) && rm(temporary; force=true)
        rethrow()
    end
    return (; path=abspath(path), sha256=file_sha256(path), bytes=Int(stat(path).size))
end

function benchmark_result_io_preflight()
    require_exact_environment()
    return mktempdir() do directory
        science_control_path = joinpath(directory, "science_control.toml")
        bridge_path = joinpath(directory, "bridge.h5")
        result_seed_path = joinpath(directory, "result_seed.h5")
        benchmark_control_path = joinpath(directory, "benchmark_control.toml")
        for (path, contents) in (
            science_control_path => "science control",
            bridge_path => "bridge",
            result_seed_path => "result seed",
            benchmark_control_path => "benchmark control",
        )
            write(path, contents)
        end
        history = (;
            iteration=[1, 2],
            environment_error=[2e-6, 1e-6],
            energy_density=[-0.5, -0.5001],
            cumulative_superblock_energy_per_site=[-0.5, -1.0001],
            discarded_weight=zeros(2),
            maximum_bond_dimension=fill(512, 2),
            elapsed_seconds=[1.0, 0.9],
        )
        run = (;
            control_record=(; path=science_control_path),
            bridge=(; path=bridge_path, parent_sha256=repeat("a", 64)),
            result_seed=(; path=result_seed_path, sha256=file_sha256(result_seed_path)),
            history,
            iteration_cpu_seconds=[0.8, 0.7],
            initialization_elapsed_seconds=0.1,
            initialization_cpu_seconds=0.08,
            initial_fixed_point_change=3e-6,
            initial_cumulative_energy_per_site=-0.49,
            total_iterations=2,
            warmup_iterations=1,
            measured_iterations=1,
            threads=2,
            slurm_cpus_per_thread=2,
        )
        result_path = joinpath(directory, "benchmark.h5")
        withenv("SLURM_JOB_ID" => "preflight", "SLURM_STEP_ID" => "preflight") do
            write_benchmark_result(result_path, run, benchmark_control_path)
        end
        return h5open(result_path, "r") do file
            Int(read(file, "schema_version")) == 2 ||
                error("benchmark I/O preflight wrote the wrong schema")
            mask = UInt8.(read(file, "benchmark/measured_mask"))
            mask == UInt8[0, 1] || error("benchmark I/O preflight mask round trip failed")
            length(read(file, "optimizer/history/elapsed_seconds")) == 2 ||
                error("benchmark I/O preflight history round trip failed")
            (; bytes=Int(stat(result_path).size), mask)
        end
    end
end

end
