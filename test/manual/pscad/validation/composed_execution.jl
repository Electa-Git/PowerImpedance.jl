const COUPLED_NATIVE_NODES = Dict("two_tlc_shared_bus"=>31,"two_mmc_shared_bus"=>77,"mmc_gfm_gfl_shared_bus"=>77,"mmc_pi_line"=>67,
    "tlc_transformer_line"=>52,"machine_mmc_shared_bus"=>55,"two_mmc_dc_cable"=>96,"mmc_rc_shunt"=>55)
# Ratings are frozen independently of solved voltages and measured outcomes. `two_mmc_dc_cable`
# declares this rating at each of its two AC ports.
const COUPLED_AGGREGATE_BASES = Dict("two_tlc_shared_bus"=>(power_MVA=200.,voltage_LL_kV=220.),
    "two_mmc_shared_bus"=>(power_MVA=2000.,voltage_LL_kV=380.),
    "mmc_gfm_gfl_shared_bus"=>(power_MVA=2060.,voltage_LL_kV=380.),
    "mmc_pi_line"=>(power_MVA=1000.,voltage_LL_kV=380.),
    "tlc_transformer_line"=>(power_MVA=100.,voltage_LL_kV=380.),
    "machine_mmc_shared_bus"=>(power_MVA=2000.,voltage_LL_kV=380.),
    "two_mmc_dc_cable"=>(power_MVA=1000.,voltage_LL_kV=380.),
    "mmc_rc_shunt"=>(power_MVA=1000.,voltage_LL_kV=380.))

function composed_ac!(net,name,side,bus)
    for t in 1:2
        connect!(net,(name,Symbol("$side.$t")),bus==:gnd ? :gnd : Symbol("$(bus)_$t"))
    end
end

function coupled_network(id)
    id in [SHARED_BUS_SHUNT_IDS;COUPLED_LINE_CONVERTER_IDS;MACHINE_DC_COUPLING_IDS] || error("coupled-circuit fixture is not registered: $id")
    net=Network();tlc_pair=id=="two_tlc_shared_bus";vll=tlc_pair ? 220. : 380.
    net.voltageBase[1]=vll/sqrt(3)
    devices=id in ("two_tlc_shared_bus","two_mmc_shared_bus","mmc_gfm_gfl_shared_bus","machine_mmc_shared_bus","two_mmc_dc_cable") ? [:C1,:C2] : [:C1]
    for name in devices
        d=if tlc_pair
            deepcopy(tlc_strong_network(mode=name==:C1 ? :pq : :qv).elements[:DUT])
        elseif id=="machine_mmc_shared_bus" && name==:C1
            active_device(:machine)
        elseif id=="mmc_gfm_gfl_shared_bus" && name==:C1
            active_device(:gfm)
        else
            deepcopy(mmc_grid_network(mode=id=="two_mmc_dc_cable" && name==:C1 ? :vdc : id=="two_mmc_shared_bus" && name==:C2 ? :qv : :pq).elements[:DUT])
        end
        bases=device_bases(d.element_model.elec)
        add!(net,name,d);composed_ac!(net,name,bases.ac_side,id=="mmc_pi_line" ? :Remote : id=="two_mmc_dc_cable" ? name : :AC)
        if bases.dc_voltage===nothing
            composed_ac!(net,name,2,:gnd)
            continue
        elseif id=="two_mmc_dc_cable"
            connect!(net,(name,Symbol("1.1")),Symbol("DC_",name))
            continue
        end
        dc=Symbol("D_",name);bus=Symbol("DC_",name)
        add!(net,dc,dc_source(setpoint=Setpoint(Vdc=bases.dc_voltage)))
        connect!(net,(dc,Symbol("1.1")),bus);connect!(net,(dc,Symbol("2.1")),:gnd)
        connect!(net,(name,Symbol("1.1")),bus)
    end
    rating=tlc_pair ? 100. : id=="mmc_gfm_gfl_shared_bus" ? 2060. : id=="machine_mmc_shared_bus" ? 2000. : 1000.
    r=vll^2/rating/8/sqrt(101);l=10r/(2π*50)
    if id=="two_mmc_dc_cable"
        for (suffix,bus) in ((:A,:C1),(:B,:C2))
            source=Symbol("G_",suffix);grid=Symbol("Grid_",suffix);src=Symbol("Src_",suffix)
            add!(net,source,ac_source(pins=3,transformation=true,setpoint=Setpoint(Vac=vll*sqrt(2/3))))
            add!(net,grid,impedance(z=s->r+l*s,pins=3,transformation=true))
            composed_ac!(net,source,1,src);composed_ac!(net,source,2,:gnd)
            composed_ac!(net,grid,1,bus);composed_ac!(net,grid,2,src)
        end
        cable=deepcopy(ClassicFixtures.dc_cable_network().elements[:line])
        cable.element_model.length=25e3
        add!(net,:CableDC,cable)
        connect!(net,(:CableDC,Symbol("1.1")),:DC_C1)
        connect!(net,(:CableDC,Symbol("2.1")),:DC_C2)
        connect!(net)
        return net
    end
    add!(net,:G_A,ac_source(pins=3,transformation=true,setpoint=Setpoint(Vac=vll*sqrt(2/3))))
    add!(net,:Grid_A,impedance(z=s->r+l*s,pins=3,transformation=true))
    composed_ac!(net,:G_A,1,:Src);composed_ac!(net,:G_A,2,:gnd)
    composed_ac!(net,:Grid_A,1,:AC);composed_ac!(net,:Grid_A,2,:Src)
    if id=="mmc_rc_shunt"
        add!(net,:Filter,impedance(z=s->2.0 + inv(s*5e-6),pins=3,transformation=true))
        composed_ac!(net,:Filter,1,:AC);composed_ac!(net,:Filter,2,:gnd)
    elseif id=="mmc_pi_line"
        add!(net,:Line,impedance(z=s->2.0+.02s,pins=3,transformation=true))
        composed_ac!(net,:Line,1,:AC);composed_ac!(net,:Line,2,:Remote)
        for (name,bus) in ((:Cnear,:AC),(:Cfar,:Remote))
            add!(net,name,impedance(z=s->inv(2e-6*s),pins=3,transformation=true))
            composed_ac!(net,name,1,bus);composed_ac!(net,name,2,:gnd)
        end
    end
    connect!(net)
    return net
