export Setpoint

# PowerBlocks things, before finding proper place
### PowerBlocks

# elecdomainpb(elem::Element) = is_three_phase(elem) ? PB.AC : PB.DC

# PB.DataInputStyle(::Network) = PB.IsDataInput()
# PB.DataInputStyle(::Element) = PB.IsDataInput()
# PB.DataInputStyle(::StateSpaceABCD) = PB.IsDataInput()
# PB.CompositeDataStyle(::Network) = PB.IsCompositeData()

struct PIACDC end
# PB.ToolType(::PIACDC) = IsTool()

struct PMACDC end
# PB.ToolType(::PMACDC) = IsTool()


"Abstract supertype for every physical component model stored in an `Element`."
abstract type AbstractElementModel end

abstract type AbstractLinFreqDomain <: AbstractElementModel end

abstract type AbstractStateSpace <: AbstractElementModel end

"""
    Setpoint(; Pac=missing, Qac=missing, θac=missing, Vac=missing,
             Pdc=missing, Vdc=missing)

Store an AC/DC steady-state operating point.

# Arguments

- `Pac`: AC active power `\\[MW\\]`.
- `Qac`: AC reactive power `\\[MVAr\\]`.
- `θac`: AC voltage angle `\\[rad\\]`.
- `Vac`: phase-voltage amplitude `\\[kV\\]`.
- `Pdc`: DC active power `\\[MW\\]`.
- `Vdc`: DC voltage `\\[kV\\]`.

Every field defaults to `missing`; the power-flow pipeline fills quantities
that are not fixed by the component's control mode.
"""
@with_kw struct Setpoint
	"AC active power `\\[MW\\]`."
    Pac ::Union{Float64, Missing} = missing              # active power [MW]
	"AC reactive power `\\[MVAr\\]`."
    Qac ::Union{Float64, Missing} = missing                # reactive power [MVA]
	"AC voltage angle `\\[rad\\]`."
    θac ::Union{Float64, Missing} = missing
	"AC phase-voltage amplitude `\\[kV\\]`."
    Vac ::Union{Float64, Missing} = missing#220*sqrt(2/3)             # AC voltage, amplitude [kV]

	"DC active power `\\[MW\\]`."
    Pdc::Union{Float64, Missing} = missing
	"DC voltage `\\[kV\\]`."
    Vdc::Union{Float64, Missing} = missing
   
end

@with_kw struct SetpointPU # Per-unitized setpoint used internally
    p_ac::Float64 = 0
    q_ac::Float64 = 0
    θ_ac::Float64 = 0
    v_ac::Float64 = 1
    
    p_dc::Float64 = 0
    v_dc::Float64 = 1
end
"""
    Limits(; P_min=0.9, P_max=1.1, Q_min=-0.5, Q_max=0.5)

Store active- and reactive-power limits in the component's per-unit base.
"""
@with_kw struct Limits
	"Minimum active power `\\[pu\\]`."
    P_min ::Float64 = 0.9         # min active power output [pu]
	"Maximum active power `\\[pu\\]`."
    P_max ::Float64 = 1.1          # max active power output [pu]
	"Minimum reactive power `\\[pu\\]`."
    Q_min ::Float64 = -0.5          # min reactive power output [pu]
	"Maximum reactive power `\\[pu\\]`."
    Q_max ::Float64 = 0.5           # max reactive power output [pu]
end


