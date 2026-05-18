export AbstractBipolarMMC, BipolarMMC, bipolar_mmc

abstract type AbstractBipolarMMC <: AbstractConverter end

mutable struct BipolarMMC{E<:Element} <: AbstractBipolarMMC
    pole_pos::E
    pole_neg::E
end

function station_setpoint(pos::Element, neg::Element)
    return SetPoint(
        Pac = pos.setpoint.Pac + neg.setpoint.Pac,
        Qac = pos.setpoint.Qac + neg.setpoint.Qac,
        θac = pos.setpoint.θac,
        Vac = pos.setpoint.Vac,
        Pdc = pos.setpoint.Pdc + neg.setpoint.Pdc,
        Vdc = pos.setpoint.Vdc + neg.setpoint.Vdc,
    )
end

function station_limits(pos::Element, neg::Element)
    return Limits(
        P_min = pos.limits.P_min + neg.limits.P_min,
        P_max = pos.limits.P_max + neg.limits.P_max,
        Q_min = pos.limits.Q_min + neg.limits.Q_min,
        Q_max = pos.limits.Q_max + neg.limits.Q_max,
    )
end

function check_pole_element(elem::Element, name::String)
    elem.element_model isa MMC || throw(ArgumentError("`$name` must be an MMC element (`mmc(...)`)."))
    return nothing
end

function bipolar_mmc(mmc_pos::Element, mmc_neg::Element; connection::Bool = true)
    check_pole_element(mmc_pos, "mmc_pos")
    check_pole_element(mmc_neg, "mmc_neg")

    conv = BipolarMMC(deepcopy(mmc_pos), deepcopy(mmc_neg))

    return Element(
        input_pins = 3,
        output_pins = 2,
        element_model = conv,
        transformation = false,
        connection = connection,
        setpoint = station_setpoint(conv.pole_pos, conv.pole_neg),
        limits = station_limits(conv.pole_pos, conv.pole_neg),
    )
end

function bipolar_mmc(
    mmc_pos::MMC,
    mmc_neg::MMC;
    setpoint_pos::SetPoint = SetPoint(),
    setpoint_neg::SetPoint = setpoint_pos,
    limits_pos::Limits = Limits(),
    limits_neg::Limits = limits_pos,
    connection::Bool = true,
)
    pos = Element(
        input_pins = 1,
        output_pins = 2,
        element_model = mmc_pos,
        transformation = false,
        connection = connection,
        setpoint = setpoint_pos,
        limits = limits_pos,
    )

    neg = Element(
        input_pins = 1,
        output_pins = 2,
        element_model = mmc_neg,
        transformation = false,
        connection = connection,
        setpoint = setpoint_neg,
        limits = limits_neg,
    )

    return bipolar_mmc(pos, neg; connection = connection)
end

"""
    update!(converter::BipolarMMC, Vm, θ, Pac, Qac, Vdc, Pdc)

Update using station totals. Active/reactive power and DC quantities are split
equally over both poles.
"""
function update!(converter::BipolarMMC, Vm, θ, Pac, Qac, Vdc, Pdc)
    return update!(
        converter, Vm, θ,
        Pac / 2, Qac / 2, Vdc / 2, Pdc / 2,
        Pac / 2, Qac / 2, Vdc / 2, Pdc / 2,
    )
end


"""
    update!(converter::BipolarMMC, Vm, θ,
            Pac_p, Qac_p, Vpr, Pdc_p,
            Pac_n, Qac_n, Vrn, Pdc_n)

True bipolar operating-point update. Updates both poles.
"""
function update!(converter::BipolarMMC, Vm, θ,
                 Pac_p, Qac_p, Vpr, Pdc_p,
                 Pac_n, Qac_n, Vrn, Pdc_n)

    setpoint_pos = SetPoint(
        Pac = Pac_p,
        Qac = Qac_p,
        θac = θ,
        Vac = Vm,
        Pdc = Pdc_p,
        Vdc = Vpr,
    )
    setpoint_neg = SetPoint(
        Pac = Pac_n,
        Qac = Qac_n,
        θac = θ,
        Vac = Vm,
        Pdc = Pdc_n,
        Vdc = Vrn,
    )

    update!(converter.pole_pos, converter.pole_pos.element_model, setpoint_pos)
    update!(converter.pole_neg, converter.pole_neg.element_model, setpoint_neg)

    return nothing
end

#= function _pole_y(elem::Element, s::Complex)
    if !isempty(elem.A)
        return eval_y(elem, s)
    end

    hasmethod(eval_parameters, Tuple{typeof(elem.element_model), Complex}) ||
        throw(ArgumentError("BipolarMMC poles are not initialized. Run `power_flow(...)` first."))

    return eval_parameters(elem.element_model, s)
end =#

