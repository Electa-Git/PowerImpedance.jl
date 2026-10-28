# # Getting started: a single-machine infinite-bus system
#
# This example connects a synchronous machine to an ideal infinite bus through
# a three-phase impedance. It calculates the operating point and displays the
# network, then plots the driving-point impedance and generalized Nyquist
# response at the machine bus.

using PowerImpedance
using PowerImpedance.NetworkBuilder: Bus, define
using GraphMakie
using CairoMakie

# ## Define the machine, infinite bus, and line
#
# Machine power-flow setpoints use per-unit values on the machine base. The
# source voltage and the network base follow the package's phase-voltage base.

voltage_base = 220 / sqrt(3)
machine = synchronousmachine(
    S_base = 1000.0,
    Vᵃᶜ_base = 220.0,
    powerflow = (p = 0.5, q = 0.0, v = 1.0),
)

elements = (
    ; machine,
    infinite_bus = ac_source(v = voltage_base),
    line = impedance(z = 0.01 + 0.1im, conductors = 3),
)

# The machine and infinite bus connect to opposite ends of the line. The AC
# buses use d/q coordinates for analysis.

connections = (
    Bus(:machine_bus; ports = ((:machine, :ac), (:line, :side1)), domain = ACDQ),
    Bus(:infinite_bus; ports = ((:line, :side2), (:infinite_bus, :ac)), domain = ACDQ),
)

network = define(
    elements,
    connections;
    options = (; voltageBase = voltage_base),
)

# ## Inspect the network and calculate its operating point
#
# The diagram shows the two buses and the connected machine, line, and source.

diagram_view = diagram(network; interactive = false)
diagram_view.figure

# Power flow supplies the steady-state terminal values used to linearize the
# machine. Linearization then produces the frequency-domain network model.

power_flow = compute(PowerFlowProblem(network), ACDCPowerFlow())
linearized = compute(
    LinearizationProblem(network, power_flow),
    AdmittanceLinearization(),
)

# ## Calculate impedance and stability responses
#
# The same frequency range and machine-bus nodes are used for both responses.

response_problem = PowerImpedanceProblem(
    linearized.network_model;
    nodes = [:machine_busd, :machine_busq],
    frequency_range = (1.0, 1000.0, 300),
)

impedance_response = compute(response_problem, NodalImpedance())
loop_gain = compute(response_problem, LoopGain())
nyquist = compute(StabilityProblem(loop_gain), GeneralizedNyquist())

# ## Plot the results
#
# The impedance plot shows the machine-bus driving-point response. The Nyquist
# plot shows the generalized eigenloci for the calculated loop gain.

impedance_plot = only(PowerImpedance.plot(impedance_response; display_plot = false))
impedance_plot.figure

nyquist_plot = only(PowerImpedance.plot(nyquist; display_plot = false))
nyquist_plot.figure

# Continue with [component definitions](../network.md),
# [power-flow initialization](../initialization.md), and
# [impedance and stability analysis](../results.md).
