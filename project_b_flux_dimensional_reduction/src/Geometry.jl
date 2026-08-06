const NN_DISPLACEMENTS = ((1, 0), (0, 1), (-1, 1))
const NNN_DISPLACEMENTS = ((1, 1), (-2, 1), (-1, 2))

"""Geometry of a YC(Ly)-n cylinder with compactification Ly*a1 - n*a2."""
struct YCGeometry
    circumference::Int
    shift::Int

    function YCGeometry(circumference::Integer, shift::Integer=0)
        circumference >= 2 || throw(ArgumentError("circumference must be at least 2"))
        0 <= shift < circumference ||
            throw(ArgumentError("shift must satisfy 0 <= shift < circumference"))
        return new(Int(circumference), Int(shift))
    end
end

Base.show(io::IO, g::YCGeometry) = print(io, "YC", g.circumference, "-", g.shift)

"""
One oriented exchange bond in an infinite-MPS unit cell.

`source_site` and `target_site` are sites in the one-dimensional snake ordering.
At least one lies in the home MPS cell. `cell_shift` is the signed target-cell
offset relative to the source cell. `winding` counts crossings of the physical
YC seam and is retained for legacy seam-gauge states.
"""
struct CylinderBond
    family::Symbol
    row::Int
    col::Int
    drow::Int
    dcol::Int
    row2::Int
    col2::Int
    winding::Int
    source_site::Int
    target_site::Int
    cell_shift::Int
end

"""
Smallest symmetry-compatible MPS period used by this project.

For the Hu geometries, an even YC(Ly)-0 cylinder has `Ly` tensors while every
YC(Ly)-1 cylinder has a two-site repeat. Odd YC(Ly)-0 cylinders require two
rings when conserving total Sz. Other shifts retain the conservative ring cell.
"""
function minimal_mps_period(geometry::YCGeometry; conserve_qns::Bool=true)
    Ly = geometry.circumference
    lattice_period = geometry.shift == 1 ? 1 : Ly
    if conserve_qns && isodd(lattice_period)
        return 2 * lattice_period
    end
    return lattice_period
end

function validate_mps_period(
    geometry::YCGeometry,
    period::Integer;
    conserve_qns::Bool=true,
)
    requested = Int(period)
    minimum = minimal_mps_period(geometry; conserve_qns)
    requested >= minimum || throw(
        ArgumentError("MPS period $requested is smaller than the required period $minimum for $geometry"),
    )
    requested % minimum == 0 || throw(
        ArgumentError("MPS period $requested must be an integer multiple of $minimum for $geometry"),
    )
    conserve_qns && isodd(requested) && throw(
        ArgumentError("a conserved-Sz spin-1/2 MPS period must contain an even number of sites"),
    )
    return true
end

"""Canonical `(row, col)` coordinates of a one-dimensional snake site."""
function lattice_coordinates(site::Integer, geometry::YCGeometry)
    site >= 1 || throw(ArgumentError("snake site indices start at one"))
    zero_based = Int(site) - 1
    return (;
        row=mod(zero_based, geometry.circumference),
        col=fld(zero_based, geometry.circumference),
    )
end

"""Snake index invariant under `(row + Ly, col - n) == (row, col)`."""
function snake_site_index(row::Integer, col::Integer, geometry::YCGeometry)
    Ly = geometry.circumference
    winding = fld(Int(row), Ly)
    wrapped_row = Int(row) - winding * Ly
    wrapped_col = Int(col) + winding * geometry.shift
    return wrapped_col * Ly + wrapped_row + 1
end

"""
Wrap a lattice endpoint using `(row + Ly, col - n) == (row, col)`.

`winding` counts signed crossings of the physical seam. It is only the twist
charge in the legacy seam gauge; the paper-compatible uniform gauge uses
`drow / Ly` instead.
"""
function wrap_endpoint(
    row::Integer,
    col::Integer,
    drow::Integer,
    dcol::Integer,
    geometry::YCGeometry,
)
    raw_row = Int(row) + Int(drow)
    raw_col = Int(col) + Int(dcol)
    winding = fld(raw_row, geometry.circumference)
    wrapped_row = raw_row - winding * geometry.circumference
    wrapped_col = raw_col + winding * geometry.shift
    return (; row=wrapped_row, col=wrapped_col, winding)
end

