const SYSTEM_FREQUENCY_RESPONSE_IDS=[entry.id for entry in REGISTRY if entry.category == :system && "frequency_response" in entry.measurements]
const SYSTEM_GROWTH_IDS=[entry.id for entry in REGISTRY if entry.category == :system && "growth" in entry.measurements]

function system_spec(id,list)
    id in SYSTEM_FREQUENCY_RESPONSE_IDS || error("no settled system measurement for $id")
    ports=system_ports(id)
    fs=filter(!=(50.),passive_settings().frequencies)
    vll=380.;power=1000.
    vb=vll*sqrt(2/3);ib=2power/(3vb);h=1.25e-6
    converter=first(e for e in list.elements if e.model isa Union{PowerImpedance.MMC,PowerImpedance.TLC})
    dcbase=device_bases(converter.model.elec, converter.model.bases).dc_voltage
    # Native peak bounds are evaluated for the preselected amplitudes; the measured limit
    # is .01 pu.
    amplitude=id=="p2p_redesigned" ? .0002916349 : .0001
    return (id=id,quantity="Z",dimension=2,buses=[port_probe(list,p...) for p in ports],
        currents=[("injection_$j","1") for j in eachindex(ports)],axes=["p$(j)_$axis" for j in 1:2 for axis in ("d","q")],
        frequencies=fs,phases=[-π*k*(k-1)/length(fs) for k in eachindex(fs)],tone_peak_pu=amplitude,
        injection_time=2.,frequency=50.,voltage_base_kV=vb,current_base_kA=ib,power_base_MVA=power,
        voltage_bases=fill(vb,4),current_bases=fill(ib,4),time_step=h,sample_step=25h,
        window_starts=(16.,24.),window_duration=8.,simulation_time=32.,minimum_witness_window_s=8.,
        drive="current",dc_clamped=false,dc_reference=:midpoint_resistors,dc_voltage_base_kV=dcbase,
        active=true,protocol="composed_coarse",travel_lower_bound_s=0.,resonance_groups=Vector{Int}[],
        settling=Dict("scope"=>"fixed coherent windows; measured drift and window changes remain required"),
        recorded_voltage_buses=[b.name for b in list.buses if b.kind==:dc ||
            any(e.model isa PowerImpedance.Source && any(t->t.bus==b.key,e.terminals) for e in list.elements)],
        recorded_terminal_currents=[(string(name),string(side)) for (name,side) in system_extra_currents(id,list)],
        estimated_station_seconds=id=="ieee14" ? 36000 : 10800)
end

function require_committed_systems()
    paths=[source["path"] for source in source_record()]
    append!(paths,["test/manual/pscad/run_system_screens.jl","test/manual/pscad/validation/README.md",
        "test/manual/pscad/validation/system_model_translation.md","test/pscad/system_factories_test.jl",
        "test/pscad/system_test.jl","test/pscad/growth_test.jl","test/pscad/validation_test.jl",
        "test/pscad/manual_scripts_test.jl","test/pscad/dc_precharge_test.jl","Project.toml"])
    for path in unique(paths)
        committed=try read(pipeline(`git -C $REPOSITORY show $("HEAD:"*path)`;stderr=devnull)) catch; UInt8[] end
        committed==read(joinpath(REPOSITORY,path)) || error("system preparation requires HEAD to contain this change: $path differs")
    end
    return nothing
end

function system_selection(ids)
    selected=ids isa AbstractString ? [String(ids)] : String.(collect(ids))
    !isempty(selected) && length(unique(selected))==length(selected) && all(in(SYSTEM_PORT_IDS),selected) ||
        throw(ArgumentError("invalid system fixture selection"))
    return selected
end

