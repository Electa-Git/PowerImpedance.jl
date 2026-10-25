# System measurements use the recorded shunt currents as independent inputs.
struct SystemPortVoltage
    name::String
    rows::Vector{Int}
    columns::Vector{Int}
end
struct SystemDeviceCurrent
    name::String
    element::Symbol
    dc::Bool
end
struct SystemBranchCurrent
    name::String
    element::Symbol
    port::Symbol
end
struct SystemACVoltage
    name::String
    element::Symbol
end
struct SystemDCVoltage
    name::String
    element::Symbol
    port::Symbol
end
const SystemMeasurand=Union{SystemPortVoltage,SystemDeviceCurrent,SystemBranchCurrent,SystemACVoltage,SystemDCVoltage}

# The measured AC ports can differ from individual converter terminals.
struct CompleteSystem
    net::NetworkBuilder.NetworkState
    devices::Vector{Symbol}
    grids::Vector{Symbol}
    nodes::Vector{Symbol}
    ports::Vector{Tuple{Symbol,Symbol}}
    dc_references::Dict{Symbol,Float64}
    measurands::Vector{SystemMeasurand}
end

system_ports(id)=id=="ieee14" ? [(:MMC1,:ac),(:MMC4,:ac)] : [(:c1,:ac),(:c2,:ac)]

function system_extra_currents(id, list)
    return [(e.name, t.port)
            for e in list.elements
            if e.model isa PowerImpedance.Transformer ||
               id in ("p2p_redesigned", "p2p_original") &&
               (e.model isa PowerImpedance.Overhead_line &&
                PowerImpedance.isac(e.ports.side1.domain) ||
                startswith(string(e.name), "Z_g")) for t in e.terminals]
end

function complete_system(id,net)
    devices=sort!([name for (name,
        e) in pairs(net.elements) if e isa Union{PowerImpedance.MMC,PowerImpedance.TLC}])
    ports=system_ports(id)
    extra=Set(system_extra_currents(id,fixture_netlist(net,nothing)))
    grids=sort!([name for name in keys(net.elements) if startswith(string(name),"Zg") || startswith(string(name),"Z_g")])
    c=composed_circuit(net,devices,grids,ports)
    outputs=SystemMeasurand[SystemPortVoltage("direct_Z",collect(1:4),collect(1:4))]
    for p in 1:2, q in 1:2
        push!(outputs,SystemPortVoltage("Z_p$(p)_p$q",collect(2p-1:2p),collect(2q-1:2q)))
    end
    for name in devices
        push!(outputs,SystemACVoltage("AC_V_"*string(name),name))
        push!(outputs,SystemDeviceCurrent("AC_I_"*string(name),name,false))
        push!(outputs,SystemDeviceCurrent("DC_I_"*string(name),name,true))
    end
    dc_nodes=Set{Symbol}()
    for (name,e) in sort!(collect(pairs(net.elements));by=first)
        e isa PowerImpedance.Source && continue
        if passive_dimension(e)==1 && !(name in devices)
            for port in (:side1, :side2)
                node=first(port_nets(net, name, port))
                if node != :gnd && !(node in dc_nodes)
                    push!(outputs,SystemDCVoltage("DC_V_"*string(name)*"_"*string(port),
                        name,port))
                    push!(dc_nodes,node)
                end
                push!(outputs,SystemBranchCurrent("DC_I_"*string(name)*"_"*string(port),
                    name,port))
                node in c.nodes && (c.dc_references[node]=2P.DC_REFERENCE_RESISTANCE)
            end
        elseif passive_dimension(e)==2 && !(name in devices)
            for port in (:side1, :side2)
                (name,port) in extra ||
                    any(first(port_nets(net, n, p))==first(port_nets(net, name,
                        port)) for (n,p) in ports) || continue
                push!(outputs,SystemBranchCurrent("AC_I_"*string(name)*"_"*string(port),
                    name,port))
            end
        end
    end
    # Separate source-clamped DC supplies still have measured V/I outputs.
    for name in devices
        node=only(port_nets(net, name, :dc))
        if !(node in dc_nodes)
            push!(outputs,SystemDCVoltage("DC_V_"*string(name),name,:dc));push!(dc_nodes,
                node)
        end
    end
    return CompleteSystem(net,devices,grids,c.nodes,ports,c.dc_references,outputs)
