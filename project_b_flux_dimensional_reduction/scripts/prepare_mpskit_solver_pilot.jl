include(joinpath(@__DIR__,"lib/ReviewEvidence.jl"))
include(joinpath(@__DIR__,"lib/SolverPilotControl.jl"))
using .ReviewEvidence, .SolverPilotControl, TOML, HDF5, Dates
const R=ReviewEvidence
length(ARGS)==1 || error("usage: prepare_mpskit_solver_pilot.jl NEW_CONTROL.toml")
recipe=TOML.parsefile(joinpath(R.ROOT,"configs/mpskit_solver_pilot.toml"))
parent=R.parent_path()
bridge=joinpath(R.ROOT,recipe["bridge_path"])
oldcontrol=TOML.parsefile(joinpath(dirname(bridge),"phase1_idmrg_control.toml"))
R.sha(bridge)==oldcontrol["bridge"]["sha256"] || error("historical bridge hash mismatch")
energy_target=h5open(bridge,"r") do f
    read(f,"lineage/parent_state_sha256")==R.PARENT_SHA || error("bridge parent mismatch")
    read(f,"model/target_theta_over_pi")==0.2 || error("bridge target mismatch")
    read(f,"validation/parent_energy_density_at_target")
end
files=["Project.toml","Manifest.toml","idmrg/Project.toml","idmrg/Manifest.toml",
    "configs/mpskit_solver_pilot.toml","configs/project_b_accounting.toml",
    "slurm/lib/project_b_resources.sh","slurm/run_mpskit_solver_pilot_cpu.sh","slurm/run_mpskit_solver_pilot_job.sh",
    "scripts/prepare_mpskit_solver_pilot.jl","scripts/validate_mpskit_solver_pilot.jl","scripts/project_b_accounting.jl",
    "scripts/audit_project_context.jl","scripts/audit_yc8_bridge_checkpoints.jl","scripts/analyze_mpskit_solver_pilot.jl",
    "idmrg/scripts/run_solver_pilot.jl","idmrg/scripts/preflight_solver_pilot.jl",
    recipe["bridge_path"],replace(relpath(parent,R.ROOT),'\\'=>'/')]
for directory in ("src","scripts/lib","idmrg/src")
    append!(files,[replace(relpath(joinpath(R.ROOT,directory,f),R.ROOT),'\\'=>'/')
        for f in readdir(joinpath(R.ROOT,directory)) if endswith(f,".jl")])
end
inputs=[Dict("path"=>f,"sha256"=>R.sha(joinpath(R.ROOT,f))) for f in sort(unique(files))]
data=Dict("artifact_kind"=>"project_b_mpskit_solver_pilot_control","schema_version"=>1,
    "created_utc"=>string(now(UTC)),"recipe"=>recipe,"inputs"=>inputs,
    "parent_path"=>replace(relpath(parent,R.ROOT),'\\'=>'/'),
    "parent_energy_density_at_0p15"=>R.scalars(parent;verified_sha256=R.PARENT_SHA)["energy_density"],
    "parent_energy_density_at_0p2"=>energy_target)
R.write_toml(abspath(only(ARGS)),data)
SolverPilotControl.validate(abspath(only(ARGS)))
println("Prepared immutable pilot: ",abspath(only(ARGS)))
println("Control SHA-256: ",R.sha(abspath(only(ARGS))))
println("Local preparation complete; live accounting and scratch audit remain required.")
