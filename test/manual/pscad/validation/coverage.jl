# Frozen measurement definitions use the native element/network physics.
function port_probe(list, element, side)
    entry = only(filter(e -> e.name == element, list.elements))
    terminal = only(filter(t -> t.side == side, entry.terminals))
    return only(filter(b -> b.key == terminal.bus, list.buses))
end

function scan_definition(id, net, list)
    fixture(id).category == :device && return device_scan_definition(net,list; id)
    old = passive_settings()
    if id == "passive_ac_rlc"
        buses = [port_probe(list, :branch, 1)]
        currents = [("branch", "1")]
        quantity, dimension = "Y", 2
    elseif id in ("passive_dc_rlc", "dc_cable_ohl")
        last_element = id == "passive_dc_rlc" ? :rc : :ohl
        buses = [port_probe(list, :line, 1), port_probe(list, last_element, 2)]
        currents = [("line", "1"), (string(last_element), "2")]
        quantity, dimension = "Y", 1
    elseif id == "ieee9_bus_impedance"
        buses = [port_probe(list, :g1, 1), port_probe(list, :l5, 1)]
        currents = [("injection_1", "1"), ("injection_2", "1")]
        quantity, dimension = "Z", 2
    else
        buses = [port_probe(list, :line, 1), port_probe(list, :line, 2)]
        currents = [("line", "1"), ("line", "2")]
        quantity, dimension = "Y", 2
    end
    frequencies = id == "passive_ac_rlc" || dimension == 1 ? old.frequencies :
                  filter(!=(50.0), old.frequencies)
    # AC 50 Hz dq has an abc DC sideband. It is outside the AC line fit and
    # excites slow transformer flux offsets; exclude it before observing EMT.
    axes = id == "passive_ac_rlc" ? ["d", "q"] :
           ["p$(port)_$(axis)" for port in eachindex(buses)
            for axis in (dimension == 1 ? ("dc",) : ("d", "q"))]
    voltages = [dimension == 1 ? 2b.base_kV * something(b.vm_pu, 1.0) :
                sqrt(2) * b.base_kV * something(b.vm_pu, 1.0) for b in buses]
    id == "passive_ac_rlc" && (voltages[1] = old.voltage_base_kV)
    currents_base = [dimension == 1 ? 1000 / v : 2000 / (3v) for v in voltages]
    vbase = repeat(voltages; inner = dimension)
    ibase = repeat(currents_base; inner = dimension)
    lengths = [Float64(e.element_model.length)
               for e in values(net.elements)
               if e.element_model isa
                  Union{PowerImpedance.Cable, PowerImpedance.Overhead_line}]
    travel = isempty(lengths) ? 0.0 : minimum(lengths) / 299792458
    spec = merge(old,
        (; id, quantity, dimension, buses, currents, axes, frequencies,
            phases = [-π * k * (k - 1) / length(frequencies)
                      for k in eachindex(frequencies)],
            voltage_bases = vbase, current_bases = ibase, travel_lower_bound_s = travel,
            estimated_station_seconds = Dict("passive_ac_rlc" => 300, "passive_dc_rlc" => 360, "ac_ohl_untransposed" => 540, "ac_cable_coaxial" => 540, "dc_cable_ohl" => 480, "transformer_yy" => 540, "transformer_dyn11" => 540, "ieee9_bus_impedance" => 1080)[id]))
    reference = scan_reference(net, list, spec)
    normalized = scale_response(reference, spec)
    bound = maximum(sum(abs.(normalized); dims = 3))
    amplitude = id == "passive_ac_rlc" ? old.tone_peak_pu :
                min(old.tone_peak_pu, 0.004 / max(bound, 1.0))
    return merge(spec, (; tone_peak_pu = amplitude)), reference
end

