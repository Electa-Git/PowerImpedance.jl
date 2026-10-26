module PowerFlowStartTests
using PowerImpedance, Test
const PI = PowerImpedance
const NB = PI.NetworkBuilder
include("pscad/fixtures.jl")

function model(data, builder)
    refs = [PI._PMACDC.add_ref_dcgrid!, PI._PMACDC.ref_add_pst!,
        PI._PMACDC.ref_add_sssc!, PI._PMACDC.ref_add_flex_load!,
        PI._PMACDC.ref_add_gendc!, PI._PMACDC.ref_add_im!]
    PI._PM.instantiate_model(data, PI._PM.ACPPowerModel, builder;
        ref_extensions = refs)
end

@testset "Converter apparent-current start" begin
    state = PSCADFixtures.tlc_network(false)
    data, _, _ = convert(state, PI.PMACDC)
    converter = only(values(data["convdc"]))
    converter["P_g"] = -3.2e-6
    converter["Q_g"] = 0.02
    for build in (pm -> NB.build_acdcpf(pm, (;)),)
        pm = model(data, build)
        id = only(PI._PM.ids(pm, :convdc))
        voltage = data["bus"][string(converter["busac_i"])]["vm"]
        current = PI.JuMP.start_value(PI._PM.var(pm, :iconv_ac, id))
        @test current ≈ sqrt(converter["P_g"]^2 + converter["Q_g"]^2) / voltage
        @test current >= 0.02 / voltage
    end
end

@testset "Converged primal starts and changed targets" begin
    let network = PSCADFixtures.tlc_network(false)
        flow() = compute(PowerFlowProblem(network), ACDCPowerFlow()).result
        first_result = flow()
        start = network.powerflow_start
        @test first_result["termination_status"] == PI.MOI.LOCALLY_SOLVED
        @test !isempty(start.primal)
        primal = copy(start.primal)
        # Every variable receives the previous converged value, including the
        # unreported DC current and converter firing angle.
        data, _, mapping = convert(network, PI.PMACDC)
        pm = model(data, pm -> NB.build_acdcpf(pm, (;)))
        NB._initialize_power_flow!(pm.model, start)
        @test all(v -> PI.JuMP.start_value(v) == primal[PI.JuMP.name(v)],
            PI.JuMP.all_variables(pm.model))
        # Changing the power target must still change the solved power.
        element = network.elements[:DUT]
        network.elements = merge(network.elements, (; DUT = withinputs(element;
            outerActive = (p_ref = 60.0 / bases(element).S,),
            outerReactive = (q_ref = 15.0 / bases(element).S,))))
        second_result = flow()
        converter = only(values(second_result["solution"]["convdc"]))
        @test second_result["termination_status"] == PI.MOI.LOCALLY_SOLVED
        @test -1000converter["pgrid"] ≈ 60.0 atol = 0.01
        @test -1000converter["qgrid"] ≈ 15.0 atol = 0.01

        # Reversed DC branch endpoints change topology despite unchanged component IDs and
        # variable names; a retained solution from that topology cannot supply a warm
        # start.
        changed, _, changed_mapping = convert(network, PI.PMACDC)
        changed_mapping = (changed_mapping, collect(network.topology.connections))
        branch = only(values(changed["branchdc"]))
        branch["fbusdc"], branch["tbusdc"] = branch["tbusdc"], branch["fbusdc"]
        NB._prepare_power_flow_start!(start, changed, changed_mapping)
        @test isempty(start.primal)
        cold = model(changed, pm -> NB.build_acdcpf(pm, (;)))
        defaults = PI.JuMP.start_value.(PI.JuMP.all_variables(cold.model))
        NB._initialize_power_flow!(cold.model, start)
        @test isequal(defaults, PI.JuMP.start_value.(PI.JuMP.all_variables(cold.model)))
    end
end
@testset "Induction-machine incidence invalidates the stored point" begin
    voltage = 220 / sqrt(3)
    elements = (;
        source = ac_source(v = voltage * sqrt(2), p = -500),
        machine = inductionmachine(mech = MechanicalIM(T_0 = 0.9, A = 0.0,
            B = 0.0, C = 1.0, m = 0), elec = ElectricalIM(r_s = 0.01)),
        branch = impedance(z = 0.01, conductors = 3))
    rows = (
        NB.Bus(:machine_; ports = ((:machine, :ac), (:branch, :side1))),
        NB.Bus(:grid_; ports = ((:branch, :side2), (:source, :ac)), domain = ACDQ),
    )
    state = NB.define(elements, rows; options = (; voltageBase = voltage,
        power_flow = (; is_bounded = (; bus_voltage = true))))
    flow = compute(PowerFlowProblem(state), ACDCPowerFlow())
    @test flow.result["termination_status"] == PI.MOI.LOCALLY_SOLVED
    start = state.powerflow_start
    @test !isempty(start.primal)
    snapshot = deepcopy(start.topology)
    connections = state.topology.connections
    for i in eachindex(connections.component)
        connections.component[i] === :machine || continue
        source_row = only(findall(j -> connections.component[j] === :source &&
            connections.terminal[j] == connections.terminal[i],
            eachindex(connections.component)))
        connections.net[i] = connections.net[source_row]
        connections.bus[i] = connections.bus[source_row]
    end
    changed, _, mapping = convert(state, PI.PMACDC)
    @test mapping == flow.elem2comp
    @test only(values(changed["im"]))["im_bus"] !=
          only(values(flow.data["im"]))["im_bus"]
    @test isequal(start.topology, snapshot)
    NB._prepare_power_flow_start!(start, changed,
        (mapping, collect(state.topology.connections)))
    @test isempty(start.primal)
end

end
