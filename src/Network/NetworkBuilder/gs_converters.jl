@gridconstructor P.ElectricalMMC P.ElectricalMMC
@gridconstructor P.NoTotalEnergyControl P.NoTotalEnergyControl
@gridconstructor P.TotalEnergyControl P.TotalEnergyControl
@gridconstructor P.ΣEnergyControl P.ΣEnergyControl
@gridconstructor P.ΔEnergyControl P.ΔEnergyControl
@gridconstructor P.NoZeroSequenceCurrentControl P.NoZeroSequenceCurrentControl
@gridconstructor P.NoCirculatingCurrentSuppressionControl P.NoCirculatingCurrentSuppressionControl
@gridconstructor P.ZeroSequenceCurrentControl P.ZeroSequenceCurrentControl
@gridconstructor P.CirculatingCurrentSuppressionControl P.CirculatingCurrentSuppressionControl
@gridconstructor P.CirculatingCurrentControl P.CirculatingCurrentControl
@gridconstructor P.UncompensatedModulation P.UncompensatedModulation
@gridconstructor P.CompensatedModulation P.CompensatedModulation
@gridconstructor P.ΔdqControlGFL P.ΔdqControlGFL
@gridconstructor P.ΔdqControlGFM P.ΔdqControlGFM
@gridconstructor P.ΣdqzControlTEC P.ΣdqzControlTEC
@gridconstructor P.ΣdqzControlLEC P.ΣdqzControlLEC
@gridconstructor P.MMC P.MMC

@gridconstructor P.ElectricalTLC P.ElectricalTLC
@gridconstructor P.NoModulation P.NoModulation
@gridconstructor P.DelayModulation P.DelayModulation
@gridconstructor P.PadeModulation P.PadeModulation
@gridconstructor P.TLC P.TLC

const _MMC_MODULAR_KEYS = Set((
    :elec, :meas, :sync, :delta_control, :sigma_control, :modulation, :limits,
))
const _MMC_LEGACY_KEYS = Set((
    :ω₀, :P, :Q, :P_dc, :P_min, :P_max, :Q_min, :Q_max, :θ, :Vₘ, :Vᵈᶜ,
    :Lₐᵣₘ, :Rₐᵣₘ, :Cₐᵣₘ, :N, :Lᵣ, :Rᵣ, :gfm, :controls, :equilibrium,
    :A, :B, :C, :D, :timeDelay, :padeOrderNum, :padeOrderDen,
    :vACbase_LL_RMS, :Sbase, :vDCbase, :turnsRatio, :occ, :ccc, :pll, :p, :q, :dc,
    :energy, :zcc, :vac, :vac_supp, :f_supp, :v_meas_filt, :i_meas_filt,
))

