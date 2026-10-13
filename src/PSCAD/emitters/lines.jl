# PSCAD field names and units verified in mhi-xml 1.3.0 twm_types.py.
const _LINE_GROUND_UNITS = (; EarthForm2 = nothing, EarthForm = nothing,
    EarthForm3 = nothing, GrRho = nothing, GRRES = "ohm*m", GPERM = nothing,
    GRP = nothing)
const _LINE_FREPHASE_UNITS = (; Interp1 = nothing, Output = nothing, Inflen = nothing,
    FS = "Hz", FE = "Hz", Numf = nothing, YMaxP = nothing, YMaxE = "%",
    AMaxP = nothing, AMaxE = "%", MaxRPtol = nothing, W1 = nothing, W2 = nothing,
    W3 = nothing, ET_PE = nothing, NFP = nothing, FSP = "Hz", MER_PE = nothing,
    MIT_PE = nothing, FEP = "Hz", FDIS = nothing, CPASS = nothing, DCenab = nothing,
    DCCOR = nothing, shntcab = "mho/m", enablf = nothing)

function _line_options(options)
    options isa NamedTuple || throw(ArgumentError("line_options must be a NamedTuple"))
    ground, frephase = Pair{String, String}[], Pair{String, String}[]
    for (key, value) in pairs(options)
        target, units = if hasproperty(_LINE_GROUND_UNITS, key)
            ground, _LINE_GROUND_UNITS
        elseif hasproperty(_LINE_FREPHASE_UNITS, key)
            frephase, _LINE_FREPHASE_UNITS
        else
            throw(ArgumentError("unknown PSCAD line_options field: $key"))
        end
        value isa Real || value isa AbstractString ||
            throw(ArgumentError("PSCAD line_options.$key must be a real value or parameter string"))
        parameter = value isa Real ? pscad_value(value; unit = getproperty(units, key)) :
                    String(value)
        push!(target, String(key) => parameter)
    end
    return (; ground, frephase)
end

function _override_line_parameters(defaults, overrides)
    params = copy(defaults)
    for parameter in overrides
        index = findfirst(p -> first(p) == first(parameter), params)
        index === nothing ? push!(params, parameter) : (params[index] = parameter)
    end
    return params
end

function _line_ground_parameters(line, overrides)
    μᵣ, ϵᵣ, ρ = line.earth_parameters
    defaults = ["EarthForm2" => "0", "EarthForm" => "2", "EarthForm3" => "2",
        "GrRho" => "0", "GRRES" => pscad_value(ρ; unit = "ohm*m"),
        "GPERM" => pscad_value(μᵣ), "GRP" => pscad_value(ϵᵣ)]
    return _override_line_parameters(defaults, overrides)
end

"""
DC line frequency/phase fit start frequency \\[Hz\\]. Cable station measurements
recorded in `docs/src/developers/pscad_mapping.md` (Cables) found a window mean
25% below power flow at 3 s with FS = 0.5 Hz, versus 0.67% above at 5 s with
FS = 0.001 Hz. AC lines retain the validation start frequency of 0.5 Hz.
"""
const DC_LINE_FIT_START_FREQUENCY = 0.001

function _line_frephase_parameters(overrides, buses)
    start_frequency = all(bus -> bus.kind == :dc, buses) ?
                      DC_LINE_FIT_START_FREQUENCY : 0.5
    defaults = ["Interp1" => "1", "Output" => "0", "Inflen" => "0",
        "FS" => pscad_value(start_frequency; unit = "Hz"), "FE" =>
            pscad_value(1e6; unit = "Hz"),
        "Numf" => "100", "YMaxP" => "20", "YMaxE" => pscad_value(0.02; unit = "%"),
        "AMaxP" => "20", "AMaxE" => pscad_value(0.02; unit = "%"),
        "MaxRPtol" => pscad_value(2e6), "CPASS" => "0", "DCenab" => "0",
        "DCCOR" => "1", "enablf" => "1"]
    return _override_line_parameters(defaults, overrides)
end

