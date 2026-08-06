# Configuration guide

The supplied files cover the first Project B calculations:

- `pilot_yc6_1.toml`: a low-cost regression geometry matching the legacy scan.
- `hu_yc8_1_forward.toml`: the two-flavor Hu geometry, with the expected crossing at `theta/pi=1`.
- `hu_yc8_0_forward.toml`: the four-flavor Hu geometry, with the expected crossing at `theta/pi=2`.
- `yc6_1_chi_ladder_at_pi.toml`: a finite-entanglement ladder at the YC6-1 crossing.

For YC10, copy the corresponding YC8 file inside this project, change
`circumference`, give it a distinct `output_directory`, and use the Hu bond
dimensions only after the lower-cost workflow is clean.

For a reverse continuation, use a strictly decreasing `fluxes_over_pi` array.
The best initial state is a converged artifact from the high-flux side, supplied
as `initial_state_file` in `[scan]`. Run separate configuration files for every
seed/branch so their immutable state artifacts cannot be confused.

The built-in product seeds are `alternating`, `alternating_shifted`, `block`,
and `random_balanced`. The latter is reproducible through `random_seed`.

`twist_gauge = "uniform"` is the production convention because it preserves
the finite-flux translations used in Hu et al.'s momentum analysis. The MPS
period is inferred automatically. An explicit `mps_period` is accepted only for
diagnostic commensurate supercells; such states are not unfolded during
momentum postprocessing.
