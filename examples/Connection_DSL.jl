# # Connection DSL
#
# `NetworkBuilder` represents an electrical connection with one named row for
# each connected element terminal. The four input fields are:
#
# - `node`: the explicit network-node name;
# - `element`: the name of the element in the element named tuple;
# - `side`: the physical element side, numbered from 1;
# - `terminal`: the conductor or transformed coordinate on that side, numbered
#   from 1.
#
# Repeating a node name joins all listed terminals at one multiway node. Rows
# remain separate so their input order, terminal identity, and electrical
# domain can be inspected after construction.
#
# Sources, machines, converters, transformed components, and multiconductor
# components identify their AC or DC domain directly. A one-conductor passive
# element inherits a fixed domain through its connected nodes and otherwise
# retains the DC interpretation. Scalar passive d/q terminations are valid for
# frequency-domain calculations; use transformed three-phase elements when a
# power flow is required.

using PowerImpedance
using PowerImpedance.NetworkBuilder: Grid, NetworkTopology, define, solve;

# ## Scalar DC network
#
# A one-conductor impedance has one terminal on each of its two physical sides.
# The explicit `:gnd` node identifies the reference side.

dc_elements = (
    source = dc_source(setpoint = Setpoint(Vdc = 240.0)),
    branch = impedance(z = 2.0, pins = 1),
    load = impedance(z = 10.0, pins = 1)
);

dc_connections = (
    (node = :source_bus, element = :source, side = 1, terminal = 1),
    (node = :source_bus, element = :branch, side = 1, terminal = 1),
    (node = :load_bus, element = :branch, side = 2, terminal = 1),
    (node = :load_bus, element = :load, side = 1, terminal = 1),
    (node = :gnd, element = :load, side = 2, terminal = 1)
);

dc_network = define(dc_elements, dc_connections);
dc_network.topology.connections

# The ideal source has one physical external terminal. It therefore receives
# one row; no artificial source-to-ground row is part of `NetworkTopology`.
# During small-signal construction the ideal source terminal is placed in the
# grounded-node selection because an ideal voltage source is a short circuit
# for perturbations.

dc_solution = solve(dc_network);
dc_solution.powerflow

# ## Transformed AC coordinates and multiway nodes
#
# Three-phase elements with `transformation=true` expose d and q coordinates as
# terminals 1 and 2. Both belong to one AC power-flow bus, while their distinct
# node names preserve the two small-signal coordinates.

ac_elements = (
    grid = ac_source(
        setpoint = Setpoint(Vac = 220 / sqrt(3)),
        pins = 3,
        transformation = true
    ),
    branch_1 = impedance(
        z = 0.2 + 0.8im,
        pins = 3,
        transformation = true
    ),
    branch_2 = impedance(
        z = 0.4 + 1.2im,
        pins = 3,
        transformation = true
    )
);

ac_connections = (
    (node = :bus_d, element = :grid, side = 1, terminal = 1),
    (node = :bus_d, element = :branch_1, side = 1, terminal = 1),
    (node = :bus_d, element = :branch_2, side = 1, terminal = 1),
    (node = :bus_q, element = :grid, side = 1, terminal = 2),
    (node = :bus_q, element = :branch_1, side = 1, terminal = 2),
    (node = :bus_q, element = :branch_2, side = 1, terminal = 2),
    (node = :remote_1_d, element = :branch_1, side = 2, terminal = 1),
    (node = :remote_1_q, element = :branch_1, side = 2, terminal = 2),
    (node = :remote_2_d, element = :branch_2, side = 2, terminal = 1),
    (node = :remote_2_q, element = :branch_2, side = 2, terminal = 2)
);

ac_topology = NetworkTopology(ac_elements, ac_connections);
ac_topology.connections

# The first three rows share `:bus_d`, and the next three share `:bus_q`.
# `NetworkTopology` assigns bus indices independently in the AC and DC domains.

# ## Multiconductor lines
#
# Without a d/q transformation, a three-conductor line exposes terminals 1, 2,
# and 3 on both physical sides. Mutual terms remain in the dense component
# matrices; connection rows do not reduce the line to independent phases.

multiconductor_elements = (
    line = overhead_line(
    length = 1e3,
    conductors = Conductors(organization = :flat, nᵇ = 3)
),
);

