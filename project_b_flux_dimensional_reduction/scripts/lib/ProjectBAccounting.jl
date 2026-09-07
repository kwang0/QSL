module ProjectBAccounting

using Dates, Printf, SHA, TOML

const TERMINAL = Set(["COMPLETED", "FAILED", "CANCELLED", "TIMEOUT", "NODE_FAIL",
    "OUT_OF_MEMORY", "PREEMPTED", "BOOT_FAIL", "DEADLINE", "REVOKED", "SPECIAL_EXIT"])
const FORMAT = "JobIDRaw,JobName,State,ElapsedRaw,TimelimitRaw,NNodes,NCPUS,ExitCode,MaxRSS,AveRSS,ReqMem,QOS"
const HEADER = replace(FORMAT, ',' => '|')
sha(path) = bytes2hex(open(sha256, path))
portable_relative(path,root) = replace(relpath(path,root), '\\'=>'/')
terminal(state) = first(split(first(split(strip(state))), '+')) in TERMINAL
project_job(name) = occursin(r"^(pb[0-4]-|project-b-)", name)

function memory_mib(value)
    m = match(r"^(\d+)([MGT]?)$", uppercase(String(value)))
    isnothing(m) && error("unsupported total-memory request: $value")
    parse(Int, m[1]) * get(Dict(""=>1, "M"=>1, "G"=>1024, "T"=>1024^2), m[2], 0)
end

function seconds(value)
    m = match(r"^(?:(\d+)-)?(\d+):(\d+):(\d+)$", String(value))
    isnothing(m) && error("use an explicit [D-]HH:MM:SS time limit")
    d = isnothing(m[1]) ? 0 : parse(Int, m[1])
    h, minute, s = parse.(Int, m.captures[2:4])
    minute < 60 && s < 60 || error("invalid time limit")
    d*86400 + h*3600 + minute*60 + s
end

function reservation(cpus, memory, time; qos="shared", nodes=1)
    cpus > 0 && nodes > 0 || error("positive CPU/node request required")
    if qos == "shared"
        nodes == 1 || error("Shared-QOS guard supports exactly one node")
        allocated = 2cld(max(cpus, cld(memory_mib(memory), 1952)), 2)
        allocated <= 256 || error("request exceeds a CPU node")
        return (; allocated_cpus=allocated, node_hours=seconds(time)/3600*allocated/256)
    end
    qos == "regular" || error("unbudgeted QOS: $qos")
    (; allocated_cpus=256nodes, node_hours=seconds(time)/3600*nodes)
end

function parse_sacct(text; source="inline", accept=(id, name)->true)
    rows = NamedTuple[]
    headers = String[]
    for line in split(text, '\n')
        isempty(strip(line)) && continue
        fields = strip.(split(strip(line), '|'; keepempty=true))
        if first(fields) in ("JobID", "JobIDRaw")
            headers = fields
            continue
        end
        occursin(r"^\d+$", first(fields)) || continue # allocation rows only
        qos=""
        if !isempty(headers)
            "ElapsedRaw" in headers || continue # efficiency-only exports
            length(fields) >= length(headers) || error("short accounting row: $source")
            d = Dict(zip(headers, fields))
            id = get(d, "JobIDRaw", get(d, "JobID", ""))
            name, state, elapsed = d["JobName"], d["State"], d["ElapsedRaw"]
            cpus = get(d, "NCPUS", get(d, "AllocCPUS", ""))
            nodes = get(d, "NNodes", "1")
            qos = get(d,"QOS","")
        elseif length(fields) in (7, 8) && endswith(basename(source), "sacct.tsv")
            id, name, state, elapsed, cpus = fields[1:5]
            nodes = "1" # historical one-node scan format
        elseif length(fields) >= 8
            id, name, state, elapsed = fields[1:4]
            nodes, cpus = fields[6:7]
        else
            error("unknown accounting format: $source")
        end
        accept(id, name) || continue
        ncpu, nnodes, sec = parse(Int, cpus), parse(Int, nodes), parse(Int, elapsed)
        ncpu > 0 && nnodes > 0 && sec >= 0 || error("invalid allocation values: $source")
        ncpu <= 256nnodes || error("CPU count exceeds declared CPU nodes: $source")
        phase_match = match(r"^pb([0-4])-", name)
        phase = isnothing(phase_match) ? -1 : parse(Int, phase_match[1])
        charge = qos=="regular" ? sec/3600*nnodes : sec/3600*cld(ncpu,2)/128
        push!(rows, (; id, name, state, elapsed=sec, cpus=ncpu, nodes=nnodes, phase,
            charge, source=String(source)))
    end
    rows
