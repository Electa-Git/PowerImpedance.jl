# This is a PowerImpedanceACDC element in order to model a MMC converter soley based on frequency scans, e.g.
# imported Two-port admittance matrix. It is a blackbox model, meaning that the internal structure of the converter is not modeled.
# The converter is represented by its imported Y-parameters.


export blackbox_MMC

mutable struct OP
    Vdc::Vector{ComplexF64}             # DC voltage [pu]
    Vac::Vector{ComplexF64}             # AC voltage [pu]    
    Pref::Vector{ComplexF64}            # Active power reference [MW]
    Qref::Vector{ComplexF64}            # Reactive power reference [MVAR]
    Vdcref::Vector{ComplexF64}          # DC voltage reference [pu]
    Pdc::Vector{ComplexF64}             # DC power [MW]
    Iac::Vector{ComplexF64}             # AC current [A]
    Ymmc::Vector{Vector{Matrix{ComplexF64}}}
    
    function OP(n::Int, Nf::Int)
        new(
            Vector{ComplexF64}(undef, n),
            Vector{ComplexF64}(undef, n),
            Vector{ComplexF64}(undef, n),
            Vector{ComplexF64}(undef, n),
            Vector{ComplexF64}(undef, n),
            Vector{ComplexF64}(undef, n),
            Vector{ComplexF64}(undef, n),
            [Vector{Matrix{ComplexF64}}(undef, Nf) for _ in 1:n]
        )
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
    data :: OP = OP(1,1) # Placeholder for operating point data and Y-parameters

end



# Constructor function
# Pull in the data from file here and store it in the struct
# Then do the model matching for the equivalent resistor --> which pkg?
function blackbox_MMC(;args...)

    converter = Blackbox_MMC()

    # Fill element fields from input arguments
    for (key, val) in pairs(args)
        if isa(val, Controller)
            converter.controls[key] = val
        elseif in(key, propertynames(converter))
            setfield!(converter, key, val)
        else
            throw(ArgumentError("Unknown converter property name.")) #If no one of the value specified above -> display an error    
        end
    end



    # Sniff the data from file here and store it 

    # First: Frequency points 

    data = readdlm(converter.path_f , '\t', Float64)
    freq = data[:, 2]                                 
    Nf = length(freq)
    println("MMC:Loaded $Nf frequency points")

    # Second: MMC data - Each row: Vdc_pu Vac_p Pref Qref Pdc Iac  then  Nf * 9 complex entries (flattened 3x3 per frequency, C-order)
    raw, header = readdlm(converter.path_MMC, Any; header=true)    # whitespace-delimited; header returned separately
    nrows, ncols = size(raw)
    println("MMC: $nrows operating points loaded from MMC data file")

    # Validate expected column count: 6 scalars + 9*Nf complex tokens
    expected_cols = 6 + 9*Nf
    if ncols != expected_cols
        error("Column count mismatch: expected $expected_cols, found $ncols. ",
            "Check that frequency points and MMC data correspond to the same scan.")
    end

    converter.data=OP(nrows, Nf)

    for i in 1:nrows

    # Fill OP struct
    converter.data.Vdc[i] = parse(ComplexF64, replace(raw[i, 1], "(" => ""))
    converter.data.Vac[i] = parse(ComplexF64, replace(raw[i, 2], "(" => ""))
    converter.data.Pref[i] = parse(ComplexF64, replace(raw[i, 3], "(" => ""))
    converter.data.Qref[i] = parse(ComplexF64, replace(raw[i, 4], "(" => ""))
    converter.data.Pdc[i] = parse(ComplexF64, replace(raw[i, 5], "(" => ""))
    converter.data.Iac[i] = parse(ComplexF64, replace(raw[i, 6], "(" => ""))

    # Fill Ymmc matrices
    for k in 1:Nf
        start_idx = 6 + (k-1)*9 + 1
        stop_idx  = start_idx + 9 - 1
        vec9 = Vector{ComplexF64}(undef, 9)
        for j in 1:9
            vec9[j] = parse(ComplexF64, replace(raw[i, start_idx + j - 1], "(" => ""))
        end
        # Reshape to 3x3 (column-major), then permute dims to emulate row-major (C) ordering
        converter.data.Ymmc[i][k] = permutedims(reshape(vec9, 3, 3))
    end

    end



    # Match an equivalent resistance based on the operating point 

    y=[]  # Power losses [W]
    x=[]  # AC current [A]


    for i in 1:nrows
        push!(y, (converter.data.Pdc[i]-converter.data.Pref[i])*1e6)  # in W
        push!(x, converter.data.Iac[i]*1e3)                  # in A
    end


    @. model(x,p)=3*p*x^2  # Power loss model for the MMC: 3*R_eq*I^2
    fit=curve_fit(model, x, y, [1.0])
    converter.Rₘₑ = fit.param[1] # Matched equivalent resistance  [Ohm] @ grid side




    # Construct interpolation object for the Y-parameters
    #Y_mmc depends on Vac, Pref, Qref and frequency
    # TODO: Extension for Vdc control
    Vac_vals = unique([real(converter.data.Vac[i]) for i in 1:nrows])
    Pref_vals = unique([real(converter.data.Pref[i]) for i in 1:nrows])
    Qref_vals = unique([real(converter.data.Qref[i]) for i in 1:nrows])

    sort!(Vac_vals)
    sort!(Pref_vals)
    sort!(Qref_vals)

    # Initialize 4D array with appropriate size
    Ymmc_4d = Array{Union{Matrix{ComplexF64}, Nothing}}(nothing, length(Vac_vals), length(Pref_vals), length(Qref_vals), Nf)

    # Fill the 4D array by matching operating points
    for i in 1:nrows
        v_idx = findfirst(x -> x ==real(converter.data.Vac[i]), Vac_vals)
        p_idx = findfirst(x -> x == real(converter.data.Pref[i]), Pref_vals)
        q_idx = findfirst(x -> x == real(converter.data.Qref[i]), Qref_vals)

        if !isnothing(v_idx) && !isnothing(p_idx) && !isnothing(q_idx)
            for f_idx in 1:Nf
                Ymmc_4d[v_idx, p_idx, q_idx, f_idx] = converter.data.Ymmc[i][f_idx]
            end
        end
    end

    println("Vac values: $Vac_vals")
    println("Pref values: $Pref_vals")
    println("Qref values: $Qref_vals")

    converter.itp = linear_interpolation((Vac_vals, Pref_vals, Qref_vals, freq), Ymmc_4d, extrapolation_bc=Line())


    # Return complete PowerImpedanceACDC element
    elem = Element(input_pins = 1, output_pins = 2, element_value = converter, transformation = false)

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








