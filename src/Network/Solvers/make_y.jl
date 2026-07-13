function _pin_side_index(pin::Symbol)
    parts = split(string(pin), ".")
    length(parts) == 2 || throw(ArgumentError("Unexpected pin format `$pin`."))
    return parse(Int, parts[1]), parse(Int, parts[2])
end

function _admittance_index(element::Element, pin::Symbol, phase::Int)
    side, idx = _pin_side_index(pin)

    if is_converter(element)
        # Converter admittances are ordered by pin number:
        # first all side-1 pins, then all side-2 pins.
        return side == 1 ? idx : nip(element) + idx
    end

    return (side - 1) * phase + idx
end

function _ac_row_start_for_sign_flip(element::Element)
    model = element.element_model
    if model isa MMC || model isa TLC
        # Monopolar ordering: [dc, d, q]
        return typemax(Int) #Changed all currents in state space to load sign convention=> Not needed to flip sign
    end

    return typemax(Int)
end

"""
function make_y(net :: Network, dict::Dict{Symbol, Array{Union{Symbol,Int}}}, s :: Complex)
    Creates y matrix of the (sub)network using data written in dictionary dict.
    The dict contains the node_list and element_list.
    The node_list contains the names of the nodes which should be included in the y matrix.
    The element_list contains the names of the elements which should be included in the y matrix.
    The y matrix is a square matrix of size n x n, where n is the number of nodes in node_list.
    The y matrix is constructed by evaluating the admittances of the elements in the element_list.

    In case of active elements calculation of y matrix in dq domain.
    If only passive elements are present, the y matrix can be calculated in abc and dq.


    Example:

    dictACDC = Dict{Symbol, Array{Union{Symbol,Int}}}(:node_list => Symbol[], :element_list => Symbol[])

    dictACDC[:node_list]= [:B2d, :B2q, :B3d, :B3q, :B4, :B5, :B6d, :B6q, :B7d, :B7q]
    dictACDC[:element_list] = [:tl1, :dc_line, :c1, :c2]

    # Create the y matrix with respect to the elements and nodes defined in dictACDC
    dummy=PowerImpedanceACDC.make_y(net,dictACDC)
"""
function make_y(net :: Network, dict::Dict{Symbol, Array{Union{Symbol,Int}}}, s :: Complex)

    n = length(dict[:node_list])
    Y_matrix = zeros(ComplexF64, n, n)
    for element in dict[:element_list]
        element = net.elements[element]
        Y = get_y(element, s)
        phase = 1
        if is_passive(element)
            # Required to achieve correct indexing with different domains for passives: dq & abc
            phase = Int(length(element.pins) / 2)
        end
        ac_row_start = _ac_row_start_for_sign_flip(element)
        for (key₁, val₁) in element.pins, (key₂, val₂) in element.pins # key is the pin name, val is the node name
            # Find the i,j element in the element admittance matrix for (key₁, key₂)
            i = _admittance_index(element, key₁, phase)
            j = _admittance_index(element, key₂, phase)
            # Element in the admittance matrix found, now check if the nodes are in the node list
            iₚ = findfirst(p -> p == val₁, dict[:node_list])
            iₚ === nothing && continue
            jₚ = findfirst(p -> p == val₂, dict[:node_list])
            jₚ === nothing && continue
            # Add the element admittance to the admittance matrix
            yij = Y[i, j]
            if i >= ac_row_start # Flip sign for converter AC current rows
                yij = -yij
            end
            Y_matrix[iₚ, jₚ] += yij
        end
    end

    return Y_matrix
end
