### The theorem

Bayes' theorem updates a prior belief with new evidence:

**P(disease | positive) = P(positive | disease) × P(disease) / P(positive)**

The denominator expands to: P(positive | disease)·P(disease) + P(positive | no disease)·P(no disease).

### The example

Take a disease affecting **1 in 1,000** people. The test catches 100% of true cases (sensitivity = 1.0) and has a **5% false positive rate**. You test positive — what's the chance you actually have it?

- Out of 1,000 people, **1** has the disease and tests positive.
- Of the 999 healthy, 5% test positive: about **50** false positives.
- So 51 positives total, only 1 real → **P(disease | positive) ≈ 1/51 ≈ 2%**.

### Why it feels wrong

The base rate dominates. Even a positive result on a good test leaves you at ~2% because the disease is **rare** — the false positives from the huge healthy group swamp the single true case.

### The takeaway

A test's accuracy alone tells you little; you need the **prior probability**. Same test in a high-risk group (say 1 in 10) gives a positive result a ~69% chance of being real.