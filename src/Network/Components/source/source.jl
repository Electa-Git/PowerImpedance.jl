#= 
@with_kw mutable struct Source <: AbstractLinFreqDomain
	V::Union{Float64, Int} = 0        # DC voltage or voltage magnitude [kV]

	P::Union{Float64, Int}     = 0      # active power output [MW]
	Q::Union{Float64, Int}     = 0      # reactive power output [MVAr]
	P_min::Union{Float64, Int} = 0    # min active power output [MW]
	P_max::Union{Float64, Int} = 0    # max active power output [MW]
	Q_min::Union{Float64, Int} = 0    # min reactive power output [MVA]
	Q_max::Union{Float64, Int} = 0    # max reactive power output [MVA]

	# pins::Int = 1
	# ABCD::Matrix{ComplexF64} = zeros(ComplexF64, 0, 0)
end

function make_abcd(source::Source, p)
	# p = np(elem)
	A = Matrix{ComplexF64}(I, p, p)
	B = Diagonal(fill(0.0, p)) |> Matrix
	C = zeros(ComplexF64, p, p)
	D = Matrix{ComplexF64}(I, p, p)

	# elem.ABCD = ABCD(A, B, C, D)
	return A,B,C,D
end

function eval_abcd(source::Source, s::Complex)
	# s unused by design; keep signature for dispatch consistency
	return source.ABCD
end

function eval_y(source::Source, s::Complex)
	abcd = source.ABCD
	p = source.pins

	abcd = copy(abcd)
	abcd[1:p, (p+1):end] .= 1e-6 .* Matrix{ComplexF64}(I, p, p)

	return abcd_to_y(abcd)
end =#


@with_kw mutable struct Source <: AbstractLinFreqDomain
    V::Union{Float64, Int} = 0

    P::Union{Float64, Int}     = 0
    Q::Union{Float64, Int}     = 0
    P_min::Union{Float64, Int} = 0
    P_max::Union{Float64, Int} = 0
    Q_min::Union{Float64, Int} = 0
    Q_max::Union{Float64, Int} = 0

    pins::Int = 1
    ABCD::Matrix{ComplexF64} = zeros(ComplexF64, 0, 0)
end

function make_abcd(source::Source, p)
    source.pins = p

    A = Matrix{ComplexF64}(I, p, p)
    B = zeros(ComplexF64, p, p)
    C = zeros(ComplexF64, p, p)
    D = Matrix{ComplexF64}(I, p, p)

    source.ABCD = [A B; C D]
    return A, B, C, D
end

function eval_abcd(source::Source, s::Complex)
    isempty(source.ABCD) && make_abcd(source, source.pins)
    return source.ABCD
end

function eval_y(source::Source, s::Complex)
    abcd = eval_abcd(source, s)
    p = source.pins

	abcd = copy(abcd)
	abcd[1:p, (p+1):end] .= 1e-6 .* Matrix{ComplexF64}(I, p, p)

    return abcd_to_y(abcd)
end


pmtype(elem::Element{<:Source}) = is_three_phase(elem) ? "gen" : "gendc"

function convert!(data,elem::Element{<:Source},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)

	if is_three_phase(elem)
		ac_nodes = make_non_ground_node(elem, bus2nodes)
		ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)
		key = comp_elem_interface!(data, elem2comp, comp2elem, elem, pmtype(elem))
		return convert!(data, elem, PMACDC, key, (ac_bus,), global_dict)
	end

	dc_nodes = make_non_ground_node(elem, bus2nodes)
	dc_bus = add_bus_dc!(data, nodes2bus, bus2nodes, dc_nodes, global_dict)
	key = comp_elem_interface!(data, elem2comp, comp2elem, elem, pmtype(elem))
	return convert!(data, elem, PMACDC, key, (dc_bus,), global_dict)
end

function convert!(data, elem::Element{<:Source}, ::Type{PMACDC}, key, buses, global_dict)
	if pmtype(elem) == "gen"
		ac_bus = first(buses)
		_initialize_gen_entry!(data, key, ac_bus, elem, global_dict)
		set_bus = data["bus"][string(ac_bus)]
		gen = data["gen"][string(key)]
		set_bus["vmin"] = 0.9 * gen["vg"]
		set_bus["vmax"] = 1.1 * gen["vg"]
		set_bus["vm"] = gen["vg"]
		data["bus"][string(ac_bus)] = set_bus_type(set_bus, 3)
		return nothing
	end

	dc_bus = first(buses)
	_initialize_gendc_entry!(data, key, dc_bus, elem, global_dict)
	busdc = data["busdc"][string(dc_bus)]
	busdc["Vdc"] = elem.element_model.V * 1e3 / global_dict["V"]
	busdc["Vdcmax"] = 1.1 * busdc["Vdc"]
	busdc["Vdcmin"] = 0.9 * busdc["Vdc"]
	data["busdc"][string(dc_bus)] = set_bus_type_dc(busdc, 2)
	return nothing
end