"""
    eval_parameters(converter::BipolarMMC, s::Complex)

Return the 5×5 small-signal admittance matrix ordered as `[p, r, n, d, q]`.

The mapping is a superposition of two 3-port MMC admittances:
- Positive pole: between `(p,r)` using `v_dc,p = v_p - v_r`
- Negative pole: between `(r,n)` using `v_dc,n = v_r - v_n`
"""
function eval_parameters(converter::BipolarMMC, s::Complex; SI_units::Bool=true)
    Yp = Matrix{ComplexF64}(eval_y(converter.pole_pos, s; SI_units)) # [dc, d, q]
    Yn = Matrix{ComplexF64}(eval_y(converter.pole_neg, s; SI_units)) # [dc, d, q]

    size(Yp) == (3, 3) || throw(ArgumentError("Positive-pole MMC must provide a 3x3 admittance matrix."))
    size(Yn) == (3, 3) || throw(ArgumentError("Negative-pole MMC must provide a 3x3 admittance matrix."))

    Y5 = zeros(ComplexF64, 5, 5)             # [p, r, n, d, q]

    # -----------------------
    # DC terminal current rows
    # -----------------------
    # i_p = i_dc,p
    Y5[1, 1] =  Yp[1, 1]
    Y5[1, 2] = -Yp[1, 1]
    Y5[1, 4] =  Yp[1, 2]
    Y5[1, 5] =  Yp[1, 3]

    # i_r = -i_dc,p + i_dc,n
    Y5[2, 1] = -Yp[1, 1]
    Y5[2, 2] =  Yp[1, 1] + Yn[1, 1]
    Y5[2, 3] = -Yn[1, 1]
    Y5[2, 4] = -Yp[1, 2] + Yn[1, 2]
    Y5[2, 5] = -Yp[1, 3] + Yn[1, 3]

    # i_n = -i_dc,n
    Y5[3, 2] = -Yn[1, 1]
    Y5[3, 3] =  Yn[1, 1]
    Y5[3, 4] = -Yn[1, 2]
    Y5[3, 5] = -Yn[1, 3]

    # -----------------------
    # AC current rows (dq), shared AC port
    # -----------------------
    # i_d = i_d,p + i_d,n
    Y5[4, 1] =  Yp[2, 1]
    Y5[4, 2] = -Yp[2, 1] + Yn[2, 1]
    Y5[4, 3] = -Yn[2, 1]
    Y5[4, 4] =  Yp[2, 2] + Yn[2, 2]
    Y5[4, 5] =  Yp[2, 3] + Yn[2, 3]

    # i_q = i_q,p + i_q,n
    Y5[5, 1] =  Yp[3, 1]
    Y5[5, 2] = -Yp[3, 1] + Yn[3, 1]
    Y5[5, 3] = -Yn[3, 1]
    Y5[5, 4] =  Yp[3, 2] + Yn[3, 2]
    Y5[5, 5] =  Yp[3, 3] + Yn[3, 3]

    return Y5
end


