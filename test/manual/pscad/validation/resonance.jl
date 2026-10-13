# Owner-approved frequency/half-power-width comparison. Never infer a resolved
# native resonance from a Julia curve alone, or from an unbracketed sparse peak.
function half_power_resonance(frequencies, response; quantity = "Z")
    length(frequencies)==length(response) >= 5 || throw(ArgumentError("resonance dimensions"))
    issorted(frequencies) && all(>(0),diff(frequencies)) || throw(ArgumentError("ordered unique frequencies required"))
    all(isfinite,response) && all(>(0),response) || return Dict{String,Any}("resolved"=>false,"reason"=>"nonpositive or nonfinite magnitude")
    power = quantity=="Z" ? response.^2 : quantity=="Y" ? inv.(response.^2) : throw(ArgumentError("Y or Z required"))
    k = argmax(power)
    1<k<length(power) || return Dict{String,Any}("resolved"=>false,"reason"=>"peak at grid boundary")
    x = frequencies[k-1:k+1] .- frequencies[k]
    coefficients = hcat(ones(3),x,x.^2) \ power[k-1:k+1]
    offset = coefficients[3]<0 ? -coefficients[2]/(2coefficients[3]) : 0.0
    offset = clamp(offset,x[1],x[3]); centre = frequencies[k]+offset
    level = (coefficients[1]+coefficients[2]*offset+coefficients[3]*offset^2)/2
    left=findlast(<=(level),power[1:k-1]);right_local=findfirst(<=(level),power[k+1:end])
    if left!==nothing && right_local!==nothing
        right=k+right_local
        crossing(i,j)=frequencies[i]+(frequencies[j]-frequencies[i])*(level-power[i])/(power[j]-power[i])
        low=crossing(left,left+1);high=crossing(right-1,right);width=high-low
        interval=maximum(diff(frequencies[left:right]))
        resolved = width >= 6interval && count(f->low<=f<=high,frequencies)>=5
        return Dict{String,Any}("resolved"=>resolved,"reason"=>resolved ? "bracketed half-power curve" : "bandwidth grid too sparse",
            "centre_Hz"=>centre,"low_Hz"=>low,"high_Hz"=>high,"width_Hz"=>width,"grid_interval_Hz"=>interval)
    end
    return Dict{String,Any}("resolved"=>false,"reason"=>"half-power crossing absent")
end

function resonance_qualification(frequencies, measured, reference; quantity="Z")
    magnitudes(m)=[norm(m[:,:,k]) for k in axes(m,3)]
    julia=half_power_resonance(frequencies,magnitudes(reference);quantity)
    native=half_power_resonance(frequencies,magnitudes(measured);quantity)
    resolved=julia["resolved"] && native["resolved"]
    result=Dict{String,Any}("resolved"=>resolved,"Julia"=>julia,"PSCAD"=>native,
        "magnitude"=>"local port-matrix Frobenius norm; reciprocal magnitude for a Y dip")
    if resolved
        limit=max(.01julia["centre_Hz"],julia["grid_interval_Hz"],native["grid_interval_Hz"])
        error=abs(native["centre_Hz"]-julia["centre_Hz"])
        width_error=abs(native["width_Hz"]-julia["width_Hz"])/julia["width_Hz"]
        merge!(result,Dict("frequency_error_Hz"=>error,"frequency_limit_Hz"=>limit,
            "width_relative_error"=>width_error,"width_limit"=>.10,"passed"=>error<=limit && width_error<=.10))
    else
        result["passed"]=false
    end
    return result
end

function resonance_judged_rows(rows, qualification; valid=true, model_mismatch="")
    resolved=qualification["resolved"]
    return [begin
        inside=resolved && any(b["low_Hz"]<=r.frequency_Hz<=b["high_Hz"] for b in (qualification["Julia"],qualification["PSCAD"]))
        mismatch=isempty(model_mismatch) ? r.model_mismatch : model_mismatch
        measured_valid=valid && r.status!="invalid_measurement"
        passed=(inside ? qualification["passed"] : r.within_tolerance) && measured_valid && isempty(mismatch)
        status=!isempty(mismatch) ? "model_mismatch" : !measured_valid ? "invalid_measurement" : passed ? "passed" : "failed"
        merge(r,(;comparison_rule=inside ? "resonance_frequency_width" : "complex",
            within_tolerance=passed,status,model_mismatch=mismatch))
    end for r in rows]
end

