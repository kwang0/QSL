module FullFluxContinuation
using TOML
include("../roundtrip/Continuation.jl")
include("../../scripts/fullflux/Control.jl")
const RT=RoundTripContinuation
const R=RT.R
const B=RT.B
const C=FullFluxControl

function run_arm(control_path,name,scratch,compact;deadline=Inf,stop_file="")
    c=C.validate(control_path); r=c["recipe"]; hash=C.sha(control_path)
    arm=only(filter(a->a["name"]==name,C.arms(r)))
    RT.Random.seed!(r["random_seed"]); B.require_exact_environment()
    b=B.load_bridge(joinpath(C.ROOT,r["bridge_path"]))
    b.parent_sha256==b.numerical_seed_sha256==r["parent_sha256"] || error("accepted bridge required")
    b=merge(b,(;target_theta=r["start_theta_over_pi"]))
    psi=B.build_state(b); H=B.build_hamiltonian(b); envs=RT.MPSKit.environments(psi,H)
    row=Dict("iteration"=>0,"native_error"=>Float64(RT.MPSKit.calc_galerkin(psi,H,psi,envs)),
        "energy_density"=>R.SP.energy_density(psi,H,envs),"chi"=>r["chi"],"wall_seconds"=>0.0,"cpu_seconds"=>0.0)
    abs(row["energy_density"]-c["parent_energy_density_at_0p15"])<=r["model_energy_tolerance"] || error("initial energy mismatch")
    mkpath(scratch); mkpath(compact)
    payload=R.SP.write_candidate(joinpath(scratch,name*"_origin.h5"),psi,b,hash,
        Dict("algorithm"=>"VUMPS","theta_over_pi"=>r["start_theta_over_pi"]),[row],"accepted_parent_import";kind="diagnostic_origin")
    origin=Dict("path"=>payload.path,"sha256"=>payload.sha256,"theta_over_pi"=>r["start_theta_over_pi"],"iteration"=>0)
    C.write_toml(joinpath(compact,name*"_origin.toml"),Dict("artifact_kind"=>"project_b_fullflux_origin","schema_version"=>1,
        "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"arm"=>name,"payload"=>origin,
        "history"=>[row],"continuation_accepted"=>false))
    previous=origin; points=String[]; checkpoints=Dict{String,Any}[]
    function solve(x,j,theta,n)
        empty!(checkpoints)
        label=name*"_point$j"; journal=joinpath(compact,label*"_history.tsv")
        ispath(journal) && error("journal exists")
        open(io->println(io,"iteration\tnative_error\tenergy_density\tchi\twall_seconds\tcpu_seconds\tpayload_sha256"),journal,"w")
        if time()>=deadline || (!isempty(stop_file) && isfile(stop_file))
            return (;psi=x,history=Dict{String,Any}[],reason="graceful_stop")
        end
        b=merge(b,(;target_theta=Float64(theta))); H=B.build_hamiltonian(b)
        function callback(state,env,row,history)
            row["chi"]==r["chi"] || error("chi changed")
            i=row["iteration"]
            payload=R.SP.write_candidate(joinpath(scratch,label*"_iter$i.h5"),state,b,hash,
                Dict("algorithm"=>"VUMPS","theta_over_pi"=>theta),history,"fixed_iteration_fullflux";kind="checkpoint")
            cp=Dict("iteration"=>i,"path"=>payload.path,"sha256"=>payload.sha256,"theta_over_pi"=>theta,
                "native_gate_passed"=>R.SP.native_gate(history,r,"VUMPS"))
            push!(checkpoints,cp)
            C.write_toml(joinpath(compact,label*"_iter$i.toml"),merge(cp,Dict("artifact_kind"=>"project_b_fullflux_checkpoint",
                "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"diagnostic_seed"=>previous,
                "record"=>row,"continuation_accepted"=>false)))
            open(journal,"a") do io
                println(io,join(vcat([string(row[k]) for k in ("iteration","native_error","energy_density","chi","wall_seconds","cpu_seconds")],[payload.sha256]),'\t'))
            end
            println(label," theta/pi=",theta," update ",i,"/",n," Galerkin=",row["native_error"]," E=",row["energy_density"]); flush(stdout)
        end
        R.fixed_updates(x,H,n;deadline,stop_requested=()->!isempty(stop_file)&&isfile(stop_file),on_record=callback)
    end
    function record(j,result,full)
        label=name*"_point$j"
        p=Dict("artifact_kind"=>"project_b_fullflux_point","schema_version"=>1,"stage"=>label,"arm"=>name,
            "point"=>j,"theta_over_pi"=>arm["fluxes"][j],"iteration_budget"=>arm["iterations"],
            "delta_theta_over_pi"=>C.actual_step(r,j),"cumulative_updates_before"=>(j-1)*arm["iterations"],
            "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"origin"=>origin,"diagnostic_seed"=>previous,
            "history"=>result.history,"checkpoints"=>copy(checkpoints),"budget_complete"=>full,
            "stop_reason"=>result.reason,"continuation_accepted"=>false)
        C.write_toml(joinpath(compact,label*".toml"),p); push!(points,label)
        full && (previous=checkpoints[end])
    end
    result=RT.follow_path(psi,arm;solve,record)
    C.write_toml(joinpath(compact,name*"_outcome.toml"),Dict("artifact_kind"=>"project_b_fullflux_outcome","schema_version"=>1,
        "control_sha256"=>hash,"parent_sha256"=>r["parent_sha256"],"arm"=>name,"points"=>points,
        "budget_complete"=>result.complete,"continuation_accepted"=>false))
end
end