end

function coupled_circuit(id,net)
    devices=filter(n->haskey(net.elements,n),[:C1,:C2])
    grids=id=="two_mmc_dc_cable" ? [:Grid_A,:Grid_B] : [:Grid_A]
    ports=id=="two_mmc_dc_cable" ? [(:C1,2),(:C2,2)] : id=="mmc_pi_line" ? [(:Line,1)] :
        [(:C1,device_bases(net.elements[:C1].element_model.elec).ac_side)]
    return composed_circuit(net,devices,grids,ports)
end

function coupled_spec(id,list; local_scan=false)
    local_scan && !(id in ("mmc_pi_line","mmc_rc_shunt")) && error("no local scan declared for $id")
    fs=local_scan ? (id=="mmc_pi_line" ? collect(357.:.5:378.) : [collect(232.:1.5:260.5);collect(334.:1.5:361.)]) :
        Float64.([1,2,3,4,6,7,10,13,18,24,32,42,56,75,100,133,178,237,316,422,562,750,1000])
    bases=COUPLED_AGGREGATE_BASES[id];vll=bases.voltage_LL_kV;sbase=bases.power_MVA
    vb=vll*sqrt(2/3);ib=2sbase/(3vb)
    amp=local_scan ? (id=="mmc_pi_line" ? 2.4385006018880013e-5 : 5.910035278632797e-5) :
        id=="two_tlc_shared_bus" ? 0.0004508893578873102 : id=="two_mmc_shared_bus" ? 0.000255889219949928 :
        id=="mmc_gfm_gfl_shared_bus" ? 0.0006924416531567809 : id=="mmc_pi_line" ? 0.0007118962353546502 : id=="machine_mmc_shared_bus" ? .0006705809970911343 :
        id=="two_mmc_dc_cable" ? .0005452727356004889 : 0.00047389717632280974
    ports=id=="two_mmc_dc_cable" ? [(:C1,2),(:C2,2)] : id=="mmc_pi_line" ? [(:Line,1)] : [(:C1,id=="machine_mmc_shared_bus" ? 1 : 2)]
    np=2length(ports);h=id in MACHINE_DC_COUPLING_IDS ? 1.25e-6 : 2.5e-6;start=id=="machine_mmc_shared_bus" ? 64. : 16.
    bands=local_scan ? (id=="mmc_pi_line" ? [collect(1:43)] : [collect(1:20),collect(21:39)]) : Vector{Int}[]
    return (id=id,quantity="Y",dimension=2,buses=[port_probe(list,p...) for p in ports],currents=[(string(p[1]),string(p[2])) for p in ports],
        axes=["p$(j)_$axis" for j in eachindex(ports) for axis in ("d","q")],frequencies=fs,phases=[-π*k*(k-1)/length(fs) for k in eachindex(fs)],
        tone_peak_pu=amp,injection_time=2.,frequency=50.,voltage_base_kV=vb,current_base_kA=ib,
        voltage_bases=fill(vb,np),current_bases=fill(ib,np),power_base_MVA=sbase,
        time_step=h,sample_step=25h,window_starts=(start,start+8),window_duration=8.,simulation_time=start+16,
        minimum_witness_window_s=id=="machine_mmc_shared_bus" ? 2. : .1,
        drive="current",dc_clamped=id!="two_mmc_dc_cable",dc_reference=:midpoint_resistors,dc_voltage_base_kV=id=="two_tlc_shared_bus" ? 640. : 800.,active=true,
        protocol=local_scan ? "composed_local" : "composed_coarse",travel_lower_bound_s=0.,
        resonance_groups=bands,
        settling=id=="mmc_gfm_gfl_shared_bus" ? Dict("scope"=>"equilibrium initialization; measurement drift gates remain mandatory",
            "caveat"=>"slow initialized GFM filters: 8 s windows do not establish generic startup settling; no 400-to-380 kV nameplate rescaling") :
            Dict("scope"=>"frozen onset and coherent windows; measurement drift gates remain mandatory"),
        estimated_station_seconds=id=="machine_mmc_shared_bus" ? 15600 : id=="two_mmc_dc_cable" ? 9000 : id=="two_tlc_shared_bus" ? 2400 : id in ("two_mmc_shared_bus","mmc_gfm_gfl_shared_bus") ? 3600 : 5400)
