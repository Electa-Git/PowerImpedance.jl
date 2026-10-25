const ang_max = deg2rad(360)
const ang_min = deg2rad(-360)

function set_bus_type(bus_data, type)
	# Preserve higher-priority AC bus types.
	## PQ (1) < PV (2) < slack (3)
	current_type = bus_data["bus_type"] #Just to make sure it is int
	if type > current_type
		bus_data["bus_type"] = type
	end
	return bus_data
end

function set_bus_type_dc(bus_data, type)
	## P(1) < Vdc droop with Pdc (3) < Vdc droop with Pac (4) < Vdc(2)
	# Change up order so DC voltage control has the highest priority, then droop and lastly
	# constant power
	order = [1, 3, 4, 2]
	current_type = bus_data["bus_type"]
	# You parse type to integer and then find the index which gives its relative importance
	imp_type = findfirst(isequal(type), order)
	imp_current = findfirst(isequal(current_type), order)
	if imp_type > imp_current # If new type has higher importance we put it in place
		bus_data["bus_type"] = type
	end
	return bus_data
end

function branch_ac!(data, key_branch, (bus1,bus2), global_dict)

	(data["branch"])[string(key_branch)] = Dict{String, Any}()
	((data["branch"])[string(key_branch)])["f_bus"] = bus1
	((data["branch"])[string(key_branch)])["t_bus"] = bus2
	((data["branch"])[string(key_branch)])["source_id"] = Any["branch", key_branch]
	((data["branch"])[string(key_branch)])["index"] = key_branch
	((data["branch"])[string(key_branch)])["rate_a"] = 1
	((data["branch"])[string(key_branch)])["rate_b"] = 1
	((data["branch"])[string(key_branch)])["rate_c"] = 1
	((data["branch"])[string(key_branch)])["br_status"] = 1
	((data["branch"])[string(key_branch)])["angmin"] = ang_min
	((data["branch"])[string(key_branch)])["angmax"] = ang_max
	return key_branch
end

function branch_dc!(data, key_branch, (bus1,bus2), global_dict)
	# Add busses for the branch

	(data["branchdc"])[string(key_branch)] = Dict{String, Any}()
	((data["branchdc"])[string(key_branch)])["fbusdc"] = bus1
	((data["branchdc"])[string(key_branch)])["tbusdc"] = bus2
	((data["branchdc"])[string(key_branch)])["source_id"] = Any["branchdc", key_branch]
	((data["branchdc"])[string(key_branch)])["index"] = key_branch
	((data["branchdc"])[string(key_branch)])["rateA"] = 100
	((data["branchdc"])[string(key_branch)])["rateB"] = 100
	((data["branchdc"])[string(key_branch)])["rateC"] = 100
	((data["branchdc"])[string(key_branch)])["status"] = 1

	#Copied these from element-specific definitions bcs everytime zero
	((data["branchdc"])[string(key_branch)])["l"] = 0
	((data["branchdc"])[string(key_branch)])["c"] = 0

	return key_branch
end

"""
	function add_interm_bus_ac!(data)

Add intermediate AC bus to PowerModels data, which has no corresponding node(s). 
An example is the Synchronous Machine wich has an intermediate bus, connecting the
generator and RL-branch (transformer)
"""
function add_interm_bus_ac!(data, global_dict)

	bus = length(data["bus"]) + 1# Create the bus with a string key.
	bus = string(bus)

	(data["bus"])[bus] = Dict{String, Any}()
	((data["bus"])[bus])["source_id"] = Any["bus", parse(Int, bus)]
	((data["bus"])[bus])["index"] = parse(Int, bus)
	((data["bus"])[bus])["bus_i"] = parse(Int, bus)
	((data["bus"])[bus])["zone"] = 1
	((data["bus"])[bus])["area"] = 1
	((data["bus"])[bus])["vmin"] = 0.9
	((data["bus"])[bus])["vmax"] = 1.1
	((data["bus"])[bus])["vm"] = 1
	((data["bus"])[bus])["va"] = 0
	((data["bus"])[bus])["base_kv"] = global_dict["V"] / 1e3
	((data["bus"])[bus])["bus_type"] = 1 # bus type - depends on components 1 is default PQ
	bus = parse(Int, bus)
	return bus
end
const dcpol = 2
