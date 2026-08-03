using HDF5
using Glob
using Printf

# Post-process saved VUMPS checkpoints with additional transfer-matrix spectra
# in a fixed QN sector. For S=1/2 sites, ITensors stores doubled Sz, so
# physical Sz=1 corresponds to QN("Sz", 2).

const DEFAULT_PATTERN = "ground_state_search_flux_threaded_vumps*.h5"
const TRANSFER_STACK_LOADED = Ref(false)

struct Options
    paths::Vector{String}
    pattern::String
    physical_sz::Float64
    qn_sz::Int
    neigs::Union{Nothing,Int}
    tol::Float64
    prefix::String
    overwrite::Bool
    dry_run::Bool
end

function ensure_transfer_stack_loaded()
    TRANSFER_STACK_LOADED[] && return nothing
    try
        @eval using MKL
        @eval using ITensors
        @eval using ITensorMPS
        @eval using ITensorInfiniteMPS
        @eval using KrylovKit: Arnoldi, eigsolve
    catch err
        error(
            """
            Could not load the ITensor VUMPS transfer-matrix stack.

            This post-processor must run in the same Julia environment that can
            run ground_state_search_flux_threaded_vumps.jl, since it needs
            ITensorInfiniteMPS to read the saved `psi` state.

            Original error:
            $(sprint(showerror, err))
            """,
        )
    end
    TRANSFER_STACK_LOADED[] = true
    return nothing
end

function usage()
    return """
    Usage:
      julia add_vumps_transfer_sector_spectrum.jl path... [options]

    Options:
      --pattern=glob       Pattern used when a path is a directory
                           [$(DEFAULT_PATTERN)]
      --sz=value           Physical Sz sector. For S=1/2 this is doubled in QN
                           labels, so --sz=1 means QN("Sz",2). [1]
      --qn-sz=value        Raw ITensors QN("Sz", value), overriding --sz
      --neigs=value        Number of sector eigenvalues. Defaults to existing
                           transfer_inverse_xi row count, or 16
      --tol=value          Arnoldi tolerance [1e-10]
      --prefix=name        Output dataset prefix [transfer_sz<value>]
      --overwrite          Recreate existing output datasets if their shape
                           does not match this run
      --dry-run            Report what would be done without writing

    The script updates files in-place. It requires each input HDF5 file to
    contain a saved `psi` state. Standard copied files from copy_vumps_data.jl
    intentionally omit `psi` and will be skipped.
    """
end

function sanitize_sector_label(physical_sz::Real)
    s = @sprintf("%.8g", physical_sz)
    s = replace(s, "-" => "m", "." => "p", "+" => "")
    return s
end

function default_prefix(physical_sz::Real)
    return "transfer_sz" * sanitize_sector_label(physical_sz)
end

function parse_bool_flag(arg::AbstractString, name::AbstractString)
    arg == "--$(name)" && return true
    return false
end

function parse_args(args)
    paths = String[]
    pattern = DEFAULT_PATTERN
    physical_sz = 1.0
    qn_sz_override = nothing
    neigs = nothing
    tol = 1e-10
    prefix = nothing
    overwrite = false
    dry_run = false

    for arg in args
        if arg == "-h" || arg == "--help"
            println(usage())
            exit(0)
        elseif startswith(arg, "--pattern=")
            pattern = split(arg, "="; limit=2)[2]
        elseif startswith(arg, "--sz=")
            physical_sz = parse(Float64, split(arg, "="; limit=2)[2])
        elseif startswith(arg, "--qn-sz=")
            qn_sz_override = parse(Int, split(arg, "="; limit=2)[2])
        elseif startswith(arg, "--neigs=")
            neigs = parse(Int, split(arg, "="; limit=2)[2])
        elseif startswith(arg, "--tol=")
            tol = parse(Float64, split(arg, "="; limit=2)[2])
        elseif startswith(arg, "--prefix=")
            prefix = split(arg, "="; limit=2)[2]
        elseif parse_bool_flag(arg, "overwrite")
            overwrite = true
        elseif parse_bool_flag(arg, "dry-run")
            dry_run = true
        elseif startswith(arg, "-")
            error("Unknown option $(arg)\n\n$(usage())")
        else
            push!(paths, arg)
        end
    end

    isempty(paths) && error(usage())
    tol > 0 || error("--tol must be positive")
    neigs !== nothing && neigs >= 1 || neigs === nothing || error("--neigs must be >= 1")

    qn_sz = if qn_sz_override === nothing
        doubled = 2 * physical_sz
        isapprox(doubled, round(doubled); atol=1e-12, rtol=0) ||
            error("--sz=$(physical_sz) does not map to an integer doubled QN value")
        Int(round(doubled))
    else
        qn_sz_override
    end
    out_prefix = prefix === nothing ? default_prefix(physical_sz) : prefix

    return Options(paths, pattern, physical_sz, qn_sz, neigs, tol, out_prefix, overwrite, dry_run)
