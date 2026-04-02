############################  filter.jl  ############################

using Parameters
using ControlSystemsBase #TODO: @Luis Some of these are imported already : check PowerImpedance.jl
using LinearAlgebra

############################  Filter types  ############################

abstract type AbstractMeasurementFilter end

struct NoFilter <: AbstractMeasurementFilter end

############################  Coefficient tables  ############################
# Each entry corresponds to one overall filter order.
# The stored tuples are the cascade sections:
#   (aᵢ, bᵢ)
# where
#   bᵢ = 0      -> first-order section    1 / (aᵢ*S + 1)
#   bᵢ ≠ 0      -> second-order section   1 / (bᵢ*S^2 + aᵢ*S + 1)
# with S = s / ω_f

const BUTTERWORTH_TABLE = (
    ((1.0000, 0.0000),),
    ((1.4142, 1.0000),),
    ((1.0000, 0.0000), (1.0000, 1.0000)),
    ((1.8478, 1.0000), (0.7654, 1.0000)),
    ((1.0000, 0.0000), (1.6180, 1.0000), (0.6180, 1.0000)),
    ((1.9319, 1.0000), (1.4142, 1.0000), (0.5176, 1.0000))
)

const CHEBYSHEV_TABLE = (
    ((1.0000, 0.0000),),
    ((1.0650, 1.9305),),
    ((3.3496, 0.0000), (0.3559, 1.1923)),
    ((2.1853, 5.5339), (0.1964, 1.2009)),
    ((5.6334, 0.0000), (0.7620, 2.6530), (0.1172, 1.0686)),
    ((3.2721, 11.6773), (0.4077, 1.9873), (0.0815, 1.0861))
)

const BESSEL_TABLE = (
    ((1.0000, 0.0000),),
    ((1.3617, 0.6180),),
    ((0.7560, 0.0000), (0.9996, 0.4772)),
    ((1.3397, 0.4889), (0.7743, 0.3890)),
    ((0.6656, 0.0000), (1.1402, 0.4128), (0.6216, 0.3245)),
    ((1.2217, 0.3887), (0.9686, 0.3505), (0.5131, 0.2756))
)

const CRITICAL_DAMPING_TABLE = (
    ((1.0000, 0.0000),),
    ((1.2872, 0.4142),),
    ((0.5098, 0.0000), (1.0197, 0.2599)),
    ((0.8700, 0.1892), (0.8700, 0.1892)),
    ((0.3856, 0.0000), (0.7712, 0.1487), (0.7712, 0.1487)),
    ((0.6999, 0.1225), (0.6999, 0.1225), (0.6999, 0.1225))
)

############################  Table-based filter specs  ############################

@with_kw struct Butterworth <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = BUTTERWORTH_TABLE
end

@with_kw struct Chebyshev <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = CHEBYSHEV_TABLE
end

@with_kw struct Bessel <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = BESSEL_TABLE
end

@with_kw struct CriticalDamping <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = CRITICAL_DAMPING_TABLE
end


##############################################  Implemenation of the Filter State Space  ###############################################
"""
    measurement_filter_ss(filter)

Return `(A, B, C, D)` for a single-channel measurement filter.

- `NoFilter()` gives a static pass-through: y = u
- all other filters are built from the normalized table:
      G(S) = ∏ 1 / (bᵢ S² + aᵢ S + 1),   with S = s / ωf
"""
function measurement_filter_ss(::NoFilter)
    A = zeros(Float64, 0, 0)
    B = zeros(Float64, 0, 1)
    C = zeros(Float64, 1, 0)
    D = Matrix{Float64}(I, 1, 1)

    return A, B, C, D
end

function measurement_filter_ss(filter::AbstractMeasurementFilter)
    1 <= filter.order <= length(filter.table) || throw(ArgumentError(
        "Unsupported filter order $(filter.order). Supported orders are 1:$(length(filter.table))"
    ))

    ωf = filter.ωc
    sections = filter.table[filter.order]

    G = tf([1.0], [1.0])

    for (a, b) in sections
        G *= iszero(b) ?
            tf([ωf],   [a, ωf]) :
            tf([ωf^2], [b, a * ωf, ωf^2])
    end

    sys = ss(G)

    return Matrix(sys.A), Matrix(sys.B), Matrix(sys.C), Matrix(sys.D)
end



## TODO: Legacy: Remove this later

function butterworthMatrices(buttOrder,ω_c,numberVars)

    # Calculation of the state-space representation of a n-order butterworth filter with a gain of 1.
    # buttOrder = Order of butterworth filter, ω_c= Cutoff frequency of the filter in [rad/s], numberVars= Variables to be filtered max.2 !
   
    size_A=buttOrder;
    Ab=zeros(size_A,size_A);
    Bb=zeros(size_A,1);
    Bb[end]=1;
    Cb=zeros(1,size_A);
    Cb[1]=1;
    Db=0;
    Ab[1:end-1,2:end] = Matrix(1.0I, buttOrder-1, buttOrder-1);
    
    γ=pi/(2*buttOrder)
    
    # Calculation of the matrix entries in A 
    # Calculation of the coefficients of the denominator polynominal aₙ*sⁿ+...+a₀
    for i=0:buttOrder-1
    
        
        if i==0
    
            a_i = 1 
            Ab[end, i+1] = -a_i;
        
        else 
    
            a_i = 1; 
            for μ=1:i
    
                a_i=a_i*cos((μ-1)γ)/(sin(μ*γ));
            
            end
            Ab[end, i+1] = -a_i * (1/ω_c)^(i)
    
        end
    
    
    end
    
    # Convert from aₙ*sⁿ+...+a₀ to sⁿ+...+a₀ by dividing numerator and denominator by 1/aₙ
    Ab[end, 1:end]=Ab[end, 1:end]*(ω_c)^buttOrder;
    Cb[1]=Cb[1]*(ω_c)^buttOrder;
    

    # Controllable canonical form can create problems while solving for MMC steady-state, espec. when high-order pade delay approximation is used. 
    # Related to high conditioning number of controllable canonical form.
    # Transformation to modal form, which results in lower conditioning number.
    # sys = ss(Ab,Bb,Cb,Db)
    # sys_modal = modal_form(sys;C1 = true)
    # Ab= sys_modal[1].A
    # Bb = sys_modal[1].B
    # Cb = sys_modal[1].C
    # Db = sys_modal[1].D


    # Adjust matrices for multiple,independent inputs, so far only up to 2 possible
    if numberVars == 1 #One input, one output
        A_butt=Ab;
        B_butt=Bb;
        C_butt=Cb;
        D_butt=Db;
    elseif numberVars == 2 #Two inputs, two outputs 
        A_butt=cat(Ab,Ab;dims=[1,2]);
        B_butt=cat(Bb,Bb;dims=[1,2]);
        C_butt=cat(Cb,Cb;dims=[1,2]);
        D_butt=cat(Db,Db;dims=[1,2]);
    end
    
    return A_butt,B_butt,C_butt,D_butt
   
end 