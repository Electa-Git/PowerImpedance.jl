@shadow :configuration ElectricalMMC P.ElectricalMMC
@shadow :configuration NoTotalEnergyControl P.NoTotalEnergyControl
@shadow :configuration TotalEnergyControl P.TotalEnergyControl
@shadow :configuration ΣEnergyControl P.ΣEnergyControl
@shadow :configuration ΔEnergyControl P.ΔEnergyControl
@shadow :configuration NoZeroSequenceCurrentControl P.NoZeroSequenceCurrentControl
@shadow :configuration NoCirculatingCurrentSuppressionControl P.NoCirculatingCurrentSuppressionControl
@shadow :configuration ZeroSequenceCurrentControl P.ZeroSequenceCurrentControl
@shadow :configuration CirculatingCurrentSuppressionControl P.CirculatingCurrentSuppressionControl
@shadow :configuration CirculatingCurrentControl P.CirculatingCurrentControl
@shadow :configuration UncompensatedModulation P.UncompensatedModulation
@shadow :configuration CompensatedModulation P.CompensatedModulation
@shadow :configuration ΔdqControlGFL P.ΔdqControlGFL
@shadow :configuration ΔdqControlGFM P.ΔdqControlGFM
@shadow :configuration ΣdqzControlTEC P.ΣdqzControlTEC
@shadow :configuration ΣdqzControlLEC P.ΣdqzControlLEC
@shadow :configuration MMC P.MMC

@shadow :configuration ElectricalTLC P.ElectricalTLC
@shadow :configuration NoModulation P.NoModulation
@shadow :configuration DelayModulation P.DelayModulation
@shadow :configuration PadeModulation P.PadeModulation
@shadow :configuration TLC P.TLC

const _MMC_MODULAR_KEYS = Set((
    :elec, :meas, :sync, :delta_control, :sigma_control, :modulation, :setpoint, :limits,
))
const _MMC_LEGACY_KEYS = Set((
    :ω₀, :P, :Q, :P_dc, :P_min, :P_max, :Q_min, :Q_max, :θ, :Vₘ, :Vᵈᶜ,
    :Lₐᵣₘ, :Rₐᵣₘ, :Cₐᵣₘ, :N, :Lᵣ, :Rᵣ, :gfm, :controls, :equilibrium,
    :A, :B, :C, :D, :timeDelay, :padeOrderNum, :padeOrderDen,
    :vACbase_LL_RMS, :Sbase, :vDCbase, :turnsRatio, :occ, :ccc, :pll, :p, :q, :dc,
))

const _TLC_MODULAR_KEYS = Set((
    :elec, :meas, :sync, :outerActive, :outerReactive, :innerVoltage,
    :innerCurrent, :mod, :setpoint, :limits,
))
const _TLC_LEGACY_KEYS = Set((
    :ω₀, :P, :Q, :P_dc, :P_min, :P_max, :Q_min, :Q_max, :θ, :Vₘ, :Vᵈᶜ,
    :Lᵣ, :Rᵣ, :Lₐᵣₘ, :Rₐᵣₘ, :pll, :v_meas_filt, :i_meas_filt, :p, :q,
    :dc, :occ, :vac, :vac_supp, :controls, :equilibrium, :A, :B, :C, :D,
    :timeDelay, :padeOrderNum, :padeOrderDen, :vACbase_LL_RMS, :Sbase, :vDCbase,
    :iDCbase, :vACbase, :iACbase, :debug,
))

function _check_converter_keywords(kind::AbstractString, names, modular, legacy)
    modular_used = sort!(collect(intersect(Set(names), modular)); by = string)
    legacy_used = sort!(collect(intersect(Set(names), legacy)); by = string)
    if !isempty(modular_used) && !isempty(legacy_used)
        throw(ArgumentError(
            "$kind received incompatible modular keywords $(modular_used) and legacy keywords $(legacy_used)",
        ))
    end
    return isempty(legacy_used) ? :modular : :legacy
