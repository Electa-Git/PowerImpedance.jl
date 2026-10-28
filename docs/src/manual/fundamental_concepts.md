# Fundamental concepts

PowerImpedance builds frequency-domain models of electrical networks from
component models and their connections. This chapter summarizes the theory
needed to interpret that workflow. Constructors and supported options are in
the [component guides](../components.md) and [API reference](../reference.md).
Calculation procedures are in [network construction](../network.md) and
[impedance and stability analysis](../results.md).

## Impedance-based small-signal analysis

An operating point describes the steady electrical quantities around which a
nonlinear model is linearized. Linearization produces a small-signal model whose
frequency response describes how perturbations in terminal voltages and
currents interact. Interconnecting passive network responses with controlled
device responses makes it possible to study resonances and control interactions
over frequency. This is the basis for impedance and admittance methods used in
power-electronic systems [Middlebrook1978, WangBlaabjerg2019, BayoSalas2018](@cite).

The result depends on the selected operating point, port orientation, reference
frame, and frequency range. See [power-flow initialization](../initialization.md)
for operating-point choices and [analysis](../results.md) for result
interpretation.

## Ports and multiport representations

A component exposes electrical ports. At a port, voltage and current vectors
are related by a frequency-dependent model. An admittance representation writes
current as a function of voltage, \\(\mathbf I = \mathbf Y\mathbf V\\), and an
impedance representation writes voltage as a function of current,
\\(\mathbf V = \mathbf Z\mathbf I\\). These forms are useful when the relevant
matrix is finite and well-conditioned. A finite matrix in either form is
undefined for some ideal open or short circuit configurations.

For a component with input and output port groups, a chain (ABCD) representation
relates both groups:

```@raw html
\[
\begin{bmatrix}\mathbf V_p\\\mathbf I_p\end{bmatrix} =
\begin{bmatrix}\mathbf A&\mathbf B\\\mathbf C&\mathbf D\end{bmatrix}
\begin{bmatrix}\mathbf V_s\\\mathbf I_s\end{bmatrix}.
\]
```

The block dimensions follow the number of coordinates at each port group.
When compatible components are cascaded, their chain matrices multiply in
connection order. Other interconnections impose shared-voltage and
current-balance conditions. They cannot in general be represented by simple
matrix multiplication. PowerImpedance assembles the declared network and
component models for its calculations. Users connect named ports with
[`Bus` and `Net`](../network.md).

When an ABCD representation and the required inverses exist, a load with
admittance \\(\mathbf Y_t\\) at the output gives the input admittance

```@raw html
\[
\mathbf Y_{in} = (\mathbf C + \mathbf D\mathbf Y_t)
                 (\mathbf A + \mathbf B\mathbf Y_t)^{-1}.
\]
```

This expression assumes the displayed inverse exists and the current
directions match the chain-matrix convention. Singular or ideal cases require
an alternate formulation. See the [analysis API](../reference.md) for the
package's available nodal, edge, and loop-gain calculations.

## AC reference frames and domains

Three-phase electrical quantities may be represented in phase coordinates
(\\(abc\\)) or in a rotating direct-quadrature frame (\\(dq\\) or \\(dqz\\), depending on
the model). A frame transformation changes the coordinates used to describe
the same physical voltage and current. In a synchronous rotating frame, a
sinusoidal fundamental can appear constant at steady state. A frequency-domain
response in a rotating frame is interpreted relative to that frame's reference
frequency. Components specify compatible frames and coordinates at each port.
The [network guide](../network.md) describes supported bus domains.

AC and DC domains also have different coordinate meanings. A network may
include both, but only ports with compatible declared domains and coordinate
counts can be connected. Component guides document the domain and frame for
each supported model.

## Matrix reduction and coordinate changes

Eliminating internal variables from a linear multiport model produces an
equivalent model at its retained ports. For a partitioned linear system

```@raw html
\[
\begin{bmatrix} \mathbf M_{rr}&\mathbf M_{re}\\
                 \mathbf M_{er}&\mathbf M_{ee}\end{bmatrix}
\begin{bmatrix}\mathbf x_r\\\mathbf x_e\end{bmatrix} =
\begin{bmatrix}\mathbf b_r\\\mathbf b_e\end{bmatrix},
\]
```

if \\(\mathbf M_{ee}\\) is invertible, eliminating \\(\mathbf x_e\\) gives the
Schur-complement system

```@raw html
\[
(\mathbf M_{rr}-\mathbf M_{re}\mathbf M_{ee}^{-1}\mathbf M_{er})\mathbf x_r
=\mathbf b_r-\mathbf M_{re}\mathbf M_{ee}^{-1}\mathbf b_e.
\]
```

The result is equivalent at the retained variables under the stated
invertibility assumption. Coordinate transformations also preserve a
linear relation when applied consistently to its voltage and current
coordinates. Check the assumptions, orientation, and retained-port meaning for
each model before using its reduced relation.

### ABCD matrix reduction {#reduction_ABCD}

Reduction of a chain representation depends on the termination and on which
ports remain exposed. Reduction formulas depend on the termination and the
model's assumptions. Singular and ideal configurations require special care.
The equations above describe general linear
elimination. Consult the supported component model and API documentation for
its actual behavior.

### Admittance and ABCD representations {#transformation-y-abcd}

Admittance and chain representations encode the same terminal behavior when
the relevant block needed for conversion is invertible. Conversion formulas
can fail at open-circuit, short-circuit, or other singular conditions. Prefer
the package's documented model and analysis methods over manually converting
matrices unless those conditions have been checked.

## Component models and operating points

Component models capture the frequency-dependent electrical behavior that
matters to a study. Lumped impedances, transformers, lines, cables, sources,
machines, and converters have different assumptions and exposed ports. Their
Use the corresponding [component pages](../components.md) to check each
model's constructors, inputs, limits, and documented restrictions.

Nonlinear active models are typically linearized around an operating point.
The point may be calculated from a power-flow problem or supplied through a
supported initialization path. Changing the operating point can change the
linearized response. The [initialization guide](../initialization.md) explains
when to solve power flow and how to inspect solved terminal values. Exact
result fields and method signatures are in the [API reference](../reference.md).

## Historical source and attribution

This chapter was curated from the *Electromagnetic Stability Simulator,
Developing Guide* (17 March 2020), authored by Aleksandra Lekić and Philippe De
Rua under the supervision of Prof. Jef Beerten. The original manual and its
figures are available in [Simulator_tutorial.pdf](Simulator_tutorial.pdf).
The current chapter retains only general theory relevant to the present
package and does not assert that the historical implementation description
matches current internals.