function resonance_spec(net,list,base)
    frequencies=setdiff(collect(312.:.25:322.),base.frequencies)
    port=2;indices=4:6;n=length(frequencies)
    spec=merge(base,(;protocol="abc_resonance",buses=[base.buses[port]],currents=[("injection_1","1")],
        axes=["p1_a","p1_b","p1_c"],voltage_bases=base.voltage_bases[indices],current_bases=base.current_bases[indices],
        frequencies,phases=[-π*k*(k-1)/n for k in 1:n],window_duration=4.,window_starts=(2.,6.),simulation_time=10.,
        estimated_station_seconds=4500))
    spec=merge(spec,(;sample_step=band_sample_step(spec)))
    twin=phase_twin(net,list)
    reference=cat((phase_network_z(twin,spec.buses,f;floating_stars=true) for f in frequencies)...;dims=3)
    bound=maximum(sum(abs.(scale_response(reference,spec));dims=3))
    return merge(spec,(;tone_peak_pu=min(base.tone_peak_pu,.002/max(bound,1.)))),reference
end

function prepare_resonance_fixture(;directory=joinpath(ROOT,"data","L1-08"))
    record=manifest_lists!(TOML.parsefile(joinpath(directory,"manifest.toml")))
    history=mkpath(joinpath(directory,"history","resonance-"*Dates.format(now(UTC),"yyyymmddTHHMMSS")))
    cp(joinpath(directory,"manifest.toml"),joinpath(history,"manifest.toml"))
    net=fixture("L1-08").factory();list=P.netlist(net,power_flow(net))
    base,_=applicable_scan("L1-08",net,list;definition=record["tier_c"])
    spec,reference=resonance_spec(net,list,base)
    scan_plan(list,spec,"baseline") # Validate before replacing prepared artifacts.
    previous = get(record,"resonance_scan",Dict())
    if !isempty(previous) && get(previous,"sample_step",nothing) != spec.sample_step
        # Measurement-only revision: archive the old projects/manifest, keep
        # native runs at their original hashes, and leave base-band files alone.
        for project in record["projects"]
            startswith(project["axis"],scan_prefix(spec)) || continue
            old=joinpath(directory,dirname(project["path"]))
            isdir(old) && mv(old,joinpath(history,basename(old)))
        end
        filter!(project -> !startswith(project["axis"],scan_prefix(spec)),record["projects"])
        pop!(record,"resonance_evaluation",nothing)
    end
    models=prepare_scan_projects(directory,list,spec,spec.axes;prefix=scan_prefix(spec))
    axis="p1_a"
    append!(models,prepare_scan_projects(directory,list,merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2)),[axis];prefix=scan_prefix(spec)*"half_amplitude_"))
    step=merge(spec,(;time_step=spec.time_step/2))
    append!(models,prepare_scan_projects(directory,list,step,[axis];prefix=scan_prefix(spec)*"half_step__"))
    for (key,model) in models;record_project!(record,key,model,directory);end
    write_response(joinpath(directory,reference_filename(spec)),reference,spec.frequencies;quantity=spec.quantity)
    record["resonance_scan"]=merge(scan_record(spec),Dict("bus"=>"Bus5","witness_axis"=>axis,
        "frequency_spacing_Hz"=>.25,"frequency_band_Hz"=>[312.,322.],"existing_frequency_reused_Hz"=>[316.],
        "resolution_gate"=>"both half-power crossings and at least six grid intervals per width; five points inside",
        "rule"=>"inside either resolved half-power band: centre <= max(1 percent of Julia centre, one grid interval), width <=10 percent; outside: unchanged complex rule"))
    record["resonance_scan"]["output"] = Dict("scalar_channels"=>6,"files_per_run"=>1,
        "rows_per_run"=>round(Int,spec.simulation_time/spec.sample_step)+1,
        "rows_per_window"=>round(Int,spec.window_duration/spec.sample_step),
        "estimated_OUT_bytes_per_run"=>(round(Int,spec.simulation_time/spec.sample_step)+1)*169+74,
        "byte_estimate_provenance"=>"retained PSCAD OUT: 24-byte numeric columns, first 23 bytes, CRLF, 74-byte project header; six scalar signals plus time",
        "selection"=>"Bus5 a/b/c voltage and outward shunt a/b/c current only; remove unused master:pgb instances from Main; keep all electrical meters/wires",
        "sampling"=>"largest integration-grid multiple dividing all windows and run duration with >=40 samples per highest measured sideband")
    record["resonance_scan"]["export_commit"] = readchomp(`git -C $REPOSITORY rev-parse HEAD`)
    record["resonance_scan"]["export_source_files"] = source_record()
    record["source_files"]=source_record()
    pop!(record,"failure",nothing)
    record["status"]="resonance_station_pending"
    write_manifest(directory,record)
    return record
end

