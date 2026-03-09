export check_stability

"""
    function check_stability(net :: Network, mmc :: Element, direction :: Symbol = :dc)
This function determines two impedances inside the network, from which it forms the feedback
transfer function. It allows "cutting" the power
network next to the converter on its dc or ac side (determined by `direction` parameter).
Afterwards, it is chacked the impedance `Z_conv` obtained by "looking" in the converter and the other
one `Z_h` from the converter to the remaining of the circuit.

Using previous two impedances, the feedback transfer function is estimated as `Z_h Y_conv`.

The impedances are calculated for the angular frequencies whose range is defined by
`omega_range`.
"""
function check_stability(net :: Network, mmc :: Element; direction :: Symbol = :dc,
    omega_range = (0, 4, 1000))

    function phase_margin(tf, omega)
        for i in 2:length(tf)
            if (20*log10(abs(tf[i-1][3])) > 0) && (20*log10(abs(tf[i][3])) < 0)
                wrappedAngle = angle(tf[i][3]) + 2*pi*floor(angle(tf[i][3])/(-2*pi))
                println("Phase Margin = ", round(rad2deg(wrappedAngle) + 180, digits = 3), "° at ", round(omega[i]/2/pi, digits = 3), " Hz.")
                # println("Phase Margin = ", round(rad2deg(angle(tf[i][3])) + 180, digits = 3), "° at ", round(omega[i]/2/pi, digits = 3), " Hz.") # Original
            end
        end
    end

    function make_lists(net :: Network, dict :: Dict{Symbol, Array{Union{Symbol,Int}}},
        elim_elements :: Array{Symbol}, start_pins :: Array{Symbol})

        for node_name in start_pins
            node = netfor!(net, node_name)

            if occursin("gnd", string(node_name))
                return node_name
            else
                # add nodes to the node list
                !in(node_name, dict[:node_list]) && push!(dict[:node_list], node_name)
            end

            # find all elements inside the port connected to the node
            elements_pins = filter(p ->  !in(p[1], elim_elements) && !in(p[1], dict[:element_list]), node)

            for (element, pin) in elements_pins
                push!(dict[:element_list], element) # add element's symbol to the list
                other_nodes = get_nodes(net.elements[element], pin) # get the pins from the other side of element
                gnd = make_lists(net, dict, elim_elements, other_nodes)
                (gnd !== nothing) && return gnd
            end
        end
    end

    if !(isa(mmc.element_model, MMC) || isa(mmc.element_model, SynchronousMachine)) #TODO: Generalize
        throw(ArgumentError("Cannot determine stability of the passive element."))
    end

    node_list = []

    if (direction == :dc)

        elim_elements = Symbol[]
        for (elem_symbol, elem_pin) in net.nets[netname(net, (mmc.symbol, Symbol(1.1)))]
            (elem_symbol != mmc.symbol) && push!(elim_elements, elem_symbol)
        end
        dict = Dict{Symbol, Array{Union{Symbol,Int}}}(:node_list => Symbol[], :element_list => Symbol[])
        gnd = make_lists(net, dict, elim_elements, Symbol[netname(net, (mmc.symbol, Symbol(1.1)))])
        imp_mmc, omega = determine_impedance(net, elim_elements = elim_elements,
                input_pins = Any[(mmc.symbol, Symbol(1.1))], output_pins = Any[gnd], omega_range = omega_range)

        dict = Dict{Symbol, Array{Union{Symbol,Int}}}(:node_list => Symbol[], :element_list => Symbol[])
        gnd = make_lists(net, dict, Symbol[mmc.symbol], Symbol[netname(net, (mmc.symbol, Symbol(1.1)))])
        imp_rest, omega = determine_impedance(net, elim_elements = [mmc.symbol],
                input_pins = Any[(mmc.symbol, Symbol(1.1))], output_pins = Any[gnd], omega_range = omega_range)

        imp = Any[]
        for i in 1:length(omega)
            push!(imp, [imp_mmc[i] imp_rest[i] imp_rest[i]/imp_mmc[i]])
        end
    else
        elim_elements = Symbol[]
        for (elem_symbol, elem_pin) in net.nets[netname(net, (mmc.symbol, Symbol(2.1)))]
            (elem_symbol != mmc.symbol) && push!(elim_elements, elem_symbol)
        end
        for (elem_symbol, elem_pin) in net.nets[netname(net, (mmc.symbol, Symbol(2.2)))]
            (elem_symbol != mmc.symbol) && push!(elim_elements, elem_symbol)
        end

        imp_mmc, omega = determine_impedance(net, elim_elements = elim_elements,
                input_pins = Any[(mmc.symbol, Symbol(2.1))], output_pins = Any[(mmc.symbol, Symbol(2.2))], omega_range = omega_range)
        imp_rest, omega = determine_impedance(net, elim_elements = [mmc.symbol],
                input_pins = Any[(mmc.symbol, Symbol(2.1))], output_pins = Any[(mmc.symbol, Symbol(2.2))], omega_range = omega_range)

        imp = Any[]
        for i in 1:length(omega)
            push!(imp, [imp_mmc[i] imp_rest[i] imp_rest[i]/imp_mmc[i]])
        end
    end

    phase_margin(imp, omega)
    return imp, omega
end
