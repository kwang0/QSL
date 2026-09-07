module SolverPilot
using ProjectBIDMRG, MPSKit, TensorKit, LinearAlgebra, HDF5, TOML, Dates
const B=ProjectBIDMRG
struct GracefulStop <: Exception end
energy_density(psi,H,envs) = Float64(real(sum(MPSKit.expectation_value(psi,H,envs)))/length(psi))
function native_gate(history, recipe, algorithm)
    n=length(history); w=recipe["energy_window"]
    n>=max(w,recipe["minimum_iterations"]) && history[end]["iteration"]>=recipe["minimum_iterations"] || return false
    tail=history[end-w+1:end]
    tolerance=recipe[algorithm=="VUMPS" ? "vumps_galerkin_tolerance" : "grassmann_gradient_tolerance"]
    all(r->r["chi"]==recipe["chi"] && isfinite(r["energy_density"]) && isfinite(r["native_error"]),tail) &&
        tail[end]["native_error"]<=tolerance &&
        maximum(r["energy_density"] for r in tail)-minimum(r["energy_density"] for r in tail)<=recipe["energy_span_tolerance"]
end

"""Bounded fixed-space solver. Callback records completed iterations only."""
function solve_kernel(psi,H,algorithm; maxiter=60,tolerance=1e-5,deadline=Inf,
        stop_requested=()->false,on_record=(args...)->nothing)
    envs=MPSKit.environments(psi,H)
    initial_energy=energy_density(psi,H,envs)
    history=Dict{String,Any}[]
    last_time=time(); last_cpu=B.process_cpu_seconds()
    function record(x,env,i,epsilon,energy)
        now_time=time(); now_cpu=B.process_cpu_seconds()
        row=Dict{String,Any}("iteration"=>i,"native_error"=>Float64(epsilon),
            "energy_density"=>Float64(energy),"chi"=>maximum(dim(right_virtualspace(x,j)) for j in 1:length(x)),
            "wall_seconds"=>now_time-last_time,"cpu_seconds"=>now_cpu-last_cpu)
        all(isfinite(row[k]) for k in ("native_error","energy_density","wall_seconds","cpu_seconds")) ||
            error("nonfinite solver diagnostic")
        push!(history,row); on_record(x,env,row,history)
        last_time=time(); last_cpu=B.process_cpu_seconds()
    end
    stopped()=time()>=deadline || stop_requested()
    reason="iteration_cap"; epsilon=NaN
    if stopped()
        return (;psi,envs,history,initial_energy,epsilon,reason="stop_before_iteration")
    elseif algorithm=="VUMPS"
        alg=VUMPS(tol=tolerance,maxiter=maxiter,verbosity=0)
        epsilon=Float64(MPSKit.calc_galerkin(psi,H,psi,envs))
        timer=MPSKit.TimerOutput("Project B VUMPS pilot"); MPSKit.disable_timer!(timer)
        solver=MPSKit.IterativeSolver(alg,MPSKit.VUMPSState(copy(psi),H,envs,0,epsilon,:SR,timer))
        for i in 1:maxiter
            (psi,envs,epsilon),_=iterate(solver)
            record(psi,envs,i,epsilon,energy_density(psi,H,envs))
            if stopped(); reason="graceful_stop"; break; end
            if epsilon<=tolerance && i>=4; reason="native_tolerance"; break; end
        end
    elseif algorithm=="GradientGrassmann"
        saved=Ref(psi)
        callback=function(x,f,g,i)
            epsilon=Float64(sqrt(max(0,MPSKit.GrassmannMPS.inner(x,g,g))))
            # f is the energy of the full unit cell in the pinned MPSKit implementation.
            record(x,envs,i,epsilon,real(f)/length(x))
            saved[]=x
            stopped() && throw(GracefulStop())
            return x,f,g
        end
        method=MPSKit.OptimKit.ConjugateGradient(gradtol=tolerance,maxiter=maxiter,verbosity=0,
            linesearch=MPSKit.OptimKit.HagerZhangLineSearch(maxiter=20,verbosity=0))
        alg=GradientGrassmann(method=method,finalize! = callback)
        try
            psi,envs,epsilon=MPSKit.find_groundstate(psi,H,alg,envs)
            reason=epsilon<=tolerance ? "native_tolerance" : "iteration_cap"
        catch e
            e isa GracefulStop || rethrow()
            psi=saved[]; epsilon=isempty(history) ? NaN : history[end]["native_error"]
            reason="graceful_stop"
        end
    else
        error("unsupported pilot algorithm: $algorithm")
    end
    (;psi,envs,history,initial_energy,epsilon,reason)
end