end

function merge_rows(rows)
    result = Dict{String,NamedTuple}()
    for row in rows
        row.phase == 0 && continue # explicitly covered by the Phase 0 estimate
        row.phase in 1:4 || error("cannot attribute phase for job $(row.id): $(row.name)")
        if haskey(result, row.id)
            old = result[row.id]
            same_allocation(old,row) ||
                error("conflicting accounting for job $(row.id): $(old.source) / $(row.source)")
        else
            result[row.id] = row
        end
    end
    result
end

same_allocation(a, b) = (a.elapsed,a.cpus,a.nodes,a.state,a.phase,a.charge) == (b.elapsed,b.cpus,b.nodes,b.state,b.phase,b.charge)

function discover(root, policy)
    rows = NamedTuple[]
    jobs = Set{String}()
    charges = Dict{String,Vector{String}}()
    for relative in policy["run_roots"]
        directory = joinpath(root, relative)
        isdir(directory) || continue
        for (dir, _, files) in walkdir(directory)
            ids = String[]
            if "job.tsv" in files
                lines = readlines(joinpath(dir, "job.tsv"))
                for line in lines[2:end]
                    id = first(split(line, '\t'))
                    occursin(r"^\d+$", id) || error("invalid job.tsv in $dir")
                    push!(ids, id)
                end
            end
            if "job_id.txt" in files
                id = strip(read(joinpath(dir, "job_id.txt"), String))
                occursin(r"^\d+$", id) || error("invalid job_id.txt in $dir")
                push!(ids, id)
            end
            for file in files
                occursin(r"^sacct(?:[-.]).*\.tsv$|^sacct\.tsv$", file) || continue
                path = joinpath(dir, file)
                parsed = parse_sacct(read(path, String); source=path)
                append!(rows, parsed)
                append!(ids, [r.id for r in parsed])
            end
            union!(jobs, ids)
            if "charged_node_hours.txt" in files
                length(unique(ids)) == 1 || error("charge file has ambiguous job in $dir")
                push!(get!(charges, first(ids), String[]), joinpath(dir, "charged_node_hours.txt"))
            end
        end
    end
    merged = merge_rows(rows)
    records = joinpath(root, "output/accounting/reconciliations")
    if isdir(records)
        latest = Dict{String,Tuple{String,NamedTuple}}()
        for (dir, _, files) in walkdir(records), file in files
            endswith(file, ".toml") || continue
            record = TOML.parsefile(joinpath(dir,file))
            record["artifact_kind"] == "project_b_live_reconciliation" || error("invalid reconciliation")
            evidence = joinpath(root, record["evidence_path"])
            sha(evidence) == record["evidence_sha256"] || error("reconciliation evidence hash mismatch")
            id = record["job_id"]
            row = only(filter(r -> r.id == id, parse_sacct(read(evidence,String); source=evidence,
                accept=(job,name)->job == id)))
            terminal(row.state) || error("nonterminal reconciliation: $id")
            time = record["recorded_utc"]
            if !haskey(latest,id) || time > latest[id][1]
                latest[id] = (time,row)
            elseif time == latest[id][1]
                same_allocation(row,latest[id][2]) || error("ambiguous reconciliation: $id")
            end
            push!(jobs,id)
        end
        for (id, (_,row)) in latest
            merged[id] = row
        end
    end
    (; rows=merged, jobs, charges)
end

