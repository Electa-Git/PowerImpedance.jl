export CirculatingCurrentSuppressionControl, ZeroSequenceCurrentControl, CirculatingCurrentControl, 
    NoZeroSequenceCurrentControl, NoCirculatingCurrentSuppressionControl

"""
$(TYPEDEF)

Disable zero-sequence-current regulation and request half the measured DC voltage.

$(TYPEDFIELDS)
"""
struct NoZeroSequenceCurrentControl <: AbstractInnerCurrentControl end
statenames(::NoZeroSequenceCurrentControl) = ()
function state_space!(F, x, inputs, b::NoZeroSequenceCurrentControl, conv::AbstractMMC)
    return (vMΣ_z_ref = inputs.meas.v_dc_f/2,)
end

"""
$(TYPEDEF)

Disable circulating-current suppression and return zero d/q voltage references.

$(TYPEDFIELDS)
"""
struct NoCirculatingCurrentSuppressionControl <: AbstractInnerCurrentControl end
statenames(::NoCirculatingCurrentSuppressionControl) = ()
function state_space!(F, x, inputs, b::NoCirculatingCurrentSuppressionControl, conv::AbstractMMC)
    return (vMΣ_d_ref_c = 0, vMΣ_q_ref_c = 0, )
end

"""
$(TYPEDEF)

Regulate the zero-sequence circulating current with PI feedback and DC-voltage
feedforward.

$(TYPEDFIELDS)
"""
struct ZeroSequenceCurrentControl <: AbstractInnerCurrentControl
    "PI gains for normalized signals; proportional gain is \\[dimensionless\\] and integral gain is \\[s⁻¹\\]."
    pi_control::PIControl
end
statenames(::ZeroSequenceCurrentControl) = (:ξ_iΣ_z,)

"""
$(TYPEDEF)

Suppress circulating currents in the converter's negative-double-frequency
frame. The PI errors are `ref[1] - iΣ_d_c` and `ref[2] - iΣ_q_c`.
The voltage references include the arm-inductance decoupling terms.
The current references are constants with default `ref=(0.0, 0.0)` \\[dimensionless\\],
suppressing both currents to zero.

$(TYPEDFIELDS)
"""
struct CirculatingCurrentSuppressionControl <: AbstractInnerCurrentControl
    "Current PI gains in the converter per-unit system."
    pi_control::PIControl
    "Converter-frame d/q circulating-current references \\[dimensionless\\]."
    ref::Tuple{Float64,Float64}
end
CirculatingCurrentSuppressionControl(pi_control::PIControl; ref = (0.0, 0.0)) =
    CirculatingCurrentSuppressionControl(pi_control, Tuple(Float64.(ref)))
"""
$(TYPEDSIGNATURES)

Construct a `CirculatingCurrentSuppressionControl` component from the supplied
parameters.

# Arguments

- `pi_control`: PI gains for normalized signals; `Kp` is \\[dimensionless\\] and `Ki` is
  \\[s⁻¹\\].
- `ref`: Tuple of constant d/q circulating-current references in the converter frame
  \\[dimensionless\\]. Default: `(0.0, 0.0)`.

# Returns

- A `CirculatingCurrentSuppressionControl` instance.

# Notes

The PI parameter container is also accepted as the first positional argument.

# Examples

```julia
using PowerImpedance
component = CirculatingCurrentSuppressionControl(pi_control=PIControl(Kp=0.1, Ki=10.0))
```
"""
CirculatingCurrentSuppressionControl(; pi_control::PIControl, ref = (0.0, 0.0)) =
    CirculatingCurrentSuppressionControl(pi_control; ref)
statenames(::CirculatingCurrentSuppressionControl) = (:ξ_iΣ_d, :ξ_iΣ_q)

### Lower level structures ###
#TODO: update the equations in comments to match the new version (including taking into account that modulation is now done in a specific function)
"""
$(TYPEDSIGNATURES)

Evaluate MMC circulating-current suppression, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `meas`: Filtered measurement signals on converter bases \\[dimensionless\\]; angle
  signals use \\[rad\\].
- `b`: The `CirculatingCurrentSuppressionControl` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `vMΣ_d_ref_c`: Converter voltage reference \\[dimensionless\\].
- `vMΣ_q_ref_c`: Converter voltage reference \\[dimensionless\\].

# Notes

```math
\\dot{\\xi}_{d,q}=K_i(i_{d,q}^{ref}-i_{d,q}),\\quad v_d^{ref}=-\\xi_d-K_p e_d+2L_{arm}i_q,\\quad v_q^{ref}=-\\xi_q-K_p e_q-2L_{arm}i_d.
```

Currents are first rotated by negative twice the synchronization angle. Electrical
quantities use converter bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC()).element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
block = CirculatingCurrentSuppressionControl(pi_control=PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = meas
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, meas, b::CirculatingCurrentSuppressionControl, conv::AbstractMMC) 
    (; ξ_iΣ_d, ξ_iΣ_q, iΣ_d, iΣ_q) = x
    Δθ_c = syncangle(conv.sync, x)
    iΣ_d_ref, iΣ_q_ref = b.ref

    T_2θ = [cos(-2Δθ_c) -sin(-2Δθ_c); sin(-2Δθ_c) cos(-2Δθ_c)];
    iΣ_d_c, iΣ_q_c = T_2θ * [iΣ_d, iΣ_q]

    F[1] = (b.pi_control.Ki) * (iΣ_d_ref - iΣ_d_c)
    F[2] = (b.pi_control.Ki) * (iΣ_q_ref - iΣ_q_c)
    # vMΣ_d_ref = 2/Vdc*(- Ki_Σ * xiΣ_d - Kp_Σ * (iΣ_d_ref -  iΣ_d) + 2*Larm*iΣ_q)
    # vMΣ_q_ref = 2/Vdc*(- Ki_Σ * xiΣ_q - Kp_Σ * (iΣ_q_ref -  iΣ_q) - 2*Larm*iΣ_d)
    # Assuming constant w
    vMΣ_d_ref_c = (- ξ_iΣ_d - b.pi_control.Kp * (iΣ_d_ref - iΣ_d_c) + 2 * conv.elec.Lₐᵣₘ * iΣ_q_c)
    vMΣ_q_ref_c = (- ξ_iΣ_q - b.pi_control.Kp * (iΣ_q_ref - iΣ_q_c) - 2 * conv.elec.Lₐᵣₘ * iΣ_d_c)

    # Output are in converter reference frame!
    return (vMΣ_d_ref_c=vMΣ_d_ref_c, vMΣ_q_ref_c=vMΣ_q_ref_c)
end

"""
$(TYPEDSIGNATURES)

