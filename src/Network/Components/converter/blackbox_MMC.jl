export blackbox_MMC

"""
$(TYPEDEF)

Store one sampled black-box MMC operating point and its frequency-indexed admittance
matrices.

$(TYPEDFIELDS)
"""
mutable struct OP
    "Sampled DC voltage on the scan base \\[dimensionless\\]."
    Vdc::Float64        # DC voltage [pu]
    "Sampled AC voltage on the scan base \\[dimensionless\\]."
    Vac::Float64        # AC voltage [pu]    
    "Sampled AC active power \\[MW\\]."
    Pac::Float64        # Active power  [MW]
    "Sampled AC reactive power \\[MVAr\\]."
    Qac::Float64        # Reactive power [MVAR]
    "Sampled DC active power \\[MW\\]."
    Pdc::Float64        # DC power [MW]
    "Sampled AC current \\[kA\\]."
    Iac::Float64        # AC current [kA]
    "Frequency-indexed admittance matrices \\[S\\]."
    Ymmc::Vector{Matrix{ComplexF64}}
    
    @doc """
    $(TYPEDSIGNATURES)

    Construct one black-box converter operating point and allocate its sampled
    admittance matrices.

    # Arguments

    - `Vdc`: Sampled DC voltage on the scan base \\[dimensionless\\].
    - `Vac`: Sampled AC voltage on the scan base \\[dimensionless\\].
    - `Pac`: Sampled AC active power \\[MW\\].
    - `Qac`: Sampled AC reactive power \\[MVAr\\].
    - `Pdc`: Sampled DC active power \\[MW\\].
    - `Iac`: Sampled AC current \\[kA\\].
    - `n`: Admittance-matrix order.
    - `Nf`: Number of frequency samples.

    # Returns

    - An `OP` with `Nf` zero-valued `n × n` complex admittance matrices.

    # Examples

    ```julia
    using PowerImpedance
    component = PowerImpedance.OP(1.0, 1.0, 100.0, 0.0, 100.0, 0.2, 3, 10)
    ```
    """
    function OP(Vdc, Vac, Pac, Qac, Pdc, Iac, n, Nf)
        new(Vdc, Vac, Pac, Qac, Pdc, Iac, [zeros(ComplexF64, n, n) for _ in 1:Nf])
    end
end

const _BLACKBOX_MMC_INPUTS = (
    ac_control = Input(:pq; type = Symbol, unit = "",
        description = "AC power-flow mode: :pq or :pv"),
    dc_control = Input(:p; type = Symbol, unit = "",
        description = "DC power-flow mode: :p or :vdc"),
    powerflow = (
        p_ac = Input(-10.0; unit = "MW", description = "AC active-power target"),
        q_ac = Input(3.0; unit = "MVAr", description = "AC reactive-power target"),
        v_ac = Input(333.0; unit = "kV", description = "AC phase-peak voltage target"),
        p_dc = Input(100.0; unit = "MW",
            description = "DC power into the converter; 603 MW in gives p_dc = 603"),
        v_dc = Input(640.0; unit = "kV", description = "DC pole-to-pole voltage target"),
    ),
)

