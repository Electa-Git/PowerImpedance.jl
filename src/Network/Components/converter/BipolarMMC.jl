export AbstractBipolarMMC, BipolarMMC, bipolar_mmc

abstract type AbstractBipolarMMC <: AbstractConverter end

struct BipolarMMC{MMC<:AbstractMMC} <: AbstractBipolarMMC
    mmc_pos::MMC
    mmc_neg::MMC
end
    
function bipolar_mmc(mmc_pos::T, mmc_neg::T; kwargs...) where {T<:AbstractMMC}
    # Element-level flags (consumed by Network.add!)
    connection = true
    transformation = false

    conv = BipolarMMC(mmc_pos, mmc_neg)

    return Element(
        input_pins = 3,
        output_pins = 2,
        element_value = conv,
        connection = connection,
        transformation = transformation
    )
end

"""
    update!(converter::BipolarMMC, Vm, θ, Pac, Qac, Vdc, Pdc)

    This function still needs to be implemented to do a per pole update of the individual setpoints with the power flow results.
"""
function update!(converter::BipolarMMC, Vm, θ, Pac, Qac, Vdc, Pdc)

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

    # Per-pole
    update!(converter.mmc_p, Vm, θ, Pac_p, Qac_p, Vpr, Pdc_p)
    update!(converter.mmc_n, Vm, θ, Pac_n, Qac_n, Vrn, Pdc_n)

    return nothing
end


"""
    eval_parameters(converter::BipolarMMC, s::Complex)

Return the 5×5 small-signal admittance matrix ordered as `[p, r, n, d, q]`.

The mapping is a superposition of two 3-port MMC admittances:
- Positive pole: between `(p,r)` using `v_dc,p = v_p - v_r`
- Negative pole: between `(r,n)` using `v_dc,n = v_r - v_n`
"""
function eval_parameters(converter::BipolarMMC, s::Complex)
    Yp = eval_parameters(converter.mmc_p, s) # [dc, d, q]
    Yn = eval_parameters(converter.mmc_n, s) # [dc, d, q]

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

Reuses the generic converter stamping through the aggregated station MMC (`converter.mmc`)
and adds the multi-conductor hints required by PowerModelsMCDC when the MCDC backend is active.
"""
function make_power_flow!(converter::BipolarMMC, data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
    # Delegate to the generic converter stamping (creates a standard convdc component)
    make_power_flow!(converter.mmc, data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)

    # When using the MCDC backend, annotate convdc with poles/connectivity fields.
    if get(data, "_mcdc", false)
        (_, key) = elem2comp[elem.symbol]
        conv = data["convdc"][string(key)]
        conv["poles"] = 2
        conv["connect_at"] = 0
        conv["status_p"] = 1
        conv["status_r"] = 1
        conv["status_n"] = 1
        # Grounding disabled by default (required field for PowerModelsMCDC refs)
        conv["ground_type"] = get(conv, "ground_type", 0)
    end
end