end

function coupled_specs(id,list)
    coarse=coupled_spec(id,list)
    return id in ("mmc_pi_line","mmc_rc_shunt") ? [coarse,coupled_spec(id,list;local_scan=true)] : [coarse]
end

# All coarse-axis and frequency selections are included, beyond the initial template.
function composed_run_axes(specs)
    axes=String[]
    for spec in specs
        prefix=scan_prefix(spec)
        append!(axes,[prefix*"baseline",prefix*"measurement_baseline"])
        append!(axes,[prefix*stem*axis for stem in ("measurement_","half_amplitude_") for axis in ["baseline";spec.axes]])
        for frequency in (spec.protocol=="composed_local" ? [first(spec.frequencies)] : spec.frequencies)
            step=composed_step_spec(spec,frequency;local_scan=spec.protocol=="composed_local")
            append!(axes,[step_prefix(step)*axis for axis in ["baseline";step.axes]])
        end
    end
    return unique(axes)
end

function composed_step_spec(spec,frequency; local_scan=false)
    local_scan && return merge(spec,(;time_step=spec.time_step/2,sample_step=spec.sample_step/2,recorder_scope="measurement"))
    step=step_definition(merge(spec,(;protocol="dq_active")),frequency)
    if spec.id=="machine_mmc_shared_bus"
        step=merge(step,(;window_starts=spec.window_starts,window_duration=spec.window_duration,
            simulation_time=spec.simulation_time))
    end
    step.window_duration<=8. || error("witness exceeds predeclared window allowance")
    return merge(step,(;protocol=spec.protocol,recorder_scope="measurement"))
end

composed_readout_targets(c,label)=label=="discrete" ? ["direct_Z";filter(t->startswith(t,"DC_"),composed_targets(c))] : String[]
composed_reference_rows(c,spec,target)=startswith(target,"DC_") ? 2 : length(spec.axes)

function composed_reference_transport!(refs,c,spec,label)
    for target in composed_readout_targets(c,label), (k,f) in enumerate(spec.frequencies)
        refs[target][:,:,k] .*= injection_readout_factor(f,spec)
    end
    return refs
end

function composed_reference_files!(record,c,spec,directory,forms; verify=false)
    discrete=any(interface_step_eligible(c.net.elements[n].element_model) for n in c.devices)
    for (label,h) in (discrete ? (("plain",nothing),("discrete",spec.time_step)) : (("plain",nothing),))
        refs=composed_reference(c,spec;time_step=h,forms=label=="discrete" ? forms : nothing)
        composed_reference_transport!(refs,c,spec,label)
        for (target,reference) in refs
            path=joinpath(directory,scan_prefix(spec)*label*"_"*target*"_reference.tsv")
            ts=composed_target_spec(spec,c,target)
            if verify || isfile(path)
                stored=read_response(path,length(spec.axes),spec.frequencies;rows=size(reference,1))
                native_reference_check(ts,reference,stored)["passed"] || error("composed reference changed: $target/$label")
            else
                write_response(path,reference,spec.frequencies;quantity=ts.quantity)
            end
        end
    end
    return nothing
end

function composed_frozen_references(directory,spec,c,label)
    targets=composed_targets(c)
    return Dict(target=>read_response(joinpath(directory,scan_prefix(spec)*label*"_"*target*"_reference.tsv"),
        length(spec.axes),spec.frequencies;rows=composed_reference_rows(c,spec,target)) for target in targets)
end

