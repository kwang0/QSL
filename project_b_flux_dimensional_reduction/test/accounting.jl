using Test, TOML, Dates
include(joinpath(@__DIR__,"../scripts/lib/ProjectBAccounting.jl"))
const A=ProjectBAccounting
@testset "Memory-rounded reservations and actual allocation charges" begin
    @test A.reservation(16,"32G","48:00:00")== (allocated_cpus=18,node_hours=3.375)
    @test A.reservation(4,"16G","12:00:00")== (allocated_cpus=10,node_hours=0.46875)
    @test A.reservation(4,"8G","48:00:00").node_hours==1.125
    @test A.reservation(128,"0","06:00:00";qos="regular").node_hours==6
    @test_throws ErrorException A.reservation(4,"8G","48")
    raw=A.HEADER*"\n57801654|pb1-yc8b|COMPLETED|124893|2880|1|18|0:0|||32G|shared\n57801654.0|pb1-yc8b|COMPLETED|124833|2880|1|8|0:0|2776996K||32G|shared\n"
    rows=A.parse_sacct(raw)
    @test length(rows)==1
    @test only(rows).charge≈2.43931640625
    regular=A.HEADER*"\n2|pb1-idmrg|COMPLETED|3600|60|1|128|0:0|||0|regular\n"
    @test only(A.parse_sacct(regular)).charge==1.0
    @test length(A.merge_rows(vcat(rows,rows)))==1
    @test_throws ErrorException A.merge_rows(vcat(rows,[merge(only(rows),(;cpus=16))]))
    @test isempty(A.parse_sacct(replace(raw,"pb1-yc8b"=>"other-project");accept=(id,name)->A.project_job(name)))
    @test A.terminal("CANCELLED by 102673")
end
@testset "Bounded live accounting retains complete allocation history" begin
    windows=A.accounting_windows("2026-08-01",DateTime(2026,9,6,12))
    @test windows==[(DateTime(2026,8,1),DateTime(2026,8,29)),
        (DateTime(2026,8,29),DateTime(2026,9,6,12))]
    long_windows=A.accounting_windows(DateTime(2024,1,15),DateTime(2024,4,1))
    @test all(b-a<=Day(28) for (a,b) in long_windows)
    @test all(long_windows[i][2]==long_windows[i+1][1] for i in 1:length(long_windows)-1)
    @test last(last(long_windows))==DateTime(2024,4,1)
    @test_throws ErrorException A.accounting_windows("2026-08-01","2026-08-01")
    @test_throws ErrorException A.accounting_windows("2026-08-01","2026-09-06";max_days=31)
    commands=Cmd[]
    shared="10|pb1-test|COMPLETED|7200|180|1|18|0:0|||32G|shared\n"
    function runner(command)
        push!(commands,command)
        shared*(length(commands)==1 ? "11|pb1-old|COMPLETED|3600|60|1|10|0:0|||16G|shared\n" :
            "12|pb1-new|COMPLETED|3600|60|1|10|0:0|||16G|shared\n")*
            "13|lmf1-other-project|PENDING|0|60|0|0|0:0|||0|shared\n"
    end
    history=A.accounting_history("test-user","2026-08-01";finish=DateTime(2026,9,6),runner,progress=devnull)
    rows=A.merge_rows(A.parse_sacct(history;accept=(id,name)->A.project_job(name)))
    @test Set(keys(rows))==Set(["10","11","12"])
    @test sum(r.charge for r in values(rows))≈(2*18+2*10)/256
    @test length(commands)==2
    @test "--starttime=2026-08-01T00:00:00" in first(commands).exec
    @test "--endtime=2026-09-06T00:00:00" in last(commands).exec
    @test occursin("# sacct window",history)
    @test_throws ErrorException A.accounting_history("test-user","2026-08-01";
        finish=DateTime(2026,9,6),runner=cmd->error("sacct unavailable"),progress=devnull)
end
@testset "Cross-root budget and immutable correction evidence" begin
    mktempdir() do root
        mkpath(joinpath(root,"configs")); mkpath(joinpath(root,"runs/a"))
        policy=Dict("run_roots"=>["runs"],"phase0_estimated_node_hours"=>1.0,
            "phase1_ceiling_node_hours"=>3.0,"project_ceiling_node_hours"=>150.0,
            "automatic_submission_ceiling_node_hours"=>140.0)
        open(io->TOML.print(io,policy),joinpath(root,"configs/project_b_accounting.toml"),"w")
        evidence=joinpath(root,"runs/a/sacct.tsv")
        write(evidence,A.HEADER*"\n1|pb1-test|COMPLETED|3600|60|1|18|0:0|||32G|shared\n")
        charge=joinpath(root,"runs/a/charged_node_hours.txt"); write(charge,"0.0625\n")
        original=A.sha(charge); s=A.snapshot(root)
        @test_throws ErrorException A.assert_budget(root,s,0.1)
        A.reconcile(root,s)
        @test A.sha(charge)==original
        @test A.assert_budget(root,A.snapshot(root),0.1)
        @test_throws ErrorException A.assert_budget(root,A.snapshot(root),3.0)
        @test_throws ErrorException A.assert_budget(root,merge(s,(;active=["other pb1 job"])),0.0)
        @test_throws ErrorException A.assert_budget(root,merge(s,(;missing=["2"])),0.0)
        correction=only(A.discrepancies(root,s))
        record=TOML.parsefile(correction.correction)
        write(joinpath(root,record["evidence_path"]),"tampered")
        @test_throws ErrorException A.assert_budget(root,A.snapshot(root),0.1)
    end
end
