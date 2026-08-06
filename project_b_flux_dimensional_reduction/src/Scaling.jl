"""Adjacent-point estimates c_eff = 6 Delta S / Delta log(xi)."""
function local_central_charges(
    bond_dimensions::AbstractVector{<:Integer},
    entropies::AbstractVector{<:Real},
    correlation_lengths::AbstractVector{<:Real},
)
    n = length(bond_dimensions)
    length(entropies) == n == length(correlation_lengths) ||
        throw(DimensionMismatch("chi, entropy, and xi arrays must have equal length"))
    order = sortperm(bond_dimensions)
    chis = Int.(bond_dimensions[order])
    S = Float64.(entropies[order])
    xi = Float64.(correlation_lengths[order])
    rows = NamedTuple[]
    for i in 1:(n - 1)
        valid = isfinite(S[i]) && isfinite(S[i + 1]) && isfinite(xi[i]) &&
            isfinite(xi[i + 1]) && xi[i] > 0 && xi[i + 1] > 0 && xi[i + 1] != xi[i]
        c_eff = valid ? 6 * (S[i + 1] - S[i]) / (log(xi[i + 1]) - log(xi[i])) : NaN
        push!(
            rows,
            (;
                chi_low=chis[i],
                chi_high=chis[i + 1],
                entropy_low=S[i],
                entropy_high=S[i + 1],
                xi_low=xi[i],
                xi_high=xi[i + 1],
                c_eff,
            ),
        )
    end
    return rows
end

"""Least-squares fit of S = (c/6) log(xi) + intercept."""
function fit_central_charge(
    entropies::AbstractVector{<:Real},
    correlation_lengths::AbstractVector{<:Real},
)
    length(entropies) == length(correlation_lengths) ||
        throw(DimensionMismatch("entropy and xi arrays must have equal length"))
    keep = [
        isfinite(entropies[i]) && isfinite(correlation_lengths[i]) && correlation_lengths[i] > 0 for
        i in eachindex(entropies)
    ]
    count(keep) >= 3 || throw(ArgumentError("at least three finite points are required"))
    x = log.(Float64.(correlation_lengths[keep]))
    y = Float64.(entropies[keep])
    xbar = mean(x)
    ybar = mean(y)
    denominator = sum(abs2, x .- xbar)
    denominator > 0 || throw(ArgumentError("correlation lengths do not span a fit window"))
    slope = sum((x .- xbar) .* (y .- ybar)) / denominator
    intercept = ybar - slope * xbar
    predictions = intercept .+ slope .* x
    residual_sum_squares = sum(abs2, y .- predictions)
    total_sum_squares = sum(abs2, y .- ybar)
    r_squared = iszero(total_sum_squares) ? 1.0 : 1 - residual_sum_squares / total_sum_squares
    slope_standard_error = sqrt(residual_sum_squares / (length(x) - 2) / denominator)
    return (;
        central_charge=6 * slope,
        central_charge_standard_error=6 * slope_standard_error,
        intercept,
        r_squared,
        npoints=length(x),
        min_xi=minimum(exp.(x)),
        max_xi=maximum(exp.(x)),
    )
end

