abstract type Machine end

function eval_abcd(machine :: Machine, s :: Complex)
    return eval_y(machine, s)
end

function eval_y(machine :: Machine, s :: Complex)
    Y = eval_parameters(machine, s)
    return Y
end

function make_power_flow!(machine:: Machine, data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)

    # Check if AC or DC source (second one not implemented)
    # is_three_phase(elem) ? nothing : error("DC sources are currently not implemented")

    ### MAKE BUSES OUT OF THE NODES
    # Find the nodes not connected to the ground
    ac_nodes = make_non_ground_node(elem, bus2nodes) 
    ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)
    # Make busses for the non-ground nodes 
    interm_bus = add_interm_bus_ac!(data, global_dict) # No mapping to node, bcs no corresponding node in PowerImpedance

    # Make the generator component for injection
    key = injection_initialization!(data, elem2comp, comp2elem, interm_bus, elem, global_dict)
    key = string(key)

    # Add additional branch & bus for SM transformer (RL-branch)
    
    key_branch = length(data["branch"]) + 1
    key_branch_str = string(key_branch)

    (data["branch"])[key_branch_str] = Dict{String, Any}()
    ((data["branch"])[key_branch_str])["f_bus"] = interm_bus
    ((data["branch"])[key_branch_str])["t_bus"] = ac_bus
    ((data["branch"])[key_branch_str])["source_id"] = Any["branch", key_branch]
    ((data["branch"])[key_branch_str])["index"] = key_branch
    ((data["branch"])[key_branch_str])["rate_a"] = 1
    ((data["branch"])[key_branch_str])["rate_b"] = 1
    ((data["branch"])[key_branch_str])["rate_c"] = 1
    ((data["branch"])[key_branch_str])["br_status"] = 1
    ((data["branch"])[key_branch_str])["angmin"] = ang_min
    ((data["branch"])[key_branch_str])["angmax"] = ang_max
    ((data["branch"])[key_branch_str])["transformer"] = false
    ((data["branch"])[key_branch_str])["tap"] = 1
    ((data["branch"])[key_branch_str])["shift"] = 0
    ((data["branch"])[key_branch_str])["c_rating_a"] = 1

    
    ((data["branch"])[key_branch_str])["br_r"] = machine.rt * (machine.Vᵃᶜ_base^2 / machine.S_base) / global_dict["Z"]
    ((data["branch"])[key_branch_str])["br_x"] = machine.lt * (machine.Vᵃᶜ_base^2 / machine.S_base) / global_dict["Z"]
    ((data["branch"])[key_branch_str])["g_fr"] = 0
    ((data["branch"])[key_branch_str])["b_fr"] = 0
    ((data["branch"])[key_branch_str])["g_to"] = 0
    ((data["branch"])[key_branch_str])["b_to"] = 0

    # Change type of intermediate bus to PV (2)
    ((data["bus"])[string(interm_bus)]) = set_bus_type((data["bus"])[string(interm_bus)], 2)


    ((data["bus"])[string(interm_bus)])["vm"] = ((data["gen"])[key])["vg"]
    ((data["bus"])[string(interm_bus)])["vmin"] =  0.9*((data["gen"])[key])["vg"]
    ((data["bus"])[string(interm_bus)])["vmax"] =  1.1*((data["gen"])[key])["vg"]
end

