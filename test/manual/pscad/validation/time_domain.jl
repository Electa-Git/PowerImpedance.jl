# Time-domain comparisons use a separate frozen protocol. Frequency-response records
# remain supporting measurements and cannot replace time-domain baselines.

const TIME_DOMAIN_IDS = ["mmc_rc_shunt", "mmc_pi_line", "machine_mmc_shared_bus"]
const TIME_DOMAIN_LIMITS = (rms=.05, peak=.10, gain=.05, frequency=.02, zeta=.10)

function burst_wave(time, spec; amplitude=spec.tone_peak_pu)
    duration=spec.burst_cycles/spec.carrier_Hz
    return [begin
        tau=t-spec.injection_time
        0 <= tau <= duration ? amplitude*.5*(1-cos(2π*tau/duration))*cos(2π*spec.carrier_Hz*tau) : 0.
    end for t in time]
end

# Clock-based phase is multiplied by a Hann envelope that vanishes at both endpoints. Only
# BlockGraph primitives and current_port are used.
function burst_graph(spec)
    graph=P.BlockGraph()
    clock,on,off,gate,t0,tau,earg,ec,one,env0,env,carg,carrier,scaled,burst=P.Signal.([
        "burst_clock","burst_on","burst_off","burst_gate","burst_t0","burst_tau",
        "envelope_arg","envelope_cos","burst_one","envelope_raw","envelope",
        "carrier_arg","burst_carrier","burst_scaled","burst_output"])
    duration=spec.burst_cycles/spec.carrier_Hz
    append!(graph.nodes,P.ControlBlock[P.TimeStep(clock),P.Const(t0,spec.injection_time),
        P.Sum([clock,t0],[1,-1],tau),P.Compare(clock,on,spec.injection_time),
        P.Compare(clock,off,spec.injection_time+duration),P.Sum([on,off],[1,-1],gate),
        P.Gain(tau,earg,2π/duration),P.Trig(earg,ec,:cos),P.Const(one,1.),
        P.Sum([one,ec],[1,-1],env0),P.Gain(env0,env,.5),
        P.Gain(tau,carg,2π*spec.carrier_Hz),P.Trig(carg,carrier,:cos),
        P.Mult(env,carrier,scaled),P.Mult(scaled,gate,burst)])
    output=P.Signal("current_burst_physical")
    push!(graph.nodes,P.Gain(burst,output,spec.voltage_base_kV))
    return graph,output,clock
end

function time_domain_spec(id,list)
    id in TIME_DOMAIN_IDS || error("no time-domain response protocol for $id")
    base=coupled_spec(id,list)
    f=id=="mmc_pi_line" ? 367.22563 : id=="mmc_rc_shunt" ? 245.50509 : 1.4869167
    alpha=id=="mmc_pi_line" ? 15.091584 : id=="mmc_rc_shunt" ? 36.011188 : .55603728
    # Amplitudes and direction are frozen from Julia-only all-terminal sizing.
    amp=id=="mmc_pi_line" ? .00085 : id=="mmc_rc_shunt" ? .001 : .0035
    ring=id=="mmc_pi_line" ? (16.05,16.30) : id=="mmc_rc_shunt" ? (16.07,16.22) : (67.,76.)
    return merge(base,(;stimulus="hann_burst",protocol="time_domain",frequencies=[f],phases=[0.],
        carrier_Hz=f,burst_cycles=id=="machine_mmc_shared_bus" ? 4 : 8,injection_time=id=="machine_mmc_shared_bus" ? 64. : 16.,
        simulation_time=id=="machine_mmc_shared_bus" ? 80. : 20.,tone_peak_pu=amp,
        driven_axis="p1_d",ringdown=ring,mode_seed=complex(-alpha,2π*f),
        fit_channels=id=="mmc_pi_line" ? [1,2,5,6] : [1,2,3,4],
        fit_residual_limit=.10,fit_frequency_uncertainty=.02,fit_zeta_uncertainty=.10,
        recorder_scope="time_domain",estimated_station_seconds=id=="machine_mmc_shared_bus" ? 15600 : 2100))
end

function time_domain_protocol(spec)
    return Dict("version"=>1,"fixture"=>spec.id,"stimulus"=>spec.stimulus,
        "carrier_Hz"=>spec.carrier_Hz,"cycles"=>spec.burst_cycles,
        "onset_s"=>spec.injection_time,"end_s"=>spec.simulation_time,
        "ringdown_s"=>collect(spec.ringdown),"amplitude_pu"=>spec.tone_peak_pu,
        "axis"=>spec.driven_axis,"time_step_s"=>spec.time_step,"recorder_ratio"=>25,
        "mode_seed"=>[real(spec.mode_seed),imag(spec.mode_seed)],"mode_search_multipliers"=>[.05,.5,20.,1.5],
        "voltage_base_kV"=>spec.voltage_base_kV,"current_base_kA"=>spec.current_base_kA,
        "power_base_MVA"=>spec.power_base_MVA,
        "metric_interval_s"=>[spec.injection_time,spec.simulation_time],
        "fit_channels"=>spec.fit_channels,"fit_model"=>"common complex mode; independent channel amplitudes; constant + linear background",
        "fit_residual_limit"=>spec.fit_residual_limit,"fit_relative_standard_error_limits"=>[.02,.10],
        "alignment"=>"absolute recorded times; no fitted shift",
        "damping_metric"=>"zeta = alpha / hypot(alpha, omega); alpha retained",
        "prediction"=>"closed native nodal response; exact interface transport and readout; recorded drive",
        "limits"=>Dict(string(k)=>v for (k,v) in pairs(TIME_DOMAIN_LIMITS)))