end

function collect_input_files(paths::AbstractVector{<:AbstractString}, pattern::AbstractString)
    files = String[]
    for path in paths
        if isdir(path)
            append!(files, sort(glob(pattern, path)))
        elseif isfile(path)
            push!(files, path)
        else
            @warn "Skipping missing path" path
        end
    end
    return unique(files)
end

function finite_nonzero(z)
    return isfinite(real(z)) && isfinite(imag(z)) && abs(z) > 0
end

function transfer_data_shape(file)
    if haskey(file, "transfer_inverse_xi")
        values = read(file, "transfer_inverse_xi")
        ndims(values) == 2 || error("transfer_inverse_xi is not a matrix")
        return size(values)
    elseif haskey(file, "fluxes_over_pi")
        return (16, length(vec(read(file, "fluxes_over_pi"))))
    elseif haskey(file, "fluxes")
        return (16, length(vec(read(file, "fluxes"))))
    else
        return (16, 1)
    end
end

function current_flux_column(file, ncols::Integer)
    column = haskey(file, "completed_flux_step") ? Int(read(file, "completed_flux_step")) : ncols
    1 <= column <= ncols || error("Current flux column $(column) is outside 1:$(ncols)")
    return column
end

function stored_reference_lambda(file, column::Integer)
    haskey(file, "transfer_lambdas") || return nothing
    lambdas = read(file, "transfer_lambdas")
    ndims(lambdas) == 2 || return nothing
    size(lambdas, 2) >= column || return nothing
    lambda0 = lambdas[1, column]
    finite_nonzero(lambda0) || return nothing
    return lambda0
end

function dominant_neutral_lambda(psi; tol=1e-10)
    T = TransferMatrix(psi.AL)
    v0 = random_itensor(QN("Sz", 0), dag(input_inds(T)))
    alg = Arnoldi(; krylovdim=8, tol)
    lambdas, _, _ = eigsolve(T, v0, 1, :LM, alg)
    return lambdas[1]
end

function sector_transfer_matrix_spectrum(
    psi,
    sector_qn,
    reference_lambda;
    neigs::Integer=16,
    tol::Real=1e-10,
    krylovdim=max(neigs + 8, 2 * neigs),
)
    T = TransferMatrix(psi.AL)
    v0 = random_itensor(sector_qn, dag(input_inds(T)))
    alg = Arnoldi(; krylovdim=max(krylovdim, neigs + 2), tol)
    lambdas, vecs, _ = eigsolve(T, v0, neigs, :LM, alg)
    normalized = lambdas ./ reference_lambda
    inverse_xi = map(eachindex(normalized)) do n
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

function read_or_init(file, key::AbstractString, dims::Tuple{Int,Int}, fill_value; overwrite::Bool=false)
    if haskey(file, key)
        values = read(file, key)
        if size(values) == dims
            return values
        end
        overwrite ||
            error("Existing dataset $(key) has shape $(size(values)), expected $(dims). Use --overwrite to recreate it.")
    end
    return fill(fill_value, dims)
end

function write_dataset!(file, key::AbstractString, values)
    haskey(file, key) && delete_object(file, key)
    file[key] = values
    return key
end

function write_scalar_dataset!(file, key::AbstractString, value)
    haskey(file, key) && delete_object(file, key)
    file[key] = value
    return key
end

function fill_column!(dest, values, column::Integer, fill_value)
    dest[:, column] .= fill_value
    n = min(size(dest, 1), length(values))
    dest[1:n, column] .= values[1:n]
    return dest
end