"""
$(TYPEDEF)

Represent an MMC by imported admittance scans interpolated at solved terminal values.
The AC port uses d/q coordinates. The DC port uses pole-to-pole voltage.
Admittance rows follow DC, AC d, AC q.

`ac_control` selects `:pq` or `:pv`. `dc_control` selects constant AC active power
(`:p`) or constant DC voltage (`:vdc`). `powerflow` stores setpoints in
physical units. Admittance evaluation receives solved terminal values separately.

$(TYPEDFIELDS)

# Errors

- Throws `ArgumentError` for an unsupported control symbol.

# Examples

```julia
model = PowerImpedance.Blackbox_MMC(ac_control = :pv, dc_control = :vdc)
```
"""
Base.@kwdef struct Blackbox_MMC <: AbstractLinFreqDomain
    "Base electrical angular frequency \\[rad/s\\]."
    ω₀::Union{Int, Float64} = 100π
    "Line-to-line RMS AC voltage base \\[kV\\]."
    vACbase::Union{Int, Float64} = 380
    "Pole-to-pole DC voltage base \\[kV\\]."
    vDCbase::Union{Int, Float64} = 640
    "Matched equivalent resistance \\[Ω\\]."
    Rₘₑ::Float64 = 1.230972594
    "Admittance interpolant over AC voltage, active power, reactive power and frequency."
    itp::Any = nothing
    "Frequency-table filename. The importer reads the second column."
    path_f::String = ""
    "Operating-point scan filename with a header row."
    path_MMC::String = ""
    "Imported operating points and admittance samples."
    data::Vector{OP} = OP[]
    "AC power-flow mode: `:pq` or `:pv`."
    ac_control::Symbol = _BLACKBOX_MMC_INPUTS.ac_control.default
    "DC power-flow mode: `:p` or `:vdc`."
    dc_control::Symbol = _BLACKBOX_MMC_INPUTS.dc_control.default
    "AC/DC power \\[MW\\], reactive power \\[MVAr\\] and voltage \\[kV\\] setpoints."
    powerflow::NamedTuple = map(input -> input.default, _BLACKBOX_MMC_INPUTS.powerflow)
    "Active- and reactive-power limits in \\[MW\\] and \\[MVAr\\]."
    limits::Limits = Limits(P_min = -100, P_max = 100, Q_min = -50, Q_max = 50)

    @doc """
    $(TYPEDSIGNATURES)

    Construct a scan-based MMC with validated power-flow modes.
    Keyword construction supplies the declared field defaults.

    # Arguments

    - `ω₀`: Base electrical angular frequency \\[rad/s\\].
    - `vACbase`: Line-to-line RMS AC voltage base \\[kV\\].
    - `vDCbase`: Pole-to-pole DC voltage base \\[kV\\].
    - `Rₘₑ`: Equivalent resistance \\[Ω\\].
    - `itp`: Admittance interpolant `(V_pu, P, Q, f)` returning \\[S\\].
    - `path_f`: Frequency-table filename.
    - `path_MMC`: Operating-point scan filename.
    - `data`: Sampled operating points and admittance matrices.
    - `ac_control`: `:pq` or `:pv`. Default: `:pq`.
    - `dc_control`: `:p` or `:vdc`. Default: `:p`.
    - `powerflow`: `(p_ac, q_ac, v_ac, p_dc, v_dc)` in \\[MW\\], \\[MVAr\\],
      phase-peak \\[kV\\], \\[MW\\] and pole-to-pole \\[kV\\]. Defaults:
      `(-10.0, 3.0, 333.0, 100.0, 640.0)`.
    - `limits`: Power limits in \\[MW\\] and \\[MVAr\\].

    # Returns

    - An immutable `Blackbox_MMC` with scan data and power-flow inputs.

    # Errors

    - Throws `ArgumentError` for an unsupported control symbol.
    """
    function Blackbox_MMC(ω₀, vACbase, vDCbase, Rₘₑ, itp, path_f, path_MMC, data,
            ac_control, dc_control, powerflow, limits)
        ac_control in (:pq, :pv) ||
            throw(ArgumentError("ac_control must be :pq or :pv."))
        dc_control in (:p, :vdc) ||
            throw(ArgumentError("dc_control must be :p or :vdc."))
        new(ω₀, vACbase, vDCbase, Rₘₑ, itp, path_f, path_MMC, data,
            ac_control, dc_control, powerflow, limits)
    end
end

