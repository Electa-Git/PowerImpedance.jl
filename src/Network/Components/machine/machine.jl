abstract type Machine end

function eval_abcd(machine :: Machine, s :: Complex)
    return eval_y(machine, s)
end

function eval_y(machine :: Machine, s :: Complex)
    Y = eval_parameters(machine, s)
    return Y
end