function system_sizing(c,spec)
    # Conservative multitone peak bound across every free voltage and converter
    # current. This offline bound never substitutes for measured departures.
    functions=composed_device_functions(c)
    drive=zeros(ComplexF64,length(c.nodes),4);drive[1:4,:]=I(4)
    voltage=zeros(length(c.nodes),4);currents=Dict(n=>zeros(3,4) for n in c.devices)
    for f in spec.frequencies
        s=ComplexF64(im*2π*f);v=composed_nodal(c,s,functions)\drive
        voltage .+= abs.(v).*spec.current_bases'
        for name in c.devices
            currents[name] .+= abs.(functions[name](s)*component_incidence(c,
                name)'*v).*spec.current_bases'
        end
    end
    # Measurement bases use physical ratings, independently of the power-flow
    # solver's shared voltage base across transformer sides.
    list=fixture_netlist(c.net,nothing)
    dcbase=device_bases(c.net.elements[first(c.devices)].elec,
        c.net.elements[first(c.devices)].bases).dc_voltage
    vb=[only(filter(b->node in b.nets,list.buses)).kind==:dc ? dcbase : spec.voltage_base_kV for node in c.nodes]
    for name in c.devices
        e=c.net.elements[name];b=device_bases(e.elec, e.bases)
        for axis in 1:2
            j=findfirst(==(port_nets(c.net, name, :ac)[axis]),c.nodes)
            j===nothing || (vb[j]=b.ac_voltage)
        end
    end
    vpeak=maximum(voltage./vb)*spec.tone_peak_pu
    ipeak=maximum(maximum(currents[n]./
        device_bases(c.net.elements[n].elec, c.net.elements[n].bases).current_outputs)
        for n in c.devices)*spec.tone_peak_pu
    return Dict("voltage_peak_bound_pu"=>vpeak,"device_current_peak_bound_pu"=>ipeak,
        "method"=>"sum of per-tone magnitudes; native full-network response; no cancellation assumed",
        "passed"=>max(vpeak,ipeak)<=.01)
end

function system_setup(id)
    entry=fixture(id);net=entry.factory();point=compute(PowerFlowProblem(net),
        ACDCPowerFlow());
    NetworkBuilder.NetworkModel(net, point.operating_point);c=complete_system(id,net)
    screen=system_stability(c)
    screen["status"]=="passed_finite_screen" || @warn "$id complete-network finite screen result: $(screen["status"])" screen
    list=fixture_netlist(net,point);spec=system_spec(id,list)
    sizing=system_sizing(c,spec)
    return (;entry,net,point,c,screen,list,spec,sizing)
end

function prepare_system(setup;directory,remote)
    (;entry,c,screen,list,spec,sizing)=setup
    id=entry.id
    ispath(directory) && error("fresh system directory already exists: $directory")
    paths=check_prepared_run_paths(id,composed_run_axes([spec]),remote)
    mkpath(directory)
    models=prepare_composed_projects(directory,list,c,[spec],remote)
    record=preparation_record(entry,screen,models;directory)
    record["required_subsystems"]=1
    record["prepared_run_paths"]=paths;record["frequency_response"]=scan_record(spec)
    record["measurement_groups"]=Dict(spec.protocol=>scan_record(spec))
    record["measurands"]=composed_targets(c);record["drive_sizing"]=sizing
    record["qualification_reference"]=
        any(interface_step_eligible(c.net.elements[n]) for n in c.devices) ?
            "composed_discrete_realization" : "plain_model"
    record["qualification_status"]="station_pending"
    record["distributed_model_scope"]=screen["root_scope"]
    write_operating_point(joinpath(directory,"operating_point.tsv"),first(models).second)
    write_manifest(directory,record)
    return models
end

function prepare_systems(ids;remote=nothing,directory=joinpath(ROOT,"data"))
    selected=system_selection(ids)
    require_committed_systems()
    for id in selected
        ispath(joinpath(directory,id)) && error("fresh system directory already exists: $id")
    end
    setups=[id in SYSTEM_GROWTH_IDS ? system_growth_setup(id) : system_setup(id) for id in selected]
    remote===nothing && (remote=RemoteConfig())
    for (id,setup) in zip(selected,setups)
        axes=id in SYSTEM_GROWTH_IDS ? [v.key for v in system_growth_variants(setup.spec)] : composed_run_axes([setup.spec])
        check_prepared_run_paths(id,axes,remote)
    end
    for (id,setup) in zip(selected,setups)
        dest=joinpath(directory,id)
        id in SYSTEM_GROWTH_IDS ? prepare_system_growth(setup;directory=dest,remote) : prepare_system(setup;directory=dest,remote)
    end
    return selected
end

function run_system(id;directory,remote,deadline)
    time()<deadline || error("system runtime budget exhausted")
    record=manifest_lists!(TOML.parsefile(joinpath(directory,"manifest.toml")));verify_inputs(directory,record)
    record["fixture_id"]==id || error("system fixture differs")
    net=fixture(id).factory();point=compute(PowerFlowProblem(net), ACDCPowerFlow());
    NetworkBuilder.NetworkModel(net, point.operating_point);c=complete_system(id,net)
    list=fixture_netlist(net,point);spec=system_spec(id,list)
    native_operating_point_check(list,joinpath(directory,"operating_point.tsv"))["passed"] || error("system operating point changed")
    scan_record(spec)==record["measurement_groups"][spec.protocol] || error("system measurement definition changed")
    record["status"]="running";started=time();pop!(record,"failure",nothing)
    try
        group=run_composed_group!(record,c,list,spec;directory,remote,deadline)
        record["status"]=group["status"]
        record["qualification_status"]=record["status"]
    catch failure
        record["status"]="run_or_analysis_failed";record["failure"]=sprint(showerror,failure);rethrow()
    finally
        record["station_workflow_seconds"]=time()-started
        write_manifest(directory,record)
    end
    return record
end

function run_systems(;timeout=100800.,ids=nothing,remote=nothing,directory=joinpath(ROOT,"data"))
    isfinite(timeout) && timeout>0 || throw(ArgumentError("timeout must be finite and positive"))
    selected=ids===nothing ? nothing : system_selection(ids)
    require_committed_systems()
    selected===nothing && (selected=system_selection([id for id in SYSTEM_PORT_IDS if isfile(joinpath(directory,id,"manifest.toml"))]))
    remote===nothing && (remote=RemoteConfig())
    deadline=time()+timeout
    queue=Dict{String,Any}("order"=>selected,"outcomes"=>Dict{String,Any}())
    output=mkpath(joinpath(directory,"systems"));path=joinpath(output,"queue.toml")
    for id in selected
        try
            result=id in SYSTEM_GROWTH_IDS ? run_system_growth(id;directory=joinpath(directory,id),remote,deadline) :
                run_system(id;directory=joinpath(directory,id),remote,deadline)
            queue["outcomes"][id]=Dict("status"=>result["status"])
        catch failure
            failure isa InterruptException && rethrow()
            queue["outcomes"][id]=Dict("status"=>"run_or_analysis_failed","failure"=>sprint(showerror,failure))
            @warn "system fixture failed; continuing" fixture=id reason=sprint(showerror,failure)
        end
        open(io->TOML.print(io,queue;sorted=true),path,"w")
    end
    return queue
end
