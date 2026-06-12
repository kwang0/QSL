using HDF5
using Glob

# Copy VUMPS flux-threaded run data excluding large MPS/state groups.
# By default this keeps one packaged full sweep per run, not every cumulative
# theta checkpoint file. Use --all-theta-files to copy every matched file.

const DEFAULT_INPUT_DIR = "/pscratch/sd/k/kwang98/QSL"
const DEFAULT_OUTPUT_DIR = "processed_data"
const DEFAULT_PATTERN = "ground_state_search_flux_threaded_vumps_YC*.h5"
const DEFAULT_SKIP_NAMES = Set([
    "psi",
    "psi0",
    "psi1",
    "psi_neutral",
    "psi_spin",
    "psi_elec",
    "mps",
    "state",
    "sites",
])

function default_input_dir()
    return isdir(DEFAULT_INPUT_DIR) ? DEFAULT_INPUT_DIR : "."
end

function usage()
    return """
    Usage:
      julia copy_vumps_data.jl [input_dir] [output_dir] [pattern] [--skip-existing] [--all-theta-files]

    Defaults:
      input_dir  = $(default_input_dir())
      output_dir = $(DEFAULT_OUTPUT_DIR)
      pattern    = $(DEFAULT_PATTERN)

    Examples:
      julia copy_vumps_data.jl
      julia copy_vumps_data.jl /pscratch/sd/k/kwang98/QSL processed_data
      julia copy_vumps_data.jl /pscratch/sd/k/kwang98/QSL processed_data 'ground_state_search_flux_threaded_vumps_YC6-*.h5'
    """
end

function parse_args(args)
    skip_existing = "--skip-existing" in args
    all_theta_files = "--all-theta-files" in args
    positional = filter(arg -> !(arg in ("--skip-existing", "--all-theta-files")), args)
    any(arg -> startswith(arg, "-"), positional) && error(usage())
    length(positional) <= 3 || error(usage())

    input_dir = length(positional) >= 1 ? positional[1] : default_input_dir()
    output_dir = length(positional) >= 2 ? positional[2] : DEFAULT_OUTPUT_DIR
    pattern = length(positional) >= 3 ? positional[3] : DEFAULT_PATTERN
    return (; input_dir, output_dir, pattern, skip_existing, all_theta_files)
end

function should_skip(name::AbstractString, skip_names::Set{String})
    return name in skip_names || startswith(lowercase(name), "psi_")
end

function copy_h5_group!(dst, src; skip_names::Set{String}=DEFAULT_SKIP_NAMES, skipped=String[])
    for name in keys(src)
        if should_skip(name, skip_names)
            push!(skipped, name)
            continue
        end

        node = src[name]
        if node isa HDF5.Dataset
            dst[name] = read(node)
        elseif node isa HDF5.Group
            child = create_group(dst, name)
            copy_h5_group!(child, node; skip_names, skipped)
        else
            @warn "Skipping unsupported HDF5 object" name typeof_node=typeof(node)
            push!(skipped, name)
        end
    end
    return skipped
end

function copy_non_mps_data(input::AbstractString, output::AbstractString; skip_names::Set{String}=DEFAULT_SKIP_NAMES)
    abspath(input) == abspath(output) && error("Refusing to copy $(input) onto itself")

    skipped = String[]
    h5open(input, "r") do src
        h5open(output, "w") do dst
            copy_h5_group!(dst, src; skip_names, skipped)
        end
    end
    return skipped
end

struct VumpsFileInfo
    path::String
    group_key::String
    fluxes::Vector{Float64}
    theta_pi::Float64
end

function key_value(file, name::AbstractString)
    if !haskey(file, name)
        return "$(name)=missing"
    end

    value = read(file, name)
    if value isa AbstractArray
        return "$(name)=array$(size(value))"
    elseif value isa AbstractFloat
        return "$(name)=$(repr(Float64(value)))"
    else
        return "$(name)=$(value)"
    end
end

function run_group_key(file)
    names = (
        "C",
        "J1",
        "J2",
        "yc_shift",
        "B",
        "Bperp",
        "Delta1",
        "Delta2",
        "maxdim",
        "cutoff",
        "vumps_tol",
        "max_vumps_iters",
        "outer_iters_initial",
        "conserve_qns",
    )
    return join((key_value(file, name) for name in names), "|")
end

function read_fluxes(file)
    if haskey(file, "fluxes")
        return Float64.(vec(real.(read(file, "fluxes"))))
    elseif haskey(file, "fluxes_over_pi")
        return pi .* Float64.(vec(real.(read(file, "fluxes_over_pi"))))
    else
        return Float64[]
    end
end

function read_theta_pi(file, fluxes::AbstractVector{<:Real})
    if haskey(file, "theta_pi")
        return Float64(real(read(file, "theta_pi")))
    elseif !isempty(fluxes)
        return Float64(last(fluxes) / pi)
    else
        return NaN
    end
end

function read_vumps_file_info(path::AbstractString)
    h5open(path, "r") do file
        fluxes = read_fluxes(file)
        theta_pi = read_theta_pi(file, fluxes)
        return VumpsFileInfo(path, run_group_key(file), fluxes, theta_pi)
    end
end

function is_flux_prefix(a::AbstractVector{<:Real}, b::AbstractVector{<:Real})
    length(a) < length(b) || return false
    isempty(a) && return false
    for i in eachindex(a)
        isapprox(a[i], b[i]; atol=1e-10, rtol=1e-10) || return false
    end
    return true
end

function select_full_sweeps(infos::AbstractVector{VumpsFileInfo})
    selected = VumpsFileInfo[]
    for group in values(groupby_run(infos))
        for info in group
            is_partial = any(other -> is_flux_prefix(info.fluxes, other.fluxes), group)
            !is_partial && push!(selected, info)
        end
    end
    return sort(selected; by=info -> info.path)
end

function groupby_run(infos::AbstractVector{VumpsFileInfo})
    groups = Dict{String,Vector{VumpsFileInfo}}()
    for info in infos
        push!(get!(groups, info.group_key, VumpsFileInfo[]), info)
    end
    return groups
end

function main(args=ARGS)
    opts = parse_args(args)
    isdir(opts.input_dir) || error("Input directory does not exist: $(opts.input_dir)")
    mkpath(opts.output_dir)

    inputs = sort(glob(opts.pattern, opts.input_dir))
    if isempty(inputs)
        println("No files matched $(joinpath(opts.input_dir, opts.pattern))")
        return nothing
    end

    infos = read_vumps_file_info.(inputs)
    selected_infos = opts.all_theta_files ? infos : select_full_sweeps(infos)
    selected_inputs = [info.path for info in selected_infos]

    println("Found $(length(inputs)) VUMPS HDF5 file(s)")
    if opts.all_theta_files
        println("Copying every theta checkpoint file")
    else
        println("Copying $(length(selected_inputs)) packaged full-sweep file(s)")
    end
    println("input_dir: $(opts.input_dir)")
    println("output_dir: $(opts.output_dir)")
    println("pattern: $(opts.pattern)")

    copied = 0
    skipped_existing = 0
    for input in selected_inputs
        output = joinpath(opts.output_dir, basename(input))
        if opts.skip_existing && isfile(output)
            println("Skipping existing $(output)")
            skipped_existing += 1
            continue
        end

        skipped = copy_non_mps_data(input, output)
        copied += 1
        if isempty(skipped)
            println("Copied $(basename(input))")
        else
            println("Copied $(basename(input)); skipped $(join(unique(skipped), ", "))")
        end
    end

    println("Done. Copied $(copied), skipped existing $(skipped_existing).")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