function scan_reference(net, list, spec)
    if spec.id == "induction_machine"
        return induction_machine_reference(net, list, spec.frequencies)
    elseif fixture(spec.id).category == :device
        return cat((device_port_y(net, ComplexF64(im*2π*f))
            for f in spec.frequencies)...; dims=3)
    elseif spec.id == "passive_ac_rlc"
        return cat(
            (PowerImpedance.get_y(net.elements[:branch], ComplexF64(im * 2π * f))[1:2, 1:2]
            for f in spec.frequencies)...;
            dims = 3)
    elseif spec.id in ("ac_ohl_untransposed", "ac_cable_coaxial", "transformer_yy", "transformer_dyn11")
        return cat(
            (PowerImpedance.get_y(net.elements[:line], ComplexF64(im * 2π * f))
            for f in spec.frequencies)...;
            dims = 3)
    elseif spec.id == "ieee9_bus_impedance"
        inputs = reduce(vcat, [b.nets for b in spec.buses])
        nodes = unique([n for e in values(net.elements) for n in values(e.pins)])
        grounds = filter(n -> occursin("gnd", string(n)), nodes)
        order = [inputs; setdiff(nodes, [inputs; grounds])]
        topology = Dict{Symbol, Array{Union{Symbol, Int}}}(:node_list => order,
            :element_list => collect(keys(net.elements)), :output_list => grounds)
        return cat(
            (PowerImpedance.make_z(net, topology, copy(inputs), copy(grounds),
                 ComplexF64(im * 2π * f)) for f in spec.frequencies)...;
            dims = 3)
    end
    elements = spec.id == "passive_dc_rlc" ? [:line, :rc] : [:line, :ohl]
    # Match the exporter's two pole-to-ground references at ungrounded internal
    # DC buses. Their differential equivalent is 2*DC_REFERENCE_RESISTANCE.
    frequency_net = deepcopy(net)
    for bus in list.buses
        bus.kind == :dc && !(bus in spec.buses) || continue
        reference_name = Symbol("validation_reference_", bus.name)
        add!(frequency_net, reference_name, impedance(z = s -> 2P.DC_REFERENCE_RESISTANCE, pins = 1))
        connect!(frequency_net, (reference_name, Symbol("1.1")), only(bus.nets))
        connect!(frequency_net, (reference_name, Symbol("2.1")), :gnd_validation_dc)
        push!(elements, reference_name)
    end
    connect!(frequency_net)
    inputs = reduce(vcat, [b.nets for b in spec.buses])
    nodes = unique([n for name in elements
                    for n in values(frequency_net.elements[name].pins)
                    if !occursin("gnd", string(n))])
    order = [inputs; setdiff(nodes, inputs)]
    topology = Dict{Symbol, Array{Union{Symbol, Int}}}(:node_list => order,
        :element_list => elements, :output_list => Symbol[])
    matrices = Matrix{ComplexF64}[]
    for f in spec.frequencies
        y = PowerImpedance.make_y(frequency_net, topology, ComplexF64(im * 2π * f))
        n = length(inputs)
        push!(matrices, y[1:n, 1:n] -
                        y[1:n, (n + 1):end] *
                        (y[(n + 1):end, (n + 1):end] \ y[(n + 1):end, 1:n]))
    end
    return cat(matrices...; dims = 3)
end

function scale_response(matrix, spec)
    input = spec.quantity == "Y" ? spec.voltage_bases : spec.current_bases
    output = get(spec,:response_output_bases,spec.quantity == "Y" ? spec.current_bases : spec.voltage_bases)
    return matrix .* reshape(1 ./ output, :, 1, 1) .* reshape(input, 1, :, 1)
end

function band_sample_step(spec)
    # Nominal 50 Hz remains measured for the abc baseline-drift comparison. A dq tone also
    # measures its +/- nominal-frequency sidebands.
    highest = spec.dimension == 1 ? maximum(spec.frequencies) :
        max(spec.frequency, maximum(spec.frequencies) +
            (spec.dimension == 2 ? spec.frequency : 0.0))
    limit = floor(Int, 1 / (40highest * spec.time_step))
    boundaries = [spec.window_starts...; spec.window_duration; spec.simulation_time]
    ticks = round.(Int, boundaries ./ spec.time_step)
    all(isapprox(t * spec.time_step, b; rtol=0, atol=1e-12)
        for (t,b) in zip(ticks,boundaries)) || error("windows are not integration-grid coherent")
    common = reduce(gcd,ticks)
    tick_step = findfirst(k -> common % k == 0, limit:-1:1)
    tick_step === nothing && error("integration step undersamples the measured band")
    return (limit-tick_step+1) * spec.time_step
end

