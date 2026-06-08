export AbstractBipolarMMC, BipolarMMC, bipolar_mmc

"""
Common abstract type for bipolar MMC converter models.
"""
abstract type AbstractBipolarMMC <: AbstractConverter end

"""
Container for a bipolar MMC assembled from a positive-pole and negative-pole MMC element.
"""
mutable struct BipolarMMC{E<:Element} <: AbstractBipolarMMC
    pole_pos::E
    pole_neg::E
end

"""
Build the station-level setpoint by summing both pole setpoints.
"""
function station_setpoint(pos::Element, neg::Element)
    return Setpoint(
        Pac = pos.setpoint.Pac + neg.setpoint.Pac,
        Qac = pos.setpoint.Qac + neg.setpoint.Qac,
        θac = pos.setpoint.θac,
        Vac = pos.setpoint.Vac,
        Pdc = pos.setpoint.Pdc + neg.setpoint.Pdc,
        Vdc = pos.setpoint.Vdc + neg.setpoint.Vdc,
    )
end

"""
Build station-level active and reactive power limits from both pole limits.
"""
function station_limits(pos::Element, neg::Element)
    return Limits(
        P_min = pos.limits.P_min + neg.limits.P_min,
        P_max = pos.limits.P_max + neg.limits.P_max,
        Q_min = pos.limits.Q_min + neg.limits.Q_min,
        Q_max = pos.limits.Q_max + neg.limits.Q_max,
    )
end

"""
Validate that a pole argument is an MMC element.
"""
function check_pole_element(elem::Element, name::String)
    elem.element_model isa MMC || throw(ArgumentError("`$name` must be an MMC element (`mmc(...)`)."))
    return nothing
end

"""
Construct a bipolar MMC element from two existing MMC elements.
"""
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

