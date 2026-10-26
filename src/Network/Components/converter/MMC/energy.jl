export NoTotalEnergyControl, TotalEnergyControl, ΣEnergyControl, ΔEnergyControl

"""
$(TYPEDEF)

Define the interface for MMC energy-control blocks.
"""
abstract type AbstractEnergyControl             <: AbstractStateSpace end

"""
$(TYPEDEF)

Disable total-energy regulation and return a zero zero-sequence-current reference.

$(TYPEDFIELDS)
"""
struct NoTotalEnergyControl <: AbstractEnergyControl end
statenames(::NoTotalEnergyControl) = ()
function state_space!(F, x, meas, b::NoTotalEnergyControl, conv::AbstractMMC)
    return (iΣ_z_ref = 0,)
end

"""
$(TYPEDEF)

Regulate total arm energy with a zero-sequence current reference in \\[dimensionless\\].
The default arm-energy reference is `ref = 1` \\[dimensionless\\].
With `power_filter = NoFilter()`, feedforward uses the filtered AC-power
measurement with unchanged state count. Other filters act independently on
measured AC voltage-current
products to avoid cascaded power-measurement filters.

$(TYPEDFIELDS)

# Notes

The current reference is

```math
i_{Σz}^{ref} = \\frac{K_p(W^{ref}-W)+ξ_W+P_f}{3V_{dc,f}},
```

where ``W`` denotes total arm energy, ``W^{ref}`` its reference and ``ξ_W``
the PI integral state. Filtered active power ``P_f`` and filtered DC voltage
``V_{dc,f}`` use the converter's per-unit bases, as do the energy and PI terms.
"""
struct TotalEnergyControl{F<:AbstractMeasurementFilter} <: AbstractEnergyControl
    "Energy PI gains in the converter per-unit system."
    pi_control::PIControl
    "Total arm-energy reference \\[dimensionless\\]."
    ref::Float64
    "Independent filter for active-power feedforward. Cutoff in \\[rad/s\\]."
    power_filter::F
    # Legacy feedforward is independent even when its filter has no states.
    "Whether power feedforward uses an independent voltage-current product or the shared
    active-power measurement."
    _independent_power::Bool
end

"""
$(TYPEDSIGNATURES)

Construct a `TotalEnergyControl` component from the supplied parameters.

# Arguments

- `pi_control`: PI gains for normalized signals. `Kp` is \\[dimensionless\\] and `Ki` is
  \\[s⁻¹\\].
- `ref`: Controller reference on the converter base \\[dimensionless\\]. Default: `1`.
- `power_filter`: Independent active-power feedforward filter. Default: `NoFilter()`.

# Returns

- A `TotalEnergyControl` instance.

# Notes

The positional form `TotalEnergyControl(pi_control, ref)` is also accepted. Both
arguments are required in that form.

# Examples

```julia
using PowerImpedance
component = TotalEnergyControl(pi_control=PIControl(Kp=0.1, Ki=10.0))
```
"""
function TotalEnergyControl(; pi_control::PIControl, ref::Real = 1,
        power_filter::AbstractMeasurementFilter = NoFilter())
    filter = measurement_filter_ss(power_filter)
    return TotalEnergyControl{typeof(filter)}(pi_control, Float64(ref), filter,
        !(filter isa NoFilter))
end
TotalEnergyControl(pi_control::PIControl, ref::Real) = TotalEnergyControl(; pi_control, ref)
statenames(b::TotalEnergyControl) = (filter_statenames(:P_energy_f, b.power_filter)..., :ξ_Wtot)
initialvalues(b::TotalEnergyControl; terminal_pu=TerminalValuesPU()) =
    filter_initialvalues(b.power_filter, filter_statenames(:P_energy_f, b.power_filter),
        terminal_pu.p_ac)