# Preparation only: retained even-ratio evidence remains readable as produced.
function check_recorder_sampling(spec)
    isfinite(spec.time_step) && spec.time_step > 0 &&
        isfinite(spec.sample_step) && spec.sample_step > 0 ||
        error("recorder and integration steps must be finite and positive")
    ratio = spec.sample_step / spec.time_step
    ticks = round(Int, ratio)
    isapprox(ratio, ticks; rtol = 0, atol = 1e-9) && isodd(ticks) ||
        error("preparation requires an odd integer sample_step / time_step ratio")
    burst = get(spec, :stimulus, "multitone") == "hann_burst"
    boundaries = burst ? (spec.injection_time, spec.ringdown..., spec.simulation_time) :
        (spec.window_starts..., spec.window_duration, spec.simulation_time)
    all(isapprox(t / spec.sample_step, round(t / spec.sample_step); rtol = 0, atol = 1e-7)
        for t in boundaries) || error("recorder windows are not sample coherent")
    if !burst
        tones = spec.dimension == 1 ? spec.frequencies : [spec.frequencies; spec.frequency]
        all(isapprox(f * spec.window_duration, round(f * spec.window_duration); rtol = 0, atol = 1e-9)
            for f in tones) || error("recorder windows are not tone coherent")
    end
    highest = maximum(spec.frequencies) + (spec.dimension == 2 ? spec.frequency : 0.0)
    spec.dimension == 1 || (highest = max(highest, spec.frequency))
    inv(2spec.sample_step) > 4highest || error("recorder Nyquist must exceed four times the measured band")
    return ticks
end

function scan_settings(spec)
    return P.SimulationSettings(simulation_time = spec.simulation_time,
        time_step = spec.time_step, sample_step = spec.sample_step,
        frequency = spec.frequency, source_ramp = 0.0, output_stem = "scan")
end

