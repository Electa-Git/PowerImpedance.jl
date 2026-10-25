module PowerFlowIdempotenceTests
using PowerImpedance, Test, LinearAlgebra
const PI = PowerImpedance
const NB = PI.NetworkBuilder
const PSC = PI.PSCAD
include("pscad/fixtures.jl")

function constraint_tolerance(options)
    attribute = PI.JuMP.MOI.RawOptimizerAttribute("constr_viol_tol")
    return last(only(filter(p -> first(p) == attribute,
        NB.powerflow_optimizer(options).params)))
end

include("parity/fixtures.jl")

function tlc_qv_fixture()
    state = PSCADFixtures.tlc_network(false)
    m = state.elements.DUT
    b = bases(m)
    reactive = OuterReactiveQControl(pi_ctrl = PIControl(Kp = 0.04, Ki = 40.0),
        support = VoltageSupportLag(K = 5.0, ωc = 2.0))
    converter = component(tlc(; m.elec, m.meas, m.sync, m.outerActive,
        outerReactive = reactive, m.innerVoltage, m.innerCurrent, m.mod,
        limits = limits(m));
        outerReactive = (q_ref = 20.0 / b.S,
            support = (v_ac_ref = (220sqrt(2 / 3)) / b.v_ac,)),
        powerflow = (v_dc = 640.0 / b.v_dc, p_dc = 70.0 / b.S))
    return NB.NetworkState(merge(state.elements, (; DUT = converter)),
        state.topology, state.options)
end

function consumer_values(net::NB.NetworkState, flow)
    model = NB.NetworkModel(net, flow.operating_point)
    converters = Dict()
    for (name, m) in pairs(net.elements)
        PI.is_converter(m) || continue
        point = flow.operating_point[name]
        inputs, sp = PI.pftoinputs(m, point)
        seed = PI.orderedinitialvalues(m; inputs, terminal_pu = sp)
        parameters = (; inputs = collect(values(inputs)), sp, m)
        f!(F, x, p) = PI._state_space!(F, x, p.inputs, p.sp, p.m, PI.Equil())
        solution = PI.solve(
            PI.NonlinearProblem(f!, collect(promote(values(seed)...)), parameters);
            maxiters = 20, abstol = 1e-6, reltol = 1e-6)
        @test PI.SciMLBase.successful_retcode(solution)
        residual = zeros(length(solution.u))
        f!(residual, solution.u, parameters)
        @test norm(residual, Inf) <= 1e-6
        @test sp.q_ac == -point.ac.q / m.elec.Sbase
        converters[name] = (; state = copy(solution.u), A = copy(m.cache.A),
            B = copy(m.cache.B), C = copy(m.cache.C), D = copy(m.cache.D),
            y = NB.get_y(model, name, ComplexF64.(2π * im .* [1.0, 100.0, 5000.0])))
    end
    omega, s = NB._frequency_axis((1.0, 5000.0, 3))
    y = NB.initY(model, s)
    fill!(y, model.element_admittances[model.active_elements], s)
    nodes = sort!(collect(keys(model.indices.nodes)); by = n -> model.indices.nodes[n])
    points = Dict(name => point for (name, point) in flow.operating_point.values
        if PI.is_converter(net.elements[name]))
    return (; converters, y, nodes, omega, points)
end

function check_powerflow(one, two, tolerance)
    @test keys(one) == keys(two)
    for group in keys(one)
        @test keys(one[group]) == keys(two[group])
        for id in keys(one[group]), field in keys(one[group][id])
            # PowerModelsACDC reports the LCC firing angle for every converter.
            # MMC/TLC set islcc=0, so phi is unused by their VSC equations.
            group == "convdc" && field == "phi" && continue
            group == "convdc" && field == "vaconv" && continue
            a, b = one[group][id][field], two[group][id][field]
            a isa Number && b isa Number || continue
            if group == "convdc" && field == "vmconv"
                a *= cis(one[group][id]["vaconv"])
                b *= cis(two[group][id]["vaconv"])
            end
            @testset "$group/$id/$field" begin
                @test abs(a - b) <= tolerance
            end
        end
    end
end

function check_setpoints(one, two, data, voltage_base, tolerance)
    @test keys(one) == keys(two)
    for name in keys(one)
        @test keys(one[name]) == keys(two[name])
        for port in keys(one[name]), field in fieldnames(typeof(one[name][port]))
            x, y = getfield(one[name][port], field), getfield(two[name][port], field)
            base = field in (:p, :q) ? data["baseMVA"] :
                   field === :v ? (port === :ac ? sqrt(2) : data["dcpol"]) *
                       voltage_base : 1.0
            @test abs(x - y) / base <= tolerance
        end
    end
