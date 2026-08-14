```@meta
CurrentModule = PowerImpedance
```

# PowerImpedance.jl

PowerImpedance is a frequency-domain modelling and small-signal analysis
package for AC, DC, and hybrid power systems. It combines detailed passive and
active component models with multiport network assembly, AC/DC power-flow
initialization, impedance extraction, and stability-analysis tools.

## Capabilities

The package provides analytical models for:

- AC and DC voltage sources;
- lumped impedances and transformers;
- overhead lines and underground cables;
- modular multilevel and two-level converters;
- synchronous and induction machines; and
- black-box passive and converter frequency responses.

The resulting systems can be studied through driving-point and transfer
impedances, nodal and edge admittances, generalized Nyquist plots, Bode plots,
passivity, small-gain criteria, stability margins, unstable-frequency scans,
and eigenvalue-decomposition tools.

Gridspace extends the same physical constructors to deterministic parameter
sweeps and uncertainty quantification. It preserves the ordinary scalar API,
samples nonlinear components before solving, and repeats the power flow and
linearization whenever an active device, source, topology, or builder option
changes.

## Installation

Install the package from the Julia package manager:

```julia
pkg> add PowerImpedance
```

Then load it with:

```julia
using PowerImpedance
```

### Former package name

The package and module were formerly named `PowerImpedanceACDC`. The UUID is
unchanged. After importing the renamed package, the former module name remains
an exported alias, so existing qualified calls need no immediate rewrite:

```julia
using PowerImpedance

PowerImpedanceACDC.make_y_node === PowerImpedance.make_y_node
```

The source tree also retains a compatibility entry point for existing
manifests that already resolve `PowerImpedanceACDC` to this UUID. New
environments must add and import `PowerImpedance`, because Julia project
metadata cannot expose the same UUID under two package names.

Optional interoperability is activated by loading `Measurements` or
`LineCableModels` in the same environment. See [Package extensions](package_extensions.md)
for the supported combinations and data structures.

## Where to start

- [Introduction](introduction.md) explains the multiport ABCD representation
  and impedance-based stability workflow.
- [Network construction](network.md) covers the scalar and declarative
  NetworkBuilder interfaces.
- [Power-flow initialization](initialization.md) explains when operating
  points are computed or reused.
- [Impedance and stability analysis](results.md) introduces the downstream
  analysis tools and result forms.
- [Parametric and uncertainty studies](gridspace.md) documents deterministic
  grids, Monte Carlo studies, retained samples, and statistics.
- [Examples](examples/index.md) contains executable Literate tutorials.
- [API reference](reference.md) lists the public interfaces by module.

The theoretical background retained from the original package documentation
is cited through the project [bibliography](bibliography.md).
