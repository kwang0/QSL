module RelaxationContinuation
using ProjectBIDMRG, MPSKit, TensorKit, LinearAlgebra, TOML, Random
include("SolverPilot.jl")
include(joinpath(@__DIR__,"../../scripts/lib/RelaxationControl.jl"))
const B=ProjectBIDMRG
const SP=SolverPilot
const RC=RelaxationControl

"""Run exactly the requested outer updates unless interrupted. Tolerance is diagnostic only.
The same IterativeSolver persists through an endpoint and its fixed-flux hold."""
function fixed_updates(psi,H,n;deadline=Inf,stop_requested=()->false,on_record=(args...)->nothing)
    envs=MPSKit.environments(psi,H)
    epsilon=Float64(MPSKit.calc_galerkin(psi,H,psi,envs))
    initial_energy=SP.energy_density(psi,H,envs)
    history=Dict{String,Any}[]
    timer=MPSKit.TimerOutput("Project B fixed iteration continuation"); MPSKit.disable_timer!(timer)
    # Keep the pilot's inner accuracy policy. Only its outer stopping policy changes.
    alg=VUMPS(tol=1e-5,maxiter=n,verbosity=0)
    solver=MPSKit.IterativeSolver(alg,MPSKit.VUMPSState(copy(psi),H,envs,0,epsilon,:SR,timer))
    reason="fixed_budget_complete"
    for i in 1:n
        if time()>=deadline || stop_requested(); reason="graceful_stop"; break; end
        started=time(); cpu=B.process_cpu_seconds()
        (psi,envs,epsilon),_=iterate(solver)
        row=Dict{String,Any}("iteration"=>i,"native_error"=>Float64(epsilon),
            "energy_density"=>SP.energy_density(psi,H,envs),
            "chi"=>maximum(dim(right_virtualspace(psi,j)) for j in 1:length(psi)),
            "wall_seconds"=>time()-started,"cpu_seconds"=>B.process_cpu_seconds()-cpu)
        all(isfinite(row[k]) for k in ("native_error","energy_density","wall_seconds","cpu_seconds")) || error("nonfinite VUMPS record")
        push!(history,row)
        on_record(psi,envs,row,history)
    end
    (;psi,envs,history,initial_energy,epsilon,reason)
end

"""First sustained rise above the running best. This labels evidence; it never stops a run."""
function turnaround(history,r)
    best=Inf; count=0
    for row in history
        e=row["native_error"]
        if e<best; best=e; count=0
        elseif e>best*(1+r["turnaround_relative_rise"]); count+=1
        else; count=0
        end
        count>=r["turnaround_patience"] && return row["iteration"]
    end
    0
end

function selected_iterations(history,n,r)
    isempty(history) && return Int[]
    endpoint=min(n,length(history))
    selection=[endpoint,argmin([h["native_error"] for h in history[1:endpoint]])]
    if length(history)>n
        append!(selection,[length(history),argmin([h["native_error"] for h in history])])
    end
    turn=turnaround(history,r)
    turn>0 && push!(selection,turn)
    sort(unique(selection))
end

