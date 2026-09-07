# Sealed launch controls

Keep compact, locally prepared launch controls here so Git push/pull delivers
them together with their source and `configs/*_active_control.ref` pointers.
Paths inside each control remain relative to the Project B root.

Controls are immutable: choose a new filename when preparing a successor,
validate it, and update the active reference with its path and SHA-256 in the
same commit. The pilot preparer already accepts a destination such as
`configs/controls/solver_pilot_control_v3.toml`. Never overwrite a previously
sealed control or include heavy tensor payloads here.

`solver_pilot_control_v2.toml` is the exact 7,255-byte control originally sealed
under `output/review_followup/`; only its delivery path changed. Its SHA-256 is
`969b69b1c40d3a70e07c58fe9b12d123564781c5f40b9a4058b74f4382278818`.
The existing accepted parent and MPSKit bridge stay in canonical `output/`;
live preflight verifies them and generates accounting and scratch-audit
evidence on Perlmutter.