end

function time_domain_grid(time,signals)
    length(time)>=8 && size(signals,1)==length(time) || throw(ArgumentError("time-domain sample dimensions"))
    dt=(last(time)-first(time))/(length(time)-1)
    dt>0 && all(isfinite,time) && all(isfinite,signals) &&
        all(x->isapprox(x,dt;rtol=1e-8,atol=1e-12),diff(time)) || throw(ArgumentError("time-domain response requires finite uniform samples"))
    return dt
end

function time_domain_metrics(measured,reference;limits=TIME_DOMAIN_LIMITS)
    size(measured)==size(reference) || throw(ArgumentError("time-domain response dimensions"))
    rows=Dict{String,Any}[]
    for j in axes(reference,2)
        r=reference[:,j];m=measured[:,j];e=m-r
        valid=all(isfinite,r)&&all(isfinite,m)&&norm(r)>0&&maximum(abs,r)>0
        rms=valid ? norm(e)/norm(r) : Inf
        peak=valid ? maximum(abs,e)/maximum(abs,r) : Inf
        gain=valid ? dot(r,m)/dot(r,r) : NaN
        push!(rows,Dict("channel"=>j,"rms_error"=>rms,"peak_error"=>peak,"gain"=>gain,
            "status"=>!valid ? "invalid_measurement" : rms<=limits.rms&&peak<=limits.peak&&abs(gain-1)<=limits.gain ? "passed" : "failed"))
    end
    return rows
end

# Variable projection: the same nuisance basis and independent amplitudes are
# used for every channel, in both the reference and the measurement.
function time_domain_mode(time,signals,spec)
    time_domain_grid(time,signals)
    ix=findall(t->spec.ringdown[1]<=t<spec.ringdown[2],time)
    length(ix)>12 || return Dict("status"=>"unextractable","reason"=>"incomplete ringdown")
    first(time)<=spec.ringdown[1] && last(time)>=spec.ringdown[2] ||
        return Dict("status"=>"unextractable","reason"=>"incomplete ringdown")
    t=time[ix].-spec.ringdown[1]; y=signals[ix,:]
    scales=[norm(y[:,j]) for j in axes(y,2)]
    all(>(0),scales) || return Dict("status"=>"unextractable","reason"=>"zero signal")
    y=y./scales'
    function basis(p)
        a,w=exp.(p)
        return hcat(exp.(-a.*t).*cos.(w.*t),exp.(-a.*t).*sin.(w.*t),ones(length(t)),t)
    end
    model=(_,p)->begin x=basis(p);vec(x*(x\y)) end
    seed=[log(-real(spec.mode_seed)),log(abs(imag(spec.mode_seed)))]
    try
        fit=PowerImpedance.LsqFit.curve_fit(model,zeros(length(y)),vec(y),seed;
            lower=seed.+log.([.05,.5]),upper=seed.+log.([20.,1.5]))
        a,w=exp.(fit.param);res=norm(fit.resid)/norm(y)
        covariance=PowerImpedance.LsqFit.estimate_covar(fit)
        dof=max(length(y)-4size(y,2)-2,1)
        covariance .*= (length(y)-2)/dof
        se=sqrt.(max.(diag(covariance),0.))
        zeta=a/hypot(a,w)
        # d log(zeta) = (1-zeta^2) * (d log(alpha)-d log(omega)).
        gz=(1-zeta^2).*[1.,-1.]
        zse=sqrt(max(dot(gz,covariance*gz),0.))
        interior=all(seed.+log.([.05,.5]).+1e-6 .< fit.param .< seed.+log.([20.,1.5]).-1e-6)
        valid=fit.converged&&interior&&isfinite(res)&&res<=spec.fit_residual_limit&&
            all(isfinite,se)&&se[2]<=spec.fit_frequency_uncertainty&&zse<=spec.fit_zeta_uncertainty
        return Dict("status"=>valid ? "extracted" : "unextractable","frequency_Hz"=>w/(2π),
            "alpha_per_s"=>a,"zeta"=>zeta,"residual_relative"=>res,
            "frequency_standard_error_Hz"=>w/(2π)*se[2],"alpha_standard_error_per_s"=>a*se[1],
            "zeta_standard_error"=>zeta*zse,"sample_count"=>length(ix),
            "reason"=>valid ? "" : "fit residual, convergence or uncertainty")
    catch failure
        failure isa InterruptException && rethrow()
        return Dict("status"=>"unextractable","reason"=>sprint(showerror,failure))
    end
