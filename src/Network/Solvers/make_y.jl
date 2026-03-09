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
                (phase = Int(length(element.pins) / 2)) # Required to achieve correct indexing with different domains for passives: dq & abc
            end
            for (key₁, val₁) in element.pins, (key₂, val₂) in element.pins # key is the pin name, val is the node name
                # Find the i,j element in the element admittance matrix for (key₁, key₂)
                i = (parse(Int, string(key₁)[1]) - 1) * phase + parse(Int, string(key₁)[3]) # Find row index 
                j = (parse(Int, string(key₂)[1]) - 1) * phase + parse(Int, string(key₂)[3]) # Find column index
                # Element in the admittance matrix found, now check if the nodes are in the node list
                iₚ = findfirst(p -> p == val₁, dict[:node_list]) # Find row index of node in the admittance matrix
                (iₚ === nothing) ? continue : nothing # If the node is not in the node list, skip it
                jₚ = findfirst(p -> p == val₂, dict[:node_list]) # Find column index of node in the admittance matrix
                (jₚ === nothing) ? continue : nothing
                # Add the element admittance to the admittance matrix
                if i>= 2 && (isa(element.element_model, MMC) || isa(element.element_model, TLC)) # Flip sign for the AC elements of converters
                    
                    Y[i,j] = -Y[i,j] 
                end
                Y_matrix[iₚ, jₚ] += Y[i,j]
            end
    end

    return Y_matrix
end
