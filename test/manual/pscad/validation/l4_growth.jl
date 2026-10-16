const L4_GROWTH_WINDOW=(.0003,.0018)
const L4_GROWTH_LIMITS=(frequency=.02,growth=.10,growth_floor=.5)

function l4_space_vector(abc)
    size(abc,2)==3 || throw(ArgumentError("three physical phases are required"))
    return (2/3).*(abc[:,1]+cis(2π/3).*abc[:,2]+cis(-2π/3).*abc[:,3])
end

# Signed circular modes retain their opposite carrier companions. The fixed
# background spans a constant, a linear trend, and both nominal carriers.
function l4_growth_basis(t,p,signs)
    n=length(signs);alpha=exp.(p[1:n]);frequency=signs.*exp.(p[n+1:2n])
    waves=Vector{ComplexF64}[]
    for j in 1:n
        push!(waves,exp.((alpha[j]+2π*im*frequency[j]).*t))
        push!(waves,exp.((alpha[j]+2π*im*(100-frequency[j])).*t))
    end
    append!(waves,[ones(ComplexF64,length(t)),ComplexF64.(t./maximum(t)),cis.(2π*50 .*t),cis.(-2π*50 .*t)])
    x=reduce(hcat,waves)
    return x./sqrt.(sum(abs2,x;dims=1))
end

