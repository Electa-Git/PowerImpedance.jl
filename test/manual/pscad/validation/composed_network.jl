# Lumped composed circuits retain native device Jacobians and explicit passive
# storage. Port coordinates lead the nodal matrix; ideal-source nodes are clamped.
function composed_circuit(net, devices, grids, ports)
    clamped = Set{Symbol}([:gnd])
    for e in values(net.elements)
        e.element_model isa PowerImpedance.Source && union!(clamped, values(e.pins))
    end
    nodes = Symbol[]
    for (name, side) in ports, t in 1:2
        push!(nodes, net.elements[name].pins[Symbol("$side.$t")])
    end
    length(unique(nodes)) == length(nodes) || error("duplicate composed port")
    any(in(clamped), nodes) && error("a measured port is voltage clamped")
    for name in sort!(collect(keys(net.elements))), node in values(net.elements[name].pins)
        node in clamped || node in nodes || push!(nodes, node)
    end
    return (; net, devices=collect(devices), grids=collect(grids), nodes, ports=collect(ports))
end

function composed_incidence(c, e, pins)
    h = zeros(length(c.nodes), length(pins))
    for (j, pin) in enumerate(pins)
        k = findfirst(==(e.pins[pin]), c.nodes)
        k === nothing || (h[k,j] = 1)
    end
    return h
end

function device_incidence(c, name)
    e = c.net.elements[name]
    b = device_bases(e.element_model.elec)
    pins = b.dc_voltage === nothing ? Symbol[] : [Symbol("1.1")]
    append!(pins, [Symbol("$(b.ac_side).$t") for t in 1:2])
    return composed_incidence(c, e, pins)
end

function passive_incidence(c, e)
    pins = [Symbol("$side.$t") for side in 1:2 for t in 1:e.input_pins]
    return composed_incidence(c, e, pins)
end

# The exact delay is inserted inside each eligible device before assembling KCL.
# Positive-delay devices retain their native model, including carrier corrections.
function composed_device_functions(c; time_step = nothing)
    return Dict(name => time_step === nothing ?
        (s -> physical_y(c.net.elements[name], ComplexF64(s))) :
        one_step_full_y(c.net.elements[name], time_step) for name in c.devices)
end

function composed_nodal(c, s, functions; which = :full, forms = nothing)
    y = zeros(ComplexF64, length(c.nodes), length(c.nodes))
    for (name, e) in c.net.elements
        e.element_model isa PowerImpedance.Source && continue
        device = name in c.devices
        which == :passive && device && continue
        which == :active && !device && continue
        if device
            h = device_incidence(c, name)
            y += h * functions[name](s) * h'
        else
            h = passive_incidence(c, e)
            yy = forms === nothing ? PowerImpedance.get_y(e, ComplexF64(s)) :
                composed_passive_y(e, forms[name], s)
            y += h * yy * h'
        end
    end
    return y
end

function composed_passive_y(e, form, s)
    n = e.input_pins
    rotation = n == 2 ? [0. 2π*50; -2π*50 0.] : zeros(n,n)
    q = s*I(n) + rotation
    r, l, cap = form.R, form.L, form.C
    if form.topology == :series
        z = something(r,0.)*I(n) + something(l,0.)*q
        cap === nothing || (z += inv(q)/cap)
        y = inv(z)
    else
        y = (r === nothing ? 0. : inv(r))*I(n) + something(cap,0.)*q
        l === nothing || (y += inv(q)/l)
    end
    return [y -y; -y y]
end

function composed_reduce(c, y)
    a = 1:2length(c.ports)
    b = (last(a)+1):size(y,1)
    return isempty(b) ? y : y[a,a] - y[a,b]*(y[b,b]\y[b,a])
end