end

function _legacy_setpoint(kwargs)
    value(key, default) = haskey(kwargs, key) ? kwargs[key] : default
    return P.Setpoint(
        Pac = Float64(value(:P, 0.0)),
        Qac = Float64(value(:Q, 0.0)),
        θac = Float64(value(:θ, 0.0)),
        Vac = Float64(value(:Vₘ, 220 * sqrt(2 / 3))),
        Pdc = Float64(value(:P_dc, 0.0)),
        Vdc = Float64(value(:Vᵈᶜ, 0.0)),
    )
end

function _legacy_limits(kwargs)
    value(key, default) = haskey(kwargs, key) ? kwargs[key] : default
    return P.Limits(
        P_min = Float64(value(:P_min, 0.9)),
        P_max = Float64(value(:P_max, 1.1)),
        Q_min = Float64(value(:Q_min, -0.5)),
        Q_max = Float64(value(:Q_max, 0.5)),
    )
end

_legacy_field(value, name, default) =
    value !== nothing && hasproperty(value, name) ? getproperty(value, name) : default

function _legacy_pi(value)
    return P.PIControl(
        Kp = Float64(_legacy_field(value, :Kp, _legacy_field(value, :Kₚ, 0.0))),
        Ki = Float64(_legacy_field(value, :Ki, _legacy_field(value, :Kᵢ, 0.0))),
    )
end

function _legacy_filter(value)
    order = Int(_legacy_field(value, :n_f, 0))
    cutoff = Float64(_legacy_field(value, :ω_f, 0.0))
    return order > 0 && cutoff > 0 ? P.Butterworth(order = order, ωc = cutoff) : P.NoFilter()
end

function _legacy_controls(kwargs)
    controls = Dict{Symbol,Any}()
    if haskey(kwargs, :controls) && kwargs.controls !== nothing
        for (name, value) in kwargs.controls
            controls[name] = value
        end
    end
    for name in (:pll, :v_meas_filt, :i_meas_filt, :p, :q, :dc, :occ, :vac, :vac_supp, :ccc, :vse, :vi)
        haskey(kwargs, name) && (controls[name] = kwargs[name])
    end
    return controls
end