function run_resonance!(record,net,list,base;directory,remote,deadline)
    spec,reference=resonance_spec(net,list,base)
    prepared=record["resonance_scan"]
    spec=merge(spec,(;tone_peak_pu=Float64(prepared["tone_peak_pu"])))
    scan_record(spec)==Dict(key=>prepared[key] for key in keys(scan_record(spec))) || error("resonance scan definition changed")
    stored=read_response(joinpath(directory,reference_filename(spec)),3,spec.frequencies)
    isapprox(reference,stored;rtol=1e-12,atol=1e-14) || error("resonance reference changed")
    results=Dict{String,P.PSCADResult}();models=Dict{String,P.PSCADModel}()
    for axis in ["baseline";spec.axes]
        key=scan_prefix(spec)*axis;model=existing_model(record,key,list,spec,directory)
        models[axis]=model;results[axis]=execute_axis!(record,key,model,directory,remote,deadline)
    end
    output=mkpath(joinpath(directory,"analysis",spec.protocol))
    quality=compare_frequency_runs(results,models,reference,output;spec)
    axis=prepared["witness_axis"];column=only(findall(==(axis),spec.axes))
    base_column,base_quality=single_response(results[axis],results["baseline"],models[axis],spec,column)
    half_spec=merge(spec,(;tone_peak_pu=spec.tone_peak_pu/2));half_key=scan_prefix(spec)*"half_amplitude_"*axis
    half_model=existing_model(record,half_key,list,half_spec,directory)
    half_run=execute_axis!(record,half_key,half_model,directory,remote,deadline)
    half_column,half_quality=single_response(half_run,results["baseline"],half_model,half_spec,column)
    amp=matrix_change(half_column,base_column;epsilon=.02);amp["passed"] &= base_quality["valid"] && half_quality["valid"]
    step_spec=merge(spec,(;time_step=spec.time_step/2));prefix=scan_prefix(spec)*"half_step__"
    step_model=existing_model(record,prefix*axis,list,step_spec,directory;prefix)
    step_baseline_model=existing_model(record,prefix*"baseline",list,step_spec,directory;prefix)
    step_baseline=execute_axis!(record,prefix*"baseline",step_baseline_model,directory,remote,deadline)
    step_run=execute_axis!(record,prefix*axis,step_model,directory,remote,deadline)
    step_column,step_quality=single_response(step_run,step_baseline,step_model,step_spec,column)
    step=matrix_change(step_column,base_column;epsilon=.01);step["passed"] &= step_quality["valid"]
    write_table(joinpath(output,"comparison_half_amplitude.tsv"),refinement_rows(spec.frequencies,half_column,base_column;limit=.02,valid=half_quality["valid"]))
    write_table(joinpath(output,"comparison_half_step.tsv"),refinement_rows(spec.frequencies,step_column,base_column;limit=.01,valid=step_quality["valid"]))
    fine=read_response(joinpath(output,"measured_ohm.tsv"),3,spec.frequencies)
    old=read_response(joinpath(directory,"analysis",base.protocol,"measured_ohm.tsv"),6,base.frequencies)
    old_reference=read_response(joinpath(directory,reference_filename(base)),6,base.frequencies)
    frequencies=sort([spec.frequencies;316.]);old_k=only(findall(==(316.),base.frequencies))
    measured=cat((f==316. ? old[4:6,4:6,old_k] : fine[:,:,only(findall(==(f),spec.frequencies))] for f in frequencies)...;dims=3)
    expected=cat((f==316. ? old_reference[4:6,4:6,old_k] : reference[:,:,only(findall(==(f),spec.frequencies))] for f in frequencies)...;dims=3)
    rule=resonance_qualification(frequencies,measured,expected)
    valid=quality["valid"] && record["tier_c_result"]["valid"]
    fine_rows=comparison_rows(frequencies,scale_response(measured,spec),scale_response(expected,spec);valid)
    fine_rows=resonance_judged_rows(fine_rows,rule;valid)
    write_table(joinpath(output,"comparison_C_qualified.tsv"),fine_rows)
    old_rows=response_rows(base,scale_response(old,base),scale_response(old_reference,base);valid=record["tier_c_result"]["valid"])
    rows=[r.row>3 && r.column>3 ? only(resonance_judged_rows([r],rule;valid)) : merge(r,(;comparison_rule="complex")) for r in old_rows]
    write_table(joinpath(directory,"analysis",base.protocol,"comparison_C_qualified.tsv"),rows)
    passed=rule["resolved"] && all(r.within_tolerance for r in fine_rows) && all(r.within_tolerance for r in rows)
    record["resonance_evaluation"]=Dict("qualification"=>rule,"measurement_quality"=>quality,"amplitude_refinement"=>amp,
        "step_refinement"=>step,"status"=>passed ? "passed" : "failed",
        "base_complex_result"=>deepcopy(record["tier_c_result"]),"frequency_points_Hz"=>frequencies)
    record["tier_c_result"] = merge(record["tier_c_result"], Dict("status"=>
        !valid ? "invalid_measurement" : passed ? "passed" : "failed",
        "resonance_resolved"=>rule["resolved"], "resonance_rule_applied"=>rule["resolved"]))
    record["status"]=passed && amp["passed"] && step["passed"] && record["tier_a_status"]=="passed" &&
        record["amplitude_refinement"]["passed"] && record["step_refinement"]["passed"] ? "passed" : "failed"
    write_manifest(directory,record)
    return record
end