function accounting_windows(start, finish; max_days=28)
    1 <= max_days <= 30 || error("accounting windows must stay below NERSC's 31-day limit")
    first_time, last_time = DateTime(start), DateTime(finish)
    first_time < last_time || error("accounting start must precede end")
    windows = Tuple{DateTime,DateTime}[]
    while first_time < last_time
        stop = min(first_time + Day(max_days), last_time)
        push!(windows, (first_time, stop))
        first_time = stop
    end
    windows
end

function accounting_history(user, start; finish=now(), max_days=28,
        runner=cmd->read(cmd,String), progress=stderr)
    windows = accounting_windows(start, finish; max_days)
    chunks = String[HEADER]
    for (i,(first_time,last_time)) in enumerate(windows)
        first_text = Dates.format(first_time,dateformat"yyyy-mm-ddTHH:MM:SS")
        last_text = Dates.format(last_time,dateformat"yyyy-mm-ddTHH:MM:SS")
        println(progress,"Accounting query ",i,"/",length(windows),": ",first_text," to ",last_text)
        flush(progress)
        # Whole allocation/step records are retained. Boundary duplicates are
        # reconciled by job ID, never summed as separate allocations.
        push!(chunks,"# sacct window $first_text to $last_text")
        push!(chunks,runner(`sacct -u $user --starttime=$first_text --endtime=$last_text -n -P --format=$FORMAT`))
    end
    join(chunks,"\n") * "\n"
end

function snapshot(root; live=false)
    policy = TOML.parsefile(joinpath(root, "configs/project_b_accounting.toml"))
    local_evidence = discover(root, policy)
    rows = local_evidence.rows
    raw = ""
    active = String[]
    if live
        Sys.islinux() || error("live accounting is only available on Perlmutter Linux")
        host = strip(read(`hostname -f`, String))
        (occursin("perlmutter", host) || startswith(get(ENV, "PSCRATCH", ""), "/pscratch/")) ||
            error("live accounting must run on Perlmutter")
        user = ENV["USER"]
        queue = read(`squeue -h -u $user -o %A\|%j`, String)
        for line in split(queue, '\n')
            fields = split(line, '|')
            length(fields) >= 2 || continue
            (project_job(fields[2]) || fields[1] in local_evidence.jobs) && push!(active, line)
        end
        raw = accounting_history(user,policy["start_date"];
            max_days=get(policy,"sacct_query_max_days",28))
        fresh = parse_sacct(raw; source="live sacct",
            accept=(id,name)->project_job(name) || id in local_evidence.jobs)
        rows = merge_rows(fresh)
    end
    missing = sort!(collect(setdiff(local_evidence.jobs, Set(keys(rows)))))
    nonterminal = sort!([r.id for r in values(rows) if !terminal(r.state)])
    unreconciled = sort!([id for (id,row) in rows if !haskey(local_evidence.rows,id) ||
        !same_allocation(row,local_evidence.rows[id])])
    phase1 = sum((r.charge for r in values(rows) if r.phase == 1); init=0.0)
    total = policy["phase0_estimated_node_hours"] + sum((r.charge for r in values(rows)); init=0.0)
    (; policy, rows, local_evidence, raw, active, missing, nonterminal, unreconciled,
        phase1, total, live)
end

function correction_path(root, id, path, charge)
    key = bytes2hex(sha256(string("v2:",sha(path), ':', charge)))
    joinpath(root, "output/accounting/corrections", "job_$(id)_$key.toml")
end

function discrepancies(root, snap)
    result = NamedTuple[]
    for (id, paths) in snap.local_evidence.charges
        haskey(snap.rows, id) || continue
        row = snap.rows[id]
        for path in paths
            old = parse(Float64, strip(read(path, String)))
            isfinite(old) && old >= 0 || error("invalid compact charge: $path")
            isapprox(old, row.charge; atol=1e-9, rtol=0) && continue
            correction = correction_path(root, id, path, row.charge)
            applied = false
            if isfile(correction)
                c = TOML.parsefile(correction)
                evidence = joinpath(root, c["evidence_path"])
                applied = c["old_charge_sha256"] == sha(path) &&
                    c["corrected_node_hours"] == row.charge && isfile(evidence) &&
                    sha(evidence) == c["evidence_sha256"]
            end
            push!(result, (; id, old, corrected=row.charge, path, correction, applied))
        end
    end
    result
