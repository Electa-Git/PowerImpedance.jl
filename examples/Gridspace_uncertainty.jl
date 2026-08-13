# # Deterministic and uncertain impedance studies

using PowerImpedanceACDC
using Measurements
using PowerImpedanceACDC.NetworkBuilder: ⟷

const NB = PowerImpedanceACDC.NetworkBuilder

# A shadow constructor turns each ordinary value into an atomic singleton axis.
# An explicit `Grid` creates the deterministic alternatives.
elements = (
    z1 = NB.impedance(z = NB.Grid([8.0, 10.0]), pins = 1),
    z2 = NB.impedance(z = 20.0, pins = 1),
)

connections = (
    NB.pin(:z1, 1, 1) ⟷ NB.pin(:z2, 1, 1) ⟷ :bus,
    NB.pin(:z1, 2, 1) ⟷ NB.pin(:z2, 2, 1) ⟷ :gnd,
)

deterministic_builders = NB.define(elements, connections)
deterministic = NB.determine_impedance(
    deterministic_builders;
    nets = [:bus],
    freq_range = (1.0, 1e3, 40),
)

# Measurements values are sampled before ordinary components are materialized.
uncertain_elements = merge(elements, (z1 = NB.impedance(z = 10.0 ± 0.5, pins = 1),))
uncertain_builders = NB.define(uncertain_elements, connections)
uncertain = NB.determine_impedance(
    uncertain_builders;
    nets = [:bus],
    freq_range = (1.0, 1e3, 40),
    trials = 1000,
    distribution = :normal,
    seed = 2026,
)

only(uncertain).impedance
only(uncertain).statistics

