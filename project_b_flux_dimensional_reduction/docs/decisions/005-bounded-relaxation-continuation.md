# 005 - Test finite relaxation before interpreting branch loss

Status: executed and reviewed; results and successor proposal in [decision 006](006-relaxation-continuation-outcome.md)
Date: 2026-09-08

The owner proposed that a few updates after each flux increment may relax the
desired state before a slower optimizer escape. The preceding pilot's VUMPS
minimum followed by a large residual increase and terminal continuity failure
is consistent with that hypothesis. The gradient arm's upturn without a
continuity failure shows that a turnaround alone cannot identify escape.

Warm-started flux insertion and temporary following of a metastable level are
explicitly discussed in [He et al. (2017)](https://arxiv.org/pdf/1611.06238).
[Hu et al. (2019)](https://arxiv.org/pdf/1905.09837) discusses collapse into
competing states but does not provide an explicit residual-turnaround stopping
rule in the methods we reviewed. This experiment tests our numerical route;
it does not attribute an unreported procedure to the authors.

Prepare the bounded comparison in
[RELAXATION_CONTINUATION.md](../plans/RELAXATION_CONTINUATION.md): fixed chi512
VUMPS, 8/16/32 outer iterations, two flux grids from the accepted 0.15 parent to
0.20, fixed-flux holds and a 0.15 baseline. The owner authorized diagnostic
advance before native convergence for this finite schedule. The primary
lineage, historical rejected classifications and campaign gates are unchanged.

Advance from predeclared endpoints, save every iterate and analyze minima as
additional samples. Do not stop on a turnaround or select whichever snapshot
best resembles the paper. Compare target observables across iteration budget,
flux step and fixed-flux relaxation before judging whether looser numerical
stopping is adequate. An algorithm-dependent trajectory can remain smooth even
after a metastable minimum disappears.

The native 1e-5 pilot gate is a reference diagnostic here, not an established
paper threshold. Discarded weight, native Galerkin error and excitation-gap
accuracy remain distinct. A future production acceptance policy needs evidence
of observable stability; no relaxed threshold is adopted by this trial.

The maximum reservation is 1.40625 node-hours inside the existing Phase 1
allowance, subject to a fresh live guard. This test has priority over the
previously proposed fixed-flux-only calibration. General-chi growth, zero-flux
preparation and the missing Figure 2 gap calculation from decision 004 remain
the broader project path.