end

function assert_budget(root, snap, forecast)
    isfinite(forecast) && forecast >= 0 || error("invalid forecast")
    isempty(snap.active) || error("another Project B job is active: $(join(snap.active, ", "))")
    isempty(snap.missing) || error("missing accounting: $(join(snap.missing, ','))")
    isempty(snap.nonterminal) || error("nonterminal predecessors: $(join(snap.nonterminal, ','))")
    isempty(snap.unreconciled) || error("run common reconcile for jobs $(join(snap.unreconciled, ','))")
    all(d -> d.applied, discrepancies(root, snap)) || error("compact charge mismatch: run common reconcile")
    snap.phase1 + forecast <= snap.policy["phase1_ceiling_node_hours"] || error("Phase 1 ceiling exceeded")
    snap.total + forecast <= min(snap.policy["project_ceiling_node_hours"],
        snap.policy["automatic_submission_ceiling_node_hours"]) || error("Project B submission ceiling exceeded")
    true
end

function write_immutable(path, contents)
    if isfile(path)
        read(path, String) == contents || error("immutable output differs: $path")
        return path
    end
    mkpath(dirname(path))
    temporary = path * ".tmp"
    ispath(temporary) && error("stale output temporary: $temporary")
    write(temporary, contents)
    mv(temporary, path)
    path
end

function reconcile(root, snap)
    isempty(snap.active) && isempty(snap.nonterminal) && isempty(snap.missing) ||
        error("reconcile requires all project jobs terminal and present")
    raw = isempty(snap.raw) ? "" : snap.raw
    if !isempty(raw)
        digest = bytes2hex(sha256(raw))
        evidence = joinpath(root,"output/accounting/evidence",digest*".tsv")
        write_immutable(evidence,raw)
        for id in snap.unreconciled
            record = Dict("artifact_kind"=>"project_b_live_reconciliation", "schema_version"=>1,
                "job_id"=>id, "evidence_path"=>portable_relative(evidence,root), "evidence_sha256"=>digest,
                "recorded_utc"=>string(now(UTC)))
            path = joinpath(root,"output/accounting/reconciliations",id,digest*".toml")
            isfile(path) || write_immutable(path,sprint(io->TOML.print(io,record;sorted=true)))
        end
    end
    for d in discrepancies(root, snap)
        d.applied && continue
        row = snap.rows[d.id]
        content = isempty(raw) ? read(row.source, String) : raw
        digest = bytes2hex(sha256(content))
        evidence = joinpath(root,"output/accounting/evidence",digest*".tsv")
        write_immutable(evidence, content)
        record = Dict("artifact_kind"=>"project_b_charge_correction", "schema_version"=>1,
            "job_id"=>d.id, "old_charge_path"=>portable_relative(d.path,root), "old_charge_sha256"=>sha(d.path),
            "old_node_hours"=>d.old, "corrected_node_hours"=>d.corrected,
            "allocated_logical_cpus"=>row.cpus, "elapsed_seconds"=>row.elapsed,
            "evidence_path"=>portable_relative(evidence,root), "evidence_sha256"=>digest,
            "authority"=>snap.live ? "live_perlmutter" : "retrospective_local_mirror")
        write_immutable(d.correction, sprint(io -> TOML.print(io, record; sorted=true)))
    end
end

function table(snap)
    io = IOBuffer()
    println(io, "job_id\tphase\tstate\telapsed_seconds\tallocated_logical_cpus\tcharged_node_hours\tsource")
    for r in sort!(collect(values(snap.rows)); by=r->parse(Int,r.id))
        println(io, join((r.id,r.phase,r.state,r.elapsed,r.cpus,@sprintf("%.12f",r.charge),r.source),'\t'))
    end
    String(take!(io))
end

end
