For a 2×2 matrix, eigenvalues come from **det(A − λI) = 0**, which gives the characteristic equation λ² − (trace)λ + (determinant) = 0. Solve that quadratic with the formula λ = [tr ± √(tr² − 4·det)] / 2.

### Example
Take A = [[4, 1], [2, 3]].

1. **Trace** = 4 + 3 = 7; **determinant** = 4·3 − 1·2 = 10.
2. Characteristic equation: λ² − 7λ + 10 = 0.
3. Factor: (λ − 5)(λ − 2) = 0, so **λ = 5 and λ = 2**.

Check: A − 5I = [[−1, 1], [2, −2]] is singular, and A − 2I = [[2, 1], [2, 1]] is singular — both confirm the values.

If the discriminant tr² − 4·det is **negative**, the eigenvalues are a complex conjugate pair; if it's **zero**, you get one repeated eigenvalue.