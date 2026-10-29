### The formula

\[
P(D\mid +)=\frac{P(+\mid D)\,P(D)}{P(+\mid D)\,P(D)+P(+\mid \neg D)\,P(\neg D)}
\]

- **Prior** \(P(D)\): how common the disease is before testing.
- **Sensitivity** \(P(+\mid D)\): chance a sick person tests positive.
- **False positive rate** \(P(+\mid \neg D)\): chance a healthy person tests positive — here **5%**.
- **Posterior** \(P(D\mid +)\): probability you actually have it given a positive result.

### The example

Say the disease affects **1 in 1,000** people, and the test catches **99%** of true cases.

Out of 100,000 people:

1. **100** have the disease; about **99** test positive.
2. **99,900** are healthy; 5% of them — about **4,995** — test positive falsely.
3. Total positives ≈ **5,094**, of which only **99** are real.

\[
P(D\mid +)=\frac{0.99\times 0.001}{0.99\times 0.001+0.05\times 0.999}\approx 0.019
\]

So a positive result means only about a **2%** chance of having the disease — the false positives from the huge healthy group swamp the true positives.

### The takeaway

The base rate dominates. A "95% accurate" test can still leave you very likely healthy after a positive, when the disease is rare. Repeat testing or a more specific test raises the posterior sharply.