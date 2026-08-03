using HDF5
using ITensors
using ITensorMPS
using LinearAlgebra

const DEFAULT_PSI_DATASET = "psi0"

const APPENDED_DATASETS = (
    "Splus_expectations",
    "Sminus_expectations",
    "Splus_Sminus_corrs",
    "Sminus_Splus_corrs",
    "longitudinal_connected_corrs",
    "Splus_Sminus_connected_corrs",
    "Sminus_Splus_connected_corrs",
    "scalar_corrs",
    "scalar_connected_corrs",
)

function usage()
    return """
    Usage:
      julia --startup-file=no tmp_append_transverse_correlations.jl [options] file1.h5 [file2.h5 ...]

    Options:
      --overwrite           Replace existing appended datasets.
      --dry-run             Report what would be done without writing.
      --psi-dataset=NAME    MPS dataset to read (default: psi0).
      --help                Show this message.

    The input file should be a ground_state_search_cpu.jl output containing
    the saved MPS. The script keeps the existing `corrs = <Sz_i Sz_j>` dataset
    and appends transverse and scalar-correlation datasets.
    """
end

function parse_args(args)
    overwrite = false
    dry_run = false
    psi_dataset = DEFAULT_PSI_DATASET
    files = String[]

    for arg in args
        if arg == "--overwrite"
            overwrite = true
        elseif arg == "--dry-run"
            dry_run = true
        elseif startswith(arg, "--psi-dataset=")
            psi_dataset = split(arg, "=", limit=2)[2]
            isempty(psi_dataset) && error("--psi-dataset cannot be empty")
        elseif arg == "--help" || arg == "-h"
            println(usage())
            exit(0)
        elseif startswith(arg, "--")
            error("Unknown option: $arg\n\n$(usage())")
        else
            push!(files, arg)
        end
    end

    isempty(files) && error("No HDF5 files provided.\n\n$(usage())")
    return (; overwrite, dry_run, psi_dataset, files)
end

function all_appended_datasets_present(file)
    return all(name -> haskey(file, name), APPENDED_DATASETS)
end

function read_or_compute!(file, name, description, compute; dry_run)
    if haskey(file, name)
        println("  loaded existing `$name`")
        return read(file, name)
    end

    println("  computing $description")
    value = compute()
    if dry_run
        println("  dry-run: would write `$name`")
    else
        file[name] = value
        println("  wrote `$name`")
    end
    return value
end

function write_appended_dataset!(file, name, value; overwrite, dry_run)
    if haskey(file, name)
        if overwrite
            if dry_run
                println("  dry-run: would replace `$name`")
                return
            end
            HDF5.delete_object(file, name)
        else
            println("  keeping existing `$name`")
            return
        end
    elseif dry_run
        println("  dry-run: would write `$name`")
        return
    end

    file[name] = value
    println("  wrote `$name`")
    return
end

function maybe_real(values; rtol=1e-12, atol=1e-12)
    values isa AbstractArray || return values
    eltype(values) <: Complex || return values
    scale = max(1.0, maximum(abs.(real.(values))))
    maximum(abs.(imag.(values))) <= atol + rtol * scale && return real.(values)
    return values
end

function outer(a, b)
    return a * transpose(b)
end