function _initialize_gen_entry!(data, key, ac_bus, elem, global_dict)
	key_str = string(key)
	data["gen"][key_str] = Dict{String, Any}()
	gen = data["gen"][key_str]
	gen["mBase"] = global_dict["S"] / 1e6
	gen["gen_bus"] = ac_bus
	gen["pc1"] = 0
	gen["pc2"] = 0
	gen["qc1min"] = 0
	gen["qc1max"] = 0
	gen["qc2min"] = 0
	gen["qc2max"] = 0
	gen["ramp_agc"] = 0
	gen["ramp_q"] = 0
	gen["ramp_10"] = 0
	gen["ramp_30"] = 0
	gen["apf"] = 0
	gen["startup"] = 0
	gen["shutdown"] = 0
	gen["gen_status"] = 1
	gen["source_id"] = Any["gen", key]
	gen["index"] = key

	injecter = elem.element_model
	sp = elem.setpoint
	lm = elem.limits
	s_base = global_dict["S"] / 1e6
	v_base = global_dict["V"] / 1e3
	gen["pg"] = sp.Pac / s_base
	gen["qg"] = sp.Qac / s_base
	gen["pmin"] = lm.P_min / s_base
	gen["pmax"] = lm.P_max / s_base
	gen["qmin"] = lm.Q_min / s_base
	gen["qmax"] = lm.Q_max / s_base
	gen["vg"] = sp.Vac / v_base
	gen["model"] = 1
	gen["cost"] = 0
	gen["ncost"] = 0
	return key
end

function _initialize_gendc_entry!(data, key, dc_bus, elem, global_dict)
	key_str = string(key)
	data["gendc"][key_str] = Dict{String, Any}()
	gendc = data["gendc"][key_str]
	gendc["mBase"] = global_dict["S"] / 1e6
	gendc["gen_bus"] = dc_bus
	gendc["quadratic_cost"] = 0
	gendc["linear_cost"] = 0
	gendc["idle_cost"] = 0
	gendc["control_type"] = 2
	gendc["droop_const"] = 0
	gendc["gen_status"] = 1
	gendc["source_id"] = Any["gen", key]
	gendc["index"] = key

	sp = elem.setpoint
	lm = elem.limits
	s_base = global_dict["S"] / 1e6
	v_base = global_dict["V"] / 1e3
	gendc["pgdcset"] = sp.Pdc / s_base
	gendc["pmin"] = lm.P_min / s_base
	gendc["pmax"] = lm.P_max / s_base
	gendc["vgdc"] = sp.Vdc / v_base
	gendc["model"] = 1
	gendc["cost"] = 0
	gendc["ncost"] = 0
	return key
end

# function topowerblocks(elem::Element{Source})
	
# 	# Check if AC or DC source (second one not implemented)
# 	nbports=1
# 	elecdomain = elecdomainpb(elem)
# 	if is_three_phase(elem)
# 		pb = PB.ACSourceData()

# 	else
# 		pb = PB.DCSourceData()
# 	end

# 	return pb, nbports, elecdomain
# end


# function addecs!(ecsdata, elem::Element{Source}, blockid, pblut)
	
# 	nongroundnets = filtergrounds(values(elem.pins))
# 	busid = pblut.bus[first(nongroundnets)] # All nets map to the same busid in the LUT

# 	value = elem.element_model.V 
	
# 	if is_three_phase(elem)
# 		componenttype = PB.Vac
# 		PB.add!(ecsdata, PB.θ, busid, 0)
# 	else
# 		componenttype =  PB.Vdc
# 	end

# 	PB.add!(ecsdata, componenttype, busid, value)
# end
		




function ac_source_power_flow!(
	data,
	nodes2bus,
	bus2nodes,
	elem2comp,
	comp2elem,
	elem,
	global_dict,
)
	### MAKE BUSES OUT OF THE NODES
	# Find the nodes not connected to the ground
	ac_nodes = make_non_ground_node(elem, bus2nodes)

	# Make busses for the non-ground nodes 
	ac_bus = add_bus_ac!(data, nodes2bus, bus2nodes, ac_nodes, global_dict)

	# Make the generator component for injection
	key = injection_initialization!(data, elem2comp, comp2elem, ac_bus, elem, global_dict)
	key = string(key) # Of form "gen", 1 so convert 2nd element to string

	# Change bus information
	((data["bus"])[string(ac_bus)])["vmin"] = 0.9*((data["gen"])[key])["vg"]
	((data["bus"])[string(ac_bus)])["vmax"] = 1.1*((data["gen"])[key])["vg"]
	((data["bus"])[string(ac_bus)])["vm"] = ((data["gen"])[key])["vg"]

	((data["bus"])[string(ac_bus)]) = set_bus_type((data["bus"])[string(ac_bus)], 3)
end

function dc_source_power_flow!(
	data,
	nodes2bus,
	bus2nodes,
	elem2comp,
	comp2elem,
	elem,
	global_dict,
)
	### MAKE BUSES OUT OF THE NODES
	# Find the nodes not connected to the ground
	dc_nodes = make_non_ground_node(elem, bus2nodes)

	# Make busses for the non-ground nodes 
	dc_bus = add_bus_dc!(data, nodes2bus, bus2nodes, dc_nodes, global_dict)

	# Make the generator component for injection
	key =
		injection_initialization_dc!(data, elem2comp, comp2elem, dc_bus, elem, global_dict)
	key = string(key) # Of form "gen", 1 so convert 2nd element to string




	((data["busdc"])[string(dc_bus)])["Vdc"] = elem.element_model.V * 1e3 / global_dict["V"]
	((data["busdc"])[string(dc_bus)])["Vdcmax"] =
		1.1 * ((data["busdc"])[string(dc_bus)])["Vdc"]
	((data["busdc"])[string(dc_bus)])["Vdcmin"] =
		0.9 * ((data["busdc"])[string(dc_bus)])["Vdc"]

	((data["busdc"])[string(dc_bus)]) = set_bus_type_dc((data["busdc"])[string(dc_bus)], 2)
end