"""
Construct a bipolar MMC element from two MMC models and optional pole setpoints/limits.
"""
function bipolar_mmc(
    mmc_pos::MMC,
    mmc_neg::MMC;
    setpoint_pos::Setpoint = Setpoint(),
    setpoint_neg::Setpoint = setpoint_pos,
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

# State-space interface names
"""
Return the positive-pole state names in the bipolar model namespace.
"""
positivepolestatenames(converter::BipolarMMC) = prefixednames(:pos_, statenames(converter.pole_pos.element_model))

"""
Return the negative-pole state names in the bipolar model namespace.
"""
negativepolestatenames(converter::BipolarMMC) = prefixednames(:neg_, statenames(converter.pole_neg.element_model))

"""
Return all bipolar MMC state names as one flat state vector.
"""
statenames(converter::BipolarMMC) = (
    positivepolestatenames(converter)...,
    negativepolestatenames(converter)...,
)

"""
Return the bipolar electrical input order: DC terminal voltages and shared AC dq voltages.
"""
inputnames(::BipolarMMC) = (:v_p, :v_r, :v_n, :vG_d, :vG_q)

"""
Return the electrical input subset used when forming the admittance transfer function.
"""
elecinputnames(::BipolarMMC) = (:v_p, :v_r, :v_n, :vG_d, :vG_q)

"""
Return the bipolar output current order in load convention.
"""
outputnames(::BipolarMMC) = (:i_p, :i_r, :i_n, :i_d, :i_q)

"""
Return dummy equilibrium equation names; the bipolar wrapper adds none.
"""
dummynames(::BipolarMMC) = ()

# Pole adapters
"""
Extract positive-pole states from the bipolar state vector.
"""
function positivepolestates(converter::BipolarMMC, x)
    names = statenames(converter.pole_pos.element_model)
    return subblockstates(x, names, positivepolestatenames(converter))
end

"""
Extract negative-pole states from the bipolar state vector.
"""
function negativepolestates(converter::BipolarMMC, x)
    names = statenames(converter.pole_neg.element_model)
    return subblockstates(x, names, negativepolestatenames(converter))
end

"""
Build one MMC pole input NamedTuple from its DC voltage and shared AC dq voltages.
"""
function poleinputs(m::MMC, v_dc, inputs)
    return NamedTuple{inputnames(m)}((v_dc, inputs.vG_d, inputs.vG_q))
end

"""
Return positive-pole MMC inputs using v_p - v_r as the pole DC voltage.
"""
positivepoleinputs(converter::BipolarMMC, inputs) =
    poleinputs(converter.pole_pos.element_model, inputs.v_p - inputs.v_r, inputs)

"""
Return negative-pole MMC inputs using v_r - v_n as the pole DC voltage.
"""
negativepoleinputs(converter::BipolarMMC, inputs) =
    poleinputs(converter.pole_neg.element_model, inputs.v_r - inputs.v_n, inputs)

# Power-flow adapter
"""
Convert a station-level power-flow setpoint into bipolar state-space inputs.
"""
function pftoinputs(converter::BipolarMMC, setpoint::Setpoint)
    pole_setpoint = Setpoint(
        Pac = setpoint.Pac / 2,
        Qac = setpoint.Qac / 2,
        θac = setpoint.θac,
        Vac = setpoint.Vac,
        Pdc = setpoint.Pdc / 2,
        Vdc = setpoint.Vdc / 2,
    )
    pole_inputs, pole_setpoint_pu = pftoinputs(converter.pole_pos.element_model, pole_setpoint)

    return (
        v_p = pole_inputs.v_dc,
        v_r = 0.0,
        v_n = -pole_inputs.v_dc,
        vG_d = pole_inputs.vG_d,
        vG_q = pole_inputs.vG_q,
    ), pole_setpoint_pu
end

# State-space assembly
"""
Return bipolar initial values by concatenating the two pole initial-value sets.
"""
function initialvalues(converter::BipolarMMC; inputs, setpoint_pu = SetpointPU())
    inputs_pos = positivepoleinputs(converter, inputs)
    inputs_neg = negativepoleinputs(converter, inputs)
    init_pos = initialvalues(converter.pole_pos.element_model; inputs = inputs_pos, setpoint_pu)
    init_neg = initialvalues(converter.pole_neg.element_model; inputs = inputs_neg, setpoint_pu)

    return (;
        prefixedinitialvalues(:pos_, init_pos)...,
        prefixedinitialvalues(:neg_, init_neg)...,
    )
end

"""
Evaluate both pole state-space equations inside the flat bipolar state vector.
"""
function state_space!(F, x, inputs, setpoint_pu::SetpointPU, converter::BipolarMMC)
    n_pos = n_states(converter.pole_pos.element_model)
    state_space!(
        @view(F[1:n_pos]),
        positivepolestates(converter, x),
        positivepoleinputs(converter, inputs),
        setpoint_pu,
        converter.pole_pos.element_model,
    )
    state_space!(
        @view(F[n_pos + 1:end]),
        negativepolestates(converter, x),
        negativepoleinputs(converter, inputs),
        setpoint_pu,
        converter.pole_neg.element_model,
    )
    return nothing
end

"""
Apply both pole equilibrium equations during the generic state-space update.
"""
function equilibriumequations!(F, x, inputs, setpoint_pu::SetpointPU, y, converter::BipolarMMC)
    n_pos = n_states(converter.pole_pos.element_model)
    equilibriumequations!(
        @view(F[1:n_pos]),
        positivepolestates(converter, x),
        positivepoleinputs(converter, inputs),
        setpoint_pu,
        nothing,
        converter.pole_pos.element_model,
    )
    equilibriumequations!(
        @view(F[n_pos + 1:end]),
        negativepolestates(converter, x),
        negativepoleinputs(converter, inputs),
        setpoint_pu,
        nothing,
        converter.pole_neg.element_model,
    )
    return nothing
end

"""
Write bipolar pin-current outputs from both pole current outputs in load convention.
"""
function outputequations!(F, x, inputs, y, converter::BipolarMMC)
    out_pos = fill(zero(eltype(F)), n_outputs(converter.pole_pos.element_model))
    out_neg = fill(zero(eltype(F)), n_outputs(converter.pole_neg.element_model))

    outputequations!(
        out_pos,
        positivepolestates(converter, x),
        positivepoleinputs(converter, inputs),
        nothing,
        converter.pole_pos.element_model,
    )
    outputequations!(
        out_neg,
        negativepolestates(converter, x),
        negativepoleinputs(converter, inputs),
        nothing,
        converter.pole_neg.element_model,
    )

    F[1] = out_pos[1]
    F[2] = -out_pos[1] + out_neg[1]
    F[3] = -out_neg[1]
    F[4] = -(out_pos[2] + out_neg[2])
    F[5] = -(out_pos[3] + out_neg[3])
    return nothing
end

"""
Evaluate the 5x5 bipolar admittance from the generic state-space ABCD matrices.
"""
function eval_y(elem::Element{<:BipolarMMC}, s::Complex; SI_units::Bool=true)
    n = size(elem.A, 1)
    Iₙ = Matrix{ComplexF64}(I, n, n)
    Y = Matrix{ComplexF64}(elem.C * ((s * Iₙ - elem.A) \ elem.B) + elem.D)

    SI_units || return Y

    elec = elem.element_model.pole_pos.element_model.elec
    iACbase = 2 * elec.Sbase / (3 * elec.vAC_base)
    iDCbase = elec.Sbase / elec.vDC_base

    Y[1:3, :] .*= iDCbase
    Y[4:5, :] .*= iACbase

    Y[:, 1:3] ./= elec.vDC_base
    Y[:, 4:5] ./= (elec.vAC_base / elec.turnsRatio)

    return Y
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
