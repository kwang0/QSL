"""Extend a completed full-flux review using saved accepted preparation data.

Read-only HDF5/JSON analysis: no solver or transfer eigensolver is run. Preserve
the original review and distinguish the common ITensor lineage from the three
MPSKit paths. Requires the same Python dependencies as the original review.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import h5py
import numpy as np

from review_fullflux_continuation import ROOT, require, sha, read_toml, figures
from review_relaxation_continuation import wrap

HASHES = [
    "95255fbe3a590505902bd0061d7d9d9f14f8ecd7ca3e4eac1aacfc5c7fe72d0b",
    "f71fc084883ea98535e012801d47c2c0b3c0b5ce58e08c72592e46410a27b7cc",
    "38312fc996fef6ea65511eaa2fe927b2a2da634bff3dae6d6feae6b265fb7803",
]
LEGACY = ROOT / "output/phase1/yc8_1/primary_forward_chi512_legacy_0p1/seed_101/chi512"


def extend(review_path):
    report = json.loads(review_path.read_text(encoding="utf-8"))
    require(report["job_id"] == "58179916", "this extension targets job 58179916")
    provenance = {review_path.relative_to(ROOT).as_posix(): sha(review_path)}

    def track(path):
        provenance[path.relative_to(ROOT).as_posix()] = sha(path)
        return path

    # Recheck the plotted run analyses against their previously audited hashes.
    sources = report["provenance_sha256"]
    analyses = {Path(p).stem: p for p in sources if Path(p).name.startswith("analysis_") and p.endswith(".toml")}
    require(len(analyses) == len(report["samples"]) == 30, "full-flux analysis count")
    for a in report["samples"]:
        suffix = "origin" if a["point"] == 0 else f"point{a['point']}_iter{a['iteration_budget']}"
        p = analyses[f"analysis_{a['arm']}_{suffix}"]
        require(sha(track(ROOT/p)) == sources[p], "full-flux analysis changed")
        raw = read_toml(ROOT/p)
        require(all(raw[k] == a[k] for k in raw), "review sample differs from its raw analysis")
    controls = [p for p in sources if p.endswith("control.snapshot.toml")]
    require(len(controls) == 1, "ambiguous full-flux control")
    control_path = track(ROOT/controls[0])
    require(sha(control_path) == report["control_sha256"], "control changed")
    control = read_toml(control_path)

    paths = []
    for label in ("00000000", "10000000"):
        matches = list((LEGACY/"states").glob(f"*theta_p0p{label}_accepted_*.h5"))
        require(len(matches) == 1, "ambiguous accepted preparation state")
        paths.append(matches[0])
    paths.append(ROOT/control["parent_path"])
    history = []
    for i,(theta,path,expected) in enumerate(zip((0., .1, .15), paths, HASHES)):
        require(sha(track(path)) == expected, "accepted state hash mismatch")
        spec_path = track(LEGACY/"spectra"/f"spectrum_{path.name}")
        with h5py.File(path,"r") as f, h5py.File(spec_path,"r") as s:
            def value(group, key):
                v = group[key][()]
                return v.decode() if isinstance(v, bytes) else v
            require(value(f,"continuation/parent_state_sha256") == (HASHES[i-1] if i else ""), "parent hash chain")
            require(np.array_equal(f["continuation/flux_history_over_pi"][()], [0., .1, .15][:i+1]), "flux history")
            require(f["continuation_accepted"][()] and f["optimizer/converged"][()], "unaccepted preparation")
            require(f["optimizer/residual"][()] <= f["optimizer/residual_tolerance"][()], "historical residual gate")
            for g in (f,s):
                for key,wanted in {
                    "theta_over_pi": theta, "geometry/circumference": 8, "geometry/shift": 1,
                    "geometry/mps_period": 2, "model/twist_gauge": "uniform", "model/J1": 1.,
                    "model/J2": .12, "model/Delta1": 1., "model/Delta2": 1., "model/Bz": 0.,
                    "branch": "primary_forward_chi512_legacy_0p1",
                    "preparation": "independent_theta0_alternating_chi512",
                    "direction": "forward", "random_seed": 101,
                }.items():
                    require(value(g,key) == wanted, f"historical metadata {key}")
            require(f["observables/maxlinkdim"][()] == s["maxlinkdim"][()] == 512, "bond dimension")
            require(value(s,"source_state_basename") == path.name, "spectrum source basename")
            stored_path = value(s,"source_state_path").replace("\\", "/")
            require(stored_path.endswith(path.relative_to(ROOT).as_posix()), "spectrum source path")
            require(value(s,"momentum/strategy") == "yc1_two_site_pure", "transfer cell convention")
            q = s["sectors/sz_1"]
            require(q["physical_sz"][()] == 1 and q["raw_qn_sz"][()] == 2, "charged sector")
            n = len(q["inverse_xi"])
            require(n == (5 if i == 0 else 4) and q["krylov_converged"][()] >= n, "cached mode count/convergence")
            require(np.all(q["momentum_resolved"][()]), "unresolved stored momentum")
            z = q["normalized_lambdas"][()]
            require(np.max(abs(z-q["lambdas"][()]/q["reference_lambda"][()])) < 1e-12, "spectrum normalization")
            require(np.max(abs(-np.log(abs(z))-q["inverse_xi"][()])) < 1e-10, "inverse length units")
            for field,wanted in (("pure_transfer_phase", np.angle(z)),
                                 ("two_k1", np.angle(z)+2*np.pi*theta/8), ("k2", 4*np.angle(z))):
                require(np.max(abs(wrap(q[field][()]-wanted))) < 1e-10, f"stored {field} identity")
            spectrum = {k:q[v][()].tolist() for k,v in [("inverse_xi","inverse_xi"),
                ("two_k1","two_k1"),("k2","k2"),("transfer_phase","pure_transfer_phase") ]}
            spectrum.update(lambda_real=z.real.tolist(),lambda_imag=z.imag.tolist(),
                mode_count=n,physical_sz=1,raw_qn_sz=2,units="complete period-2 transfer cells")
            history.append(dict(role="shared_accepted_preparation", theta_over_pi=theta,
                state_path=path.relative_to(ROOT).as_posix(), state_sha256=expected,
                spectrum_path=spec_path.relative_to(ROOT).as_posix(), spectrum_sha256=sha(spec_path),
                parent_state_sha256=HASHES[i-1] if i else "",
                energy_density=float(f["observables/energy_density"][()]),
                energy_terms=f["observables/energy_terms"][()].tolist(),
                magnetization_z=f["observables/magnetization_z"][()].tolist(),
                entropy=f["observables/von_neumann_entropies"][()].tolist(),
                itensor_projected_residual=float(f["optimizer/residual"][()]),spectra={"sz1":spectrum}))
    report["accepted_prehistory"] = history
    report["plot_extension"] = dict(date="2026-09-12", provenance_sha256=provenance,
        notes=["Common accepted ITensor preparation is repeated for context; three MPSKit arms begin at 0.15pi.",
               "Cached spectra contain 5/4/4 converged charged modes at 0/0.1/0.15pi; full-flux spectra contain six.",
               "Historical spectrum files link states by path/basename and metadata, without a creation-time source hash. Current state hashes and lineage match the established records; both artifacts are hashed here.",
               "ITensor projected residual and MPSKit Galerkin error are different quantities.",
               "Stored momentum convention is preserved, including its unresolved absolute-sign caveat. No new optimization or measurement was performed."])
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    require(not out.exists(), "use a new output directory")
    report = extend(args.review.resolve())
    out.mkdir(parents=True)
    for path in (Path(__file__).resolve(),ROOT/"scripts/review_fullflux_continuation.py"):
        report["plot_extension"]["provenance_sha256"][path.relative_to(ROOT).as_posix()] = sha(path)
    (out/"review_with_prehistory.json").write_text(json.dumps(report,indent=2,allow_nan=False),encoding="utf-8")
    figures(report,out)
    print(json.dumps(report["accepted_prehistory"],indent=2))


if __name__ == "__main__":
    main()