function l4_growth_fit(time,signals,seeds;window=L4_GROWTH_WINDOW)
    try
        tierb_grid(time,signals)
        n=length(seeds)
        n>0 && all(z->real(z)>0 && !iszero(imag(z)),seeds) || throw(ArgumentError("growing signed mode seeds required"))
        first(time)<=window[1] && last(time)>=window[2] || return Dict("status"=>"unextractable","reason"=>"incomplete fixed interval")
        ix=findall(t->window[1]<=t<window[2],time)
        length(ix)>4n+12 || return Dict("status"=>"unextractable","reason"=>"insufficient fixed-interval samples")
        t=time[ix].-window[1];y=ComplexF64.(signals[ix,:])
        background=hcat(ones(ComplexF64,length(t)),t./maximum(t),cis.(2π*50 .*t),cis.(-2π*50 .*t))
        nuisance=Matrix(qr(background).Q)[:,1:4]
        y-=nuisance*(nuisance'*y)
        scales=sqrt.(sum(abs2,y;dims=1))
        all(>(0),scales) || return Dict("status"=>"unextractable","reason"=>"zero fitted channel")
        y=y./scales
        signs=sign.(imag.(seeds));seed=log.([real.(seeds);abs.(imag.(seeds))./(2π)])
        lower=seed.+log.([fill(.05,n);fill(.5,n)])
        upper=seed.+log.([fill(20.,n);fill(1.5,n)])
        function projected_basis(p)
            x=l4_growth_basis(t,p,signs)[:,1:2n]
            return x-nuisance*(nuisance'*x)
        end
        function model(_,p)
            x=projected_basis(p);fitted=x*(x\y)
            return [real.(vec(fitted));imag.(vec(fitted))]
        end
        data=[real.(vec(y));imag.(vec(y))]
        fit=PowerImpedance.LsqFit.curve_fit(model,zeros(length(data)),data,seed;lower,upper)
        x=projected_basis(fit.param);amplitudes=x\y
        residual=y-x*amplitudes;relative=norm(residual)/norm(y)
        covariance=PowerImpedance.LsqFit.estimate_covar(fit)
        dof=max(length(data)-2(size(x,2)+4)*size(y,2)-2n,1)
        covariance .*= (length(data)-2n)/dof
        errors=sqrt.(max.(diag(covariance),0.))
        alpha=exp.(fit.param[1:n]);frequency=signs.*exp.(fit.param[n+1:2n])
        interior=all(lower.+1e-6 .< fit.param .< upper.-1e-6)
        valid=fit.converged && interior && relative<=.10 && all(isfinite,errors) &&
            all(errors[1:n].<=.10) && all(errors[n+1:2n].<=.02) && isfinite(cond(x)) && cond(x)<1e10
        modes=[Dict("growth_per_s"=>alpha[j],"signed_frequency_Hz"=>frequency[j],
            "growth_standard_error_per_s"=>alpha[j]*errors[j],
            "frequency_standard_error_Hz"=>abs(frequency[j])*errors[n+j],
            "growth_95_interval_per_s"=>alpha[j].*exp.([-1.96,1.96].*errors[j]),
            "frequency_magnitude_95_interval_Hz"=>abs(frequency[j]).*exp.([-1.96,1.96].*errors[n+j])) for j in 1:n]
        return Dict("status"=>valid ? "extracted" : "unextractable","modes"=>modes,
            "residual_relative"=>relative,"basis_condition"=>cond(x),"sample_count"=>length(ix),
            "window_s"=>collect(window),"per_channel_residual"=>[norm(residual[:,j])/norm(y[:,j]) for j in axes(y,2)],
            "reason"=>valid ? "" : "fit convergence, residual, search extent, or uncertainty")
    catch failure
        failure isa InterruptException && rethrow()
        return Dict("status"=>"unextractable","reason"=>sprint(showerror,failure))
    end
end

function l4_growth_comparison(fit,reference)
    get(fit,"status","")=="extracted" || return Dict("status"=>"unextractable")
    length(fit["modes"])==length(reference) || return Dict("status"=>"unextractable")
    rows=Dict{String,Any}[]
    for (mode,root) in zip(fit["modes"],reference)
        frequency=imag(root)/(2π);growth=real(root)
        df=abs(mode["signed_frequency_Hz"]-frequency)/abs(frequency)
        da=abs(mode["growth_per_s"]-growth)
        limit=max(L4_GROWTH_LIMITS.growth*abs(growth),L4_GROWTH_LIMITS.growth_floor)
        push!(rows,Dict("frequency_relative_error"=>df,"growth_error_per_s"=>da,
            "growth_limit_per_s"=>limit,"passed"=>df<=L4_GROWTH_LIMITS.frequency && da<=limit))
    end
    return Dict("status"=>all(r["passed"] for r in rows) ? "passed" : "failed","modes"=>rows)
end

function l4_growth_reference(c)
    functions=composed_device_functions(c)
    initial=filter(z->real(z)>-1500,l4_line_seeds(c))
    _,tracks,_=l4_root_search(c,functions,initial)
    located=Tuple{ComplexF64,Float64}[]
    for (root,residual) in tracks
        real(root)>0 && imag(root)>0 && residual<1e-6 || continue
        any(x->isapprox(x[1],root;rtol=1e-5),located) || push!(located,(root,residual))
    end
    sort!(located;by=x->real(x[1]),rev=true)
    modes=Dict{Int,NamedTuple}()
    for (root,residual) in located
        v=svd(composed_nodal(c,root,functions)).V[:,end]
        positive=abs(v[1]-im*v[2]);negative=abs(v[1]+im*v[2])
        direction=positive>negative ? 1 : -1
        haskey(modes,direction) && continue
        physical=direction*imag(root)/(2π)+50
        modes[direction]=(;root,signed_root=complex(real(root),2π*physical),residual,
            polarization=ComplexF64[v[1],v[2]]./(norm(v[1:2])*cis(angle(v[1]))),
            circular_ratio=max(positive,negative)/max(min(positive,negative),eps()))
    end
    isempty(modes) && error("no located growing circular mode")
    return [modes[direction] for direction in sort!(collect(keys(modes));rev=true)]
end

function l4_growth_spec(id,list,modes)
    base=l4_spec(id=="L4-00D" ? "L4-01" : "L4-04",list)
    dominant=modes[argmax(real(m.root) for m in modes)]
    carrier=id=="L4-04D" ? 3526.5564 : abs(imag(dominant.root))/(2π)
    return merge(base,(;id,stimulus="hann_burst",protocol="growth",frequencies=[carrier],
        phases=[0.],carrier_Hz=carrier,burst_cycles=1,
        burst_polarization=dominant.polarization,injection_time=0.,tone_peak_pu=1e-7,
        ringdown=L4_GROWTH_WINDOW,simulation_time=.002,time_step=.2e-6,sample_step=5e-6,
        window_starts=(.0003,.00105),window_duration=.00075,driven_axis="p1_d",recorder_scope="",
        estimated_station_seconds=1200))
end

function l4_growth_variants(spec)
    half=merge(spec,(;time_step=.1e-6,sample_step=2.5e-6))
    amplitude=merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2,baseline_template="g_baseline"))
    return [(key="g_baseline",spec=spec,axis="baseline",prefix="g_"),
        (key="g_"*spec.driven_axis,spec=spec,axis=spec.driven_axis,prefix="g_"),
        (key="g_half_amplitude_"*spec.driven_axis,spec=amplitude,axis=spec.driven_axis,prefix="g_half_amplitude_"),
        (key="gh_baseline",spec=half,axis="baseline",prefix="gh_"),
        (key="gh_"*spec.driven_axis,spec=half,axis=spec.driven_axis,prefix="gh_")]
