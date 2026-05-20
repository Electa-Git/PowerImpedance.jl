abstract type AbstractConverter <: AbstractStateSpace end


# Evaluating the admittance of the converter
function eval_abcd(converter :: AbstractConverter, s :: Complex)
    return eval_y(converter, s)
end

function eval_y(converter :: AbstractConverter, s :: Complex)
    Y = eval_parameters(converter, s)
    return Y
end


function convert!(data,elem::Element{<:AbstractConverter},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)
    
    converter = elem.element_model
    pins = elem.pins
    
    # Busses interface (dc_bus --> 1.1 & ac_bus --> 2.1 and 2.2)
    dc_node = make_node(elem, 1) 
    ac_nodes = make_node(elem,2) #Similar AC bus
    dc_bus = add_bus_dc!(data, nodes2bus, bus2nodes, dc_node, global_dict)
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)
    
    # Interface element
    key = comp_elem_interface!(data, elem2comp, comp2elem, elem, "convdc")

    (data["convdc"])[string(key)] = Dict{String, Any}()
    ((data["convdc"])[string(key)])["busdc_i"] = dc_bus
    ((data["convdc"])[string(key)])["busac_i"] = ac_bus
    ((data["convdc"])[string(key)])["source_id"] = Any["convdc", key]
    ((data["convdc"])[string(key)])["status"] = 1
    ((data["convdc"])[string(key)])["index"] = key

    ((data["convdc"])[string(key)])["basekVac"] = global_dict["V"] / 1e3

    if in(:vac, keys(converter.controls)) || in(:vac_supp, keys(converter.controls)) 
        ((data["convdc"])[string(key)])["type_ac"] = 2  # V ac bus
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
        ((data["convdc"])[string(key)])["type_ac"] = 1  # Q ac bus
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
end

function timeDelayPadeMatrices(padeOrderNum,padeOrderDen,t_delay,numberVars)

    # Calculation of the state-space representation of a pade approximation with nth-order numerator and nth-order denominator
    # padeOrderNum = Order of the numerator, padeOrderDen= Order of the denominator, t_delay = Time delay duration, numberVars= Variables to be delayed max.2 !
    #
    size_A=padeOrderDen;
    a_k=factorial(padeOrderNum);
    b_l=((factorial(padeOrderDen)*(-1)^padeOrderNum)*(t_delay^(padeOrderNum-padeOrderDen)))/a_k;
    Ad=zeros(size_A,size_A);
    Bd=zeros(size_A,1);
    Bd[end]=1;
    Cd=zeros(1,size_A);
    Dd=b_l;
    Ad[1:end-1,2:end] = Matrix(1.0I, padeOrderDen-1, padeOrderDen-1);
    for i=0:padeOrderDen-1
        a_i=(t_delay^(i-padeOrderDen)*(factorial(padeOrderNum+padeOrderDen-i)*factorial(padeOrderDen)/(factorial(i)*factorial(padeOrderDen-i))))/a_k;
        b_i=(t_delay^(i-padeOrderDen)*((-1)^i)*(factorial(padeOrderNum+padeOrderDen-i)*factorial(padeOrderNum)/(factorial(i)*factorial(padeOrderNum-i))))/a_k;
        Ad[end,i+1] =-a_i;
        Cd[i+1] = (b_i-(a_i*b_l));
    end
    # Result above gives state space in canonical realization, which is ill-conditioned, especially for higher order pades.
    # In order to improve numerical handling, transform state space into modal realization
    # Alternative # TODO: What about Dd?
    sys = ss(Ad,Bd,Cd,Dd)
    sys_modal = modal_form(sys; C1=true)
    Ad = sys_modal[1].A
    Bd = sys_modal[1].B
    Cd = sys_modal[1].C
    if numberVars == 1
        A_Pade=Ad;
        B_Pade=Bd;
        C_Pade=Cd;
        D_Pade=Dd;
    elseif numberVars == 2
        A_Pade=cat(Ad,Ad;dims=[1,2]);
        B_Pade=cat(Bd,Bd;dims=[1,2]);
        C_Pade=cat(Cd,Cd;dims=[1,2]);
        D_Pade=cat(Dd,Dd;dims=[1,2]);
    end

    return A_Pade,B_Pade,C_Pade,D_Pade
end
