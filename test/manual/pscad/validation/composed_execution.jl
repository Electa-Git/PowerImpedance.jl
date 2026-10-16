const L3_NATIVE_NODES = Dict("L3-01"=>31,"L3-02"=>77,"L3-03"=>77,"L3-04"=>67,
    "L3-05"=>52,"L3-06"=>55,"L3-07"=>96,"L3-08"=>55)
# Ratings are frozen independently of solved voltages and measured outcomes.
# L3-07 declares this rating at each of its two AC ports.
const L3_AGGREGATE_BASES = Dict("L3-01"=>(power_MVA=200.,voltage_LL_kV=220.),
    "L3-02"=>(power_MVA=2000.,voltage_LL_kV=380.),
    "L3-03"=>(power_MVA=2060.,voltage_LL_kV=380.),
    "L3-04"=>(power_MVA=1000.,voltage_LL_kV=380.),
    "L3-05"=>(power_MVA=100.,voltage_LL_kV=380.),
    "L3-06"=>(power_MVA=2000.,voltage_LL_kV=380.),
    "L3-07"=>(power_MVA=1000.,voltage_LL_kV=380.),
    "L3-08"=>(power_MVA=1000.,voltage_LL_kV=380.))

function composed_ac!(net,name,side,bus)
    for t in 1:2
        connect!(net,(name,Symbol("$side.$t")),bus==:gnd ? :gnd : Symbol("$(bus)_$t"))
    end
end

function l3_network(id)
    id in M9D_A_IDS || error("L3 fixture is not registered for stage A: $id")
    net=Network();tlc_pair=id=="L3-01";vll=tlc_pair ? 220. : 380.
    net.voltageBase[1]=vll/sqrt(3)
    devices=tlc_pair ? [:C1,:C2] : [:C1]
    for name in devices
        d=tlc_pair ? deepcopy(tlc_strong_network(mode=name==:C1 ? :pq : :qv).elements[:DUT]) :
            deepcopy(mmc_grid_network(mode=:pq).elements[:DUT])
        add!(net,name,d);composed_ac!(net,name,2,:AC)
        dc=Symbol("D_",name);bus=Symbol("DC_",name);vdc=tlc_pair ? 640. : 800.
        add!(net,dc,dc_source(setpoint=Setpoint(Vdc=vdc)))
        connect!(net,(dc,Symbol("1.1")),bus);connect!(net,(dc,Symbol("2.1")),:gnd)
        connect!(net,(name,Symbol("1.1")),bus)
    end
    rating=tlc_pair ? 100. : 1000.;r=vll^2/rating/8/sqrt(101);l=10r/(2π*50)
    add!(net,:G_A,ac_source(pins=3,transformation=true,setpoint=Setpoint(Vac=vll*sqrt(2/3))))
    add!(net,:Grid_A,impedance(z=s->r+l*s,pins=3,transformation=true))
    composed_ac!(net,:G_A,1,:Src);composed_ac!(net,:G_A,2,:gnd)
    composed_ac!(net,:Grid_A,1,:AC);composed_ac!(net,:Grid_A,2,:Src)
    if !tlc_pair
        add!(net,:Filter,impedance(z=s->2.0 + inv(s*5e-6),pins=3,transformation=true))
        composed_ac!(net,:Filter,1,:AC);composed_ac!(net,:Filter,2,:gnd)
    end
    connect!(net)
    return net
end

function l3_circuit(id,net)
    return composed_circuit(net,id=="L3-01" ? [:C1,:C2] : [:C1],[:Grid_A],[(:C1,2)])
end