function append_transverse_correlations!(filename; overwrite=false, dry_run=false, psi_dataset=DEFAULT_PSI_DATASET)
    isfile(filename) || error("File not found: $filename")

    mode = dry_run ? "r" : "r+"
    h5open(filename, mode) do file
        println(filename)

        if all_appended_datasets_present(file) && !overwrite
            println("  appended datasets already present; use --overwrite to refresh them")
            return
        end

        haskey(file, psi_dataset) || error(
            "File $filename does not contain MPS dataset `$psi_dataset`. " *
            "Use an unstripped ground_state_search_cpu.jl output, or pass --psi-dataset=NAME.",
        )

        if dry_run
            println("  dry-run: `$psi_dataset` is present")
            for name in ("Zs", "corrs")
                if haskey(file, name)
                    println("  dry-run: would use existing `$name`")
                else
                    println("  dry-run: would compute and write `$name`")
                end
            end
            for name in APPENDED_DATASETS
                if haskey(file, name)
                    action = overwrite ? "replace" : "keep"
                    println("  dry-run: would $action existing `$name`")
                else
                    println("  dry-run: would write `$name`")
                end
            end
            if haskey(file, "transverse_correlations_appended_unix_time")
                println("  dry-run: would replace `transverse_correlations_appended_unix_time`")
            else
                println("  dry-run: would write `transverse_correlations_appended_unix_time`")
            end
            return
        end

        println("  reading `$psi_dataset`")
        psi = read(file, psi_dataset, MPS)
        N = length(psi)

        Zs = read_or_compute!(
            file,
            "Zs",
            "Sz one-point expectations",
            () -> Array(expect(psi, "Sz"));
            dry_run,
        )
        length(Zs) == N || error("File $filename has length(Zs) = $(length(Zs)), but length(psi) = $N.")

        sz_sz_corrs = read_or_compute!(
            file,
            "corrs",
            "Sz-Sz correlation matrix",
            () -> correlation_matrix(psi, "Sz", "Sz"; ishermitian=true);
            dry_run,
        )
        size(sz_sz_corrs) == (N, N) || error(
            "File $filename has size(corrs) = $(size(sz_sz_corrs)), but expected ($N, $N).",
        )

        println("  computing transverse one-point expectations")
        Splus = Array(expect(psi, "S+"))
        Sminus = Array(expect(psi, "S-"))

        println("  computing <S+_i S-_j>")
        splus_sminus_corrs = correlation_matrix(psi, "S+", "S-"; ishermitian=true)

        println("  computing <S-_i S+_j>")
        sminus_splus_corrs = correlation_matrix(psi, "S-", "S+"; ishermitian=true)

        longitudinal_connected_corrs = sz_sz_corrs .- outer(Zs, Zs)
        splus_sminus_connected_corrs = splus_sminus_corrs .- outer(Splus, Sminus)
        sminus_splus_connected_corrs = sminus_splus_corrs .- outer(Sminus, Splus)

        scalar_corrs = sz_sz_corrs .+ 0.5 .* (splus_sminus_corrs .+ sminus_splus_corrs)
        scalar_connected_corrs =
            longitudinal_connected_corrs .+
            0.5 .* (splus_sminus_connected_corrs .+ sminus_splus_connected_corrs)

        write_appended_dataset!(file, "Splus_expectations", Splus; overwrite, dry_run)
        write_appended_dataset!(file, "Sminus_expectations", Sminus; overwrite, dry_run)
        write_appended_dataset!(file, "Splus_Sminus_corrs", splus_sminus_corrs; overwrite, dry_run)
        write_appended_dataset!(file, "Sminus_Splus_corrs", sminus_splus_corrs; overwrite, dry_run)
        write_appended_dataset!(
            file,
            "longitudinal_connected_corrs",
            maybe_real(longitudinal_connected_corrs);
            overwrite,
            dry_run,
        )
        write_appended_dataset!(
            file,
            "Splus_Sminus_connected_corrs",
            splus_sminus_connected_corrs;
            overwrite,
            dry_run,
        )
        write_appended_dataset!(
            file,
            "Sminus_Splus_connected_corrs",
            sminus_splus_connected_corrs;
            overwrite,
            dry_run,
        )
        write_appended_dataset!(file, "scalar_corrs", maybe_real(scalar_corrs); overwrite, dry_run)
        write_appended_dataset!(
            file,
            "scalar_connected_corrs",
            maybe_real(scalar_connected_corrs);
            overwrite,
            dry_run,
        )

        write_appended_dataset!(
            file,
            "transverse_correlations_appended_unix_time",
            time();
            overwrite=true,
            dry_run,
        )
    end
end

function main()
    options = parse_args(ARGS)
    failures = 0

    for filename in options.files
        try
            append_transverse_correlations!(
                filename;
                overwrite=options.overwrite,
                dry_run=options.dry_run,
                psi_dataset=options.psi_dataset,
            )
        catch err
            failures += 1
            println(stderr, "$filename: ERROR: $(sprint(showerror, err))")
        end
    end

    if failures > 0
        println(stderr, "Finished with $failures failure(s).")
        exit(1)
    end
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    main()
end
