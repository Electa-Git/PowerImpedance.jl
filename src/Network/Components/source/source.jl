#= 
@with_kw mutable struct Source <: AbstractMultiport
	Z::Union{Float64, Int} = 0 # source series impedance [Ω]
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
	B = Diagonal(fill(ComplexF64(source.Z), p)) |> Matrix
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

	if source.Z == 0
		abcd = copy(abcd)
		abcd[1:p, (p+1):end] .= 1e-6 .* Matrix{ComplexF64}(I, p, p)
	end

	return abcd_to_y(abcd)
end =#


@with_kw mutable struct Source <: AbstractMultiport
    Z::Union{Float64, Int} = 0
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
    B = Diagonal(fill(ComplexF64(source.Z), p)) |> Matrix
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

    if source.Z == 0
        abcd = copy(abcd)
        abcd[1:p, (p+1):end] .= 1e-6 .* Matrix{ComplexF64}(I, p, p)
    end

    return abcd_to_y(abcd)
end


function convert!(data,elem::Element{Source},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)
    
    # source = elem.element_model

	# Check if AC or DC source (second one not implemented)
	is_three_phase(elem) ?
	ac_source_power_flow!(
		data,
		nodes2bus,
		bus2nodes,
		elem2comp,
		comp2elem,
		elem,
		global_dict,
	) :
	dc_source_power_flow!(
		data,
		nodes2bus,
		bus2nodes,
		elem2comp,
		comp2elem,
		elem,
		global_dict,
	)


end

function topowerblocks(elem::Element{Source})
	
	# Check if AC or DC source (second one not implemented)
	nbports=1
	elecdomain = elecdomainpb(elem)
	if is_three_phase(elem)
		pb = PB.ACSourceData()

	else
		pb = PB.DCSourceData()
	end

	return pb, nbports, elecdomain
end


function addecs!(ecsdata, elem::Element{Source}, blockid, pblut)
	
	nongroundnets = filtergrounds(values(elem.pins))
	busid = pblut.bus[first(nongroundnets)] # All nets map to the same busid in the LUT

	value = elem.element_model.V 
	
	if is_three_phase(elem)
		componenttype = PB.Vac
		PB.add!(ecsdata, PB.θ, busid, 0)
	else
		componenttype =  PB.Vdc
	end

	PB.add!(ecsdata, componenttype, busid, value)
end
		




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