function l3_spec(id,list; local_scan=false)
    local_scan && id!="L3-08" && error("no local scan declared for $id")
    fs=local_scan ? [collect(232.:1.5:260.5);collect(334.:1.5:361.)] :
        Float64.([1,2,3,4,6,7,10,13,18,24,32,42,56,75,100,133,178,237,316,422,562,750,1000])
    bases=L3_AGGREGATE_BASES[id];vll=bases.voltage_LL_kV;sbase=bases.power_MVA
    vb=vll*sqrt(2/3);ib=2sbase/(3vb)
    amp=local_scan ? 5.910035278632797e-5 : id=="L3-01" ? 0.0004508893578873102 : 0.00047389717632280974
    return (id=id,quantity="Y",dimension=2,buses=[port_probe(list,:C1,2)],currents=[("C1","2")],
        axes=["p1_d","p1_q"],frequencies=fs,phases=[-π*k*(k-1)/length(fs) for k in eachindex(fs)],
        tone_peak_pu=amp,injection_time=2.,frequency=50.,voltage_base_kV=vb,current_base_kA=ib,
        voltage_bases=fill(vb,2),current_bases=fill(ib,2),power_base_MVA=sbase,
        time_step=2.5e-6,sample_step=62.5e-6,window_starts=(16.,24.),window_duration=8.,simulation_time=32.,
        drive="current",dc_clamped=true,dc_voltage_base_kV=id=="L3-01" ? 640. : 800.,active=true,
        protocol=local_scan ? "composed_local" : "composed_coarse",travel_lower_bound_s=0.,
        estimated_station_seconds=id=="L3-01" ? 2400 : 5400)
end

function composed_step_spec(spec,frequency; local_scan=false)
    local_scan && return merge(spec,(;time_step=spec.time_step/2,sample_step=spec.sample_step/2,recorder_scope="measurement"))
    step=step_definition(merge(spec,(;protocol="dq_active")),frequency)
    step.window_duration<=8. || error("witness exceeds predeclared window allowance")
    return merge(step,(;protocol=spec.protocol,recorder_scope="measurement"))
end

function composed_reference_files!(record,c,spec,directory,forms; verify=false)
    discrete=any(interface_step_eligible(c.net.elements[n].element_model) for n in c.devices)
    for (label,h) in (discrete ? (("plain",nothing),("discrete",spec.time_step)) : (("plain",nothing),))
        refs=composed_reference(c,spec;time_step=h,forms=label=="discrete" ? forms : nothing)
        if label=="discrete"
            # Y uses simultaneous branch I and terminal V, so timing cancels.
            # Direct Z divides terminal V by the separately recorded drive.
            for (k,f) in enumerate(spec.frequencies)
                refs["direct_Z"][:,:,k] .*= injection_readout_factor(f,spec)
            end
        end
        for (target,reference) in refs
            path=joinpath(directory,scan_prefix(spec)*label*"_"*target*"_reference.tsv")
            ts=composed_target_spec(spec,c,target)
            if verify || isfile(path)
                stored=read_response(path,length(spec.axes),spec.frequencies)
                native_reference_check(ts,reference,stored)["passed"] || error("composed reference changed: $target/$label")
            else
                write_response(path,reference,spec.frequencies;quantity=ts.quantity)
            end
        end
    end
    return nothing
end

function composed_frozen_references(directory,spec,c,label)
    targets=["aggregate_Y","direct_Z",[string(n)*"_Y" for n in c.devices]...]
    return Dict(target=>read_response(joinpath(directory,scan_prefix(spec)*label*"_"*target*"_reference.tsv"),
        length(spec.axes),spec.frequencies) for target in targets)
end