"""
$(TYPEDSIGNATURES)

Evaluate MMC total-energy PI control, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `meas`: Filtered measurement signals on converter bases \\[dimensionless\\]. Angle
  signals use \\[rad\\].
- `b`: The `TotalEnergyControl` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `iΣ_z_ref`: Current reference \\[dimensionless\\].

# Notes

```math
W=\\tfrac12(v_{C\\Delta d}^2+v_{C\\Delta q}^2+v_{C\\Delta Zd}^2+v_{C\\Delta Zq}^2+v_{C\\Sigma d}^2+v_{C\\Sigma q}^2+2v_{C\\Sigma z}^2),\\quad \\dot{\\xi}=K_i(W_{ref}-W),\\quad i_{\\Sigma z}^{ref}=\\frac{K_p(W_{ref}-W)+\\xi+p_f}{3v_{dc,f}}.
```

`W` is the dimensionless capacitor-voltage quadratic shown above, with capacitor
voltages normalized by the DC voltage base. Current and power use their converter
bases \\[dimensionless\\]. A configured feedforward filter acts independently on the
voltage-current product.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = TotalEnergyControl(pi_control=PIControl(Kp=0.1, Ki=1.0))
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
function state_space!(F, x, meas, b::TotalEnergyControl, conv::AbstractMMC)
    (; ξ_Wtot, vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; v_dc_f, P_ac_f) = meas
    power = b._independent_power ? meas.vG_d_f * meas.i_d_f + meas.vG_q_f * meas.i_q_f : P_ac_f
    P_ac_f, idx = filter_step!(F, 1, x, b.power_filter,
        filter_statenames(:P_energy_f, b.power_filter), power)
    # wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/(2)
    wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/2;
    
    F[idx] = b.pi_control.Ki * (b.ref - wΣz)
    #iΣ_z_ref = (Kp_wΣ * (wΣz_ref - wΣz) + Ki_wΣ * xwΣz + Pac_f) / 3 / Vdc,
    return ( iΣ_z_ref = ( (b.pi_control.Kp * (b.ref - wΣz) + ξ_Wtot + P_ac_f) / 3 / v_dc_f ),)
end

"""
$(TYPEDEF)

Regulate sum arm energies with a double-frequency notch filter and a rotating-frame PI
controller.

$(TYPEDFIELDS)
"""
@with_kw struct ΣEnergyControl <: AbstractEnergyControl
    "PI gains for normalized signals. Proportional gain is \\[dimensionless\\] and integral
    gain is \\[s⁻¹\\]."
    pi_control::PIControl
    "Per-leg sum-energy reference. The zero-sequence target is twice this value
    \\[dimensionless\\]."
    ref::Float64 = 1 # reference for the energy in each leg (in pu)
end
statenames(::ΣEnergyControl) = (:FΣ1_d, :FΣ1_q, :FΣ1_z, :FΣ2_d, :FΣ2_q, :FΣ2_z, # Notch filter states
                                    :ξ_wΣ_d, :ξ_wΣ_q, :ξ_wΣ_z)                  # PI controller states

"""
$(TYPEDSIGNATURES)

Evaluate MMC summed-energy PI control, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `b`: The `ΣEnergyControl` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `iΣ_d_dc_ref`: Current reference \\[dimensionless\\].
- `iΣ_q_dc_ref`: Current reference \\[dimensionless\\].
- `iΣ_z_dc_ref`: Current reference \\[dimensionless\\].

# Notes

```math
\\dot{\\mathbf f}_1=\\mathbf f_2-2\\zeta\\omega_n(\\mathbf f_1+\\mathbf w)-J\\mathbf f_1,\\quad \\dot{\\mathbf f}_2=-\\omega_n^2\\mathbf f_1-J\\mathbf f_2,\\quad \\dot{\\boldsymbol\\xi}=K_i(\\mathbf w^{ref}-\\mathbf w_f)-J\\boldsymbol\\xi.
```

Here ``ζ=√2/2``, ``ω_n=2ω_b``, ``w=2(w_{Σd},w_{Σq},w_{Σz})^T``,
``w_f=f_1+w``, and ``w^{ref}=(0,0,2\\,ref)^T``. The energy projections
``w_{Σd},w_{Σq},w_{Σz}`` are calculated from the capacitor-voltage states.
The rotation is fixed at nominal frequency, independently of `inputs.sync.ω_c`:

```math
J=-2\\omega_b\\begin{bmatrix}0&1&0\\\\-1&0&0\\\\0&0&0\\end{bmatrix},\\qquad
\\mathbf i_\\Sigma^{dc,ref}=\\frac{\\boldsymbol\\xi+K_p(\\mathbf w^{ref}-\\mathbf w_f)+(0,0,p_f/3)^T}{v_{dc,f}}.
```

