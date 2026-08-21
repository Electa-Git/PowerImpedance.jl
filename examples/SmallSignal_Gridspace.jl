# # Gridspace small-signal stability analysis

using PowerImpedance

const NB = PowerImpedance.NetworkBuilder

# The network declaration is lazy. Its uncertain branch is realized as an
# ordinary numeric component separately for each Monte Carlo trial.

elements = (
    branch=NB.impedance(z=Grid(2.0, 5.0; key=:branch_impedance), pins=1),
    shunt=NB.impedance(z=4.0, pins=1),
)
connections = (
    (node=:bus, element=:branch, side=1, terminal=1),
    (node=:bus, element=:shunt, side=1, terminal=1),
    (node=:gnd, element=:branch, side=2, terminal=1),
    (node=:gnd, element=:shunt, side=2, terminal=1),
)
network_space = NB.define(elements, connections)

# First complete the frequency-response calculations.

response_problems = PowerImpedanceProblem(
    network_space;
    nodes=[:bus],
    frequency_range=(1.0, 1e3, 80),
)
responses = compute(
    ParametricProblem(response_problems),
    MonteCarlo(LoopGain(); trials=200, seed=2026),
)

# `preprocess` is the explicit checkpoint between completed responses and the
# stability calculation. The second call reuses those exact trajectories.

stability_problem = preprocess(responses, GeneralizedNyquist())
stability = compute(
    stability_problem,
    MonteCarlo(GeneralizedNyquist(); seed=2026),
)

(;
    trials=stability.stats.n,
    failures=stability.details.failures.items,
    analysis=stability.details.categorical.analysis,
)

# Plot definitions consume the completed result without rerunning the analysis.
# Building the render definition does not load Makie.

render = PlotBuilder.make_render(
    NyquistPlotDefinition,
    stability;
    zoom=true,
    title="Uncertain loop gain",
)

length(render.figures)

# Load one Makie backend to create a `UIPlot` from the same result:
#
# ```julia
# using CairoMakie
# handle = plot(stability; zoom=true, display_plot=false)
# ```
