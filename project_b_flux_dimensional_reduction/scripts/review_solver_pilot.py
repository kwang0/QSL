"""Verify and summarize a synchronized pilot without reading scratch tensors.

Chart contract: three static line panels show all recorded native errors by
iteration, with their declared tolerances. Each panel is a distinct solver
observable, never a speed ranking. The single blue palette, facet labels and
neutral dashed thresholds work in grayscale. Export PNG/SVG for the scientific
review. Numerical tables retain energy, continuity, timing and provenance.

Requires Python 3.11+, numpy, h5py and matplotlib; Julia runs the existing
accounting audit/guard. Write a new output directory on each review.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
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


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def toml(path):
    with Path(path).open("rb") as stream:
        return tomllib.load(stream)


def serial(value):
    if isinstance(value, bytes):
        return value.decode()
    if isinstance(value, np.ndarray):
        return [serial(x) for x in value.tolist()]
    if isinstance(value, np.generic):
        return serial(value.item())
    if isinstance(value, complex):
        return {"real": value.real, "imag": value.imag}
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, list):
        return [serial(x) for x in value]
    if isinstance(value, dict):
        return {k: serial(v) for k, v in value.items()}
    return value


def log_fit(rows, count):
    tail = rows[-min(count, len(rows)):]
    x = np.array([r["iteration"] for r in tail])
    y = np.log([r["native_error"] for r in tail])
    slope, intercept = np.polyfit(x, y, 1)
    total = np.sum((y-y.mean())**2)
    r2 = 1-np.sum((y-(slope*x+intercept))**2)/total if total else 0.0
    return {"points": len(tail), "log_error_slope_per_iteration": slope, "r_squared": r2}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", type=Path)
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--julia", default="julia")
    args = parser.parse_args()
    run = args.run_directory.resolve()
    out = args.output_directory.resolve()
    require(not out.exists(), f"Review output already exists: {out}")
    provenance = {}

    def track(path):
        path = Path(path).resolve()
        provenance[path.relative_to(ROOT).as_posix()] = sha(path)
        return path

    control_file = track(run / "control.snapshot.toml")
    control = toml(control_file)
    control_hash = sha(control_file)
    require(control_hash == track(run / "control.sha256").read_text().strip(), "control reference mismatch")
    recipe = control["recipe"]
    require(recipe == toml(ROOT / "configs/mpskit_solver_pilot.toml"), "recipe mismatch")
    for record in control["inputs"]:
        path = (ROOT / record["path"]).resolve()
        require(path.is_relative_to(ROOT), "control input outside project")
        require(sha(track(path)) == record["sha256"], f"sealed input mismatch: {path}")

    with track(run / "job.tsv").open() as stream:
        jobs = list(csv.DictReader(stream, delimiter="\t"))
    require(len(jobs) == 1 and jobs[0]["control_sha256"] == control_hash, "job/control mismatch")
    job_id = jobs[0]["job_id"]
    reconciliations = list((ROOT / "output/accounting/reconciliations" / job_id).glob("*.toml"))
    require(bool(reconciliations), "pilot has no synced live reconciliation")
    reconciliation = max((toml(track(p)) for p in reconciliations), key=lambda d: d["recorded_utc"])
    require(reconciliation["artifact_kind"] == "project_b_live_reconciliation", "unexpected accounting provenance")
    evidence = track(ROOT / reconciliation["evidence_path"])
    require(sha(evidence) == reconciliation["evidence_sha256"], "accounting evidence hash mismatch")
    lines = [s for s in evidence.read_text().splitlines() if s.strip() and not s.startswith("#")]
    raw_rows = list(csv.DictReader(lines, delimiter="|"))
    allocations = [r for r in raw_rows if r["JobIDRaw"] == job_id]
    require(bool(allocations) and all(r == allocations[0] for r in allocations), "ambiguous pilot allocation")
    allocation = allocations[0]
    require(allocation["State"] == "COMPLETED" and allocation["ExitCode"] == "0:0", "pilot not cleanly completed")
    cpus, seconds = int(allocation["NCPUS"]), int(allocation["ElapsedRaw"])
    charge = seconds / 3600 * math.ceil(cpus/2) / 128
    audit_command = [args.julia, "--startup-file=no", str(ROOT / "scripts/project_b_accounting.jl")]
    accounting = subprocess.run(audit_command + ["audit"], cwd=ROOT, check=True, text=True, capture_output=True).stdout
    subprocess.run(audit_command + ["guard", "0"], cwd=ROOT, check=True, text=True, capture_output=True)
    phase1, remaining = map(float, re.search(r"Phase 1: ([\d.]+); remaining: ([\d.]+)", accounting).groups())
    total = float(re.search(r"Project B: ([\d.]+)", accounting).group(1))
    table_lines = [line for line in accounting.splitlines() if re.match(r"\d+\t", line)]
    require(len({s.split("\t")[0] for s in table_lines}) == len(table_lines), "duplicate charged jobs")
    ledger_rows = [s.split("\t") for s in table_lines]
    recomputed = sum(int(v[3])/3600*math.ceil(int(v[4])/2)/128 for v in ledger_rows if v[1] == "1")
    require(abs(recomputed-phase1) < 1e-10, "independent accounting sum disagrees")
    pilot_rows = [v for v in ledger_rows if v[0] == job_id]
    require(len(pilot_rows) == 1 and abs(float(pilot_rows[0][5])-charge) < 1e-10, "pilot charge disagrees")

    audit_file = track(ROOT / recipe["checkpoint_audit_path"])
    scratch_audit = toml(audit_file)
    require(scratch_audit["authority"] == "owner_run_perlmutter" and scratch_audit["all_requested_hashes_verified"], "scratch audit authority mismatch")
    for key, relative in [("audit_script_sha256", "scripts/audit_yc8_bridge_checkpoints.jl"),
                          ("audit_library_sha256", "scripts/lib/ReviewEvidence.jl"),
                          ("audit_hash_library_sha256", "scripts/lib/FileIntegrity.jl")]:
        require(scratch_audit[key] == sha(ROOT / relative), "scratch-audit source mismatch")
    expected_scratch = {"4e3a5f406f61cb791ea98ef6b0dc6cfb108877eb5199d4dc71d204f150c0a9e6",
                        "45e5e6cf308936e35fdcf93f4d4cd909bcea4b8b71e061964b0e119ca1ddbcd7",
                        "fa4d7f01dbb7e10deb1c37bab659c07a9dba60fe63ba3e3db34c705c102b3e9b"}
    require(expected_scratch <= {a["sha256"] for a in scratch_audit["artifacts"] if a["hash_verified"]}, "missing required scratch audit")
    parent = scratch_audit["parent"]
    require(parent["sha256"] == recipe["parent_sha256"], "audit parent mismatch")
    with h5py.File(ROOT / control["parent_path"], "r") as h5:
        parent_entropy = h5["observables/von_neumann_entropies"][()]
        parent_terms = h5["observables/energy_terms"][()]
        parent_magnetization = h5["observables/magnetization_z"][()]

    stages = []
    chart_rows = []
    for index, spec in enumerate(recipe["stages"]):
        name = spec["name"]
        stage = toml(track(run / f"{name}.toml"))
        summary = toml(track(run / f"analysis_{name}.toml"))
        analysis_file = track(run / f"analysis_{name}.h5")
        require(sha(analysis_file) == summary["analysis_sha256"], f"analysis hash mismatch: {name}")
        require(stage["control_sha256"] == control_hash and stage["parent_sha256"] == recipe["parent_sha256"], "stage lineage mismatch")
        with track(run / f"{name}_history.tsv").open() as stream:
            rows = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(stream, delimiter="\t")]
        require(len(rows) == len(stage["history"]), "history row count mismatch")
        require(all(all(v == expected[k] for k, v in row.items()) for row, expected in zip(rows, stage["history"])), "TSV/TOML history mismatch")
        require(all(all(math.isfinite(v) for v in row.values()) and row["chi"] == recipe["chi"] for row in rows), "nonfinite/changed-chi history")
        require(all(b["iteration"] == a["iteration"]+1 for a, b in zip(rows, rows[1:])), "history iteration gap")
        tolerance = recipe["vumps_galerkin_tolerance" if spec["algorithm"] == "VUMPS" else "grassmann_gradient_tolerance"]
        tail = rows[-recipe["energy_window"]:]
        energy_span = max(r["energy_density"] for r in tail) - min(r["energy_density"] for r in tail)
        native = (len(rows) >= max(recipe["energy_window"], recipe["minimum_iterations"]) and
                  rows[-1]["iteration"] >= recipe["minimum_iterations"] and
                  rows[-1]["native_error"] <= tolerance and energy_span <= recipe["energy_span_tolerance"])
        require(native == stage["native_gate_passed"] == summary["native_gate_passed"], "native gate disagrees")
        with h5py.File(analysis_file, "r") as h5:
            get = lambda key: serial(h5[key][()])
            require(get("source/control_sha256") == control_hash and get("source/result_sha256") == stage["result_sha256"], "analysis provenance mismatch")
            require(get("lineage/parent_state_sha256") == recipe["parent_sha256"], "analysis parent mismatch")
            require(get("geometry/mps_period") == 2 and get("observables/maxlinkdim") == 512, "analysis geometry mismatch")
            diagnostics = {k: get("diagnostic/"+k) for k in h5["diagnostic"]}
            continuity = {k: get("continuation/"+k) for k in h5["continuation"] if isinstance(h5["continuation/"+k], h5py.Dataset)}
            observables = {k: get("observables/"+k) for k in ("energy_density", "energy_terms", "von_neumann_entropies", "magnetization_z")}
            require(bool(diagnostics["native_gate_passed"]) == native, "HDF5 native gate mismatch")
            require(bool(continuity["continuity_passed"]) == summary["multimetric_continuity_passed"], "continuity summary mismatch")
            require(not get("continuation_accepted") and not summary["continuation_accepted"], "unexpected promotion")
            entropy_jump = float(np.max(np.abs(np.array(observables["von_neumann_entropies"])-parent_entropy)))
            term_rms = float(np.sqrt(np.mean((np.array(observables["energy_terms"])-parent_terms)**2)))
            mag_rms = float(np.sqrt(np.mean((np.array(observables["magnetization_z"])-parent_magnetization)**2)))
            for actual, key in [(entropy_jump, "maximum_cut_entropy_jump"), (term_rms, "energy_term_rms_jump"), (mag_rms, "magnetization_rms_jump")]:
                require(abs(actual-continuity[key]) < 1e-12, f"independent {key} mismatch")
            xi_change = float(np.max(np.abs(np.log(np.array(continuity["candidate_correlation_lengths"])/
                                                  np.array(continuity["parent_correlation_lengths"])))))
            require(abs(xi_change-continuity["maximum_log_correlation_length_jump"]) < 1e-12, "correlation-length change mismatch")
            policy = recipe["continuity"]
            for value, limit, flag in [(entropy_jump, "maximum_cut_entropy_jump", "entropy_gate_passed"),
                                       (term_rms, "maximum_energy_term_rms_jump", "energy_term_gate_passed"),
                                       (mag_rms, "maximum_magnetization_rms_jump", "magnetization_gate_passed"),
                                       (continuity["mean_schmidt_total_variation"], "maximum_mean_schmidt_total_variation", "schmidt_gate_passed"),
                                       (xi_change, "maximum_log_correlation_length_jump", "correlation_length_gate_passed")]:
                require(bool(continuity[flag]) == (value <= policy[limit]), f"threshold disagreement: {flag}")
            require(summary["overlap_floor_passed"] == (continuity["overlap_per_site"] >= policy["minimum_overlap_per_site"]), "overlap gate mismatch")
            energy_error = abs(observables["energy_density"]-rows[-1]["energy_density"])
            require(abs(energy_error-diagnostics["cross_library_energy_difference"]) < 1e-15, "energy equivalence mismatch")

        step_rows = [r for r in raw_rows if r["JobIDRaw"] == f"{job_id}.{2*index}"]
        analysis_rows = [r for r in raw_rows if r["JobIDRaw"] == f"{job_id}.{2*index+1}"]
        require(step_rows and analysis_rows, "missing solver/analysis accounting")
        for row in step_rows + analysis_rows:
            require(row["State"] == "COMPLETED" and row["ExitCode"] == "0:0", "stage accounting failed")
        step = step_rows[-1]
        require(step["MaxRSS"].endswith("K"), "unexpected RSS units")
        minimum = min(rows, key=lambda r: r["native_error"])
        measured = rows[1:] if rows[0]["iteration"] == 0 else rows
        item = {"stage": name, "algorithm": spec["algorithm"], "theta_over_pi": spec["theta_over_pi"],
                "history_records": len(rows), "first_iteration": int(rows[0]["iteration"]), "final_iteration": int(rows[-1]["iteration"]),
                "first_native_error": rows[0]["native_error"], "final_native_error": rows[-1]["native_error"],
                "minimum_native_error": minimum["native_error"], "minimum_error_iteration": int(minimum["iteration"]),
                "final_over_minimum_error": rows[-1]["native_error"]/minimum["native_error"],
                "native_tolerance": tolerance, "last_four_energy_span": energy_span,
                "stop_reason": stage["stop_reason"], "native_gate_passed": native,
                "solver_step_seconds": int(step["ElapsedRaw"]), "analysis_step_seconds": int(analysis_rows[-1]["ElapsedRaw"]),
                "solver_max_rss_gib": float(step["MaxRSS"][:-1])/2**20,
                "median_iteration_seconds": float(np.median([r["wall_seconds"] for r in measured])),
                "last10_median_iteration_seconds": float(np.median([r["wall_seconds"] for r in measured[-10:]])),
                "process_cpu_to_wall_ratio": sum(r["cpu_seconds"] for r in measured)/sum(r["wall_seconds"] for r in measured),
                "late_fits": {str(n): log_fit(rows, n) for n in (5, 10, 20)},
                "summary": summary, "diagnostics": diagnostics, "continuity": continuity,
                "observables": observables, "initial_energy_density": stage["initial_energy_density"],
                "result_path": stage["result_path"], "result_sha256": stage["result_sha256"], "checkpoints": stage["checkpoints"]}
        stages.append(item)
        for row in rows:
            chart_rows.append({"stage": name, "algorithm": spec["algorithm"], "theta_over_pi": spec["theta_over_pi"],
                               "native_tolerance": tolerance, **row})
        track(run / "metrics" / f"{name}.time")
        track(run / "metrics" / f"analysis_{name}.time")

    track(run / f"logs/pilot-{job_id}.out")
    worker_result = track(run / "job.result").read_text()
    track(__file__)
    report = {"artifact_kind": "project_b_solver_pilot_retrospective_review", "job_id": job_id,
              "authority": "owner_confirmed_completed_checksum_sync; retrospective only",
              "reconciled_utc": reconciliation["recorded_utc"], "control_sha256": control_hash,
              "elapsed_seconds": seconds, "allocated_logical_cpus": cpus, "pilot_node_hours": charge,
              "phase1_spent_node_hours": phase1, "phase1_remaining_node_hours": remaining,
              "project_spent_node_hours": total, "unique_accounted_jobs": len(table_lines),
              "worker_result": worker_result, "stages": stages,
              "scratch_audit": [{k: a[k] for k in ("role", "iteration", "sha256", "vumps_projected_residual",
                  "maximum_cut_entropy_jump_from_parent", "mean_entropy", "energy_density", "dimerization")} for a in scratch_audit["artifacts"]],
              "limitations": ["Full pilot tensors remain on Perlmutter scratch and were not rehashed locally.",
                  "Intermediate checkpoint continuity was not measured by this pilot.",
                  "Native errors differ by algorithm; fits describe observed histories and are not completion forecasts.",
                  "All candidates remain diagnostic and unaccepted."],
              "provenance_sha256": provenance}
    out.mkdir(parents=True)
    (out / "review.json").write_text(json.dumps(serial(report), indent=2, allow_nan=False)+"\n", encoding="utf-8")
    (out / "accounting.txt").write_text(accounting, encoding="utf-8")
    with (out / "histories.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(chart_rows[0]))
        writer.writeheader()
        writer.writerows(chart_rows)
    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11, "axes.spines.top": False,
                         "axes.spines.right": False, "text.color": "#20252B", "axes.labelcolor": "#20252B"})
    fig, axes = plt.subplots(1, 3, figsize=(13.8, 4.9), layout="constrained")
    for ax, stage in zip(axes, stages):
        rows = [r for r in chart_rows if r["stage"] == stage["stage"]]
        x, y = [r["iteration"] for r in rows], [r["native_error"] for r in rows]
        ax.semilogy(x, y, color="#2864A0", lw=1.8, marker="o", ms=2.5)
        ax.axhline(stage["native_tolerance"], color="#555555", ls="--", lw=1.1)
        ax.annotate("gate: 1e−5", xy=(0.03, 1e-5), xycoords=("axes fraction", "data"), xytext=(0, -14), textcoords="offset points", fontsize=10)
        ax.set_ylim(5.5e-6, max(y)*1.7)
        ax.set_xlim(0, max(x)*1.06)
        label = "VUMPS" if stage["algorithm"] == "VUMPS" else "GradientGrassmann"
        ax.set_title(f"{label}  |  θ/π = {stage['theta_over_pi']:.2f}", loc="left", fontsize=12, pad=12)
        ax.set_xlabel("Recorded iteration")
        ax.set_ylabel("Galerkin error (log scale)" if label == "VUMPS" else "Gradient norm (log scale)")
        ax.grid(axis="y", which="major", color="#E5E7EB", lw=0.7)
        label_left = stage["stage"] == "difficult_vumps"
        ax.xaxis.set_major_locator(matplotlib.ticker.MaxNLocator(nbins=6, integer=True))
        ax.text(0.03 if label_left else 0.98, 0.96,
                f"final {stage['final_native_error']:.3g}\ncontinuity: {'pass' if stage['summary']['multimetric_continuity_passed'] else 'fail'}",
                transform=ax.transAxes, ha="left" if label_left else "right", va="top", fontsize=10)
    fig.suptitle(f"Solver histories — pilot {job_id}\nχ = 512; independent starts from the accepted θ/π = 0.15 parent", x=0.02, ha="left", fontsize=14)
    fig.supxlabel("Separate logarithmic y-ranges; Galerkin error and gradient norm are distinct quantities.\nSource: synchronized pilot journals and control; 2026-09-07.", fontsize=10)
    fig.savefig(out / "convergence.png", dpi=170)
    fig.savefig(out / "convergence.svg")
    plt.close(fig)
    brief = {k: report[k] for k in ("job_id", "pilot_node_hours", "phase1_spent_node_hours", "phase1_remaining_node_hours", "project_spent_node_hours", "unique_accounted_jobs")}
    brief["stages"] = [{k: s[k] for k in ("stage", "final_iteration", "final_native_error", "minimum_native_error", "minimum_error_iteration", "final_over_minimum_error", "last_four_energy_span", "last10_median_iteration_seconds", "late_fits")} for s in stages]
    print(json.dumps(serial(brief), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