function scan_record(spec)
    record = Dict("quantity" => spec.quantity, "axes" => spec.axes,
        "coordinates" => spec.dimension == 3 ? "abc" : spec.dimension == 2 ? "dq" : "DC differential",
        "protocol" => get(spec, :protocol, ""),
        "applicable_comparison" => spec.dimension == 3 ? "phase-domain physics" : "native dq/DC physics",
        "phase_order" => spec.dimension == 3 ? ["a", "b", "c"] : String[],
        "SI_units" => fixture(spec.id).category == :coupled ? "phase kV/kA imply S for Y and ohm for direct Z; fixed nominal 50 Hz dq; declared aggregate bases and original individual single-device bases" : fixture(spec.id).category == :device ? "kV/kA: S; fixed nominal 50 Hz dq; declared external AC phase-peak voltage/current bases and total three-phase rating" :
            "phase kV/kA imply S for Y and ohm for Z; phase-peak AC bases, 1000 MVA total three-phase base",
        "IEEE9_blocks" => spec.id == "ieee9_bus_impedance" && spec.dimension == 3 ? "separate local Bus1/Bus5 3x3; full 6x6 transfer retained as evidence" : "not applicable",
        "frequencies" => spec.frequencies, "phases" => spec.phases,
        "tone_peak_pu" => spec.tone_peak_pu, "injection_time" => spec.injection_time,
        "window_starts" => collect(spec.window_starts), "window_duration" =>
            spec.window_duration,
        "simulation_time" => spec.simulation_time, "time_step" => spec.time_step,
        "sample_step" => spec.sample_step, "voltage_bases_kV" => spec.voltage_bases,
        "minimum_witness_window_s" => get(spec,:minimum_witness_window_s,0.1),
        "current_bases_kA" => spec.current_bases,
        "travel_time_lower_bound_s" => spec.travel_lower_bound_s,
        "estimated_station_seconds" => spec.estimated_station_seconds,
        "ports" => [Dict("bus" => b.name, "nets" => string.(b.nets), "angle_rad" =>
             something(b.va_rad, 0.0)) for b in spec.buses],
        "refinement" =>
            Dict("amplitude_change_limit" => 0.02, "step_change_limit" => 0.01,
                "selection" => get(spec, :protocol, "") == "abc_resonance" ?
                    "phase-a column; full extra resonance band for amplitude/step witnesses; completed base-band witnesses retained" :
                    "one worst-error column; half-step baseline plus column at worst frequency and 1000 Hz; retain predeclared coherent windows",
                "amplitude_scale" => 0.5, "half_step_s" => spec.time_step/2),
        "excluded_ac_frequency_Hz" =>
            spec.dimension == 2 && spec.id != "passive_ac_rlc" ? [50.0] : Float64[])
    haskey(spec, :settling) && (record["settling"] = spec.settling)
    if fixture(spec.id).category == :device
        record["drive"]="shunt current at converter AC terminal; measured voltage matrix is the Y input"
        spec.dc_voltage_base_kV===nothing || (record["dc_voltage_base_kV"]=spec.dc_voltage_base_kV)
        record["power_base_MVA"]=spec.power_base_MVA
        record["active"]=true
        record["dc_clamped"]=spec.dc_clamped
        record["reference_scope"]=spec.dc_voltage_base_kV===nothing ? "native machine full AC-terminal Y converted from per-unit to SI; native rt/lt retained" : spec.dc_clamped ? "native DUT AC block with DC clamped" : "native DUT + DC resistor AC-terminal Schur reduction; remote zero-voltage reference grounded"
        record["refinement"]["selection"]="one worst-error drive axis; qualify both V/Idrive and Iconverter/Idrive, including cross-axis voltage; half-step at worst frequency plus 1000 Hz"
        if spec.id == "induction_machine"
            record["drive"] = "shunt current at the machine AC terminal; measured voltage matrix is the Y input"
            record["reference_scope"] = "NetworkBuilder.get_y at the solved machine setpoint; SI_scale supplies S_base/Vac_base^2; inward terminal current"
            record["kcl_required"] = true
        end
    end
    if fixture(spec.id).category == :coupled
        record["power_base_MVA"]=spec.power_base_MVA
        record["active"]=true
        record["dc_clamped"]=spec.dc_clamped
        record["reference_scope"]="individual local device Y on original single-device bases; aggregate port Y and direct V/Idrive on predeclared aggregate bases"
        record["comparison_rule"]=Dict(string(k)=>v for (k,v) in pairs(ACTIVE_FREQUENCY_LIMITS))
        record["resonance_groups"]=get(spec,:resonance_groups,Vector{Int}[])
        if spec.id=="two_mmc_dc_cable"
            record["reference_scope"]="full 4x4 Y and direct Z over both AC ports, including every cross block; only internal DC voltages eliminated; native distributed dc_cable_ohl cable"
            record["dc_reference"]=string(spec.dc_reference)
            record["dc_transfer_witnesses"]=Dict("outputs"=>["both DC differential voltages","both inward cable currents"],
                "voltage_base_kV"=>800.,"current_base_kA"=>1.25,"independent_drives"=>spec.axes)
            record["cross_entry_accuracy"]="near-zero cross entries are scored only against the absolute floor; no relative-accuracy claim"
            record["distributed_admission_caveat"]="finite contour to 1 MHz and located roots only; infinite spectrum unenumerated and no closure-at-infinity proof; drift/window gates remain mandatory"
        end
        if spec.protocol=="composed_local"
            record["refinement"]["selection"]="one worst-error drive axis; full predeclared local band at half amplitude and half step; matching half-step baseline; original eight-second windows"
        end
    end
    return record
end

# Native state-space voltage inputs and inward-current outputs retain each
# converter's normalization. Measurement bases refer to the external terminal.
function device_bases(e::PowerImpedance.ElectricalTLC)
    return (voltage_inputs=[e.vDCbase,e.vACbase,e.vACbase],
        current_outputs=[e.iDCbase,e.iACbase,e.iACbase],
        ac_voltage=e.vACbase, ac_current=e.iACbase, dc_voltage=e.vDCbase, power=e.Sbase, ac_side=2, ac_indices=2:3)
end

function device_bases(e::PowerImpedance.ElectricalMMC)
    current = 2e.Sbase / (3e.vAC_base) * e.turnsRatio
    return (voltage_inputs=[e.vDC_base,e.vAC_base,e.vAC_base],
        current_outputs=[e.Sbase/e.vDC_base,current,current],
        ac_voltage=e.vAC_base/e.turnsRatio, ac_current=current,
        dc_voltage=e.vDC_base, power=e.Sbase, ac_side=2, ac_indices=2:3)
