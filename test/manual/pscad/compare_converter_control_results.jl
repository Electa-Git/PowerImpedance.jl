# Native CSV comparison against archived TSV references; never contacts the station.
using PowerImpedance, DelimitedFiles, LinearAlgebra
include("../../pscad/fixtures.jl")
const P = PowerImpedance.PSCAD
const INPUTS = "/tmp/pscad-converter-control-results"
const REFERENCES = "/tmp/pscad-converter-control-experiments"
const REPORT = mkpath("/tmp/pscad-converter-control-comparison")
BLAS.set_num_threads(1)

function retained_point(list, name)
    rows = Iterators.drop(readlines(joinpath(REFERENCES, name * "_reference.tsv")), 1)
    refs = Dict{Tuple{String, Symbol}, Float64}()
    for row in rows
        element, quantity, value, unit, index = split(row, '\t')
        parse(Int, index) == 0 &&
            (refs[(element, Symbol(quantity))] = parse(Float64, value))
    end
    # Rebuilding supplies topology and probe associations only. Numeric comparison
    # references come from the archived TSV, never from the reconstruction's solve.
    original = list.operating_point
    buses = Dict{P.BusKey, NamedTuple}()
    for bus in list.buses
        buses[bus.key] = (; vm_pu = refs[(bus.name, :vm)],
            va_rad = bus.kind == :dc ? nothing : refs[(bus.name, :angle)])
    end
    flows = Dict{Symbol, NamedTuple}()
    for (element, flow) in original.branch_flows
        fields = keys(flow)
        values = map(key -> refs[(string(element), key)], fields)
        flows[element] = NamedTuple{fields}(values)
    end
    point = P.OperatingPointRecord(
        buses, flows, original.values, original.slack_bus, original.bases)
    return point
end

function compare_case(name, network)
    println("Reading ", name)
    flush(stdout)
    pf = compute(PowerFlowProblem(network), ACDCPowerFlow())
    list = P.netlist(network, pf)
    mmc = startswith(name, "mmc_")
    ramp = name == "mmc_pq_default_ramp" || startswith(name, "tlc_vac") ?
           P.SimulationSettings().source_ramp : 0.0
    settings = P.SimulationSettings(simulation_time = 10.0, time_step = 10e-6,
        sample_step = mmc ? 250e-6 : 40e-6, source_ramp = ramp)
    plan = P.build_plan(list; name, settings,
        dc_reference = startswith(name, "mmc_vdc") ? :midpoint_resistors : :none)
    point = retained_point(list, name)
    list = P.Netlist(list.buses, list.elements, point, list.voltageBase, list.frequency)
    model = PSCADModel(joinpath(REFERENCES, name * ".pscx"), name, list, plan.probes,
        settings, point, (; source = :station_reference_tsv))
    samples, header = readdlm(joinpath(INPUTS, name * ".csv"), ',', Float64; header = true)
    header[1] == "time" || error("missing time column")
    length(unique(header)) == length(header) || error("duplicate CSV channel name")
    channels = PowerImpedance.OrderedDict(string(header[i]) => samples[:, i]
    for i in 2:length(header))
    result = PSCADResult(
        PSCADRun(), samples[:, 1], channels, plan.probes, settings, (;), (;))
    table = compare_operating_point(result, model)
    limit(q) = q in (:current_dc, :current_rms, :converter_dc_current_identity) ? 0.02 :
               q == :voltage_angle ? 1.0 :
               q in (
        :voltage_rms, :voltage_dc, :converter_p, :converter_q, :converter_arm_voltage) ?
               0.01 :
               error("unexpected comparison quantity: $q")
    ratios = [r.error / limit(r.quantity) for r in table]
    worst = table[argmax(ratios)]
    open(joinpath(REPORT, name * ".tsv"), "w") do io
        println(io, "quantity\tname\tpscad\treference\terror\ttolerance\tfraction_of_tolerance\tpass")
        for row in table
            println(io,
                join(
                    (row.quantity, row.name, row.pscad, row.powerflow, row.error,
                        limit(row.quantity), row.error / limit(row.quantity), row.within_tolerance),
                    '\t'))
        end
    end
    println(
        name, " ", all(table.within_tolerance) ? "PASS" : "FAIL", " rows=", length(table),
        " worst=", worst.quantity, "/", worst.name, " error=", worst.error,
        " tolerance=", limit(worst.quantity), " ratio=", maximum(ratios))
    return (project = name, pass = all(table.within_tolerance), rows = length(table),
        quantity = worst.quantity, probe = worst.name, error = worst.error,
        tolerance = limit(worst.quantity), fraction_of_tolerance = maximum(ratios))
end

summary = []
for (stem, factory) in (("mmc_vdc", PSCADFixtures.mmc_vdc_network),
    ("mmc_pf", PSCADFixtures.mmc_pf_network), ("mmc_qv", PSCADFixtures.mmc_qv_network),
    ("mmc_vac", PSCADFixtures.mmc_vac_network), ("tlc_vac", PSCADFixtures.tlc_vac_network))
    fixture = factory()
    for (suffix, network) in (("builder", fixture),)
        push!(summary, compare_case(stem * "_" * suffix, network))
    end
end
push!(summary, compare_case("mmc_pq_default_ramp", PSCADFixtures.mmc_pq_network()))
push!(summary, compare_case("tlc_case2_zero_ramp", PSCADFixtures.tlc_case2_network()))
open(joinpath(REPORT, "summary.tsv"), "w") do io
    println(io, join(keys(first(summary)), '\t'))
    for row in summary
        println(io, join(values(row), '\t'))
    end
end

all(row.pass for row in summary) || error("converter-control station operating-point comparison failed")