Evaluate MMC zero-sequence current control, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `b`: The `ZeroSequenceCurrentControl` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `vMΣ_z_ref`: Converter voltage reference \\[dimensionless\\].

# Notes

```math
e=i_{\\Sigma z}^{ref}-i_{\\Sigma z},\\quad \\dot{\\xi}=K_i e,\\quad v_{\\Sigma z}^{ref}=v_{dc,f}/2-K_p e-\\xi.
```

Current and voltage use converter bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC()).element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
block = ZeroSequenceCurrentControl(PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, out_Wtot=(iΣ_z_ref=0.1/3,))
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, b::ZeroSequenceCurrentControl, conv::AbstractMMC)
    (; meas, out_Wtot) = inputs
    (; ξ_iΣ_z, iΣ_z) = x
    iΣ_z_ref, v_dc_f = out_Wtot.iΣ_z_ref, meas.v_dc_f

    F[1] = b.pi_control.Ki * (iΣ_z_ref - iΣ_z);
    # vMΣ_z_ref = 2/Vdc*(Vdc/2 - Kp_Σz*(iΣ_z_ref - iΣ_z) - Ki_Σz * xiΣ_z),
    return ( vMΣ_z_ref = (v_dc_f/2 - b.pi_control.Kp *(iΣ_z_ref - iΣ_z) - ξ_iΣ_z), )
end


"""
$(TYPEDEF)

Combine sum- and difference-energy current references in a rotating-frame
circulating-current PI controller.

$(TYPEDFIELDS)
"""
struct CirculatingCurrentControl <: AbstractInnerCurrentControl
    "PI gains for normalized signals; proportional gain is \\[dimensionless\\] and integral gain is \\[s⁻¹\\]."
    pi_control::PIControl
end
statenames(::CirculatingCurrentControl) = (:ξ_iΣ_d, :ξ_iΣ_q, :ξ_iΣ_z)

"""
$(TYPEDSIGNATURES)

Evaluate MMC circulating-current PI control, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `b`: The `CirculatingCurrentControl` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `vMΣ_d_ref_c`: Converter voltage reference \\[dimensionless\\].
- `vMΣ_q_ref_c`: Converter voltage reference \\[dimensionless\\].
- `vMΣ_z_ref`: Converter voltage reference \\[dimensionless\\].

# Notes

```math
\\dot{\\boldsymbol\\xi}=K_i(\\mathbf i^{ref}-\\mathbf i)-J_{-2\\omega}\\boldsymbol\\xi,\\quad \\mathbf v^{ref}=-[\\boldsymbol\\xi+K_p(\\mathbf i^{ref}-\\mathbf i)]+[0,0,v_{dc,f}/2]^T.
```

Sum- and difference-energy outputs are added to form the three-component current
reference. ``J_{-2ω}`` is the implemented double-frequency rotation matrix; all
electrical quantities use converter bases \\[dimensionless\\].

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC()).element_model
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.SetpointPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, setpoint_pu=point)
block = CirculatingCurrentControl(PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, sync=sync,
    out_wΣ=(iΣ_d_dc_ref=0.0, iΣ_q_dc_ref=0.0, iΣ_z_dc_ref=0.1/3),
    out_wΔ=(iΣ_d_ac_ref=0.0, iΣ_q_ac_ref=0.0, iΣ_z_ac_ref=0.0))
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, b::CirculatingCurrentControl, conv::AbstractMMC)
    (; sync, meas, out_wΣ, out_wΔ) = inputs
    ξ_iΣ = [x.ξ_iΣ_d, x.ξ_iΣ_q, x.ξ_iΣ_z]
    iΣ = [x.iΣ_d, x.iΣ_q, x.iΣ_z] #TODO implement filters?
    iΣ_ref = [out_wΣ.iΣ_d_dc_ref + out_wΔ.iΣ_d_ac_ref, out_wΣ.iΣ_q_dc_ref + out_wΔ.iΣ_q_ac_ref, out_wΣ.iΣ_z_dc_ref + out_wΔ.iΣ_z_ac_ref]    
    Ki_iΣ = b.pi_control.Ki


    J = [ 0 1 0
         -1 0 0
          0 0 0]
    J_min2ω = -2 * conv.elec.ωbase * J

    F[1:3] = Ki_iΣ * (iΣ_ref - iΣ) - J_min2ω * ξ_iΣ

    vMΣ_ref = -1 * ( ξ_iΣ + b.pi_control.Kp * (iΣ_ref - iΣ) ) + [0, 0, meas.v_dc_f/2] # This last term is added to match PSCAD implementation (the minus sign & + v_dc_f/2 is in the modulation block in PSCAD)

    return (vMΣ_d_ref_c = vMΣ_ref[1], vMΣ_q_ref_c = vMΣ_ref[2], vMΣ_z_ref = vMΣ_ref[3])
    
end
