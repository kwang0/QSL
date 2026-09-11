"""Audit synced full-flux results and plot Fig. 3 comparisons; no solver runs.

Python 3.11+, numpy, h5py, matplotlib; Julia is used for the existing compact
replay and accounting. Preserve recorded momentum labels; do not identify
eigenvalue ranks with physical excitation branches.
"""
from __future__ import annotations
import argparse
import csv
import itertools
import json
import math
from pathlib import Path
import re
import subprocess

import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from review_relaxation_continuation import ROOT, require, sha, read_toml, continuity_failures, native_gate, spectrum_comparison
from review_roundtrip_continuation import audit_spectrum

ARMS = ["n2", "n4", "n8"]
COLORS = ["#0072B2", "#D55E00", "#009E73"]


def review(run, out, julia):
    provenance = {}
    def track(path):
        path = Path(path).resolve()
        require(path.is_relative_to(ROOT), "evidence outside project")
        provenance[path.relative_to(ROOT).as_posix()] = sha(path)
        return path
    def read(path):
        return read_toml(track(path))
    def command(script, *args):
        track(ROOT / "scripts" / script)
        return subprocess.run([julia, "--startup-file=no", str(ROOT/"scripts"/script), *map(str,args)],
                              cwd=ROOT, check=True, capture_output=True, text=True).stdout
    c = read(run/"control.snapshot.toml"); r = c["recipe"]
    for item in c["inputs"]:
        require(sha(track(ROOT/item["path"])) == item["sha256"], f"sealed input {item['path']}")
    replay = command("summarize_fullflux_continuation.jl", run)
    require(replay == track(run/"summary.txt").read_text(encoding="utf-8"), "remote summary differs from replay")
    require(replay.startswith("EXPERIMENT_COMPLETE=true\n"), "incomplete experiment")
    (out/"summary_replayed.txt").write_text(replay, encoding="utf-8")
    for p in itertools.chain(run.glob("*.toml"),run.glob("*.tsv")): track(p)
    samples = sorted([read(p) for p in run.glob("analysis_*.toml")],key=lambda a:(a["iteration_budget"] if a["point"] else int(a["arm"][1:]),a["point"]))
    require(len(samples)==30, "analysis count")
    with h5py.File(ROOT/c["parent_path"],"r") as f:
        parent = {k:f["observables/"+v][()].tolist() for k,v in
                  [("entropy","von_neumann_entropies"),("energy_terms","energy_terms"),("magnetization_z","magnetization_z")]}
    for a in samples:
        require(max(a["canonical_errors"].values())<=r["canonical_relation_tolerance"], "canonical errors")
        require(a["cross_library_energy_difference"]<=r["model_energy_tolerance"], "cross-library energy")
        require(abs(np.mean(a["energy_terms"])-a["energy_density"])<1e-12, "energy terms")
        for s in a["spectra"].values(): audit_spectrum(s,a["theta_over_pi"],r["spectrum"])
        a["continuity_failures"] = {}
        for key,d in a["comparisons"].items():
            a["continuity_failures"][key] = continuity_failures(d,r["continuity"])
            ref=a["reference_observables"][key]
            actual=parent if key=="accepted_parent" else next(x for x in samples if x["arm"]==a["arm"] and x["payload_sha256"]==a["reference_payload_sha256"][key])
            for field in ("entropy","energy_terms","magnetization_z"):
                require(np.max(abs(np.asarray(ref[field])-actual[field]))<1e-12, "reference observables")
    updates = 0
    for p in run.glob("n*_point[0-9].toml"):
        point=read(p); h=point["history"]; updates+=len(h)
        for i,cp in enumerate(point["checkpoints"]):
            require(cp["native_gate_passed"]==native_gate(h[:i+1],r), "native gate")
    require(updates==126, "update count")
    finals=[]
    for arm in ARMS:
        data=[a for a in samples if a["arm"]==arm]; origin=data[0]; end=data[-1]
        minimum=min(data,key=lambda a:min(a["spectra"]["sz1"]["inverse_xi"]))
        failures=lambda key:[a["theta_over_pi"] for a in data if a["continuity_failures"].get(key)]
        magnetized=[a["theta_over_pi"] for a in data if max(abs(np.asarray(a["magnetization_z"])))>=.01]
        finals.append(dict(arm=arm,updates=end["cumulative_updates"],energy=end["energy_density"],
            galerkin=end["native_error"],mean_entropy=float(np.mean(end["entropy"])),
            max_abs_sz=float(max(abs(np.asarray(end["magnetization_z"])))),
            inverse_xi_at_pi=min(end["spectra"]["sz1"]["inverse_xi"]),
            xi_at_pi=1/min(end["spectra"]["sz1"]["inverse_xi"]),
            minimum_inverse_xi=min(minimum["spectra"]["sz1"]["inverse_xi"]),minimum_theta=minimum["theta_over_pi"],
            final_inverse_xi_change_percent=100*(min(end["spectra"]["sz1"]["inverse_xi"])/min(origin["spectra"]["sz1"]["inverse_xi"])-1),
            first_parent_failure=min(failures("accepted_parent"),default=None),
            first_previous_failure=min(failures("previous_flux"),default=None),first_abs_sz_at_least_0p01=min(magnetized,default=None),
            stored_leading_two_k1_over_pi=end["spectra"]["sz1"]["two_k1"][0]/np.pi,
            stored_leading_k2_over_pi=(end["spectra"]["sz1"]["k2"][0]/np.pi)%2,
            final_payload_sha256=end["payload_sha256"]))
    pairs=[]
    for a,b in itertools.combinations(samples,2):
        if a["theta_over_pi"]!=b["theta_over_pi"]: continue
        pairs.append(dict(first_arm=a["arm"],second_arm=b["arm"],theta_over_pi=a["theta_over_pi"],
            energy_difference=abs(a["energy_density"]-b["energy_density"]),
            max_entropy_difference=float(max(abs(np.asarray(a["entropy"])-b["entropy"]))),
            leading_inverse_xi_relative_difference=abs(min(a["spectra"]["sz1"]["inverse_xi"])-min(b["spectra"]["sz1"]["inverse_xi"]))/min(a["spectra"]["sz1"]["inverse_xi"]),
            sz1=spectrum_comparison(a,b)))
    job=track(run/"job.tsv").read_text().splitlines()[1].split("\t")[0]
    records=[read(p) for p in (ROOT/"output/accounting/reconciliations"/job).glob("*.toml")]
    rec=max(records,key=lambda x:x["recorded_utc"]); evidence=track(ROOT/rec["evidence_path"])
    require(sha(evidence)==rec["evidence_sha256"], "accounting evidence hash")
    rows=list(csv.DictReader(evidence.read_text().splitlines(),delimiter="|"))
    def allocation(identifier):
        found=[x for x in rows if x.get("JobIDRaw")==identifier]
        require(found and all(x==found[0] for x in found), "Slurm row ambiguity")
        row=found[0]
        require(row["State"]=="COMPLETED" and row["ExitCode"]=="0:0", "Slurm failure")
        return row
    alloc=allocation(job); cpus=int(alloc["NCPUS"]); seconds=int(alloc["ElapsedRaw"])
    require(cpus==10 and alloc["QOS"]=="shared", "allocation resources")
    charge=seconds/3600*math.ceil(cpus/2)/128
    timing=[]
    for i,arm in enumerate(ARMS):
        solver,analysis=allocation(f"{job}.{2*i}"),allocation(f"{job}.{2*i+1}")
        require(int(solver["NCPUS"])==int(analysis["NCPUS"])==4, "step CPUs")
        for prefix in ("","analysis_"):
            require("Exit status: 0" in track(run/"metrics"/f"{prefix}{arm}.time").read_text(), "timed step failure")
        timing.append(dict(arm=arm,solver_seconds=int(solver["ElapsedRaw"]),analysis_seconds=int(analysis["ElapsedRaw"]),solver_rss_gib=float(solver["MaxRSS"][:-1])/2**20))
    accounting=command("project_b_accounting.jl","audit")
    (out/"accounting_replayed.txt").write_text(accounting,encoding="utf-8")
    ledger=[x.split("\t") for x in accounting.splitlines() if re.match(r"\d+\t",x)]
    spent,remaining=map(float,re.search(r"Phase 1: ([\d.]+); remaining: ([\d.]+)",accounting).groups())
    require(len({x[0] for x in ledger})==len(ledger), "duplicate ledger")
    require(abs(sum(int(x[3])/3600*math.ceil(int(x[4])/2)/128 for x in ledger if x[1]=="1")-spent)<1e-10, "phase sum")
    require(abs(float(next(x for x in ledger if x[0]==job)[5])-charge)<1e-10, "charge mismatch")
    result=track(run/"job.result").read_text()
    require(all(x in result for x in ("experiment_complete=true","pretimeout_requested=false","step_failure=0")), "worker outcome")
    track(run/f"logs/fullflux-{job}.out")
    for p in (__file__,ROOT/"scripts/review_roundtrip_continuation.py",ROOT/"scripts/review_relaxation_continuation.py"):track(p)
    return dict(artifact_kind="project_b_fullflux_retrospective_review",job_id=job,
        authority="owner-confirmed completed sync; retrospective only",control_sha256=sha(run/"control.snapshot.toml"),
        sealed_inputs=len(c["inputs"]),updates=updates,analyzed_states=len(samples),
        native_gate_passes=sum(a["native_gate_passed"] for a in samples),
        all_transfer_modes_converged=all(s["requested_modes_converged"] for a in samples for s in a["spectra"].values()),
        maximum_canonical_error=max(max(a["canonical_errors"].values()) for a in samples),
        maximum_cross_library_energy_difference=max(a["cross_library_energy_difference"] for a in samples),
        elapsed_seconds=seconds,node_hours=charge,phase1_spent=spent,phase1_remaining=remaining,
        project_spent=float(re.search(r"Project B: ([\d.]+)",accounting).group(1)),timing=timing,
        reconciliation=rec,finals=finals,samples=samples,pairs=pairs,
        limitations=["No scratch tensors reloaded locally; canonical, energy, overlap and Schmidt checks were performed remotely.",
            "Only six leading modes per spin sector; eigenvalue matching is descriptive, not eigenvector branch tracking.",
            "Positive flux 0.15..1 only; no mirrored or interpolated states are invented.",
            "Stored Eq.4 labels retain the launched convention. Hamiltonian exchange phase has the opposite sign to Fig.S2; absolute momenta require a convention audit.",
            "No native convergence or scientific promotion; not a physical spinodal determination."],
        provenance_sha256=provenance)