function prepare_composed(id;directory=joinpath(ROOT,"data",id),remote=nothing)
    id in COUPLED_LINE_CONVERTER_IDS && require_committed_coupled_line_converter()
    id in MACHINE_DC_COUPLING_IDS && require_committed_machine_dc_coupling()
    remote===nothing && (remote=RemoteConfig())
    entry=fixture(id);net=entry.factory();point=power_flow(net);c=coupled_circuit(id,net)
    gate=composed_stability(c)
    gate["status"]=="passed" || @warn "$id composed stability result: $(gate["status"])" stability=gate
    # Fresh preparation excludes retained runs, reference tables and proposal exports.
    ispath(directory) && error("fresh composed directory already exists: $directory")
    list=fixture_netlist(net,point);spec=coupled_spec(id,list)
    groups=coupled_specs(id,list)
    path_limits=check_prepared_run_paths(id,composed_run_axes(groups),remote)
    mkpath(directory)
    allmodels=prepare_composed_projects(directory,list,c,groups,remote)
    record=preparation_record(entry,gate,allmodels;directory)
    record["prepared_run_paths"]=path_limits
    record["frequency_response"]=scan_record(spec)
    record["aggregate_bases"]=Dict("power_MVA"=>spec.power_base_MVA,"voltage_kVpeak"=>spec.voltage_bases,"current_kApeak"=>spec.current_bases)
    individual_bases=Dict{String,Any}()
    for n in c.devices
        bases=device_bases(net.elements[n].element_model.elec)
        individual_bases[string(n)]=Dict("voltage_kVpeak"=>bases.ac_voltage,
            "current_kApeak"=>bases.ac_current,"power_MVA"=>bases.power)
    end
    record["individual_bases"]=individual_bases
    record["native_node_admission"]=Dict("source"=>"owner station measurement","duration_s"=>.01,
        "errors"=>0,"live_nodes"=>COUPLED_NATIVE_NODES[id],"limit_exclusive"=>100,
        "scope"=>"proposal exports; every new measurement build checks its own live count")
    record["measurement_groups"]=Dict(g.protocol=>scan_record(g) for g in groups)
    if id=="two_mmc_dc_cable"
        record["distributed_admission_caveat"]=gate["root_scope"]
        record["cross_entry_accuracy"]="near-zero cross entries are scored only against the absolute floor; no relative-accuracy claim"
        record["dc_transfer_witnesses"]=Dict("voltage_base_kV"=>800.,"current_base_kA"=>1.25,
            "rows"=>["CableDC side 1 inward","CableDC side 2 inward"],"drives"=>spec.axes)
        record["precharge"]=Dict("buses"=>[b.name for b in P._dc_precharge_buses(list)],
            "release_s"=>.2,"pole_voltage_kV"=>[b.vm_pu*b.base_kV for b in P._dc_precharge_buses(list)])
    end
    record["qualification_reference"]=any(interface_step_eligible(net.elements[n].element_model) for n in c.devices) ? "composed_discrete_realization" : "plain_model"
    record["qualification_status"]="station_pending"
    record["fresh_generation"]="coupled-circuit fresh generation; no prior projects, references or native completions reused"
    write_operating_point(joinpath(directory,"operating_point.tsv"),first(allmodels).second)
    environment=mkpath(joinpath(directory,"environment"))
    cp(Base.active_project(),joinpath(environment,"Project.toml"))
    manifest=joinpath(dirname(Base.active_project()),"Manifest.toml")
    isfile(manifest) && cp(manifest,joinpath(environment,"Manifest.toml"))
    write_manifest(directory,record)
    return allmodels
end

function composed_witnesses!(group_record,c,spec,step_spec,column,main,half,amp,
        models,checks,output)
    residual=any(interface_step_eligible(c.net.elements[n].element_model) for n in c.devices)
    forms=exported_composed_passives(c,models.main.project_path,models.main.netlist)
    forms==exported_composed_passives(c,models.half.project_path,models.half.netlist) || error("half-step passives changed")
    pred=residual ? composed_predicted_columns(c,spec,column,forms) : nothing
    predhalf=residual ? composed_predicted_columns(c,step_spec,column,forms) : nothing
    indices=[only(findall(==(f),spec.frequencies)) for f in step_spec.frequencies]
    witnesses=Dict{String,Any}()
    for target in keys(main)
        a=main[target];b=half[target];am=amp[target]
        amplitude=Dict{String,Any}(matrix_change(am.matrix,a.matrix;epsilon=.02))
        amplitude["valid"]=a.quality["valid"]&&am.quality["valid"]
        amplitude["passed"] &= amplitude["valid"]
        amplitude["quality"]=am.quality
        raw=Dict{String,Any}(matrix_change(b.matrix,a.matrix[:,:,indices];epsilon=.01))
        raw["valid"]=a.quality["valid"]&&b.quality["valid"]&&all(x["passed"] for x in checks)
        raw["passed"] &= raw["valid"];raw["quality"]=b.quality
        selected=raw;reproduction=Dict{String,Any}()
        device=findfirst(n->target==string(n)*"_Y",c.devices)
        device_residual=device!==nothing && interface_step_eligible(c.net.elements[c.devices[device]].element_model)
        use_residual=false
        if residual
            pm=pred[target];ph=predhalf[target]
            rm=matrix_change(a.matrix,pm;epsilon=.01);rh=matrix_change(b.matrix,ph;epsilon=.01)
            reproduction=Dict("main"=>rm,"half"=>rh)
            use_residual=device===nothing ? rm["passed"]&&rh["passed"] : device_residual
        end
        reason=device!==nothing ? (device_residual ? "zero-delay converter" : "device without zero-delay modulation") :
            !residual ? "circuit has no zero-delay converter" : use_residual ?
            "circuit reference reproduces main and half-step columns within 1 %" :
            "circuit reference does not reproduce main and half-step columns within 1 %"
        if use_residual
            valid=raw["valid"]&&rm["passed"]&&rh["passed"]
            selected=residual_step_change(a.matrix[:,:,indices],b.matrix,pm[:,:,indices],ph;valid)
            rows=[(step=label,frequency_Hz=f,row=r,measured_real=real(m[r,1,k]),measured_imag=imag(m[r,1,k]),
                predicted_real=real(p[r,1,k]),predicted_imag=imag(p[r,1,k]))
                for (label,fs,m,p) in (("main",spec.frequencies,a.matrix,pm),("half",step_spec.frequencies,b.matrix,ph))
                for (k,f) in enumerate(fs) for r in axes(m,1)]
            write_table(joinpath(output,target*"_residual_columns.tsv"),rows)
            residual_rows=[begin
                j=indices[k]
                change=residual_step_change(a.matrix[:,:,j:j],b.matrix[:,:,k:k],pm[:,:,j:j],ph[:,:,k:k];valid)
                (frequency_Hz=f,frobenius_change=change["frobenius_change"],entry_change=change["entry_change"],
                    residual_normalised_frobenius=change["residual_normalised_frobenius"],
                    residual_normalised_entry=change["residual_normalised_entry"],valid,within_tolerance=change["passed"])
            end for (k,f) in enumerate(step_spec.frequencies)]
            write_table(joinpath(output,target*"_residual_step.tsv"),residual_rows)
        end
        write_table(joinpath(output,target*"_amplitude.tsv"),refinement_rows(spec.frequencies,am.matrix,a.matrix;limit=.02,valid=amplitude["valid"]))
        write_table(joinpath(output,target*"_raw_step.tsv"),refinement_rows(step_spec.frequencies,b.matrix,a.matrix[:,:,indices];limit=.01,valid=raw["valid"]))
        valid=amplitude["valid"]&&selected["valid"]
        status=!valid ? "invalid_measurement" : amplitude["passed"]&&selected["passed"] ? "passed" : "failed"
        reasons=String[]
        append!(reasons,["main: "*r for r in get(a.quality,"invalid_reasons",String[])])
        append!(reasons,["half_amplitude: "*r for r in get(am.quality,"invalid_reasons",String[])])
        append!(reasons,["half_step: "*r for r in get(b.quality,"invalid_reasons",String[])])
        all(x["passed"] for x in checks) || push!(reasons,"kcl_readout")
        if use_residual
            reproduction["main"]["passed"] || push!(reasons,"main_discrete_reproduction")
            reproduction["half"]["passed"] || push!(reasons,"half_step_discrete_reproduction")
        end
        witnesses[target]=Dict("status"=>status,"invalid_reasons"=>reasons,"amplitude"=>amplitude,"raw_step"=>raw,"selected_step"=>selected,
            "reproduction"=>reproduction,"step_reference"=>use_residual ? "composed_residual" : "raw",
            "step_reference_reason"=>reason)
    end
    group_record["witnesses"]=witnesses;group_record["readout_checks"]=checks
    group_record["exported_passives"]=Dict(string(n)=>Dict("topology"=>string(f.topology),
        "R_ohm"=>something(f.R,0.),"L_H"=>something(f.L,0.),"C_F"=>something(f.C,0.)) for (n,f) in forms)
    group_record["selected_axis"]=spec.axes[column];group_record["step_definition"]=scan_record(step_spec)
    return witnesses
