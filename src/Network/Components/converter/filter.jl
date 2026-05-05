############################  filter.jl  ############################

############################  Filter types  ############################

abstract type AbstractMeasurementFilter end

@with_kw mutable struct NoFilter <: AbstractMeasurementFilter
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

############################  Coefficient tables  ############################
# The floating point values were taken from SciPy.
# Each entry corresponds to one overall filter order.
# The stored tuples are the cascade sections:
#   (aᵢ, bᵢ)
# where
#   bᵢ = 0      -> first-order section    1 / (aᵢ*S + 1)
#   bᵢ ≠ 0      -> second-order section   1 / (bᵢ*S^2 + aᵢ*S + 1)
# with S = s / ω_f

const BUTTERWORTH_TABLE = (
    ((1.0000, 0.0000),),
    ((1.4142135623730951, 1.0000000000000000),),
    ((1.0000, 0.0000), (1.0000, 1.0000)),
    ((1.8477590650225735, 1.0000000000000000), (0.7653668647301796, 1.0000000000000000)),
    ((1.0000000000000000, 0.0000000000000000), (1.6180339887498949, 1.0000000000000000), (0.6180339887498949, 1.0000000000000000)),
    ((1.9318516525781366, 1.0000000000000000), (1.4142135623730951, 1.0000000000000000), (0.5176380902050415, 1.0000000000000000))
)

const CHEBYSHEV_TABLE = (
    ((0.9976283451109836, 0.0000000000000000),),
    ((0.9109424019787794, 1.4125335626068893),),
    ((0.3558501550650937, 1.1916479367750799), (3.3487351903980445, 0.0000000000000000)),
    ((0.1886206299189319, 1.1073132983403204), (2.0983726255243650, 5.1025615414320170)),
    ((0.1172187536782796, 1.0683469690235923), (0.7619191964227391, 2.6524600893969073), (5.6328421682993770, 0.0000000000000000)),
    ((0.0800760434214973, 1.0473066248992997), (0.4003122538427246, 1.9163787969084394), (3.2132155032005600, 11.2606523445589170))
)

const BESSEL_TABLE = (
    ((1.0000000000000007, 0.0000000000000000),),
    ((1.3616541287161310, 0.6180339887498953),),
    ((0.7560431664869864, 0.0000000000000000), (0.9996292021942250, 0.4771913591204964)),
    ((1.3396637000153104, 0.4889041513645733), (0.7742539748889071, 0.3889907337152438)),
    ((0.6656387999023018, 0.0000000000000000), (1.1401766958285258, 0.4128450349918194), (0.6215952064218018, 0.3245329581029818)),
    ((1.2217343796721554, 0.3887183710638390), (0.9686070259812813, 0.3504726815531784), (0.5130536555494885, 0.2756407132488260))
)

const CRITICAL_DAMPING_TABLE = (
    ((1.0000000000000000, 0.0000000000000000),),
    ((1.2871885058111654, 0.4142135623730951),),
    ((0.5098245285339587, 0.0000000000000000), (1.0196490570679173, 0.2599210498948732)),
    ((0.8699588840921645, 0.1892071150027210), (0.8699588840921645, 0.1892071150027210)),
    ((0.3856142567346740, 0.0000000000000000), (0.7712285134693481, 0.1486983549970351), (0.7712285134693481, 0.1486983549970351)),
    ((0.6998915581984769, 0.1224620483093730), (0.6998915581984769, 0.1224620483093730), (0.6998915581984769, 0.1224620483093730))
)

############################  Table-based filter specs  ############################

@with_kw mutable struct Butterworth <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = BUTTERWORTH_TABLE
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

@with_kw mutable struct Chebyshev <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = CHEBYSHEV_TABLE
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

@with_kw mutable struct Bessel <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = BESSEL_TABLE
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end

@with_kw mutable struct CriticalDamping <: AbstractMeasurementFilter
    order::Int = 1
    ωc::Float64 = 100 * π
    table::Tuple = CRITICAL_DAMPING_TABLE
    A::Matrix{Float64} = zeros(0, 0)
    B::Matrix{Float64} = zeros(0, 1)
    C::Matrix{Float64} = zeros(1, 0)
    D::Matrix{Float64} = Matrix{Float64}(I, 1, 1)
end


##############################################  Implemenation of the Filter State Space  ###############################################
"""
    measurement_filter_ss(filter)

Return `(A, B, C, D)` for a single-channel measurement filter.

- `NoFilter()` gives a static pass-through: y = u
- all other filters are built from the normalized table:
      G(S) = ∏ 1 / (bᵢ S² + aᵢ S + 1),   with S = s / ωf
"""
function measurement_filter_ss(filter::NoFilter)
    filter.A = zeros(Float64, 0, 0)
    filter.B = zeros(Float64, 0, 1)
    filter.C = zeros(Float64, 1, 0)
    filter.D = Matrix{Float64}(I, 1, 1)

    return filter
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
    filter.A, filter.B, filter.C, filter.D = Matrix(sys.A), Matrix(sys.B), Matrix(sys.C), Matrix(sys.D)

    return filter
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
