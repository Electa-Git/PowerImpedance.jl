export UncompensatedModulation, CompensatedModulation


"""
$(TYPEDEF)

Define the interface for MMC insertion-index calculation and modulation delays.
"""
abstract type AbstractModulationMMC               <: AbstractStateSpace end 


"""
$(TYPEDEF)

Calculate insertion indices using measured DC voltage, without instantaneous
capacitor-voltage compensation. Separate delays act on differential, sum, and
zero-sequence commands.

$(TYPEDFIELDS)
"""
struct UncompensatedModulation{D<:PadeDelay} <: AbstractModulationMMC 
    "Two-channel differential d/q modulation delay."
    delay1::D
    "Two-channel sum d/q modulation delay."
    delay2::D
    "Scalar sum zero-sequence modulation delay."
    delay3::D
end
statenames(m::UncompensatedModulation) = (statenames(m.delay1)..., statenames(m.delay2)..., statenames(m.delay3)...)

"""
$(TYPEDSIGNATURES)

Construct a `UncompensatedModulation` component from the supplied parameters.

# Arguments

- `timeDelay`: Delay duration \\[s\\]. Default: `0.0`.
- `padeOrderNum`: Requested Padé numerator polynomial order. Default: `0`.
- `padeOrderDen`: Requested Padé denominator polynomial order. Default: `0`.

# Returns

- An `UncompensatedModulation` instance.

# Examples

```julia
using PowerImpedance
component = UncompensatedModulation(timeDelay=200e-6, padeOrderNum=3, padeOrderDen=3)
```
"""
function UncompensatedModulation(;
    timeDelay::Real = 0.0,
    padeOrderNum::Int = 0,
    padeOrderDen::Int = 0
)
    delay1 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 2,
        state_prefix = :mΔ_delay,
    )
    delay2 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 2,
        state_prefix = :mΣ_delay,
    )
    delay3 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 1,
        state_prefix = :mΣ_z_delay,
    )
    return UncompensatedModulation{PadeDelay}(delay1, delay2, delay3)
end