end

@testset "P2P builder repeated calls and exported setpoints" begin
    fixture = ParityFixtures.P2PAlt
    state = NB.define(fixture.ohl_to_ugc(0.0), fixture.connections;
        options = fixture.builder_options)
    declared = map(inputvalues, state.elements)
    one = compute(PowerFlowProblem(state), ACDCPowerFlow())
    two = compute(PowerFlowProblem(state), ACDCPowerFlow())
    @test declared == map(inputvalues, state.elements)
    tolerance = constraint_tolerance(state.options)
    # A warm solve reoptimizes the converged point; compare using the same
    # physical tolerance as the converter repeats rather than exact rounding.
    check_powerflow(one.result["solution"], two.result["solution"], tolerance)
    @test keys(one.operating_point) == keys(two.operating_point)
    for name in keys(one.operating_point), port in keys(one.operating_point[name]),
            field in propertynames(one.operating_point[name][port])
        x = getproperty(one.operating_point[name][port], field)
        y = getproperty(two.operating_point[name][port], field)
        base = field in (:p, :q) ? one.data["baseMVA"] :
            field === :v ? (port === :ac ? sqrt(2) : one.data["dcpol"]) *
                state.options.voltageBase : 1.0
        @test abs(x - y) / base <= tolerance
    end
    a = PSC.netlist(state, one)
    b = PSC.netlist(state, two)
    @test keys(a.operating_point.branch_flows) == keys(b.operating_point.branch_flows)
    for name in keys(a.operating_point.branch_flows)
        x, y = a.operating_point.branch_flows[name], b.operating_point.branch_flows[name]
        @test keys(x) == keys(y)
        @test norm(collect(values(x)) - collect(values(y)), Inf) / one.data["baseMVA"] <= tolerance
    end
    check_setpoints(a.operating_point.values, b.operating_point.values,
        one.data, state.options.voltageBase, tolerance)
    @test keys(a.operating_point.bus_states) == keys(b.operating_point.bus_states)
    for key in keys(a.operating_point.bus_states)
        x, y = a.operating_point.bus_states[key], b.operating_point.bus_states[key]
        @test keys(x) == keys(y)
        for field in keys(x)
            if x[field] isa Number && y[field] isa Number
                @test abs(x[field] - y[field]) <= tolerance
            else
                @test isequal(x[field], y[field])
            end
        end
    end
    for n in (:c1, :c2)
        i = string(one.elem2comp[n].compkey)
        point = one.operating_point[n]
        @test point.ac.q ==
              one.result["solution"]["convdc"][i]["qgrid"] * one.data["baseMVA"]
        @test -point.ac.q > 1e-6
        e = only(filter(e -> e.name == n, a.elements))
        @test e.values == point
        @test PI.pftoinputs(e.model, e.values)[2].q_ac == -point.ac.q / e.model.elec.Sbase
    end
end


function pscad_export_after_explicit_solve(factories)
    @testset "PSCAD export after explicit power flow" begin
        if Base.get_extension(PI, :PowerImpedancePSCADExt) === nothing
            @test_skip false # Run with PythonCall for actual XML exports.
        else
            for factory in factories
                state = factory()
                tolerance = constraint_tolerance(state.options)
                fresh = deepcopy(state)
                solved = deepcopy(fresh)
                pf = compute(PowerFlowProblem(solved), ACDCPowerFlow())
                mktempdir() do directory
                    mkpath(joinpath(directory, "fresh"))
                    mkpath(joinpath(directory, "solved"))
                    mkpath(joinpath(directory, "reused"))
                    settings = PSC.SimulationSettings(source_ramp = 0.0)
                    a = PI.export_pscad(fresh; settings,
                        path = joinpath(directory, "fresh", "repeated.pscx"))
                    b = PI.export_pscad(solved; settings, powerflow = pf,
                        path = joinpath(directory, "solved", "repeated.pscx"))
                    c = PI.export_pscad(solved; settings,
                        path = joinpath(directory, "reused", "repeated.pscx"))
                    @test a.operating_point.branch_flows == b.operating_point.branch_flows
                    @test a.operating_point.values == b.operating_point.values
                    @test a.operating_point.bus_states == b.operating_point.bus_states
                    pc = Base.get_extension(PI, :PowerImpedancePSCADExt).PythonCall
                    etree = pc.pyimport("lxml.etree")
                    # Project revision timestamps are metadata. Compare settings
                    # and every definition's electrical/control parameters.
                    parameters(path) = [(pc.pyconvert(String, p.get("name")),
                                            pc.pyconvert(String, p.get("value")))
                                        for p in etree.parse(path).getroot().xpath(
                        "./definitions//paramlist/param | ./paramlist[@name='Settings']/param[@name!='revisor']")]
                    @test parameters(a.project_path) == parameters(b.project_path)
                    for (x, y) in zip(a.netlist.elements, b.netlist.elements)
                        x.model isa Union{PI.MMC, PI.TLC} || continue
                        @test PSC.converter_equilibrium(x) == PSC.converter_equilibrium(y)
                        reused = only(filter(e -> e.name == x.name, c.netlist.elements))
                        first_q = PSC.converter_equilibrium(x).terminal_pu.q_ac
                        second_q = PSC.converter_equilibrium(reused).terminal_pu.q_ac
                        system_base = a.operating_point.bases.S_MVA
                        @test abs(first_q - second_q) <=
                              tolerance * system_base / x.model.elec.Sbase
                        @test abs(a.operating_point.branch_flows[x.name].qt -
                                  c.operating_point.branch_flows[x.name].qt) /
                              system_base <=
                              tolerance
                    end
                end
            end
        end
    end