end

function l4_polarized_burst_graph(spec)
    graph=P.BlockGraph()
    clock,t0,tau,arg,cosine,one,envelope0,envelope,on,off,enabled=P.Signal.([
        "growth_clock","growth_onset","growth_time","growth_envelope_arg","growth_envelope_cos",
        "growth_one","growth_envelope_raw","growth_envelope","growth_on","growth_off","growth_enabled"])
    duration=spec.burst_cycles/spec.carrier_Hz
    append!(graph.nodes,P.ControlBlock[P.TimeStep(clock),P.Const(t0,spec.injection_time),P.Sum([clock,t0],[1,-1],tau),
        P.Gain(tau,arg,2π/duration),P.Trig(arg,cosine,:cos),P.Const(one,1.),
        P.Sum([one,cosine],[1,-1],envelope0),P.Gain(envelope0,envelope,.5),
        P.Compare(clock,on,spec.injection_time),P.Compare(clock,off,spec.injection_time+duration),P.Sum([on,off],[1,-1],enabled)])
    outputs=P.Signal[]
    for (j,axis) in enumerate(("d","q"))
        omega,phase,shifted,carrier,windowed,limited,physical,output=P.Signal.([
            "growth_omega_$axis","growth_phase_$axis","growth_shifted_$axis","growth_carrier_$axis",
            "growth_windowed_$axis","growth_limited_$axis","growth_physical_$axis","growth_output_$axis"])
        polarization=spec.burst_polarization[j]
        append!(graph.nodes,P.ControlBlock[P.Gain(tau,omega,2π*spec.carrier_Hz),P.Const(phase,angle(polarization)),
            P.Sum([omega,phase],[1,1],shifted),P.Trig(shifted,carrier,:cos),P.Mult(carrier,envelope,windowed),
            P.Mult(windowed,enabled,limited),P.Gain(limited,physical,spec.current_base_kA*abs(polarization)),
            P.Gain(physical,output,"d_amplitude_pu")])
        push!(outputs,output)
    end
    return graph,outputs[1],outputs[2],clock
end

function l4_exact_modulation_y(e)
    m=e.element_model;names=PowerImpedance.statenames(m)
    delayed=Set(PowerImpedance.statenames(m.modulation))
    d=findall(in(delayed),collect(names));r=setdiff(1:length(names),d)
    tau=m.modulation.delay1.timeDelay
    scalar=PowerImpedance.PadeDelay(timeDelay=tau,padeOrderNum=5,padeOrderDen=5)
    b=device_bases(m.elec);n=length(r)
    function response(s)
        g=only(scalar.C*((s*I-scalar.A)\scalar.B)+scalar.D)
        feedback=vcat(e.A[r,d],e.C[:,d])*((s*I-e.A[d,d])\hcat(e.A[d,r],e.B[d,:]))
        z=[e.A[r,r] e.B[r,:];e.C[:,r] e.D]+feedback*((exp(-s*tau)+1)/(g+1))
        y=z[n+1:end,1:n]*((s*I-z[1:n,1:n])\z[1:n,n+1:end])+z[n+1:end,n+1:end]
        return y.*b.current_outputs./b.voltage_inputs'
    end
    return response
