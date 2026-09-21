const DiagramExtension = Base.get_extension(
    PowerImpedance,
    :PowerImpedanceGraphMakieExt
)

diagram_row(node, element, side, terminal) = (; node, element, side, terminal)

function diagram_hybrid_network()
    elements = (
        ac_grid = ac_source(pins = 3, transformation = true),
        ac_line = impedance(z = 0.2 + 0.8im, pins = 3, transformation = true),
        ac_parallel = impedance(z = 0.3 + 0.9im, pins = 3, transformation = true),
        converter = tlc(),
        dc_line = impedance(z = 1.0, pins = 1),
        dc_load = impedance(z = 10.0, pins = 1),
        ac_shunt = impedance(z = 20.0, pins = 3, transformation = true),
        machine = synchronousmachine()
    )
    connections = (
        diagram_row(:ac_1_d, :ac_grid, 1, 1),
        diagram_row(:ac_1_q, :ac_grid, 1, 2),
        diagram_row(:ac_1_d, :ac_line, 1, 1),
        diagram_row(:ac_1_q, :ac_line, 1, 2),
        diagram_row(:ac_2_d, :ac_line, 2, 1),
        diagram_row(:ac_2_q, :ac_line, 2, 2),
        diagram_row(:ac_1_d, :ac_parallel, 1, 1),
        diagram_row(:ac_1_q, :ac_parallel, 1, 2),
        diagram_row(:ac_2_d, :ac_parallel, 2, 1),
        diagram_row(:ac_2_q, :ac_parallel, 2, 2),
        diagram_row(:dc_1, :converter, 1, 1),
        diagram_row(:ac_2_d, :converter, 2, 1),
        diagram_row(:ac_2_q, :converter, 2, 2),
        diagram_row(:dc_1, :dc_line, 1, 1),
        diagram_row(:dc_2, :dc_line, 2, 1),
        diagram_row(:dc_2, :dc_load, 1, 1),
        diagram_row(:gnd_dc, :dc_load, 2, 1),
        diagram_row(:ac_2_d, :ac_shunt, 1, 1),
        diagram_row(:ac_2_q, :ac_shunt, 1, 2),
        diagram_row(:gnd_ac_d, :ac_shunt, 2, 1),
        diagram_row(:gnd_ac_q, :ac_shunt, 2, 2),
        diagram_row(:ac_2_d, :machine, 1, 1),
        diagram_row(:ac_2_q, :machine, 1, 2)
    )
    return PowerImpedance.NetworkBuilder.define(elements, connections)
end

function diagram_nodes2bus(network)
    mapping = Dict{Symbol, Tuple{Symbol, Int}}()
    for row in network.topology.connections
        bus_type = row.bus == 0 ? :ground : row.domain == 1 ? :ac : :dc
        mapping[row.node] = (bus_type, row.bus)
    end
    return mapping
end

function diagram_powerflow_fixture(network)
    data = Dict{String, Any}(
        "bus" => Dict(
            "1" => Dict{String, Any}("bus_i" => 1),
            "2" => Dict{String, Any}("bus_i" => 2)
        ),
        "busdc" => Dict(
            "1" => Dict{String, Any}("busdc_i" => 1),
            "2" => Dict{String, Any}("busdc_i" => 2)
        ),
        "gen" => Dict(
            "1" => Dict{String, Any}("gen_bus" => 1, "gen_status" => 1),
            "2" => Dict{String, Any}("gen_bus" => 2, "gen_status" => 1)
        ),
        "branch" => Dict(
            "1" => Dict{String, Any}(
                "f_bus" => 1,
                "t_bus" => 2,
                "br_status" => 1,
                "transformer" => false
            ),
            "2" => Dict{String, Any}(
                "f_bus" => 1,
                "t_bus" => 2,
                "br_status" => 0,
                "transformer" => false
            )
        ),
        "convdc" => Dict(
            "1" => Dict{String, Any}(
            "busac_i" => 2,
            "busdc_i" => 1,
            "status" => 1
        )
        ),
        "branchdc" => Dict(
            "1" => Dict{String, Any}(
                "fbusdc" => 1,
                "tbusdc" => 2,
                "status" => 1
            ),
            "2" => Dict{String, Any}(
                "fbusdc" => 2,
                "tbusdc" => 0,
                "status" => 1
            )
        ),
        "load" => Dict(
            "1" => Dict{String, Any}("load_bus" => 2, "status" => 1)
        )
    )
    solution = Dict{String, Any}(
        "bus" => Dict(
            "1" => Dict{String, Any}("vm" => 1.0, "va" => 0.0),
            "2" => Dict{String, Any}("vm" => 0.99, "va" => -0.01)
        ),
        "busdc" => Dict(
            "1" => Dict{String, Any}("Vdc" => 1.01),
            "2" => Dict{String, Any}("Vdc" => 0.98)
        ),
        "gen" => Dict(
            "1" => Dict{String, Any}("pg" => 0.1),
            "2" => Dict{String, Any}("pg" => 0.05)
        ),
        "branch" => Dict(
            "1" => Dict{String, Any}("pf" => 0.08),
            "2" => Dict{String, Any}("pf" => 0.02)
        ),
        "convdc" => Dict(
            "1" => Dict{String, Any}("pgrid" => -0.1, "pdc" => 0.1)
        ),
        "branchdc" => Dict(
            "1" => Dict{String, Any}("pf" => 0.1),
            "2" => Dict{String, Any}("pf" => 0.03)
        ),
        "load" => Dict("1" => Dict{String, Any}("qd" => 0.01))
    )
    elem2comp = Dict(
        :ac_grid => (pmtype = "gen", compkey = 1),
        :ac_line => (pmtype = "branch", compkey = 1),
        :ac_parallel => (pmtype = "branch", compkey = 2),
        :converter => (pmtype = "convdc", compkey = 1),
        :dc_line => (pmtype = "branchdc", compkey = 1),
        :dc_load => (pmtype = "branchdc", compkey = 2),
        :ac_shunt => (pmtype = "load", compkey = 1),
        :machine => (pmtype = "gen", compkey = 2)
    )
    return PowerFlowResult(
        PowerImpedance.NetworkBuilder.ACDCPowerFlow(),
        Dict{String, Any}("solution" => solution, "termination_status" => :fixture),
        data,
        diagram_nodes2bus(network),
        elem2comp,
        OperatingPoint(),
        (termination_status = :fixture,)
    )
end
