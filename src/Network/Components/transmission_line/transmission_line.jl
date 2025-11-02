abstract type Transmission_line end

function eval_y(tl :: Transmission_line, s :: Complex)
    return abcd_to_y(eval_abcd(tl, s))
end


function make_power_flow!(tl :: Transmission_line, data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
 
    if is_three_phase(elem)    
        key = branch_ac!(data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
        ((data["branch"])[string(key)])["transformer"] = false
        ((data["branch"])[string(key)])["tap"] = 1
        ((data["branch"])[string(key)])["shift"] = 0
        ((data["branch"])[string(key)])["c_rating_a"] = 1

        abcd = eval_abcd(tl, global_dict["omega"] * 1im)
        n = Int(size(abcd, 1)/2)
        id = Matrix{ComplexF64}(I, n, n)
        A = abcd[1:n, 1:n]
        B = abcd[1:n, n+1:end]

        # Extract pi model parameters from ABCD matrix
        # According to p. 190 of "Microwave Engineering" by Pozar
        Z_ph = B / global_dict["Z"] # Phase domain series impedance
        T_seq = [1 1 1;1 exp(2*pi/3im) exp(4*pi/3im);1 exp(4*pi/3im) exp(2*pi/3im)]/sqrt(3) # Transformation matrix for sequence domain
        Z = (inv(T_seq) * Z_ph * T_seq)[2,2] # Taking the positive sequence impedance
        Y_ph=(A-id)*inv(B)*global_dict["Z"] # Phase domain shunt admittance
        Y=(inv(T_seq) * Y_ph * T_seq)[2,2]# Taking the positive sequence admittance
        
        ((data["branch"])[string(key)])["br_r"] = real(Z)
        ((data["branch"])[string(key)])["br_x"] = imag(Z)
        ((data["branch"])[string(key)])["g_fr"] = real(Y)
        ((data["branch"])[string(key)])["b_fr"] = imag(Y)
        ((data["branch"])[string(key)])["g_to"] = real(Y)
        ((data["branch"])[string(key)])["b_to"] = imag(Y)

    else
        key = branch_dc!(data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
        abcd = eval_abcd(tl, 1e-6*1im)
        n = Int(size(abcd, 1)/2)
        Z = (abcd[1:n,n+1:end])[1,1] / (global_dict["Z"] / 3) # Conversion from AC-side base to DC-side base
        ((data["branchdc"])[string(key)])["r"] = real(Z)
    end


end
