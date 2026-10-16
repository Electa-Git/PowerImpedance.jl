# Measurement channels are selected from the exact project's probe manifest. All current
# sums are inward at the specified bus, including passive shunts.
function composed_current(result, model, probe)
    probe.orientation in (:into,:out) || error("missing composed current orientation")
    sign=probe.orientation==:into ? 1 : -1
    return sign .* fixed_dq(result.time,probe_samples(result,probe))
end

function composed_samples(result, model, spec, c)
    voltages=Matrix{Float64}[];aggregates=Matrix{Float64}[];drives=Matrix{Float64}[]
    branches=Dict{String,Matrix{Float64}}();individual=Dict{String,Matrix{Float64}}()
    for (port,bus) in enumerate(spec.buses)
        vp=only(filter(p->p.kind==:voltage && p.bus==bus.name,model.probes.channels))
        push!(voltages,fixed_dq(result.time,probe_samples(result,vp)))
        ips=filter(p->p.kind==:current && p.bus==bus.name,model.probes.channels)
        isempty(ips) && error("no KCL branches at $(bus.name)")
        agg=zeros(length(result.time),2)
        for p in ips
            cur=composed_current(result,model,p)
            key="$(port):$(p.element):$(p.side)";branches[key]=cur
            if !(Symbol(p.element) in c.grids)
                agg+=cur
            end
            if Symbol(p.element) in c.devices
                data=get!(individual,p.element,zeros(length(result.time),2length(spec.buses)))
                data[:,(2port-1):2port]=cur
            end
        end
        push!(aggregates,agg)
        ip=only(filter(p->p.kind==:injection_current && p.bus==bus.name,model.probes.channels))
        ip.orientation==:out || error("injection must point into composed bus")
        push!(drives,fixed_dq(result.time,probe_samples(result,ip)))
    end
    voltage=reduce(hcat,voltages);current=reduce(hcat,aggregates);drive=reduce(hcat,drives)
    outputs=Dict("aggregate_Y"=>current,"direct_Z"=>voltage)
    for (name,data) in individual;outputs[name*"_Y"]=data;end
    clamps=Dict{String,Vector{Float64}}()
    device_voltages=Dict{String,Matrix{Float64}}()
    for name in c.devices
        b=device_bases(c.net.elements[name].element_model.elec)
        bus=port_probe(model.netlist,name,b.ac_side).name
        vp=only(filter(p->p.kind==:voltage && p.bus==bus,model.probes.channels))
        device_voltages[string(name)*"_Y"]=fixed_dq(result.time,probe_samples(result,vp))
        if length(spec.axes)==2
            ip=only(filter(p->p.kind==:current && p.element==string(name) && p.side==string(b.ac_side),model.probes.channels))
            outputs[string(name)*"_Y"]=composed_current(result,model,ip)
        end
        b.dc_voltage===nothing && continue
        bus=port_probe(model.netlist,name,1).name
        poles=[only(filter(p->p.kind==:voltage && p.bus==bus && p.side==pole,model.probes.channels)) for pole in ("P","N")]
        clamps[string(name)]=result.channels[poles[1].name]-result.channels[poles[2].name]
    end
    if haskey(c.net.elements,:CableDC)
        outputs["DC_voltage_Z"]=hcat([clamps[string(n)] for n in c.devices]...)
        currents=Matrix{Float64}[]
        for side in ("1","2")
            p=only(filter(p->p.kind==:current && p.element=="CableDC" && p.side==side,model.probes.channels))
            p.orientation in (:into,:out) || error("missing DC cable current orientation")
            push!(currents,reshape((p.orientation==:into ? 1 : -1).*result.channels[p.name],:,1))
        end
        outputs["DC_current_T"]=reduce(hcat,currents)
    end
    return (;voltage,current,drive,drive_base=spec.current_bases,outputs,branches,clamps,device_voltages)
end

function composed_target_spec(spec,c,target)
    target=="DC_voltage_Z" && return merge(spec,(;quantity="Z",voltage_bases=fill(800.,2),dc_clamped=false))
    target=="DC_current_T" && return merge(spec,(;quantity="T",response_output_bases=fill(1.25,2),dc_clamped=false))
    target=="direct_Z" && return merge(spec,(;quantity="Z",dc_clamped=false))
    target=="aggregate_Y" && return merge(spec,(;dc_clamped=false))
    name=Symbol(chop(target;tail=2));b=device_bases(c.net.elements[name].element_model.elec)
    return merge(spec,(;quantity="Y",voltage_bases=fill(b.ac_voltage,length(spec.axes)),
        current_bases=fill(b.ac_current,length(spec.axes)),dc_clamped=false))
end

