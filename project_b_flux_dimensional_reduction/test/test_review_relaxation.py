"""Regression checks for review calculations and corruption rejection."""
import importlib.util
from pathlib import Path
import sys
import unittest

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("review", ROOT / "scripts/review_relaxation_continuation.py")
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)
RECIPE = review.read_toml(ROOT / "configs/relaxation_continuation.toml")


class ReviewTests(unittest.TestCase):
    def test_turnaround_is_first_sustained_rise_not_global_minimum(self):
        rows = [{"native_error": x} for x in [4, 2, 2.2, 2.3, 2.4, 1.0, 1.1]]
        self.assertEqual(review.selection(rows, 4, RECIPE), ([2, 4, 5, 6, 7], 5))
        self.assertEqual(review.selection(rows[:3], 8, RECIPE), ([2, 3], 0))

    def test_native_gate_requires_energy_window(self):
        rows = [{"native_error": 1e-6, "energy_density": -0.5} for _ in range(4)]
        self.assertFalse(review.native_gate(rows[:3], RECIPE))
        self.assertTrue(review.native_gate(rows, RECIPE))
        rows[0]["energy_density"] += 2e-8
        self.assertFalse(review.native_gate(rows, RECIPE))

    def spectrum(self):
        phase = np.array([.1, -.1, .5, -.5, 2.9, -2.9])
        inverse = np.linspace(.2, .4, 6)
        z = np.exp(-inverse+1j*phase)
        return {"lambda_real": z.real.tolist(), "lambda_imag": z.imag.tolist(), "inverse_xi": inverse.tolist(),
                "transfer_phase": phase.tolist(), "two_k1": review.wrap(phase+2*np.pi*.2/8).tolist(),
                "k2": review.wrap(4*phase).tolist(), "physical_sz": 1, "raw_qn_sz": 2,
                "units": RECIPE["spectrum"]["units"], "krylov_converged": 6,
                "requested_modes_converged": True, "krylov_residual_norms": [1e-12]*6}

    def test_spectrum_identities_reject_wrong_units_or_numbers(self):
        s = self.spectrum()
        review.audit_spectrum(s, .2, RECIPE["spectrum"])
        for key, value in [("raw_qn_sz", 1), ("units", "sites"), ("requested_modes_converged", False),
                           ("inverse_xi", [1.0]*6), ("two_k1", [0.0]*6)]:
            bad = {**s, key: value}
            with self.subTest(key=key), self.assertRaises(ValueError):
                review.audit_spectrum(bad, .2, RECIPE["spectrum"])

    def test_matching_is_permutation_invariant(self):
        s, t = self.spectrum(), self.spectrum()
        for key in ("lambda_real", "lambda_imag", "inverse_xi", "transfer_phase", "two_k1", "k2"):
            t[key] = t[key][::-1]
        d = review.spectrum_comparison({"spectra": {"sz1": s}}, {"spectra": {"sz1": t}})
        self.assertEqual(d["assignment"], [5, 4, 3, 2, 1, 0])
        self.assertEqual(d["hausdorff_complex"], 0)
        self.assertEqual(d["max_matched_inverse_xi_difference"], 0)

    def test_phase_matching_wraps_branch_cut(self):
        s, t = self.spectrum(), self.spectrum()
        t["transfer_phase"] = [x+2*np.pi for x in t["transfer_phase"]]
        d = review.spectrum_comparison({"spectra": {"sz1": s}}, {"spectra": {"sz1": t}})
        self.assertLess(d["max_matched_transfer_phase_difference"], 1e-14)


if __name__ == "__main__":
    unittest.main()
