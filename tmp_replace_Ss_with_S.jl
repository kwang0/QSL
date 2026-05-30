using HDF5

function single_entropy_value(raw_Ss, filename)
    if raw_Ss isa Number
        return Float64(raw_Ss)
    end

    values = vec(Array(raw_Ss))
    length(values) == 1 || error(
        "File $filename has `Ss` with $(length(values)) entries; refusing to convert non-scalar entropy data.",
    )
    return Float64(values[1])
end

function replace_Ss_with_S!(filename)
    isfile(filename) || error("File not found: $filename")

    h5open(filename, "r+") do F
        if !haskey(F, "Ss")
            println("$filename: no `Ss` dataset found; skipping.")
            return
        end

        S = single_entropy_value(read(F, "Ss"), filename)

        if haskey(F, "S")
            println("$filename: `S` already exists; deleting redundant `Ss`.")
        else
            F["S"] = S
            println("$filename: wrote `S = $S`.")
        end

        HDF5.delete_object(F, "Ss")
    end
end

if isempty(ARGS)
    error("Usage: julia tmp_replace_Ss_with_S.jl file1.h5 [file2.h5 ...]")
end

for filename in ARGS
    replace_Ss_with_S!(filename)
end