end

function run_composed_group!(record,c,list,spec;directory,remote,deadline)
    local_scan=spec.protocol=="composed_local";prefix=scan_prefix(spec)
    output=mkpath(joinpath(directory,"analysis",spec.protocol))
    group=get!(get!(record,"groups",Dict{String,Any}()),spec.protocol,Dict{String,Any}())
    results=Dict{String,P.PSCADResult}();models=Dict{String,P.PSCADModel}()
    for axis in ["baseline";spec.axes]
        project_prefix=axis=="baseline" ? prefix : prefix*"measurement_"
        key=project_prefix*axis
        model=existing_model(record,key,list,spec,directory;prefix=project_prefix)
        results[axis]=execute_axis!(record,key,model,directory,remote,deadline);models[axis]=model
        if axis=="baseline"
            rows=compare_operating_point(results[axis],model)
            write_table(joinpath(output,"comparison_operating_point.tsv"),rows)
            group["operating_point_status"]=all(rows.within_tolerance) ? "passed" : "failed"
        end
    end
    forms=exported_composed_passives(c,models["baseline"].project_path,list)
    composed_reference_files!(record,c,spec,directory,forms;verify=true)
    residual=any(interface_step_eligible(c.net.elements[n].element_model) for n in c.devices)
    qualifying=nothing
    for label in (residual ? ("plain","discrete") : ("plain",))
        refs=composed_frozen_references(directory,spec,c,label)
        dest=mkpath(joinpath(output,label))
        bands=local_scan ? spec.resonance_groups : Vector{Int}[]
        comparison=composed_comparison(results,models,refs,dest,spec,c;resonance_groups=bands)
        group[label]=comparison.comparisons
        group["readout_checks"]=comparison.kcl
        group["invalid_reasons"]=Dict(target=>x["invalid_reasons"] for (target,x) in comparison.comparisons)
        write_manifest(directory,record)
        qualifying=comparison
    end
    outcomes=Dict(target=>x["status"] for (target,x) in qualifying.comparisons)
    any(in(("invalid_measurement","model_mismatch")),values(outcomes)) &&
        @warn "$(spec.id) frequency-response results: $outcomes"
    # The selected axis and frequency are saved before any comparison run; retries use
    # exactly this choice.
    chosen=get!(group,"selection",Dict("column"=>qualifying.selection.column,"frequency_Hz"=>qualifying.selection.frequency))
    column=chosen["column"];axis=spec.axes[column]
    step=composed_step_spec(spec,chosen["frequency_Hz"];local_scan)
    write_manifest(directory,record)
    halfspec=merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2,recorder_scope="measurement"))
    ampmodel=existing_model(record,prefix*"half_amplitude_"*axis,list,halfspec,directory)
    ampresult=execute_axis!(record,prefix*"half_amplitude_"*axis,ampmodel,directory,remote,deadline)
    stepmodels=prepare_scan_projects(directory,list,step,[axis];prefix=step_prefix(step),remote)
    for (key,model) in stepmodels;record_project!(record,key,model,directory);end
    write_manifest(directory,record)
    stepbase=execute_axis!(record,first(stepmodels).first,first(stepmodels).second,directory,remote,deadline)
    stepmodel=last(stepmodels).second
    stepresult=execute_axis!(record,last(stepmodels).first,stepmodel,directory,remote,deadline)
    main=composed_column(results[axis],results["baseline"],models[axis],spec,c,column)
    amp=composed_column(ampresult,results["baseline"],ampmodel,halfspec,c,column)
    half=composed_column(stepresult,stepbase,stepmodel,step,c,column)
    checks=copy(qualifying.kcl)
    push!(checks,composed_readout_evidence(ampresult,results["baseline"],ampmodel,halfspec,c,column;axis="half_amplitude_"*axis))
    push!(checks,composed_readout_evidence(stepresult,stepbase,stepmodel,step,c,column;axis="half_step_"*axis))
    witnesses=composed_witnesses!(group,c,spec,step,column,main,half,amp,(main=models[axis],half=stepmodel),checks,output)
    label=residual ? "discrete" : "plain"
    group["measurand_summary"]=Dict(target=>Dict("plain"=>group["plain"][target]["status"],
        "discrete"=>residual ? group["discrete"][target]["status"] : "not_applicable",
        "witness"=>witnesses[target]["status"],
        "invalid_reasons"=>unique([group[label][target]["invalid_reasons"];witnesses[target]["invalid_reasons"]]),
        "status"=>group[label][target]["status"]=="model_mismatch" ? "model_mismatch" :
            group[label][target]["status"]=="invalid_measurement"||witnesses[target]["status"]=="invalid_measurement" ? "invalid_measurement" :
            group[label][target]["status"]=="passed"&&witnesses[target]["status"]=="passed" ? "passed" : "failed") for target in keys(witnesses))
    group["invalid_reasons"]=Dict(target=>x["invalid_reasons"] for (target,x) in group["measurand_summary"])
    statuses=[x["status"] for x in values(group["measurand_summary"])]
    group["status"]="model_mismatch" in statuses ? "model_mismatch" : "invalid_measurement" in statuses ? "invalid_measurement" :
        all(==("passed"),statuses)&&group["operating_point_status"]=="passed" ? "passed" : "failed"
    write_manifest(directory,record)
    return group