end

function l4_growth_sensitivity(c,modes)
    functions=composed_device_functions(c)
    list=fixture_netlist(c.net,nothing)
    dc=Set(node for bus in list.buses if bus.kind==:dc for node in bus.nets)
    early=L4System(c.net,c.devices,c.grids,filter(!in(dc),c.nodes),c.ports,Dict{Symbol,Float64}(),c.measurands)
    exact=Dict(n=>l4_exact_modulation_y(c.net.elements[n]) for n in c.devices)
    discrete=any(interface_step_eligible(c.net.elements[n].element_model) for n in c.devices)
    main_functions=discrete ? composed_device_functions(c;time_step=.2e-6) : functions
    half_functions=discrete ? composed_device_functions(c;time_step=.1e-6) : functions
    return [begin
        precharged,pr=composed_refine_root(early,functions,m.root)
        exact_root,er=composed_refine_root(c,exact,m.root)
        main_root,mr=composed_refine_root(c,main_functions,m.root)
        half_root,hr=composed_refine_root(c,half_functions,m.root)
        main_early,mer=composed_refine_root(early,main_functions,m.root)
        half_early,her=composed_refine_root(early,half_functions,m.root)
        growth_limit=max(L4_GROWTH_LIMITS.growth*real(m.root),L4_GROWTH_LIMITS.growth_floor)
        inside(z,r)=r<1e-6 && abs(real(z)-real(m.root))<=growth_limit &&
            abs(imag(z)-imag(m.root))/abs(imag(m.signed_root))<=L4_GROWTH_LIMITS.frequency
        Dict("native_real_per_s"=>real(m.root),"native_dq_Hz"=>imag(m.root)/(2π),
            "signed_abc_Hz"=>imag(m.signed_root)/(2π),"circular_amplitude_ratio"=>m.circular_ratio,
            "precharged_growth_per_s"=>real(precharged),"precharged_dq_Hz"=>imag(precharged)/(2π),
            "exact_delay_growth_per_s"=>real(exact_root),"exact_delay_dq_Hz"=>imag(exact_root)/(2π),
            "precharged_residual"=>pr,"exact_delay_residual"=>er,"one_step_applicable"=>discrete,
            "one_step_full_growth_per_s"=>real(main_root),"half_step_full_growth_per_s"=>real(half_root),
            "one_step_precharged_growth_per_s"=>real(main_early),"half_step_precharged_growth_per_s"=>real(half_early),
            "one_step_precharged_dq_Hz"=>imag(main_early)/(2π),"half_step_precharged_dq_Hz"=>imag(half_early)/(2π),
            "passed"=>inside(precharged,pr) && inside(exact_root,er) && inside(main_root,mr) && inside(half_root,hr) &&
                inside(main_early,mer) && inside(half_early,her))
    end for m in modes]
end

function l4_growth_setup(id)
    entry=fixture(id);net=entry.factory();point=power_flow(net);c=l4_system(id,net)
    modes=l4_growth_reference(c)
    id=="L4-00D" && length(modes)!=2 && error("both original P2P circular modes must be located")
    sensitivity=l4_growth_sensitivity(c,modes)
    all(r["passed"] for r in sensitivity) || error("early precharge or exact-delay sensitivity exceeds growth limits")
    list=fixture_netlist(net,point);spec=l4_growth_spec(id,list,modes)
    return (;entry,net,point,c,modes,sensitivity,list,spec)
end

