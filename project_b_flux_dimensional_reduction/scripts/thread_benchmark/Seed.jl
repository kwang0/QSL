module ThreadBenchmarkSeed
using TriangularJ1J2ProjectB, ITensors, ITensorMPS, HDF5, TOML
include("Control.jl")
const C=ThreadBenchmarkControl
const PB=TriangularJ1J2ProjectB
function indices(t)
    p=only(filter(i->hastags(i,"Site"),inds(t)))
    links=filter(i->hastags(i,"Link"),inds(t))
    only(filter(i->dir(i)==ITensors.Out,links)),p,only(filter(i->dir(i)==ITensors.In,links))
end
charges(i)=reduce(vcat,[fill(Int(val(q,"Sz")),Int(n)) for (q,n) in space(i)])

"""Export the existing left tensors only; the benchmark canonicalizes once in MPSKit."""
function export_al(path,source,source_sha,control_sha)
    ispath(path) && error("immutable bridge exists")
    C.sha(source)==source_sha || error("source changed before export")
    s=PB.read_state_file(source)
    s.circumference==8 && s.shift==1 && s.mps_period==2 && s.twist_gauge==:uniform || error("seed geometry/gauge")
    (s.J1,s.J2,s.Delta1,s.Delta2,s.Bz)==(1.,.12,1.,1.,0.) || error("seed Hamiltonian")
    PB.maxlinkdim(s.psi)==s.maxlinkdim || error("seed bond metadata mismatch")
    bonds=PB.unit_cell_bonds(PB.YCGeometry(8,1);period=2)
    mkpath(dirname(path)); tmp=path*".tmp"; ispath(tmp) && error("stale bridge temporary")
    h5open(tmp,"w") do f
        f["artifact_kind"]="project_b_thread_benchmark_al_bridge"; f["schema_version"]=1
        f["source_sha256"]=source_sha; f["control_sha256"]=control_sha
        f["chi"]=s.maxlinkdim; f["theta_over_pi"]=s.theta_over_pi
        f["source_energy_density"]=s.observables.energy_density
        f["source_continuation_accepted"]=s.continuation_accepted
        f["source_parent_sha256"]=s.parent_state_sha256
        for (key,values) in (("source",[b.source_site for b in bonds]),("target",[b.target_site for b in bonds]),
            ("coupling",[b.family==:NN ? 1. : .12 for b in bonds]),("anisotropy",ones(length(bonds))),
            ("twist_charge",[PB.bond_twist_charge(b,PB.YCGeometry(8,1),:uniform) for b in bonds]))
            f["bonds/$key"]=values
        end
        for i in 1:2
            t=s.psi.AL[i]; l,p,r=indices(t); prefix="state/site_$i"
            f["$prefix/AL"]=Array(t,l,p,r)
            for (key,index) in (("left",l),("physical",p),("right",r)); f["$prefix/$(key)_charges"]=charges(index); end
        end
    end
    mv(tmp,path)
    (;source=s,bridge_sha256=C.sha(path))
end

function main(args)
    length(args)==3 || error("usage: export_seed.jl CONTROL SCRATCH COMPACT")
    control,scratch,compact=abspath.(args); c=C.validate(control;live=true); s=c["seed"]
    path=joinpath(scratch,"seed_al.h5")
    result=export_al(path,s["source_path"],s["source_sha256"],C.sha(control))
    original=result.source
    original.maxlinkdim==1024 && original.theta_over_pi==.15 && !original.continuation_accepted || error("benchmark seed classification")
    original.parent_state_sha256==C.PARENT_SHA || error("benchmark seed parent")
    abs(original.observables.energy_density-s["source_energy_density"])<1e-12 || error("seed energy metadata")
    C.write_toml(joinpath(compact,"export.toml"),Dict("artifact_kind"=>"project_b_thread_benchmark_export",
        "control_sha256"=>C.sha(control),"source_seed_sha256"=>s["source_sha256"],
        "bridge_path"=>path,"bridge_sha256"=>result.bridge_sha256,"chi"=>1024,"theta_over_pi"=>.15,
        "original_energy_density"=>original.observables.energy_density,"scientific_promotion"=>false))
    println("Exported rejected chi1024 AL tensors for timing only; original artifact preserved.")
end
end
