# 007 - Test return paths at matched relaxation density

Status: owner-authorized, implemented and validated locally and by live Perlmutter preflight on 2026-09-09; submission unconfirmed

Job 58082150 preserved close spectra after short relaxation but changed state
under further updates, including at fixed flux. Equal-total-update comparisons
show that decreasing the flux step at fixed N confounds flux discretization
with accumulated relaxation. A useful continuation test must address both.

Implement [ROUNDTRIP_CONTINUATION.md](../plans/ROUNDTRIP_CONTINUATION.md): four
independent accepted-parent starts, 0.15 to 0.25 to 0.15, coarse/fine update
pairs 2/1 and 4/2. This holds update density fixed within each refinement pair
and doubles it between pairs. The loop has 96 updates and a 0.546875 node-hour
maximum reservation. No scratch state from the preceding job is required.

The return carries its own outward endpoint, and same-flux comparisons use
that arm's actual outward states. The imported origin is measured to distinguish
return drift from the small known bridge-recanonicalization drift. Save and
measure every iterate so future review does not depend on selecting a favorable
residual minimum. Limited diagnostic advance is authorized only within this
sealed finite schedule; the accepted parent and production gates remain intact.

Use the existing fixed-update VUMPS kernel, separate new control/driver modules,
and the common accounting/locking machinery. New modules sit outside the
completed controls' automatic top-level source enumeration. This preserves
their exact source validation while allowing a separately sealed successor.
Correct neutral momentum labels in the new analysis by multiplying the uniform
twist shift by physical Sz. Keep the completed run's recorded labels immutable.

An apparent return can result from insufficient state response. Evaluate both
update densities, step refinement, forward/return spectra, magnetization and
local-energy ordering before interpreting reversibility. No new convergence
threshold, physical phase claim or Fig. 2 gap result follows from this setup.