"""
$(TYPEDSIGNATURES)

Evaluate DC-voltage-normalized MMC modulation with delays and frame-dependent phase
compensation, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `b`: The `UncompensatedModulation` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `mΔd`: Insertion index or modulation command \\[dimensionless\\].
- `mΔq`: Insertion index or modulation command \\[dimensionless\\].
- `mΔZd`: Insertion index or modulation command \\[dimensionless\\].
- `mΔZq`: Insertion index or modulation command \\[dimensionless\\].
- `mΣd`: Insertion index or modulation command \\[dimensionless\\].
- `mΣq`: Insertion index or modulation command \\[dimensionless\\].
- `mΣz`: Insertion index or modulation command \\[dimensionless\\].

# Notes

```math
\\mathbf m_\\Delta=-2\\frac{V_{ac,b}}{V_{dc,b}}\\frac{\\mathbf v_\\Delta^{ref}}{v_{dc,f}},\\qquad \\mathbf m_\\Sigma=2\\frac{\\mathbf v_\\Sigma^{ref}}{v_{dc,f}}.
```

References are rotated to the electrical-model frames before insertion-index
calculation. Triplen differential indices are zero; delayed commands receive
frame-dependent phase compensation. Voltages and insertion indices are normalized
\\[dimensionless\\].

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
block = UncompensatedModulation()
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, out_delta=(vMΔ_d_ref_c=1.0, vMΔ_q_ref_c=0.0),
    out_sigma=(vMΣ_d_ref_c=0.0, vMΣ_q_ref_c=0.0, vMΣ_z_ref=0.5))
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, b::UncompensatedModulation, conv::AbstractMMC)
    (; meas, out_delta, out_sigma) = inputs
    (;v_dc_f) = meas
    (; vMΔ_d_ref_c, vMΔ_q_ref_c) = out_delta
    (; vMΣ_d_ref_c, vMΣ_q_ref_c, vMΣ_z_ref) = out_sigma

    # First, the references are converter to grid reference framoe
    Δθ_c = syncangle(conv.sync, x)
    vMΔ_d_ref, vMΔ_q_ref = inverse_frame_transform(vMΔ_d_ref_c, vMΔ_q_ref_c, Δθ_c)
    vMΣ_d_ref, vMΣ_q_ref = inverse_frame_transform(vMΣ_d_ref_c, vMΣ_q_ref_c, -2*Δθ_c) # Zero sequence is reference frame independent, so not transformed

    # Δ variables multiplied by -1 * baseConv1 * 2/v_dc_f
    mΔd = -conv.elec.baseConv1 * 2/v_dc_f * vMΔ_d_ref 
    mΔq = -conv.elec.baseConv1 * 2/v_dc_f * vMΔ_q_ref

    # Σ variables multiplied by 2/v_dc_f
    mΣd = 2/v_dc_f * vMΣ_d_ref
    mΣq = 2/v_dc_f * vMΣ_q_ref
    mΣz = 2/v_dc_f * vMΣ_z_ref          # zero-sequence is reference-frame independent

    # Pade delays
    y, i = state_space_block!(F, x, (mΔd, mΔq), b.delay1, conv, 1)
    mΔd, mΔq = phase_compensated_dq(y, conv.elec.ωbase * b.delay1.timeDelay)

    y, i = state_space_block!(F, x, (mΣd, mΣq), b.delay2, conv, i)
    mΣd, mΣq = phase_compensated_dq(y, -2*conv.elec.ωbase * b.delay2.timeDelay)

    mΣz = state_space_block!(F, x, (mΣz, ), b.delay3, conv, i)[1][1]

    return (mΔd = mΔd, mΔq = mΔq, mΔZd = 0, mΔZq = 0,
        mΣd = mΣd, mΣq = mΣq, mΣz = mΣz)
end

"""
$(TYPEDEF)

Calculate insertion indices by solving the instantaneous capacitor-voltage coupling
system. A singular coupling matrix produces NaN insertion indices so an equilibrium
solver can reject the iterate.

$(TYPEDFIELDS)
"""
struct CompensatedModulation{D<:PadeDelay} <: AbstractModulationMMC 
    "Two-channel differential d/q modulation delay."
    delay1::D
    "Differential triplen d-component modulation delay."
    delay2a::D
    "Differential triplen q-component modulation delay."
    delay2b::D
    "Two-channel sum d/q modulation delay."
    delay3::D
    "Scalar sum zero-sequence modulation delay."
    delay4::D
end
statenames(m::CompensatedModulation) = (statenames(m.delay1)..., statenames(m.delay2a)..., statenames(m.delay2b)..., statenames(m.delay3)..., statenames(m.delay4)...)

"""
$(TYPEDSIGNATURES)

Construct a `CompensatedModulation` component from the supplied parameters.

# Arguments

- `timeDelay`: Delay duration \\[s\\]. Default: `0.0`.
- `padeOrderNum`: Requested Padé numerator polynomial order. Default: `0`.
- `padeOrderDen`: Requested Padé denominator polynomial order. Default: `0`.

# Returns

- A `CompensatedModulation` instance.

# Examples

```julia
using PowerImpedance
component = CompensatedModulation(timeDelay=200e-6, padeOrderNum=3, padeOrderDen=3)
```
"""
function CompensatedModulation(;
    timeDelay::Real = 0.0,
    padeOrderNum::Int = 0,
    padeOrderDen::Int = 0
)
    delay1 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 2,
        state_prefix = :mΔ_delay,
    )
    delay2a = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 1,
        state_prefix = :mΔ_Zd_delay,
    )
    delay2b = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 1,
        state_prefix = :mΔ_Zq_delay,
    )
    delay3 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 2,
        state_prefix = :mΣ_delay,
    )
    delay4 = PadeDelay(
        timeDelay = timeDelay,
        padeOrderNum = padeOrderNum,
        padeOrderDen = padeOrderDen,
        n_inputs = 1,
        state_prefix = :mΣ_z_delay,
    )
    return CompensatedModulation{PadeDelay}(delay1, delay2a, delay2b, delay3, delay4)
end


"""
$(TYPEDSIGNATURES)

