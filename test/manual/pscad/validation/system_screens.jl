# Offline system diagnostics record the source hash and line-model choice for every
# result. Native node counts and PSCAD validation require separate runs.
function system_circuit(net)
    devices=sort!([name for (name,e) in pairs(net.elements) if
        e isa Union{PowerImpedance.MMC,PowerImpedance.TLC}])
    ports=[(name, device_bases(net.elements[name].elec,
        net.elements[name].bases).ac_port) for name in devices]
    grids=sort!([name for (name,e) in pairs(net.elements) if startswith(string(name),"Zg")])
    c=composed_circuit(net,devices,grids,ports)
    for (name,e) in pairs(net.elements)
        e isa Union{PowerImpedance.Overhead_line,PowerImpedance.Cable} || continue
        passive_dimension(e)==1 || continue
        for node in component_nets(net, name)
            node in c.nodes && (c.dc_references[node]=2P.DC_REFERENCE_RESISTANCE)
        end
    end
    return c
end

# Positive-sequence AC pi sections at 50 Hz and differential DC pi sections at
# 1 Hz provide seeds only. Final residuals and contours use native get_y on the
# entire distributed network. No seed approximation is exported.
function system_line_seeds(c)
    elements=deepcopy(c.net.elements)
    topology=fixture_topology(c.net)
    for name in sort!(collect(keys(c.net.elements)))
        e=c.net.elements[name];m=e
        m isa Union{PowerImpedance.Overhead_line,PowerImpedance.Cable} || continue
        ac=passive_dimension(e)==2;ω=ac ? 2π*50 : 2π
        z,y=PowerImpedance.eval_parameters(m,ComplexF64(im*ω))
        q=ac ? ComplexF64[1,cis(-2π/3),cis(2π/3)] : ComplexF64[1,-1]
        zz=dot(q,z*q)*m.length/(ac ? 3 : 1)
        yy=dot(q,y*q)*m.length/(ac ? 3 : 4)
        r=real(zz);l=imag(zz)/ω;cap=imag(yy)/(2ω)
        r>0 && l>0 && cap>0 || error("nonphysical line seed for $name")
        branch=impedance(z=s->r+l*s,conductors=ac ? 3 : 1)
        elements=merge(elements,(;name=>branch))
        for port in (:side1,:side2)
            shunt=impedance(z=s->inv(cap*s),conductors=ac ? 3 : 1)
            capname=Symbol(name,"_seed_cap_",port)
            elements=merge(elements,(;capname=>shunt))
            row=first(filter(row->row.component==name&&row.port==port,
                c.net.topology.connections))
            bus=ac ? Symbol(chop(string(row.net))) : row.net
            domain=ac ? ACDQ : DC_CM
            append!(topology,[
                NetworkBuilder.Bus(bus;ports=((capname,:side1),),domain),
                NetworkBuilder.Bus(:gnd;ports=((capname,:side2),),domain)])
        end
    end
    net=NetworkBuilder.define(elements,topology;options=c.net.options)
    seeds=system_taylor_seeds(c)
    if !any(e isa PowerImpedance.Transformer for (name,e) in pairs(net.elements))
        lumped=composed_circuit(net,c.devices,c.grids,c.ports)
        append!(seeds,composed_descriptor(merge(lumped,(;dc_references=c.dc_references))).poles)
    end
    return seeds
end

function system_root_search(c,functions,initial)
    selected=copy(initial);tracks=Tuple{ComplexF64,Float64}[];errors=String[]
    function track(seed)
        try
            push!(tracks,composed_refine_root(c,functions,seed));push!(errors,"")
        catch failure
            failure isa InterruptException && rethrow()
            push!(tracks,(ComplexF64(seed),Inf));push!(errors,sprint(showerror,failure))
        end
    end
    foreach(track,initial)
    # A 50 Hz nominal frame separates opposite circular regions by about 100 Hz. These
    # offsets give initial root guesses, without an assumed modal identity.
    omega=2c.net.elements[first(c.devices)].bases.omega
    growing=unique([z for (z,residual) in tracks if real(z)>0 && imag(z)>0 && residual<1e-6])
    partners=[z+im*direction*omega for z in growing for direction in (-1,1)]
    append!(selected,partners);foreach(track,partners)
    return selected,tracks,errors
