# This is a PowerImpedanceACDC element in order to model a MMC converter soley based on frequency scans, e.g.
# imported Two-port admittance matrix. It is a blackbox model, meaning that the internal structure of the converter is not modeled.
# The converter is represented by its imported Y-parameters.


export blackbox_MMC

mutable struct OP
    Vdc::Float64        # DC voltage [pu]
    Vac::Float64        # AC voltage [pu]    
    Pac::Float64        # Active power  [MW]
    Qac::Float64        # Reactive power [MVAR]
    Pdc::Float64        # DC power [MW]
    Iac::Float64        # AC current [kA]
    Ymmc::Vector{Matrix{ComplexF64}}
    
    @doc """
        OP(Vdc, Vac, Pac, Qac, Pdc, Iac, n, Nf)

    Construct one black-box converter operating point and allocate its sampled
    admittance matrices.

    # Arguments

    - `Vdc`: DC voltage `\\[pu\\]`.
    - `Vac`: AC voltage `\\[pu\\]`.
    - `Pac`: AC active power `\\[MW\\]`.
    - `Qac`: AC reactive power `\\[MVAr\\]`.
    - `Pdc`: DC active power `\\[MW\\]`.
    - `Iac`: AC current `\\[kA\\]`.
    - `n`: Admittance-matrix order.
    - `Nf`: Number of frequency samples.

    # Returns

    - An `OP` with `Nf` zero-valued `n × n` complex admittance matrices.
    """
    function OP(Vdc, Vac, Pac, Qac, Pdc, Iac, n, Nf)
        new(Vdc, Vac, Pac, Qac, Pdc, Iac, [zeros(ComplexF64, n, n) for _ in 1:Nf])
    end
end

# Type definition, add only elements needed for the blackbox model
@with_kw mutable struct Blackbox_MMC <: Converter

    ω₀ :: Union{Int, Float64} = 100*π           # Base angular frequncy [rad/s]

    P :: Union{Int, Float64} = -10              # active power [MW]
    Q :: Union{Int, Float64} = 3                # reactive power [MVA]
    P_dc :: Union{Int, Float64} = 100           # DC power [MW]
    P_min :: Union{Float64, Int} = -100         # min active power output [MW]
    P_max :: Union{Float64, Int} = 100          # max active power output [MW]
    Q_min :: Union{Float64, Int} = -50          # min reactive power output [MVA]
    Q_max :: Union{Float64, Int} = 50           # max reactive power output [MVA]

    θ :: Union{Int, Float64} = 0
    Vₘ :: Union{Int, Float64} = 333             # AC voltage, amplitude [kV]
    Vᵈᶜ :: Union{Int, Float64} = 640            # DC-bus voltage [kV]
    vDCbase :: Union{Int, Float64} = 640        # DC voltage base [kV]
    vACbase :: Union{Int, Float64} = 380        # AC voltage base LL-rms, grid side [kV]
    controls :: OrderedDict{Symbol, Controller} = OrderedDict{Symbol, Controller}() # Control structures, only to indicate the operating mode of the MMC !

    Rₘₑ :: Float64  = 1.230972594                # matched equivalent resistance [Ohm]
    itp :: Any = nothing                         # Interpolation object for the Y-parameters

    # Black box data storage

    path_f :: String = "" # absoulte path to the files containing the frequency vector
    path_MMC :: String = "" # absolute path to the files containing the MMC data
    data :: Vector{OP} = OP[] # Placeholder for operating point data and Y-parameters

end



