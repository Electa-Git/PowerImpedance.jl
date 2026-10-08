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

function emit!(state::PlanState, e::NetlistElement{<:PowerImpedance.Overhead_line}, context)
    tl = e.model
    c, g = tl.conductors, tl.groundwires
    c.nᵇ == 3 ||
        throw(ArgumentError("PSCAD export of overhead line :$(e.name) with $(c.nᵇ) phases is not implemented yet"))
    length(e.terminals) == 2 && [t.side for t in e.terminals] == [1, 2] ||
        throw(ArgumentError("overhead line :$(e.name) must have two fully connected sides"))
    left, right = e.terminals
    !left.grounded && !right.grounded ||
        throw(ArgumentError("overhead line :$(e.name) requires two nongrounded AC terminals"))
    left_bus, right_bus = _ac_bus(e, left, context), _ac_bus(e, right, context)
    0 <= g.nᵍ <= 2 ||
        throw(ArgumentError("overhead line :$(e.name): PSCAD supports at most two ground wires"))
    1 <= c.nˢᵇ <= 15 ||
        throw(ArgumentError("overhead line :$(e.name): PSCAD supports 1 to 15 subconductors per bundle"))
    x, y = PowerImpedance._ohl_conductor_coordinates(c)
    length(x) == length(y) == c.nᵇ ||
        throw(ArgumentError("overhead line :$(e.name) requires one tower coordinate per phase"))
    xg, yg = PowerImpedance._ohl_groundwire_coordinates(tl)
    μᵣ, ϵᵣ, ρ = tl.earth_parameters
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
    ground = ["EarthForm2" => "0", "EarthForm" => "2", "EarthForm3" => "2",
        "GrRho" => "0", "GRRES" => pscad_value(ρ; unit = "ohm*m"),
        "GPERM" => pscad_value(μᵣ), "GRP" => pscad_value(ϵᵣ)]
    frephase = ["Interp1" => "1", "Output" => "0", "Inflen" => "0",
        "FS" => pscad_value(0.5; unit = "Hz"), "FE" => pscad_value(1e6; unit = "Hz"),
        "Numf" => "100", "YMaxP" => "20", "YMaxE" => pscad_value(0.2; unit = "%"),
        "AMaxP" => "20", "AMaxE" => pscad_value(0.2; unit = "%"),
        "MaxRPtol" => pscad_value(2e6), "CPASS" => "0", "DCenab" => "0",
        "DCCOR" => "1", "enablf" => "1"]
    push!(state.lines,
        LineDefinitionPlan(row, :tline, tower,
            collect(zip(Float64.(x), Float64.(y))), collect(zip(xg, yg)),
            _override_line_parameters(ground, context.line_options.ground),
            _override_line_parameters(frephase, context.line_options.frephase),
            ["DataF" => pscad_value(context.settings.frequency; unit = "Hz")]))
    xcell, ycell = allocate_cell!(state.layout)
    wx, wy = xcell + 144, ycell + 36
    push!(state.wrappers,
        TLineWrapperPlan(row,
            wx,
            wy,
            [
                "Name" => e.pscad, "Freq" =>
                    pscad_value(context.settings.frequency; unit = "Hz"),
                "Length" => pscad_value(tl.length / 1e3; unit = "km"),
                "Dim" => pscad_value(c.nᵇ), "Mode" => "1", "CoupleEnab" => "0",
                "CoupleName" => "row", "CoupleOffset" => pscad_value(0.0; unit = "m"),
                "CoupleRef" => "0", "tname" => "tandem_segment", "sfault" => "0",
                "linc" => pscad_value(10.0; unit = "km"), "steps" => "3"]))
    first_probe = current_probe!(state, e, left, context)
    second_probe = current_probe!(state, e, right, context)
    ammeter_stub!(state.main, (wx - 54, wy + 18), left_bus.name, first_probe;
        direction = -1)
    ammeter_stub!(state.main, (wx + 54, wy + 72), right_bus.name, second_probe)
    output_probe!(state.main, first_probe, "branch", "kA", (xcell + 144, ycell + 144))
    output_probe!(state.main, second_probe, "branch", "kA", (xcell + 144, ycell + 180))
    return nothing
end
