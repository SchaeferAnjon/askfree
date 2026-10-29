# Maxwell's Equations (Differential Form)

## 1. Gauss's Law
$$\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0}$$

**Meaning:** Electric charges are the source of electric field lines. The divergence of the electric field at any point is proportional to the charge density there. Field lines begin on positive charges and end on negative charges.

## 2. Gauss's Law for Magnetism
$$\nabla \cdot \mathbf{B} = 0$$

**Meaning:** There are no magnetic monopoles. Magnetic field lines always form closed loops — they never begin or end at a point. Whatever magnetic flux enters a region must leave it.

## 3. Faraday's Law of Induction
$$\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t}$$

**Meaning:** A time-varying magnetic field induces a circulating electric field. This is the principle behind electric generators and transformers. The minus sign (Lenz's law) reflects that the induced field opposes the change that produced it.

## 4. Ampère–Maxwell Law
$$\nabla \times \mathbf{B} = \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}$$

**Meaning:** Magnetic fields are produced by two things: (a) electric currents $\mathbf{J}$, and (b) a time-varying electric field (the "displacement current" term). Maxwell's addition of the displacement current was crucial — it made the equations consistent and predicted electromagnetic waves.

---

## Key Symbols
| Symbol | Meaning |
|--------|---------|
| $\mathbf{E}$ | Electric field |
| $\mathbf{B}$ | Magnetic field |
| $\rho$ | Electric charge density |
| $\mathbf{J}$ | Electric current density |
| $\varepsilon_0$ | Vacuum permittivity |
| $\mu_0$ | Vacuum permeability |
| $\nabla \cdot$ | Divergence operator |
| $\nabla \times$ | Curl operator |

## In Matter (macroscopic form)
When working inside materials, the equations are often written with auxiliary fields:
- $\nabla \cdot \mathbf{D} = \rho_f$
- $\nabla \cdot \mathbf{B} = 0$
- $\nabla \times \mathbf{E} = -\partial \mathbf{B}/\partial t$
- $\nabla \times \mathbf{H} = \mathbf{J}_f + \partial \mathbf{D}/\partial t$

where $\mathbf{D} = \varepsilon_0\mathbf{E} + \mathbf{P}$ and $\mathbf{H} = \mathbf{B}/\mu_0 - \mathbf{M}$, and the subscript $f$ denotes "free" charge/current.

Together these four equations (plus the Lorentz force law) form the complete classical description of electricity, magnetism, and light.