function _legacy_tlc(kwargs)
    value(key, default) = haskey(kwargs, key) ? kwargs[key] : default
    controls = _legacy_controls(kwargs)
    vac_filter = _legacy_filter(get(controls, :v_meas_filt, nothing))
    iac_filter = _legacy_filter(get(controls, :i_meas_filt, nothing))
    vdc_filter = _legacy_filter(get(controls, :dc, nothing))
    meas = value(:meas, P.Measurement(v_ac = vac_filter, i_ac = iac_filter, v_dc = vdc_filter))
    sync = value(:sync, begin
        controller = get(controls, :pll, nothing)
        controller === nothing ? P.NoSynchronization() : P.PLLSynchronization(
            pi_ctrl = _legacy_pi(controller), filter = _legacy_filter(controller),
        )
    end)
    outer_active = value(:outerActive, begin
        if haskey(controls, :dc)
            P.OuterActiveVdcControl(pi_ctrl = _legacy_pi(controls[:dc]))
        elseif haskey(controls, :p)
            P.OuterActivePowerControl(pi_ctrl = _legacy_pi(controls[:p]))
        else
            P.NoOuterActiveControl()
        end
    end)
    outer_reactive = value(:outerReactive, begin
        if haskey(controls, :vac)
            P.OuterReactiveVacControl(pi_ctrl = _legacy_pi(controls[:vac]))
        elseif haskey(controls, :q) || haskey(controls, :vac_supp)
            controller = haskey(controls, :q) ? controls[:q] : controls[:vac_supp]
            support = if haskey(controls, :vac_supp)
                legacy = controls[:vac_supp]
                P.VoltageSupportLag(
                    K = Float64(_legacy_field(legacy, :Kₚ, 0.0)),
                    ωc = Float64(_legacy_field(legacy, :ω_f, 0.0)),
                )
            else
                P.NoVoltageSupport()
            end
            P.OuterReactiveQControl(pi_ctrl = _legacy_pi(controller), support = support)
        else
            P.NoOuterReactiveControl()
        end
    end)
    inner_current = value(:innerCurrent, begin
        controller = get(controls, :occ, nothing)
        controller === nothing ? P.NoInnerCurrentControl() : P.InnerCurrentPIControl(
            pi_ctrl = _legacy_pi(controller), filter = _legacy_filter(controller),
        )
    end)
    elec = haskey(kwargs, :elec) ? kwargs.elec : P.ElectricalTLC(
        ωbase = Float64(value(:ω₀, 100π)),
        Lᵣ = Float64(value(:Lᵣ, 60e-3)),
        Rᵣ = Float64(value(:Rᵣ, 0.535)),
        vACbase_LL_RMS = Float64(value(:vACbase_LL_RMS, 220.0)),
        Sbase = Float64(value(:Sbase, 500.0)),
        vDCbase = Float64(value(:vDCbase, 640.0)),
    )
    mod = haskey(kwargs, :mod) ? kwargs.mod : begin
        delay = Float64(value(:timeDelay, 0.0))
        numerator = Int(value(:padeOrderNum, 0))
        denominator = Int(value(:padeOrderDen, 0))
        !iszero(delay) && (numerator > 0 || denominator > 0) ?
            P.DelayModulation(; timeDelay = delay, padeOrderNum = numerator, padeOrderDen = denominator) :
            P.NoModulation()
    end
    return P.tlc(
        elec = elec,
        meas = meas,
        sync = sync,
        outerActive = outer_active,
        outerReactive = outer_reactive,
        innerVoltage = value(:innerVoltage, P.NoInnerVoltageControl()),
        innerCurrent = inner_current,
        mod = mod,
        setpoint = value(:setpoint, _legacy_setpoint(kwargs)),
        limits = value(:limits, _legacy_limits(kwargs)),
        connection = value(:connection, true),
    )
end