multiconductor_connections = (
    (node = :sending_a, element = :line, side = 1, terminal = 1),
    (node = :sending_b, element = :line, side = 1, terminal = 2),
    (node = :sending_c, element = :line, side = 1, terminal = 3),
    (node = :receiving_a, element = :line, side = 2, terminal = 1),
    (node = :receiving_b, element = :line, side = 2, terminal = 2),
    (node = :receiving_c, element = :line, side = 2, terminal = 3)
);

multiconductor_topology = NetworkTopology(
    multiconductor_elements,
    multiconductor_connections
);
multiconductor_topology.connections

# ## Passive component families
#
# The following AC chain uses the same engineering parameters as the topology
# tests. It covers transformers, analytical overhead lines and cables, and
# imported black-box line data. Each transformed element has d and q terminals
# on sides 1 and 2.

passive_elements = (
    transformer = transformer(
        pins = 3,
        n = 1.0,
        Rₚ = 0.1,
        Lₚ = 1e-3,
        Rₛ = 0.1,
        Lₛ = 1e-3,
        transformation = true
    ),
    overhead = overhead_line(
        length = 1e3,
        conductors = Conductors(organization = :flat, nᵇ = 3),
        transformation = true
    ),
    cable = cable(
        length = 1e3,
        positions = [(-1.0, 1.0), (0.0, 1.0), (1.0, 1.0)],
        C1 = Conductor(rₒ = 0.01),
        transformation = true
    ),
    blackbox_line = blackbox_line(
        data_type = :Ztool,
        n = 3,
        transformation = true
    )
);

passive_connections = (
    (node = :p1_d, element = :transformer, side = 1, terminal = 1),
    (node = :p1_q, element = :transformer, side = 1, terminal = 2),
    (node = :p2_d, element = :transformer, side = 2, terminal = 1),
    (node = :p2_q, element = :transformer, side = 2, terminal = 2),
    (node = :p2_d, element = :overhead, side = 1, terminal = 1),
    (node = :p2_q, element = :overhead, side = 1, terminal = 2),
    (node = :p3_d, element = :overhead, side = 2, terminal = 1),
    (node = :p3_q, element = :overhead, side = 2, terminal = 2),
    (node = :p3_d, element = :cable, side = 1, terminal = 1),
    (node = :p3_q, element = :cable, side = 1, terminal = 2),
    (node = :p4_d, element = :cable, side = 2, terminal = 1),
    (node = :p4_q, element = :cable, side = 2, terminal = 2),
    (node = :p4_d, element = :blackbox_line, side = 1, terminal = 1),
    (node = :p4_q, element = :blackbox_line, side = 1, terminal = 2),
    (node = :p5_d, element = :blackbox_line, side = 2, terminal = 1),
    (node = :p5_q, element = :blackbox_line, side = 2, terminal = 2)
);

passive_topology = NetworkTopology(passive_elements, passive_connections);
passive_topology.connections

# ## Converter sides
#
# MMC, two-level, and black-box converter models use side 1 for DC and side 2
# for AC. The DC side has one terminal. A transformed AC side has d and q
# terminals. These definitions follow the same side ordering used by the
# validated PowerModelsACDC conversion.

delta_control = ΔdqControlGFL(
    outer_active = NoOuterActiveControl(),
    outer_reactive = NoOuterReactiveControl(),
    occ = NoInnerCurrentControl()
);

converter_elements = (
    dc_grid = dc_source(setpoint = Setpoint(Vdc = 240.0)),
    ac_grid = ac_source(pins = 3, transformation = true),
    mmc = mmc(
        sync = NoSynchronization(),
        delta_control = delta_control,
        sigma_control = ΣdqzControlTEC()
    ),
    tlc = tlc(),
    blackbox_converter = PowerImpedance.Element(
        input_pins = 1,
        output_pins = 2,
        element_model = PowerImpedance.Blackbox_MMC()
    )
);