function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.Overhead_line}, context)
    tl = e.model
    if tl.length / 299_792_458 < context.settings.time_step
        @warn "PSCAD overhead line :$(e.name), length $(tl.length) m, time step $(context.settings.time_step) s: PSCAD aborts if the travel time is below the step; a smaller step or a longer section is needed."
    end
    c, g = tl.conductors, tl.groundwires
    length(e.terminals) == 2 && [t.side for t in e.terminals] == [1, 2] ||
        throw(ArgumentError("overhead line :$(e.name) must have two fully connected sides"))
    left, right = e.terminals
    !left.grounded && !right.grounded ||
        throw(ArgumentError("overhead line :$(e.name) requires two nongrounded terminals"))
    left_bus, right_bus = _terminal_bus(e, left, context), _terminal_bus(e, right, context)
    dc = left_bus.kind == :dc
    (right_bus.kind == :dc) == dc ||
        throw(ArgumentError("overhead line :$(e.name) cannot join AC and DC buses"))
    c.nᵇ == (dc ? 2 : 3) ||
        throw(ArgumentError("overhead line :$(e.name) requires $(dc ? 2 : 3) conductors for $(dc ? "DC" : "AC") export"))
    0 <= g.nᵍ <= 2 ||
        throw(ArgumentError("overhead line :$(e.name): PSCAD supports at most two ground wires"))
    1 <= c.nˢᵇ <= 15 ||
        throw(ArgumentError("overhead line :$(e.name): PSCAD supports 1 to 15 subconductors per bundle"))
    x, y = PowerImpedance._ohl_conductor_coordinates(c)
    length(x) == length(y) == c.nᵇ ||
        throw(ArgumentError("overhead line :$(e.name) requires one tower coordinate per phase"))
    xg, yg = PowerImpedance._ohl_groundwire_coordinates(tl)
    row = pscad_name(e.pscad * "_row"; used = state.used)
    tower = [
        "TName" => row, "Transp" => pscad_value(0),
        "CDataType" => pscad_value(1), "Hollow" => pscad_value(0),
        "RadiusC" => pscad_value(c.rᶜ; unit = "m"),
        "DCResC" => pscad_value(c.Rᵈᶜ; unit = "ohm/km"),
        "PERMC" => pscad_value(c.μᵣᶜ), "SAGC" => pscad_value(c.dˢᵃᵍ; unit = "m"),
        "NCondB" => pscad_value(c.nˢᵇ), "BSP" => pscad_value(c.dˢᵇ; unit = "m"),
        "BundSym" => pscad_value(0), "ShuntG" => pscad_value(c.gᶜ; unit = "mho/m"),
        "GDataType" => pscad_value(1), "GWSame" => pscad_value(1),
        "ElimGW" => pscad_value(1), "RadiusG" => pscad_value(g.rᵍ; unit = "m"),
        "DCResG" => pscad_value(g.Rᵍᵈᶜ; unit = "ohm/km"),
        "PERMG" => pscad_value(g.μᵣᵍ), "SAGG" => pscad_value(g.dᵍˢᵃᵍ; unit = "m")]
    push!(state.lines,
        LineDefinitionPlan(row, :tline, tower,
            collect(zip(Float64.(x), Float64.(y))), collect(zip(xg, yg)),
            _line_ground_parameters(tl, context.line_options.ground),
            _line_frephase_parameters(context.line_options.frephase, (left_bus, right_bus)),
            ["DataF" => pscad_value(context.settings.frequency; unit = "Hz")]))
    xcell, ycell = allocate_cell!(state.layout)
    wx, wy = xcell + 144, ycell + 36
    push!(state.wrappers,
        TLineWrapperPlan(row,
            wx,
            wy,
            [
                "Name" => e.pscad, "Freq" =>
                    pscad_value(dc ? 0.0 : context.settings.frequency; unit = "Hz"),
                "Length" => pscad_value(tl.length / 1e3; unit = "km"),
                "Dim" => pscad_value(c.nᵇ), "Mode" => dc ? "0" : "1", "CoupleEnab" => "0",
                "CoupleName" => "row", "CoupleOffset" => pscad_value(0.0; unit = "m"),
                "CoupleRef" => "0", "tname" => "tandem_segment", "sfault" => "0",
                "linc" => pscad_value(10.0; unit = "km"), "steps" => "3"]))
    if dc
        # PSCAD 5.1.0 master:tline_interface, NC=2/View=0: scalar ports
        # A(-18,-18), C(-18,18), in physical conductor order. Remote wrapper
        # vertices have no electrical connections. See the M7 mapping record.
        for (side, (terminal, bus)) in enumerate(zip(e.terminals, (left_bus, right_bus)))
            ix, iy = allocate_cell!(state.layout)
            interface = (ix + 144, iy + 72)
            direction = side == 1 ? -1 : 1
            push!(state.main.components,
                ComponentPlan("master:tline_interface",
                    ["Name" => e.pscad, "NC" => "2", "View" => "0", "send_recv" => "0",
                        "dim_s" => "0", "dim_r" => "0"], interface..., side == 1 ? 0 : 4))
            probe = current_probe!(state, e, terminal, context; orientation = side == 1 ? :into : :out)
            positive, negative = context.dc_labels[bus.key]
            ammeter_stub!(state.main, (interface[1] + 18direction, interface[2] - 18),
                positive, probe; direction)
            stub!(state.main, (interface[1] + 18direction, interface[2] + 18),
                negative; direction)
            output_probe!(state.main, probe, "branch", "kA", (ix + 144, iy + 180))
        end
        return nothing
    end
    first_probe = current_probe!(state, e, left, context; orientation = :into)
    second_probe = current_probe!(state, e, right, context; orientation = :out)
    ammeter_stub!(state.main, (wx - 54, wy + 18), left_bus.name, first_probe;
        direction = -1)
    ammeter_stub!(state.main, (wx + 54, wy + 72), right_bus.name, second_probe)
    output_probe!(state.main, first_probe, "branch", "kA", (xcell + 144, ycell + 144))
    output_probe!(state.main, second_probe, "branch", "kA", (xcell + 144, ycell + 180))
    return nothing
end
