For a 2×2 matrix $A$, eigenvalues solve the characteristic equation:

$$\det(A - \lambda I) = 0$$

For $A = \begin{pmatrix} a & b \\ c & d \end{pmatrix}$, this becomes:

$$\lambda^2 - (a+d)\lambda + (ad - bc) = 0$$

So the **trace** $a+d$ is the sum of the eigenvalues, and the **determinant** $ad-bc$ is their product.

### Example

Take $A = \begin{pmatrix} 4 & 1 \\ 2 & 3 \end{pmatrix}$.

1. Trace $= 4+3 = 7$, determinant $= 4\cdot3 - 1\cdot2 = 10$.
2. Characteristic equation: $\lambda^2 - 7\lambda + 10 = 0$.
3. Factor: $(\lambda - 5)(\lambda - 2) = 0$.
4. Eigenvalues: $\lambda_1 = 5$, $\lambda_2 = 2$.

Check: $5 + 2 = 7$ (trace), $5 \cdot 2 = 10$ (determinant). ✓

If the quadratic doesn't factor nicely, use the quadratic formula: $\lambda = \frac{(a+d) \pm \sqrt{(a+d)^2 - 4(ad-bc)}}{2}$. A negative discriminant means **complex** eigenvalues.