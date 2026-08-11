function add_twisted_heisenberg_bond!(
    opsum,
    coupling::Real,
    anisotropy::Real,
    source::Integer,
    target::Integer,
    theta::Real,
    twist_charge::Real,
)
    iszero(coupling) && return opsum
    phase = cis(Float64(theta) * Float64(twist_charge))
    opsum += anisotropy * coupling, "Sz", source, "Sz", target
    opsum += 0.5 * coupling * phase, "S+", source, "S-", target
    opsum += 0.5 * coupling * conj(phase), "S-", source, "S+", target
    return opsum
end

function triangular_flux_opsum(
    model::ModelSettings,
    theta::Real;
    period::Integer=model_mps_period(model),
    bonds=unit_cell_bonds(model.geometry; period),
)
    opsum = OpSum()
    for site in 1:Int(period)
        opsum += 0.0, "Id", site
        !iszero(model.Bz) && (opsum += -model.Bz, "Sz", site)
    end
    for bond in bonds
        coupling, anisotropy = bond.family === :NN ?
            (model.J1, model.Delta1) : (model.J2, model.Delta2)
        opsum = add_twisted_heisenberg_bond!(
            opsum,
            coupling,
            anisotropy,
            bond.source_site,
            bond.target_site,
            theta,
            bond_twist_charge(bond, model.geometry, model.twist_gauge),
        )
    end
    return opsum
end

function balanced_seed_states(circumference::Integer, pattern::AbstractString, random_seed::Integer)
    iseven(circumference) ||
        throw(ArgumentError("a conserved-Sz spin-1/2 MPS seed requires an even unit-cell size"))
    key = lowercase(replace(pattern, '-' => '_'))
    states = if key == "alternating"
        [isodd(i) ? "Up" : "Dn" for i in 1:circumference]
    elseif key in ("alternating_shifted", "shifted_alternating")
        [isodd(i) ? "Dn" : "Up" for i in 1:circumference]
    elseif key in ("block", "domain")
        [i <= circumference ÷ 2 ? "Up" : "Dn" for i in 1:circumference]
    elseif key in ("random", "random_balanced")
        rng = MersenneTwister(random_seed)
        shuffle!(rng, vcat(fill("Up", circumference ÷ 2), fill("Dn", circumference ÷ 2)))
    else
        throw(ArgumentError("unknown seed pattern '$pattern'"))
    end
    count(==("Up"), states) == count(==("Dn"), states) || error("seed is not Sz balanced")
    return states
end

function seed_function(circumference::Integer, pattern::AbstractString, random_seed::Integer)
    states = balanced_seed_states(circumference, pattern, random_seed)
    return site -> states[mod1(site, circumference)]
end

function build_product_state(settings::ProjectSettings)
    period = model_mps_period(settings.model)
    initial_state = seed_function(period, settings.scan.seed_pattern, settings.scan.random_seed)
    sites = infsiteinds(
        "S=1/2",
        period;
        conserve_qns=true,
        initstate=initial_state,
    )
    return InfMPS(sites, initial_state)
end

function build_hamiltonian(model::ModelSettings, sites, theta_over_pi::Real)
    period = length(sites)
    validate_mps_period(model.geometry, period)
    theta = pi * Float64(theta_over_pi)
    if model.twist_gauge === :seam && !iszero(theta) && period % model.geometry.circumference != 0
        error(
            "the seam twist gauge is not periodic in the $period-site MPS cell for " *
            "$(model.geometry); use twist_gauge='uniform' (recommended) or a ring-sized supercell",
        )
    end
    bonds = unit_cell_bonds(model.geometry; period)
    validate_bond_table(model.geometry, bonds; period)
    opsum = triangular_flux_opsum(model, theta; period, bonds)
    return InfiniteSum{MPO}(opsum, sites)
end

