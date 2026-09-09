module RoundTripMomentum
wrap(k)=mod(k+pi,2pi)-pi
"""Uniform-gauge YC8-1 period-2 mapping; theta_over_pi is dimensionless.
A transfer mode of physical spin charge q picks up q times the gauge shift."""
function momentum(k,theta_over_pi,q)
    all(isfinite,(k,theta_over_pi,q)) || error("nonfinite momentum input")
    (;two_k1=wrap(k+2q*pi*theta_over_pi/8),k2=wrap(4k))
end
end
