
function Base.convert(bs::BuilderState, ::Type{P.PMACDC})
    
    #PMACDC data + interface
    data = Dict{String, Any}()
    global_dict = P.PowerModelsACDC.get_pu_bases(1000, option_value(bs.options, :voltageBase, 320)) # 3-PH MVA, LL-RMS, Original setting was 100,320
    P.data_init!(data, global_dict)
  
   
    
    global_dict["omega"] = 2*π*50


    ## Adding buses 

    convert!(data, bs.connections, P.PMACDC, global_dict)
    

    # 2. Fill up the data dictionary with corresponding PM index and bus connections 

    elempitopm = Dict{Symbol,@NamedTuple{pmtype::String, compkey::Int}}() #Maps PM component to element symbol for later use in transformation of results

    for (elemid, element) in pairs(bs.elements) #NamedTuple
        # Get sorted connectoins (first AC, then DC)
        connections = sortedcomponentconnections(bs.connections, elemid)
        sortedbusses = unique(connections.bus)
        

        # Get the PM component key and update LUT
        pmtype = P.pmtype(element)
        compkey = length(data[pmtype]) + 1
        elempitopm[elemid] = (;pmtype, compkey)

        P.convert!(data, element, P.PMACDC, compkey, sortedbusses, global_dict)
        
    end 

    ensure_slack_bus!(data)
	P.PowerModelsACDC.process_additional_data!(data)
   

	# powerflow = (result = result, data = data, nodes2bus = nodes2bus, elem2comp = elem2comp)



    return data, elempitopm

        
end

function convert!(data, element::P.Element{T}, ::Type{P.PMACDC}, elempmtopi, buspm2pi ) where {T}
    
    


    #1. Convert component
    pmcomp, pmcomptype = convert(element, global_dict)    
    compindex = length(data[pmcomptype]) + 1

    
    ## Update the LUT
    elempmtopi[(pmcomptype, compindex)] = elemid

    
   


    ## Add the copy to the right index of data dict
    data[pmcomptype][string(compindex)] = compdict
    return compdict, pmcomptype
end

# function updateacbus!(compdict::Dict, pmcomptype, pmbus_vec)
#     ACBusDict = Dict("gen"=>("gen_bus",), "shunt"=>("shunt_bus",), "branch" =>("f_bus", "t_bus"), "convdc"=>("busac_i",))

#     names = ACBusDict[pmcomptype]
#     for (name, bus) in zip(names, pmbus_vec)
#         compdict[name] = bus
#     end
# end



# function updateid!(compdict, index, pmcomptype)
#     compdict["source_id"] = Any[pmcomptype, index]
#     compdict["index"] = index
# end


findvalue(componentdata, id) = componentdata[id] 



function convert!(data, connections::ConnectionsRegistry,  ::Type{P.PMACDC},global_dict)
    
    # pm2pi = Dict{Tuple{String, Int}, Int}() # Maps PM bus index to PI bus index for later use in transformation of results
    # pi2pm = Dict{Int, Tuple{String, Int}}()

    # Split up for improved speed inside for loop (same function)
    acconn = acconnections(connections)
    acbusses = unique(acconn.bus) # Their index is busid
    dcconn = dcconnections(connections)
    dcbusses = unique(dcconn.bus)
    
    # AC-bus generation
    for (i,bus) in enumerate(acbusses)
        # pm2pi[("bus", i)] = bus
        addbus!(data, bus, global_dict, Val(:AC))
    end

    # DC-bus generation
    for (i,bus) in enumerate(dcbusses)
        # pm2pi[("busdc", i)] = bus
        addbus!(data, bus, global_dict, Val(:DC))
    end

    # return pm2pi
end

function addbus!(data, bus, global_dict, ::Val{:AC})
 
    busstr = string(bus)
    V = 1.0
    bustype = 1 # Default PQ bus, can be updated later if generator or shunt is connected

    (data["bus"])[busstr] = Dict{String, Any}()
    ((data["bus"])[busstr])["source_id"] = Any["bus", bus]
    ((data["bus"])[busstr])["index"] = bus
    ((data["bus"])[busstr])["bus_i"] = bus
    ((data["bus"])[busstr])["zone"] = 1
    ((data["bus"])[busstr])["area"] = 1
    ((data["bus"])[busstr])["vmin"] = 0.9*V
    ((data["bus"])[busstr])["vmax"] = 1.1*V
    ((data["bus"])[busstr])["vm"] = V
    ((data["bus"])[busstr])["va"] = 0
    ((data["bus"])[busstr])["base_kv"] = global_dict["V"] / 1e3
    ((data["bus"])[busstr])["bus_type"] = bustype 

end

function addbus!(data, bus, global_dict, ::Val{:DC})
    
    busstr = string(bus)
    
    (data["busdc"])[busstr] = Dict{String, Any}()
    ((data["busdc"])[busstr])["busdc_i"] = bus
    ((data["busdc"])[busstr])["source_id"] = Any["busdc", bus]
    ((data["busdc"])[busstr])["grid"] = 1
    ((data["busdc"])[busstr])["index"] = bus
    ((data["busdc"])[busstr])["Cdc"] = 0
    ((data["busdc"])[busstr])["Vdc"] = 1
    ((data["busdc"])[busstr])["Vdcmax"] = 1.1
    ((data["busdc"])[busstr])["Vdcmin"] = 0.9
    ((data["busdc"])[busstr])["Pdc"] = 0
    ((data["busdc"])[busstr])["basekVdc"] = global_dict["V"] / 1e3
    ((data["busdc"])[busstr])["bus_type"] = 1 # bus type - depends on components 1 is default P
end