end

composed_targets(c::CompleteSystem)=[m.name for m in c.measurands]
system_measurand(c,target)=only(filter(m->m.name==target,c.measurands))
composed_score_columns(c::CompleteSystem,target,spec)=system_input_columns(system_measurand(c,target),spec)
system_input_columns(m,spec)=collect(eachindex(spec.axes))
system_input_columns(m::SystemPortVoltage,spec)=m.columns

function system_output_bases(m::SystemDeviceCurrent,c)
    b=device_bases(c.net.elements[m.element].elec)
    return m.dc ? [b.current_outputs[1]] : fill(b.ac_current,2)
end
system_output_bases(m::SystemACVoltage,
    c)=fill(device_bases(c.net.elements[m.element].elec).ac_voltage,2)
system_output_bases(m::SystemDCVoltage,
    c)=[device_bases(c.net.elements[first(c.devices)].elec).dc_voltage]
system_output_bases(m::SystemBranchCurrent,c)=fill(system_current_base(c,m),
    passive_dimension(c.net.elements[m.element]))
function system_current_base(c,m)
    if c.net.elements[m.element] isa PowerImpedance.Transformer
        transformer=c.net.elements[m.element]
        phase_rms_V=m.port==:side1 ? transformer.V₁ᵒ : transformer.V₂ᵒ
        power=device_bases(c.net.elements[first(c.devices)].elec).power
        return 2power/(3phase_rms_V/1000*sqrt(2))
    end
    for name in c.devices
        e=c.net.elements[name];b=device_bases(e.elec)
        node=first(port_nets(c.net, m.element, m.port))
        node==only(port_nets(c.net, name, :dc)) && return b.current_outputs[1]
        node==first(port_nets(c.net, name, :ac)) && return b.ac_current
    end
    b=device_bases(c.net.elements[first(c.devices)].elec)
    return passive_dimension(c.net.elements[m.element])==1 ?
        b.current_outputs[1] : b.ac_current
end

function composed_target_spec(spec,c::CompleteSystem,target)
    m=system_measurand(c,target)
    bases=m isa SystemPortVoltage ? spec.voltage_bases[m.rows] : system_output_bases(m,c)
    if m isa SystemBranchCurrent && passive_dimension(c.net.elements[m.element])==2
        node=first(port_nets(c.net, m.element, m.port))
        port=findfirst(p->first(port_nets(c.net, p...))==node,c.ports)
        port===nothing || (bases=spec.current_bases[(2port-1):2port])
    end
    return merge(spec,(;quantity=m isa Union{SystemPortVoltage,SystemACVoltage,SystemDCVoltage} ? "Z" : "T",
        response_output_bases=bases,dc_clamped=false))
end
composed_reference_rows(c::CompleteSystem,spec,target)=length(composed_target_spec(spec,c,target).response_output_bases)
function composed_score_indices(c::CompleteSystem,target,spec)
    return collect(1:composed_reference_rows(c,spec,target))
end

function system_response(m::SystemPortVoltage,c,s,functions,forms,v)
    return v[m.rows,:]
