# # Connection DSL
#
# `NetworkBuilder` connects named component ports with `Bus` and `Net`.
# A `Bus` joins complete ports and creates one net per electrical coordinate.
# A `Net` joins individual terminals with explicit names. Both declarations
# retain the order of their ports or terminals in the constructed topology.
#
# - `Bus(name; ports, domain)` takes ordered `(component, port)` pairs;
# - `Net(name; terminals, domain)` takes ordered `(component, port, terminal)`
#   triples.
#
# The component name is its key in the element named tuple. Port names are
# `side1` and `side2` for two-port passives, `ac` for AC sources and machines,
# `dc` for DC sources, and `ac` and `dc` for converters.
#
# An AC bus uses d/q coordinates when a connected port uses `ACDQ`, or when
# `domain = ACDQ` is declared. Otherwise it uses a/b/c coordinates. A scalar
# passive inherits its connected domain and otherwise uses DC. Scalar d/q
# terminations can be used in frequency calculations. Use three-phase
# passives for power flow.

using PowerImpedance
using PowerImpedance.NetworkBuilder: Bus, Net, Grid, NetworkTopology, define, solve;

# ## Scalar DC network
#
# A one-conductor impedance has one terminal on each of its two ports.
# The explicit `:gnd` bus identifies the reference port.

dc_elements = (
    source = dc_source(v = 480.0),
    branch = impedance(z = 2.0, conductors = 1),
    load = impedance(z = 10.0, conductors = 1)
);

dc_connections = (
    Bus(:source_bus; ports = ((:source, :dc), (:branch, :side1))),
    Bus(:load_bus; ports = ((:branch, :side2), (:load, :side1))),
    Bus(:gnd; ports = ((:load, :side2),))
);

dc_network = define(dc_elements, dc_connections);
dc_network.topology.connections

# The ideal source has one external port. It therefore receives one connection;
# no source-to-ground row is part of `NetworkTopology`.
# During small-signal construction the ideal source terminal is placed in the
# grounded-node selection because an ideal voltage source is a short circuit
# for perturbations.

dc_solution = solve(dc_network);
dc_solution.operating_point

# ## Transformed AC coordinates and multiway nodes
#
# Three-phase passives declare `ACABC` ports. An `ACDQ` bus converts them to
# d and q coordinates. Each pair belongs to one AC power-flow bus, while the
# generated net names preserve the two small-signal coordinates.

ac_elements = (
    grid = ac_source(v = 220 * sqrt(2/3)),
    branch_1 = impedance(z = 0.2 + 0.8im, conductors = 3),
    branch_2 = impedance(z = 0.4 + 1.2im, conductors = 3)
);

ac_connections = (
    Bus(:bus_; ports = ((:grid, :ac), (:branch_1, :side1), (:branch_2, :side1)),
        domain = ACDQ),
    Bus(:remote_1_; ports = ((:branch_1, :side2),), domain = ACDQ),
    Bus(:remote_2_; ports = ((:branch_2, :side2),), domain = ACDQ)
);

ac_topology = NetworkTopology(ac_elements, ac_connections);
ac_topology.connections

# The first bus creates nets `:bus_d` and `:bus_q` shared by its three ports.
# `NetworkTopology` assigns bus indices independently in the AC and DC domains.

# ## Multiconductor lines
#
# A three-conductor line exposes terminals `a`, `b` and `c` on both ports.
# `Net` gives each terminal its own name. Mutual terms remain in the dense
# component matrices; the nets do not reduce the line to independent phases.

multiconductor_elements = (
    line = overhead_line(
        length = 1e3,
        conductors = Conductors(organization = :flat, nᵇ = 3)
    ),
);