function prepare_composed(id;directory=joinpath(ROOT,"data",id))
    entry=fixture(id);net=entry.factory();point=power_flow(net);c=l3_circuit(id,net)
    gate=composed_stability(c);gate["status"]=="passed" || error("composed stability gate failed: $gate")
    # Fresh preparation never adopts old runs, reference tables or proposal exports.
    ispath(directory) && error("fresh composed directory already exists: $directory")
    mkpath(directory);list=fixture_netlist(net,point);spec=l3_spec(id,list)
    groups=id=="L3-08" ? [spec,l3_spec(id,list;local_scan=true)] : [spec]
    allmodels=Pair{String,P.PSCADModel}[]
    for group in groups
        prefix=scan_prefix(group);check_recorder_sampling(group)
        # Full tier-A baseline; a separate unrun measurement template keeps
        # only V/I/drive recorders for every injected run. Electrical meters stay.
        models=prepare_scan_projects(directory,list,group,String[];prefix)
        measured=merge(group,(;recorder_scope="measurement"))
        append!(models,prepare_scan_projects(directory,list,measured,group.axes;prefix=prefix*"measurement_"))
        append!(models,prepare_scan_projects(directory,list,merge(measured,(;tone_peak_pu=group.tone_peak_pu/2,baseline_template=prefix*"measurement_baseline")),group.axes;
            prefix=prefix*"half_amplitude_"))
        step=composed_step_spec(group,1000.;local_scan=group.protocol=="composed_local")
        append!(models,prepare_scan_projects(directory,list,step,step.axes;prefix=step_prefix(step)))
        forms=exported_composed_passives(c,first(models).second.project_path,list)
        composed_reference_files!(nothing,c,group,directory,forms)
        append!(allmodels,models)
    end
    record=preparation_record(entry,gate,allmodels;directory)
    record["tier_c"]=scan_record(spec)
    record["aggregate_bases"]=Dict("power_MVA"=>spec.power_base_MVA,"voltage_kVpeak"=>spec.voltage_bases,"current_kApeak"=>spec.current_bases)
    individual_bases=Dict{String,Any}()
    for n in c.devices
        bases=device_bases(net.elements[n].element_model.elec)
        individual_bases[string(n)]=Dict("voltage_kVpeak"=>bases.ac_voltage,
            "current_kApeak"=>bases.ac_current,"power_MVA"=>bases.power)
    end
    record["individual_bases"]=individual_bases
    record["native_node_admission"]=Dict("source"=>"owner station measurement","duration_s"=>.01,
        "errors"=>0,"live_nodes"=>L3_NATIVE_NODES[id],"limit_exclusive"=>100,
        "scope"=>"proposal exports; every new measurement build checks its own live count")
    record["measurement_groups"]=Dict(g.protocol=>scan_record(g) for g in groups)
    record["qualification_reference"]=id=="L3-08" ? "composed_discrete_realization" : "plain_model"
    record["qualification_status"]="station_pending"
    record["fresh_generation"]="M9d stage A; no prior projects, references or native completions reused"
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
        if residual
            pm=pred[target];ph=predhalf[target]
            rm=matrix_change(a.matrix,pm;epsilon=.01);rh=matrix_change(b.matrix,ph;epsilon=.01)
            valid=raw["valid"]&&rm["passed"]&&rh["passed"]
            selected=residual_step_change(a.matrix[:,:,indices],b.matrix,pm[:,:,indices],ph;valid)
            reproduction=Dict("main"=>rm,"half"=>rh)
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
        if residual
            reproduction["main"]["passed"] || push!(reasons,"main_discrete_reproduction")
            reproduction["half"]["passed"] || push!(reasons,"half_step_discrete_reproduction")
        end
        witnesses[target]=Dict("status"=>status,"invalid_reasons"=>reasons,"amplitude"=>amplitude,"raw_step"=>raw,"selected_step"=>selected,
            "reproduction"=>reproduction,"step_reference"=>residual ? "composed_residual" : "raw")
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
            write_table(joinpath(output,"comparison_A.tsv"),rows)
            group["tier_a_status"]=all(rows.within_tolerance) ? "passed" : "failed"
        end
    end
    forms=exported_composed_passives(c,models["baseline"].project_path,list)
    composed_reference_files!(record,c,spec,directory,forms;verify=true)
    residual=any(interface_step_eligible(c.net.elements[n].element_model) for n in c.devices)
    qualifying=nothing
    for label in (residual ? ("plain","discrete") : ("plain",))
        refs=composed_frozen_references(directory,spec,c,label)
        dest=mkpath(joinpath(output,label))
        bands=local_scan ? [collect(1:20),collect(21:39)] : Vector{Int}[]
        comparison=composed_comparison(results,models,refs,dest,spec,c;resonance_groups=bands)
        group[label]=comparison.comparisons
        group["readout_checks"]=comparison.kcl
        group["invalid_reasons"]=Dict(target=>x["invalid_reasons"] for (target,x) in comparison.comparisons)
        write_manifest(directory,record)
        qualifying=comparison
    end
    if any(x["status"] in ("invalid_measurement","model_mismatch") for x in values(qualifying.comparisons))
        group["status"]=any(x["status"]=="model_mismatch" for x in values(qualifying.comparisons)) ? "model_mismatch" : "invalid_measurement"
        group["measurand_summary"]=Dict(target=>Dict("status"=>x["status"],"witness"=>"not_run",
            "invalid_reasons"=>x["invalid_reasons"])
            for (target,x) in qualifying.comparisons)
        write_manifest(directory,record)
        return group
    end
    # Persist selection before any witness run; retries use exactly this choice.
    chosen=get!(group,"selection",Dict("column"=>qualifying.selection.column,"frequency_Hz"=>qualifying.selection.frequency))
    column=chosen["column"];axis=spec.axes[column]
    step=composed_step_spec(spec,chosen["frequency_Hz"];local_scan)
    write_manifest(directory,record)
    halfspec=merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2,recorder_scope="measurement"))
    ampmodel=existing_model(record,prefix*"half_amplitude_"*axis,list,halfspec,directory)
    ampresult=execute_axis!(record,prefix*"half_amplitude_"*axis,ampmodel,directory,remote,deadline)
    stepmodels=prepare_scan_projects(directory,list,step,[axis];prefix=step_prefix(step))
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
        "status"=>group[label][target]["status"]=="invalid_measurement"||witnesses[target]["status"]=="invalid_measurement" ? "invalid_measurement" :
            group[label][target]["status"]=="passed"&&witnesses[target]["status"]=="passed" ? "passed" : "failed") for target in keys(witnesses))
    group["invalid_reasons"]=Dict(target=>x["invalid_reasons"] for (target,x) in group["measurand_summary"])
    statuses=[x["status"] for x in values(group["measurand_summary"])]
    group["status"]="invalid_measurement" in statuses ? "invalid_measurement" :
        all(==("passed"),statuses)&&group["tier_a_status"]=="passed" ? "passed" : "failed"
    write_manifest(directory,record)
    return group
