using Test, TOML, SHA
include(joinpath(@__DIR__,"../scripts/lib/SolverPilotControl.jl"))
const PC=SolverPilotControl
const FI=PC.FileIntegrity
const SOURCE=normpath(joinpath(@__DIR__,".."))

@testset "Streaming and native file integrity" begin
    mktempdir() do root
        file=joinpath(root,"data with spaces.txt")
        write(file,repeat("abc\n",300000))
        expected=bytes2hex(sha256(read(file)))
        @test FI.file_sha256(file;native=false)==expected
        if isnothing(Sys.which("sha256sum"))
            @test_skip FI.file_sha256(file;native=true)==expected
        else
            @test FI.file_sha256(file;native=true)==expected
        end
        @test FI.file_sha256(file)==expected
        write(file,"changed")
        @test FI.file_sha256(file;native=true)!=expected
        @test_throws ErrorException FI.file_sha256(joinpath(root,"missing"))
        if Sys.islinux()
            escaped=joinpath(root,"name\nwith newline")
            write(escaped,"abc")
            @test FI.file_sha256(escaped;native=true)==bytes2hex(sha256("abc"))
        end
    end
end

@testset "Git-free source export retains source and data gates" begin
    mktempdir() do root
        source_paths=["scripts/audit_project_context.jl","scripts/lib/SolverPilotControl.jl",
            "scripts/lib/FileIntegrity.jl","scripts/lib/ProjectBAccounting.jl",
            "Project.toml","Manifest.toml","idmrg/Project.toml","idmrg/Manifest.toml",
            "configs/mpskit_solver_pilot.toml","scripts/audit_yc8_bridge_checkpoints.jl",
            "scripts/lib/ReviewEvidence.jl"]
        for relative in source_paths
            target=joinpath(root,relative); mkpath(dirname(target))
            cp(joinpath(SOURCE,relative),target)
        end
        for relative in ("AGENTS.md","docs/PROJECT_STATE.md","docs/ARCHITECTURE.md",
                "docs/plans/README.md","docs/decisions/README.md","docs/NEW_TASK_PROMPT.md")
            target=joinpath(root,relative); mkpath(dirname(target)); write(target,"Test context fixture\n")
        end
        mkpath(joinpath(root,"output"))
        data=joinpath(root,"output/data.h5"); write(data,"test payload")
        paths=vcat(source_paths,["output/data.h5"])
        recipe=TOML.parsefile(joinpath(root,"configs/mpskit_solver_pilot.toml"))
        control=Dict("artifact_kind"=>"project_b_mpskit_solver_pilot_control","schema_version"=>1,
            "recipe"=>recipe,"inputs"=>[Dict("path"=>p,"sha256"=>PC.sha(joinpath(root,p))) for p in paths])
        control_path=joinpath(root,"control.toml")
        open(io->TOML.print(io,control),control_path,"w")
        @test PC.validate(control_path;root,progress=devnull)==control
        write(data,"tampered test payload")
        @test PC.validate(control_path;root,code_only=true,progress=devnull)==control
        @test_throws ErrorException PC.validate(control_path;root,progress=devnull)
        @test_throws ErrorException PC.validate(control_path;root,live=true,code_only=true,progress=devnull)
        @test_throws ErrorException PC.root_path(root,"../escape")

        command=`$(Base.julia_cmd()) --startup-file=no $(joinpath(root,"scripts/audit_project_context.jl"))`
        function audit(args...)
            buffer=IOBuffer()
            process=run(pipeline(ignorestatus(`$command $args`);stdout=buffer,stderr=buffer))
            success(process),String(take!(buffer))
        end
        ok,output=audit()
        @test !ok && occursin("Git root lookup failed",output)
        ok,output=audit("--source-export",control_path)
        @test ok && occursin("source_export_hash_result: MATCH",output)
        @test occursin("source_export_data_hashes: deferred",output)
        @test occursin("git_root: <unavailable>",output)
        ok,output=audit("--source-export",joinpath(root,"missing.toml"))
        @test !ok && occursin("Source-export validation failed",output)
        open(io->write(io,"\n# changed\n"),joinpath(root,"Manifest.toml"),"a")
        ok,output=audit("--source-export",control_path)
        @test !ok && occursin("pilot input hash mismatch",output)
        cp(joinpath(SOURCE,"Manifest.toml"),joinpath(root,"Manifest.toml");force=true)

        @test_throws ErrorException PC.validate_audit(recipe;root)
        report=Dict("artifact_kind"=>"project_b_yc8_checkpoint_audit","authority"=>"owner_run_perlmutter",
            "parent_sha256"=>recipe["parent_sha256"],"all_requested_hashes_verified"=>true,
            "audit_script_sha256"=>PC.sha(joinpath(root,"scripts/audit_yc8_bridge_checkpoints.jl")),
            "audit_library_sha256"=>PC.sha(joinpath(root,"scripts/lib/ReviewEvidence.jl")),
            "audit_hash_library_sha256"=>PC.sha(joinpath(root,"scripts/lib/FileIntegrity.jl")),
            "artifacts"=>[Dict("sha256"=>hash,"hash_verified"=>true) for hash in
                ["4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6",
                 "45e5e6cf308936e35fdcf93f4d4cd909bcea4b8b71e061964b0e119ca1ddbcd7",
                 "fa4d7f01dbb7e10deb1c37bab659c07a9dba60fe63ba3e3db34c705c102b3e9b"]])
        report_path=PC.root_path(root,recipe["checkpoint_audit_path"]); mkpath(dirname(report_path))
        open(io->TOML.print(io,report),report_path,"w")
        @test PC.validate_audit(recipe;root)==report
        report["audit_hash_library_sha256"]="changed"
        open(io->TOML.print(io,report),report_path,"w")
        @test_throws ErrorException PC.validate_audit(recipe;root)
    end
end
