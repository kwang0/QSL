module ThreadBenchmark
using ProjectBIDMRG, MPSKit, TensorKit, LinearAlgebra, HDF5, Serialization, TOML, Random, Statistics
include("../src/RelaxationContinuation.jl")
include("../../scripts/thread_benchmark/Control.jl")
const R=RelaxationContinuation
const B=ProjectBIDMRG
const C=ThreadBenchmarkControl

function load_al(path)
    h5open(path,"r") do f
        read(f,"artifact_kind")=="project_b_thread_benchmark_al_bridge" && read(f,"schema_version")==1 || error("AL bridge schema")
        entries=map(1:2) do i
            prefix="state/site_$i"
            (;data=ComplexF64.(read(f,"$prefix/AL")),
                left_charges=Int.(read(f,"$prefix/left_charges")),
                physical_charges=Int.(read(f,"$prefix/physical_charges")),
                right_charges=Int.(read(f,"$prefix/right_charges")))
        end
        bonds=[(;source=Int(a),target=Int(b),coupling=Float64(j),anisotropy=Float64(d),twist_charge=Float64(t))
            for (a,b,j,d,t) in zip((read(f,"bonds/$key") for key in ("source","target","coupling","anisotropy","twist_charge"))...)]
        (;entries,bonds,period=2,target_theta=Float64(read(f,"theta_over_pi")),chi=Int(read(f,"chi")),
            source_energy=Float64(read(f,"source_energy_density")),source_sha256=read(f,"source_sha256"),
            control_sha256=read(f,"control_sha256"))
    end
end

function import_al(bridge)
    psi=InfiniteMPS(B.bridge_tensor.(bridge.entries);tol=1e-12,maxiter=2000)
    length(psi)==2 || error("unit cell changed")
    for i in 1:2
        dim(right_virtualspace(psi,i))==bridge.chi || error("import changed bond dimension")
        sort(B.tensor_basis_charges(right_virtualspace(psi,i)))==sort(bridge.entries[i].right_charges) || error("import changed U1 spaces")
    end
    psi
end