end

function time_domain_mode_comparison(measured,reference)
    get(measured,"status","")=="extracted" && get(reference,"status","")=="extracted" ||
        return Dict("status"=>"unextractable")
    f=abs(measured["frequency_Hz"]/reference["frequency_Hz"]-1)
    z=abs(measured["zeta"]/reference["zeta"]-1)
    return Dict("status"=>f<=TIME_DOMAIN_LIMITS.frequency&&z<=TIME_DOMAIN_LIMITS.zeta ? "passed" : "failed",
        "frequency_relative_error"=>f,"zeta_relative_error"=>z)
end

# In-place radix-two evaluation of the DFT, using only Base arithmetic. Roots
# are computed directly, not recursively multiplied, to avoid accumulated phase
# error on the million-sample records. The same roots serve all channels.
function time_domain_dft!(values, roots; inverse=false)
    n=length(values)
    ispow2(n) && length(roots)==n÷2 || throw(ArgumentError("B DFT dimensions"))
    j=0
    @inbounds for i in 0:n-1
        i<j && ((values[i+1],values[j+1])=(values[j+1],values[i+1]))
        bit=n÷2
        while bit>0 && j&bit!=0
            j ⊻= bit
            bit >>= 1
        end
        j ⊻= bit
    end
    @inbounds for stage in 1:trailing_zeros(n)
        width=1<<stage
        half=width÷2;stride=n÷width
        for first in 1:width:n, k in 0:half-1
            root=roots[k*stride+1]
            odd=(inverse ? conj(root) : root)*values[first+k+half]
            even=values[first+k]
            values[first+k]=even+odd
            values[first+k+half]=even-odd
        end
    end
    inverse && (values ./= n)
    return values
end

# Uniform-grid frequency-response convolution. Exponential weighting suppresses
# periodic wraparound without filtering any recorded input bin. Double padding;
# exp(-sigma*Tperiod)=1e-12. A second padding length checks inversion numerics.
# The input is the recorded dq injection, never the ideal command. DFT evaluation
# is O(n log n); output channels are inverted individually to bound workspace.
function time_domain_convolve(time,drive,response; padding=2)
    dt=time_domain_grid(time,drive);n=nextpow(2,padding*length(time));sigma=-log(1e-12)/(n*dt)
    t=time.-first(time);weight=exp.(-sigma.*t)
    roots=[cispi(-2k/n) for k in 0:n÷2-1]
    spectrum=zeros(ComplexF64,n÷2+1,size(drive,2))
    work=zeros(ComplexF64,n)
    for j in axes(drive,2)
        fill!(work,0)
        work[1:length(time)]=drive[:,j].*weight
        time_domain_dft!(work,roots)
        spectrum[:,j]=work[1:n÷2+1]
    end
    first_response=response(complex(sigma,0.))
    output=zeros(ComplexF64,size(spectrum,1),size(first_response,1))
    for k in axes(spectrum,1)
        s=complex(sigma,2π*(k-1)/(n*dt))
        output[k,:]=response(s)*spectrum[k,:]
    end
    predicted=zeros(length(time),size(output,2))
    for j in axes(output,2)
        work[1]=real(output[1,j]);work[n÷2+1]=real(output[end,j])
        @inbounds for k in 2:n÷2
            work[k]=output[k,j]
            work[n-k+2]=conj(output[k,j])
        end
        time_domain_dft!(work,roots;inverse=true)
        @inbounds for k in eachindex(time)
            predicted[k,j]=real(work[k])/weight[k]
        end
    end
    return predicted
end

# Channels include all free-node voltages, every inward passive branch current,
# and every individual device AC current, in physical kV / kA.
function time_domain_channels(c,spec)
    labels=String[];bases=Float64[]
    vb=spec.voltage_base_kV
    for node in c.nodes;push!(labels,"V:"*string(node));push!(bases,vb);end
    for name in sort(c.devices)
        b=device_bases(c.net.elements[name].elec)
        for axis in ("d","q");push!(labels,"I:$name:$axis");push!(bases,b.ac_current);end
    end
    for (name,e) in sort!(collect(pairs(c.net.elements));by=first)
        e isa PowerImpedance.Impedance || continue
        for axis in ("d","q");push!(labels,"I:$name:$axis");push!(bases,2*1000/(3vb));end
    end
    return (;labels,bases)
end