end

function run_composed(id;remote=RemoteConfig(),directory=joinpath(ROOT,"data",id),deadline=time()+10800,protocols=nothing)
    time()<deadline || error("composed station runtime budget exhausted")
    record=manifest_lists!(TOML.parsefile(joinpath(directory,"manifest.toml")));verify_inputs(directory,record)
    record["fixture_id"]==id || error("composed fixture mismatch")
    net=fixture(id).factory();point=power_flow(net);c=coupled_circuit(id,net)
    gate=composed_stability(c);record["stability"]=gate
    gate["status"]=="passed" || @warn "$id composed stability result: $(gate["status"])" stability=gate
    list=fixture_netlist(net,point)
    native_operating_point_check(list,joinpath(directory,"operating_point.tsv"))["passed"] || error("composed operating point changed")
    specs=coupled_specs(id,list)
    for spec in specs
        scan_record(spec)==record["measurement_groups"][spec.protocol] || error("composed measurement definition changed")
    end
    record["status"]="running";started=time();pop!(record,"failure",nothing)
    try
        for spec in specs
            protocols===nothing || spec.protocol in protocols || continue
            group=run_composed_group!(record,c,list,spec;directory,remote,deadline)
        end
        statuses=[g["status"] for g in values(record["groups"])]
        record["status"]="model_mismatch" in statuses ? "model_mismatch" : "invalid_measurement" in statuses ? "invalid_measurement" :
            length(statuses)==length(specs)&&all(==("passed"),statuses) ? "passed" : "failed"
        record["qualification_status"]=record["status"]
    catch failure
        record["status"]="run_or_analysis_failed";record["failure"]=sprint(showerror,failure);rethrow()
    finally
        record["station_workflow_seconds"]=time()-started
        summary=NamedTuple[]
        for (name,group) in get(record,"groups",Dict()), (target,status) in get(group,"measurand_summary",Dict())
            push!(summary,(measurement_group=name,measurand=target,
                plain=get(status,"plain","not_run"),discrete=get(status,"discrete","not_applicable"),
                witness=status["witness"],status=status["status"]))
        end
        isempty(summary) || write_table(joinpath(directory,"summary.tsv"),summary)
        write_manifest(directory,record)
    end
    return record
end

function prepare_shared_bus_shunt()
    return [prepare_composed(id) for id in SHARED_BUS_SHUNT_IDS]
end


