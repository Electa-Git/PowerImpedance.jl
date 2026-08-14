# using PowerImpedance.NetworkBuilder: BuilderState

"""
    This function converts the nonlinear network (represented with BuilderState) to a linearized admittance representation
    It returns a LinearizedAdmittanceNetwork of the current network
    3 steps
    - Converts the network to a PowerModelsACDC representation
    - Lets PowerModelsACDC solve the powerflow
    - Use the setpoints to convert to a linearized admittance representation
"""
function Base.convert(bs::BuilderState, ::Type{LinearizedAdmittanceNetwork})

    if !islinear(bs.elements)

        sp = nonlinearsetpoints(bs)

    else
        @info "Network only consists of linear elements. Skipping power flow."
        sp = (;)
    end

    return LinearizedAdmittanceNetwork(bs, sp)

end

function islinear(elements)
    for elem in values(elements)
        if !P.islinear(elem) 
            return false
        end
    end
    return true
end


function nonlinearsetpoints(bs::BuilderState)
    
    #1. Convert PowerImpedance payload to PMACDC
    data, global_dict, elempitopm = convert(bs, P.PMACDC)

    options = bs.options

    result = solve_acdcpf(
        data,
        P._PM.ACPPowerModel,
        powerflow_optimizer(options),
        is_bounded_options(options);
        setting = powerflow_setting(options),
    )

    # Transform results to setpoints that can be used by linearization step
    sp = transform(result["solution"], global_dict, bs, P.PMACDC, P.PIACDC, elempitopm)

    @info "Setpoints of nonlinear devices: $(sp)"
    return sp
end

# Transforms output(output payload) from PMACDC to PIACDC
function transform(output, global_dict, bs::BuilderState, ::Type{P.PMACDC}, ::Type{P.PIACDC}, elempitopm)

    sp = (;)
    for (key,elem) in pairs(bs.elements)
        
        #1. Skip passive devices
        if P.is_passive(elem) || P.is_source(elem)
            continue # Skips iteration
        end

        pmcomptype, pmkey = elempitopm[key]
        elemresult = output[pmcomptype][string(pmkey)]
        busresult = transform(output, bs.connections, P.PMACDC, P.PIACDC, key) #Sorted from AC to DC (easier extension for nonshunt active elements)
        

        sp = merge(sp, (; key => P.transform(elemresult, busresult, global_dict, elem, P.PMACDC, P.PIACDC),))

    end


    return sp
end

function transform(output, connections, ::Type{P.PMACDC}, ::Type{P.PIACDC}, key)
   
    elemconnections = sortedcomponentconnections(connections, key) #Sorted from AC to DC and with terminal
    busids = unique(Table(bus = elemconnections.bus, elecdomain=elemconnections.elecdomain))
    # busids_symbol = Symbol.(unique(string.(elemconnections.elecdomain, "_", elemconnections.bus)))
    busresults = [output[string(busid.elecdomain == 1 ? "bus" : "busdc")][string(busid.bus)] for busid in busids]
    # busresults_nt = NamedTuple{busids_symbol}(busresults)
    
    return busresults
end