def figures(report,out):
    plt.rcParams.update({"font.family":"DejaVu Sans","font.size":10,"axes.spines.top":False,
        "axes.spines.right":False,"axes.grid":True,"grid.alpha":.16})
    fig,axes=plt.subplots(2,2,figsize=(10.5,7.5),layout="constrained")
    for arm,color in zip(ARMS,COLORS):
        data=[a for a in report["samples"] if a["arm"]==arm]; x=[a["theta_over_pi"] for a in data]
        y=[[min(a["spectra"]["sz1"]["inverse_xi"]) for a in data],
           [max(abs(np.asarray(a["magnetization_z"]))) for a in data],
           [a["native_error"] for a in data],[a["energy_terms"][0]-a["energy_terms"][1] for a in data]]
        for ax,values in zip(axes.flat,y): ax.plot(x,values,"o-",color=color,ms=4,label=f"{arm[1:]} updates / point")
    axes[0,1].set_yscale("log");axes[1,0].set_yscale("log")
    axes[1,0].axhline(1e-5,ls="--",color=".5",lw=1,label="Historical threshold")
    axes[1,1].axhline(0,ls="--",color=".5",lw=1)
    titles=["a  Softening reverses before the endpoint","b  More updates accelerate magnetic drift",
            "c  No endpoint reaches native convergence","d  Local-energy alternation changes sign"]
    labels=[r"Leading $S^z=1$ inverse $\xi$ / transfer cell",r"max $|\langle S^z\rangle|$", "VUMPS Galerkin error",r"Local energy difference $e_1-e_2$"]
    for ax,title,label in zip(axes.flat,titles,labels):
        ax.set_title(title,loc="left",fontsize=11);ax.set_ylabel(label);ax.set_xlabel(r"$\theta/\pi$");ax.set_xlim(.12,1.03)
    axes[0,0].legend(fontsize=9);axes[1,0].legend(fontsize=8,loc="lower right")
    fig.suptitle(f"YC8-1 at chi512: full-flux finite-relaxation scans | job {report['job_id']}",fontsize=14)
    for ext in ("png","svg"):fig.savefig(out/f"fullflux_diagnostics.{ext}",dpi=180)
    plt.close(fig)

    fig,axes=plt.subplots(3,3,figsize=(12,10),layout="constrained",sharey=True)
    for row,arm in enumerate(ARMS):
        data=[a for a in report["samples"] if a["arm"]==arm]
        for a in data:
            s=a["spectra"]["sz1"]; t=a["theta_over_pi"]; y=s["inverse_xi"]
            x=[np.full(len(y),t),np.asarray(s["two_k1"])/np.pi,np.mod(np.asarray(s["k2"])/np.pi,2)]
            for ax,xx in zip(axes[row],x):
                artist=ax.scatter(xx,y,c=np.full(len(y),t),cmap="viridis",vmin=.15,vmax=1,s=21,linewidths=.3,edgecolors=".15")
                if t==1:ax.scatter(xx,y,marker="*",s=85,facecolors="none",edgecolors="#D55E00",linewidths=1)
        for x in [-2/3,0,2/3]:axes[row,1].axvline(x,color=".6",ls=":" if x else "--",lw=.8)
        for x in [2/3,1,4/3]:axes[row,2].axvline(x,color=".6",ls="--" if x==1 else ":",lw=.8)
        axes[row,0].set_ylabel(f"{arm[1:]} updates / point\n"+r"$1/\xi_{S^z=1}$ / transfer cell")
        for ax in axes[row]:ax.set_ylim(0,.6)
        axes[row,0].set_xlim(.1,1.04);axes[row,1].set_xlim(-1.05,1.05);axes[row,2].set_xlim(-.05,2.05)
    for ax,title in zip(axes[0],["Flux dependence","Stored longitudinal momentum","Stored transverse momentum"]):ax.set_title(title)
    for ax,label in zip(axes[-1],[r"$\theta/\pi$",r"$2k_1/\pi$ (stored Eq. 4 labels)",r"$k_2/\pi$ (modulo 2)"]):ax.set_xlabel(label)
    fig.colorbar(artist,ax=axes.ravel().tolist(),label=r"Measured $\theta/\pi$",shrink=.6,pad=.015)
    fig.suptitle("Fig. 3 comparison: six measured charged modes per point",fontsize=15)
    fig.supxlabel("Outlined stars: theta = pi. Dashed guides: M; dotted guides: K projections.\nStored labels are shown without correction; exchange-phase sign must be reconciled before absolute momentum identification.\nOnly measured positive-flux points are shown. No connecting lines imply branch tracking.",fontsize=9)
    for ext in ("png","svg"):fig.savefig(out/f"fullflux_spectra.{ext}",dpi=180)
    plt.close(fig)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run",type=Path,required=True);p.add_argument("--out",type=Path,required=True);p.add_argument("--julia",required=True)
    args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    require(not (out/"review.json").exists(),"use a new output directory")
    report=review(args.run.resolve(),out,args.julia);figures(report,out)
    (out/"review.json").write_text(json.dumps(report,indent=2,allow_nan=False),encoding="utf-8")
    for filename,rows in [("finals.csv",report["finals"])]:
        with (out/filename).open("w",newline="",encoding="utf-8") as f:
            w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    print(json.dumps({k:v for k,v in report.items() if k not in ("samples","pairs","provenance_sha256")},indent=2))

if __name__=="__main__":main()
