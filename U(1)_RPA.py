import numpy as np
import matplotlib.pyplot as plt

# ----------------------------
# PI-FLUX MEAN-FIELD H(k): SI Eq. (3)-(4)
# ----------------------------

def M_k(k1, k2):
    """
    2x2 sublattice matrix M_k from SI Eq. (4).
    """
    M_AA = 2.0 * np.cos(k2)
    M_BB = -M_AA
    M_AB = 1.0 + np.exp(-1j * k1) + np.exp(1j * (k2 - k1)) - np.exp(-1j * k2)
    return np.array([[M_AA, M_AB],
                     [np.conjugate(M_AB), M_BB]], dtype=complex)

def precompute_bands(Nk, t):
    """
    Diagonalize the spinless 2x2 problem on a uniform grid k1,k2 in [-pi, pi).
    Returns:
      kvals: 1D array of grid values (length Nk)
      eps:   (Nk, Nk, 2)
      vec:   (Nk, Nk, 2, 2)  (band index, sublattice component)
    """
    kvals = np.linspace(-np.pi, np.pi, Nk, endpoint=False)
    eps = np.zeros((Nk, Nk, 2), dtype=float)
    vec = np.zeros((Nk, Nk, 2, 2), dtype=complex)

    for i, k1 in enumerate(kvals):
        for j, k2 in enumerate(kvals):
            H2 = t * M_k(k1, k2)  # overall sign convention won't affect half-filled bubble shape
            w, v = np.linalg.eigh(H2)  # columns are eigenvectors
            eps[i, j, :] = w
            vec[i, j, :, :] = v.T

    return kvals, eps, vec

# ----------------------------
# J_q MATRIX: SI Eq. (27)-(28)
# ----------------------------

def J_matrix(q1, q2, J1, J2):
    J_AA = 2 * J1 * np.cos(q2) + 2 * J2 * np.cos(q1 - q2)
    J_AB = (
        J1 * (1 + np.exp(-1j * q1) + np.exp(1j * (q2 - q1)) + np.exp(-1j * q2))
        + J2 * (np.exp(1j * q2) + np.exp(1j * (2 * q2 - q1)) + np.exp(-1j * (q1 + q2)) + np.exp(-2j * q2))
    )
    return np.array([[J_AA, J_AB],
                     [np.conjugate(J_AB), J_AA]], dtype=complex)

# ----------------------------
# Physical contraction vector R_q: SI Eq. (17)-(18)
# ----------------------------

def R_vec(q1):
    return np.array([1.0, np.exp(-1j * q1 / 2.0)], dtype=complex)
    # return np.array([1.0, 1.0], dtype=complex)

# ----------------------------
# Grid / snapping utilities (THIS IS THE FIX)
# ----------------------------

def wrap_to_pi(x):
    return (x + np.pi) % (2 * np.pi) - np.pi

def shift_from_q(q, Nk):
    """
    Convert a real q in [-pi,pi) into an integer shift s such that q ~ s * dk.
    IMPORTANT: s is a SHIFT, not an index.
    """
    dk = 2 * np.pi / Nk
    qw = wrap_to_pi(q)
    s = int(np.rint(qw / dk))

    # wrap s into [-Nk/2, Nk/2)
    s = s % Nk
    if s >= Nk // 2:
        s -= Nk
    return s

def q_from_shift(s, Nk):
    dk = 2 * np.pi / Nk
    return s * dk

# ----------------------------
# Fermi occupation (T=0 default)
# ----------------------------

def fermi_occ(eps, mu=0.0, T=0.0):
    if T <= 0.0:
        return (eps < mu).astype(float)
    x = (eps - mu) / T
    x = np.clip(x, -60.0, 60.0)
    return 1.0 / (np.exp(x) + 1.0)

# ----------------------------
# Bubble chi0^{XY}(q,w): SI Eq. (23)-(24)
#
# We compute the spinless band part (2 bands) and include the spin trace:
# longitudinal sigma^z gives a factor of 2 from spin up/down.
# So prefactor is -1/(2N_kpoints) instead of -1/(4N_kpoints) for the 4-band sum.
# This does not change the dispersion, only an overall scale.
# ----------------------------

