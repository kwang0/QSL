"""Audit compact bounded-relaxation evidence and export scientific comparisons.

No scratch tensors are required or rehashed here. The audit checks the sealed
inputs, complete iteration/seed chain, independent scalar gates, selected-state
provenance, transfer eigenvalue identities and reconciled actual-CPU accounting.
Six-mode matching minimizes total squared complex-eigenvalue distance over all
permutations; it is descriptive, not a physical mode identity or acceptance gate.
Use a new output directory. Requires Python 3.11+, numpy, h5py, matplotlib, Julia.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import itertools
import json
import math
from pathlib import Path
import re
import subprocess
import tomllib

import h5py
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
COLORS = {8: "#0072B2", 16: "#D55E00", 32: "#009E73"}


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    with Path(path).open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def read_toml(path):
    with Path(path).open("rb") as f:
        return tomllib.load(f)


def wrap(x):
    return (np.asarray(x) + np.pi) % (2 * np.pi) - np.pi


def native_gate(rows, recipe):
    if len(rows) < max(recipe["minimum_iterations"], recipe["energy_window"]):
        return False
    tail = [r["energy_density"] for r in rows[-recipe["energy_window"]:]]
    return (rows[-1]["native_error"] <= recipe["vumps_galerkin_tolerance"] and
            max(tail) - min(tail) <= recipe["energy_span_tolerance"])


def selection(rows, n, recipe):
    errors = [r["native_error"] for r in rows]
    endpoint = min(n, len(rows))
    chosen = {endpoint, int(np.argmin(errors[:endpoint])) + 1}
    if len(rows) > n:
        chosen.update([len(rows), int(np.argmin(errors)) + 1])
    best, count, turn = math.inf, 0, 0
    for i, e in enumerate(errors, 1):
        if e < best:
            best, count = e, 0
        elif e > best * (1 + recipe["turnaround_relative_rise"]):
            count += 1
        else:
            count = 0
        if count >= recipe["turnaround_patience"]:
            turn = i
            chosen.add(i)
            break
    return sorted(chosen), turn


def continuity_failures(d, policy):
    failures = []
    for key, limit in [("maximum_cut_entropy_jump", "maximum_cut_entropy_jump"),
                       ("energy_term_rms_jump", "maximum_energy_term_rms_jump"),
                       ("magnetization_rms_jump", "maximum_magnetization_rms_jump"),
                       ("mean_schmidt_total_variation", "maximum_mean_schmidt_total_variation"),
                       ("maximum_log_correlation_length_jump", "maximum_log_correlation_length_jump")]:
        require(math.isfinite(d[key]) and d[key] >= 0, f"invalid continuity scalar: {key}")
        if d[key] > policy[limit]:
            failures.append(key)
    if not d["u1_sector_diagnostics_passed"]:
        failures.append("U1")
    if not d["correlation_length_diagnostics_passed"]:
        failures.append("correlation_diagnostics")
    require(d["multimetric_passed"] == (not failures), "multimetric gate disagrees")
    require(math.isfinite(d["overlap_per_site"]), "nonfinite overlap")
    require(d["overlap_floor_passed"] == (d["overlap_per_site"] >= policy["minimum_overlap_per_site"]), "overlap gate disagrees")
    if not d["overlap_floor_passed"]:
        failures.append("overlap")
    actual = max(abs(np.log(np.array(d["candidate_correlation_lengths"]) /
                            np.array(d["reference_correlation_lengths"]))))
    require(abs(actual - d["maximum_log_correlation_length_jump"]) < 1e-12, "xi ratio disagrees")
    return failures


def audit_spectrum(s, theta, recipe):
    count = recipe["neigs"]
    for key in ("lambda_real", "lambda_imag", "inverse_xi", "transfer_phase", "two_k1", "k2"):
        require(len(s[key]) == count and np.all(np.isfinite(s[key])), f"invalid spectrum: {key}")
    require(s["raw_qn_sz"] == 2 * s["physical_sz"], "charge units disagree")
    require(s["units"] == recipe["units"], "transfer-cell units disagree")
    z = np.array(s["lambda_real"]) + 1j * np.array(s["lambda_imag"])
    require(np.max(abs(-np.log(abs(z)) - s["inverse_xi"])) < 1e-10, "inverse xi disagrees")
    require(np.max(abs(wrap(np.angle(z) - s["transfer_phase"]))) < 1e-10, "transfer phase disagrees")
    # Verify what v1 wrote. Only Sz=1's mapped momenta are interpreted below:
    # v1 applies this charged-sector shift to Sz=0 too; see review limitation.
    require(np.max(abs(wrap(np.array(s["two_k1"]) - np.angle(z) - 2*np.pi*theta/8))) < 1e-10, "mapped 2k1 disagrees")
    require(np.max(abs(wrap(np.array(s["k2"]) - 4*np.angle(z)))) < 1e-10, "mapped k2 disagrees")
    require(s["requested_modes_converged"] == (s["krylov_converged"] >= count), "mode convergence flag disagrees")
    require(len(s["krylov_residual_norms"]) >= count and np.all(np.isfinite(s["krylov_residual_norms"])), "missing Krylov residuals")


def spectrum_comparison(a, b, sector="sz1"):
    x, y = a["spectra"][sector], b["spectra"][sector]
    z = np.array(x["lambda_real"]) + 1j*np.array(x["lambda_imag"])
    w = np.array(y["lambda_real"]) + 1j*np.array(y["lambda_imag"])
    distances = abs(z[:, None] - w[None, :])
    permutation = min(itertools.permutations(range(len(w))),
                      key=lambda p: sum(distances[i, j]**2 for i, j in enumerate(p)))
    ix, iy = np.array(x["inverse_xi"]), np.array(y["inverse_xi"])[list(permutation)]
    phase = wrap(np.array(x["transfer_phase"]) - np.array(y["transfer_phase"])[list(permutation)])
    return {"hausdorff_complex": float(max(distances.min(axis=0).max(), distances.min(axis=1).max())),
            "assignment": list(permutation),
            "max_matched_complex": float(max(distances[i, j] for i, j in enumerate(permutation))),
            "max_matched_inverse_xi_difference": float(max(abs(ix-iy))),
            "max_matched_inverse_xi_relative_difference": float(max(abs(ix-iy)/np.maximum(abs(ix), 1e-12))),
            "max_matched_transfer_phase_difference": float(max(abs(phase))),
            "all_requested_modes_converged": x["requested_modes_converged"] and y["requested_modes_converged"]}


def comparison(a, b):
    return {"first": f"{a['stage']}_iter{a['iteration']}", "second": f"{b['stage']}_iter{b['iteration']}",
            "theta_over_pi": a["theta_over_pi"],
            "abs_energy_difference": abs(a["energy_density"]-b["energy_density"]),
            "max_entropy_difference": float(max(abs(np.array(a["entropy"])-b["entropy"]))),
            "sz1": spectrum_comparison(a, b), "sz0": spectrum_comparison(a, b, "sz0")}


def audit(run, julia):
    provenance = {}

    def track(path):
        path = Path(path).resolve()
        require(path.is_relative_to(ROOT), "evidence outside project")
        provenance[path.relative_to(ROOT).as_posix()] = sha(path)
        return path

    def read(path):
        return read_toml(track(path))

    control_path = track(run / "control.snapshot.toml")
    c = read(control_path)
    chash, recipe = sha(control_path), c["recipe"]
    require(c["artifact_kind"] == "project_b_relaxation_continuation_control" and c["schema_version"] == 1, "control schema")
    require(track(run / "control.sha256").read_text().strip() == chash, "control hash mismatch")
    require(recipe == read(ROOT / "configs/relaxation_continuation.toml"), "recipe mismatch")
    for item in c["inputs"]:
        require(sha(track(ROOT / item["path"])) == item["sha256"], f"sealed input mismatch: {item['path']}")
    with track(run / "job.tsv").open() as f:
        jobs = list(csv.DictReader(f, delimiter="\t"))
    require(len(jobs) == 1 and jobs[0]["control_sha256"] == chash, "job control mismatch")
    job = jobs[0]["job_id"]
    recs = [read(p) for p in (ROOT / "output/accounting/reconciliations" / job).glob("*.toml")]
    require(bool(recs), "missing live reconciliation")
    rec = max(recs, key=lambda x: x["recorded_utc"])
    require(rec["artifact_kind"] == "project_b_live_reconciliation" and rec["job_id"] == job, "reconciliation provenance")
    ep = track(ROOT / rec["evidence_path"])
    require(sha(ep) == rec["evidence_sha256"], "accounting evidence hash mismatch")
    records = list(csv.DictReader([s for s in ep.read_text().splitlines() if s and not s.startswith("#")], delimiter="|"))

    def allocation(identifier):
        found = [r for r in records if r["JobIDRaw"] == identifier]
        require(found and all(x == found[0] for x in found), f"ambiguous/missing Slurm row {identifier}")
        require(found[0]["State"] == "COMPLETED" and found[0]["ExitCode"] == "0:0", f"incomplete Slurm row {identifier}")
        return found[0]

    alloc = allocation(job)
    require(alloc["QOS"] == "shared", "unexpected QOS")
    cpus, seconds = int(alloc["NCPUS"]), int(alloc["ElapsedRaw"])
    charge = seconds/3600 * math.ceil(cpus/2)/128
    command = [julia, "--startup-file=no", str(ROOT / "scripts/project_b_accounting.jl")]
    accounting = subprocess.run(command + ["audit"], cwd=ROOT, text=True, capture_output=True, check=True).stdout
    subprocess.run(command + ["guard", "0"], cwd=ROOT, text=True, capture_output=True, check=True)
    ledger = [s.split("\t") for s in accounting.splitlines() if re.match(r"\d+\t", s)]
    require(len({r[0] for r in ledger}) == len(ledger), "duplicate accounting jobs")
    phase1, remaining = map(float, re.search(r"Phase 1: ([\d.]+); remaining: ([\d.]+)", accounting).groups())
    require(abs(sum(int(r[3])/3600*math.ceil(int(r[4])/2)/128 for r in ledger if r[1] == "1")-phase1) < 1e-10, "independent accounting disagrees")
    charged = [r for r in ledger if r[0] == job]
    require(len(charged) == 1 and abs(float(charged[0][5])-charge) < 1e-10, "run charge mismatch")

    with h5py.File(ROOT / c["parent_path"], "r") as f:
        parent = {k: f["observables/"+v][()].tolist() for k, v in
                  [("entropy", "von_neumann_entropies"), ("energy_terms", "energy_terms"), ("magnetization_z", "magnetization_z")]}
    specs = [("baseline", recipe["baseline_iterations"], [0.15], 0.0, 0)]
    for n in recipe["iteration_budgets"]:
        for grid, step in enumerate(recipe["steps_over_pi"], 1):
            fluxes = [round(0.15+k*step, 10) for k in range(1, round(0.05/step)+1)]
            specs.append((f"n{n}_grid{grid}", n, fluxes, step, recipe["hold_iterations"]))
    points, samples, origins, timing = [], [], [], []
    for index, (name, n, fluxes, step, hold) in enumerate(specs):
        origin = read(run / f"{name}_origin.toml")
        require(origin["control_sha256"] == chash and origin["parent_sha256"] == recipe["parent_sha256"], "origin provenance")
        origins.append(origin)
        previous = origin["payload"]
        outcome = read(run / f"{name}_outcome.toml")
        require(outcome["control_sha256"] == chash and not outcome["continuation_accepted"] and outcome["budget_complete"], "arm outcome incomplete/provenance")
        require(outcome["points"] == [f"{name}_point{j}" for j in range(1, len(fluxes)+1)], "arm point schedule mismatch")
        for j, theta in enumerate(fluxes, 1):
            stage = f"{name}_point{j}"
            path = run / f"{stage}.toml"
            p = read(path)
            for key, value in {"control_sha256": chash, "parent_sha256": recipe["parent_sha256"], "arm": name,
                               "theta_over_pi": theta, "iteration_budget": n, "step_over_pi": step,
                               "hold_iterations": hold if j == len(fluxes) else 0,
                               "budget_complete": True, "continuation_accepted": False,
                               "stop_reason": "fixed_budget_complete"}.items():
                require(p[key] == value, f"point {stage} {key} mismatch")
            require(all(p["diagnostic_seed"][k] == previous[k] for k in ("path", "sha256", "theta_over_pi")), "seed chain mismatch")
            require(all(p["origin"][k] == origin["payload"][k] for k in ("path", "sha256")), "origin changed")
            rows = p["history"]
            require(len(rows) == n+p["hold_iterations"] == len(p["checkpoints"]), "incomplete history")
            with track(run / f"{stage}_history.tsv").open() as f:
                journal = list(csv.DictReader(f, delimiter="\t"))
            require(len(journal) == len(rows), "journal length mismatch")
            for i, (r, cp, jr) in enumerate(zip(rows, p["checkpoints"], journal), 1):
                require(r["iteration"] == cp["iteration"] == i and r["chi"] == recipe["chi"], "iteration/chi mismatch")
                require(all(math.isfinite(v) and float(jr[k]) == v for k, v in r.items()), "nonfinite/journal mismatch")
                require(cp["theta_over_pi"] == theta and jr["payload_sha256"] == cp["sha256"], "checkpoint hash/theta mismatch")
                require(cp["native_gate_passed"] == native_gate(rows[:i], recipe), "native gate disagrees")
                checkpoint = read(run / f"{stage}_iter{i}.toml")
                require(checkpoint["record"] == r and all(checkpoint[k] == v for k, v in cp.items()), "checkpoint journal mismatch")
                require(checkpoint["control_sha256"] == chash and checkpoint["parent_sha256"] == recipe["parent_sha256"] and
                        not checkpoint["continuation_accepted"] and checkpoint["diagnostic_seed"] == p["diagnostic_seed"], "checkpoint lineage mismatch")
            chosen, turn = selection(rows, n, recipe)
            require(chosen == p["selected_iterations"] and turn == p["turnaround_iteration"], "sample selection mismatch")
            for i in chosen:
                a = read(run / f"analysis_{stage}_iter{i}.toml")
                require(a["point_manifest_sha256"] == sha(path) and a["payload_sha256"] == p["checkpoints"][i-1]["sha256"], "analysis hash chain mismatch")
                for key in ("control_sha256", "parent_sha256", "arm", "stage", "iteration_budget", "theta_over_pi", "step_over_pi", "continuation_accepted"):
                    require(a[key] == p[key], f"analysis {key} mismatch")
                require(a["iteration"] == i and a["native_error"] == rows[i-1]["native_error"] and
                        a["native_gate_passed"] == native_gate(rows[:i], recipe), "analysis native history mismatch")
                require(a["is_budget_endpoint"] == (i == n) and a["is_hold_endpoint"] == (hold > 0 and j == len(fluxes) and i == n+hold), "endpoint flags disagree")
                e = abs(a["energy_density"]-rows[i-1]["energy_density"])
                require(abs(e-a["cross_library_energy_difference"]) < 1e-14 and e <= recipe["model_energy_tolerance"], "cross-library energy mismatch")
                require(all(math.isfinite(v) and 0 <= v <= recipe["canonical_relation_tolerance"] for v in a["canonical_errors"].values()), "canonical check failed")
                require(abs(np.mean(a["energy_terms"])-a["energy_density"]) < 1e-12, "energy density normalization mismatch")
                a["review_failures"] = {key: continuity_failures(d, recipe["continuity"]) for key, d in a["comparisons"].items()}
                for s in a["spectra"].values():
                    audit_spectrum(s, theta, recipe["spectrum"])
                a["cumulative_updates"] = (j-1)*n+i
                samples.append(a)
            points.append(p)
            previous = p["checkpoints"][n-1]
        solver, analysis = allocation(f"{job}.{2*index}"), allocation(f"{job}.{2*index+1}")
        require(int(solver["NCPUS"]) == int(analysis["NCPUS"]) == recipe["resources"]["step_cpus"], "step allocation mismatch")
        for prefix in ("", "analysis_"):
            metrics = track(run / "metrics" / f"{prefix}{name}.time").read_text()
            require("Exit status: 0" in metrics, "timed process failed")
        require(solver["MaxRSS"].endswith("K"), "unknown RSS unit")
        timing.append({"arm": name, "solver_seconds": int(solver["ElapsedRaw"]), "analysis_seconds": int(analysis["ElapsedRaw"]),
                       "solver_rss_gib": float(solver["MaxRSS"][:-1])/2**20})

    # Independent starts must reproduce the same first-flux trajectory before
    # their predeclared budgets diverge. Timing and payload hashes include I/O
    # metadata and are deliberately not equality targets.
    prefix_checks = []
    for a, b in itertools.combinations([p for p in points if p["point"] == 1 and p["arm"] != "baseline"], 2):
        if a["theta_over_pi"] == b["theta_over_pi"]:
            count = min(len(a["history"]), len(b["history"]))
            error = max(abs(x[k]-y[k]) for x, y in zip(a["history"], b["history"])
                        for k in ("native_error", "energy_density"))
            require(error < 1e-12, "independent first-flux prefixes disagree")
            prefix_checks.append({"first": a["arm"], "second": b["arm"], "updates": count, "max_scalar_difference": error})

    lookup = {(a["stage"], a["iteration"]): a for a in samples}
    for a in samples:
        p = next(p for p in points if p["stage"] == a["stage"])
        references = {"accepted_parent": parent}
        if p["point"] > 1:
            references["previous_flux"] = lookup[(f"{a['arm']}_point{p['point']-1}", a["iteration_budget"])]
        if "before_hold" in a["comparisons"]:
            references["before_hold"] = lookup[(a["stage"], a["iteration_budget"])]
        for kind, reference in references.items():
            d = a["comparisons"][kind]
            for key, field, method in [("maximum_cut_entropy_jump", "entropy", "max"),
                                       ("energy_term_rms_jump", "energy_terms", "rms"),
                                       ("magnetization_rms_jump", "magnetization_z", "rms")]:
                diff = np.array(a[field])-reference[field]
                actual = max(abs(diff)) if method == "max" else np.sqrt(np.mean(diff**2))
                require(abs(actual-d[key]) < 1e-12, f"independent {kind} {key} mismatch")
    endpoints = [a for a in samples if a["is_budget_endpoint"] and a["arm"] != "baseline"]
    pairs = []
    for a, b in itertools.combinations(endpoints, 2):
        if a["theta_over_pi"] != b["theta_over_pi"]:
            continue
        same_n = a["iteration_budget"] == b["iteration_budget"]
        doubled = a["step_over_pi"] == b["step_over_pi"] and b["iteration_budget"] == 2*a["iteration_budget"]
        equal_work = a["cumulative_updates"] == b["cumulative_updates"]
        if same_n or doubled or equal_work:
            pairs.append({"fixed_N_step_refinement": same_n, "fixed_step_N_doubling": doubled,
                          "equal_total_updates": equal_work, **comparison(a, b)})
    holds = []
    for b in samples:
        if b["is_hold_endpoint"]:
            a = lookup[(b["stage"], b["iteration_budget"])]
            holds.append({"arm": b["arm"], **comparison(a, b), "continuity_vs_unheld": b["comparisons"]["before_hold"],
                          "failures_vs_unheld": b["review_failures"]["before_hold"]})
    track(run / f"logs/relaxation-{job}.out")
    result = track(run / "job.result").read_text()
    require("pretimeout_requested=false" in result, "pretimeout requested")
    track(__file__)
    report = {"artifact_kind": "project_b_relaxation_retrospective_review", "job_id": job, "control_sha256": chash,
              "authority": "owner-confirmed completed sync; retrospective only", "reconciliation": rec,
              "sealed_inputs": len(c["inputs"]), "points": len(points), "updates": sum(len(p["history"]) for p in points),
              "analyzed_states": len(samples), "allocated_logical_cpus": cpus, "elapsed_seconds": seconds,
              "node_hours": charge, "phase1_spent": phase1, "phase1_remaining": remaining,
              "project_spent": float(re.search(r"Project B: ([\d.]+)", accounting).group(1)),
              "unique_accounted_jobs": len(ledger), "timing": timing, "worker_result": result,
              "native_gate_passes": sum(a["native_gate_passed"] for a in samples),
              "all_requested_transfer_modes_converged": all(s["requested_modes_converged"] for a in samples for s in a["spectra"].values()),
              "independent_prefix_checks": prefix_checks,
              "origins": origins, "samples": samples, "endpoint_comparisons": pairs, "hold_comparisons": holds,
              "limitations": ["Scratch tensors were hash-checked during remote analysis, not rehashed locally.",
                              "First-point imported-origin scalar observables are not in the compact output; those comparisons cannot be independently recomputed here.",
                              "Native and continuity gates are distinct; fixed-budget states remain diagnostics.",
                              "Six-mode set comparisons can be affected by modes crossing the retained cutoff; assignments are not eigenvector tracking.",
                              "v1 writes the charged-sector momentum shift for both spin sectors. Only Sz=1 mapped momenta are interpreted; Sz=0 eigenvalues and inverse xi remain usable.",
                              "Fixed N with a finer grid increases total relaxation; equal-work comparisons are reported separately.",
                              "These are VUMPS updates, not iDMRG sweeps, and transfer inverse xi is not an excitation energy."],
              "provenance_sha256": provenance}
    return report, points, accounting


def figures(report, points, out):
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.spines.top": False,
                         "axes.spines.right": False, "axes.grid": True, "grid.alpha": .18})
    samples = report["samples"]
    fig, axes = plt.subplots(2, 3, figsize=(13, 7.5), layout="constrained")
    for row, grid in enumerate((1, 2)):
        for col, n in enumerate((8, 16, 32)):
            ax = axes[row, col]
            arm = f"n{n}_grid{grid}"
            for p in (p for p in points if p["arm"] == arm):
                start = (p["point"]-1)*n
                ax.semilogy([start+r["iteration"] for r in p["history"]], [r["native_error"] for r in p["history"]], color=COLORS[n], lw=1.5)
                ax.axvline(start, lw=.7, color=".6", ls=":")
                ax.text(start+1, 1.8e-2, f"{p['theta_over_pi']:g}", fontsize=8, color=".35")
            selected = [a for a in samples if a["arm"] == arm]
            for a in selected:
                ax.scatter(a["cumulative_updates"], a["native_error"], s=32,
                           marker="o" if not a["review_failures"]["accepted_parent"] else "x", color="black", zorder=3)
            final_n = (2 if grid == 1 else 4)*n
            ax.axvspan(final_n, final_n+16, color=".90", zorder=0)
            ax.axhline(1e-5, color=".5", ls="--", lw=.8)
            ax.set_ylim(7e-6, .03)
            ax.set_title(f"N = {n}, Δθ/π = {0.025 if grid == 1 else 0.0125:g}", loc="left")
            ax.set_xlabel("Cumulative VUMPS updates in this arm")
            if col == 0:
                ax.set_ylabel("Galerkin error")
    fig.suptitle(f"Short relaxation postpones the large state change — job {report['job_id']}", fontsize=15)
    fig.supxlabel("Numbers above curves: θ/π   •: sampled continuity pass   ×: sampled failure   Shading: fixed-flux hold\nχ = 512; all states unconverged diagnostics. Dashed line: historical native-error threshold.", fontsize=10)
    for ext in ("png", "svg"):
        fig.savefig(out / f"histories.{ext}", dpi=165)
    plt.close(fig)

    fig, axes = plt.subplots(1, 3, figsize=(13, 4.8), layout="constrained")
    finals = [a for a in samples if a["theta_over_pi"] == .2 and a["is_budget_endpoint"]]
    labels = []
    for i, a in enumerate(finals):
        b = next(x for x in samples if x["arm"] == a["arm"] and x["is_hold_endpoint"])
        labels.append(f"{a['iteration_budget']} / {'coarse' if a['step_over_pi']==.025 else 'fine'}")
        vals = lambda x: [x["comparisons"]["accepted_parent"]["maximum_cut_entropy_jump"],
                          x["energy_terms"][0]-x["energy_terms"][1], min(x["spectra"]["sz1"]["inverse_xi"])]
        for ax, v, w in zip(axes, vals(a), vals(b)):
            color = COLORS[a["iteration_budget"]]
            ax.plot([i, i], [v, w], color=color, lw=2)
            ax.scatter(i, v, c=color, s=48, zorder=3)
            ax.scatter(i, w, facecolors="white", edgecolors=color, marker="s", s=45, zorder=3)
    for ax, title in zip(axes, ["Maximum cut-entropy change\nfrom accepted parent", "Local-energy alternation\ne₁ − e₂", "Leading Sz = 1 inverse ξ\nper period-2 transfer cell"]):
        ax.set_title(title, loc="left")
        ax.set_xticks(range(len(labels)), labels, rotation=40, ha="right")
    axes[0].axhline(.1, color=".5", ls="--", lw=1)
    axes[1].axhline(0, color=".5", ls="--", lw=1)
    fig.suptitle("Same flux, different relaxation histories: θ/π = 0.20", fontsize=15)
    fig.supxlabel("● Fixed-budget endpoint    □ After 16 more updates at the same flux\nCoarse Δθ/π = 0.025; fine = 0.0125. Inverse ξ is not a Fig. 2 energy gap.", fontsize=10)
    for ext in ("png", "svg"):
        fig.savefig(out / f"endpoints_and_holds.{ext}", dpi=165)
    plt.close(fig)

    fig, axes = plt.subplots(1, 2, figsize=(11, 4.9), layout="constrained")
    for a in finals:
        s = a["spectra"]["sz1"]
        color = COLORS[a["iteration_budget"]]
        marker = "o" if a["step_over_pi"] == .025 else "x"
        target = 0 if a["arm"] in ("n8_grid1", "n8_grid2", "n16_grid1") else 1
        axes[target].scatter(np.array(s["two_k1"])/np.pi, s["inverse_xi"], s=50, color=color, marker=marker,
                             label=f"N={a['iteration_budget']}, {'coarse' if marker=='o' else 'fine'}", alpha=.85)
    for ax, title in zip(axes, ["Short-budget endpoints: close spectra", "Longer-budget endpoints: changed spectra"]):
        ax.set_title(title, loc="left")
        ax.set_xlabel("2k₁ / π (charged-sector mapping)")
        ax.set_ylabel("Inverse ξ per period-2 transfer cell")
        ax.set_xlim(-1, 1)
        ax.set_ylim(.20, .35)
        ax.legend(fontsize=9, loc="upper left")
    fig.suptitle("Six leading Sz = 1 transfer modes at θ/π = 0.20", fontsize=14)
    fig.supxlabel("All requested transfer modes converged; the underlying MPS are unconverged diagnostics.\nMarker correspondence does not establish eigenvector identity across runs.", fontsize=10)
    for ext in ("png", "svg"):
        fig.savefig(out / f"spectra.{ext}", dpi=165)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--julia", default="julia")
    args = parser.parse_args()
    require(not args.output_directory.exists(), "review output already exists")
    report, points, accounting = audit(args.run_directory.resolve(), args.julia)
    args.output_directory.mkdir(parents=True)
    out = args.output_directory
    (out / "review.json").write_text(json.dumps(report, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    (out / "accounting.txt").write_text(accounting, encoding="utf-8")
    with (out / "histories.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["arm", "theta_over_pi", "cumulative_updates", "iteration", "native_error", "energy_density", "chi", "wall_seconds", "cpu_seconds"])
        writer.writeheader()
        for p in points:
            for row in p["history"]:
                writer.writerow({"arm": p["arm"], "theta_over_pi": p["theta_over_pi"],
                                 "cumulative_updates": (p["point"]-1)*p["iteration_budget"]+row["iteration"], **row})
    figures(report, points, out)
    print(json.dumps({k: report[k] for k in ("job_id", "sealed_inputs", "points", "updates", "analyzed_states", "elapsed_seconds", "node_hours", "phase1_remaining")}, indent=2))


if __name__ == "__main__":
    main()
