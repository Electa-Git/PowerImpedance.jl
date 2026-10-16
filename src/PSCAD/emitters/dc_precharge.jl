# A permanent DC source supplies its entire connected DC circuit. Shared
# ground and converter AC terminals do not connect separate DC circuits.
_sets_dc_voltage(::Any) = false
_sets_dc_voltage(m::PowerImpedance.TLC) = m.outerActive isa PowerImpedance.OuterActiveVdcControl
_sets_dc_voltage(m::PowerImpedance.MMC) = m.delta_control isa PowerImpedance.ΔdqControlGFL &&
    m.delta_control.outer_active isa PowerImpedance.OuterActiveVdcControl

function _dc_precharge_buses(netlist::Netlist)
    adjacency = Dict(b.key => BusKey[] for b in netlist.buses if b.kind == :dc)
    sources, controllers = Set{BusKey}(), Set{BusKey}()
    for e in netlist.elements
        keys = [t.bus for t in e.terminals if t.bus !== nothing && t.bus.domain == 2]
        for a in keys, b in keys
            a == b || push!(adjacency[a], b)
        end
        e.model isa PowerImpedance.Source && union!(sources, keys)
        _sets_dc_voltage(e.model) && union!(controllers, keys)
    end
    selected, visited = Set{BusKey}(), Set{BusKey}()
    for bus in netlist.buses
        bus.kind == :dc && !(bus.key in visited) || continue
        island, pending = Set{BusKey}(), [bus.key]
        while !isempty(pending)
            key = pop!(pending)
            key in island && continue
            push!(island, key)
            append!(pending, adjacency[key])
        end
        union!(visited, island)
        isempty(intersect(island, sources)) && !isempty(intersect(island, controllers)) &&
            union!(selected, island)
    end
    buses = filter(b -> b.key in selected, netlist.buses)
    for bus in buses
        bus.vm_pu !== nothing && isfinite(bus.vm_pu) && bus.vm_pu > 0 ||
            throw(ArgumentError("DC pre-charge at $(bus.name) requires positive solved pole voltages"))
    end
    return buses
end

function dc_precharge!(state::PlanState, bus::Bus, context)
    # The breaker command NAME=0 closes and NAME=1 opens. OPCUR=1 permits
    # opening at nonzero DC current, and RON=0 gives an ideal closed branch.
    state.layout.next = 6cld(state.layout.next, 6)
    x, y = allocate_cell!(state.layout)
    # The time-signal output stub extends 36 pixels above its origin, so
    # an extra row prevents intersection with the preceding row's wires.
    clock_x = x + 468
    if any(state.main.wires) do wire
        a, b = wire.vertices
        min(a[1], b[1]) <= clock_x <= max(a[1], b[1]) &&
            max(min(a[2], b[2]), y - 36) <= min(max(a[2], b[2]), y)
    end
        state.layout.next += 5
        x, y = allocate_cell!(state.layout)
    end
    stem = pscad_name("precharge_" * bus.name; used = state.used)
    clock = Signal(pscad_name(stem * "_clock"; used = state.used))
    opened = Signal(pscad_name(stem * "_open"; used = state.used))
    graph = BlockGraph(ControlBlock[TimeStep(clock),
        Compare(clock, opened, _CONVERTER_STARTUP_RELEASE)])
    lower!(state.main, graph; origin = (x + 432, y))
    state.layout.next += 11
    voltage = bus.vm_pu * bus.base_kV
    for (i, pole) in enumerate(("P", "N"))
        row = y + 54 + 108(i - 1)
        inner = pscad_name(stem * "_" * pole * "_inner"; used = state.used)
        component!(state.main, "source_1", (x + 126, row),
            ["Name" => pscad_name(stem * "_" * pole; used = state.used),
                "Type" => "6", "Grnd" => "0", "Spec" => "0", "Cntrl" => "0",
                "AC" => "0", "Vm" => pscad_value(voltage; unit = "kV"),
                "Tc" => "0.0 [s]", "Ph" => "0.0 [deg]",
                "f" => pscad_value(context.settings.frequency; unit = "Hz")])
        # The orient-0 source terminal NA is positive, giving +Vpole and -Vpole
        # relative to ground.
        stub!(state.main, (x + 90, row), pole == "P" ? inner : nothing; direction = -1)
        stub!(state.main, (x + 162, row), pole == "P" ? nothing : inner)
        component!(state.main, "breaker1", (x + 324, row),
            ["NAME" => opened.name, "BOpen" => "0", "ENAB" => "0", "OPCUR" => "1",
                "RON" => "0.0 [ohm]", "ROFF" => "1.0E100 [ohm]", "CLVL" => "0.0 [kA]",
                "ViewB" => "0", "VBR" => "", "SBR" => "", "IBR" => ""])
        stub!(state.main, (x + 288, row), inner; direction = -1)
        stub!(state.main, (x + 360, row), context.dc_labels[bus.key][i])
    end
    return nothing
end