"""
$(TYPEDSIGNATURES)

Import MMC admittance scans, fit the equivalent loss resistance, and construct
a direct black-box converter model.

# Arguments

- `ac_control`: AC power-flow mode, `:pq` or `:pv`. Default: `:pq`.
- `dc_control`: DC power-flow mode, `:p` or `:vdc`. Default: `:p`.
- `powerflow`: Power-flow setpoints `(p_ac, q_ac, v_ac, p_dc, v_dc)` in
  \\[MW\\], \\[MVAr\\], AC phase-peak \\[kV\\], \\[MW\\] and DC pole-to-pole \\[kV\\].
  Defaults: `(-10.0, 3.0, 333.0, 100.0, 640.0)`.
- `limits`: Power limits in \\[MW\\] and \\[MVAr\\]. Defaults: active `[-100, 100]`,
  reactive `[-50, 50]`.
- `args...`: Scan filenames, voltage bases and other `Blackbox_MMC` field keywords.

# Returns

- A `Blackbox_MMC` containing the fitted resistance and scan interpolant.

# Notes

The tab-delimited frequency table has no header and uses its second column for
frequency \\[Hz\\]. The admittance table has one header row. Each scan row contains
six operating-point entries followed by nine row-major complex entries per frequency.
Use complex-literal tokens such as `1.0+0.0im` for the operating-point entries so
that the reader preserves strings for the parser. Interpolation uses AC voltage,
active power, reactive power, and frequency. The importer requires a complete
scan grid at one fixed DC voltage.

```math
P_{loss}=3R_{eq}I_{ac}^{2}.
```

A least-squares fit matches ``R_eq`` \\[Ω\\] to the imported loss-current samples before
the four-axis admittance interpolant is constructed. The fit converts current samples
from \\[kA\\] to \\[A\\] and power samples from \\[MW\\] to \\[W\\].

# Errors

- Propagates file-reading and parsing errors. Unsupported control symbols raise
  `ArgumentError`. Incompatible scan dimensions raise an error.

# Examples

The following call assumes matching frequency and admittance scan files
in the formats described above, with a complete grid of AC voltage and power scans.

```julia
using PowerImpedance
converter = blackbox_MMC(path_f="scan_frequency.tsv",
                        path_MMC="scan_admittance.txt",
                        vACbase=380.0, vDCbase=640.0)
```
"""
function blackbox_MMC(; ac_control = :pq, dc_control = :p,
        powerflow = (;), limits = Limits(P_min = -100, P_max = 100,
            Q_min = -50, Q_max = 50), args...)
    defaults = map(input -> input.default, _BLACKBOX_MMC_INPUTS.powerflow)
    seeds = _withinputs(defaults, _BLACKBOX_MMC_INPUTS.powerflow,
        powerflow, "powerflow")
    converter = Blackbox_MMC(; ac_control, dc_control, powerflow = seeds, limits, args...)

    # Sniff the data from file here and store it 

    # Frequency points

    data = readdlm(converter.path_f , '\t', Float64)
    freq = data[:, 2]                                 
    Nf = length(freq)
    @info "MMC:Loaded $Nf frequency points"

    # Second: MMC data - Each row: Vdc_pu Vac_p Pref Qref Pdc Iac
    # then Nf * 9 complex entries (flattened 3x3 per frequency, C-order)
    # Whitespace-delimited data. The header is returned separately.
    raw, header = readdlm(converter.path_MMC, Any; header=true)
    nrows, ncols = size(raw)
    @info "MMC: $nrows operating points loaded from MMC data file"

    expected_cols = 6 + 9*Nf
    if ncols != expected_cols
        error("Column count mismatch: expected $expected_cols, found $ncols. ",
            "Check that frequency points and MMC data correspond to the same scan.")
    end

    scan_data = Vector{OP}(undef, nrows)

    for i in 1:nrows
        # Fill in OPs
        vdc = real(parse(ComplexF64, replace(raw[i, 1], "(" => "")))
        vac = real(parse(ComplexF64, replace(raw[i, 2], "(" => "")))
        pac = real(parse(ComplexF64, replace(raw[i, 3], "(" => "")))
        qac = real(parse(ComplexF64, replace(raw[i, 4], "(" => "")))
        pdc = real(parse(ComplexF64, replace(raw[i, 5], "(" => "")))
        iac = real(parse(ComplexF64, replace(raw[i, 6], "(" => "")))

        # Create OP object
        op = OP(vdc, vac, pac, qac, pdc, iac, 3, Nf) # Assuming Vdcref is 0.0 and n=3

        # Fill Ymmc matrices
        for k in 1:Nf
            start_idx = 6 + (k-1)*9 + 1
            vec9 = Vector{ComplexF64}(undef, 9)
            for j in 1:9
                vec9[j] = parse(ComplexF64, replace(raw[i, start_idx + j - 1], "(" => ""))
            end
            # Reshape to 3x3 (column-major), then permute dims to emulate
            # row-major (C) ordering
            op.Ymmc[k] = permutedims(reshape(vec9, 3, 3))
        end
        scan_data[i] = op
    end

    # TODO use the preceding condition to determine whether matching is needed.
    # Match an equivalent resistance based on the operating point 

    y=[]  # Power losses [W]
    x=[]  # AC current [A]

    # DC-voltage control losses are Pdc-(sqrt(3)*Vac*Iac-Qref).
    if converter.dc_control == :vdc

        for i in 1:nrows
            # Apparent power in VA
            S = sqrt(3) * (1e3 * scan_data[i].Iac) *
                (scan_data[i].Vac * converter.vACbase * 1e3)
            Q=scan_data[i].Qac * 1e6  # Reactive power in VAR
            if S < Q # Sanity check 
                continue
            end
            Pac=sqrt(S^2 - Q^2)  # AC-side active power in W
            push!(y, abs(scan_data[i].Pdc*1e6 - Pac))  # in W
            push!(x, scan_data[i].Iac*1e3)                  # in A
        end

    else # Active-power control losses are Pdc-Pac.

        for i in 1:nrows
            push!(y, (scan_data[i].Pdc - scan_data[i].Pac)*1e6)  # in W
            push!(x, scan_data[i].Iac*1e3)                  # in A
        end

    end

    @. model(x,p)=3*p*x^2  # Power loss model for the MMC: 3*R_eq*I^2
    # Initial guess for R_eq is 1.0 Ohm and uniform weights of 1
    fit = curve_fit(model, x, y, [1.0])
    Rₘₑ = fit.param[1] # Matched equivalent resistance  [Ohm] @ grid side

    # Construct interpolation object for the Y-parameters
    #Y_mmc depends on Vdc, Vac, Pref, Qref and frequency
    Vdc_vals = unique([real(scan_data[i].Vdc) for i in 1:nrows])
    Vac_vals = unique([real(scan_data[i].Vac) for i in 1:nrows])
    Pac_vals = unique([real(scan_data[i].Pac) for i in 1:nrows])
    Qac_vals = unique([real(scan_data[i].Qac) for i in 1:nrows])

    sort!(Vdc_vals)
    sort!(Vac_vals)
    sort!(Pac_vals)
    sort!(Qac_vals)

    # Initialize 4D array with appropriate size
    Ymmc_4d = Array{Matrix{ComplexF64}}(undef,
        length(Vac_vals), length(Pac_vals), length(Qac_vals), Nf)

    # Fill the 4D array by matching operating points
    for i in 1:nrows
        vac_idx = findfirst(x -> x ==real(scan_data[i].Vac), Vac_vals)
        p_idx = findfirst(x -> x == real(scan_data[i].Pac), Pac_vals)
        q_idx = findfirst(x -> x == real(scan_data[i].Qac), Qac_vals)

        if !isnothing(vac_idx) && !isnothing(p_idx) && !isnothing(q_idx)
            for f_idx in 1:Nf
                Ymmc_4d[vac_idx, p_idx, q_idx, f_idx] = scan_data[i].Ymmc[f_idx]
            end
        end
    end

    @info "Vdc values: $Vdc_vals"
    @info "Vac values: $Vac_vals"
    @info "Pac values: $Pac_vals"
    @info "Qac values: $Qac_vals"

    itp = linear_interpolation((Vac_vals, Pac_vals, Qac_vals, freq),
        Ymmc_4d, extrapolation_bc = Line())

    return Parameters.reconstruct(converter; data = scan_data, Rₘₑ, itp)