end

function device_bases(e::PowerImpedance.ElectricalSM)
    voltage=e.Vᵃᶜ_base*sqrt(2/3)
    current=2e.S_base/(3voltage)
    return (voltage_inputs=fill(voltage,2), current_outputs=fill(current,2),
        ac_voltage=voltage, ac_current=current, dc_voltage=nothing, power=e.S_base,
        ac_side=1, ac_indices=1:2)
end

# The machine's native get_y is per-unit; converters already return SI S.
physical_y(dut::PowerImpedance.Element, s)=PowerImpedance.get_y(dut,s)
function physical_y(dut::PowerImpedance.Element{<:PowerImpedance.SynchronousMachine}, s)
    e=dut.element_model.elec
    return PowerImpedance.get_y(dut,s)*(e.S_base/e.Vᵃᶜ_base^2)
end

function device_scan_definition(net,list; id="tlc_pq_freq_support")
    old=passive_settings()
    elec=net.elements[:DUT].element_model.elec
    bases=device_bases(elec)
    bus=port_probe(list,:DUT,bases.ac_side)
    frequencies=filter(!=(50.0),old.frequencies)
    spec=merge(old,(; id,quantity="Y",dimension=2,buses=[bus],
        currents=[("DUT",string(bases.ac_side))],axes=["p1_d","p1_q"], frequencies,
        phases=[-π*k*(k-1)/length(frequencies) for k in eachindex(frequencies)],
        voltage_bases=fill(bases.ac_voltage,2),current_bases=fill(bases.ac_current,2),
        dc_voltage_base_kV=bases.dc_voltage, power_base_MVA=bases.power,
        drive="current", dc_clamped=bases.dc_voltage!==nothing && !haskey(net.elements,:DC_load), active=true,protocol="dq_active", tone_peak_pu=5e-5,
        time_step=id=="tlc_vdc_q" ? 0.625e-6 : id=="mmc_vdc_q" ? 1.25e-6 : id=="mmc_gfm_lec_compensated" ? 1e-6 : 2.5e-6,sample_step=20e-6,injection_time=2.0,
        window_starts=(8.0,9.0),window_duration=1.0,simulation_time=10.0,
        travel_lower_bound_s=0.0,estimated_station_seconds=1800))
    id == "induction_machine" && return induction_machine_scan(net, list, spec)
    if id in ("mmc_pq", "mmc_pf_q", "mmc_p_qv", "mmc_p_vac")
        settling = gfl_settling(stability_gate(net, fixture(id)); fixture_id = id, tone_peak_pu = spec.tone_peak_pu)
        spec = merge(spec, (; window_starts = Tuple(settling["window_starts_s"]),
            simulation_time = settling["simulation_time_s"], settling, estimated_station_seconds = 3300))
    end
    if id=="synchronous_machine"
        gate=stability_gate(net,fixture(id))
        gate["status"]=="passed" || @warn "$id machine stability result: $(gate["status"])" stability=gate
        root=gate["most_positive_located_real_per_s"]
        tau=root<0 ? -1/root : 0.
        # Mechanical control transfers at 1 s. A decaying mode uses twelve decay
        # times for baseline settling and eight from tone onset. Other modes use
        # the existing minimum interval.
        start=ceil(max(8.,1+12tau,2+8tau))
        spec=merge(spec,(machine_stability=gate,window_starts=(start,start+2.),window_duration=2.,minimum_witness_window_s=2.,
            simulation_time=start+4.,estimated_station_seconds=5400))
    end
    reference=scan_reference(net,list,spec)
    return spec,reference
end

# Exact native nodal Schur reduction of the converter plus passive DC load.
# The zero-voltage remote reference is ground; the AC Thevenin is excluded
# because the meter measures DUT current alone (the load has no AC terminal).
function device_port_y(net, s)
    y = physical_y(net.elements[:DUT],s)
    indices=device_bases(net.elements[:DUT].element_model.elec).ac_indices
    haskey(net.elements,:DC_load) || return y[indices,indices]
    g = PowerImpedance.get_y(net.elements[:DC_load],s)[1,1]
    return y[2:3,2:3] - y[2:3,1:1]*((y[1,1]+g)\y[1:1,2:3])
end
