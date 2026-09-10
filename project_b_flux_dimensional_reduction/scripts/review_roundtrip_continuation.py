"""Review synced roundtrip evidence without loading or optimizing scratch tensors.

Uses the sealed Julia summary for schedule/provenance replay, then independently
checks scalar gates, spectrum identities, references and actual-CPU accounting.
Reuses the prior review's descriptive six-mode assignment (not mode tracking).
Requires Python 3.11+, numpy, h5py, matplotlib and Julia; no solver tests run.
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

from review_relaxation_continuation import (
    ROOT, require, sha, read_toml, wrap, continuity_failures, spectrum_comparison,
)

ARMS = ["n2_grid1", "n1_grid2", "n4_grid1", "n2_grid2"]
LABELS = ["2 / coarse", "1 / fine", "4 / coarse", "2 / fine"]
COLORS = ["#0072B2", "#56B4E9", "#D55E00", "#CC79A7"]


def audit_spectrum(s, theta, recipe):
    n = recipe["neigs"]
    for key in ("lambda_real", "lambda_imag", "inverse_xi", "transfer_phase", "two_k1", "k2"):
        require(len(s[key]) == n and np.all(np.isfinite(s[key])), f"invalid {key}")
    q = s["physical_sz"]
    require(s["raw_qn_sz"] == 2*q and q in recipe["physical_sz"], "charge convention")
    require(s["units"] == recipe["units"] and s["momentum_mapping"] == recipe["momentum_mapping"], "spectrum convention")
    z = np.array(s["lambda_real"]) + 1j*np.array(s["lambda_imag"])
    require(np.max(abs(-np.log(abs(z))-s["inverse_xi"])) < 1e-10, "inverse xi identity")
    require(np.max(abs(wrap(np.angle(z)-s["transfer_phase"]))) < 1e-10, "phase identity")
    require(np.max(abs(wrap(np.array(s["two_k1"])-np.angle(z)-2*q*np.pi*theta/8))) < 1e-10, "charge-aware 2k1")
    require(np.max(abs(wrap(np.array(s["k2"])-4*np.angle(z)))) < 1e-10, "k2 mapping")
    require(s["requested_modes_converged"] == (s["krylov_converged"] >= n), "convergence flag")
    require(len(s["krylov_residual_norms"]) >= n and np.all(np.isfinite(s["krylov_residual_norms"])), "Krylov records")


def compare(a, b):
    require(a["theta_over_pi"] == b["theta_over_pi"], "comparison at different flux")
    return {"first_arm": a["arm"], "second_arm": b["arm"], "theta_over_pi": a["theta_over_pi"],
            "first_direction": a["direction"], "second_direction": b["direction"],
            "first_updates": a["cumulative_updates"], "second_updates": b["cumulative_updates"],
            "abs_energy_difference": abs(a["energy_density"]-b["energy_density"]),
            "max_entropy_difference": float(max(abs(np.array(a["entropy"])-b["entropy"]))),
            "sz1": spectrum_comparison(a, b)}


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
        return subprocess.run([julia, "--startup-file=no", str(ROOT/"scripts"/script), *map(str, args)],
                              cwd=ROOT, check=True, capture_output=True, text=True).stdout

    c = read(run/"control.snapshot.toml"); r = c["recipe"]
    for item in c["inputs"]:
        require(sha(track(ROOT/item["path"])) == item["sha256"], f"sealed input {item['path']}")
    replay = command("summarize_roundtrip_continuation.jl", run)
    require(replay == track(run/"summary.txt").read_text(encoding="utf-8"), "remote summary differs from replay")
    require(replay.startswith("EXPERIMENT_COMPLETE=true\n"), "experiment incomplete")
    (out/"summary_replayed.txt").write_text(replay, encoding="utf-8")
    for p in run.glob("*.toml"):
        track(p)
    for p in run.glob("*.tsv"):
        track(p)
    samples = [read(p) for p in sorted(run.glob("analysis_*.toml"))]
    require(len(samples) == 100, "analysis count")
    with h5py.File(ROOT/c["parent_path"], "r") as f:
        parent = {k: f["observables/"+v][()].tolist() for k,v in
                  [("entropy", "von_neumann_entropies"), ("energy_terms", "energy_terms"), ("magnetization_z", "magnetization_z")]}
    for a in samples:
        require(max(a["canonical_errors"].values()) <= r["canonical_relation_tolerance"], "canonical errors")
        require(a["cross_library_energy_difference"] <= r["model_energy_tolerance"], "cross-library energy")
        require(abs(np.mean(a["energy_terms"])-a["energy_density"]) < 1e-12, "energy terms")
        for sector in a["spectra"].values():
            audit_spectrum(sector, a["theta_over_pi"], r["spectrum"])
        for key, d in a["comparisons"].items():
            require(not continuity_failures(d, r["continuity"]), f"continuity failure: {a['stage']} {key}")
            ref = a["reference_observables"][key]
            if key == "accepted_parent":
                actual = parent
            else:
                matches = [x for x in samples if x["arm"] == a["arm"] and
                           x["payload_sha256"] == a["reference_payload_sha256"][key]]
                require(len(matches) == 1, "reference lookup")
                actual = matches[0]
            for field in ("entropy", "energy_terms", "magnetization_z"):
                require(np.max(abs(np.array(ref[field])-actual[field])) < 1e-12, "reference scalar mismatch")
            if key != "accepted_parent":
                require(ref["energy_density"] == actual["energy_density"], "reference energy mismatch")

    origins = [a for a in samples if a["direction"] == "origin"]
    require(len(origins) == 4, "origin count")
    # Independently written HDF5 files need not share a byte hash. Compare the
    # measured starts, keeping each arm's own payload hash for reference checks.
    for a in origins[1:]:
        for key in ("native_error", "energy_density", "entropy", "energy_terms", "magnetization_z"):
            require(np.max(abs(np.asarray(a[key])-np.asarray(origins[0][key]))) < 1e-12, "independent origin mismatch")
        require(spectrum_comparison(origins[0],a)["max_matched_complex"] < 1e-10, "origin spectrum mismatch")
    endpoints = [a for a in samples if a["is_budget_endpoint"]]
    require(len(endpoints) == 48, "endpoint count")
    returns = []
    for a in endpoints:
        if a["direction"] == "return":
            ref = next(x for x in samples if x["arm"] == a["arm"] and x["payload_sha256"] == a["reference_payload_sha256"]["forward_same_flux"])
            returns.append({**compare(ref, a), "continuity": a["comparisons"]["forward_same_flux"]})
    pairs = []
    for a,b in itertools.combinations(endpoints, 2):
        if a["theta_over_pi"] != b["theta_over_pi"] or a["direction"] != b["direction"]:
            continue
        equal = a["updates_per_theta_over_pi"] == b["updates_per_theta_over_pi"]
        if equal or a["step_over_pi"] == b["step_over_pi"]:
            pairs.append({"equal_density": equal, **compare(a,b)})

    # Historical fixed-flux control: same accepted parent, kernel and inner accuracy;
    # no flux changes or per-point environment rebuilds, so it is not identical work.
    old = ROOT/"output/mpskit_solver_pilot_jobs/relaxation/20260908T200715Z_3e790f71089c"
    old_c = read(old/"control.snapshot.toml")
    require(old_c["recipe"]["parent_sha256"] == r["parent_sha256"], "baseline parent")
    for item in old_c["inputs"]:
        require(sha(track(ROOT/item["path"])) == item["sha256"], "historical input changed")
    baseline = [read(old/f"analysis_baseline_point1_iter{i}.toml") for i in (16,21,32)]
    for b in baseline:
        p = track(old/(b["stage"]+".toml"))
        require(b["point_manifest_sha256"] == sha(p) and b["control_sha256"] == sha(old/"control.snapshot.toml"), "baseline provenance")
        manifest = read_toml(p)
        cp = next(x for x in manifest["checkpoints"] if x["iteration"] == b["iteration"])
        require(cp["sha256"] == b["payload_sha256"], "baseline payload provenance")
    finals = []
    for arm in ARMS:
        origin = next(a for a in origins if a["arm"] == arm)
        turn = next(a for a in endpoints if a["arm"] == arm and a["theta_over_pi"] == .25)
        end = next(a for a in endpoints if a["arm"] == arm and a["theta_over_pi"] == .15)
        history = sorted([a for a in samples if a["arm"] == arm], key=lambda x:x["cumulative_updates"])
        m = [max(abs(np.array(a["magnetization_z"]))) for a in history]
        fixed = next(b for b in baseline if b["iteration"] == end["cumulative_updates"])
        return_data = next(x for x in returns if x["second_arm"] == arm and x["theta_over_pi"] == .15)
        finals.append({"arm": arm, "updates": end["cumulative_updates"], "turn_energy": turn["energy_density"],
                       "return_minus_origin_energy": end["energy_density"]-origin["energy_density"],
                       "return_overlap": return_data["continuity"]["overlap_per_site"],
                       "return_entropy_difference": return_data["max_entropy_difference"],
                       "return_inverse_xi_relative_difference": return_data["sz1"]["max_matched_inverse_xi_relative_difference"],
                       "turn_leading_inverse_xi": min(turn["spectra"]["sz1"]["inverse_xi"]),
                       "return_leading_inverse_xi": min(end["spectra"]["sz1"]["inverse_xi"]),
                       "turn_max_magnetization": max(abs(np.array(turn["magnetization_z"]))),
                       "return_max_magnetization": m[-1], "magnetization_growth_factor": m[-1]/m[0],
                       "magnetization_monotone_every_update": bool(np.all(np.diff(m)>0)),
                       "return_magnetization_over_fixed_flux": m[-1]/max(abs(np.array(fixed["magnetization_z"]))),
                       "return_native_error": end["native_error"], "return_payload_sha256": end["payload_sha256"],
                       "turn_payload_sha256": turn["payload_sha256"]})

    job = next(csv.DictReader(track(run/"job.tsv").read_text().splitlines(), delimiter="\t"))["job_id"]
    rec = max([read(p) for p in (ROOT/"output/accounting/reconciliations"/job).glob("*.toml")], key=lambda x:x["recorded_utc"])
    ep = track(ROOT/rec["evidence_path"])
    require(sha(ep) == rec["evidence_sha256"] and rec["job_id"] == job, "accounting provenance")
    rows = list(csv.DictReader([x for x in ep.read_text().splitlines() if x and not x.startswith("#")], delimiter="|"))
    def allocation(identifier):
        found = [x for x in rows if x["JobIDRaw"] == identifier]
        require(found and all(x == found[0] for x in found), "Slurm row ambiguity")
        row = found[0]
        require(row["State"] == "COMPLETED" and row["ExitCode"] == "0:0", "Slurm failure")
        return row
    alloc = allocation(job)
    cpus, seconds = int(alloc["NCPUS"]), int(alloc["ElapsedRaw"])
    require(cpus == r["resources"]["allocation_cpus"] and alloc["QOS"] == "shared", "resource mismatch")
    charge = seconds/3600*math.ceil(cpus/2)/128
    timing = []
    for i,arm in enumerate(ARMS):
        solver, analysis = allocation(f"{job}.{2*i}"), allocation(f"{job}.{2*i+1}")
        require(int(solver["NCPUS"]) == int(analysis["NCPUS"]) == r["resources"]["step_cpus"], "step CPUs")
        for prefix in ("", "analysis_"):
            require("Exit status: 0" in track(run/"metrics"/f"{prefix}{arm}.time").read_text(), "timed process failure")
        require(solver["MaxRSS"].endswith("K"), "RSS unit")
        timing.append({"arm": arm, "solver_seconds": int(solver["ElapsedRaw"]), "analysis_seconds": int(analysis["ElapsedRaw"]),
                       "solver_rss_gib": float(solver["MaxRSS"][:-1])/2**20})
    accounting = command("project_b_accounting.jl", "audit")
    ledger = [x.split("\t") for x in accounting.splitlines() if re.match(r"\d+\t", x)]
    require(len({x[0] for x in ledger}) == len(ledger), "duplicate ledger jobs")
    spent, remaining = map(float, re.search(r"Phase 1: ([\d.]+); remaining: ([\d.]+)", accounting).groups())
    require(abs(sum(int(x[3])/3600*math.ceil(int(x[4])/2)/128 for x in ledger if x[1]=="1")-spent) < 1e-10, "phase sum")
    require(abs(float(next(x for x in ledger if x[0]==job)[5])-charge) < 1e-10, "charge mismatch")
    result = track(run/"job.result").read_text()
    require("experiment_complete=true" in result and "pretimeout_requested=false" in result, "worker completion")
    track(run/f"logs/roundtrip-{job}.out"); track(__file__); track(ROOT/"scripts/review_relaxation_continuation.py")
    report = {"artifact_kind": "project_b_roundtrip_retrospective_review", "job_id": job,
              "authority": "owner-confirmed completed sync; retrospective only", "control_sha256": sha(run/"control.snapshot.toml"),
              "sealed_inputs": len(c["inputs"]), "updates": len(samples)-len(origins), "analyzed_states": len(samples),
              "native_gate_applicable_samples": sum(a["native_gate_applicable"] for a in samples),
              "native_gate_passes": sum(a["native_gate_passed"] for a in samples),
              "all_continuity_comparisons_pass": True,
              "all_transfer_modes_converged": all(s["requested_modes_converged"] for a in samples for s in a["spectra"].values()),
              "maximum_cross_library_energy_difference": max(a["cross_library_energy_difference"] for a in samples),
              "maximum_canonical_error": max(max(a["canonical_errors"].values()) for a in samples),
              "elapsed_seconds": seconds, "allocated_logical_cpus": cpus, "node_hours": charge,
              "phase1_spent": spent, "phase1_remaining": remaining,
              "project_spent": float(re.search(r"Project B: ([\d.]+)", accounting).group(1)),
              "timing": timing, "reconciliation": rec, "finals": finals, "samples": samples,
              "return_comparisons": returns, "grid_density_comparisons": pairs, "fixed_flux_baseline": baseline,
              "limitations": ["Scratch tensor hashes, overlaps and Schmidt spectra were measured remotely; no scratch tensors reloaded locally.",
                              "Six-mode assignment minimizes squared complex-eigenvalue distance; it is not eigenvector tracking or a cutoff-convergence study.",
                              "Fixed-flux baseline has no per-point environment resets; comparison does not isolate a unique cause of drift.",
                              "Continuity passes do not establish native convergence, adiabaticity or a physical spinodal.",
                              "Inverse xi is per period-2 transfer cell, not a Fig. 2 excitation gap."],
              "provenance_sha256": provenance}
    (out/"accounting_replayed.txt").write_text(accounting, encoding="utf-8")
    return report


def figures(report, out):
    plt.rcParams.update({"font.family":"DejaVu Sans", "font.size":10, "axes.spines.top":False,
                         "axes.spines.right":False, "axes.grid":True, "grid.alpha":.18})
    samples = report["samples"]
    fig, axes = plt.subplots(2,2,figsize=(11,8),layout="constrained")
    for arm,label,color in zip(ARMS,LABELS,COLORS):
        data = sorted([a for a in samples if a["arm"]==arm], key=lambda x:x["cumulative_updates"])
        origin = data[0]
        endpoints = [a for a in data if a["is_budget_endpoint"]]
        turn = next(a for a in endpoints if a["theta_over_pi"]==.25)
        for direction, style, marker in [("forward","-","o"),("return","--","s")]:
            path = ([origin] if direction=="forward" else [turn])+[a for a in endpoints if a["direction"]==direction]
            x = [a["theta_over_pi"] for a in path]
            for ax,y in [(axes[0,0],[np.mean(a["entropy"])-np.mean(origin["entropy"]) for a in path]),
                         (axes[0,1],[min(a["spectra"]["sz1"]["inverse_xi"]) for a in path])]:
                ax.plot(x,y,style,marker=marker,ms=3.5,color=color,lw=1.4,
                        markerfacecolor=color if direction=="forward" else "white")
        axes[1,0].semilogy([a["cumulative_updates"] for a in data],
                           [max(abs(np.array(a["magnetization_z"]))) for a in data],color=color,label=label,lw=1.8)
        axes[1,1].semilogy([a["cumulative_updates"] for a in data], [a["native_error"] for a in data],color=color,lw=1.4)
    baseline = report["fixed_flux_baseline"]
    for ax,key in [(axes[1,0],"magnetization_z"),(axes[1,1],"native_error")]:
        y = [max(abs(np.array(a[key]))) if key=="magnetization_z" else a[key] for a in baseline]
        ax.plot([a["iteration"] for a in baseline],y,"k:",marker="D",ms=4,label="Fixed flux 0.15 (prior run)")
    axes[1,1].axhline(1e-5,color=".45",ls="--",lw=1)
    axes[1,1].text(1,1.15e-5,"Historical error threshold",color=".4",fontsize=9)
    titles = ["a  Entropy nearly returns", "b  Correlations retain a visible offset",
              "c  Staggered magnetization keeps growing", "d  Native errors remain above threshold"]
    for ax,title in zip(axes.flat,titles): ax.set_title(title,loc="left",fontsize=11)
    axes[0,0].set_ylabel("Mean cut entropy − imported origin")
    axes[0,1].set_ylabel("Leading Sz = 1 inverse ξ / transfer cell")
    axes[1,0].set_ylabel("max |⟨Sz⟩| on the two sites")
    axes[1,1].set_ylabel("VUMPS Galerkin error")
    for ax in axes[0]: ax.set_xlabel("θ/π")
    for ax in axes[1]: ax.set_xlabel("Cumulative outer updates")
    axes[1,0].legend(fontsize=8,loc="lower right")
    fig.suptitle(f"YC8-1 flux return at χ512 — job {report['job_id']}",fontsize=15)
    fig.supxlabel("Labels: updates per point / grid. Coarse Δ(θ/π)=0.025; fine=0.0125.\nTop panels: solid outward, dashed return. Bottom panels: every iterate; dotted diamonds are historical fixed-flux samples.",fontsize=9)
    for ext in ("png","svg"): fig.savefig(out/f"roundtrip_paths.{ext}",dpi=180)
    plt.close(fig)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run",type=Path,required=True); p.add_argument("--out",type=Path,required=True)
    p.add_argument("--julia",required=True)
    args=p.parse_args(); out=args.out.resolve(); out.mkdir(parents=True,exist_ok=True)
    require(not (out/"review.json").exists(),"use a new output directory")
    report=review(args.run.resolve(),out,args.julia)
    figures(report,out)
    (out/"review.json").write_text(json.dumps(report,indent=2,allow_nan=False),encoding="utf-8")
    with (out/"finals.csv").open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=list(report["finals"][0]));w.writeheader();w.writerows(report["finals"])
    print(json.dumps({k:v for k,v in report.items() if k not in ("samples","return_comparisons","grid_density_comparisons","provenance_sha256","fixed_flux_baseline")},indent=2))


if __name__=="__main__":
    main()