"""
$(TYPEDEF)

Represent one physical component as a multiport element with ABCD blocks,
network pins, coordinate-transformation state, operating-point data, and
connection state.

$(TYPEDFIELDS)
"""
mutable struct Element{T<: Any} #TODO: consider making this an immutable struct, and use a constructor to handle the logic of setting the fields
    "Element name assigned when inserted into a network."
    symbol::Symbol
    "Mapping from local pin names to network-node names."
    pins :: Dict{Symbol, Symbol}
    "Number of externally visible input pins."
    input_pins :: Int
    "Number of externally visible output pins."
    output_pins :: Int
    "Physical component model."
    element_model :: T #AbstractElementModel  # component defined type
    "ABCD ``\\mathbf{A}`` block."
    A::Matrix{ComplexF64}  
    "ABCD ``\\mathbf{B}`` block."
    B::Matrix{ComplexF64} 
    "ABCD ``\\mathbf{C}`` block."
    C::Matrix{ComplexF64} 
    "ABCD ``\\mathbf{D}`` block."
    D::Matrix{ComplexF64} 
    "Whether the element exposes transformed external coordinates."
    transformation :: Bool
    "Whether the element participates in network construction."
    connection :: Bool # True = Element is connected, False= Element is disconnected 
    "Steady-state operating point."
    setpoint::Setpoint
    "Power-flow operating limits."
    limits::Limits
    @doc """
        Element(; element_model=nothing, element_value=nothing, kwargs...)

    Construct an `Element` around one physical component model.

    # Arguments

    - `element_model`: component model stored by the element.
    - `element_value`: deprecated alias for `element_model`.
    - `kwargs`: values for element fields such as `input_pins`, `output_pins`,
      `transformation`, `connection`, `setpoint`, and `limits`.

    # Returns

    - An initialized `Element` whose pins reflect the requested terminal counts.

    # Notes

    When `transformation=true`, the externally visible input and output pin
    counts are each reduced by one to match the transformed representation.

    # Errors

    - Throws `UndefKeywordError` if neither component-model keyword is supplied.
    - Throws `ArgumentError` when both model keywords differ or a keyword is not
      an `Element` field.
    """
    function Element(; element_model=nothing, element_value=nothing, args...)
        

        model =
            element_model !== nothing ? element_model :
            element_value !== nothing ? element_value :
            throw(UndefKeywordError(:element_model))

        if element_model !== nothing && element_value !== nothing && !(element_model === element_value)
            throw(ArgumentError("Both `element_model` and legacy `element_value` were provided with different values."))
        end

        elem = new{typeof(model)}()

        elem.element_model = model
        elem.symbol = Symbol()
        elem.transformation = false
        elem.connection = true
        elem.setpoint = Setpoint()
        elem.limits = Limits()
        elem.A, elem.B, elem.C, elem.D = fill(Array{ComplexF64}(undef, 0, 0), 4)

        for (key, val) in pairs(args)
            if key in propertynames(elem)
                setfield!(elem, key, val)
            else
                throw(ArgumentError("The property name $(key) is not defined."))
            end
        end

        if elem.transformation
            elem.input_pins -= 1
            elem.output_pins -= 1
        end

        if !isdefined(elem, :pins)
            elem.pins = merge(
                Dict{Symbol, Symbol}(Symbol(string("1.", i)) => Symbol() for i in 1:nip(elem)),
                Dict{Symbol, Symbol}(Symbol(string("2.", i)) => Symbol() for i in 1:nop(elem)),
            )
        end

        return elem
    end
end

is_statespace(elem::Element) = elem.element_model isa AbstractStateSpace
is_linfreqdomain(elem::Element) = elem.element_model isa AbstractLinFreqDomain

for (n,m) in Dict(:nip => :input_pins, :nop => :output_pins)
  @eval ($n)(e::Element) = e.$m # creation of functions nip() and nop(), fetching the input_pins and output_pins parameters within the element structure
end
np(e::Element) = nip(e) + nop(e) # total number of pins

function add!(elem::Element, sym::Symbol, value::Any)
  if (sym in propertynames(elem))
    setfield!(elem, sym, value)
  end
end

function get_nodes(element::Element) # Returns all nodes connected to the element
    return values(element.pins)
end

function get_nodes(element::Element, pin::Symbol) # Returns all nodes connected to the element, except the one specified by pin
    array = Symbol[]
    for (key, val) in element.pins
        (pin != key) && push!(array, val)
        # !occursin(string(pin)[1:2], string(key)) && push!(array, val)
    end
    return array
end


####### NEW GENERAL ELEMENT FUNCTIONS ###########################

# this is p.u.
#= function eval_y(elem::Element, s::Complex)
    n = size(elem.A, 1)
    Iₙ = Matrix{ComplexF64}(I, n, n)
    return elem.C * ((s * Iₙ - elem.A) \ elem.B) + elem.D
end =#

