#!/usr/bin/env julia

include(joinpath(@__DIR__,"lib/FileIntegrity.jl"))

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const REQUIRED_CONTEXT = [
    "AGENTS.md",
    "docs/PROJECT_STATE.md",
    "docs/ARCHITECTURE.md",
    "docs/plans/README.md",
    "docs/decisions/README.md",
    "docs/NEW_TASK_PROMPT.md",
]

function run_capture(argv::AbstractVector{<:AbstractString})
    isnothing(Sys.which(first(argv))) && return false, "executable unavailable: $(first(argv))"
    buffer = IOBuffer()
    process = run(pipeline(ignorestatus(Cmd(String.(argv))); stdout=buffer, stderr=buffer))
    return success(process), chomp(String(take!(buffer)))
end

function project_path(relative::AbstractString)
    normalized = replace(strip(relative), '\\' => '/')
    return normpath(joinpath(PROJECT_ROOT, split(normalized, '/')...))
end

function relative_display(path::AbstractString)
    return replace(relpath(path, PROJECT_ROOT), '\\' => '/')
end

function file_sha256(path::AbstractString)
    return FileIntegrity.file_sha256(path)
end

function print_block(label::AbstractString, value::AbstractString)
    println(label, ":")
    if isempty(value)
        println("  <empty>")
    else
        for line in split(value, '\n')
            println("  ", line)
        end
    end
end

println("Project B context audit (read-only)")
println("project_root: ", PROJECT_ROOT)
println("host_os: ", Sys.iswindows() ? "Windows" : "$(Sys.KERNEL)")
println("expected_interactive_shell: ", Sys.iswindows() ? "PowerShell" : "POSIX shell (Perlmutter launchers use Bash)")

errors = String[]
warnings = String[]
source_export = length(ARGS)==2 && ARGS[1]=="--source-export"
isempty(ARGS) || source_export || error("usage: audit_project_context.jl [--source-export CONTROL]")

root_ok, git_root = run_capture(["git", "-C", PROJECT_ROOT, "rev-parse", "--show-toplevel"])
if !root_ok
    if source_export
        push!(warnings, "Git history unavailable in source export; sealed source hashes are checked below")
    else
        push!(errors, "Git root lookup failed: $git_root")
    end
    git_root = "<unavailable>"
end

if source_export
    println("source_export_control: ", abspath(ARGS[2])); flush(stdout)
    try
        include(joinpath(@__DIR__,"lib/SolverPilotControl.jl"))
        control=SolverPilotControl.validate(abspath(ARGS[2]);code_only=true)
        required=["scripts/audit_project_context.jl","scripts/lib/SolverPilotControl.jl",
            "scripts/lib/FileIntegrity.jl","Project.toml","Manifest.toml",
            "idmrg/Project.toml","idmrg/Manifest.toml"]
        all(p->any(r->r["path"]==p,control["inputs"]),required) ||
            error("source-export control lacks required source or manifest pins")
        println("source_export_sha256: ",file_sha256(abspath(ARGS[2])))
        println("source_export_hash_result: MATCH")
        println("source_export_data_hashes: deferred to full pilot plan")
        println("source_export_git_history: not established by this mode")
    catch exception
        push!(errors,"Source-export validation failed: $(sprint(showerror,exception))")
    end
end
println("git_root: ", git_root)

if root_ok
    safe_root = replace(git_root, '\\' => '/')
    git_prefix = [
        "git",
        "-c",
        "safe.directory=$safe_root",
        "-c",
        "core.excludesFile=",
        "-C",
        git_root,
    ]

    function git_capture(args...)
        return run_capture(vcat(git_prefix, collect(String, args)))
    end

    branch_ok, branch = git_capture("symbolic-ref", "--short", "-q", "HEAD")
    if !branch_ok
        short_ok, short_head = git_capture("rev-parse", "--short", "HEAD")
        branch = short_ok ? "DETACHED@$short_head" : "<unavailable>"
    end
    head_ok, head = git_capture("rev-parse", "HEAD")
    status_ok, status = git_capture("status", "--short", "--branch")

    println("git_branch: ", branch)
    println("git_head: ", head_ok ? head : "<unavailable>")
    print_block("git_status", status_ok ? status : "<failed: $status>")
    !head_ok && push!(errors, "Git HEAD lookup failed: $head")
    !status_ok && push!(errors, "Git status failed: $status")
end

println("required_context:")
for relative in REQUIRED_CONTEXT
    exists = isfile(project_path(relative))
    println("  ", exists ? "OK      " : "MISSING ", relative)
    !exists && push!(errors, "Required context file is missing: $relative")
end

println("active_control_references:")
config_directory = joinpath(PROJECT_ROOT, "configs")
reference_names = if isdir(config_directory)
    sort(filter(name -> endswith(name, "_active_control.ref"), readdir(config_directory)))
else
    String[]
end

if isempty(reference_names)
    println("  <none>")
else
    for name in reference_names
        reference_path = joinpath(config_directory, name)
        lines = filter(!isempty, strip.(readlines(reference_path)))
        println("  reference: configs/", name)
        if length(lines) != 2
            println("    result: MALFORMED (expected path and SHA-256)")
            push!(errors, "Malformed active-control reference: configs/$name")
            continue
        end

        target_relative, expected_hash = lines
        target_path = project_path(target_relative)
        println("    target: ", replace(target_relative, '\\' => '/'))
        println("    expected_sha256: ", lowercase(expected_hash))
        if !isfile(target_path)
            println("    local_artifact: MISSING (may require ignored-output sync)")
            push!(warnings, "Referenced ignored artifact is absent locally: $target_relative")
            continue
        end

        actual_hash = file_sha256(target_path)
        matches = actual_hash == lowercase(expected_hash)
        println("    local_artifact: PRESENT")
        println("    actual_sha256: ", actual_hash)
        println("    hash_result: ", matches ? "MATCH" : "MISMATCH")
        !matches && push!(errors, "Active-control hash mismatch: configs/$name")
    end
end

println("local_output_mirror:")
println("  authority: retrospective_only; Perlmutter is authoritative for live state")
output_directory = joinpath(PROJECT_ROOT, "output")
latest_pointers = String[]
if isdir(output_directory)
    for (directory, _, files) in walkdir(output_directory)
        "latest_run.txt" in files && push!(latest_pointers, joinpath(directory, "latest_run.txt"))
    end
end

if isempty(latest_pointers)
    println("  latest_run_pointers: <none>")
    push!(warnings, "No local latest_run.txt pointers were found; output may be unsynchronized")
else
    println("  latest_run_pointers:")
    for pointer in sort(latest_pointers)
        value = strip(read(pointer, String))
        println("    ", relative_display(pointer), " -> ", isempty(value) ? "<empty>" : value)
    end
    println("  caution: choose the greatest remote job ID in job.tsv, not a pointer alone")
end

if !isempty(warnings)
    println("warnings:")
    for warning in warnings
        println("  - ", warning)
    end
end

if isempty(errors)
    println("audit_result: OK", isempty(warnings) ? "" : "_WITH_WARNINGS")
    println("mutation_performed: false")
else
    println("errors:")
    for error in errors
        println("  - ", error)
    end
    println("audit_result: FAILED")
    println("mutation_performed: false")
    exit(2)
end
