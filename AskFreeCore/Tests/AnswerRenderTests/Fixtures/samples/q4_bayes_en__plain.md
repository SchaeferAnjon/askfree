# Bayes' Theorem Explained with a Medical Test

## The Formula

$$P(D \mid T^+) = \frac{P(T^+ \mid D) \cdot P(D)}{P(T^+)}$$

Where:
- $P(D \mid T^+)$ = probability you have the disease **given** a positive test (the "posterior")
- $P(T^+ \mid D)$ = probability of a positive test **given** you have the disease (test **sensitivity**)
- $P(D)$ = **prior** probability of the disease in the population
- $P(T^+)$ = overall probability of a positive test

The denominator expands to:

$$P(T^+) = P(T^+ \mid D)\,P(D) + P(T^+ \mid \text{no } D)\,P(\text{no } D)$$

The second term is where the **false positive rate** enters.

## The Example

Suppose:

| Quantity | Value |
|---|---|
| Disease prevalence (prior) | $P(D) = 1\% = 0.01$ |
| Test sensitivity | $P(T^+ \mid D) = 99\%$ |
| **False positive rate** | $P(T^+ \mid \text{no } D) = 5\%$ |

You test positive. What's the chance you actually have the disease?

## Step 1: Overall probability of a positive test

- True positives: $0.99 \times 0.01 = 0.0099$
- False positives: $0.05 \times 0.99 = 0.0495$

$$P(T^+) = 0.0099 + 0.0495 = 0.0594$$

## Step 2: Apply Bayes

$$P(D \mid T^+) = \frac{0.0099}{0.0594} \approx 0.167$$

## The Surprising Result

**A positive test means only about a 16.7% chance you have the disease** — roughly 1 in 6.

## Why Is This Counterintuitive?

Think in counts per 10,000 people:

- **100** have the disease → 99 test positive (true positives)
- **9,900** don't → 495 test positive (false positives)

So of **594 positive tests**, only **99** are real. The false positives (495) vastly outnumber the true positives because the disease is rare — even though the test is 95% specific, it's applied to a huge healthy population.

## Key Takeaways

1. **Base rates matter enormously.** A "99% accurate" test on a rare disease produces mostly false alarms.
2. **The false positive rate interacts with prevalence.** Lower prevalence → lower posterior probability after a positive test.
3. **Bayes updates belief with evidence.** The prior (1%) is revised upward to 16.7% — a big jump, but still far from certainty.
4. **Practical implication:** confirmatory testing is essential. If a second independent test is also positive, the posterior from the first (16.7%) becomes the new prior, and the probability jumps dramatically (to roughly 80% with the same test characteristics).