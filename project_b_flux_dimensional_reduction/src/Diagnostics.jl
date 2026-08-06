function relative_jump(a::Real, b::Real; floor::Real=1e-12)
    return abs(Float64(b) - Float64(a)) / max(abs(Float64(a)), abs(Float64(b)), Float64(floor))
end

"""
Rank adjacent scan intervals for possible basin changes.

This is deliberately a warning system, not a phase classifier. A point is
unusable for physics whenever its VUMPS residual exceeds the requested
tolerance, irrespective of this score.
"""
function diagnose_series(
    theta_over_pi::AbstractVector{<:Real};
    energy_density::AbstractVector{<:Real},
    mean_entropy::AbstractVector{<:Real},
    leading_inverse_xi::AbstractVector{<:Real},
    energy_term_std::AbstractVector{<:Real},
    residual::AbstractVector{<:Real}=fill(NaN, length(theta_over_pi)),
    residual_tolerance::Real=NaN,
)
    n = length(theta_over_pi)
    all(length(values) == n for values in (
        energy_density,
        mean_entropy,
        leading_inverse_xi,
        energy_term_std,
        residual,
    )) || throw(DimensionMismatch("all diagnostic series must have equal length"))
    rows = NamedTuple[]
    for i in 1:(n - 1)
        entropy_jump = abs(Float64(mean_entropy[i + 1]) - Float64(mean_entropy[i]))
        inverse_xi_jump = abs(Float64(leading_inverse_xi[i + 1]) - Float64(leading_inverse_xi[i]))
        dispersion_ratio = Float64(energy_term_std[i + 1]) / max(Float64(energy_term_std[i]), eps())
        residual_ratio = isfinite(residual_tolerance) && residual_tolerance > 0 ?
            max(Float64(residual[i]), Float64(residual[i + 1])) / residual_tolerance : NaN
        score = entropy_jump / 0.1 + inverse_xi_jump / 0.1
        isfinite(dispersion_ratio) && dispersion_ratio > 0 &&
            (score += abs(log10(dispersion_ratio)))
        isfinite(residual_ratio) && residual_ratio > 1 &&
            (score += log10(residual_ratio))
        push!(
            rows,
            (;
                left_theta_over_pi=Float64(theta_over_pi[i]),
                right_theta_over_pi=Float64(theta_over_pi[i + 1]),
                energy_jump=Float64(energy_density[i + 1]) - Float64(energy_density[i]),
                entropy_jump,
                inverse_xi_jump,
                energy_term_std_ratio=dispersion_ratio,
                residual_ratio,
                score,
            ),
        )
    end
    return sort(rows; by=row -> row.score, rev=true)
end

function parse_vumps_log(path::AbstractString)
    isfile(path) || error("VUMPS log does not exist: $path")
    rows = Dict{Int,Dict{Symbol,Any}}()
    current_step = nothing
    for line in eachline(path)
        step_match = match(r"Flux step (\d+) / (\d+): theta/pi = ([^ ]+)", line)
        if step_match !== nothing
            current_step = parse(Int, step_match.captures[1])
            rows[current_step] = Dict{Symbol,Any}(
                :theta_over_pi => parse(Float64, step_match.captures[3]),
                :residuals => Float64[],
                :tolerance => NaN,
                :energy_density => NaN,
                :mean_entropy => NaN,
            )
            continue
        end
        current_step === nothing && continue
        residual_match = match(r"ϵᵖʳᵉˢ = ([0-9.eE+\-]+), tol = ([0-9.eE+\-]+)", line)
        if residual_match !== nothing
            push!(rows[current_step][:residuals], parse(Float64, residual_match.captures[1]))
            rows[current_step][:tolerance] = parse(Float64, residual_match.captures[2])
        end
        energy_match = match(r"energy density = ([0-9.eE+\-]+)", line)
        energy_match !== nothing &&
            (rows[current_step][:energy_density] = parse(Float64, energy_match.captures[1]))
        entropy_match = match(r"mean entanglement entropy = ([0-9.eE+\-]+)", line)
        entropy_match !== nothing &&
            (rows[current_step][:mean_entropy] = parse(Float64, entropy_match.captures[1]))
    end
    return [
        (;
            step,
            theta_over_pi=rows[step][:theta_over_pi],
            residuals=copy(rows[step][:residuals]),
            last_residual=isempty(rows[step][:residuals]) ? NaN : last(rows[step][:residuals]),
            minimum_residual=isempty(rows[step][:residuals]) ? NaN : minimum(rows[step][:residuals]),
            tolerance=rows[step][:tolerance],
            energy_density=rows[step][:energy_density],
            mean_entropy=rows[step][:mean_entropy],
        ) for step in sort!(collect(keys(rows)))
    ]
end

function diagnose_legacy_file(
    path::AbstractString;
    log_rows::AbstractVector=NamedTuple[],
)
    isfile(path) || error("legacy HDF5 file does not exist: $path")
    return h5open(path, "r") do file
        planned_theta = haskey(file, "fluxes_over_pi") ?
            Float64.(vec(read(file, "fluxes_over_pi"))) : Float64.(vec(read(file, "fluxes"))) ./ pi
        inverse_xi = Float64.(read(file, "transfer_inverse_xi"))
        npoints = size(inverse_xi, 2)
        theta = planned_theta[1:npoints]
        energy_density = Float64.(vec(read(file, "energy_densities")))[1:npoints]
        entropies = Float64.(read(file, "entropies"))[:, 1:npoints]
        energy_terms = Float64.(read(file, "energy_terms"))[:, 1:npoints]
        mean_entropy = vec(mean(entropies; dims=1))
        energy_term_std = [std(energy_terms[:, column]) for column in 1:npoints]
        leading_inverse_xi = vec(inverse_xi[2, 1:npoints])
        labels = haskey(file, "transfer_flux_labels") ?
            unique(String.(vec(read(file, "transfer_flux_labels")))) : String[]
        residual_tolerance = haskey(file, "vumps_tol") ? Float64(read(file, "vumps_tol")) : NaN
        residual = fill(NaN, npoints)
        for row in log_rows
            index = findfirst(value -> isapprox(value, row.theta_over_pi; atol=1e-12, rtol=0), theta)
            index !== nothing && (residual[index] = row.last_residual)
            isfinite(row.tolerance) && (residual_tolerance = row.tolerance)
        end
        intervals = diagnose_series(
            theta;
            energy_density,
            mean_entropy,
            leading_inverse_xi,
            energy_term_std,
            residual,
            residual_tolerance,
        )
        circumference = Int(read(file, "C"))
        shift = Int(read(file, "yc_shift"))
        geometry = YCGeometry(circumference, shift)
        return (;
            path,
            geometry,
            planned_points=length(planned_theta),
            completed_points=npoints,
            completed_theta_maximum=maximum(theta),
            predicted_crossing_over_pi=predicted_crossing_over_pi(geometry),
            maxdim=Int(read(file, "maxdim")),
            theta,
            energy_density,
            mean_entropy,
            energy_term_std,
            leading_inverse_xi,
            residual,
            residual_tolerance,
            labels,
            contains_physical_sz1=any(label -> occursin("Sz\",2", label), labels),
            contains_state=haskey(file, "psi"),
            intervals,
        )
    end
end