end

"""
$(TYPEDSIGNATURES)

Evaluate the imported admittance at the supplied solved terminal values.

# Arguments

- `converter`: Scan-based MMC model.
- `values`: Solved `(ac = ACPortValues, dc = DCPortValues)` tuple. AC voltage
  is phase-peak \\[kV\\], AC angle is in \\[rad\\], and DC voltage is pole-to-pole
  \\[kV\\]. Active and reactive powers are positive into the converter in
  \\[MW\\] and \\[MVAr\\], respectively.
- `s`: Complex Laplace frequency \\[s⁻¹\\]. Sinusoidal evaluation uses
  `s = 2π * im * f` for frequency `f` \\[Hz\\].

# Returns

- Rotated terminal admittance matrix \\[S\\], with row order DC, AC d, AC q.
  The scan admittance retains its units.

# Notes

```math
Y=T(\\theta)^{-1}Y_{scan}(V_{pu},-p,-q,f)T(\\theta),\\qquad
V_{pu}=\\frac{v}{\\sqrt{2/3}V_{LL,b}},\\qquad f=\\Re\\frac{s}{2\\pi\\mathrm{j}},
```

```math
T(\\theta)=\\begin{bmatrix}
1 & 0 & 0\\\\
0 & \\cos\\theta & -\\sin\\theta\\\\
0 & \\sin\\theta & \\cos\\theta
\\end{bmatrix}.
```

Here `v` is the solved AC phase-peak voltage \\[kV\\], `V_LL,b` is `vACbase`
\\[kV\\], and `p` \\[MW\\] and `q` \\[MVAr\\] are solved powers into the converter.
The scan receives the solved active- and reactive-power injections into the AC bus.
The imported interpolant uses linear extrapolation outside the sampled intervals.
DC voltage is fixed across the interpolation grid.

# Examples

```julia
P = PowerImpedance
model = P.Blackbox_MMC(itp = (v, p, q, f) -> ComplexF64[1 0 0; 0 1 0; 0 0 1])
values = (ac = ACPortValues(380sqrt(2/3), 0.0, -100.0, -3.0),
    dc = DCPortValues(640.0, 100.0))
Y = P.eval_parameters(model, values, 2π * im * 50)
@assert Y == ComplexF64[1 0 0; 0 1 0; 0 0 1]
```
"""
function eval_parameters(converter::Blackbox_MMC, values::NamedTuple, s::Complex)
    ac = values.ac
    # Operating point from power flow
    Vpu = ac.v / (sqrt(2/3) * converter.vACbase) # Convert from LN-PK to pu
    # Interpolate Y-parameters at given operating point and frequency
    Y1 = converter.itp(Vpu, -ac.p, -ac.q, real(s / (2pi * 1im)))
    # Transform into global dq frame
    TdqDC_0 = [1 0 0; 0 cos(ac.theta) -sin(ac.theta); 0 sin(ac.theta) cos(ac.theta)]
    return inv(TdqDC_0) * Y1 * TdqDC_0