def bubble_chi0_matrix_shift(s1, s2, omegas, eps, vec, eta=0.03, T=0.0, mu=0.0):
    """
    Return chi0(omega): (Nw, 2, 2) in sublattice basis (A,B).
    """
    Nk = eps.shape[0]
    Ktot = Nk * Nk
    nb = 2

    eps_k = eps.reshape(Ktot, nb)         # (K,2)
    vec_k = vec.reshape(Ktot, nb, nb)     # (K,2,2)

    # shift k -> k+q using integer shifts
    ii = np.repeat(np.arange(Nk), Nk)
    jj = np.tile(np.arange(Nk), Nk)
    ii_q = (ii + s1) % Nk
    jj_q = (jj + s2) % Nk
    lin_q = ii_q * Nk + jj_q

    eps_kq = eps_k[lin_q, :]      # (K,2)
    vec_kq = vec_k[lin_q, :, :]   # (K,2,2)

    # Sublattice projectors in the 2x2 basis:
    P_A = np.array([[1.0, 0.0],
                    [0.0, 0.0]], dtype=complex)
    P_B = np.array([[0.0, 0.0],
                    [0.0, 1.0]], dtype=complex)

    # U_X^{mn}(k,q) = <m,k| P_X |n,k+q>
    U_A = np.einsum("kma,ab,knb->kmn", np.conjugate(vec_k), P_A, vec_kq)  # (K,2,2)
    U_B = np.einsum("kma,ab,knb->kmn", np.conjugate(vec_k), P_B, vec_kq)

    n_k = fermi_occ(eps_k, mu=mu, T=T)
    n_kq = fermi_occ(eps_kq, mu=mu, T=T)

    dE = eps_k[:, :, None] - eps_kq[:, None, :]   # (K,2,2)
    dn = n_k[:, :, None] - n_kq[:, None, :]       # (K,2,2)

    W_AA = dn * U_A * np.conjugate(U_A)
    W_AB = dn * U_A * np.conjugate(U_B)
    W_BA = dn * U_B * np.conjugate(U_A)
    W_BB = dn * U_B * np.conjugate(U_B)

    # spin factor 2 folded in:
    pref = -1.0 / (2.0 * Ktot)

    chi0_w = np.zeros((len(omegas), 2, 2), dtype=complex)
    for iw, w in enumerate(omegas):
        denom = (w + dE + 1j * eta)
        chi0_w[iw, 0, 0] = pref * np.sum(W_AA / denom)
        chi0_w[iw, 0, 1] = pref * np.sum(W_AB / denom)
        chi0_w[iw, 1, 0] = pref * np.sum(W_BA / denom)
        chi0_w[iw, 1, 1] = pref * np.sum(W_BB / denom)

    return chi0_w

# ----------------------------
# RPA susceptibility: SI Eq. (36)
# ----------------------------

def rpa_chi(chi0, Jq):
    I = np.eye(2, dtype=complex)
    return chi0 @ np.linalg.inv(I + 2.0 * (Jq @ chi0))

# ----------------------------
# Path construction
# ----------------------------

def build_path(points_k12, n_per_segment):
    pts = []
    ticks = [0]
    for (a1, a2), (b1, b2) in zip(points_k12[:-1], points_k12[1:]):
        for s in range(n_per_segment):
            u = s / float(n_per_segment)
            pts.append((a1 * (1 - u) + b1 * u, a2 * (1 - u) + b2 * u))
        ticks.append(len(pts))
    pts.append(points_k12[-1])
    return np.array(pts), ticks

# ----------------------------
# Main driver: compute S0 and/or S_RPA on a path
# ----------------------------