# Preparation requires the implementation in HEAD, beyond a dirty or staged working copy.
# The time-domain implementation is compared before file creation.
function require_committed_coupled_line_converter()
    for file in ("composed_execution.jl","queue.jl","coverage.jl","scan.jl")
        path=relpath(joinpath(ROOT,file),REPOSITORY)
        committed=read(`git -C $REPOSITORY show $("HEAD:"*path)`)
        committed==read(joinpath(ROOT,file)) || error("coupled line/converter preparation requires HEAD to contain the current validation sources: $path differs from HEAD; merge the coupled line/converter change first")
    end
    return nothing
end

function prepare_coupled_line_converter(;remote=nothing)
    require_committed_coupled_line_converter()
    remote===nothing && (remote=RemoteConfig())
    return [prepare_composed(id;remote) for id in COUPLED_LINE_CONVERTER_IDS]
end

function replace_local_witness_projects!(record,directory,models,old_prefix)
    old=filter(p->startswith(p["axis"],old_prefix),record["projects"])
    isempty(old) && error("no long-name local half-step projects to archive")
    for project in old
        any(r->r["axis"]==project["axis"],record["run_records"]) && error("refusing to archive a run-recorded witness")
        isempty(completed_axis_runs(directory,project["axis"],project["sha256"])) || error("refusing to archive a completed witness")
        digest(joinpath(directory,project["path"]))==project["sha256"] || error("long-name project changed")
    end
    for (key,model) in models
        ispath(joinpath(directory,key)) && error("compact witness already exists: $key")
        all(modelpath->digest(model.project_path)!=modelpath["sha256"],old) || error("compact witness must have a fresh project hash")
    end
    archive=joinpath(directory,"history","local-witness-"*Dates.format(now(UTC),"yyyymmddTHHMMSSsss"))
    mkpath(archive);cp(joinpath(directory,"manifest.toml"),joinpath(archive,"manifest.toml"))
    for project in old
        mv(dirname(joinpath(directory,project["path"])),joinpath(archive,basename(dirname(project["path"]))))
    end
    filter!(p->!startswith(p["axis"],old_prefix),record["projects"])
    for (key,model) in models
        mv(dirname(model.project_path),joinpath(directory,key))
        moved=P.PSCADModel(joinpath(directory,key,basename(model.project_path)),model.project_name,
            model.netlist,model.probes,model.settings,model.operating_point,model.provenance)
        record_project!(record,key,moved,directory)
    end
    record["local_witness_repair"]=Dict("archive"=>relpath(archive,directory),"previous_projects"=>old,
        "previous_source_files"=>record["source_files"],"purpose"=>"compact local half-step paths; completed evidence retained")
    return record
end

function prepare_shunt_local_witness(;directory=joinpath(ROOT,"data","mmc_rc_shunt"),remote=nothing)
    require_committed_coupled_line_converter()
    remote===nothing && (remote=RemoteConfig())
    record=manifest_lists!(TOML.parsefile(joinpath(directory,"manifest.toml")))
    record["fixture_id"]=="mmc_rc_shunt" || error("local witness repair is restricted to mmc_rc_shunt")
    haskey(record,"local_witness_repair") && error("local witness already repaired")
    # Only the recorded harness revision may differ. Retained payloads are verified.
    allowed=Set("test/manual/pscad/validation/"*file for file in ("composed_execution.jl","queue.jl","coverage.jl","scan.jl"))
    for source in record["source_files"]
        source["path"] in allowed && continue
        digest(joinpath(REPOSITORY,source["path"]))==source["sha256"] || error("unrelated source changed: $(source["path"])")
    end
    for file in record["files"]
        path=joinpath(directory,file["path"])
        isfile(path) && filesize(path)==file["bytes"] && digest(path)==file["sha256"] || error("retained payload changed: $path")
    end
    coarse_status=get(record["groups"]["composed_coarse"],"status","")
    group=record["groups"]["composed_local"]
    local_status=Dict(target=>x["status"] for (target,x) in group["discrete"])
    record["local_repeat_prior_results"]=Dict("coarse_status"=>coarse_status,"local_status"=>local_status)
    coarse_status=="passed" || @warn "mmc_rc_shunt earlier coarse comparison result: $coarse_status"
    all(==("passed"),values(local_status)) || @warn "mmc_rc_shunt earlier local comparison results: $local_status"
    net=coupled_network("mmc_rc_shunt");point=power_flow(net);list=fixture_netlist(net,point);c=coupled_circuit("mmc_rc_shunt",net)
    stability=composed_stability(c);record["stability"]=stability
    stability["status"]=="passed" || @warn "mmc_rc_shunt composed stability result: $(stability["status"])" stability
    native_operating_point_check(list,joinpath(directory,"operating_point.tsv"))["passed"] || error("operating point changed")
    specs=coupled_specs("mmc_rc_shunt",list);spec=last(specs)
    spec=merge(spec,(;recorder_scope="measurement"))
    step=composed_step_spec(spec,group["selection"]["frequency_Hz"];local_scan=true)
    old_prefix=scan_prefix(step)*"half_step_"*join(round.(Int,step.frequencies),"_")*"__"
    paths=check_prepared_run_paths("mmc_rc_shunt",composed_run_axes(specs),remote)
    for frozen_spec in specs
        baseline=only(filter(p->p["axis"]==scan_prefix(frozen_spec)*"baseline",record["projects"]))
        forms=exported_composed_passives(c,joinpath(directory,baseline["path"]),list)
        composed_reference_files!(record,c,frozen_spec,directory,forms;verify=true)
    end
    mktempdir() do staging
        models=prepare_scan_projects(staging,list,step,step.axes;prefix=step_prefix(step),remote)
        replace_local_witness_projects!(record,directory,models,old_prefix)
    end
    record["source_files"]=source_record()
    record["measurement_groups"]=Dict(s.protocol=>scan_record(s) for s in specs)
    record["prepared_run_paths"]=paths
    record["status"]="local_witness_pending";record["qualification_status"]="witness_pending"
    write_manifest(directory,record)
    return record
