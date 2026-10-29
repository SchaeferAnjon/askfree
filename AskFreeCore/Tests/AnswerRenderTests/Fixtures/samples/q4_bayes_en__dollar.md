### The formula

Bayes' theorem updates a prior belief with evidence:

$$P(D \mid +) = \frac{P(+ \mid D)\,P(D)}{P(+ \mid D)\,P(D) + P(+ \mid \lnot D)\,P(\lnot D)}$$

- $P(D)$ is the **prior**: how common the disease is before testing.
- $P(+ \mid D)$ is **sensitivity**: probability a sick person tests positive.
- $P(+ \mid \lnot D)$ is the **false positive rate** — here 0.05.
- $P(D \mid +)$ is the **posterior**: probability you actually have it given a positive result.

### The example

Take a disease with **1% prevalence**, and a test with 95% sensitivity and a 5% false positive rate. For 10,000 people:

1. 100 have the disease; 95 of them test positive (true positives).
2. 9,900 are healthy; 5% of them — 495 — test positive (false positives).
3. Total positives: 95 + 495 = 590.

So the posterior is:

$$P(D \mid +) = \frac{95}{590} \approx 0.161$$

A positive result means only about a **16%** chance of having the disease.

### Why it feels wrong

The intuition-killer is the **base rate**. False positives vastly outnumber true positives because the healthy group is 99× larger, so most positives are noise.

- Raise prevalence to 10% and the same test gives roughly **68%**.
- Cut the false positive rate to 1% and the 1% case jumps to about **49%**.

The test's accuracy didn't change — only the prior and the error rate did.