end

function system_stability(c; checkpoint=nothing, analysis_scope="post-line-fix")
    functions=composed_device_functions(c)
    seeds=system_line_seeds(c)
    initial=filter(z->real(z)>-1500,seeds)
    selected,tracks,track_errors=system_root_search(c,functions,initial)
    located=filter(x->x[2]<1e-6,tracks)
    sort!(located;by=x->real(x[1]),rev=true)
    # Keep converged tracks, including duplicates, so seed coverage is explicit.
    gate=Dict{String,Any}(
        "analysis_scope"=>analysis_scope, "status"=>"incomplete",
        "method"=>"complete-network native distributed finite contours and locally located roots",
        "seed_count"=>length(seeds)+length(selected)-length(initial),"selected_seed_count"=>length(selected),"native_taylor_seeded"=>true,
        "unresolved_seed_count"=>length(tracks)-length(located),
        "poles_real_per_s"=>[real(x[1]) for x in located],
        "poles_imag_rad_per_s"=>[imag(x[1]) for x in located],
        "poles_frequency_Hz"=>[abs(imag(x[1]))/(2π) for x in located],
        "root_residuals"=>[x[2] for x in located],
        "seed_real_per_s"=>real.(selected),"seed_imag_rad_per_s"=>imag.(selected),
        "track_real_per_s"=>[real(x[1]) for x in tracks],
        "track_imag_rad_per_s"=>[imag(x[1]) for x in tracks],
        "track_residuals"=>[x[2] for x in tracks],"track_errors"=>track_errors,
        "root_scope"=>"finite contours through 1 MHz and locally located roots only; distributed infinite spectrum unenumerated; no infinite-frequency proof, as in two_mmc_dc_cable",
        "root_search"=>"native Newton refinement within max(1,abs(seed)) of pi and local native Taylor seeds with Re > -1500/s, followed by nominal-frame circular offsets; unresolved tracks remain unresolved",
        "contours"=>Dict{String,Any}[])
    isempty(located) || (gate["most_positive_located_real_per_s"]=real(first(located)[1]))
    checkpoint===nothing || open(io->TOML.print(io,gate;sorted=true),checkpoint,"w")
    open_rhp=sum(count(z->real(z)>1e-6,
        eigvals(c.net.elements[n].cache.A)) for n in c.devices)
    gate["open_RHP_count"]=open_rhp
    for fs in (exp10.(range(-2,5;length=6001)),exp10.(range(-6,6;length=12001)))
        values=ComplexF64[];margin=Inf
        for f in [0.;fs]
            s=1e-6+im*2π*f
            ret=try
                I+composed_nodal(c,s,functions;which=:passive)\composed_nodal(c,s,functions;which=:active)
            catch failure
                gate["contour_error_frequency_Hz"]=f
                gate["contour_error"]=sprint(showerror,failure)
                checkpoint===nothing || open(io->TOML.print(io,gate;sorted=true),checkpoint,"w")
                rethrow()
            end
            all(isfinite,ret) || error("nonfinite native return difference at $f Hz")
            push!(values,det(ret));margin=min(margin,minimum(svdvals(ret)))
        end
        contour=[conj.(reverse(values[2:end]));values]
        increments=[angle(contour[mod1(j+1,length(contour))]/contour[j]) for j in eachindex(contour)]
        turns=sum(increments)/(2π);net=-round(Int,turns)
        push!(gate["contours"],Dict("frequency_count"=>length(fs),"frequency_band_Hz"=>[first(fs),last(fs)],
            "nyquist_net"=>net,"closed_RHP_count"=>net+open_rhp,"turns"=>turns,
            "max_contour_phase_increment_rad"=>maximum(abs,increments),"return_difference_min"=>margin))
        checkpoint===nothing || open(io->TOML.print(io,gate;sorted=true),checkpoint,"w")
    end
    return system_refine_stability(c,gate;checkpoint)