function composed_target_samples(samples,spec,target)
    voltage=haskey(samples.device_voltages,target) && length(spec.axes)==2 ? samples.device_voltages[target] : samples.voltage
    input=spec.quantity!="Y" ? samples.drive : voltage
    output=samples.outputs[target]
    input_base=spec.quantity!="Y" ? spec.current_bases : spec.voltage_bases
    output_base=get(spec,:response_output_bases,spec.quantity!="Y" ? spec.voltage_bases : spec.current_bases)
    return (;input,output,input_base,output_base,drive=samples.drive,drive_base=samples.drive_base)
end

function composed_quality(time, baseline, runs, spec, c, target; columns=eachindex(spec.axes))
    ts=composed_target_spec(spec,c,target)
    bs=composed_target_samples(baseline,ts,target)
    rs=[composed_target_samples(run,ts,target) for run in runs]
    quality=scan_quality(time,bs,rs,ts;columns)
    clamp=0.
    for (name,held) in baseline.clamps
        b=device_bases(c.net.elements[Symbol(name)].element_model.elec)
        # Only source-clamped DC terminals have this clamp limit. Internal DC nodes in a
        # coupled circuit are measured responses, rather than ideal voltage clamps.
        node=c.net.elements[Symbol(name)].pins[Symbol("1.1")]
        node in c.nodes && continue
        clamp=max(clamp,maximum(maximum(abs,run.clamps[name]-held)/b.dc_voltage for run in runs))
    end
    for (name,held) in get(baseline,:source_clamps,Dict())
        clamp=max(clamp,maximum(maximum(abs,run.source_clamps[name]-held) for run in runs))
    end
    quality["clamped_voltage_departure_pu"]=clamp
    quality["valid"] &= clamp<=1e-6
    quality["invalid_reasons"] = [name for (name,limit) in
        (("baseline_drift",1e-3),("input_departure_pu",.01),("output_departure_pu",.01),
         ("drive_amplitude_error",.01),("clamped_voltage_departure_pu",1e-6))
        if !(isfinite(quality[name]) && quality[name]<=limit)]
    return quality
end

# Generic n-coordinate identification also retains full 4x4 cross blocks when
# two AC ports/four independent drives are supplied. No Y inversion is measured.
function composed_extract(time, baseline, runs, spec, c)
    extracted=Dict{String,Any}()
    for target in keys(baseline.outputs)
        ts=composed_target_spec(spec,c,target)
        base=composed_target_samples(baseline,ts,target)
        rs=[composed_target_samples(run,ts,target) for run in runs]
        extracted[target]=try
            merge(extract_response(time,[x.input for x in rs],[x.output for x in rs],base.input,base.output,
                spec.frequencies;starts=spec.window_starts,duration=spec.window_duration,input_bases=base.input_base),
                (;valid=true,reason=""))
        catch failure
            failure isa ArgumentError || rethrow()
            (;valid=false,reason=sprint(showerror,failure))
        end
    end
    return extracted
end

function composed_readout_evidence(result,baseline,model,spec,c,column;axis=spec.axes[column])
    result.time==baseline.time || error("composed KCL sample times differ")
    a=composed_samples(result,model,spec,c);b=composed_samples(baseline,model,spec,c)
    rows=Dict{String,Any}[]
    for (port,bus) in enumerate(spec.buses)
        keys_at_bus=filter(k->startswith(k,"$port:"),collect(keys(a.branches)))
        kcl=sum(a.branches[k]-b.branches[k] for k in keys_at_bus)
        drive=(a.drive-b.drive)[:,(2port-1):2port]
        for start in spec.window_starts
            kp=dft_phasors(result.time,kcl,spec.frequencies;start,duration=spec.window_duration)
            ip=dft_phasors(result.time,drive,spec.frequencies;start,duration=spec.window_duration)
            for (k,f) in enumerate(spec.frequencies)
                # The driven coordinate supplies the ratio check. Every other
                # coordinate is checked as a KCL residual on the same drive scale.
                driven_port=cld(column,2);driven_axis=mod1(column,2)
                scale=spec.tone_peak_pu*spec.current_bases[column]
                gamma=injection_readout_factor(f,spec)
                # Recorded abc injection lags the branch meters by one electrical step. In
                # the fixed dq frame, advancing it rotates both coordinates. The driven
                # projection gamma is unchanged; its scalar extension to a null coordinate
                # incorrectly leaves an O(omega0*h) residual.
                expected=injection_readout_transport(f,spec)*ip[:,k]
                for coord in 1:2
                    if port==driven_port && coord==driven_axis
                        check=kcl_readout_check(kp[coord,k],ip[coord,k],gamma)
                    else
                        err=abs(kp[coord,k]-expected[coord])/scale
                        check=Dict{String,Any}("passed"=>isfinite(err)&&err<=1e-6,"relative_error"=>err,"limit"=>1e-6)
                    end
                    push!(rows,merge(check,Dict("axis"=>axis,"port"=>port,"coordinate"=>coord,
                        "frequency_Hz"=>f,"window_start_s"=>start,"branches"=>sort(keys_at_bus),
                        "kcl_real"=>real(kp[coord,k]),"kcl_imag"=>imag(kp[coord,k]),
                        "recorded_real"=>real(ip[coord,k]),"recorded_imag"=>imag(ip[coord,k]),
                        "timed_expected_real"=>real(expected[coord]),"timed_expected_imag"=>imag(expected[coord]),
                        "check"=>port==driven_port && coord==driven_axis ? "L2 driven timing ratio" : "transported dq KCL residual",
                        "normalization_kA"=>port==driven_port && coord==driven_axis ? abs(gamma*ip[coord,k]) : scale)))
                end
            end
        end
    end
    summary=[Dict("axis"=>axis,"port"=>port,"coordinate"=>coord,
        "max_relative_error"=>maximum(r["relative_error"] for r in rows if r["port"]==port && r["coordinate"]==coord),
        "failed_rows"=>findall(r->r["port"]==port && r["coordinate"]==coord && !r["passed"],rows))
        for port in eachindex(spec.buses) for coord in 1:2]
    return Dict("passed"=>all(r["passed"] for r in rows),"rows"=>rows,"summary"=>summary,"limit"=>1e-6,
        "max_relative_error"=>maximum(r["relative_error"] for r in rows),
        "measurement"=>"all inward device, grid and shunt branches; each port and coordinate; recorded injection timing")
