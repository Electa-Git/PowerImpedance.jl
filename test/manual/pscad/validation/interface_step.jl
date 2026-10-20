# Discrete DUT realization reference; residual_step.jl defines fixture/probe columns and
# their residual integration-step comparisons.
zero_modulation_delay(::Any) = false
zero_modulation_delay(::PowerImpedance.NoModulation) = true
zero_modulation_delay(m::PowerImpedance.DelayModulation) = iszero(m.delay.timeDelay)
zero_modulation_delay(m::PowerImpedance.UncompensatedModulation) =
    all(d -> iszero(d.timeDelay), (m.delay1, m.delay2, m.delay3))
zero_modulation_delay(m::PowerImpedance.CompensatedModulation) =
    all(d -> iszero(d.timeDelay), (m.delay1, m.delay2a, m.delay2b, m.delay3, m.delay4))
interface_step_eligible(::Any) = false
interface_step_eligible(m::PowerImpedance.TLC) = zero_modulation_delay(m.mod)
interface_step_eligible(m::PowerImpedance.MMC) = zero_modulation_delay(m.modulation)

one_step_modulation(::PowerImpedance.UncompensatedModulation, dt) =
    PowerImpedance.UncompensatedModulation(timeDelay = dt, padeOrderNum = 3, padeOrderDen = 3)
one_step_modulation(::PowerImpedance.CompensatedModulation, dt) =
    PowerImpedance.CompensatedModulation(timeDelay = dt, padeOrderNum = 3, padeOrderDen = 3)
function one_step_model(m::PowerImpedance.MMC, dt)
    return PowerImpedance.MMC(m.meas, m.sync, m.delta_control, m.sigma_control,
        one_step_modulation(m.modulation, dt), m.elec)
end
function one_step_model(m::PowerImpedance.TLC, dt)
    return PowerImpedance.TLC(m.elec, m.meas, m.sync, m.outerActive, m.outerReactive,
        m.innerVoltage, m.innerCurrent,
        PowerImpedance.DelayModulation(timeDelay = dt, padeOrderNum = 3, padeOrderDen = 3))
end
modulation_states(m::PowerImpedance.MMC) = PowerImpedance.statenames(m.modulation)
modulation_states(m::PowerImpedance.TLC) = PowerImpedance.statenames(m.mod)

# Exact one-step modulation feedback uses the same carrier correction and delay-state
# Schur replacement as interface_step_reference.
function one_step_full_y(original,h)
    interface_step_eligible(original.element_model) || return s->physical_y(original,s)
    isfinite(h) && h>0 || error("interface reference requires a positive finite step")
    e=PowerImpedance.Element(element_model=one_step_model(original.element_model,h),input_pins=original.input_pins,output_pins=original.output_pins,
        transformation=original.transformation,setpoint=original.setpoint,limits=original.limits)
    e.symbol=original.symbol;PowerImpedance.update!(e,original.setpoint)
    names=PowerImpedance.statenames(e.element_model);delayed=Set(modulation_states(e.element_model))
    d=findall(in(delayed),collect(names));r=setdiff(1:length(names),d)
    pade=PowerImpedance.PadeDelay(timeDelay=h,padeOrderNum=3,padeOrderDen=3)
    base=device_bases(e.element_model.elec);n=length(r)
    function response(s)
        gp=only(pade.C*((s*I-pade.A)\pade.B)+pade.D)
        effect=vcat(e.A[r,d],e.C[:,d])*((s*I-e.A[d,d])\hcat(e.A[d,r],e.B[d,:]))
        eff=[e.A[r,r] e.B[r,:];e.C[:,r] e.D]+effect*((exp(-s*h)+1)/(gp+1))
        y=eff[n+1:end,1:n]*((s*I-eff[1:n,1:n])\eff[1:n,n+1:end])+eff[n+1:end,n+1:end]
        return y.*base.current_outputs./base.voltage_inputs'
    end
    return response
end

function interface_step_reference(net, spec; dc_conductance = nothing)
    original = net.elements[:DUT]
    interface_step_eligible(original.element_model) || return nothing
    dt = spec.time_step
    isfinite(dt) && dt > 0 || error("interface reference requires a positive finite step")
    full_y = one_step_full_y(original, dt)
    bases = device_bases(original.element_model.elec)
    matrices = Matrix{ComplexF64}[]
    for frequency in spec.frequencies
        s = ComplexF64(im * 2π * frequency)
        y = full_y(s)
        if haskey(net.elements, :DC_load)
            g = dc_conductance === nothing ?
                PowerImpedance.get_y(net.elements[:DC_load], s)[1,1] : dc_conductance
            y = y[2:3,2:3] - y[2:3,1:1] * ((y[1,1]+g) \ y[1:1,2:3])
        else
            y = y[bases.ac_indices, bases.ac_indices]
        end
        push!(matrices, y)
    end
    return cat(matrices...; dims = 3)
end

function interface_step_comparison(spec, measured, reference, quality)
    rows = response_rows(spec, scale_response(measured, spec), scale_response(reference, spec);
        active = true, valid = quality["valid"], model_mismatch = quality["model_mismatch"])
    status = !isempty(quality["model_mismatch"]) ? "model_mismatch" :
        !quality["valid"] ? "invalid_measurement" : all(row.within_tolerance for row in rows) ? "passed" : "failed"
    result = Dict("label" => "Julia + one inherent interface step", "status" => status,
        "step_s" => spec.time_step, "transport" => "exact exp(-s dt) inside modulation feedback, native carrier corrections",
        "valid" => quality["valid"], "max_frobenius_error" => maximum(row.frobenius_error for row in rows),
        "original_model_status" => quality["status"])
    return rows, result
end

function record_interface_comparison!(record, net, spec, directory, comparison_directory)
    reference = interface_step_reference(net, spec)
    reference === nothing && return nothing
    path = joinpath(directory, "interface_step_reference.tsv")
    stored = read_response(path, length(spec.axes), spec.frequencies)
    native_reference_check(spec, reference, stored)["passed"] || error("interface-step reference changed")
    measured = read_response(joinpath(comparison_directory, "measured_S.tsv"), length(spec.axes), spec.frequencies)
    rows, result = interface_step_comparison(spec, measured, stored, record["frequency_response_result"])
    write_table(joinpath(comparison_directory, "comparison_frequency_response_interface_step.tsv"), rows)
    record["interface_step_result"] = result
    return result
end
