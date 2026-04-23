"""
    This function converts the nonlinear network to a linearized admittance representation
    It returns a LinearizedAdmittanceNetwork of the current network
    3 steps
    - Converts the network to a PowerModelsACDC representation
    - Lets PowerModelsACDC solve the powerflow
    - Use the setpoints to convert to a linearized admittance representation
"""
function convert(nw::Network, ::Type{LinearizedAdmittanceNetwork})

    if is_linear(nw)
        println("Network only consists of linear elements. Skipping power flow.")
        return
    end

    #1. Convert PowerImpedanceACDC payload to PMACDC
    data, nodes2bus, elem2comp = convert(nw, PMACDC)

    # 2. Call the PowerModelsACDC solver
    ipopt = JuMP.optimizer_with_attributes(
        Ipopt.Optimizer,
        "tol" => 1e2,
        "dual_inf_tol" => 1e-1,
        "constr_viol_tol" => 1e-3,
        "compl_inf_tol" => 1e3,
        "print_level" => 0, # was set to 5 for more verbose output
        "max_iter" => 100,
        "grad_f_constant" => "yes",
        "recalc_y" => "yes",
        "bound_relax_factor" => 1e-8,
        "expect_infeasible_problem" => "yes",
    )
    s = Dict("output" => Dict("branch_flows" => true), "conv_losses_mp" => false)
    result = solve_acdcpf(data, _PM.ACPPowerModel, ipopt; setting = s)

    # Transform results to setpoints that can be used by linearization step
    transform(result["solution"],nw, nodes2bus,elem2comp, PMACDC, PIACDC)

end

# Transforms output(output payload) from PMACDC to PIACDC
function transform(output, nw, nodes2bus, elem2comp, ::Type{PMACDC}, ::Type{PIACDC})

    for (key,elem) in nw.elements
        
        #1. Skip passive devices
        if passive(elem)
            continue # Skips iteration
        end

        pmcomptype, key = elem2comp[elem.symbol]
        elemresult = output[string(key)]

        sp = transform(output, element, nodes2bus)

    end

end

"""
    Function returns bus in input payload PMACDC together with interface from the nets in a PIACDC Network
    Interface maps nets onto buses (key=("bus",1)). Actual type and initial values depend on component
"""
function convert!(data, nets, ::Type{PMACDC}, nw)
    
    LUTnet = Dict{Symbol,Tuple{String, Int}}()
    
    for elem in nw.elemens
        # 1. Check if already processed
        nets = values(elem.pins)
        if net[1] ∈ keys(LUTnet) # Yes, processed
            @assert all(in.(nets, (keys(LUTnet),))) # Make sure that all of them are in there. Otherwise,not physical power system
        else
            #2. If not, process that shit
            #2.a Check side bus type
            pmbustypes = (Val(DC), Val(DC))
            if is_converter(elem)
                pmbustypes = (Val(DC), Val(AC))
            elseif is_three_phase(elem)
                pmbustypes = (Val(AC), Val(AC))
            end
            firstpins = (Symbol("1.1"), Symbol("2.1")) # All components are implemented with 2 sides and for sure have a first pin per side
            for side in (1,2)
                pin = Symbol(string(side,".1"))
                net = elem.pins
                busid = addbus!(data, LUTnet,)

            end
        end
    end
end

function convert(nw::Network, ::Type{PMACDC})
    global ang_min, ang_max, result, nodes2bus, elem2comp, data
    global_dict = PowerModelsACDC.get_pu_bases(1000, net.voltageBase[1]) # 3-PH MVA, LL-RMS, Original setting was 100,320
    global_dict["omega"] = 2π * 50

    ang_min = deg2rad(360)
    ang_max = deg2rad(-360)

    nodes_dict = net.nets
    elem_dict = net.elements

    # No power flow when linear (no setpoint updates) 
    if is_linear(net)
        println("Network only consists of linear elements. Skipping power flow.")
        return
    end

    # PowerModelsACDC network dictoniary
    data = Dict{String, Any}()
    data = data_init(data, global_dict)
   
    ### 2-way dicts so we can have O(1) time complexity (node, elem:PowerImpedance ↔ bus, component:PowerModelsACDC)
    nodes2bus = Dict()
    # bus2nodes = Dict() 
    elem2comp = Dict()
    # comp2elem = Dict()

    ### Add grounds to the interfaces so we know for following (only do it once)
    ground_nodes = [k for k in keys(net.nets) if startswith(string(k), "gnd")] #TODO: add other ground identifiers (GND, Gnd, Ground, ground)
    push!(nodes2bus, ground_nodes => "gnd")
    push!(bus2nodes, "gnd" => ground_nodes) 
    
    #### 1. Create PowerModelsACDC dictionary and make interface 
    for (elem) in values(elem_dict)
        convert!(data,elem, PMACDC, nodes2bus, elem2comp, global_dict)

        
    end

    #### 1b. Check for slack busses (add one if none present) (3 is slack bus)
    if !(3 in [data["bus"][index]["bus_type"] for index in keys(data["bus"])])
        println("WARNING: No slack bus present. The first PV bus with generator will be set as reference")
        for gen_index in keys(data["gen"])
            bus_gen = data["gen"][gen_index]["gen_bus"]
            if data["bus"][string(bus_gen)]["bus_type"] == 2 # PV-bus
                set_bus_type(data["bus"][string(bus_gen)], 3)
                break
            end
            error("No PV bus with generator found. Update your problem!")
        end
    end
end