function composed_reference(c, spec; time_step = nothing, forms = nothing)
    functions = composed_device_functions(c; time_step)
    targets = Dict{String,Vector{Matrix{ComplexF64}}}("aggregate_Y" => [], "direct_Z" => [])
    for name in c.devices
        targets[string(name)*"_Y"] = Matrix{ComplexF64}[]
    end
    np = 2length(c.ports)
    for f in spec.frequencies
        s = im*2π*f
        full = composed_nodal(c,s,functions; forms)
        # A unit imposed port voltage and exact elimination of internal nodes.
        lift = Matrix{ComplexF64}(I, length(c.nodes), np)
        if length(c.nodes)>np
            b = (np+1):length(c.nodes)
            lift[b,:] = -full[b,b]\full[b,1:np]
        end
        passive = composed_nodal(c,s,functions; which=:passive, forms)
        grid = zeros(ComplexF64,size(full))
        for name in c.grids
            e = c.net.elements[name]; h = passive_incidence(c,e)
            yy = forms === nothing ? PowerImpedance.get_y(e,ComplexF64(s)) : composed_passive_y(e,forms[name],s)
            grid += h*yy*h'
        end
        push!(targets["aggregate_Y"], ((full-grid)*lift)[1:np,:])
        push!(targets["direct_Z"], inv(composed_reduce(c,full)))
        for name in c.devices
            h = device_incidence(c,name); b = device_bases(c.net.elements[name].element_model.elec)
            yy=functions[name](s)
            if b.dc_voltage===nothing || all(iszero,h[:,1])
                # Local device Y uses its own measured terminal voltage, even
                # when that terminal is internal to a line-plus-device circuit.
                individual=yy[b.ac_indices,b.ac_indices]
            else
                # Coupled DC nodes require the complete nodal reduction.
                # Embed this device's current rows at their measured AC port.
                ac=h[:,b.ac_indices]
                all(iszero,ac[(np+1):end,:]) || error("unmeasured coupled AC terminal")
                individual=ac[1:np,:]*(yy*h'*lift)[b.ac_indices,:]
            end
            push!(targets[string(name)*"_Y"],individual)
        end
    end
    return Dict(name=>cat(values...;dims=3) for (name,values) in targets)
end

# Independent descriptor for native lumped networks: every converter/machine
# state and every series/parallel RLC storage state survives the KCL assembly.
function composed_descriptor(c)
    nv = length(c.nodes)
    blocks = Any[]
    for (name,e) in c.net.elements
        e.element_model isa PowerImpedance.Source && continue
        name in c.devices && continue
        e.element_model isa PowerImpedance.Impedance || error("descriptor requires a lumped RLC branch: $name")
        form = P.identify_rlc(e; name).form
        m = e.input_pins
        h = passive_incidence(c,e)*[I(m); -I(m)]
        rot = m == 2 ? [0. 2π*50; -2π*50 0.] : zeros(m,m)
        push!(blocks,(;name,form,m,h,rot))
    end
    nx = sum(size(c.net.elements[n].A,1) for n in c.devices)
    ns = sum(b.m*((b.form.L!==nothing)+(b.form.C!==nothing)) for b in blocks;init=0)
    n = nx+ns+nv; vi = (n-nv+1):n
    K = zeros(ComplexF64,n,n); E = similar(K); fill!(E,0)
    offset = 0
    for name in c.devices
        e=c.net.elements[name];b=device_bases(e.element_model.elec);h=device_incidence(c,name)
        ix=(offset+1):(offset+size(e.A,1));offset=last(ix)
        E[ix,ix]=I(length(ix));K[ix,ix]=e.A
        K[ix,vi]=(e.B./b.voltage_inputs')*h'
        K[vi,ix]=-h*(e.C.*b.current_outputs)
        K[vi,vi]-=h*(e.D.*b.current_outputs./b.voltage_inputs')*h'
    end
    for b in blocks
        f=b.form;m=b.m;h=b.h;rot=b.rot
        if f.topology==:parallel
            f.R===nothing || (K[vi,vi]-=h*h'/f.R)
            f.C===nothing || (E[vi,vi]+=f.C*h*h';K[vi,vi]-=f.C*h*rot*h')
            if f.L!==nothing
                ix=(offset+1):(offset+m);offset=last(ix)
                E[ix,ix]=f.L*I(m);K[ix,ix]=-f.L*rot;K[ix,vi]=h';K[vi,ix]=-h
            end
        elseif f.L!==nothing
            ix=(offset+1):(offset+m);offset=last(ix)
            E[ix,ix]=f.L*I(m);K[ix,ix]=-something(f.R,0.)*I(m)-f.L*rot
            K[ix,vi]=h';K[vi,ix]=-h
            if f.C!==nothing
                cx=(offset+1):(offset+m);offset=last(cx)
                E[cx,cx]=f.C*I(m);K[cx,cx]=-f.C*rot;K[cx,ix]=I(m);K[ix,cx]=-I(m)
            end
        elseif f.C!==nothing && f.R!==nothing
            ix=(offset+1):(offset+m);offset=last(ix)
            E[ix,ix]=f.C*I(m);K[ix,ix]=-I(m)/f.R-f.C*rot
            K[ix,vi]=h'/f.R;K[vi,ix]=h/f.R;K[vi,vi]-=h*h'/f.R
        elseif f.C!==nothing
            E[vi,vi]+=f.C*h*h';K[vi,vi]-=f.C*h*rot*h'
        else
            K[vi,vi]-=h*h'/f.R
        end
    end
    # Pure capacitors have no extra branch state: their voltage storage is nodal.
    used = [collect(1:offset);collect(vi)]
    K=K[used,used];E=E[used,used];vi=(offset+1):length(used)
    qz=schur(K,E);finite=abs.(qz.β).>100eps()*max(norm(E),1.)
    poles=sort!(qz.α[finite]./qz.β[finite];by=real,rev=true)
    return (;K,E,vi,poles)
end

function composed_stability(c; frequencies=exp10.(range(-2,5;length=6001)))
    pen=composed_descriptor(c);functions=composed_device_functions(c)
    residual=0.
    for s in (1.0 + 2im, 10.0 + 100im, 100.0 + 1000im)
        mat=s*pen.E-pen.K;ix=setdiff(axes(mat,1),pen.vi)
        y=mat[pen.vi,pen.vi]-mat[pen.vi,ix]*(mat[ix,ix]\mat[ix,pen.vi])
        native=composed_nodal(c,s,functions)
        residual=max(residual,norm(y-native)/max(norm(native),1e-12))
    end
    characteristic=ComplexF64[];margin=Inf
    for f in [0.;frequencies]
        s=1e-6+im*2π*f
        yp=composed_nodal(c,s,functions;which=:passive)
        ya=composed_nodal(c,s,functions;which=:active)
        ret=I+yp\ya;push!(characteristic,det(ret));margin=min(margin,minimum(svdvals(ret)))
    end
    contour=[conj.(reverse(characteristic[2:end]));characteristic]
    increments=[angle(contour[mod1(j+1,length(contour))]/contour[j]) for j in eachindex(contour)]
    turns=sum(increments)/(2π);net=-round(Int,turns)
    open_rhp=sum(count(z->real(z)>1e-6,eigvals(c.net.elements[n].A)) for n in c.devices)
    stable=!isempty(pen.poles) && maximum(real,pen.poles)<-1e-7 && net+open_rhp==0 && abs(turns+net)<1e-6 && residual<=1e-6
    return Dict("method"=>"complete lumped KCL descriptor + native finite contour",
        "status"=>stable ? "passed" : "failed","frequency_count"=>length(frequencies),
        "frequency_band_Hz"=>[first(frequencies),last(frequencies)],"contour_shift_per_s"=>1e-6,
        "nyquist_net"=>net,"open_RHP_count"=>open_rhp,"closed_RHP_count"=>net+open_rhp,
        "max_contour_phase_increment_rad"=>maximum(abs,increments),
        "most_positive_located_real_per_s"=>maximum(real,pen.poles),
        "poles_real_per_s"=>real.(pen.poles),"poles_imag_rad_per_s"=>imag.(pen.poles),
        "descriptor_native_residual"=>residual,"return_difference_min"=>margin,
        "root_scope"=>"all finite lumped descriptor roots; not a distributed or exact-delay spectrum proof")
end

function exported_composed_passives(c, project, list)
    text=read(project,String);forms=Dict{Symbol,P.RLCForm}()
    for (name,e) in c.net.elements
        e.element_model isa PowerImpedance.Source && continue
        name in c.devices && continue
        original=P.identify_rlc(e;name).form
        item=only(filter(x->x.name==name,list.elements))
        fields=map(((:R,"resistor","R","ohm"),(:L,"inductor","L","H"),(:C,"capacitor","C","uF"))) do (field,kind,key,unit)
            value=getproperty(original,field)
            value===nothing && return nothing
            # AC impedance component_chain! emits stem_R/L/C; capacitor units are uF.
            parsed=exported_passive(text,item.pscad*"_"*key,kind,key,unit)
            field==:C && (parsed*=1e-6)
            isapprox(parsed,value;rtol=1e-8) || error("exported passive changed: $name/$field")
            return parsed
        end
        forms[name]=P.RLCForm(original.topology,fields...)
    end
    return forms
end