Energy and current references are normalized \\[dimensionless\\]. ``ω_b`` uses
\\[rad/s\\]. The returned d/q/z entries are the components of this current vector.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = ΣEnergyControl(pi_control=PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, power=(P_ac_f=0.1,), sync=sync)
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs::NamedTuple{(:meas, :power, :sync)}, b::ΣEnergyControl, conv::AbstractMMC)
    (; vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; ω_c) = inputs.sync
    (; v_dc_f) = inputs.meas
    (; P_ac_f) = inputs.power

    # values in per-unit. wΔ have mainly dc and -2ω_c components
    wΣd = (vCΔ_d^2 - vCΔ_q^2 + 2 * vCΔ_Zd * vCΔ_d + 2 * vCΔ_Zq * vCΔ_q + 4 * vCΣ_d * vCΣ_z)/2
    wΣq = (2* vCΔ_q * vCΔ_Zd - 2 * vCΔ_d * vCΔ_Zq - 2 * vCΔ_d * vCΔ_q + 4 * vCΣ_q * vCΣ_z)/2
    wΣz = (vCΔ_d^2 + vCΔ_q^2 + vCΔ_Zd^2 + vCΔ_Zq^2 + vCΣ_d^2 + vCΣ_q^2 + 2*vCΣ_z^2)/2;

    # notch filter. Expressed in dqz in -2ω_c reference frame.
    # TODO change by actual frequency? (depends on how it is implemented in PSCAD)
    ω_n = 2 * conv.bases.omega
    ζ = sqrt(2)/2    
    FΣ1 = [x.FΣ1_d, x.FΣ1_q, x.FΣ1_z]; FΣ2 = [x.FΣ2_d, x.FΣ2_q, x.FΣ2_z]; wΣ = 2 .* [wΣd, wΣq, wΣz] # Defining the vectors
    J = [ 0 1 0
         -1 0 0
          0 0 0]
    J_min2ω = -2 * conv.bases.omega * J

    F[1:3] = FΣ2 - 2 * ζ * ω_n * (FΣ1 + wΣ) - J_min2ω * FΣ1
    F[4:6] = -ω_n^2 * FΣ1 - J_min2ω * FΣ2
    wΣ_f = FΣ1 + wΣ

    # PI controllers
    ξ_wΣ = [x.ξ_wΣ_d, x.ξ_wΣ_q, x.ξ_wΣ_z]; wΣ_f_ref = [0, 0, 2*b.ref] # multiplication by 2 to match PSCAD implementation TODO change that
    Ki_wΣ = b.pi_control.Ki
    F[7:9] = Ki_wΣ * (wΣ_f_ref - wΣ_f) - J_min2ω * ξ_wΣ

    iΣ_dc_ref = ( ξ_wΣ + b.pi_control.Kp * (wΣ_f_ref - wΣ_f) + [0, 0, P_ac_f/3]) / v_dc_f

    return (iΣ_d_dc_ref = iΣ_dc_ref[1], iΣ_q_dc_ref = iΣ_dc_ref[2], iΣ_z_dc_ref = iΣ_dc_ref[3])

end

"""
$(TYPEDEF)

Regulate difference arm energies with fundamental- and triplen-frame notch and PI
states. The difference-energy references are fixed at zero, independently of the stored
`ref` parameter.

$(TYPEDFIELDS)
"""
@with_kw struct ΔEnergyControl <: AbstractEnergyControl
    "PI gains for normalized signals. Proportional gain is \\[dimensionless\\] and integral
    gain is \\[s⁻¹\\]."
    pi_control::PIControl
    "Legacy energy-reference parameter, currently unused by the equations \\[dimensionless\\]."
    ref::Float64 = 1
end
statenames(::ΔEnergyControl) = (:FΔ1_d, :FΔ1_q, :FΔ1_Zd, :FΔ1_Zq, :FΔ2_d, :FΔ2_q, :FΔ2_Zd, :FΔ2_Zq, # Notch filter states
                                    :ξ_wΔ_d, :ξ_wΔ_q, :ξ_wΔ_Zd, :ξ_wΔ_Zq) # PI controller states