function normalize_bond_to_home_cell(source::Integer, target::Integer, period::Integer)
    source_cell = fld(Int(source) - 1, Int(period))
    target_cell = fld(Int(target) - 1, Int(period))
    offset_cells = -min(source_cell, target_cell)
    source_site = Int(source) + offset_cells * Int(period)
    target_site = Int(target) + offset_cells * Int(period)
    min(fld(source_site - 1, period), fld(target_site - 1, period)) == 0 ||
        error("bond normalization did not touch the home MPS cell")
    return (;
        source_site,
        target_site,
        cell_shift=target_cell - source_cell,
    )
end

"""
Return the oriented NN and NNN bonds in one MPS unit cell.

The default is the smallest Hu-compatible conserved-Sz cell. A larger
commensurate `period` is accepted so old supercell checkpoints can still be
read and benchmarked without being mistaken for the production convention.
"""
function unit_cell_bonds(
    geometry::YCGeometry;
    period::Integer=minimal_mps_period(geometry),
)
    validate_mps_period(geometry, period)
    cell_sites = Int(period)
    bonds = CylinderBond[]
    sizehint!(bonds, 6 * cell_sites)
    for source in 1:cell_sites
        coordinates = lattice_coordinates(source, geometry)
        for (family, displacements) in ((:NN, NN_DISPLACEMENTS), (:NNN, NNN_DISPLACEMENTS))
            for (drow, dcol) in displacements
                endpoint = wrap_endpoint(
                    coordinates.row,
                    coordinates.col,
                    drow,
                    dcol,
                    geometry,
                )
                target = snake_site_index(endpoint.row, endpoint.col, geometry)
                normalized = normalize_bond_to_home_cell(source, target, cell_sites)
                push!(
                    bonds,
                    CylinderBond(
                        family,
                        coordinates.row,
                        coordinates.col,
                        drow,
                        dcol,
                        endpoint.row,
                        endpoint.col,
                        endpoint.winding,
                        normalized.source_site,
                        normalized.target_site,
                        normalized.cell_shift,
                    ),
                )
            end
        end
    end
    return bonds
end

function validate_bond_table(
    geometry::YCGeometry,
    bonds=unit_cell_bonds(geometry);
    period::Integer=length(bonds) ÷ 6,
)
    validate_mps_period(geometry, period)
    count(b -> b.family === :NN, bonds) == 3 * period ||
        error("wrong nearest-neighbor bond count")
    count(b -> b.family === :NNN, bonds) == 3 * period ||
        error("wrong next-nearest-neighbor bond count")
    all(b -> b.source_site != b.target_site, bonds) || error("self-bond detected")
    return true
end

"""Twist charge multiplying theta for one bond in the requested gauge."""
function bond_twist_charge(bond::CylinderBond, geometry::YCGeometry, gauge::Symbol)
    gauge === :uniform && return bond.drow / geometry.circumference
    gauge === :seam && return Float64(bond.winding)
    throw(ArgumentError("twist gauge must be :uniform or :seam, got $gauge"))
end

cylinder_class(g::YCGeometry) =
    iseven(g.circumference) && iseven(g.shift) ? :four_flavor : :two_flavor

expected_gapless_flavors(g::YCGeometry) = cylinder_class(g) === :four_flavor ? 4 : 2

"""Positive Hu et al. Dirac crossing in units of pi."""
predicted_crossing_over_pi(g::YCGeometry) = cylinder_class(g) === :four_flavor ? 2.0 : 1.0

"""
Coarse-to-dense positive-flux schedule centered on the predicted crossing.

The default contains both sides of the crossing. Runs intended to preserve a
specific metastable branch should split this into separate forward and reverse
configuration files.
"""
function recommended_flux_schedule(
    g::YCGeometry;
    coarse_step::Real=0.25,
    dense_offsets=(1 / 8, 1 / 16, 1 / 32, 0.0),
    include_above::Bool=true,
)
    coarse_step > 0 || throw(ArgumentError("coarse_step must be positive"))
    crossing = predicted_crossing_over_pi(g)
    coarse = collect(0.0:Float64(coarse_step):crossing)
    dense = Float64[]
    for offset in dense_offsets
        offset >= 0 || throw(ArgumentError("dense offsets must be nonnegative"))
        push!(dense, crossing - Float64(offset))
        include_above && !iszero(offset) && push!(dense, crossing + Float64(offset))
    end
    return sort!(unique!(filter(x -> x >= 0, vcat(coarse, dense))))
end