function center_probabilities(center_tensor)
    _, singular_values, _ = svd(center_tensor, first(inds(center_tensor)))
    weights = Float64[]
    for n in 1:dim(singular_values, 1)
        weight = real(singular_values[n, n]^2)
        weight > 0 && push!(weights, weight)
    end
    normalization = sum(weights)
    normalization > 0 || error("center tensor has zero Schmidt norm")
    return weights ./ normalization, normalization
end

function entanglement_observables(psi)
    ncuts = nsites(psi)
    von_neumann = zeros(Float64, ncuts)
    renyi2 = zeros(Float64, ncuts)
    raw_norms = zeros(Float64, ncuts)
    schmidt_probabilities = Vector{Vector{Float64}}(undef, ncuts)
    for cut in 1:ncuts
        probabilities, raw_norm = center_probabilities(psi.C[cut])
        schmidt_probabilities[cut] = probabilities
        raw_norms[cut] = raw_norm
        von_neumann[cut] = -sum(p -> p * log(p), probabilities)
        renyi2[cut] = -log(sum(abs2, probabilities))
    end
    return (; von_neumann, renyi2, raw_norms, schmidt_probabilities)
end

function bond_sector_profile(center_tensor)
    _, singular_values, _ = svd(center_tensor, first(inds(center_tensor)))
    schmidt_index = last(inds(singular_values))
    sector_space = space(schmidt_index)
    sector_space isa AbstractVector || error(
        "bond-sector diagnostics require a QN-conserving virtual index",
    )
    raw_weights = Dict{String,Float64}()
    multiplicities = Dict{String,Int}()
    offset = 0
    for entry in sector_space
        qn = first(entry)
        multiplicity = Int(last(entry))
        label = string(qn)
        weight = sum(
            abs2(singular_values[position, position]) for
            position in (offset + 1):(offset + multiplicity)
        )
        multiplicities[label] = multiplicity
        raw_weights[label] = Float64(real(weight))
        offset += multiplicity
    end
    offset == dim(schmidt_index) || error("QN sector multiplicities do not sum to bond dimension")
    normalization = sum(values(raw_weights))
    normalization > 0 || error("center tensor has zero Schmidt norm")
    return Dict(
        label => (
            multiplicity=multiplicities[label],
            schmidt_weight=raw_weights[label] / normalization,
        ) for label in keys(multiplicities)
    )
end

function compare_bond_sectors(before, after)
    nsites(before) == nsites(after) || error("states have different MPS periods")
    rows = NamedTuple[]
    for cut in 1:nsites(before)
        before_profile = bond_sector_profile(before.C[cut])
        after_profile = bond_sector_profile(after.C[cut])
        labels = sort!(collect(union(keys(before_profile), keys(after_profile))))
        for label in labels
            before_entry = get(
                before_profile,
                label,
                (multiplicity=0, schmidt_weight=0.0),
            )
            after_entry = get(
                after_profile,
                label,
                (multiplicity=0, schmidt_weight=0.0),
            )
            push!(
                rows,
                (;
                    cut,
                    qn_label=label,
                    before_multiplicity=before_entry.multiplicity,
                    after_multiplicity=after_entry.multiplicity,
                    multiplicity_delta=
                        after_entry.multiplicity - before_entry.multiplicity,
                    before_schmidt_weight=before_entry.schmidt_weight,
                    after_schmidt_weight=after_entry.schmidt_weight,
                    schmidt_weight_delta=
                        after_entry.schmidt_weight - before_entry.schmidt_weight,
                ),
            )
        end
    end
    return rows
end

function local_observables(psi, hamiltonian)
    period = nsites(psi)
    energy_terms = real.(expect(psi, hamiltonian))
    length(energy_terms) == period ||
        error("expected $period energy terms, got $(length(energy_terms))")
    entropy = entanglement_observables(psi)
    magnetization_z = [real(expect(psi, "Sz", site)) for site in 1:period]
    return (;
        energy_density=sum(energy_terms) / period,
        energy_terms=Float64.(energy_terms),
        energy_term_std=std(Float64.(energy_terms)),
        entropy,
        magnetization_z,
        maxlinkdim=maxlinkdim(psi),
    )
end