end

# Both nodal and all-device-port Schur conditioning are sampled, not maximized over the
# continuum. Equal 380 kV AC bases leave cond unchanged under common SI-to-pu scaling.
# Mixed AC/DC nodal cond remains in SI.
function system_conditioning(c;frequencies=sort!(unique([exp10.(range(0,3;length=3001));
            filter(!=(50.),passive_settings().frequencies)])), analysis_scope="post-line-fix",
        measurement_ports=[[p] for p in c.ports])
    functions=composed_device_functions(c)
    rows=NamedTuple[]
    measurements=[Dict{String,Any}("ports"=>[string(n)*":"*string(side) for (n,side) in ports],
        "dimension"=>2length(ports),"sampled_condition_peak"=>0.,"peak_frequency_Hz"=>0.) for ports in measurement_ports]
    peak_directions=Dict{String,Any}()
    peak_condition=0.
    for f in frequencies
        full=composed_nodal(c,ComplexF64(im*2π*f),functions)
        reduced=composed_reduce(c,full)
        if cond(reduced)>peak_condition
            peak_condition=cond(reduced)
            decomposition=svd(reduced)
            peak_directions=Dict("singular_values_S"=>decomposition.S,
                "voltage_min_direction_port_weights"=>[sum(abs2,decomposition.V[2j-1:2j,end]) for j in eachindex(c.ports)],
                "current_min_direction_port_weights"=>[sum(abs2,decomposition.U[2j-1:2j,end]) for j in eachindex(c.ports)])
        end
        for (ports,record) in zip(measurement_ports,measurements)
            selected=reduce(vcat,[collect(2only(findall(==(p),c.ports))-1:2only(findall(==(p),c.ports))) for p in ports])
            internal=setdiff(collect(axes(reduced,1)),selected)
            local_y=isempty(internal) ? reduced[selected,selected] :
                reduced[selected,selected]-reduced[selected,internal]*(reduced[internal,internal]\reduced[internal,selected])
            condition=cond(local_y)
            if condition>record["sampled_condition_peak"]
                record["sampled_condition_peak"]=condition
                record["peak_frequency_Hz"]=f
            end
        end
        push!(rows,(frequency_Hz=f,nodal_condition_SI=cond(full),port_condition=cond(reduced),
            nodal_sigma_min_S=minimum(svdvals(full)),port_sigma_min_S=minimum(svdvals(reduced))))
    end
    peak=rows[argmax(getproperty.(rows,:port_condition))]
    return rows,Dict("analysis_scope"=>analysis_scope,"frequency_count"=>length(frequencies),
        "band_Hz"=>[first(frequencies),last(frequencies)],"port_dimension"=>2length(c.ports),
        "ports"=>[string(name)*":"*string(side) for (name,side) in c.ports],
        "measurement_port_sets"=>measurements,"peak_singular_directions"=>peak_directions,
        "measurement_scope"=>"port Schur Y after zero external current at every unmeasured device terminal; all device dynamics remain; target-matrix conditioning is not measured drive-matrix conditioning",
        "sampled_port_condition_peak"=>peak.port_condition,"peak_frequency_Hz"=>peak.frequency_Hz,
        "sampled_nodal_condition_SI_peak"=>maximum(r.nodal_condition_SI for r in rows),
        "scope"=>"sampled declared frequencies; port Schur Y with all device AC terminals; no measured input-conditioning or continuum bound")
end

