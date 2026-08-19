# # Deterministic and uncertain impedance studies

using PowerImpedance
using Measurements
using PowerImpedance.NetworkBuilder: Grid, define

# The positional `Grid` selects the lazy constructor. Each ordinary keyword
# value remains an atomic singleton axis.
# An explicit `Grid` creates the deterministic alternatives.
elements = (
    z1 = impedance(Grid; z = Grid([8.0, 10.0]), pins = 1),
    z2 = impedance(Grid; z = 20.0, pins = 1)
)

connections = (
    (node = :bus, element = :z1, side = 1, terminal = 1),
    (node = :bus, element = :z2, side = 1, terminal = 1),
    (node = :gnd, element = :z1, side = 2, terminal = 1),
    (node = :gnd, element = :z2, side = 2, terminal = 1),
)

deterministic_builders = define(elements, connections)
deterministic = determine_impedance(
    deterministic_builders;
    nets = [:bus],
    freq_range = (1.0, 1e3, 40)
)

# Measurements values are sampled before ordinary components are materialized.
uncertain_elements = merge(elements, (z1 = impedance(Grid; z = 10.0 ± 0.5, pins = 1),))
uncertain_builders = define(uncertain_elements, connections)
uncertain = determine_impedance(
    uncertain_builders;
    nets = [:bus],
    freq_range = (1.0, 1e3, 40),
    trials = 1000,
    distribution = :normal,
    seed = 2026
)

only(uncertain).impedance
only(uncertain).statistics