end

function composed_column(result,baseline,model,spec,c,column)
    a=composed_samples(result,model,spec,c);b=composed_samples(baseline,model,spec,c)
    responses=Dict{String,Any}()
    for target in keys(b.outputs)
        ts=composed_target_spec(spec,c,target);base=composed_target_samples(b,ts,target)
        run=composed_target_samples(a,ts,target);matrices=Array{ComplexF64,3}[]
        for start in spec.window_starts
            drive=dft_phasors(result.time,a.drive-b.drive,spec.frequencies;start,duration=spec.window_duration)
            voltage=run.input-base.input
            transfer=ts.quantity!="Y"
            signal=transfer ? run.output-base.output : hcat(voltage,run.output-base.output)
            output=dft_phasors(result.time,signal,spec.frequencies;start,duration=spec.window_duration)
            bases=ts.quantity!="Y" ? get(ts,:response_output_bases,ts.voltage_bases) : [ts.voltage_bases;ts.current_bases]
            response=output./drive[column:column,:] .* (spec.current_bases[column]./bases)
            push!(matrices,reshape(response,size(response,1),1,:))
        end
        quality=composed_quality(result.time,b,[a],spec,c,target;columns=[column])
        change=matrix_change(matrices[2],matrices[1];epsilon=.01)
        quality["valid"] &= change["passed"]
        change["passed"] || push!(quality["invalid_reasons"],"window_change")
        quality["window_change"]=change
        responses[target]=(matrix=sum(matrices)/length(matrices),quality=quality)
    end
    return responses
end