# A local Taylor pencil supplies additional seeds for transformer networks.
# Final roots always use native distributed elements and converter responses.
function system_taylor_seeds(c)
    functions=composed_device_functions(c)
    s0=ComplexF64(1e-3);delta=1e-4
    y0=composed_nodal(c,s0,functions;which=:passive)
    dy=(composed_nodal(c,s0+delta,functions;which=:passive)-composed_nodal(c,s0-delta,functions;which=:passive))/(2delta)
    nv=length(c.nodes);nx=sum(size(c.net.elements[n].cache.A,1) for n in c.devices)
    K=zeros(ComplexF64,nx+nv,nx+nv);E=copy(K);vi=(nx+1):(nx+nv)
    K[vi,vi]=-(y0-s0*dy);E[vi,vi]=dy;offset=0
    for name in c.devices
        e=c.net.elements[name];b=device_bases(e.elec, e.bases);h=component_incidence(c,
            name)
        ix=(offset+1):(offset+size(e.cache.A,1));offset=last(ix)
        K[ix,ix]=e.cache.A;E[ix,ix]=I(length(ix));K[ix,vi]=(e.cache.B./b.voltage_inputs')*h'
        K[vi,ix]=-h*(e.cache.C.*b.current_outputs)
        K[vi,vi]-=h*(e.cache.D.*b.current_outputs./b.voltage_inputs')*h'
    end
    q=schur(K,E);finite=abs.(q.β).>100eps()*max(norm(E),1.)
    return q.α[finite]./q.β[finite]
end

# Refine the finite determinant polygon without changing any circuit parameter.
# Unit determinant phases avoid overflow; local magnitude curvature and midpoint
# phases trigger subdivision. Located-mode and nominal-carrier regions are
# explicitly sampled before subdivision to expose narrow turns.
function system_finite_contour(c,functions,frequencies,roots;shift=1e-6,maxdepth=12)
    fs=Float64[0.;frequencies]
    append!(fs,exp10.(range(-12,log10(first(frequencies));length=121)))
    for root in roots
        center=abs(imag(root))/(2π);width=max(abs(real(root))/(2π),1e-7)
        center<=last(frequencies) || continue
        append!(fs,filter(f->0<f<last(frequencies),center.+width.*range(-12,12;length=97)))
    end
    if last(frequencies)>50
        append!(fs,[50.;50 .- exp10.(range(-9,-1;length=81));50 .+ exp10.(range(-9,-1;length=81))])
    end
    sort!(unique!(fs))
    cache=Dict{Float64,NamedTuple}()
    function evaluate(f)
        return get!(cache,f) do
            s=ComplexF64(shift+im*2π*f)
            ret=I+composed_nodal(c,s,functions;which=:passive)\composed_nodal(c,s,functions;which=:active)
            logmagnitude,phase=logabsdet(ret)
            separation=minimum(svdvals(ret))
            isfinite(logmagnitude) && isfinite(phase) && abs(phase)>0 || error("nonfinite determinant at $f Hz")
            (;phase=ComplexF64(phase),logmagnitude,separation)
        end
    end
    retained=Float64[first(fs)];unresolved=Tuple{Float64,Float64}[]
    function segment(a,b,depth)
        mid=(a+b)/2
        left=evaluate(a);right=evaluate(b);center=evaluate(mid)
        increments=(angle(center.phase/left.phase),angle(right.phase/center.phase))
        folded=angle(right.phase/left.phase)
        curved=abs(center.logmagnitude-(left.logmagnitude+right.logmagnitude)/2)>.25
        subdivide=maximum(abs,increments)>π/6 || abs(sum(increments)-folded)>π || curved
        if subdivide && depth<maxdepth && mid!=a && mid!=b
            segment(a,mid,depth+1);segment(mid,b,depth+1)
        else
            subdivide && push!(unresolved,(a,b))
            push!(retained,mid);push!(retained,b)
        end
    end
    for j in 1:length(fs)-1
        segment(fs[j],fs[j+1],0)
    end
    values=[evaluate(f).phase for f in retained]
    polygon=[conj.(reverse(values[2:end]));values]
    increments=[angle(polygon[mod1(j+1,length(polygon))]/polygon[j]) for j in eachindex(polygon)]
    turns=sum(increments)/(2π);net=-round(Int,turns)
    openrhp=sum(count(z->real(z)>shift,
        eigvals(c.net.elements[n].cache.A)) for n in c.devices)
    peak=argmin([evaluate(f).separation for f in retained])
    return Dict("frequency_count"=>length(retained),"frequency_band_Hz"=>[first(frequencies),last(frequencies)],
        "shift_per_s"=>shift,"nyquist_net"=>net,"closed_RHP_count"=>net+openrhp,"turns"=>turns,
        "max_contour_phase_increment_rad"=>maximum(abs,increments),
        "return_difference_min"=>evaluate(retained[peak]).separation,"minimum_frequency_Hz"=>retained[peak],
        "unresolved_intervals_Hz"=>[[a,b] for (a,b) in unresolved],
        "sampling_resolved"=>isempty(unresolved) && maximum(abs,increments)<=π/3,
        "frequencies_Hz"=>retained,
        "scope"=>"finite determinant polygon; distributed infinite spectrum unenumerated")
end

function system_refine_stability(c,record;checkpoint=nothing)
    functions=composed_device_functions(c)
    roots=complex.(record["poles_real_per_s"],record["poles_imag_rad_per_s"])
    record["raw_contours"]=get(record,"raw_contours",record["contours"])
    record["contours"]=Dict{String,Any}[]
    for fs in (exp10.(range(-2,5;length=6001)),exp10.(range(-6,6;length=12001)))
        push!(record["contours"],system_finite_contour(c,functions,fs,roots))
        checkpoint===nothing || open(io->TOML.print(io,record;sorted=true),checkpoint,"w")
    end
    # A positive finite count with no growing located root supplies additional
    # guesses at the measured minimum separation, followed by circular offsets.
    if !any(real.(roots).>0) && any(x["closed_RHP_count"]>0 for x in record["contours"])
        initial=[ComplexF64(1+2π*im*x["minimum_frequency_Hz"]) for x in record["contours"] if x["closed_RHP_count"]>0]
        selected,tracks,errors=system_root_search(c,functions,initial)
        append!(record["seed_real_per_s"],real.(selected));append!(record["seed_imag_rad_per_s"],imag.(selected))
        append!(record["track_real_per_s"],[real(x[1]) for x in tracks])
        append!(record["track_imag_rad_per_s"],[imag(x[1]) for x in tracks])
        append!(record["track_residuals"],[x[2] for x in tracks]);append!(record["track_errors"],errors)
        record["seed_count"]+=length(selected);record["selected_seed_count"]+=length(selected)
        old=collect(zip(complex.(record["poles_real_per_s"],record["poles_imag_rad_per_s"]),record["root_residuals"]))
        append!(old,filter(x->x[2]<1e-6,tracks));sort!(old;by=x->real(x[1]),rev=true)
        record["poles_real_per_s"]=[real(x[1]) for x in old]
        record["poles_imag_rad_per_s"]=[imag(x[1]) for x in old]
        record["poles_frequency_Hz"]=[abs(imag(x[1]))/(2π) for x in old]
        record["root_residuals"]=[x[2] for x in old]
        isempty(old) || (record["most_positive_located_real_per_s"]=real(first(old)[1]))
        record["unresolved_seed_count"]=record["selected_seed_count"]-length(old)
        record["root_search"]*="; positive finite-count minima supply further native seeds and circular offsets"
        roots=complex.(record["poles_real_per_s"],record["poles_imag_rad_per_s"])
    end
    favorable=!isempty(roots) && maximum(real,roots)<-1e-7 &&
        all(contour["sampling_resolved"] && contour["closed_RHP_count"]==0 for contour in record["contours"])
    record["status"]=favorable ? "passed_finite_screen" : any(real.(roots).>0) ? "unstable" : "unresolved_finite_screen"
    record["refinement_source_files"]=source_record()
    checkpoint===nothing || open(io->TOML.print(io,record;sorted=true),checkpoint,"w")
    return record
end
