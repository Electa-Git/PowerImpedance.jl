abstract type Transmission_line <: AbstractMultiport end

function eval_y(tl :: Transmission_line, s :: Complex)
    return abcd_to_y(eval_abcd(tl, s))
end

function eval_y(el::Element{<:Transmission_line}, s :: Complex)
    return eval_y(el.element_model, s)
end

pmtype(elem::Element{<:Transmission_line}) = is_three_phase(elem) ? "branch" : "branchdc"

function convert!(data,elem::Element{<:Transmission_line},::Type{PMACDC}, nodes2bus, bus2nodes, elem2comp, comp2elem, global_dict)

    if is_three_phase(elem)
        key, bus1,bus2 = branch_ac!(data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
       
    else
        key,bus1,bus2 = branch_dc!(data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
    end

    return convert!(data, elem, PMACDC, key, (bus1,bus2), global_dict)
end

function convert!(data, elem::Element{<:Transmission_line}, ::Type{PMACDC}, key, buses, global_dict)
    tl = elem.element_model

   

    if pmtype(elem) == "branch"
        branch_ac!(data, key, buses, global_dict)
        branch = data["branch"][string(key)]
        branch["transformer"] = false
        branch["tap"] = 1
        branch["shift"] = 0
        branch["c_rating_a"] = 1

        abcd = eval_abcd(tl, global_dict["omega"] * 1im)
        n = Int(size(abcd, 1) / 2)
        id = Matrix{ComplexF64}(I, n, n)
        a = abcd[1:n, 1:n]
        b = abcd[1:n, (n+1):end]

        z_ph = b / global_dict["Z"]
        t_seq = [1 1 1; 1 exp(2 * pi / 3im) exp(4 * pi / 3im); 1 exp(4 * pi / 3im) exp(2 * pi / 3im)] / sqrt(3)
        z = (inv(t_seq) * z_ph * t_seq)[2, 2]
        y_ph = (a - id) * inv(b) * global_dict["Z"]
        y = (inv(t_seq) * y_ph * t_seq)[2, 2]

        branch["br_r"] = real(z)
        branch["br_x"] = imag(z)
        branch["g_fr"] = real(y)
        branch["b_fr"] = imag(y)
        branch["g_to"] = real(y)
        branch["b_to"] = imag(y)
        return nothing
    end
    branch_dc!(data, key, buses, global_dict)
    branchdc = data["branchdc"][string(key)]
    abcd = eval_abcd(tl, 1e-6 * 1im)
    n = Int(size(abcd, 1) / 2)
    z = abcd[1:n, (n+1):end][1, 1] / (global_dict["Z"] / 3)
    branchdc["r"] = real(z)
    return nothing
end
