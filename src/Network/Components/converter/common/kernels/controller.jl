############################  common/kernels/controller.jl  ############################

#=
Shared controller primitives used by converter models.

This file contains controller data containers that are independent of a
particular converter topology. TLC and MMC control blocks can use these types
without depending on each other's implementation files.
=#

export PIControl

"""
$(TYPEDEF)

Store proportional-integral controller gains.

$(TYPEDFIELDS)

# Notes

`PIControl` is intentionally a lightweight immutable parameter container.
State variables for the integrator live in the state-space blocks that use the
controller.
"""
@with_kw struct PIControl
    "Proportional gain for the normalized input and output signals \\[dimensionless\\]."
    Kp :: Float64  = 0  # Proportional gain
    "Integral gain for normalized signals \\[s⁻¹\\]."
    Ki :: Float64  = 0  # Integral gain
end
