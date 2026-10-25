# # Deterministic and uncertain impedance studies

using PowerImpedance
using Measurements

const NB = PowerImpedance.NetworkBuilder

# A Gridspace owns the network constructor and its parameter axes. Product
# composition enumerates the deterministic impedance values below.

function impedance_space(axis)
    elements = (
        branch = impedance(Grid; z = axis, conductors = 1),
        shunt = impedance(z = 20.0, conductors = 1)
    )
    connections = (
        NetworkBuilder.Bus(:bus; ports = ((:branch, :side1), (:shunt, :side1))),
        NetworkBuilder.Bus(:gnd; ports = ((:branch, :side2), (:shunt, :side2)))
    )
    return NB.define(elements, connections)
end

deterministic_space = impedance_space(Grid([8.0, 10.0]))
deterministic_problems = PowerImpedanceProblem(
    deterministic_space;
    nodes = [:bus],
    frequency_range = (1.0, 1e3, 40)
)
deterministic = compute(
    ParametricProblem(deterministic_problems),
    Combinatorial(NodalImpedance())
)

response_shapes = size.(getproperty.(deterministic.values, :response))

# Measurements remain outside the scalar solver. Monte Carlo draws one numeric
# network realization for each trial and retains the completed responses needed
# by later plotting recipes.

uncertain_space = impedance_space(Grid(10.0, 5.0; key = :branch_impedance))
uncertain_problems = PowerImpedanceProblem(
    uncertain_space;
    nodes = [:bus],
    frequency_range = (1.0, 1e3, 40)
)
uncertain = compute(
    ParametricProblem(uncertain_problems),
    MonteCarlo(NodalImpedance(); trials = 1000, seed = 2026)
)

(;
    trials = uncertain.stats.n,
    retained_plot_groups = length(uncertain.details.plot_data.values),
    raw_samples = uncertain.details.samples
)

# `LinearError` is the first-order alternative for supported frequency-response
# paths. It returns a distinct result type and preserves Measurements covariance.

linearized = compute(
    ParametricProblem(uncertain_problems),
    LinearError(NodalImpedance())
)

only(linearized.values).response[1, 1, 1]