function time_domain_response(c,spec; discrete=false,forms=nothing)
    functions=composed_device_functions(c;time_step=discrete ? spec.time_step : nothing)
    function response(s)
        full=composed_nodal(c,s,functions;forms)
        drive=zeros(ComplexF64,length(c.nodes),2);drive[1:2,:]=I(2)
        voltage=full\drive
        output=Matrix{ComplexF64}[voltage]
        for name in sort(c.devices)
            b=device_bases(c.net.elements[name].elec);h=component_incidence(c,name)
            push!(output,(functions[name](s)*h'*voltage)[b.ac_indices,:])
        end
        for (name,e) in sort!(collect(pairs(c.net.elements));by=first)
            e isa PowerImpedance.Impedance || continue
            h=component_incidence(c,name)
            y=forms===nothing ? physical_y(e,ComplexF64(s)) : composed_passive_y(e,
                forms[name],s)
            push!(output,(y*h'*voltage)[1:2,:])
        end
        # The frequency-response transport/readout convention applies: recorded injection
        # lags KCL.
        transfer=reduce(vcat,output)
        angle=2π*spec.frequency*spec.time_step
        rotation=[cos(angle) sin(angle);-sin(angle) cos(angle)]
        return discrete ? exp(s*spec.time_step).*(transfer*rotation) : transfer
    end
    return response
end

function time_domain_prediction(c,spec,time,drive;discrete=false,forms=nothing,padding=2)
    time[end]>=spec.simulation_time-spec.sample_step || error("incomplete time-domain record")
    time_domain_grid(time,drive)
    # Skip only identically zero prehistory, retaining two zero samples before
    # the first nonzero recorded drive. Even tiny pre-onset noise is retained.
    first_nonzero=findfirst(k->any(!iszero,view(drive,k,:)),axes(drive,1))
    first_nonzero===nothing && error("time-domain response has no recorded injection")
    start=max(1,first_nonzero-2)
    response=time_domain_response(c,spec;discrete,forms)
    predicted=time_domain_convolve(time[start:end],drive[start:end,:],response;padding)
    check=time_domain_convolve(time[start:end],drive[start:end,:],response;padding=2padding)
    norm(predicted-check)/norm(check)<=1e-4 || error("B Fourier inversion unresolved at frozen padding lengths")
    return vcat(zeros(start-1,size(predicted,2)),predicted)
end

function time_domain_samples(result,model,c)
    columns=Vector{Float64}[]
    for node in c.nodes
        found=false
        for row in c.net.topology.connections
            row.net == node || continue
            bus=port_probe(model.netlist,row.component,row.port).name
            probe=only(filter(p->p.kind==:voltage&&p.bus==bus,model.probes.channels))
            axis = row.terminal == :d ? 1 : 2
            push!(columns,fixed_dq(result.time,probe_samples(result,probe))[:,axis])
            found=true;break
        end
        found || error("missing time-domain nodal voltage $node")
    end
    for name in sort(c.devices)
        b=device_bases(c.net.elements[name].elec)
        p=only(filter(p->p.kind==:current&&p.element==string(name)&&p.port==:ac,
            model.probes.channels))
        data=composed_current(result, model, p)
        append!(columns, [data[:, 1], data[:, 2]])
    end
    for (name,e) in sort!(collect(pairs(c.net.elements));by=first)
        e isa PowerImpedance.Impedance || continue
        p=only(filter(p->p.kind==:current&&p.element==string(name)&&p.port==:side1,
            model.probes.channels))
        data=composed_current(result, model, p)
        append!(columns, [data[:, 1], data[:, 2]])
    end
    ip=only(filter(p->p.kind==:injection_current,model.probes.channels))
    return (;signals=reduce(hcat,columns),
        drive=fixed_dq(result.time,injection_samples(result,ip)))
end

# Only stimulus instance gains may differ from the zero-stimulus baseline.
function time_domain_baseline_hash(path)
    text=read(path,String)
    text=replace(text,r"<param name=\"([dq])_amplitude_pu\" value=\"[^\"]*\"/>"=>
        s->replace(s,r"value=\"[^\"]*\""=>"value=\"0.0\""))
    return bytes2hex(sha256(text))
end

function time_domain_subtract(result,baseline,model,basemodel,c)
    result.time==baseline.time || throw(ArgumentError("time-domain baseline sample times differ"))
    gains=[parse(Float64,m.captures[1]) for m in eachmatch(
        r"<param name=\"[dq]_amplitude_pu\" value=\"([^\"]*)\"/>",read(basemodel.project_path,String))]
    !isempty(gains)&&all(iszero,gains) || throw(ArgumentError("time-domain baseline is not zero stimulus"))
    time_domain_baseline_hash(model.project_path)==time_domain_baseline_hash(basemodel.project_path) ||
        throw(ArgumentError("time-domain zero-stimulus baseline project hash mismatch"))
    a=time_domain_samples(result,model,c);b=time_domain_samples(baseline,basemodel,c)
    return (;signals=a.signals-b.signals,drive=a.drive-b.drive,baseline=b.signals)
end

function time_domain_quality(time,data,c,spec)
    dt=time_domain_grid(time,data.signals)
    isapprox(dt,spec.sample_step;rtol=1e-8) || throw(ArgumentError("time-domain recorder sample step changed"))
    check_recorder_sampling(spec)==25 || error("time-domain recorder ratio must remain odd (25)")
    channels=time_domain_channels(c,spec);ix=findall(t->spec.injection_time<=t<=spec.simulation_time,time)
    isempty(ix) && error("time-domain metric interval is missing")
    normed=data.signals[ix,:]./channels.bases'
    nv=length(c.nodes)
    v=maximum(abs,normed[:,1:nv]);i=maximum(abs,normed[:,nv+1:end])
    base=data.baseline[ix,:]./channels.bases'
    middle=length(ix)÷2
    drift=maximum(abs,vec(mean(base[1:middle,:];dims=1)-mean(base[middle+1:end,:];dims=1)))
    # Recorded current uses the measured interface readout timing.
    wave=burst_wave(time.-spec.time_step,spec).*spec.current_base_kA
    angle=2π*spec.frequency*spec.time_step
    command=hcat(wave.*cos(angle),wave.*sin(angle))
    waveform_error=norm(data.drive[ix,:]-command[ix,:])/norm(command[ix,:])
    drive_error=maximum(abs(norm(data.drive[ix,j])-norm(command[ix,j])) for j in 1:2)/norm(command[ix,:])
    noise=sqrt.(vec(mean(abs2,base.-mean(base;dims=1);dims=1)))
    signal=sqrt.(vec(mean(abs2,normed;dims=1)))
    snr=[iszero(noise[j]) ? Inf : signal[j]/noise[j] for j in eachindex(noise)]
    valid=v<=.01&&i<=.01&&drift<=1e-3&&drive_error<=.01&&all(isfinite,normed)
    return Dict("status"=>valid ? "valid" : "invalid_measurement","voltage_peak_pu"=>v,
        "current_peak_pu"=>i,"baseline_drift_pu"=>drift,"drive_amplitude_error"=>drive_error,
        "command_waveform_error_diagnostic"=>waveform_error,
        "signal_to_baseline_rms"=>snr,"signal_rms_pu"=>signal,"baseline_noise_rms_pu"=>noise,"recorder_ratio"=>25)
end

function time_domain_compare(time,data,predicted,spec;valid=true)
    ix=findall(t->spec.injection_time<=t<=spec.simulation_time,time)
    metrics=time_domain_metrics(data[ix,:],predicted[ix,:])
    fitted=time_domain_mode(time,data[:,spec.fit_channels],spec)
    reference=time_domain_mode(time,predicted[:,spec.fit_channels],spec)
    mode=time_domain_mode_comparison(fitted,reference)
    invalid=!valid||any(x["status"]=="invalid_measurement" for x in metrics)
    status=invalid ? "invalid_measurement" : mode["status"]=="unextractable" ? "unextractable" :
        all(x["status"]=="passed" for x in metrics)&&mode["status"]=="passed" ? "passed" : "failed"
    return Dict("status"=>status,"metrics"=>metrics,"mode"=>fitted,"reference_mode"=>reference,"mode_comparison"=>mode)
end

function read_frequency_response_record(id;directory=joinpath(ROOT,"data",id))
    record=TOML.parsefile(joinpath(directory,"manifest.toml"))
    record["fixture_id"]==id || error("frequency-response fixture mismatch")
    expected=id in ("mmc_pi_line","mmc_rc_shunt") ? ["composed_coarse","composed_local"] : ["composed_coarse"]
    groups=get(record,"groups",Dict())
    outcomes=Dict(key=>get(get(groups,key,Dict()),"status","not_run") for key in expected)
    status=get(record,"status","not_run")
    comparison_status=get(record,"qualification_status","not_run")
    status=="passed" && comparison_status=="passed" && all(==("passed"),values(outcomes)) ||
        @warn "$id earlier frequency-response results: $status, $comparison_status, $outcomes"
    # Native model files and shared fixture factories require the recorded
    # frequency-response hashes, including fixtures `mmc_pi_line` and `mmc_rc_shunt`. Harness revisions
    # are compared numerically.
    for source in record["source_files"]
        path=source["path"]
        startswith(path,"test/manual/pscad/validation/") && continue
        digest(joinpath(REPOSITORY,path))==source["sha256"] || error("frequency-response producing source changed: $path")
    end
    for file in get(record,"files",Any[])
        path=file["path"]
        endswith(path,".pscx")||occursin("reference.tsv",path)||path=="operating_point.tsv" || continue
        digest(joinpath(directory,path))==file["sha256"] || error("retained frequency-response input changed: $path")
    end
    return record
end

function time_domain_frequency_reference_check(c,list,directory)
    record=TOML.parsefile(joinpath(directory,"manifest.toml"))
    id=record["fixture_id"]
    native_operating_point_check(list,joinpath(directory,"operating_point.tsv"))["passed"] || error("time-domain/frequency-response operating point differs")
    checks=Dict{String,Any}()
    for spec in coupled_specs(id,list)
        baseline=only(filter(p->p["axis"]==scan_prefix(spec)*"baseline",record["projects"]))
        project=joinpath(directory,baseline["path"])
        forms=exported_composed_passives(c,project,list)
        for (label,h) in (("plain",nothing),("discrete",spec.time_step))
            fresh=composed_reference(c,spec;time_step=h,forms=h===nothing ? nothing : forms)
            if h!==nothing
                for (k,f) in enumerate(spec.frequencies)
                    fresh["direct_Z"][:,:,k].*=injection_readout_factor(f,spec)
                end
            end
            frozen=composed_frozen_references(directory,spec,c,label)
            for target in keys(fresh)
                ts=composed_target_spec(spec,c,target)
                check=native_reference_check(ts,fresh[target],frozen[target])
                check["passed"] || error("time-domain/frequency-response reference differs: $id/$(spec.protocol)/$label/$target")
                checks[spec.protocol*"/"*label*"/"*target]=check
            end
        end
    end
    return checks
end

function require_committed_time_domain()
    # HEAD must contain all harness .jl files, protocol documentation, tests and both
    # project declarations; a missing file prevents preparation.
    paths=[relpath(joinpath(ROOT,f),REPOSITORY) for f in readdir(ROOT) if endswith(f,".jl")]
    append!(paths,["test/manual/pscad/validation/README.md","test/manual/pscad/validation/Project.toml",
        "test/pscad/validation_test.jl","test/pscad/time_domain_test.jl","Project.toml"])
    for path in paths
        committed=try read(pipeline(`git -C $REPOSITORY show $("HEAD:"*path)`;stderr=devnull)) catch; UInt8[] end
        committed==read(joinpath(REPOSITORY,path)) || error("time-domain response preparation requires HEAD to contain this change: $path differs; commit or merge it first")
    end
    return nothing
end

function time_domain_variants(spec)
    half=merge(spec,(;time_step=spec.time_step/2,sample_step=spec.sample_step/2))
    amp=merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2,baseline_template="time_domain_baseline"))
    return [(key="time_domain_baseline",spec=spec,axis="baseline",prefix="time_domain_"),
        (key="time_domain_"*spec.driven_axis,spec=spec,axis=spec.driven_axis,prefix="time_domain_"),
        (key="time_domain_half_amplitude_"*spec.driven_axis,spec=amp,axis=spec.driven_axis,prefix="time_domain_half_amplitude_"),
        (key="time_domain_half_step_baseline",spec=half,axis="baseline",prefix="time_domain_half_step_"),
        (key="time_domain_half_step_"*spec.driven_axis,spec=half,axis=spec.driven_axis,prefix="time_domain_half_step_")]
end

function prepare_time_domain(ids=TIME_DOMAIN_IDS;remote=nothing)
    require_committed_time_domain()
    length(ids)==length(unique(ids))&&all(in(TIME_DOMAIN_IDS),ids) || error("invalid time-domain response fixture selection")
    # Read the selected frequency-response records before writing projects.
    prior=Dict{String,Any}()
    for id in ids
        prior[id]=read_frequency_response_record(id)
        ispath(joinpath(ROOT,"data",id*"_time_domain")) && error("time-domain directory already exists: $id")
    end
    remote===nothing && (remote=RemoteConfig())
    for id in ids
        net=coupled_network(id);point=compute(PowerFlowProblem(net), ACDCPowerFlow());
            c=coupled_circuit(id,net);list=fixture_netlist(net,point)
        gate=composed_stability(c)
        gate["status"]=="passed" || @warn "$id time-domain stability result: $(gate["status"])" stability=gate
        cchecks=time_domain_frequency_reference_check(c,list,joinpath(ROOT,"data",id))
        spec=time_domain_spec(id,list);directory=joinpath(ROOT,"data",id*"_time_domain")
        check_prepared_run_paths(id,[v.key for v in time_domain_variants(spec)],remote)
        models=prepare_scan_projects(directory,list,spec,[spec.driven_axis];prefix="time_domain_",remote)
        amp=merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2,baseline_template="time_domain_baseline"))
        amplitude_models=prepare_scan_projects(directory,list,amp,[spec.driven_axis];prefix="time_domain_half_amplitude_",remote)
        append!(models,filter(p->p.first!="time_domain_half_amplitude_baseline",amplitude_models))
        half=merge(spec,(;time_step=spec.time_step/2,sample_step=spec.sample_step/2))
        append!(models,prepare_scan_projects(directory,list,half,[spec.driven_axis];prefix="time_domain_half_step_",remote))
        record=preparation_record(fixture(id),gate,models;directory)
        record["frequency_response_reference_checks"]=cchecks
        record["measurements"]=["time_domain"];record["time_domain_protocol"]=time_domain_protocol(spec)
        record["frequency_response_record"]=Dict("manifest"=>relpath(joinpath(ROOT,"data",id,"manifest.toml"),ROOT),
            "sha256"=>digest(joinpath(ROOT,"data",id,"manifest.toml")),"status"=>get(prior[id],"status","not_run"),
            "comparison_status"=>get(prior[id],"qualification_status","not_run"),
            "groups"=>Dict(name=>Dict("status"=>get(group,"status","not_run")) for (name,group) in get(prior[id],"groups",Dict())))
        record["channels"]=time_domain_channels(c,spec).labels;record["channel_bases"]=time_domain_channels(c,spec).bases
        record["fit_channels"]=spec.fit_channels
        record["qualification_reference"]="one_interface_step_with_readout"
        record["run_order"]=[v.key for v in time_domain_variants(spec)]
        record["status"]="prepared_station_pending"
        write_operating_point(joinpath(directory,"operating_point.tsv"),first(models).second)
        environment=mkpath(joinpath(directory,"environment"))
        for file in ("Project.toml","Manifest.toml")
            path=joinpath(dirname(Base.active_project()),file)
            isfile(path)&&cp(path,joinpath(environment,file))
        end
        write_manifest(directory,record)
    end
    return collect(ids)
