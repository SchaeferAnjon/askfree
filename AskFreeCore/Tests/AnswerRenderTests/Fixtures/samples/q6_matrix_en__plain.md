# Finding Eigenvalues of a 2×2 Matrix

## The Method

For a 2×2 matrix **A**, eigenvalues λ satisfy:

$$A\vec{v} = \lambda \vec{v}$$

which rearranges to:

$$(A - \lambda I)\vec{v} = 0$$

For a nonzero eigenvector to exist, the **characteristic equation** must hold:

$$\det(A - \lambda I) = 0$$

For a matrix $A = \begin{pmatrix} a & b \\ c & d \end{pmatrix}$, this gives:

$$\det\begin{pmatrix} a-\lambda & b \\ c & d-\lambda \end{pmatrix} = (a-\lambda)(d-\lambda) - bc = 0$$

Expanding:

$$\lambda^2 - (a+d)\lambda + (ad - bc) = 0$$

So the two eigenvalues are:

$$\lambda = \frac{(a+d) \pm \sqrt{(a+d)^2 - 4(ad-bc)}}{2}$$

**Shortcut:** The sum of eigenvalues equals the **trace** (a+d), and the product equals the **determinant** (ad−bc).

---

## Example

Let 

$$A = \begin{pmatrix} 4 & 1 \\ 2 & 3 \end{pmatrix}$$

**Step 1 — Set up the characteristic equation:**

$$\det\begin{pmatrix} 4-\lambda & 1 \\ 2 & 3-\lambda \end{pmatrix} = 0$$

**Step 2 — Expand:**

$$(4-\lambda)(3-\lambda) - (1)(2) = 0$$
$$12 - 4\lambda - 3\lambda + \lambda^2 - 2 = 0$$
$$\lambda^2 - 7\lambda + 10 = 0$$

**Step 3 — Solve:**

$$(\lambda - 5)(\lambda - 2) = 0$$

$$\boxed{\lambda_1 = 5, \quad \lambda_2 = 2}$$

**Check:** Trace = 4 + 3 = 7 = 5 + 2 ✓, Determinant = 12 − 2 = 10 = 5 × 2 ✓

---

## Quick Check of Eigenvectors (optional)

- For λ = 5: solve $(A - 5I)\vec{v} = 0$ → $\begin{pmatrix} -1 & 1 \\ 2 & -2 \end{pmatrix}\vec{v} = 0$ → $\vec{v} = \begin{pmatrix} 1 \\ 1 \end{pmatrix}$
- For λ = 2: solve $(A - 2I)\vec{v} = 0$ → $\begin{pmatrix} 2 & 1 \\ 2 & 1 \end{pmatrix}\vec{v} = 0$ → $\vec{v} = \begin{pmatrix} 1 \\ -2 \end{pmatrix}$

---

## Summary of Steps

1. Write $\det(A - \lambda I) = 0$
2. Expand to get $\lambda^2 - (\text{trace})\lambda + (\text{det}) = 0$
3. Solve the quadratic (use the quadratic formula if it doesn't factor nicely)
4. The roots are your eigenvalues

**Note:** If the discriminant $(a+d)^2 - 4(ad-bc)$ is negative, the eigenvalues are complex conjugates.