end

append!(REGISTRY,[(;id,category=:coupled,description,parent,factory=()->coupled_network(id),topology,
    physics=["composed KCL","individual and aggregate admittance","direct closed-network impedance"],
    dissipativity=id=="two_mmc_dc_cable" ? "owner-admitted finite native contour to 1 MHz and located roots; infinite spectrum unenumerated; drift/window gates mandatory" : "complete-network descriptor and native contour required",
    differences=["positive-delay native Padé versus exact transport retained; zero-delay uses composed discrete realization";
        id=="mmc_gfm_gfl_shared_bus" ? ["equilibrium-start caveat: slow initialized GFM filters; no 400-to-380 kV nameplate rescaling"] :
        id=="two_mmc_dc_cable" ? ["finite contour and located roots do not prove closure at infinity; near-zero cross entries support only absolute floor accuracy"] : String[]],
    measurements=["operating_point", "frequency_response"],estimated_nodes=COUPLED_NATIVE_NODES[id])
    for (id,description,parent,topology) in (
        ("two_tlc_shared_bus","TLC P-f/Q + P/Q-V shared bus","tlc_pq_freq_support + tlc_p_qv","two DC-clamped TLCs — shared SCR-4 grid"),
        ("mmc_rc_shunt","MMC with damped series-RC shunt","mmc_pq + explicit R/C","DC-clamped MMC + series RC — SCR-8 grid"),
        ("two_mmc_shared_bus","MMC P/Q + P/Q-V shared bus","mmc_pq + mmc_p_qv","two DC-clamped MMCs — shared SCR-4 grid"),
        ("mmc_pi_line","MMC behind explicit lumped pi line","mmc_pq + explicit R/L/C","near-end port — pi line — remote DC-clamped MMC"),
        ("mmc_gfm_gfl_shared_bus","GFM + GFL MMC shared 380 kV bus","mmc_gfm_vsm + mmc_pq","separate DC clamps — shared SCR-8 grid on 2060 MVA"),
        ("two_mmc_dc_cable","DC-coupled Vdc/Q and P/Q MMC pair","mmc_vdc_q + mmc_pq + dc_cable_ohl","independent SCR-8 AC grids — native distributed 25 km DC cable"),
        ("machine_mmc_shared_bus","Synchronous machine + MMC shared bus","synchronous_machine + mmc_pq","machine and DC-clamped MMC — shared SCR-8 grid on 2000 MVA"))])

function require_committed_machine_dc_coupling()
    for file in ("composed_execution.jl","composed_network.jl","composed_measurement.jl",
            "queue.jl","coverage.jl","scan.jl","frequency.jl","records.jl","ports.jl")
        path=relpath(joinpath(ROOT,file),REPOSITORY)
        committed=read(`git -C $REPOSITORY show $("HEAD:"*path)`)
        committed==read(joinpath(ROOT,file)) || error("machine/DC coupling preparation requires HEAD to contain the current validation sources: $path differs from HEAD; commit the machine/DC coupling change first")
    end
    return nothing
end

function prepare_machine_dc_coupling(;remote=nothing)
    require_committed_machine_dc_coupling()
    remote===nothing && (remote=RemoteConfig())
    return [prepare_composed(id;remote) for id in MACHINE_DC_COUPLING_IDS]
end

function prepare_composed_projects(directory,list,c,groups,remote)
    allmodels=Pair{String,P.PSCADModel}[]
    for group in groups
        prefix=scan_prefix(group);check_recorder_sampling(group)
        # The baseline records all channels. A separate unrun measurement template keeps
        # only V/I/drive recorders for each injected run. Electrical meters remain.
        models=prepare_scan_projects(directory,list,group,String[];prefix,remote)
        measured=merge(group,(;recorder_scope="measurement"))
        append!(models,prepare_scan_projects(directory,list,measured,group.axes;prefix=prefix*"measurement_",remote))
        append!(models,prepare_scan_projects(directory,list,merge(measured,(;tone_peak_pu=group.tone_peak_pu/2,baseline_template=prefix*"measurement_baseline")),group.axes;
            prefix=prefix*"half_amplitude_",remote))
        step=composed_step_spec(group,1000.;local_scan=group.protocol=="composed_local")
        append!(models,prepare_scan_projects(directory,list,step,step.axes;prefix=step_prefix(step),remote))
        forms=exported_composed_passives(c,first(models).second.project_path,list)
        composed_reference_files!(nothing,c,group,directory,forms)
        append!(allmodels,models)
    end
    return allmodels
end