function update_file!(path::AbstractString, opts::Options)
    h5open(path, opts.dry_run ? "r" : "r+") do file
        if !haskey(file, "psi")
            println("SKIP $(path): no saved psi state")
            return :skipped
        end

        nlevels_existing, ncols = transfer_data_shape(file)
        neigs = opts.neigs === nothing ? nlevels_existing : opts.neigs
        column = current_flux_column(file, ncols)
        theta_text = if haskey(file, "fluxes_over_pi")
            theta = vec(real.(read(file, "fluxes_over_pi")))
            column <= length(theta) ? @sprintf("theta/pi=%.12g", theta[column]) : "theta/pi=?"
        else
            "theta/pi=?"
        end

        println(
            "Processing $(path): column $(column)/$(ncols), $(theta_text), sector QN(\"Sz\",$(opts.qn_sz)), neigs=$(neigs)",
        )
        opts.dry_run && return :dry_run

        ensure_transfer_stack_loaded()
        sector_qn = QN("Sz", opts.qn_sz)
        psi = read(file, "psi", InfiniteCanonicalMPS)
        reference_lambda = stored_reference_lambda(file, column)
        if reference_lambda === nothing
            @warn "Missing neutral reference lambda; computing QN(\"Sz\",0) dominant eigenvalue" path column
            reference_lambda = dominant_neutral_lambda(psi; tol=opts.tol)
        end
        finite_nonzero(reference_lambda) || error("Invalid neutral reference lambda $(reference_lambda)")

        spectrum = sector_transfer_matrix_spectrum(
            psi,
            sector_qn,
            reference_lambda;
            neigs,
            tol=opts.tol,
        )

        dims = (neigs, ncols)
        lambdas = read_or_init(file, "$(opts.prefix)_lambdas", dims, complex(NaN, NaN); overwrite=opts.overwrite)
        normalized = read_or_init(
            file,
            "$(opts.prefix)_normalized_lambdas",
            dims,
            complex(NaN, NaN);
            overwrite=opts.overwrite,
        )
        inverse_xi = read_or_init(file, "$(opts.prefix)_inverse_xi", dims, NaN; overwrite=opts.overwrite)
        xi = read_or_init(file, "$(opts.prefix)_xi", dims, NaN; overwrite=opts.overwrite)
        momenta = read_or_init(file, "$(opts.prefix)_momenta", dims, NaN; overwrite=opts.overwrite)
        labels = read_or_init(file, "$(opts.prefix)_flux_labels", dims, ""; overwrite=opts.overwrite)

        fill_column!(lambdas, spectrum.lambdas, column, complex(NaN, NaN))
        fill_column!(normalized, spectrum.normalized, column, complex(NaN, NaN))
        fill_column!(inverse_xi, spectrum.inverse_xi, column, NaN)
        fill_column!(xi, spectrum.xi, column, NaN)
        fill_column!(momenta, spectrum.momenta, column, NaN)
        fill_column!(labels, spectrum.flux_labels, column, "")

        write_dataset!(file, "$(opts.prefix)_lambdas", lambdas)
        write_dataset!(file, "$(opts.prefix)_normalized_lambdas", normalized)
        write_dataset!(file, "$(opts.prefix)_inverse_xi", inverse_xi)
        write_dataset!(file, "$(opts.prefix)_xi", xi)
        write_dataset!(file, "$(opts.prefix)_momenta", momenta)
        write_dataset!(file, "$(opts.prefix)_flux_labels", labels)
        write_scalar_dataset!(file, "$(opts.prefix)_physical_sz", opts.physical_sz)
        write_scalar_dataset!(file, "$(opts.prefix)_qn_sz", opts.qn_sz)
        write_scalar_dataset!(file, "$(opts.prefix)_last_updated_column", column)
        write_scalar_dataset!(file, "$(opts.prefix)_reference_lambda", reference_lambda)

        if !isempty(spectrum.inverse_xi)
            @printf(
                "  leading %s inverse xi = %.12g, momentum = %.12g, label = %s\n",
                string(sector_qn),
                spectrum.inverse_xi[1],
                spectrum.momenta[1],
                spectrum.flux_labels[1],
            )
        end
        return :updated
    end
end

function main(args=ARGS)
    opts = parse_args(args)
    files = collect_input_files(opts.paths, opts.pattern)
    isempty(files) && error("No input files found")

    println("Adding VUMPS transfer sector spectrum")
    println("sector: physical Sz=$(opts.physical_sz), raw QN(\"Sz\",$(opts.qn_sz))")
    println("dataset prefix: $(opts.prefix)")
    println("files: $(length(files))")
    opts.dry_run && println("dry run: no files will be modified")

    counts = Dict(:updated => 0, :skipped => 0, :dry_run => 0, :failed => 0)
    for path in files
        try
            result = update_file!(path, opts)
            counts[result] = get(counts, result, 0) + 1
        catch err
            counts[:failed] = get(counts, :failed, 0) + 1
            @error "Failed to update $(path)" exception=(err, catch_backtrace())
        end
    end

    println(
        "Summary: updated=$(counts[:updated]), skipped=$(counts[:skipped]), dry_run=$(counts[:dry_run]), failed=$(counts[:failed])",
    )
    counts[:failed] == 0 || error("One or more files failed")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