"""
$(TYPEDSIGNATURES)

Evaluate MMC differential-energy PI control, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]. Filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]. Angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]. Angles, when
  present, use \\[rad\\].
- `b`: The `ΔEnergyControl` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `iΣ_d_ac_ref`: Current reference \\[dimensionless\\].
- `iΣ_q_ac_ref`: Current reference \\[dimensionless\\].
- `iΣ_z_ac_ref`: Current reference \\[dimensionless\\].

# Notes

```math
\\dot{\\mathbf f}_1=\\mathbf f_2-2\\zeta\\omega_n(\\mathbf f_1+\\mathbf w)-J\\mathbf f_1,\\quad \\dot{\\mathbf f}_2=-\\omega_n^2\\mathbf f_1-J\\mathbf f_2,\\quad \\dot{\\boldsymbol\\xi}=K_i(\\mathbf w^{ref}-\\mathbf w_f)-J\\boldsymbol\\xi.
```

Here ``ζ=√2/2``, ``ω_n=ω_b``, ``w=-2(w_{Δd},w_{Δq},w_{ΔZd},w_{ΔZq})^T``,
``w_f=f_1+w``, and ``w^{ref}=0``. The energy projections are calculated from
capacitor-voltage states. Both filter and PI rotations use nominal frequency,
independently of `inputs.sync.ω_c`:

```math
J_2=\\begin{bmatrix}0&1\\\\-1&0\\end{bmatrix},\\qquad
J=\\operatorname{diag}(\\omega_bJ_2,3\\omega_bJ_2),\\qquad
\\mathbf u=\\boldsymbol\\xi-K_p\\mathbf w_f,\\qquad
\\mathbf i_\\Sigma^{ac,ref}=\\frac34(u_1+u_3,-u_2-u_4,0)^T.
```

The stored `ref` is unused. The PI output is used directly.
Energy and current references are normalized \\[dimensionless\\]. ``ω_b`` uses
\\[rad/s\\]. The returned zero-sequence current reference is always zero.

# Examples

```julia
using PowerImpedance
P = PowerImpedance
model = mmc(sync=PLLSynchronization(pi_ctrl=PIControl(Kp=0.1, Ki=1.0)),
    delta_control=ΔdqControlGFL(outer_active=OuterActivePowerControl(),
        outer_reactive=OuterReactiveQControl(), occ=InnerCurrentPIControl()),
    sigma_control=ΣdqzControlTEC())
inputs = (v_dc=1.0, vG_d=1.0, vG_q=0.0)
point = P.TerminalValuesPU(p_ac=0.1, q_ac=0.0, p_dc=0.1, v_ac=1.0, v_dc=1.0)
x = P.orderedinitialvalues(model; inputs, terminal_pu=point)
block = ΔEnergyControl(pi_control=PIControl(Kp=0.1, Ki=1.0))
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, power=(P_ac_f=0.1,), sync=sync)
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs::NamedTuple{(:meas, :power, :sync)}, b::ΔEnergyControl, conv::AbstractMMC)
    (; vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; ω_c) = inputs.sync

    # values in per-unit. wΔ have mainly ω_c and 3ω_c components
    wΔd = vCΔ_d * vCΣ_d + 2 * vCΔ_d * vCΣ_z - vCΔ_q * vCΣ_q + vCΔ_Zd * vCΣ_d - vCΔ_Zq * vCΣ_q
    wΔq = 2 * vCΔ_q * vCΣ_z - vCΔ_q * vCΣ_d - vCΔ_d * vCΣ_q + vCΔ_Zd * vCΣ_q + vCΔ_Zq * vCΣ_d
    wΔZd = vCΔ_d * vCΣ_d + vCΔ_q * vCΣ_q + 2 * vCΔ_Zd * vCΣ_z
    wΔZq = vCΔ_q * vCΣ_d - vCΔ_d * vCΣ_q + 2 * vCΔ_Zq * vCΣ_z

    # notch filter. Expressed in dqz in ω_c reference frame
    # TODO change by actual frequency? (depends on how it is implemented in PSCAD)
    ω_n = conv.bases.omega
    ζ = sqrt(2)/2
    FΔ1 = [x.FΔ1_d, x.FΔ1_q, x.FΔ1_Zd, x.FΔ1_Zq]; FΔ2 = [x.FΔ2_d, x.FΔ2_q, x.FΔ2_Zd, x.FΔ2_Zq]; wΔ = -2 .* [wΔd, wΔq, wΔZd, wΔZq] # PSCAD implementation has a minus sign for wΔ, and *2 TODO check if it is a problem?
    J_dq = [ 0 1
            -1 0]
    # Triplen reconstruction `T = [cos(3θ) sin(3θ); sin(3θ) -cos(3θ)]`
    # gives (dT/dt)*T = -3ωbase*J_dq. Since the equations use -J_G*x,
    # its triplen block is +3ωbase*J_dq for both notch and PI states.
    J_G = [ J_dq * conv.bases.omega zeros(2, 2)
            zeros(2, 2) J_dq * (3*conv.bases.omega)]

    F[1:4] = FΔ2 - 2 * ζ * ω_n * (FΔ1 + wΔ) - J_G * FΔ1
    F[5:8] = -ω_n^2 * FΔ1 - J_G * FΔ2
    wΔ_f = wΔ + FΔ1

    # PI controllers
    ξ_wΔ = [x.ξ_wΔ_d, x.ξ_wΔ_q, x.ξ_wΔ_Zd, x.ξ_wΔ_Zq]; wΔ_f_ref = [0, 0, 0, 0]
    Ki_wΔ = b.pi_control.Ki
    F[9:12] = Ki_wΔ * (wΔ_f_ref - wΔ_f) - J_G * ξ_wΔ 
    
    # PSCAD uses the PI output directly. Freytes divides it by -Vac.
    d, q, Zd, Zq = (ξ_wΔ + b.pi_control.Kp * (wΔ_f_ref - wΔ_f))
    # PSCAD uses R directly. Freytes multiplies R by sqrt(2).
    iΣ_dqZ_ac_ref = 3/4 * [d + Zd, - (q + Zq), 0]

    return (iΣ_d_ac_ref = iΣ_dqZ_ac_ref[1], iΣ_q_ac_ref = iΣ_dqZ_ac_ref[2], iΣ_z_ac_ref = iΣ_dqZ_ac_ref[3])
end