Solve MMC capacitor-voltage compensation and apply delays and frame-dependent phase
compensation, writing state derivatives into `F`.

# Arguments

- `F`: Writable derivative buffer in block state order. Normalized electrical-state
  rates use \\[s⁻¹\\] and angle rates use \\[rad/s\\]; filter-state rates follow the
  realization.
- `x`: Named state values. Electrical states use their component bases
  \\[dimensionless\\]; angles use \\[rad\\]. Filter-state units follow the realization.
- `inputs`: Named input signals on the component bases \\[dimensionless\\]; angles, when
  present, use \\[rad\\].
- `b`: The `CompensatedModulation` parameters.
- `conv`: Parent converter, providing electrical bases and synchronization.

# Returns

- `mΣd`: Insertion index or modulation command \\[dimensionless\\].
- `mΣq`: Insertion index or modulation command \\[dimensionless\\].
- `mΣz`: Insertion index or modulation command \\[dimensionless\\].
- `mΔd`: Insertion index or modulation command \\[dimensionless\\].
- `mΔq`: Insertion index or modulation command \\[dimensionless\\].
- `mΔZd`: Insertion index or modulation command \\[dimensionless\\].
- `mΔZq`: Insertion index or modulation command \\[dimensionless\\].

# Notes

```math
M(\\mathbf v_C)\\mathbf m=\\mathbf v^{ref}.
```

``M`` is the seven-by-seven capacitor-voltage coupling matrix used by the electrical
model. The reference vector contains sum d/q/z and differential d/q voltages, followed
by two zero triplen-voltage targets. Differential references rotate into the grid
frame and are multiplied by `baseConv1`; sum references are used without rotation
in this method. Singular matrices produce NaN insertion indices.
Independent Padé delays and fundamental, negative-double-frequency, and triplen phase
compensation follow the solve.

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
block = CompensatedModulation()
x = merge(NamedTuple{P.statenames(block)}(zeros(P.n_states(block))), x)
F = zeros(P.n_states(block))
meas = (vG_d_f=1.0, vG_q_f=0.0, v_dc_f=1.0, i_d_f=0.1,
    i_q_f=0.0, i_dc_f=0.1, θ_f=0.0, P_ac_f=0.1, Q_ac_f=0.0, P_dc_f=0.1)
sync = (ω_c=1.0, P_ac_f=0.1)
signals = (meas=meas, out_delta=(vMΔ_d_ref_c=1.0, vMΔ_q_ref_c=0.0),
    out_sigma=(vMΣ_d_ref_c=0.0, vMΣ_q_ref_c=0.0, vMΣ_z_ref=0.5))