function canonical_errors(psi)
    left=Float64[]; right=Float64[]; center=Float64[]
    for i in 1:length(psi)
        al,ar=psi.AL[i],psi.AR[i]
        push!(left,norm(al'*al-id(domain(al)))/sqrt(dim(domain(al))))
        @plansor gram[-1;-2] := ar[-1 1;2]*conj(ar[-2 1;2])
        push!(right,norm(gram-id(space(ar,1)))/sqrt(dim(space(ar,1))))
        @plansor difference[-1 -2;-3] := al[-1 -2;1]*psi.C[i][1;-3]-psi.C[i-1][-1;1]*ar[1 -2;-3]
        push!(center,norm(difference)/max(norm(psi.C[i]),eps()))
    end
    Dict("left_isometry"=>maximum(left),"right_isometry"=>maximum(right),"center_relation"=>maximum(center))
end

function prepare(control,compact)
    c=C.validate(control); hash=C.sha(control); e=TOML.parsefile(joinpath(compact,"export.toml"))
    e["control_sha256"]==hash && e["source_seed_sha256"]==c["seed"]["source_sha256"] || error("export provenance")
    path=e["bridge_path"]; C.sha(path)==e["bridge_sha256"] || error("AL bridge changed")
    B.require_exact_environment(); BLAS.set_num_threads(1); Random.seed!(c["recipe"]["random_seed"])
    b=load_al(path); b.source_sha256==e["source_seed_sha256"] && b.control_sha256==hash || error("bridge provenance")
    b.chi==1024 && b.target_theta==.15 || error("bridge representation")
    psi=import_al(b); errors=canonical_errors(psi)
    maximum(values(errors))<=c["recipe"]["canonical_tolerance"] || error("canonical import failed")
    H=B.build_hamiltonian(b); env=MPSKit.environments(psi,H)
    energy=R.SP.energy_density(psi,H,env)
    output=joinpath(dirname(path),"canonical_seed.jls"); ispath(output) && error("canonical seed exists")
    tmp=output*".tmp"; ispath(tmp) && error("stale canonical seed temporary")
    serialize(tmp,(;psi,bridge=b)); mv(tmp,output)
    C.write_toml(joinpath(compact,"seed.toml"),Dict("artifact_kind"=>"project_b_thread_benchmark_canonical_seed",
        "control_sha256"=>hash,"source_seed_sha256"=>b.source_sha256,"bridge_sha256"=>e["bridge_sha256"],
        "canonical_seed_path"=>output,"canonical_seed_sha256"=>C.sha(output),"julia_version"=>string(VERSION),
        "energy_density"=>energy,"original_energy_density"=>b.source_energy,"import_energy_change"=>energy-b.source_energy,
        "canonical_errors"=>errors,"scientific_promotion"=>false,
        "interpretation"=>"One recanonicalization of the rejected AL seed, shared exactly by all timing settings; import energy change is diagnostic."))
    println("Prepared one canonical chi1024 timing seed; import energy change = ",energy-b.source_energy)
end

function run(control,name,compact)
    c=C.validate(control); r=c["recipe"]; hash=C.sha(control)
    setting=only(filter(s->s["name"]==name,r["settings"]))
    B.require_exact_environment()
    Threads.nthreads()==setting["julia_threads"] || error("wrong Julia thread count")
    BLAS.set_num_threads(setting["blas_threads"])
    BLAS.get_num_threads()==setting["blas_threads"] || error("wrong BLAS thread count")
    parse(Int,get(ENV,"SLURM_CPUS_PER_TASK","0"))==r["resources"]["step_cpus"] || error("wrong step CPU binding allocation")
    s=TOML.parsefile(joinpath(compact,"seed.toml"))
    s["control_sha256"]==hash && s["source_seed_sha256"]==c["seed"]["source_sha256"] || error("canonical seed provenance")
    s["julia_version"]==string(VERSION) || error("serialized seed Julia version differs")
    C.sha(s["canonical_seed_path"])==s["canonical_seed_sha256"] || error("canonical seed hash mismatch")
    initial=deserialize(s["canonical_seed_path"]); psi=initial.psi; b=initial.bridge
    b.chi==r["chi"] && b.target_theta==r["theta_over_pi"] || error("serialized seed representation")
    H=B.build_hamiltonian(b); Random.seed!(r["random_seed"])
    prefix=joinpath(compact,name); ispath(prefix*".toml") && error("benchmark result exists")
    ispath(prefix*".tsv") && error("benchmark journal exists")
    deadline=parse(Float64,get(ENV,"PROJECT_B_THREAD_BENCHMARK_DEADLINE","Inf"))
    stopfile=get(ENV,"PROJECT_B_PRETIMEOUT_REQUEST_FILE","")
    result=open(prefix*".tsv","w") do io
        println(io,"iteration\tmeasured\tenergy_density\tnative_error\tchi\twall_seconds\tcpu_seconds"); flush(io)
        R.fixed_updates(psi,H,r["warmup_iterations"]+r["measured_iterations"];deadline,
            stop_requested=()->!isempty(stopfile)&&isfile(stopfile),on_record=(x,env,row,history)->begin
                all(dim(right_virtualspace(x,i))==r["chi"] for i in 1:2) || error("benchmark bond dimension changed")
                row["measured"]=row["iteration"]>r["warmup_iterations"]
                println(io,join((row[k] for k in ("iteration","measured","energy_density","native_error","chi","wall_seconds","cpu_seconds")),'\t')); flush(io)
                println(name," update ",row["iteration"]," measured=",row["measured"]," seconds=",row["wall_seconds"]," energy=",row["energy_density"]," error=",row["native_error"]); flush(stdout)
            end)
    end
    complete=length(result.history)==4 && result.reason=="fixed_budget_complete"
    abs(result.initial_energy-s["energy_density"])<=r["initial_energy_match_tolerance"] || error("initial energy differs")
    affinity=Sys.islinux() ? only(filter(x->startswith(x,"Cpus_allowed_list:"),readlines("/proc/self/status"))) : "unavailable"
    C.write_toml(prefix*".toml",Dict("artifact_kind"=>"project_b_vumps_thread_benchmark_result","schema_version"=>1,
        "control_sha256"=>hash,"setting"=>setting,"canonical_seed_sha256"=>s["canonical_seed_sha256"],
        "source_seed_sha256"=>s["source_seed_sha256"],"initial_energy_density"=>result.initial_energy,
        "complete"=>complete,"stop_reason"=>result.reason,"history"=>result.history,"journal_sha256"=>C.sha(prefix*".tsv"),
        "julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),"blas_backend"=>string(BLAS.get_config()),
        "julia_version"=>string(VERSION),"step_cpus"=>r["resources"]["step_cpus"],"affinity"=>affinity,
        "scientific_promotion"=>false))
    complete || error("benchmark interrupted before completing setting $name")
end
end