end

"""
$(TYPEDSIGNATURES)

Return the declared AC/DC modes and physical power-flow inputs.

# Arguments

- `model`: Scan-based MMC model.

# Returns

- Input declarations with fixed defaults. Active power uses \\[MW\\], reactive
  power \\[MVAr\\], AC voltage phase-peak \\[kV\\] and DC voltage pole-to-pole \\[kV\\].
"""
inputs(::Blackbox_MMC) = _BLACKBOX_MMC_INPUTS

"""
$(TYPEDSIGNATURES)

Return `nothing`. The scan-based MMC has no model power base.
"""
bases(::Blackbox_MMC) = nothing

limits(model::Blackbox_MMC) = model.limits

electricalconnections(::Blackbox_MMC) = (ac = Port(ACDQ), dc = Port(DC_CM))

"""
$(TYPEDSIGNATURES)

Return the scan matrix coordinate order: DC, AC d, AC q.
"""
admittance_order(::Blackbox_MMC) = ((:dc, :dc), (:ac, :d), (:ac, :q))
is_converter(::Blackbox_MMC) = true
is_passive(::Blackbox_MMC) = false

"""
$(TYPEDSIGNATURES)

Return `false` because scan evaluation requires a solved operating point.
"""
islinear(::Blackbox_MMC) = false

"""
$(TYPEDSIGNATURES)

Return the PowerModelsACDC converter table name, `"convdc"`.
"""
pmtype(::Blackbox_MMC, rows) = "convdc"

