# `triangular_gutzwiller_mps.jl` quick usage notes

## New geometry options

```julia
using .TriangularGutzwillerMPS

lat_xc = TriangularXC(6, 12)
lat_yc = TriangularYC(6, 12)      # ordinary YC
lat_yc_m = TriangularYC(6, 12, 2) # generalized YC2n-2m with m = 2
```

For `TriangularYC(C,L,m)`, winding the row index by `C` shifts the column by `m`,
so this realizes the generalized YC identification used in `YC2n-2m` cylinders.

## Boundary twists `theta` and `phi`

The top-level constructors now accept

- `theta`: spin twist
- `phi`: emergent gauge / boundary twist seen by both spin species

The seam-crossing hopping phases are

- spin up: `exp(im * (phi + theta/2))`
- spin down: `exp(im * (phi - theta/2))`

Example:

```julia
lat = TriangularYC(6, 12, 2)

res = prepare_u1_dsl_gutzwiller_mps(
    lat;
    theta=pi,
    phi=0.0,
    gauge=:auto,
    maxdim=4000,
    cutoff=1e-10,
    verbose=true,
)
```

At the mean-field boundary-condition level, `(phi = pi, theta = 0)` is equivalent to
`(phi = 0, theta = 2pi)` because the spinon twists are `phi ± theta/2`.

## Shared physical spin-site indices

```julia
using ITensors

lat = TriangularYC(6, 12, 2)
N = nsite(lat)
sites = siteinds("S=1/2", N; conserve_qns=false)

psi_u1 = prepare_u1_dsl_gutzwiller_mps(lat; spin_sites=sites)
psi_z2 = prepare_z2_piflux_gutzwiller_mps(lat; spin_sites=sites)
```

## Notes on the π-flux gauge

The module now chooses a geometry-dependent convenient gauge by default:

- `:xc_half_triangle` for `TriangularXC`
- `:yc_half_triangle` for `TriangularYC`

You can override that with `gauge=:uniform` or an explicit gauge symbol.