end

function repeated_converter_solves(cases)
    @testset "Repeated converter power flow" begin
        # Both solves use the optimizer's default setting. A 1000 MVA system base
        # makes constr_viol_tol=1e-5 equivalent to 0.01 MVA (0.01 MW active or 0.01 MVAr
        # reactive), per equality. Q sign is ignored below the absolute noise threshold of
        # 1e-6 MVAr.
        q_sign_threshold = 1e-6
        for (label, factory) in cases
            @testset "$label" begin
                state = factory()
                tolerance = constraint_tolerance(state.options)
                declared = map(inputvalues, state.elements)
                flow = compute(PowerFlowProblem(state), ACDCPowerFlow())
                result, data = flow.result, flow.data
                mapping = flow.elem2comp
                one = consumer_values(state, flow)
                system_base = data["baseMVA"]
                for (name, c) in one.converters
                    record = result["solution"]["convdc"][string(mapping[name].compkey)]
                    @test one.points[name].ac.q == record["qgrid"] * 1e9 / 1e6
                end
                # Builder compute leaves its input definition unchanged. Reusing
                # solved output setpoints would construct a different problem.
                flow = compute(PowerFlowProblem(state), ACDCPowerFlow())
                second = flow.result
                two = consumer_values(state, flow)
                check_powerflow(result["solution"], second["solution"], tolerance)
                @test declared == map(inputvalues, state.elements)
                for name in keys(two.points)
                    @test two.points[name] == flow.operating_point[name]
                end
                @test one.nodes == two.nodes
                @test one.omega == two.omega
                @test norm(one.y - two.y) / norm(one.y) <= tolerance
                for (name, a) in one.converters
                    b = two.converters[name]
                    for field in (:state, :A, :B, :C, :D, :y)
                        x, y = getproperty(a, field), getproperty(b, field)
                        @test norm(x - y, Inf) <= tolerance * max(norm(x, Inf), 1.0)
                    end
                    for port in keys(one.points[name]),
                            field in fieldnames(typeof(one.points[name][port]))
                        x, y = getfield(one.points[name][port], field),
                            getfield(two.points[name][port], field)
                        base = field in (:p, :q) ? system_base :
                            field === :v ? (port === :ac ? sqrt(2) : 2) *
                                state.options.voltageBase : 1.0
                        @test abs(x - y) / base <= tolerance
                    end
                    if min(abs(one.points[name].ac.q), abs(two.points[name].ac.q)) >=
                            q_sign_threshold
                        @test signbit(one.points[name].ac.q) ==
                            signbit(two.points[name].ac.q)
                    end
                end
                for (name, model) in pairs(state.elements)
                    PI.is_source(model) || continue
                    @test inputvalues(model) == declared[name]
                end
            end
        end
    end
end

pscad_export_after_explicit_solve((
    () -> PSCADFixtures.mmc_pq_network(),
    () -> PSCADFixtures.tlc_network(false)))

repeated_converter_solves((
    ("MMC PQ", PSCADFixtures.mmc_pq_network),
    ("TLC PQ", () -> PSCADFixtures.tlc_network(false)),
    ("TLC Q-V", tlc_qv_fixture),
    ("TLC Vdc", () -> PSCADFixtures.tlc_network(true))))
end
