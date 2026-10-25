"""
$(TYPEDEF)

Select the native PowerImpedance operating-point representation.

$(TYPEDFIELDS)
"""
struct PIACDC end

"""
$(TYPEDEF)

Select the PowerModelsACDC power-flow data representation.

$(TYPEDFIELDS)
"""
struct PMACDC end


"""
$(TYPEDEF)

Common parent of the direct frequency-domain and state-space model interfaces.
The legacy `Machine` hierarchy is separate.
"""
abstract type AbstractElementModel end

"""
$(TYPEDEF)

Define a component evaluated directly in the complex-frequency domain.
"""
abstract type AbstractLinFreqDomain <: AbstractElementModel end

"""
$(TYPEDEF)

Define a component represented by nonlinear state and output equations.
"""
abstract type AbstractStateSpace <: AbstractElementModel end

"""
$(TYPEDEF)

Store active- and reactive-power limits using the component adapter's convention.
Source, TLC and synchronous-machine adapters interpret active limits in \\[MW\\] and
reactive limits in \\[MVAr\\]. The MMC adapter multiplies these limits by its power base,
interpreting them as per-unit values \\[dimensionless\\] for its power bounds.

$(TYPEDFIELDS)
"""
@with_kw struct Limits
    "Minimum active power: sources/TLC \\[MW\\], MMC \\[dimensionless\\]."
    P_min ::Float64 = 0.9         # min active power output [pu]
    "Maximum active power: sources/TLC \\[MW\\], MMC \\[dimensionless\\]."
    P_max ::Float64 = 1.1          # max active power output [pu]
    "Minimum reactive power: sources/TLC \\[MVAr\\], MMC \\[dimensionless\\]."
    Q_min ::Float64 = -0.5          # min reactive power output [pu]
    "Maximum reactive power: sources/TLC \\[MVAr\\], MMC \\[dimensionless\\]."
    Q_max ::Float64 = 0.5           # max reactive power output [pu]
end