"""
Power-flow stamping for bipolar MMC.

Creates one AC bus and one 3-terminal DC bus (`p,r,n`) for PowerModelsMCDC.
"""
function make_power_flow!(converter::BipolarMMC, data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
    get(data, "_mcdc", false) || throw(ArgumentError("BipolarMMC requires the PowerModelsMCDC power-flow backend."))

    dc_node = make_node(elem, 1) # {p,r,n}
    ac_nodes = make_node(elem, 2) # {d,q}
    dc_bus = add_bus_dc!(data, nodes2bus, bus2nodes, dc_node, global_dict)
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)

    key = comp_elem_interface!(data, elem2comp, comp2elem, elem, "convdc")
    key_str = string(key)

    data["convdc"][key_str] = Dict{String, Any}()
    convdc = data["convdc"][key_str]

    convdc["busdc_i"] = dc_bus
    convdc["busac_i"] = ac_bus
    convdc["source_id"] = Any["convdc", key]
    convdc["status"] = 1
    convdc["index"] = key
    convdc["basekVac"] = global_dict["V"] / 1e3

    mmc_pos = converter.pole_pos.element_model::MMC
    mmc_neg = converter.pole_neg.element_model::MMC
    setpoint_pos = converter.pole_pos.setpoint
    setpoint_neg = converter.pole_neg.setpoint
    limits_pos = converter.pole_pos.limits
    limits_neg = converter.pole_neg.limits

    convdc["type_ac"] = pf_type_ac(mmc_pos.delta_control)
    convdc["Vtar"] = pf_vtar_pu(mmc_pos, converter.pole_pos, global_dict)
    if convdc["type_ac"] == 2
        data["bus"][string(ac_bus)] = set_bus_type(data["bus"][string(ac_bus)], 2)
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
    end

    convdc["type_dc"] = pf_type_dc(mmc_pos.delta_control, mmc_pos.sync)
    convdc["acq_droop"] = 0
    convdc["kq_droop"] = 0.0
    convdc["droop"] = 0.0

    pdc_pos = !iszero(setpoint_pos.Pdc) ? setpoint_pos.Pdc : setpoint_pos.Pac
    pdc_neg = !iszero(setpoint_neg.Pdc) ? setpoint_neg.Pdc : setpoint_neg.Pac
    p_pole = 0.5 * (setpoint_pos.Pac + setpoint_neg.Pac)
    q_pole = 0.5 * (setpoint_pos.Qac + setpoint_neg.Qac)
    pdc_pole = 0.5 * (pdc_pos + pdc_neg)
    vdc_pole = 0.5 * (setpoint_pos.Vdc + setpoint_neg.Vdc)
    vac = 0.5 * (setpoint_pos.Vac + setpoint_neg.Vac)

    # MCDC uses 3-terminal DC buses: Vdcset is a pole-to-return target.
    convdc["Vdcset"] = vdc_pole / (global_dict["V"] / 1e3)
    convdc["Pacset"] = -p_pole
    convdc["Pdcset"] = pdc_pole
    convdc["dVdcSet"] = 0.0
    convdc["dVdcset"] = convdc["dVdcSet"]

    convdc["islcc"] = 0
    convdc["transformer"] = 0
    convdc["rtf"] = 0.0
    convdc["xtf"] = 0.0
    convdc["tm"] = 1.0
    convdc["filter"] = 0
    convdc["bf"] = 0.0
    convdc["reactor"] = 1

    z_ac_base_pos = (3 / 2) * mmc_pos.elec.vAC_base^2 / mmc_pos.elec.Sbase
    z_ac_base_neg = (3 / 2) * mmc_neg.elec.vAC_base^2 / mmc_neg.elec.Sbase
    rc_pos = mmc_pos.elec.turnsRatio^(-2) * mmc_pos.elec.Rₑ * z_ac_base_pos / global_dict["Z"]
    xc_pos = mmc_pos.elec.turnsRatio^(-2) * mmc_pos.elec.Lₑ * z_ac_base_pos * global_dict["omega"] / mmc_pos.elec.ωbase / global_dict["Z"]
    rc_neg = mmc_neg.elec.turnsRatio^(-2) * mmc_neg.elec.Rₑ * z_ac_base_neg / global_dict["Z"]
    xc_neg = mmc_neg.elec.turnsRatio^(-2) * mmc_neg.elec.Lₑ * z_ac_base_neg * global_dict["omega"] / mmc_neg.elec.ωbase / global_dict["Z"]

    # PowerModelsMCDC internally rescales bipolar converter parameters to per-pole values.
    convdc["rc"] = 0.25 * (rc_pos + rc_neg)
    convdc["xc"] = 0.25 * (xc_pos + xc_neg)

    convdc["Vmmax"] = 1.1 * vac * 1e3 / global_dict["V"]
    convdc["Vmmin"] = 0.9 * vac * 1e3 / global_dict["V"]

    i_pos = 1.1 * max(abs(limits_pos.P_min), abs(limits_pos.P_max), abs(setpoint_pos.Pac)) / max(setpoint_pos.Vac, eps())
    i_neg = 1.1 * max(abs(limits_neg.P_min), abs(limits_neg.P_max), abs(setpoint_neg.Pac)) / max(setpoint_neg.Vac, eps())
    convdc["Imax"] = 2 * max(i_pos, i_neg)

    # Values expected per pole by MCDC.
    convdc["P_g"] = p_pole
    convdc["Q_g"] = q_pole
    convdc["LossA"] = 0.0
    convdc["LossB"] = 0.0
    convdc["LossCrec"] = 0.0
    convdc["LossCinv"] = 0.0

    # These are interpreted as station totals and internally halved for bipolar.
    convdc["Qacmax"] = limits_pos.Q_max + limits_neg.Q_max
    convdc["Qacmin"] = limits_pos.Q_min + limits_neg.Q_min
    convdc["Pacmax"] = limits_pos.P_max + limits_neg.P_max
    convdc["Pacmin"] = limits_pos.P_min + limits_neg.P_min

    if data["bus"][string(ac_bus)]["bus_type"] == 1
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
        data["bus"][string(ac_bus)]["vmin"] = 0.9 * data["bus"][string(ac_bus)]["vm"]
        data["bus"][string(ac_bus)]["vmax"] = 1.1 * data["bus"][string(ac_bus)]["vm"]
    end

    data["busdc"][string(dc_bus)]["Vdc"] = vdc_pole / (global_dict["V"] / 1e3)
    data["busdc"][string(dc_bus)]["Vdcmax"] = 1.1 * data["busdc"][string(dc_bus)]["Vdc"]
    data["busdc"][string(dc_bus)]["Vdcmin"] = 0.9 * data["busdc"][string(dc_bus)]["Vdc"]
    data["busdc"][string(dc_bus)] = set_bus_type_dc(data["busdc"][string(dc_bus)], convdc["type_dc"])

    # Multi-conductor converter metadata.
    convdc["poles"] = 2
    convdc["connect_at"] = 0
    convdc["status_p"] = 1
    convdc["status_r"] = 1
    convdc["status_n"] = 1
    convdc["ground_type"] = 0
    convdc["ground_z"] = 0.0

    return nothing
end