"""
$(TYPEDSIGNATURES)

Write the MMC targets, loss resistance and limits to PowerModelsACDC data.

# Arguments

- `data`: Power-flow data, including AC and DC buses.
- `model`: Scan-based MMC. Power targets and limits use \\[MW\\] and \\[MVAr\\].
  AC voltage uses phase-peak \\[kV\\], DC voltage pole-to-pole \\[kV\\].
- `PMACDC`: PowerModelsACDC data representation.
- `component_key`: Component name, index and power-flow type.
- `ports`: Named AC/DC bus indices `(ac, dc)`.
- `global_dict`: Network bases, with `V` in \\[V\\] and `Z` in \\[Ω\\].

# Returns

- `nothing`. Converter and bus entries are written in place.

# Notes

```math
V_{tar}=\\frac{10^3 v_{ac}}{V},\\qquad
V_{dc,set}=\\frac{v_{dc}}{dcpol\\,V/10^3}.
```

Both AC modes use the same voltage target. Both targets are \\[dimensionless\\].
"""
function convert!(data, model::Blackbox_MMC, ::Type{PMACDC}, component_key,
        ports::NamedTuple, global_dict)
    key = component_key.index
    ac_bus, dc_bus = ports.ac, ports.dc
    (; p_ac, q_ac, v_ac, p_dc, v_dc) = model.powerflow
    lm = limits(model)
    convdc = data["convdc"][string(key)] = Dict{String, Any}()
    convdc["busdc_i"] = dc_bus
    convdc["busac_i"] = ac_bus
    convdc["source_id"] = Any["convdc", key]
    convdc["status"] = 1
    convdc["index"] = key
    convdc["basekVac"] = global_dict["V"] / 1e3

    convdc["type_ac"] = model.ac_control == :pv ? 2 : 1
    convdc["Vtar"] = v_ac * 1e3 / global_dict["V"]
    if convdc["type_ac"] == 2
        data["bus"][string(ac_bus)] = set_bus_type(data["bus"][string(ac_bus)], 2)
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
    end
    convdc["type_dc"] = model.dc_control == :vdc ? 2 : 1
    convdc["acq_droop"] = 0
    convdc["kq_droop"] = 0
    # Constant power control or DC voltage control
    convdc["droop"] = 0
    convdc["Pdcset"] = p_dc
    convdc["Vdcset"] = v_dc / (data["dcpol"] * global_dict["V"] / 1e3)
    convdc["dVdcSet"] = 0

    # LCC converter
    convdc["islcc"] = 0
    # without transformer
    convdc["transformer"] = 0
    convdc["rtf"] = 0
    convdc["xtf"] = 0
    convdc["tm"] = 1
    # without filter
    convdc["filter"] = 0
    convdc["bf"] = 0
    # with reactor
    convdc["reactor"] = 1
    convdc["rc"] = model.Rₘₑ / global_dict["Z"]
    convdc["xc"] = 0.0

    # default values
    convdc["Vmmax"] = 1.1 * v_ac * 1e3 / global_dict["V"]
    convdc["Vmmin"] = 0.9 * v_ac * 1e3 / global_dict["V"]
    convdc["Imax"] = 1.1 * abs(p_ac) / v_ac
    convdc["P_g"] = p_ac
    convdc["Q_g"] = q_ac
    convdc["LossA"] = 0
    convdc["LossB"] = 0
    convdc["LossCrec"] = 0
    convdc["LossCinv"] = 0
    convdc["Qacmax"] = lm.Q_max
    convdc["Qacmin"] = lm.Q_min
    convdc["Pacmax"] = lm.P_max
    convdc["Pacmin"] = lm.P_min

    #Voltage limits for bus, these are already set when PV bus
    if data["bus"][string(ac_bus)]["bus_type"] == 1 #PQ-bus
        data["bus"][string(ac_bus)]["vm"] = convdc["Vtar"]
        data["bus"][string(ac_bus)]["vmin"] = 0.9 * data["bus"][string(ac_bus)]["vm"]
        data["bus"][string(ac_bus)]["vmax"] = 1.1 * data["bus"][string(ac_bus)]["vm"]
    end
    # Convert from pp to pg for PMACDC
    busdc = data["busdc"][string(dc_bus)]
    busdc["Vdc"] = v_dc / (data["dcpol"] * global_dict["V"] / 1e3)
    busdc["Vdcmax"] = 1.1 * busdc["Vdc"]
    busdc["Vdcmin"] = 0.9 * busdc["Vdc"]
    data["busdc"][string(dc_bus)] = set_bus_type_dc(busdc, convdc["type_dc"])
    return nothing
end

"""
$(TYPEDSIGNATURES)

Convert solved powers and voltages to port values positive into the converter.
Taking 603 MW from DC and delivering 600 MW to AC gives `dc.p = 603` and `ac.p = -600`.

# Arguments

- `elemresult`: PowerModelsACDC converter result in network per-unit values.
- `busresult`: Named AC/DC bus results in network per-unit values.
- `global_dict`: Network bases, with `S` in \\[VA\\] and `V` in \\[V\\].
- `model`: Scan-based MMC model.
- `PMACDC`: Source data representation.
- `PIACDC`: Physical terminal-value representation.

# Returns

- `ac`: `ACPortValues` in phase-peak \\[kV\\], \\[rad\\], \\[MW\\] into the converter
  and \\[MVAr\\] into the converter.
- `dc`: `DCPortValues` in pole-to-pole \\[kV\\] and \\[MW\\] into the converter.
  A converter inverting from DC to AC has `dc.p > 0`.
"""
function transform(elemresult, busresult::NamedTuple, global_dict,
        model::Blackbox_MMC, ::Type{PMACDC}, ::Type{PIACDC})
    ac = busresult.ac
    dc = busresult.dc
    return (
        ac = ACPortValues(ac["vm"] * global_dict["V"] / 1e3 * sqrt(2), ac["va"],
            elemresult["pgrid"] * global_dict["S"] / 1e6,
            elemresult["qgrid"] * global_dict["S"] / 1e6),
        dc = DCPortValues(dc["vm"] * (dcpol * global_dict["V"] / 1e3),
            elemresult["pdc"] * global_dict["S"] / 1e6),
    )
end