converter_connections = (
    (node = :dc_bus, element = :dc_grid, side = 1, terminal = 1),
    (node = :dc_bus, element = :mmc, side = 1, terminal = 1),
    (node = :dc_bus, element = :tlc, side = 1, terminal = 1),
    (node = :dc_bus, element = :blackbox_converter, side = 1, terminal = 1),
    (node = :ac_bus_d, element = :ac_grid, side = 1, terminal = 1),
    (node = :ac_bus_d, element = :mmc, side = 2, terminal = 1),
    (node = :ac_bus_d, element = :tlc, side = 2, terminal = 1),
    (node = :ac_bus_d, element = :blackbox_converter, side = 2, terminal = 1),
    (node = :ac_bus_q, element = :ac_grid, side = 1, terminal = 2),
    (node = :ac_bus_q, element = :mmc, side = 2, terminal = 2),
    (node = :ac_bus_q, element = :tlc, side = 2, terminal = 2),
    (node = :ac_bus_q, element = :blackbox_converter, side = 2, terminal = 2)
);

converter_topology = NetworkTopology(converter_elements, converter_connections);
converter_topology.connections

# ## Synchronous and induction machines
#
# Machine models expose one physical AC side. Transformed d and q coordinates
# are terminals 1 and 2 on that side.

machine_elements = (
    synchronous = synchronousmachine(),
    induction = inductionmachine()
);

machine_connections = (
    (node = :machine_bus_d, element = :synchronous, side = 1, terminal = 1),
    (node = :machine_bus_q, element = :synchronous, side = 1, terminal = 2),
    (node = :machine_bus_d, element = :induction, side = 1, terminal = 1),
    (node = :machine_bus_q, element = :induction, side = 1, terminal = 2)
);

machine_topology = NetworkTopology(machine_elements, machine_connections);
machine_topology.connections

# ## Disconnected elements and validation
#
# An element constructed with `connection=false` is omitted even if supplied
# rows mention it. Other malformed rows are rejected while the topology is
# constructed, before power flow or frequency evaluation begins.

disconnected = impedance(z = 5.0, pins = 1);
disconnected.connection = false;
disconnected_network = define(
    (; disconnected),
    ((node = :ignored, element = :disconnected, side = 1, terminal = 1),)
);
isempty(disconnected_network.topology.connections)

duplicate_terminal_error = try
    NetworkTopology(
        (branch = impedance(z = 2.0, pins = 1),),
        (
            (node = :first, element = :branch, side = 1, terminal = 1),
            (node = :second, element = :branch, side = 1, terminal = 1)
        )
    )
catch error
    error
end;
duplicate_terminal_error

# Validation also rejects unknown elements, invalid side or terminal numbers,
# and a node name shared between AC and DC terminals. Nodes are never generated
# implicitly.

# ## Deterministic parameter grids
#
# Only the parameters receiving `Grid` values vary. The connection rows remain
# ordinary fixed data for each stochastic study case.

grid_elements = (
    branch = impedance(
        Grid;
        z = Grid([1.0, 2.0, 5.0]),
        pins = 1
    ),
    load = impedance(Grid; z = 10.0, pins = 1)
);

grid_connections = (
    (node = :bus, element = :branch, side = 1, terminal = 1),
    (node = :bus, element = :load, side = 1, terminal = 1),
    (node = :gnd, element = :branch, side = 2, terminal = 1),
    (node = :gnd, element = :load, side = 2, terminal = 1)
);

network_space = define(grid_elements, grid_connections);
length(network_space)

grid_problems = PowerImpedanceProblem(
    network_space;
    nodes = [:bus],
    frequency_range = (1.0, 1e3, 40)
);
grid_impedance = compute(
    ParametricProblem(grid_problems),
    Combinatorial(NodalImpedance())
);
grid_impedance

# ## Lines constructed from `LineParameters`
#
# Loading LineCableModels and Measurements activates the optional extension.
# A phase-domain, per-metre `LineParameters` result then replaces only the line
# model definition; the connection rows are unchanged. The documentation
# environment does not install LineCableModels, so this executable pattern is
# shown without importing the optional package:
#
# ```julia
# using LineCableModels
# using Measurements
#
# workspace, line_parameters = LineCableModels.compute!(problem, formulation)
#
# line_elements = (
#     line = cable(
#         Grid,
#         line_parameters;
#         length = Grid([50e3, 75e3, 100e3]),
#         transformation = true,
#     ),
# )
#
# line_connections = (
#     (node = :sending_d, element = :line, side = 1, terminal = 1),
#     (node = :sending_q, element = :line, side = 1, terminal = 2),
#     (node = :receiving_d, element = :line, side = 2, terminal = 1),
#     (node = :receiving_q, element = :line, side = 2, terminal = 2),
# )
#
# line_space = define(line_elements, line_connections)
# ```