function run_arm(control_path,name,scratch,compact;deadline=Inf,stop_file="")
    c=RC.validate(control_path); r=c["recipe"]; hash=RC.sha(control_path)
    arm=only(filter(a->a["name"]==name,RC.arms(r)))
    Random.seed!(r["random_seed"])
    B.require_exact_environment()
    b=B.load_bridge(joinpath(RC.ROOT,r["bridge_path"]))
    b.parent_sha256==b.numerical_seed_sha256==r["parent_sha256"] || error("not accepted-parent bridge")
    b=merge(b,(;target_theta=r["start_theta_over_pi"]))
    psi=B.build_state(b); H=B.build_hamiltonian(b); envs=MPSKit.environments(psi,H)
    energy=SP.energy_density(psi,H,envs)
    abs(energy-c["parent_energy_density_at_0p15"])<=r["model_energy_tolerance"] || error("initial model equivalence failed")
    mkpath(scratch); mkpath(compact)
    origin_row=Dict("iteration"=>0,"native_error"=>Float64(MPSKit.calc_galerkin(psi,H,psi,envs)),
        "energy_density"=>energy,"chi"=>r["chi"],"wall_seconds"=>0.0,"cpu_seconds"=>0.0)
    stage=Dict("algorithm"=>"VUMPS","theta_over_pi"=>r["start_theta_over_pi"])
    origin=SP.write_candidate(joinpath(scratch,name*"_origin.h5"),psi,b,hash,stage,[origin_row],"accepted_parent_import";kind="diagnostic_origin")
    previous=Dict("path"=>origin.path,"sha256"=>origin.sha256,"theta_over_pi"=>r["start_theta_over_pi"])
    RC.write_toml(joinpath(compact,name*"_origin.toml"),Dict("artifact_kind"=>"project_b_relaxation_origin",
        "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"payload"=>previous,"history"=>[origin_row]))
    finished=String[]; complete=true
    stopped()=!isempty(stop_file)&&isfile(stop_file)
    for (j,theta) in enumerate(arm["fluxes"])
        label=name*"_point$(j)"; n=arm["iterations"]
        hold=j==length(arm["fluxes"]) ? arm["hold_iterations"] : 0
        b=merge(b,(;target_theta=Float64(theta))); H=B.build_hamiltonian(b)
        journal=joinpath(compact,label*"_history.tsv")
        ispath(journal) && error("immutable journal exists: $journal")
        open(io->println(io,"iteration\tnative_error\tenergy_density\tchi\twall_seconds\tcpu_seconds\tpayload_sha256"),journal,"w")
        checkpoints=Dict{String,Any}[]
        callback=function(x,e,row,history)
            row["chi"]==r["chi"] || error("virtual dimension changed")
            iteration=row["iteration"]
            payload=SP.write_candidate(joinpath(scratch,label*"_iter$(iteration).h5"),x,b,hash,
                Dict("algorithm"=>"VUMPS","theta_over_pi"=>theta),history,"fixed_iteration_diagnostic";kind="checkpoint")
            cp=Dict{String,Any}("iteration"=>iteration,"path"=>payload.path,"sha256"=>payload.sha256,
                "theta_over_pi"=>theta,"native_gate_passed"=>SP.native_gate(history,r,"VUMPS"))
            push!(checkpoints,cp)
            # An atomic compact record survives even if the allocation ends before its point manifest.
            RC.write_toml(joinpath(compact,label*"_iter$(iteration).toml"),merge(cp,Dict(
                "artifact_kind"=>"project_b_relaxation_checkpoint","control_sha256"=>hash,
                "parent_sha256"=>r["parent_sha256"],"diagnostic_seed"=>previous,
                "continuation_accepted"=>false,"record"=>row)))
            open(journal,"a") do io
                println(io,join(vcat([string(row[k]) for k in ("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds")],[payload.sha256]),'\t'))
            end
            println(label," iteration ",iteration,"/",n+hold," Galerkin=",row["native_error"]," E=",row["energy_density"]); flush(stdout)
        end
        result=fixed_updates(psi,H,n+hold;deadline,stop_requested=stopped,on_record=callback)
        full=length(result.history)==n+hold
        record=Dict("artifact_kind"=>"project_b_relaxation_point","schema_version"=>1,
            "stage"=>label,"arm"=>name,"point"=>j,"algorithm"=>"VUMPS","theta_over_pi"=>theta,
            "step_over_pi"=>arm["step_over_pi"],"iteration_budget"=>n,"hold_iterations"=>hold,
            "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"origin"=>Dict("path"=>origin.path,"sha256"=>origin.sha256),
            "diagnostic_seed"=>previous,"history"=>result.history,"checkpoints"=>checkpoints,
            "selected_iterations"=>selected_iterations(result.history,n,r),"turnaround_iteration"=>turnaround(result.history,r),
            "budget_complete"=>full,"stop_reason"=>result.reason,"continuation_accepted"=>false)
        RC.write_toml(joinpath(compact,label*".toml"),record); push!(finished,label)
        if !full; complete=false; break; end
        # Only the predeclared N-th state advances an arm. Never use its best residual or held state.
        # Holds occur only at the last flux; intermediate points have exactly N iterations.
        psi=result.psi
        previous=checkpoints[n]
    end
    RC.write_toml(joinpath(compact,name*"_outcome.toml"),Dict("artifact_kind"=>"project_b_relaxation_arm_outcome",
        "control_sha256"=>hash,"arm"=>name,"points"=>finished,"budget_complete"=>complete,"continuation_accepted"=>false))
end
end
