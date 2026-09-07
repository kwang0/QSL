module FileIntegrity
using SHA

"""Stream file hashes; use the precompiled system implementation on Linux."""
function file_sha256(path; native=Sys.islinux())
    isfile(path) || error("hash input is missing: $path")
    executable = native ? Sys.which("sha256sum") : nothing
    if !isnothing(executable)
        result = read(`$executable -- $path`, String)
        matched = match(r"^\\?([0-9a-f]{64})[ \t]", result)
        isnothing(matched) && error("invalid sha256sum output for $path")
        return String(matched[1])
    end
    bytes2hex(open(sha256, path))
end
end