# PSCAD requires SI results
function eval_y(elem::Element{<:AbstractStateSpace}, s::Complex; SI_units::Bool=true)
    n = size(elem.A, 1)
    Iₙ = Matrix{ComplexF64}(I, n, n)
    Y = elem.C * ((s * Iₙ - elem.A) \ elem.B) + elem.D
    Y = Matrix{ComplexF64}(Y)
    
    if !SI_units
        return Y
    end

    model = elem.element_model

    if isa(model, TLC)
        elec = model.elec

        vACbase = elec.vACbase
        iACbase = 2 * elec.Sbase / (3 * vACbase)
        iDCbase = elec.Sbase / elec.vDCbase


        # row scaling = output current bases
        Y[1, :]   .*= iDCbase
        Y[2:3, :] .*= iACbase

        # column scaling = input voltage bases
        Y[:, 1]   ./= elec.vDCbase
        Y[:, 2:3] ./= vACbase
    end

    if isa(model, MMC)
        elec = model.elec

        
        

        iACbase = 2 * elec.Sbase / (3 * elec.vAC_base)
        iDCbase = elec.Sbase / elec.vDC_base

        # row scaling = output current bases
        Y[1, :]   .*= iDCbase
        Y[2:3, :] .*= iACbase

        # column scaling = input voltage bases
        Y[:, 1]   ./= elec.vDC_base
        Y[:, 2:3] ./= (elec.vAC_base / elec.turnsRatio)

    end

    return Y
end

function eval_y(elem::Element{<:AbstractLinFreqDomain}, s::Complex; SI_units::Bool=true)
    Y = get_y(elem, s)
    return Y
end

################### ABCD functions ################################
function get_abcd(element::Element, s::Complex)
    if isa(element.element_model, AbstractStateSpace) && !isempty(element.A)
        return eval_y(element, s)
    end

    if element.transformation
        if np(element) == 2
            abcd = eval_abcd(element.element_model, s)
            return transformation_dc(abcd)
        elseif is_three_phase(element)
            ω₀ = 100 * π
            abcd₁ = eval_abcd(element.element_model, s + 1im * ω₀)
            abcd₂ = eval_abcd(element.element_model, s - 1im * ω₀)
            return transformation_dq(abcd₁, abcd₂)
        end
    else
        abcd = eval_abcd(element.element_model, s)
    end
    return abcd
end

function nip_abcd(e::Element)
    if isa(e.element_model, MMC) || isa(e.element_model, TLC)
        return 3
    else
        return 2nip(e)
    end
    # return 2nip(e)
end

function nop_abcd(e::Element)
    if isa(e.element_model, MMC) || isa(e.element_model, TLC)
        return 3
    else
        return 2nop(e)
    end
    # return 2nop(e)
end
np_abcd(e::Element) = Int((nip_abcd(e) + nop_abcd(e))/2) # number pins

########################## Y functions #############################

function get_y(element :: Element, s :: Complex)

    abcd = get_abcd(element, s) # Return ABCD for passives, returns Y for actives
    
    if is_converter(element) || is_generator(element) # If converter or generator, return Y
        return abcd
    end

    return abcd_to_y(abcd)
end

######################### Element type #############################

## New islinear functions for element
# Default can be overridden for specific element types
islinear(elem::Element{<:AbstractStateSpace}) = false
islinear(elem::Element{<:AbstractLinFreqDomain}) = true

function is_passive(element :: Element)
    (isa(element.element_model, MMC) ||
     isa(element.element_model, Blackbox_MMC) ||
     isa(element.element_model, TLC) ||
     isa(element.element_model, Source) ||
     isa(element.element_model, InductionMachine) ||
     isa(element.element_model, SynchronousMachine)) && return false
    
    return  true
end

function is_active(element :: Element)
    (isa(element.element_model, MMC) ||
     isa(element.element_model, Blackbox_MMC) ||
     isa(element.element_model, TLC) ||
     isa(element.element_model, Source) ||
     isa(element.element_model, InductionMachine) ||
     isa(element.element_model, SynchronousMachine)) && return true
    
    return false
end

function is_source(element :: Element)
    isa(element.element_model, Source)
end

function is_converter(element :: Element)
    (isa(element.element_model, MMC) ||
     isa(element.element_model, TLC) ||
     isa(element.element_model, Blackbox_MMC))
end


function is_generator(element :: Element)
    isa(element.element_model, SynchronousMachine)
end
 
function is_inductionmachine(element :: Element)
    return isa(element.element_model, InductionMachine)
end

function is_impedance(element :: Element)
    isa(element.element_model, Impedance) && !any(occursin("gnd", string(x)) for x in element.pins)
end

function issingleport(element :: Element)
    isa(element.element_model, SynchronousMachine) || isa(element.element_model, Source) || isa(element.element_model, InductionMachine)
end

function is_load(element :: Element)
    isa(element.element_model, Impedance) && any(occursin("gnd", string(x)) for x in element.pins)
end

function is_three_phase(element :: Element)
    (np(element) == 6) || (np(element) == 4 && (element.transformation) && !is_converter(element)) && return true
    return false
end
