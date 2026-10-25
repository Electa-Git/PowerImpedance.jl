"""
$(TYPEDEF)

Define the state-space interface shared by modular converter models.
"""
abstract type AbstractConverter <: AbstractStateSpace end

is_converter(::AbstractConverter) = true

# Evaluating the admittance of the converter
function eval_abcd(converter :: AbstractConverter, s :: Complex)
    return eval_y(converter, s)
end

function eval_y(converter :: AbstractConverter, s :: Complex)
    Y = eval_parameters(converter, s)
    return Y
end

function timeDelayPadeMatrices(padeOrderNum,padeOrderDen,t_delay,numberVars)

    # Calculation of the state-space representation of a pade approximation with nth-order numerator and nth-order denominator
    # padeOrderNum = Order of the numerator, padeOrderDen= Order of the denominator, t_delay = Time delay duration, numberVars= Variables to be delayed max.2 !
    #
    size_A=padeOrderDen;
    a_k=factorial(padeOrderNum);
    b_l=((factorial(padeOrderDen)*(-1)^padeOrderNum)*(t_delay^(padeOrderNum-padeOrderDen)))/a_k;
    Ad=zeros(size_A,size_A);
    Bd=zeros(size_A,1);
    Bd[end]=1;
    Cd=zeros(1,size_A);
    Dd=b_l;
    Ad[1:end-1,2:end] = Matrix(1.0I, padeOrderDen-1, padeOrderDen-1);
    for i=0:padeOrderDen-1
        a_i=(t_delay^(i-padeOrderDen)*(factorial(padeOrderNum+padeOrderDen-i)*factorial(padeOrderDen)/(factorial(i)*factorial(padeOrderDen-i))))/a_k;
        b_i=(t_delay^(i-padeOrderDen)*((-1)^i)*(factorial(padeOrderNum+padeOrderDen-i)*factorial(padeOrderNum)/(factorial(i)*factorial(padeOrderNum-i))))/a_k;
        Ad[end,i+1] =-a_i;
        Cd[i+1] = (b_i-(a_i*b_l));
    end
    # Result above gives state space in canonical realization, which is ill-conditioned, especially for higher order pades.
    # In order to improve numerical handling, transform state space into modal realization
    # Alternative # TODO: What about Dd?
    sys = ss(Ad,Bd,Cd,Dd)
    sys_modal = modal_form(sys; C1=true)
    Ad = sys_modal[1].A
    Bd = sys_modal[1].B
    Cd = sys_modal[1].C
    if numberVars == 1
        A_Pade=Ad;
        B_Pade=Bd;
        C_Pade=Cd;
        D_Pade=Dd;
    elseif numberVars == 2
        A_Pade=cat(Ad,Ad;dims=[1,2]);
        B_Pade=cat(Bd,Bd;dims=[1,2]);
        C_Pade=cat(Cd,Cd;dims=[1,2]);
        D_Pade=cat(Dd,Dd;dims=[1,2]);
    end

    return A_Pade,B_Pade,C_Pade,D_Pade
end


"""
$(TYPEDSIGNATURES)

Return AC and DC port powers positive into the converter. Taking 603 MW from DC
and delivering 600 MW to AC gives `dc.p = 603` and `ac.p = -600`.
"""
function transform(elemresult, busresult::NamedTuple, global_dict,
        model::AbstractConverter, ::Type{PMACDC}, ::Type{PIACDC})

    acbusresult = busresult.ac # AC bus
    dcbusresult = busresult.dc # DC bus

    Pdc = elemresult["pdc"] * global_dict["S"] / 1e6
    Vm =
        (acbusresult["vm"] * global_dict["V"] / 1e3) *
        sqrt(2)
    θ = acbusresult["va"]
    Vdc =
        dcbusresult["vm"] *
        # data["dcpol"] should be here. const dcpol in powermodels_data.jl
        (dcpol * global_dict["V"] / 1e3)
    Pac = -elemresult["pgrid"] * global_dict["S"] / 1e6
    # PowerModels pgrid/qgrid are absorbed; port values use their signs and
    # pftoinputs negates AC powers to obtain the model's internal pu references.
    Qac = -elemresult["qgrid"] * global_dict["S"] / 1e6

    return (ac = ACPortValues(Vm, θ, -Pac, -Qac), dc = DCPortValues(Vdc, Pdc))
end