def compute_S_on_path(path, omegas, eps, vec, Nk, J1, J2, eta=0.03):
    Nq = path.shape[0]
    Nw = len(omegas)

    S = np.zeros((Nq, Nw), dtype=float)
    S_rpa = np.zeros((Nq, Nw), dtype=float)

    I2 = np.eye(2, dtype=complex)

    for iq, (q1, q2) in enumerate(path):
        s1 = shift_from_q(q1, Nk)
        s2 = shift_from_q(q2, Nk)

        chi0_w = bubble_chi0_matrix_shift(s1, s2, omegas, eps, vec, eta=eta)  # (Nw,2,2)

        Jq = J_matrix(q1, q2, J1=J1, J2=J2)   # (2,2)
        R  = R_vec(q1)                        # (2,)

        # S0 for all omegas at once
        S[iq, :] = np.imag(np.einsum("a,wab,b->w", np.conjugate(R), chi0_w, R))

        # RPA for all omegas at once (batched 2x2 inverses)
        M = I2[None, :, :] + 2.0 * (Jq @ chi0_w)          # (Nw,2,2)
        chi_rpa_w = chi0_w @ np.linalg.inv(M)             # (Nw,2,2)

        S_rpa[iq, :] = np.imag(np.einsum("a,wab,b->w", np.conjugate(R), chi_rpa_w, R))

    return S, S_rpa

def plot_intensity(S, omegas, ticks, labels, title, vmax=10.0, rescale_to_vmax=True):
    """
    The paper's figures use a 0..10-ish colorbar. Our normalization may differ
    by an overall constant, so we optionally rescale for visual comparison.
    """
    Splot = np.copy(S)
    Splot[Splot < 0] = 0.0

    if rescale_to_vmax:
        # robust scale: map 99.5 percentile to vmax
        p = np.quantile(Splot, 0.995)
        if p > 0:
            Splot *= (vmax / p)

    plt.figure(figsize=(10, 4))
    plt.imshow(
        Splot.T,
        origin="lower",
        aspect="auto",
        extent=[0, Splot.shape[0] - 1, omegas[0], omegas[-1]],
        vmin=0.0,
        vmax=vmax,
    )
    plt.colorbar()
    plt.xticks(ticks, labels)
    plt.xlabel("q-path index")
    plt.ylabel("omega / J1")
    plt.title(title)
    plt.tight_layout()

if __name__ == "__main__":
    # Parameters (Fig. 2 top panel uses J2/J1 = 0.09 and t/J1 = 0.395)
    J1 = 1.0
    J2 = 0.09
    t  = 0.395

    Nk = 100
    eta = 0.03
    w_max = 2.6
    Nw = 240
    omegas = np.linspace(0.0, w_max, Nw)

    # Precompute bands
    kvals, eps, vec = precompute_bands(Nk=Nk, t=t)

    # High-symmetry path (M-Y-G-X-K-M'-X-Y)
    pts = [
        (0.0, np.pi),           # M
        (0.0, np.pi / 2.0),     # Y
        (0.0, 0.0),             # Gamma
        (4*np.pi/3, 1*np.pi/3), # X (K'/2 instead of K/2==K)
        (8*np.pi/3, 2*np.pi/3), # K (= K')
        (2*np.pi, np.pi),   # M'
        (4*np.pi/3, 1*np.pi/3), # X
        (np.pi, 0.0),     # Y
    ]
    # pts = [
    # (0.0, np.pi),              # M
    # (0.0, np.pi/2.0),          # Y
    # (0.0, 0.0),                # Gamma
    # (np.pi, 0.0),              # X
    # (2*np.pi/3, 2*np.pi/3),    # K
    # (np.pi, np.pi/2.0),        # M'
    # (np.pi, 0.0),              # X
    # (0.0, np.pi/2.0),          # Y
    # ]
    labels = ["M", "Y", "Gamma", "X", "K", "M'", "X", "Y"]
    path, ticks = build_path(pts, n_per_segment=30)

    S0, S_rpa = compute_S_on_path(path, omegas, eps, vec, Nk, J1, J2, eta=eta)

    # 1) Free fermion (compare to their Fig. 5)
    plot_intensity(S0, omegas, ticks, labels, title="Free fermion structure factor (chi0)")

    # 2) RPA (compare to their Fig. 2)
    plot_intensity(S_rpa, omegas, ticks, labels, title=f"RPA structure factor, J2/J1={J2:.3f}, t/J1={t:.3f}, Nk={Nk}, eta={eta:.3f}")

    plt.show()