function _legacy_mmc(kwargs)
    value(key, default) = haskey(kwargs, key) ? kwargs[key] : default
    controls = _legacy_controls(kwargs)
    elec = P.ElectricalMMC(
        Lₐᵣₘ = Float64(value(:Lₐᵣₘ, 50e-3)),
        Rₐᵣₘ = Float64(value(:Rₐᵣₘ, 1.07)),
        Cₐᵣₘ = Float64(value(:Cₐᵣₘ, 10e-3)),
        N = Int(value(:N, 400)),
        Lᵣ = Float64(value(:Lᵣ, 60e-3)),
        Rᵣ = Float64(value(:Rᵣ, 0.535)),
        ωbase = Float64(value(:ω₀, 100π)),
        vACbase_LL_RMS = Float64(value(:vACbase_LL_RMS, 380.0)),
        Sbase = Float64(value(:Sbase, 1000.0)),
        vDC_base = Float64(value(:vDCbase, 640.0)),
        turnsRatio = Float64(value(:turnsRatio, 1.0)),
    )
    pll_controller = get(controls, :pll, nothing)
    pll = pll_controller === nothing ? nothing : P.PLLSynchronization(
        pi_ctrl = _legacy_pi(pll_controller), filter = _legacy_filter(pll_controller),
    )
    sync = value(:sync, begin
        vse = get(controls, :vse, nothing)
        if Bool(value(:gfm, false)) && vse !== nothing
            P.VSEWithDamping(
                H = Float64(_legacy_field(vse, :H, 5.0)),
                K_d = Float64(_legacy_field(vse, :K_d, 100.0)),
                K_ω = Float64(_legacy_field(vse, :K_ω, 10.0)),
                ω_ref = Float64(_legacy_field(vse, :ref_ω, 1.0)),
                pll = something(pll, P.PLLSynchronization(pi_ctrl = P.PIControl(), filter = P.NoFilter())),
            )
        else
            something(pll, P.NoSynchronization())
        end
    end)
    outer_active = if haskey(controls, :dc)
        P.OuterActiveVdcControl(pi_ctrl = _legacy_pi(controls[:dc]))
    elseif haskey(controls, :p)
        P.OuterActivePowerControl(pi_ctrl = _legacy_pi(controls[:p]))
    else
        P.NoOuterActiveControl()
    end
    outer_reactive = if haskey(controls, :vac)
        P.OuterReactiveVacControl(pi_ctrl = _legacy_pi(controls[:vac]))
    elseif haskey(controls, :q)
        P.OuterReactiveQControl(pi_ctrl = _legacy_pi(controls[:q]))
    else
        P.NoOuterReactiveControl()
    end
    occ = haskey(controls, :occ) ? P.InnerCurrentPIControl(
        pi_ctrl = _legacy_pi(controls[:occ]), filter = _legacy_filter(controls[:occ]),
    ) : P.NoInnerCurrentControl()
    delta = value(:delta_control, P.ΔdqControlGFL(
        outer_active = outer_active,
        outer_reactive = outer_reactive,
        occ = occ,
    ))
    sigma = value(:sigma_control, P.ΣdqzControlTEC(
        tec = P.NoTotalEnergyControl(),
        zscc = P.NoZeroSequenceCurrentControl(),
        ccsc = P.NoCirculatingCurrentSuppressionControl(),
    ))
    modulation = value(:modulation, P.UncompensatedModulation(
        timeDelay = Float64(value(:timeDelay, 0.0)),
        padeOrderNum = Int(value(:padeOrderNum, 0)),
        padeOrderDen = Int(value(:padeOrderDen, 0)),
    ))
    return P.mmc(
        elec = elec,
        meas = value(:meas, P.Measurement()),
        sync = sync,
        delta_control = delta,
        sigma_control = sigma,
        modulation = modulation,
        setpoint = value(:setpoint, _legacy_setpoint(kwargs)),
        limits = value(:limits, _legacy_limits(kwargs)),
        connection = value(:connection, true),
    )
end

struct _ConverterMaterializer{Kind,N} end

function (::_ConverterMaterializer{:mmc,N})(values...) where {N}
    kwargs = NamedTuple{N}(values)
    route = _check_converter_keywords("mmc", N, _MMC_MODULAR_KEYS, _MMC_LEGACY_KEYS)
    return route === :legacy ? _legacy_mmc(kwargs) : P.mmc(; kwargs...)
end

function (::_ConverterMaterializer{:tlc,N})(values...) where {N}
    kwargs = NamedTuple{N}(values)
    route = _check_converter_keywords("tlc", N, _TLC_MODULAR_KEYS, _TLC_LEGACY_KEYS)
    return route === :legacy ? _legacy_tlc(kwargs) : P.tlc(; kwargs...)
end

function mmc(; kwargs...)
    names = keys(kwargs)
    _check_converter_keywords("mmc", names, _MMC_MODULAR_KEYS, _MMC_LEGACY_KEYS)
    return Gridspace{Any}(
        _ConverterMaterializer{:mmc,names}(), map(_axis, Tuple(values(kwargs))), names,
    )
end

function tlc(; kwargs...)
    names = keys(kwargs)
    _check_converter_keywords("tlc", names, _TLC_MODULAR_KEYS, _TLC_LEGACY_KEYS)
    return Gridspace{Any}(
        _ConverterMaterializer{:tlc,names}(), map(_axis, Tuple(values(kwargs))), names,
    )
end

_register_shadow!(:mmc, :element)
_register_shadow!(:tlc, :element)