function write_candidate(path,psi,bridge,control_sha,stage,history,reason;kind="candidate")
    ispath(path) && error("immutable pilot payload exists: $path")
    mkpath(dirname(path)); tmp=path*".tmp"
    ispath(tmp) && error("stale pilot payload temporary")
    h5open(tmp,"w") do f
        f["artifact_kind"]="project_b_mpskit_solver_pilot_result"
        f["schema_version"]=2; f["payload_role"]=kind
        f["canonical_payload"]=true
        f["control_sha256"]=control_sha; f["parent_sha256"]=bridge.parent_sha256
        f["algorithm"]=stage["algorithm"]; f["theta_over_pi"]=stage["theta_over_pi"]
        f["native_error_semantics"]=stage["algorithm"]=="VUMPS" ?
            "MPSKit.calc_galerkin projected error" : "OptimKit Grassmann gradient norm"
        f["stop_reason"]=reason; f["continuation_accepted"]=false
        for (i,entry) in enumerate(bridge.tensors)
            prefix="state/site_$i"
            f["$prefix/AL"]=B.state_in_bridge_order(psi.AL[i],entry)
            f["$prefix/AR"]=B.state_in_bridge_order(psi.AR[i],entry)
            center=psi.C[i]
            pl=B.basis_permutation(entry.right_charges,B.tensor_basis_charges(space(center,1)))
            pr=B.basis_permutation(entry.right_charges,B.tensor_basis_charges(domain(center)[1]))
            f["$prefix/C"]=convert(Array,center)[invperm(pl),invperm(pr)]
            f["$prefix/left_charges"]=entry.left_charges
            f["$prefix/physical_charges"]=entry.physical_charges
            f["$prefix/right_charges"]=entry.right_charges
        end
        for key in ("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds")
            values=[r[key] for r in history]
            f["history/$key"]=key in ("iteration","chi") ? Int.(values) : Float64.(values)
        end
    end
    mv(tmp,path)
    (;path,sha256=B.file_sha256(path))
end

function run_stage(control_path,stage_name,scratch,compact;deadline=Inf,stop_file="")
    control=TOML.parsefile(control_path); recipe=control["recipe"]
    root=normpath(joinpath(@__DIR__,"../.."))
    B.require_exact_environment()
    stage=only(filter(s->s["name"]==stage_name,recipe["stages"]))
    stage_deadline=min(deadline,time()+stage["maximum_seconds"])
    bridge=B.load_bridge(joinpath(root,recipe["bridge_path"]))
    bridge.parent_sha256==recipe["parent_sha256"] && bridge.numerical_seed_sha256==bridge.parent_sha256 ||
        error("pilot must start from the accepted parent")
    bridge=merge(bridge,(;target_theta=Float64(stage["theta_over_pi"])))
    psi=B.build_state(bridge); H=B.build_hamiltonian(bridge)
    envs=MPSKit.environments(psi,H)
    initial_energy=energy_density(psi,H,envs)
    reference=control[stage["theta_over_pi"]==0.15 ? "parent_energy_density_at_0p15" : "parent_energy_density_at_0p2"]
    abs(initial_energy-reference)<=recipe["model_energy_tolerance"] || error("cross-library Hamiltonian equality failed")
    mkpath(compact); mkpath(scratch)
    control_sha=B.file_sha256(control_path)
    journal=joinpath(compact,stage_name*"_history.tsv")
    ispath(journal) && error("stage history exists")
    checkpoint_records=Dict{String,Any}[]
    open(journal,"w") do io
        println(io,"iteration\tnative_error\tenergy_density\tchi\twall_seconds\tcpu_seconds")
    end
    callback=function(x,env,row,history)
        open(journal,"a") do io
            println(io,join((row[k] for k in ("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds")),'\t'))
        end
        println(stage_name," iteration ",row["iteration"],": ",row["native_error"]," E=",row["energy_density"])
        if row["iteration"]>0 && row["iteration"]%recipe["checkpoint_every"]==0
            cp=write_candidate(joinpath(scratch,stage_name*"_iter_"*string(row["iteration"])*".h5"),
                x,bridge,control_sha,stage,history,"diagnostic_checkpoint";kind="checkpoint")
            push!(checkpoint_records,Dict("path"=>cp.path,"sha256"=>cp.sha256))
        end
    end
    tol=recipe[stage["algorithm"]=="VUMPS" ? "vumps_galerkin_tolerance" : "grassmann_gradient_tolerance"]
    result=solve_kernel(psi,H,stage["algorithm"];maxiter=recipe["maximum_iterations"],tolerance=tol,
        deadline=stage_deadline,stop_requested=()->!isempty(stop_file)&&isfile(stop_file),on_record=callback)
    isempty(result.history) && error("no completed solver iterations; see checkpoint/log evidence")
    payload=write_candidate(joinpath(scratch,stage_name*"_result.h5"),result.psi,bridge,control_sha,
        stage,result.history,result.reason)
    record=Dict("artifact_kind"=>"project_b_mpskit_solver_pilot_stage","schema_version"=>1,
        "stage"=>stage_name,"algorithm"=>stage["algorithm"],"theta_over_pi"=>stage["theta_over_pi"],
        "control_sha256"=>control_sha,"parent_sha256"=>bridge.parent_sha256,
        "result_path"=>payload.path,"result_sha256"=>payload.sha256,"stop_reason"=>result.reason,
        "model_equivalence_error"=>abs(initial_energy-reference),"initial_energy_density"=>initial_energy,
        "native_gate_passed"=>native_gate(result.history,recipe,stage["algorithm"]),
        "history"=>result.history,"checkpoints"=>checkpoint_records,"continuation_accepted"=>false)
    target=joinpath(compact,stage_name*".toml")
    ispath(target) && error("immutable stage manifest exists")
    open(io->TOML.print(io,record;sorted=true),target,"w")
    println("Stage manifest: ",target)
    record
end
end