function prepare_l4_growth(setup;directory,remote)
    (;entry,modes,sensitivity,list,spec)=setup
    id=entry.id
    ispath(directory) && error("fresh L4 growth directory already exists: $directory")
    paths=check_prepared_run_paths(id,[v.key for v in l4_growth_variants(spec)],remote)
    mkpath(directory)
    models=prepare_scan_projects(directory,list,spec,[spec.driven_axis];prefix="g_",remote)
    amp=merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2,baseline_template="g_baseline"))
    append!(models,filter(x->x.first!="g_half_amplitude_baseline",prepare_scan_projects(directory,list,amp,[spec.driven_axis];prefix="g_half_amplitude_",remote)))
    half=merge(spec,(;time_step=.1e-6,sample_step=2.5e-6))
    append!(models,prepare_scan_projects(directory,list,half,[spec.driven_axis];prefix="gh_",remote))
    roots=[m.signed_root for m in modes]
    record=preparation_record(entry,Dict("status"=>"deliberately_unstable"),models;directory)
    record["required_subsystems"]=1
    record["prepared_run_paths"]=paths;record["growth_reference_real_per_s"]=real.(roots)
    record["growth_reference_signed_Hz"]=imag.(roots)./(2π)
    record["growth_sensitivity"]=sensitivity;record["fixed_fit_interval_s"]=collect(L4_GROWTH_WINDOW)
    record["growth_protocol"]=Dict("time_step_s"=>.2e-6,"half_time_step_s"=>.1e-6,
        "sample_step_s"=>5e-6,"half_sample_step_s"=>2.5e-6,"amplitude_pu"=>spec.tone_peak_pu,
        "carrier_Hz"=>spec.carrier_Hz,"polarization_real"=>real.(spec.burst_polarization),
        "polarization_imag"=>imag.(spec.burst_polarization),"fit"=>"signed circular modes and their carrier companions; fixed nominal background",
        "execution"=>"five independent starts; no completed-run reuse")
    write_operating_point(joinpath(directory,"operating_point.tsv"),first(models).second)
    write_manifest(directory,record)
    return models
end

function execute_l4_growth!(record,key,model,directory,remote,deadline)
    remaining=deadline-time();remaining>0 || error("L4 growth runtime budget exhausted")
    parent=mkpath(joinpath(remote.local_root,"validation",record["fixture_id"]))
    work=mktempdir(parent;prefix=key*"-",cleanup=false)
    destination=joinpath(directory,"runs",basename(work));mkpath(dirname(destination))
    result=nothing
    try
        result=compute(model,PSCADRun();options=(remote=budget_remote(remote,remaining),work_root=work,verbosity=1))
    finally
        cp(work,destination)
    end
    messages=read(result.paths.build_messages,String)
    count=match(r"The total number of live nodes: (\d+)",messages)
    live=count===nothing ? 0 : parse(Int,count[1])
    0<live<native_node_limit(record["fixture_id"]) || error("missing or excessive live-node count: $live")
    push!(record["run_records"],Dict("axis"=>key,"path"=>relpath(destination,directory),
        "live_nodes"=>live,"project_sha256"=>digest(model.project_path),"fresh_start"=>true,
        "solver"=>result.diagnostics.solver_identity,"project_run_seconds"=>result.diagnostics.elapsed_seconds))
    write_manifest(directory,record)
    return result
end

function l4_growth_channels(result,model,c)
    columns=Vector{ComplexF64}[];labels=String[];bases=Float64[];reference=ComplexF64[]
    for name in c.devices
        b=device_bases(c.net.elements[name].element_model.elec)
        bus=port_probe(model.netlist,name,b.ac_side).name
        voltage=only(filter(p->p.kind==:voltage && p.bus==bus,model.probes.channels))
        current=only(filter(p->p.kind==:current && p.element==string(name) && p.side==string(b.ac_side),model.probes.channels))
        entry=only(filter(e->e.name==name,model.netlist.elements))
        equilibrium=P.converter_equilibrium(entry)
        output=zeros(3)
        PowerImpedance.outputequations!(output,equilibrium.states,nothing,equilibrium.inputs,entry.model)
        v0=complex(equilibrium.inputs.vG_d,-equilibrium.inputs.vG_q)*b.voltage_inputs[2]
        i0=complex(output[2],-output[3])*b.ac_current
        for (probe,kind,base,nominal) in ((voltage,"V",b.ac_voltage,v0),(current,"I",b.ac_current,i0))
            sign=kind=="I" && probe.orientation==:out ? -1 : 1
            push!(columns,sign.*l4_space_vector(probe_samples(result,probe)))
            push!(labels,"$kind:$name");push!(bases,base);push!(reference,nominal)
        end
    end
    return (;signals=reduce(hcat,columns),labels,bases,reference)