outputs = P.state_space!(F, x, signals, block, model)
@assert all(isfinite, F)
```
"""
function state_space!(F, x, inputs, b::CompensatedModulation, conv::AbstractMMC)
    (; meas, out_delta, out_sigma) = inputs
    (; vCΔ_d, vCΔ_q, vCΔ_Zd, vCΔ_Zq, vCΣ_d, vCΣ_q, vCΣ_z) = x
    (; vMΔ_d_ref_c, vMΔ_q_ref_c) = out_delta
    (; vMΣ_d_ref_c, vMΣ_q_ref_c, vMΣ_z_ref) = out_sigma
    
    # First, the references are converter to grid reference framoe
    Δθ_c = syncangle(conv.sync, x)
    vMΔ_d_ref, vMΔ_q_ref = inverse_frame_transform(vMΔ_d_ref_c, vMΔ_q_ref_c, Δθ_c)
    vMΣ_d_ref, vMΣ_q_ref = vMΣ_d_ref_c, vMΣ_q_ref_c

    vMΔ_d_ref *= conv.elec.baseConv1; vMΔ_q_ref *= conv.elec.baseConv1 # Δ variables multiplied by baseConv1 (DC -> AC base conversion)

    VΣΔ_CmdqZ = 1/4 * [ 2 * vCΣ_z       0              2 * vCΣ_d               vCΔ_d + vCΔ_Zd       vCΔ_Zq - vCΔ_q       vCΔ_d       vCΔ_q
                        0              2 * vCΣ_z       2 * vCΣ_q               -vCΔ_q - vCΔ_Zq      vCΔ_Zd - vCΔ_d       vCΔ_q       -vCΔ_d
                        vCΣ_d           vCΣ_q           2 * vCΣ_z               vCΔ_d               vCΔ_q               vCΔ_Zd      vCΔ_Zq
                        -vCΔ_d - vCΔ_Zd  vCΔ_q + vCΔ_Zq   -2 * vCΔ_d              -vCΣ_d - 2 * vCΣ_z   vCΣ_q               -vCΣ_d      vCΣ_q
                        vCΔ_q - vCΔ_Zq   vCΔ_d - vCΔ_Zd   -2 * vCΔ_q              vCΣ_q               vCΣ_d - 2 * vCΣ_z    -vCΣ_q      -vCΣ_d
                        -vCΔ_d          -vCΔ_q          -2 * vCΔ_Zd             -vCΣ_d              -vCΣ_q              -2 * vCΣ_z  0
                        -vCΔ_q          vCΔ_d           -2 * vCΔ_Zq             vCΣ_q               -vCΣ_d              0          -2 * vCΣ_z]
    
    # For optimization, the matrix VΣΔ_CmdqZ could be inversed or factorized (symbolically) beforehand. But is it needed/better?
    references = [vMΣ_d_ref; vMΣ_q_ref; vMΣ_z_ref; vMΔ_d_ref; vMΔ_q_ref; 0; 0] # vΔZdq are set to zero by controller, but mΔZdq can be different from zero
    # A singular capacitor-voltage matrix has no insertion indices. NaN marks the
    # point as invalid, so a steady-state solver rejects the iterate instead of
    # aborting; regular points use the same LU solve as `\`.
    factorization = LinearAlgebra.lu(VΣΔ_CmdqZ; check = false)
    insertion = LinearAlgebra.issuccess(factorization) ? factorization \ references :
                fill(oftype(first(references), NaN), length(references))
    (mΣd, mΣq, mΣz, mΔd, mΔq, mΔZd, mΔZq) = insertion

    # Pade delays
    y, i = state_space_block!(F, x, (mΔd, mΔq), b.delay1, conv, 1)
    mΔd, mΔq = phase_compensated_dq(y, conv.elec.ωbase * b.delay1.timeDelay)
    # TODO improve this part
    mΔZd_res, i = state_space_block!(F, x, (mΔZd, ), b.delay2a, conv, i)
    mΔZq_res, i = state_space_block!(F, x, (mΔZq, ), b.delay2b, conv, i)

    T = [cos(3 * conv.elec.ωbase * b.delay2a.timeDelay) sin(3 * conv.elec.ωbase * b.delay2a.timeDelay)
         -sin(3 * conv.elec.ωbase * b.delay2a.timeDelay) cos(3 * conv.elec.ωbase * b.delay2a.timeDelay)]

    mΔZd, mΔZq = T * [mΔZd_res[1]; mΔZq_res[1]]

    y, i = state_space_block!(F, x, (mΣd, mΣq), b.delay3, conv, i)
    mΣd, mΣq = phase_compensated_dq(y, -2*conv.elec.ωbase * b.delay3.timeDelay)

    mΣz = state_space_block!(F, x, (mΣz, ), b.delay4, conv, i)[1][1]
    return (; mΣd, mΣq, mΣz, mΔd, mΔq, mΔZd, mΔZq)
end
