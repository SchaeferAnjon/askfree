For a 2×2 matrix \(A=\begin{pmatrix}a&b\\c&d\end{pmatrix}\), solve the characteristic equation:

\[
\det(A-\lambda I)=\lambda^2-(a+d)\lambda+(ad-bc)=0
\]

Then use the quadratic formula:

\[
\lambda=\frac{(a+d)\pm\sqrt{(a+d)^2-4(ad-bc)}}{2}
\]

### Example
Take \(A=\begin{pmatrix}4&1\\2&3\end{pmatrix}\).

1. **Trace**: \(a+d=7\)
2. **Determinant**: \(ad-bc=12-2=10\)
3. Characteristic equation: \(\lambda^2-7\lambda+10=0\)
4. Factor: \((\lambda-5)(\lambda-2)=0\)

So the eigenvalues are **\(\lambda=5\)** and **\(\lambda=2\)**.

Quick check: plug \(\lambda=5\) into \(A-\lambda I\) and confirm the rows are dependent (here \(\begin{pmatrix}-1&1\\2&-2\end{pmatrix}\), second row is \(-2\times\) first).