end

function l4_growth_quality(time,channels,spec)
    ix=findall(t->L4_GROWTH_WINDOW[1]<=t<L4_GROWTH_WINDOW[2],time)
    isempty(ix) && return Dict("passed"=>false,"reason"=>"missing fixed interval")
    carrier=cis.(2π*spec.frequency.*time)
    # Native solved terminal values fix the carrier independently of startup
    # readout zeros and independently of the fitted nuisance amplitudes.
    departure=maximum(abs.((channels.signals[ix,:]-carrier[ix]*transpose(channels.reference)))./channels.bases')
    return Dict("passed"=>isfinite(departure) && departure<=.01,"peak_departure_pu"=>departure,
        "limit_pu"=>.01,"scope"=>"all selected AC V/I space vectors; native solved carrier retained")
end

function run_l4_growth(id;directory,remote,deadline)
    record=manifest_lists!(TOML.parsefile(joinpath(directory,"manifest.toml")));verify_inputs(directory,record)
    record["fixture_id"]==id || error("L4 growth fixture differs")
    net=fixture(id).factory();point=power_flow(net);c=l4_system(id,net)
    modes=l4_growth_reference(c);list=fixture_netlist(net,point);spec=l4_growth_spec(id,list,modes)
    native_operating_point_check(list,joinpath(directory,"operating_point.tsv"))["passed"] || error("L4 growth operating point changed")
    reference=complex.(record["growth_reference_real_per_s"],2π.*record["growth_reference_signed_Hz"])
    length(modes)==length(reference) && all(isapprox(m.signed_root,z;rtol=1e-8) for (m,z) in zip(modes,reference)) || error("L4 growth reference changed")
    record["status"]="running";record["growth_analysis"]=Dict{String,Any}()
    # Every invocation executes all five variants from time zero. Old output
    # directories stay available, but they cannot supply a completed axis.
    results=Dict{String,Any}();channels=Dict{String,Any}()
    started=time()
    try
        for variant in l4_growth_variants(spec)
            time()<deadline || error("L4 growth runtime budget exhausted")
            model=existing_model(record,variant.key,list,variant.spec,directory;prefix=variant.prefix)
            result=execute_l4_growth!(record,variant.key,model,directory,remote,deadline)
            data=l4_growth_channels(result,model,c)
            results[variant.key]=result;channels[variant.key]=data
            fit=l4_growth_fit(result.time,data.signals,reference)
            quality=l4_growth_quality(result.time,data,variant.spec)
            quality["internal"]=l4_growth_internal_quality(result,model)
            quality["passed"] &= quality["internal"]["passed"]
            subwindows=[l4_growth_fit(result.time,data.signals,reference;window=w) for w in ((.0003,.0015),(.0006,.0018))]
            per_channel=[l4_growth_fit(result.time,data.signals[:,j:j],reference) for j in axes(data.signals,2)]
            record["growth_analysis"][variant.key]=Dict("fit"=>fit,"comparison"=>l4_growth_comparison(fit,reference),
                "quality"=>quality,"subwindows"=>subwindows,"per_channel_fit"=>per_channel,"channels"=>data.labels)
            write_manifest(directory,record)
        end
        main=channels["g_"*spec.driven_axis].signals-channels["g_baseline"].signals
        halfamp=channels["g_half_amplitude_"*spec.driven_axis].signals-channels["g_baseline"].signals
        half=channels["gh_"*spec.driven_axis].signals-channels["gh_baseline"].signals
        t=results["g_baseline"].time;th=results["gh_baseline"].time
        ix=findall(x->L4_GROWTH_WINDOW[1]<=x<L4_GROWTH_WINDOW[2],t)
        matching=[only(findall(x->isapprox(x,time;atol=1e-12,rtol=0),th)) for time in t[ix]]
        scaled=main[ix,:]./channels["g_baseline"].bases'
        amplitude=matrix_change(reshape(2halfamp[ix,:]./channels["g_baseline"].bases',length(ix),size(main,2),1),
            reshape(scaled,length(ix),size(main,2),1);epsilon=.02)
        step=matrix_change(reshape(half[matching,:]./channels["g_baseline"].bases',length(ix),size(main,2),1),
            reshape(scaled,length(ix),size(main,2),1);epsilon=.01)
        record["growth_amplitude_check"]=amplitude;record["growth_raw_step_change"]=step
        driven=["g_"*spec.driven_axis,"g_half_amplitude_"*spec.driven_axis,"gh_"*spec.driven_axis]
        analyses=record["growth_analysis"]
        invalid=any(analyses[key]["fit"]["status"]!="extracted" || !analyses[key]["quality"]["passed"] for key in driven)
        passed=all(analyses[key]["comparison"]["status"]=="passed" for key in driven)
        record["status"]=invalid ? "invalid_measurement" : passed && amplitude["passed"] ? "passed" : "failed"
    catch failure
        record["status"]="run_or_analysis_failed";record["failure"]=sprint(showerror,failure);rethrow()
    finally
        record["station_workflow_seconds"]=time()-started
        write_manifest(directory,record)
    end
    return record
end

function l4_growth_recorders!(plan,list)
    x=maximum(c.x for c in plan.main.components)+216
    commands=unique([Dict(c.params)["NAME"] for c in plan.main.components if
        c isa P.ComponentPlan && c.defn=="master:breaker1" && startswith(get(Dict(c.params),"NAME",""),"precharge_")])
    for (j,command) in enumerate(commands)
        P.output_probe!(plan.main,command,"precharge","pu",(x,72j))
        push!(plan.probes.channels,P.ProbeChannel(command,:precharge_command,nothing,nothing,nothing,1,"pu"))
    end
    device=only(filter(e->e.name==:c1,list.elements))
    name="MMC_"*device.pscad
    definition=only(filter(m->m.name==name,plan.modules))
    recorder_x=maximum(c.x for c in definition.canvas.components)+216
    row=0
    for half in ("u","l"),phase in ("a","b","c"),quantity in ("m","i")
        signal=quantity=="m" ? "m_$(half)_$phase" : "i_$(half)_solved_$phase"
        row+=1;unit=quantity=="m" ? "pu" : "kA"
        P.output_probe!(definition.canvas,signal,"growth_c1",unit,(recorder_x,72row))
        push!(plan.probes.channels,P.ProbeChannel(signal,:converter_diagnostic,nothing,"c1","2",1,unit))
    end
    return nothing
end

function l4_growth_internal_quality(result,model)
    ix=findall(t->L4_GROWTH_WINDOW[1]<=t<L4_GROWTH_WINDOW[2],result.time)
    isempty(ix) && return Dict("passed"=>false,"reason"=>"missing fixed interval")
    commands=filter(p->p.kind==:precharge_command,model.probes.channels)
    modulation=filter(p->p.element=="c1" && startswith(p.name,"m_") && p.unit=="pu",model.probes.channels)
    ranges=Dict{String,Any}()
    for probe in [commands;modulation]
        data=result.channels[probe.name][ix]
        ranges[probe.name]=Dict("minimum"=>minimum(data),"maximum"=>maximum(data))
    end
    held=!isempty(commands) && all(all(iszero,result.channels[p.name][ix]) for p in commands)
    linear=length(modulation)==6 && all(all(v->isfinite(v) && 0<=v<=1,result.channels[p.name][ix]) for p in modulation)
    return Dict("passed"=>held && linear,"precharge_closed"=>held,"arm_insertions_in_range"=>linear,"ranges"=>ranges)
end