end

function run_composed(id;remote=RemoteConfig(),directory=joinpath(ROOT,"data",id),deadline=time()+10800)
    time()<deadline || error("stage A station runtime budget exhausted")
    record=manifest_lists!(TOML.parsefile(joinpath(directory,"manifest.toml")));verify_inputs(directory,record)
    record["fixture_id"]==id || error("composed fixture mismatch")
    net=fixture(id).factory();point=power_flow(net);c=l3_circuit(id,net)
    gate=composed_stability(c);gate["status"]=="passed" || error("complete composed network failed admission")
    list=fixture_netlist(net,point)
    native_operating_point_check(list,joinpath(directory,"operating_point.tsv"))["passed"] || error("composed operating point changed")
    specs=id=="L3-08" ? [l3_spec(id,list),l3_spec(id,list;local_scan=true)] : [l3_spec(id,list)]
    for spec in specs
        scan_record(spec)==record["measurement_groups"][spec.protocol] || error("composed measurement definition changed")
    end
    record["status"]="running";started=time();pop!(record,"failure",nothing)
    try
        for spec in specs
            group=run_composed_group!(record,c,list,spec;directory,remote,deadline)
            group["status"]=="passed" || break
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

function prepare_m9d_a()
    return [prepare_composed(id) for id in M9D_A_IDS]
end


append!(REGISTRY,[(id=id,description=id=="L3-01" ? "TLC P-f/Q + P/Q-V shared bus" : "MMC with damped series-RC shunt",
    parent=id=="L3-01" ? "L2-01 + L2-03" : "L2-07 + explicit R/C",
    factory=()->l3_network(id),topology=id=="L3-01" ? "two DC-clamped TLCs — shared SCR-4 grid" : "DC-clamped MMC + series RC — SCR-8 grid",
    physics=["composed KCL","individual and aggregate admittance","direct closed-network impedance"],
    dissipativity="complete-network descriptor and native contour required",
    differences=["positive-delay native Padé versus exact transport retained; zero-delay uses composed discrete realization"],
    tiers=["A","C"],estimated_nodes=L3_NATIVE_NODES[id]) for id in M9D_A_IDS])