multiconductor_connections = (
    Net(:sending_a; terminals = ((:line, :side1, :a),)),
    Net(:sending_b; terminals = ((:line, :side1, :b),)),
    Net(:sending_c; terminals = ((:line, :side1, :c),)),
    Net(:receiving_a; terminals = ((:line, :side2, :a),)),
    Net(:receiving_b; terminals = ((:line, :side2, :b),)),
    Net(:receiving_c; terminals = ((:line, :side2, :c),))
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
# imported black-box line data. Each bus uses d and q coordinates on the
# connected ports `side1` and `side2`.

passive_elements = (
    transformer = transformer(
        conductors = 3,
        n = 1.0,
        Rₚ = 0.1,
        Lₚ = 1e-3,
        Rₛ = 0.1,
        Lₛ = 1e-3
    ),
    overhead = overhead_line(
        length = 1e3,
        conductors = Conductors(organization = :flat, nᵇ = 3)
    ),
    cable = cable(
        length = 1e3,
        positions = [(-1.0, 1.0), (0.0, 1.0), (1.0, 1.0)],
        C1 = Conductor(rₒ = 0.01)
    ),
    blackbox_line = blackbox_line(data_type = :Ztool, n = 3)
);

passive_connections = (
    Bus(:p1_; ports = ((:transformer, :side1),), domain = ACDQ),
    Bus(:p2_; ports = ((:transformer, :side2), (:overhead, :side1)), domain = ACDQ),
    Bus(:p3_; ports = ((:overhead, :side2), (:cable, :side1)), domain = ACDQ),
    Bus(:p4_; ports = ((:cable, :side2), (:blackbox_line, :side1)), domain = ACDQ),
    Bus(:p5_; ports = ((:blackbox_line, :side2),), domain = ACDQ)
);

passive_topology = NetworkTopology(passive_elements, passive_connections);
passive_topology.connections

# ## Converter ports
#
# MMC, two-level, and black-box converter models have named `ac` and `dc`
# ports. The DC port has one differential terminal, labelled `dc`.
# The AC port uses d and q terminals in the synchronous frame.

delta_control = ΔdqControlGFL(
    outer_active = NoOuterActiveControl(),
    outer_reactive = NoOuterReactiveControl(),
    occ = NoInnerCurrentControl()
);

converter_elements = (
    dc_grid = dc_source(v = 480.0),
    ac_grid = ac_source(),
    mmc = mmc(
        sync = NoSynchronization(),
        delta_control = delta_control,
        sigma_control = ΣdqzControlTEC()
    ),
    tlc = tlc(),
    blackbox_converter = PowerImpedance.Blackbox_MMC()
);

converter_connections = (
    Bus(:dc_bus;
        ports = ((:dc_grid, :dc), (:mmc, :dc), (:tlc, :dc), (:blackbox_converter, :dc))),
    Bus(:ac_bus_;
        ports = ((:ac_grid, :ac), (:mmc, :ac), (:tlc, :ac), (:blackbox_converter, :ac)),
        domain = ACDQ)
);

converter_topology = NetworkTopology(converter_elements, converter_connections);
converter_topology.connections

# ## Synchronous and induction machines
#
# Machine models expose one AC port. Its d and q terminals share one bus.

machine_elements = (
    synchronous = synchronousmachine(),
    induction = inductionmachine()
);

machine_connections = (
    Bus(:machine_bus_; ports = ((:synchronous, :ac), (:induction, :ac)), domain = ACDQ),
);

machine_topology = NetworkTopology(machine_elements, machine_connections);
machine_topology.connections

# ## Disconnected elements and validation
#
# `exclude` omits selected components even when the topology mentions them.
# Other malformed declarations are rejected while the topology is constructed,
# before power flow or frequency evaluation begins.
disconnected = impedance(z = 5.0, conductors = 1);
disconnected_network = define(
    (; disconnected),
    (Bus(:ignored; ports = ((:disconnected, :side1),)),);
    exclude = (:disconnected,)
);
isempty(disconnected_network.topology.connections)

duplicate_terminal_error = try
    NetworkTopology(
        (branch = impedance(z = 2.0, conductors = 1),),
        (
            Bus(:first; ports = ((:branch, :side1),)),
            Bus(:second; ports = ((:branch, :side1),))
        )
    )
catch error
    error
end;
duplicate_terminal_error

# Validation also rejects unknown components, invalid port or terminal labels,
# and a net name shared between AC and DC terminals. Net names come from the
# declarations above.

# ## Deterministic parameter grids
#
# Only the parameters receiving `Grid` values vary. The topology remains
# ordinary fixed data for each stochastic study case.

grid_elements = (
    branch = impedance(
        Grid;
        z = Grid([1.0, 2.0, 5.0]),
        conductors = 1
    ),
    load = impedance(Grid; z = 10.0, conductors = 1)
);

grid_connections = (
    Bus(:bus; ports = ((:branch, :side1), (:load, :side1))),
    Bus(:gnd; ports = ((:branch, :side2), (:load, :side2)))
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
# LineCableModels interoperability is dormant until LineCableModels.jl is
# registered and restored as a PowerImpedance weak dependency.
# A phase-domain, per-metre `LineParameters` result then replaces only the line
# model definition; the topology is unchanged. The documentation environment
# does not install LineCableModels, so this executable pattern is shown without
# importing the optional package:
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
#     ),
# )
#
# line_connections = (
#     Bus(:sending_; ports = ((:line, :side1),), domain = ACDQ),
#     Bus(:receiving_; ports = ((:line, :side2),), domain = ACDQ),
# )
#
# line_space = define(line_elements, line_connections)
# ```