const _TLC_MODULAR_KEYS = Set((
    :elec, :meas, :sync, :outerActive, :outerReactive, :innerVoltage,
    :innerCurrent, :mod, :limits,
))
const _TLC_LEGACY_KEYS = Set((
    :ω₀, :P, :Q, :P_dc, :P_min, :P_max, :Q_min, :Q_max, :θ, :Vₘ, :Vᵈᶜ,
    :Lᵣ, :Rᵣ, :Lₐᵣₘ, :Rₐᵣₘ, :pll, :v_meas_filt, :i_meas_filt, :p, :q,
    :dc, :occ, :vac, :vac_supp, :controls, :equilibrium, :A, :B, :C, :D,
    :timeDelay, :padeOrderNum, :padeOrderDen, :vACbase_LL_RMS, :Sbase, :vDCbase,
    :iDCbase, :vACbase, :iACbase, :debug, :f_supp,
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

# A controller reference supplies an absent setpoint. Explicit network values
# remain authoritative for both power flow and the dynamic equilibrium.
function _legacy_setpoint(kwargs, controls, kind::Symbol, elec, name::Symbol)
    defaults = _legacy_setpoint_defaults(kwargs)
    supplied = haskey(kwargs, :setpoint) ? kwargs.setpoint : P.Setpoint()
    fields = fieldnames(P.Setpoint)
    values = Dict{Symbol,Union{Float64,Missing}}(field => getfield(supplied, field) for field in fields)
    for (key, field, scale) in ((:P, :Pac, 1.0), (:Q, :Qac, 1.0),
            (:θ, :θac, 1.0), (:Vₘ, :Vac, sqrt(2)), (:P_dc, :Pdc, 1.0), (:Vᵈᶜ, :Vdc, 1.0))
        ismissing(values[field]) && haskey(kwargs, key) && !ismissing(kwargs[key]) &&
            (values[field] = Float64(kwargs[key]) * scale)
    end
    dcbase = kind === :mmc ? elec.vDC_base : elec.vDCbase
    power_scale = kind === :mmc ? 1.0 : elec.Sbase
    for (control, field, scale) in ((:p, :Pac, power_scale), (:q, :Qac, power_scale),
            (:dc, :Vdc, dcbase), (:vac, :Vac, 1.0), (:vac_supp, :Vac, 1.0))
        ref = _legacy_reference(get(controls, control, nothing))
        ref === nothing && continue
        reference = ref * scale
        if ismissing(values[field])
            values[field] = reference
        elseif values[field] != reference
            @warn "converter :$name: legacy :$control reference $reference differs from setpoint $(values[field]); using setpoint" converter=name control=control legacy_reference=reference setpoint=values[field]
        end
    end
    return P.Setpoint(; (field => ismissing(values[field]) ? getfield(defaults, field) : values[field] for field in fields)...)
end

function _legacy_setpoint_defaults(kwargs)
    value(key, default) = haskey(kwargs, key) && !ismissing(kwargs[key]) ? kwargs[key] : default
    return P.Setpoint(
        Pac = Float64(value(:P, 0.0)),
        Qac = Float64(value(:Q, 0.0)),
        θac = Float64(value(:θ, 0.0)),
        Vac = Float64(value(:Vₘ, 220.0)) * sqrt(2), # Convert RMS to peak
        Pdc = Float64(value(:P_dc, 0.0)),
        Vdc = Float64(value(:Vᵈᶜ, 0.0)),
    )
end

function _legacy_reference(controller)
    ref = _legacy_field(controller, :ref, nothing)
    ref === nothing && return nothing
    value = ref isa AbstractArray || ref isa Tuple ? first(ref) : ref
    return iszero(value) ? nothing : Float64(value)
end

function _legacy_frequency_support(controls)
    controller = get(controls, :f_supp, nothing)
    return controller === nothing ? P.NoFrequencySupport() : P.FrequencySupportLag(
        Kω = _legacy_pi(controller).Kp,
        ωc = Float64(_legacy_field(controller, :ω_f, 0.0)))
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
    for name in (:pll, :v_meas_filt, :i_meas_filt, :p, :q, :dc, :occ, :vac, :vac_supp, :energy, :zcc, :ccc, :f_supp, :vse, :vi)
        haskey(kwargs, name) && (controls[name] = kwargs[name])
    end
    return controls
end

function _legacy_tlc(kwargs, name::Symbol = :tlc)
    value(key, default) = haskey(kwargs, key) ? kwargs[key] : default
    controls = _legacy_controls(kwargs)
    vac_filter = _legacy_filter(get(controls, :v_meas_filt, nothing))
    iac_filter = _legacy_filter(get(controls, :i_meas_filt, nothing))
    meas = value(:meas, P.Measurement(v_ac = vac_filter, i_ac = iac_filter))
    sync = value(:sync, begin
        controller = get(controls, :pll, nothing)
        controller === nothing ? P.NoSynchronization() : P.PLLSynchronization(
            pi_ctrl = _legacy_pi(controller), filter = _legacy_filter(controller),
        )
    end)
    outer_active = value(:outerActive, begin
        if haskey(controls, :p)
            P.OuterActivePowerControl(pi_ctrl = _legacy_pi(controls[:p]), support = _legacy_frequency_support(controls))
        elseif haskey(controls, :dc)
            P.OuterActiveVdcControl(pi_ctrl = _legacy_pi(controls[:dc]), filter = _legacy_filter(controls[:dc]))
        else
            P.NoOuterActiveControl()
        end
    end)
    outer_reactive = value(:outerReactive, begin
        if haskey(controls, :q) || haskey(controls, :vac_supp)
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
        elseif haskey(controls, :vac)
            P.OuterReactiveVacControl(pi_ctrl = _legacy_pi(controls[:vac]), filter = _legacy_filter(controls[:vac]))
        else
            P.NoOuterReactiveControl()
        end
    end)
    inner_current = value(:innerCurrent, begin
        controller = get(controls, :occ, nothing)
        controller === nothing ? P.NoInnerCurrentControl() : P.InnerCurrentPIControl(
            pi_ctrl = _legacy_pi(controller),
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
        setpoint = _legacy_setpoint(kwargs, controls, :tlc, elec, name),
        limits = value(:limits, _legacy_limits(kwargs)),
        connection = value(:connection, true),
    )
end

function _legacy_mmc(kwargs, name::Symbol = :mmc)
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
    outer_active = if haskey(controls, :p)
        P.OuterActivePowerControl(pi_ctrl = _legacy_pi(controls[:p]), support = _legacy_frequency_support(controls))
    elseif haskey(controls, :dc)
        P.OuterActiveVdcControl(pi_ctrl = _legacy_pi(controls[:dc]), filter = _legacy_filter(controls[:dc]))
    else
        P.NoOuterActiveControl()
    end
    outer_reactive = if haskey(controls, :q)
        legacy = get(controls, :vac_supp, nothing)
        # A first-order magnitude filter is exactly a lag on K*(Vref-V).
        # Static and higher-order legacy droop require a different support block.
        support = legacy !== nothing && _legacy_field(legacy, :n_f, 0) == 1 ?
            P.VoltageSupportLag(K = _legacy_pi(legacy).Kp,
                ωc = Float64(_legacy_field(legacy, :ω_f, 0.0))) : P.NoVoltageSupport()
        P.OuterReactiveQControl(pi_ctrl = _legacy_pi(controls[:q]), support = support)
    elseif haskey(controls, :vac)
        P.OuterReactiveVacControl(pi_ctrl = _legacy_pi(controls[:vac]), filter = _legacy_filter(controls[:vac]))
    else
        P.NoOuterReactiveControl()
    end
    occ = haskey(controls, :occ) ? P.InnerCurrentPIControl(
        pi_ctrl = _legacy_pi(controls[:occ]), filter = _legacy_filter(controls[:occ]),
        activate_ω_c_multiplication = false,
    ) : P.NoInnerCurrentControl()
    delta = value(:delta_control, P.ΔdqControlGFL(
        outer_active = outer_active,
        outer_reactive = outer_reactive,
        occ = occ,
    ))
    energy = get(controls, :energy, nothing)
    power_filter = P.measurement_filter_ss(_legacy_filter(get(controls, :q, nothing)))
    tec = energy === nothing ? P.NoTotalEnergyControl() : P.TotalEnergyControl{typeof(power_filter)}(
        _legacy_pi(energy), something(_legacy_reference(energy), 1.0), power_filter, true)
    ccc = get(controls, :ccc, nothing)
    ccc_ref = _legacy_field(ccc, :ref, [0.0])
    refs = length(ccc_ref) == 1 && iszero(first(ccc_ref)) ? (0.0, 0.0) : Tuple(ccc_ref)
    sigma = value(:sigma_control, P.ΣdqzControlTEC(
        tec = tec,
        zscc = haskey(controls, :zcc) ? P.ZeroSequenceCurrentControl(_legacy_pi(controls[:zcc])) : P.NoZeroSequenceCurrentControl(),
        ccsc = ccc === nothing ? P.NoCirculatingCurrentSuppressionControl() : P.CirculatingCurrentSuppressionControl(_legacy_pi(ccc); ref = refs),
    ))
    modulation = value(:modulation, P.UncompensatedModulation(
        timeDelay = Float64(value(:timeDelay, 0.0)),
        padeOrderNum = Int(value(:padeOrderNum, 0)),
        padeOrderDen = Int(value(:padeOrderDen, 0)),
    ))
    return P.mmc(
        elec = elec,
        meas = value(:meas, P.Measurement(
            v_ac = _legacy_filter(get(controls, :v_meas_filt, nothing)),
            i_ac = _legacy_filter(get(controls, :i_meas_filt, nothing)),
            P_ac = _legacy_filter(get(controls, :p, nothing)),
            Q_ac = _legacy_filter(get(controls, :q, nothing)))),
        sync = sync,
        delta_control = delta,
        sigma_control = sigma,
        modulation = modulation,
        setpoint = _legacy_setpoint(kwargs, controls, :mmc, elec, name),
        limits = value(:limits, _legacy_limits(kwargs)),
        connection = value(:connection, true),
    )
end

struct _ConverterMaterializer{Kind,N}
    name::Symbol
end
_ConverterMaterializer{Kind,N}() where {Kind,N} = _ConverterMaterializer{Kind,N}(Kind)

_named_converter(name, value) = value
function _named_converter(name::Symbol, space::Gridspace{P.Element,<:_ConverterMaterializer})
    return typeof(space)(typeof(space.target)(name), space.axes, space.names, space.combine)
end

function (target::_ConverterMaterializer{:mmc,N})(values...) where {N}
    kwargs = NamedTuple{N}(values)
    route = _check_converter_keywords("mmc", N, _MMC_MODULAR_KEYS, _MMC_LEGACY_KEYS)
    return route === :legacy ? _legacy_mmc(kwargs, target.name) : P.mmc(; kwargs...)
end

function (target::_ConverterMaterializer{:tlc,N})(values...) where {N}
    kwargs = NamedTuple{N}(values)
    route = _check_converter_keywords("tlc", N, _TLC_MODULAR_KEYS, _TLC_LEGACY_KEYS)
    return route === :legacy ? _legacy_tlc(kwargs, target.name) : P.tlc(; kwargs...)
end

function _mmc_gridspace(; kwargs...)
    names = keys(kwargs)
    _check_converter_keywords("mmc", names, _MMC_MODULAR_KEYS, _MMC_LEGACY_KEYS)
    inputs = (; kwargs...)
    return _lift_gridspace(
        P.Element,
        _ConverterMaterializer{:mmc,names}(),
        inputs,
        Val(:product),
    )
end

function _tlc_gridspace(; kwargs...)
    names = keys(kwargs)
    _check_converter_keywords("tlc", names, _TLC_MODULAR_KEYS, _TLC_LEGACY_KEYS)
    inputs = (; kwargs...)
    return _lift_gridspace(
        P.Element,
        _ConverterMaterializer{:tlc,names}(),
        inputs,
        Val(:product),
    )
end

"""
    mmc(Grid; kwargs...)

Construct a lazy MMC `Gridspace` through positional dispatch. The keyword set
may use either the modular API or the supported legacy API, but the two forms
cannot be mixed. Ordinary keyword-only calls remain scalar constructors.
"""
P.mmc(::typeof(Grid); kwargs...) = _mmc_gridspace(; kwargs...)

"""
    tlc(Grid; kwargs...)

Construct a lazy two-level-converter `Gridspace` through positional dispatch.
The keyword set may use either the modular API or the supported legacy API, but
the two forms cannot be mixed. Ordinary keyword-only calls remain scalar
constructors.
"""
P.tlc(::typeof(Grid); kwargs...) = _tlc_gridspace(; kwargs...)