function composed_predicted_columns(c,spec,column,forms)
    functions=composed_device_functions(c;time_step=spec.time_step)
    refs=composed_reference(c,spec;time_step=spec.time_step,forms)
    predicted=Dict{String,Array{ComplexF64,3}}()
    np=length(spec.axes)
    for target in keys(refs)
        ts=composed_target_spec(spec,c,target)
        cols=Matrix{ComplexF64}[]
        for (k,f) in enumerate(spec.frequencies)
            s=im*2π*f;nodal=composed_nodal(c,s,functions;forms)
            drive=zeros(ComplexF64,length(c.nodes));drive[column]=1
            all_voltage=nodal\drive;voltage=all_voltage[1:np]
            if startswith(target,"DC_")
                physical=refs[target][:,:,k]*drive[1:np]
            elseif target=="direct_Z"
                physical=voltage
            elseif target=="aggregate_Y"
                physical=[voltage;refs[target][:,:,k]*voltage]
            else
                name=Symbol(chop(target;tail=2));h=device_incidence(c,name)
                b=device_bases(c.net.elements[name].element_model.elec)
                local_current=(functions[name](s)*h'*all_voltage)[b.ac_indices]
                if np==2
                    local_voltage=(h'*all_voltage)[b.ac_indices]
                    physical=[local_voltage;local_current]
                else
                    ac=h[1:np,b.ac_indices]
                    physical=[voltage;ac*local_current]
                end
            end
            bases=ts.quantity!="Y" ? get(ts,:response_output_bases,ts.voltage_bases) : [ts.voltage_bases;ts.current_bases]
            push!(cols,reshape(injection_readout_factor(f,spec).*physical.*(spec.current_bases[column]./bases),:,1))
        end
        predicted[target]=cat(cols...;dims=3)
    end
    return predicted
end

function composed_score_indices(c,target)
    target in ("aggregate_Y","direct_Z") && return collect(1:2length(c.ports))
    name=Symbol(chop(target;tail=2));h=device_incidence(c,name)
    b=device_bases(c.net.elements[name].element_model.elec)
    rows=findall(x->!iszero(x),vec(sum(abs.(h[1:2length(c.ports),b.ac_indices]);dims=2)))
    # A sole device behind a passive line is scored at its local terminal.
    return isempty(rows) ? [1,2] : rows
end

composed_score_indices(c,target,spec)=startswith(target,"DC_") ? [1,2] : composed_score_indices(c,target)
composed_score_columns(c,target,spec)=startswith(target,"DC_") ? collect(eachindex(spec.axes)) : composed_score_indices(c,target)

function composed_comparison(results,models,reference,directory,spec,c;resonance_groups=Vector{Int}[])
    base=composed_samples(results["baseline"],models["baseline"],spec,c)
    all(results[axis].time==results["baseline"].time for axis in spec.axes) || error("composed scan sample times differ")
    runs=[composed_samples(results[axis],models[axis],spec,c) for axis in spec.axes]
    extracted=composed_extract(results["baseline"].time,base,runs,spec,c)
    comparisons=Dict{String,Any}();worst=-Inf;selection=(column=1,frequency=first(spec.frequencies))
    kcl=[composed_readout_evidence(results[axis],results["baseline"],models[axis],spec,c,j) for (j,axis) in enumerate(spec.axes)]
    for target in sort!(collect(keys(reference)))
        ts=composed_target_spec(spec,c,target);x=extracted[target]
        if !x.valid
            comparisons[target]=Dict("valid"=>false,"status"=>"invalid_measurement","reason"=>x.reason,
                "invalid_reasons"=>["response_extraction: "*x.reason])
            continue
        end
        indices=composed_score_indices(c,target,spec)
        columns=composed_score_columns(c,target,spec)
        normed=[scale_response(m,ts) for m in x.matrices]
        measured=sum(x.matrices)/length(x.matrices)
        scored=[m[indices,columns,:] for m in normed]
        windows=matrix_change(scored[2],scored[1];epsilon=.01)
        quality=composed_quality(results["baseline"].time,base,runs,spec,c,target)
        quality["valid"] &= windows["passed"] && all(r["passed"] for r in kcl)
        windows["passed"] || push!(quality["invalid_reasons"],"window_change")
        all(r["passed"] for r in kcl) || push!(quality["invalid_reasons"],"kcl_readout")
        quality["max_input_condition"]=maximum(x.conditions);quality["window_change"]=windows
        bs=composed_target_samples(base,ts,target)
        rs=[composed_target_samples(run,ts,target) for run in runs]
        coupling=sideband_coupling(results["baseline"].time,bs,rs,ts)
        mismatch=coupling>C_PASSIVE.epsilon ? "phase-domain frequency coupling absent from native fixed-dq LTI reference" : ""
        quality["omitted_sideband_ratio"]=coupling;quality["model_mismatch"]=mismatch
        measured_pu=scale_response(measured,ts)[indices,columns,:]
        reference_pu=scale_response(reference[target],ts)[indices,columns,:]
        rows=response_rows(ts,measured_pu,reference_pu;active=true,valid=quality["valid"],model_mismatch=mismatch)
        resonances=Dict{String,Any}[]
        if target=="direct_Z"
            for group in resonance_groups
                band=resonance_qualification(spec.frequencies[group],measured[:,:,group],reference[target][:,:,group];quantity="Z")
                push!(resonances,band)
                bandrows=findall(r->r.frequency_Hz in spec.frequencies[group],rows)
                rows[bandrows]=resonance_judged_rows(rows[bandrows],band;valid=quality["valid"])
            end
        end
        quality["resonances"]=resonances
        quality["status"]=!isempty(mismatch) ? "model_mismatch" : !quality["valid"] ? "invalid_measurement" :
            all(r.within_tolerance for r in rows) && all(r["passed"] for r in resonances) ? "passed" : "failed"
        quality["max_frobenius_error"]=maximum(r.frobenius_error for r in rows)
        for r in rows
            err=r.complex_error_pu/max(abs(complex(r.reference_real_pu,r.reference_imag_pu)),.02)
            if err>worst;worst=err;selection=(column=columns[r.column],frequency=r.frequency_Hz);end
        end
        write_table(joinpath(directory,target*"_C.tsv"),rows)
        write_table(joinpath(directory,target*"_windows.tsv"),refinement_rows(spec.frequencies,scored[2],scored[1];limit=.01,valid=true))
        write_response(joinpath(directory,target*"_measured.tsv"),measured,spec.frequencies;quantity=ts.quantity)
        comparisons[target]=quality
    end
    return (;comparisons,selection,kcl)
end