# Constructor function
# Pull in the data from file here and store it in the struct
# Then do the model matching for the equivalent resistor --> which pkg?
function blackbox_MMC(;args...)

    converter = Blackbox_MMC()
    connection = true
    # Fill element fields from input arguments
    for (key, val) in pairs(args)
        if isa(val, Controller)
            converter.controls[key] = val
        elseif in(key, propertynames(converter))
            setfield!(converter, key, val)
        elseif (key == :connection)
            connection = val
        else
            throw(ArgumentError("Unknown converter property name.")) #If no one of the value specified above -> display an error    
        end
    end



    # Sniff the data from file here and store it 

    # First: Frequency points 

    data = readdlm(converter.path_f , '\t', Float64)
    freq = data[:, 2]                                 
    Nf = length(freq)
    @info "MMC:Loaded $Nf frequency points"

    # Second: MMC data - Each row: Vdc_pu Vac_p Pref Qref Pdc Iac  then  Nf * 9 complex entries (flattened 3x3 per frequency, C-order)
    raw, header = readdlm(converter.path_MMC, Any; header=true)    # whitespace-delimited; header returned separately
    nrows, ncols = size(raw)
    @info "MMC: $nrows operating points loaded from MMC data file"
    
    #TODO: Can be further generalized based on the controller dict, and then infer column count and matrix dimensions

    expected_cols = 6 + 9*Nf
    if ncols != expected_cols
        error("Column count mismatch: expected $expected_cols, found $ncols. ",
            "Check that frequency points and MMC data correspond to the same scan.")
    end

    converter.data = Vector{OP}(undef, nrows)

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
            # Reshape to 3x3 (column-major), then permute dims to emulate row-major (C) ordering
            op.Ymmc[k] = permutedims(reshape(vec9, 3, 3))
        end
        converter.data[i] = op
    end


    # TODO: Based on prior discremination if statement whether matching is actually needed 
    # Match an equivalent resistance based on the operating point 

    y=[]  # Power losses [W]
    x=[]  # AC current [A]


    # If DC-controlling then: Losses Pdc-(sqrt(3)*Vac*Iac-Qref)
    if haskey(converter.controls, :dc) 

        for i in 1:nrows
            S=sqrt(3)*(1e3*converter.data[i].Iac)*(converter.data[i].Vac*converter.vACbase*1e3) # Apparent power in VA
            Q=converter.data[i].Qac * 1e6  # Reactive power in VAR
            if S < Q # Sanity check 
                continue
            end
            Pac=sqrt(S^2 - Q^2)  # AC-side active power in W
            push!(y, abs(converter.data[i].Pdc*1e6 - Pac))  # in W
            push!(x, converter.data[i].Iac*1e3)                  # in A
        end

    else # Pac-controlling: Losses Pdc-Pac

        for i in 1:nrows
            push!(y, (converter.data[i].Pdc - converter.data[i].Pac)*1e6)  # in W
            push!(x, converter.data[i].Iac*1e3)                  # in A
        end

    end




    @. model(x,p)=3*p*x^2  # Power loss model for the MMC: 3*R_eq*I^2
    fit=curve_fit(model, x, y, [1.0]) # Initial guess for R_eq is 1.0 Ohm and uniform weights of 1 
    converter.Rₘₑ = fit.param[1] # Matched equivalent resistance  [Ohm] @ grid side




    # Construct interpolation object for the Y-parameters
    #Y_mmc depends on Vdc, Vac, Pref, Qref and frequency
    Vdc_vals = unique([real(converter.data[i].Vdc) for i in 1:nrows])
    Vac_vals = unique([real(converter.data[i].Vac) for i in 1:nrows])
    Pac_vals = unique([real(converter.data[i].Pac) for i in 1:nrows])
    Qac_vals = unique([real(converter.data[i].Qac) for i in 1:nrows])

    sort!(Vdc_vals)
    sort!(Vac_vals)
    sort!(Pac_vals)
    sort!(Qac_vals)

    # Initialize 4D array with appropriate size
    Ymmc_4d = Array{Matrix{ComplexF64}}(undef, length(Vac_vals), length(Pac_vals), length(Qac_vals), Nf)

    # Fill the 4D array by matching operating points
    for i in 1:nrows
        vac_idx = findfirst(x -> x ==real(converter.data[i].Vac), Vac_vals)
        p_idx = findfirst(x -> x == real(converter.data[i].Pac), Pac_vals)
        q_idx = findfirst(x -> x == real(converter.data[i].Qac), Qac_vals)
        

        if !isnothing(vac_idx) && !isnothing(p_idx) && !isnothing(q_idx)
            for f_idx in 1:Nf
                Ymmc_4d[vac_idx, p_idx, q_idx, f_idx] = converter.data[i].Ymmc[f_idx]
            end
        end
    end

    @info "Vdc values: $Vdc_vals"
    @info "Vac values: $Vac_vals"
    @info "Pac values: $Pac_vals"
    @info "Qac values: $Qac_vals"

    converter.itp = linear_interpolation((Vac_vals, Pac_vals, Qac_vals, freq), Ymmc_4d, extrapolation_bc=Line())


    # Return complete PowerImpedanceACDC element
    elem = Element(input_pins = 1, output_pins = 2, element_value = converter, transformation = false, connection = connection)

end

# Here grab the data from the powerflow and store it in the converter struct
# Might wanna do a two stage interpolation here: First interpolate for the OP variables (Vm, θ, Pac, Qac, Vdc, Pdc),
# then interpolate for the frequency variable in eval_parameters function to make things faster 
function update!(converter :: Blackbox_MMC, Vm, θ, Pac, Qac, Vdc, Pdc)

    # Operating point from power flow
    converter.θ = θ
    converter.Vₘ = Vm
    converter.Vᵈᶜ = Vdc
    converter.P = Pac
    converter.Q = -Qac  # Correction for reactive power sign





end
# Here do the interpolation of the imported data to evaluate the admittance matrix at the given s=jω
function eval_parameters(converter :: Blackbox_MMC, s :: Complex)


    # Operating point from power flow

    Vpu=converter.Vₘ/(sqrt(2/3)*converter.vACbase) # Convert from LN-PK to pu
    # TODO: Include interpolation of Vdc as well
    Vdc_pu=converter.Vᵈᶜ/converter.vDCbase # Convert from pole-pole to pu

    #println("MMC: Evaluating Y-parameters at Vpu=$Vpu, P=$(converter.P), Q=$(-converter.Q), f=$(real(s/(2pi*1im))) Hz")
    # Interpolate Y-parameters at given operating point and frequency
    Y1 = converter.itp(Vpu, converter.P, converter.Q, real(s/(2pi*1im))) 

    # Transform into global dq frame

    TdqDC_0 = [1 0 0; 0 cos(converter.θ) -sin(converter.θ); 0 sin(converter.θ) cos(converter.θ)]

    Ymmc = inv(TdqDC_0)*Y1*TdqDC_0

    return Ymmc


end






