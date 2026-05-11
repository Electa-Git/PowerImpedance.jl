#=
Common converter power-flow integration helpers.

This file contains the legacy `Converter` interface and the shared converter
power-flow data mapping used by non-modular converter models. Modular TLC uses
its own specialized `make_power_flow!`, but these definitions remain part of
the common converter layer because MMC and black-box converters still depend on
them.
=#

"""
Abstract supertype for legacy converter models.
"""
abstract type Converter end

"""
Evaluate the ABCD representation of a converter at complex frequency `s`.

$(SIGNATURES)

# Details

The legacy converter interface delegates ABCD evaluation to [`eval_y`](@ref).
"""
function eval_abcd(converter :: Converter, s :: Complex)
    return eval_y(converter, s)
end

"""
Evaluate the admittance representation of a converter at complex frequency `s`.

$(SIGNATURES)
"""
function eval_y(converter :: Converter, s :: Complex)
    Y = eval_parameters(converter, s)
    return Y
end


"""
Write a legacy converter into a PowerModelsACDC power-flow data dictionary.

$(SIGNATURES)

# Details

The method creates the AC/DC buses, converter component entry, operating-point
setpoints, limits, and reactor parameters expected by PowerModelsACDC.
"""
pmtype(::Element{<:Converter}) = "convdc"

function convert!(data,elem::Element{<:Converter},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)
    # Busses interface (dc_bus --> 1.1 & ac_bus --> 2.1 and 2.2)
    dc_node = make_node(elem, 1) 
    ac_nodes = make_node(elem,2) #Similar AC bus
    dc_bus = add_bus_dc!(data, nodes2bus, bus2nodes, dc_node, global_dict)
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)
    
    # Interface element
    key = comp_elem_interface!(data, elem2comp, comp2elem, elem, pmtype(elem))
    return convert!(data, elem, PMACDC, key, (ac_bus, dc_bus), global_dict)
end