end

# A diagnostic interpolation evaluates the coarse trace on the untouched fine
# grid. No native half-step sample is discarded or used to fit a time shift.
function time_domain_interpolate(time,signals,target)
    values=zeros(length(target),size(signals,2))
    for (k,t) in enumerate(target)
        first(time)<=t<=last(time) || error("time-domain interpolation outside record")
        j=min(searchsortedlast(time,t),length(time)-1)
        a=(t-time[j])/(time[j+1]-time[j]);values[k,:]=(1-a).*signals[j,:]+a.*signals[j+1,:]
    end
    return values
end

function write_time_domain_trace(path,timegrid,drive,labels,traces;start=first(timegrid))
    all(size(values)==(length(timegrid),length(labels)) for (_,values) in traces) || error("time-domain trace dimensions")
    open(path,"w") do io
        header=["time_s","drive_d_kA","drive_q_kA",[label*":"*name for (label,_) in traces for name in labels]...]
        println(io,join(header,'\t'))
        for k in searchsortedfirst(timegrid,start):length(timegrid)
            values=[timegrid[k],drive[k,1],drive[k,2],[value for (_,matrix) in traces for value in matrix[k,:]]...]
            println(io,join(values,'\t'))
        end
    end
    return path
end

function run_time_domain(id;remote,directory=joinpath(ROOT,"data",id*"_time_domain"),deadline)
    require_committed_time_domain();read_frequency_response_record(id)
    record=manifest_lists!(TOML.parsefile(joinpath(directory,"manifest.toml")));verify_inputs(directory,record)
    net=coupled_network(id);point=compute(PowerFlowProblem(net), ACDCPowerFlow());
        c=coupled_circuit(id,net);list=fixture_netlist(net,point);
        spec=time_domain_spec(id,list)
    time_domain_frequency_reference_check(c,list,joinpath(ROOT,"data",id))
    record["time_domain_protocol"]==time_domain_protocol(spec) || error("time-domain frozen protocol changed")
    record["channels"]==time_domain_channels(c,spec).labels&&record["channel_bases"]==time_domain_channels(c,spec).bases || error("time-domain signal inventory changed")
    digest(joinpath(ROOT,"data",id,"manifest.toml"))==record["frequency_response_record"]["sha256"] || error("time-domain/frequency-response record changed")
    native_operating_point_check(list,joinpath(directory,"operating_point.tsv"))["passed"] || error("time-domain operating point changed")
    variants=time_domain_variants(spec);models=Dict{String,P.PSCADModel}();results=Dict{String,Any}()
    grids=Dict{String,Vector{Float64}}()
    record["status"]="running";write_manifest(directory,record)
    try
        output=mkpath(joinpath(directory,"analysis"));comparisons=Dict{String,Any}();data=Dict{String,Any}()
        for v in variants
            model=existing_model(record,v.key,list,v.spec,directory;prefix=v.prefix)
            models[v.key]=model
            results[v.key]=execute_axis!(record,v.key,model,directory,remote,deadline)
            v.axis=="baseline" && continue
            base=startswith(v.key,"time_domain_half_step_") ? "time_domain_half_step_baseline" : "time_domain_baseline"
            sample=time_domain_subtract(results[v.key],results[base],models[v.key],models[base],c)
            data[v.key]=sample.signals;timegrid=results[v.key].time;grids[v.key]=timegrid
            # Native records are already retained on disk. Keep only the
            # baseline still needed by the amplitude pair, not five raw runs.
            delete!(results,v.key)
            (startswith(v.key,"time_domain_half_step_")||v.key=="time_domain_half_amplitude_"*spec.driven_axis) && delete!(results,base)
            quality=time_domain_quality(timegrid,sample,c,v.spec)
            if quality["status"]!="valid"
                comparisons[v.key]=Dict("quality"=>quality,"discrete"=>Dict("status"=>"invalid_measurement"),
                    "continuous"=>Dict("status"=>"invalid_measurement"))
                @warn "$id time-domain result for $(v.key): invalid_measurement" quality
                record["comparisons"]=comparisons;write_manifest(directory,record)
                continue
            end
            forms=exported_composed_passives(c,models[v.key].project_path,list)
            # Freeze/verify passive values separately for each actual export.
            continuous=time_domain_prediction(c,v.spec,timegrid,sample.drive)
            discrete=time_domain_prediction(c,v.spec,timegrid,sample.drive;discrete=true,forms)
            comparisons[v.key]=Dict("quality"=>quality,
                "continuous"=>time_domain_compare(timegrid,sample.signals,continuous,v.spec;valid=quality["status"]=="valid"),
                "discrete"=>time_domain_compare(timegrid,sample.signals,discrete,v.spec;valid=quality["status"]=="valid"))
            # Every native sample in the declared time-domain comparison interval is
            # retained.
            write_time_domain_trace(joinpath(output,v.key*"_time_domain.tsv"),timegrid,sample.drive,record["channels"],
                ["measured"=>sample.signals,"continuous"=>continuous,"discrete"=>discrete];start=spec.injection_time)
            record["comparisons"]=comparisons;write_manifest(directory,record)
            if comparisons[v.key]["discrete"]["status"]!="passed"
                @warn "$id time-domain result for $(v.key): $(comparisons[v.key]["discrete"]["status"])"
            end
            if v.key=="time_domain_half_amplitude_"*spec.driven_axis
                ix=findall(t->spec.injection_time<=t<=spec.simulation_time,timegrid)
                amplitude=time_domain_metrics(2sample.signals[ix,:],data["time_domain_"*spec.driven_axis][ix,:];
                    limits=(rms=.02,peak=.02,gain=.02))
                amp_pass=all(m["status"]=="passed" for m in amplitude)
                record["amplitude_witness"]=Dict("status"=>amp_pass ? "passed" : "failed","limit"=>.02,"metrics"=>amplitude)
                delete!(data,v.key)
                amp_pass || @warn "$id time-domain half-amplitude result: failed" amplitude
            end
        end
        main="time_domain_"*spec.driven_axis;fine="time_domain_half_step_"*spec.driven_axis
        tmain=grids[main];tfine=grids[fine]
        amp_pass=get(get(record,"amplitude_witness",Dict()),"status","")=="passed"
        fi=findall(t->spec.injection_time<=t<=spec.simulation_time,tfine)
        raw=time_domain_metrics(data[fine][fi,:],time_domain_interpolate(tmain,data[main],tfine[fi]))
        record["raw_step_diagnostic"]=raw
        record["frequency_response_step_policy"]="frequency-response step results recorded separately; time-domain results score both native grids independently"
        statuses=[x["discrete"]["status"] for x in values(comparisons)]
        record["status"]="invalid_measurement" in statuses ? "invalid_measurement" : "unextractable" in statuses ? "unextractable" :
            all(==("passed"),statuses)&&amp_pass ? "passed" : "failed"
    catch failure
        failure isa InterruptException && rethrow()
        record["status"]=failure isa ArgumentError ? "invalid_measurement" : "run_or_analysis_failed"
        record["failure"]=sprint(showerror,failure)
        failure isa ArgumentError && return record
        rethrow()
    finally
        write_manifest(directory,record)
    end
    return record
end

function run_time_domain_queue(;timeout=19800.,remote=nothing)
    require_committed_time_domain()
    isfinite(timeout)&&timeout>0 || error("timeout must be finite and positive")
    remote===nothing && (remote=RemoteConfig())
    deadline=time()+timeout;directory=mkpath(joinpath(ROOT,"data","time_domain_checks"));path=joinpath(directory,"queue.toml")
    record=isfile(path) ? TOML.parsefile(path) : Dict{String,Any}("order"=>TIME_DOMAIN_IDS,"outcomes"=>Dict{String,Any}())
    record["order"]==TIME_DOMAIN_IDS || error("time-domain response queue order changed")
    for id in TIME_DOMAIN_IDS
        try
            result=run_time_domain(id;remote,deadline)
            record["outcomes"][id]=Dict("status"=>result["status"])
        catch failure
            failure isa InterruptException && rethrow()
            record["outcomes"][id]=Dict("status"=>"run_or_analysis_failed","failure"=>sprint(showerror,failure))
            @warn "time-domain response fixture failed; continuing queue" fixture=id reason=sprint(showerror,failure)
        end
        open(io->TOML.print(io,record;sorted=true),path,"w")
    end
    return record
end
