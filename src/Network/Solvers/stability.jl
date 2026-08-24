export check_stability

"""
$(TYPEDSIGNATURES)

Calculate the converter and network impedances at a selected partition of a Classic network. The method forms the minor-loop gain as `Z_network / Z_device` and reports the phase margin at each detected unity-gain crossing.

# Arguments

- `net`: connected Classic network.
- `mmc`: active converter or synchronous-machine element at the partition.
- `direction`: partition side. `:dc` selects the DC terminals. Other values select the AC terminals. Default: `:dc`.
- `omega_range`: legacy logarithmic frequency-grid tuple used by the impedance calculation. Default: `(0, 4, 1_000)`.

# Returns

- `impedance_data`: one `[Z_device Z_network Z_network/Z_device]` row for each frequency.
- `angular_frequencies`: angular-frequency vector in radians per second.

# Errors

- Throws `ArgumentError` when `mmc` is not an active converter or synchronous machine.
"""
function check_stability(net :: Network, mmc :: Element; direction :: Symbol = :dc,
    omega_range = (0, 4, 1000))

    function phase_margin(tf, omega)
        for i in 2:length(tf)
            if (20*log10(abs(tf[i-1][3])) > 0) && (20*log10(abs(tf[i][3])) < 0)
                wrappedAngle = angle(tf[i][3]) + 2*pi*floor(angle(tf[i][3])/(-2*pi))
                @info "Phase Margin = $(round(rad2deg(wrappedAngle) + 180, digits = 3))° at $(round(omega[i]/2/pi, digits = 3)) Hz."
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