end
function system_response(m::SystemDeviceCurrent,c,s,functions,forms,v)
    b=device_bases(c.net.elements[m.element].elec)
    rows=m.dc ? [1] : collect(b.ac_indices)
    return (functions[m.element](s)*component_incidence(c,m.element)'*v)[rows,:]
end
function system_response(m::SystemBranchCurrent,c,s,functions,forms,v)
    e=c.net.elements[m.element];n=passive_dimension(e)
    yy=forms!==nothing && haskey(forms,m.element) ? composed_passive_y(e,
        forms[m.element],s) : physical_y(e,ComplexF64(s))
    return (yy*component_incidence(c,m.element)'*v)[m.port == :side1 ? (1:n) : (n+1:2n),:]
end
function system_response(m::SystemACVoltage,c,s,functions,forms,v)
    b=device_bases(c.net.elements[m.element].elec)
    return (component_incidence(c,m.element)'*v)[b.ac_indices,:]
end
function system_response(m::SystemDCVoltage,c,s,functions,forms,v)
    h=composed_incidence(c, port_nets(c.net, m.element, m.port))
    return h'*v
end

function composed_reference(c::CompleteSystem,spec;time_step=nothing,forms=nothing)
    functions=composed_device_functions(c;time_step)
    values=Dict(m.name=>Matrix{ComplexF64}[] for m in c.measurands)
    drive=zeros(ComplexF64,length(c.nodes),length(spec.axes));drive[1:length(spec.axes),:]=I(length(spec.axes))
    for f in spec.frequencies
        s=ComplexF64(im*2π*f);v=composed_nodal(c,s,functions;forms)\drive
        for m in c.measurands
            push!(values[m.name],system_response(m,c,s,functions,forms,v))
        end
    end
    return Dict(name=>cat(rows...;dims=3) for (name,rows) in values)
end

function system_current_samples(result, model, element, port)
    probe=only(filter(
        p->p.kind==:current && p.element==string(element) &&
           p.port==port,
        model.probes.channels))
    probe.orientation in (:into, :out) || error("missing system current orientation")
    sign=probe.orientation==:into ? 1 : -1
    return probe.dim==1 ? reshape(sign.*result.channels[probe.name],:,1) : sign.*fixed_dq(result.time,probe_samples(result,probe))
end
system_samples(m::SystemPortVoltage,result,model,c,voltage)=voltage[:,m.rows]
function system_samples(m::SystemDeviceCurrent,result,model,c,voltage)
    b=device_bases(c.net.elements[m.element].elec)
    return system_current_samples(result,model,m.element,m.dc ? :dc : :ac)
end
system_samples(m::SystemBranchCurrent,result,model,c,
    voltage)=system_current_samples(result,model,m.element,m.port)
function system_samples(m::SystemACVoltage,result,model,c,voltage)
    bus=port_probe(model.netlist,m.element,:ac).name
    probe=only(filter(p->p.kind==:voltage && p.bus==bus,model.probes.channels))
    return fixed_dq(result.time,probe_samples(result,probe))
end
function system_samples(m::SystemDCVoltage, result, model, c, voltage)
    bus=port_probe(model.netlist, m.element, m.port).name
    poles=[only(filter(p->p.kind==:voltage && p.bus==bus && p.pole==pole,
        model.probes.channels))
           for pole in ("P", "N")]
    return reshape(result.channels[poles[1].name]-result.channels[poles[2].name], :, 1)
end

function composed_samples(result,model,spec,c::CompleteSystem)
    voltages=Matrix{Float64}[];drives=Matrix{Float64}[];branches=Dict{String,Matrix{Float64}}()
    for (port,bus) in enumerate(spec.buses)
        vp=only(filter(p->p.kind==:voltage && p.bus==bus.name,model.probes.channels))
        push!(voltages,fixed_dq(result.time,probe_samples(result,vp)))
        ip=only(filter(p->p.kind==:injection_current && p.bus==bus.name,model.probes.channels))
        push!(drives, fixed_dq(result.time, injection_samples(result, ip)))
        for p in filter(p->p.kind==:current && p.bus==bus.name, model.probes.channels)
            port = p.port
            key = "$port:$(p.element):$port"
            branches[key] = system_current_samples(result, model, Symbol(p.element), port)
        end
    end
    voltage=reduce(hcat,voltages);drive=reduce(hcat,drives)
    outputs=Dict(m.name=>system_samples(m,result,model,c,voltage) for m in c.measurands)
    clamps=Dict(string(n)=>vec(system_samples(SystemDCVoltage("",n,:dc),result,model,c,
        voltage)) for n in c.devices)
    source_clamps=Dict{String,Matrix{Float64}}()
    for e in model.netlist.elements
        e.model isa PowerImpedance.Source && PowerImpedance.isac(first(e.ports).domain) ||
            continue
        bus=port_probe(model.netlist, e.name, :ac)
        probe=only(filter(p->p.kind==:voltage && p.bus==bus.name, model.probes.channels))
        source_clamps[string(e.name)]=fixed_dq(result.time, probe_samples(result, probe)) ./
                                      inputvalues(e.model).v
    end
    return (;voltage,current=zeros(size(voltage)),drive,drive_base=spec.current_bases,outputs,branches,clamps,source_clamps,
        device_voltages=Dict{String,Matrix{Float64}}())
end

function composed_predicted_columns(c::CompleteSystem,spec,column,forms)
    refs=composed_reference(c,spec;time_step=spec.time_step,forms)
    return Dict(target=>cat([reshape(injection_readout_factor(f,spec).*reference[:,column,k].*
            (spec.current_bases[column]./composed_target_spec(spec,c,target).response_output_bases),:,1)
            for (k,f) in enumerate(spec.frequencies)]...;dims=3) for (target,reference) in refs)
end

function exported_composed_passives(c::CompleteSystem,project,list)
    text=read(project,String);forms=Dict{Symbol,P.RLCForm}()
    for (name,e) in pairs(c.net.elements)
        e isa PowerImpedance.Impedance || continue
        original=P.identify_rlc(e;name).form
        item=only(filter(x->x.name==name,list.elements))
        fields=map(((:R,"resistor","R","ohm"),(:L,"inductor","L","H"),(:C,"capacitor","C","uF"))) do (field,kind,key,unit)
            value=getproperty(original,field)
            value===nothing && return nothing
            parsed=exported_passive(text,item.pscad*"_"*key,kind,key,unit)
            field==:C && (parsed*=1e-6)
            isapprox(parsed,value;rtol=1e-8) || error("exported passive changed: $name/$field")
            return parsed
        end
        forms[name]=P.RLCForm(original.topology,fields...)
    end
    saved=P.read_project_summary(project).settings
    settings=P.SimulationSettings(time_step=parse(Float64,saved["time_step"])*1e-6,
        sample_step=parse(Float64,saved["sample_step"])*1e-6)
    plan=P.build_plan(list;name="system_check",settings)
    for row in plan.lines
        block=only(m.match for m in eachmatch(r"<Definition\b[^>]*>.*?</Definition>"s,text)
            if occursin("name=\"$(row.name)\"",first(split(m.match,'>'))))
        for (key,value) in [row.ground;row.frephase;row.outdisp]
            occursin("<param name=\"$key\" value=\"$value\"/>",block) || error("exported line setting changed: $(row.name)/$key")
        end
        if row isa P.CableDefinitionPlan
            for component in row.cables
                number=only(value for (key,value) in component.params if key=="CABNUM")
                cable=only(m.match for m in eachmatch(r"<User\b[^>]*>.*?</User>"s,block)
                    if occursin("<param name=\"CABNUM\" value=\"$number\"/>",m.match))
                for (key,value) in component.params
                    occursin("<param name=\"$key\" value=\"$value\"/>",cable) || error("exported cable changed: $(row.name)/$number/$key")
                end
            end
        else
            for (key,value) in row.tower
                occursin("<param name=\"$key\" value=\"$value\"/>",block) || error("exported tower changed: $(row.name)/$key")
            end
        end
    end
    for wrapper in plan.wrappers
        block=only(m.match for m in eachmatch(r"<Wire\b[^>]*classid=\"(?:Cable|TLine)\"[^>]*>.*?</Wire>"s,text)
            if endswith(match(r"\bdefn=\"([^\"]+)\"",first(split(m.match,'>')))[1],":"*wrapper.row))
        for (key,value) in wrapper.params
            occursin("<param name=\"$key\" value=\"$value\"/>",block) || error("exported line length changed: $(wrapper.row)/$key")
        end
    end
    for (node,resistance) in c.dc_references
        bus=only(filter(b->node in b.nets,list.buses))
        poles=[exported_passive(text,bus.name*"_reference_"*pole*"_R","resistor","R","ohm") for pole in ("P","N")]
        sum(poles)==resistance || error("exported DC reference changed at $node")
    end
    return forms
end

function composed_reference_transport!(refs,c::CompleteSystem,spec,label)
    for (k,f) in enumerate(spec.frequencies)
        rotation=injection_readout_transport(f,spec)
        transport=zeros(ComplexF64,length(spec.axes),length(spec.axes))
        for port in eachindex(c.ports)
            ix=(2port-1):2port;transport[ix,ix]=rotation
        end
        for reference in values(refs)
            reference[:,:,k]=reference[:,:,k]*transport
        end
    end
    return refs
end