function convert!(data, elem::Element{<:Converter}, ::Type{PMACDC}, key, buses, global_dict)
    converter = elem.element_model
    ac_bus = buses[1]
    dc_bus = buses[2]

    (data["convdc"])[string(key)] = Dict{String, Any}()
    ((data["convdc"])[string(key)])["busdc_i"] = dc_bus
    ((data["convdc"])[string(key)])["busac_i"] = ac_bus
    ((data["convdc"])[string(key)])["source_id"] = Any["convdc", key]
    ((data["convdc"])[string(key)])["status"] = 1
    ((data["convdc"])[string(key)])["index"] = key

    ((data["convdc"])[string(key)])["basekVac"] = global_dict["V"] / 1e3

    if in(:vac, keys(converter.controls)) || in(:vac_supp, keys(converter.controls)) 
        ((data["convdc"])[string(key)])["type_ac"] = 2  # PV ac bus
        data["bus"][string(ac_bus)] = set_bus_type(data["bus"][string(ac_bus)], 2)
        # TODO: The line below sometimes gives errors during power flow (NUMERICAL_ERROR)
         # Not entirely sure if this is necessary. ΔQ = kp*ΔV -> new pu base kp_new = kppu
        if in(:vac, keys(converter.controls))
            ((data["convdc"])[string(key)])["Vtar"] = converter.controls[:vac].ref[1] * 1e3 / (global_dict["V"] * sqrt(2))
        else
            ((data["convdc"])[string(key)])["Vtar"] = converter.controls[:vac_supp].ref[1] * 1e3 / (global_dict["V"] * sqrt(2))
        end
        data["bus"][string(ac_bus)]["vm"] = ((data["convdc"])[string(key)])["Vtar"]
    else
        ((data["convdc"])[string(key)])["type_ac"] = 1  # PQ ac bus
        ((data["convdc"])[string(key)])["Vtar"] = converter.Vₘ * 1e3 / global_dict["V"] # Not needed for PQ bus ?
    end

    if in(:p, keys(converter.controls)) && in(:vdc_droop, keys(converter.controls))
        ((data["convdc"])[string(key)])["type_dc"] = 4  # DC voltage droop using AC power
        # ((data["convdc"])[string(key)])["type_dc"] = 3  # DC voltage droop using DC power
    elseif in(:p, keys(converter.controls))
        ((data["convdc"])[string(key)])["type_dc"] = 1  # Constant AC active power        
    elseif in(:dc, keys(converter.controls))
        ((data["convdc"])[string(key)])["type_dc"] = 2  # constant DC voltage
    end

    if in(:vac_supp, keys(converter.controls)) # AC voltage droop control
        ((data["convdc"])[string(key)])["acq_droop"] = 1
        ((data["convdc"])[string(key)])["kq_droop"] = (converter.controls[:vac_supp].Kₚ*(converter.Sbase/(global_dict["S"]*1e-6))) # Adjust for PMACDC pu base
    else
        ((data["convdc"])[string(key)])["acq_droop"] = 0
        ((data["convdc"])[string(key)])["kq_droop"] = 0
    end

    # Power-voltage droop control
    if in(:vdc_droop, keys(converter.controls))
        # Droop control
        ((data["convdc"])[string(key)])["droop"] = 1/converter.controls[:vdc_droop].Kₚ * (converter.Vᵈᶜ /  (data["dcpol"]*global_dict["V"] / 1e3)) / (converter.Sbase *1e6 / global_dict["S"]) # In pu/pu
        ((data["convdc"])[string(key)])["Vdcset"] = converter.controls[:vdc_droop].ref[1] * converter.Vᵈᶜ / (data["dcpol"]*global_dict["V"] / 1e3) # In pu
        ((data["convdc"])[string(key)])["Pacset"] = - converter.P # Using AC-side power [MW]
        ((data["convdc"])[string(key)])["Pdcset"] = converter.P_dc # Using DC-side power [MW]
    else
        # Constant power control or DC voltage control
        ((data["convdc"])[string(key)])["droop"] = 0
        ((data["convdc"])[string(key)])["Pdcset"] = converter.P_dc
        ((data["convdc"])[string(key)])["Vdcset"] = converter.Vᵈᶜ / (data["dcpol"]*global_dict["V"] / 1e3)
    end
    ((data["convdc"])[string(key)])["dVdcSet"] = 0
    
    # LCC converter
    ((data["convdc"])[string(key)])["islcc"] = 0

    # without transformer
    ((data["convdc"])[string(key)])["transformer"] = 0
    ((data["convdc"])[string(key)])["rtf"] = 0
    ((data["convdc"])[string(key)])["xtf"] = 0
    ((data["convdc"])[string(key)])["tm"] = 1
    # without filter
    ((data["convdc"])[string(key)])["filter"] = 0
    ((data["convdc"])[string(key)])["bf"] = 0
    # with reactor
    ((data["convdc"])[string(key)])["reactor"] = 1
    #Discrimination needed, as TLC's R & L refers to grid side, where in MMC R & L refered to converter side

    if typeof(converter) == TLC
            ((data["convdc"])[string(key)])["rc"] = 1*(converter.Rᵣ + converter.Rₐᵣₘ / 2) / global_dict["Z"]
            ((data["convdc"])[string(key)])["xc"] = 1*(converter.Lᵣ + converter.Lₐᵣₘ / 2) * global_dict["omega"] / global_dict["Z"]
    end
    if typeof(converter) == MMC
            ((data["convdc"])[string(key)])["rc"] = converter.turnsRatio^(-2)*(converter.Rᵣ + converter.Rₐᵣₘ / 2) / global_dict["Z"]
            ((data["convdc"])[string(key)])["xc"] = converter.turnsRatio^(-2)*(converter.Lᵣ + converter.Lₐᵣₘ / 2) * global_dict["omega"] / global_dict["Z"]
    end
    if typeof(converter) == Blackbox_MMC
            ((data["convdc"])[string(key)])["rc"] = converter.Rₘₑ / global_dict["Z"]
            ((data["convdc"])[string(key)])["xc"] = 0.0 
    end

    converter.ω₀ = global_dict["omega"]
    # default values
    ((data["convdc"])[string(key)])["Vmmax"] = 1.1 * converter.Vₘ * 1e3 / global_dict["V"]
    ((data["convdc"])[string(key)])["Vmmin"] = 0.9 * converter.Vₘ * 1e3 / global_dict["V"]
    ((data["convdc"])[string(key)])["Imax"] = 1.1 * abs(converter.P) / converter.Vₘ

    ((data["convdc"])[string(key)])["P_g"] = converter.P
    ((data["convdc"])[string(key)])["Q_g"] = converter.Q
    

    ((data["convdc"])[string(key)])["LossA"] = 0
    ((data["convdc"])[string(key)])["LossB"] = 0
    ((data["convdc"])[string(key)])["LossCrec"] = 0
    ((data["convdc"])[string(key)])["LossCinv"] = 0

    ((data["convdc"])[string(key)])["Qacmax"] = converter.Q_max
    ((data["convdc"])[string(key)])["Qacmin"] = converter.Q_min
    ((data["convdc"])[string(key)])["Pacmax"] = converter.P_max
    ((data["convdc"])[string(key)])["Pacmin"] = converter.P_min

    
    
    #Voltage limits for bus, these are already set when PV bus
    if (data["bus"][string(ac_bus)]["bus_type"] == 1) #PQ-bus
        data["bus"][string(ac_bus)]["vm"] = ((data["convdc"])[string(key)])["Vtar"]
        ((data["bus"])[string(ac_bus)])["vmin"] = 0.9 * data["bus"][string(ac_bus)]["vm"]
        ((data["bus"])[string(ac_bus)])["vmax"] = 1.1 * data["bus"][string(ac_bus)]["vm"]
    end
    ((data["busdc"])[string(dc_bus)])["Vdc"] = converter.Vᵈᶜ / (data["dcpol"] * global_dict["V"] / 1e3)  # Convert from pp to pg for PMACDC
    ((data["busdc"])[string(dc_bus)])["Vdcmax"] = 1.1 * ((data["busdc"])[string(dc_bus)])["Vdc"]
    ((data["busdc"])[string(dc_bus)])["Vdcmin"] = 0.9 * ((data["busdc"])[string(dc_bus)])["Vdc"]
    ((data["busdc"])[string(dc_bus)]) = set_bus_type_dc((data["busdc"])[string(dc_bus)], ((data["convdc"])[string(key)])["type_dc"])
    return nothing
end
