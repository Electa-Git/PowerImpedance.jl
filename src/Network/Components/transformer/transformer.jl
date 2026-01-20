export transformer

@with_kw mutable struct Transformer
    ABCD :: Array{Basic} = []          # ABCD value

    pins :: Int = 1                     # marks single or three phase
    organization :: Symbol = :YY        # three phase organization (:YY or :ΔY)

    ω :: Union{Int, Float64} = 2*π*50   # rated frequency in [rad/s]
    V₁ᵒ :: Union{Int, Float64} = 0      # open circuit primary voltage [V]
    V₁ˢ :: Union{Int, Float64} = 0      # short circuit primary voltage [V]
    I₁ᵒ :: Union{Int, Float64} = 0      # open circuit primary current [V]
    I₁ˢ :: Union{Int, Float64} = 0      # short circuit primary current [V]
    P₁ᵒ :: Union{Int, Float64} = 0      # open circuit losses on primary side [W]
    P₁ˢ :: Union{Int, Float64} = 0      # short circuit losses on primary side [W]
    V₂ᵒ :: Union{Int, Float64} = 0      # open circuit secondary voltage [V]
    V₂ˢ :: Union{Int, Float64} = 0      # short circuit secondary voltage [V]

    n :: Union{Int, Float64} = 0        # turn ratio
    Lₚ :: Union{Int, Float64} = 0       # primary side inductance [H]
    Rₚ :: Union{Int, Float64} = 0       # primary side resistance [Ω]
    Rₛ :: Union{Int, Float64} = 0       # secondary side resistance [Ω]
    Lₛ :: Union{Int, Float64} = 0       # secondary side inductance [H]
    Lₘ :: Union{Int, Float64} = 0      # magnetising inductance [H]
    Rₘ :: Union{Int, Float64} = 0      # magnetising resistance [Ω]
    Cₜ :: Union{Int, Float64} = 0       # turn-to-turn capacitance [F]
    Cₛ :: Union{Int, Float64} = 0       # stray capacitance [F] 
    hasRω :: Bool = false              # Boolean to set frequency-dependent winding resistance [-]
    k:: Union{Int, Float64} = 0        # Exponent for frequency-dependent winding resistance [-]
end

"""
    function transformer(;args...)
Creates a dc or a single phase transfromer, or a three-phase transformer in YY
or ΔY configuration.

```julia
@with_kw mutable struct Transformer
    value :: Array{Basic} = []          # ABCD value

    pins :: Int = 1                     # marks single or three phase
    organization :: Symbol = :YY        # three phase organization (:YY or :ΔY)

    ω :: Union{Int, Float64} = 2*π*50   # rated frequency in [Hz]
    V₁ᵒ :: Union{Int, Float64} = 0      # open circuit primary voltage [V]
    V₁ˢ :: Union{Int, Float64} = 0      # short circuit primary voltage [V]
    I₁ᵒ :: Union{Int, Float64} = 0      # open circuit primary current [V]
    I₁ˢ :: Union{Int, Float64} = 0      # short circuit primary current [V]
    P₁ᵒ :: Union{Int, Float64} = 0      # open circuit losses on primary side [W]
    P₁ˢ :: Union{Int, Float64} = 0      # short circuit losses on primary side [W]
    V₂ᵒ :: Union{Int, Float64} = 0      # open circuit secondary voltage [V]
    V₂ˢ :: Union{Int, Float64} = 0      # short circuit secondary voltage [V]

    n :: Union{Int, Float64} = 0        # turn ratio
    Lₚ :: Union{Int, Float64} = 0       # primary side inductance [H]
    Rₚ :: Union{Int, Float64} = 0       # primary side resistance [Ω]
    Rₛ :: Union{Int, Float64} = 0       # secondary side resistance [Ω]
    Lₛ :: Union{Int, Float64} = 0       # secondary side inductance [H]
    Lₘ :: Union{Int, Float64} = 0      # magnetising inductance [H]
    Rₘ :: Union{Int, Float64} = 0      # magnetising resistance [Ω]
    Cₜ :: Union{Int, Float64} = 0       # turn-to-turn capacitance [F]
    Cₛ :: Union{Int, Float64} = 0       # stray capacitance [F]
end
```

Pins: `1.1`, `2.1` for single phase transformer and `1.1`, `1.2`, `1.3`, `2.1`,
`2.2`, `2.3` for a three-phase transformer.
"""
function transformer(;args...)
    t = Transformer() #mutable struct defined above
    transformation = false #dq transformation
    connection = true      #connection to the network
    for (key, val) in pairs(args)
        if in(key, propertynames(t))
            setfield!(t, key, val)
        elseif (key == :transformation)
            transformation = val
        elseif (key == :connection)
            connection = val
        else
            throw(ArgumentError("Transformer does not have a property $(key)."))
        end
    end
    #computation of the equivalent circuit parameters of a Transformer
    if (t.V₁ᵒ  != 0) #if open circuit primary voltage is defined, enter
        t.n = t.V₁ᵒ / t.V₂ᵒ # turn ratio definition
        # equivalent circuit of a transformer eq(26) pag 18 simulator_tutorial
        R = t.P₁ˢ / (t.I₁ˢ)^2 #resistance-> copper losses from short circuit test
        L = sqrt((t.V₁ˢ*t.I₁ˢ)^2 - t.P₁ˢ^2) / t.ω / (t.I₁ˢ)^2 # leakage inductance
        t.Rₚ = R / 2  # resistance primary side -> copper losses primary side
        t.Rₛ = R / 2 / t.n^2 # resistance secondary side -> copper losses secondary side
        t.Lₚ = L / 2 # inductance primary side -> Leakage flux primary side
        t.Lₛ = L / 2 / t.n^2 # inductance secondary side -> Leakage flux secondary side

        t.Rₘ = (t.V₁ᵒ)^2 / t.P₁ᵒ # magnetising resitance computation
        t.Lₘ = (t.V₁ᵒ)^2 / sqrt((t.V₁ᵒ*t.I₁ᵒ)^2 - t.P₁ᵒ^2) / t.ω # magnetising inductance computation
    end

    # determine ABCD parameters pag18 simulator_tutorial
    # Definition of symbolic expressions
    s = symbols(:s) #allows to use s (in the following passages) as the Laplace operator
    if t.hasRω
        wk = symbols(:wk)  #Frequency-dependent scaling factor of the winding resistance, calculated as wk = (ω/(ω₀))^k, when frequency response is evaluated, eg. calling eval_abcd
    else
    end
    
    #Definition of the matrices that could be used for the ABCD representation
    Zᵖ_winding = convert(Array{Basic},Diagonal([1 for i in 1:2])) #[1 0; 0 1] Diagonal([1 for i in 1:2]) generates a 2*2 diagonal matrix with 1 on the diagonal
    Zˢ_winding = convert(Array{Basic},Diagonal([1 for i in 1:2])) #[1 0; 0 1]
    Y_turn = convert(Array{Basic},Diagonal([1 for i in 1:2]))     #[1 0; 0 1]
    Y_iron = convert(Array{Basic},Diagonal([1 for i in 1:2]))     #[1 0; 0 1]
    Z_stray = convert(Array{Basic},Diagonal([1 for i in 1:2]))    #[1 0; 0 1]

    #Zp_winding matrix
    (t.hasRω) ? Zᵖ_winding[1,2] += s*t.Lₚ + (t.Rₚ*wk) : Zᵖ_winding[1,2] += t.Rₚ + s*t.Lₚ  #pag18 Zp_winding=[1 sLp+Rp; 0 1], inclusion of frequency dependent resistance
    #Zs_winding matrix
    (t.hasRω) ? Zˢ_winding[1,2] += s*t.Lₛ + (t.Rₛ*wk) : Zˢ_winding[1,2] += t.Rₛ + s*t.Lₛ   #pag18 Zs_winding=[1 sLs+Rs; 0 1], inclusion of frequency dependent resistance
    #Y_turn Matrix
    Y_turn[2,1] += s*t.Cₜ #pag18 Y_turn=[ 1 0; sCt 1]
    #N_tr Matrix
    N_tr = [t.n 0; 0 1/t.n] #pag18 N_tr= [n 0; 0 1/n]

    # Y_iron Matrix pag 18
    (t.Lₘ != 0) ? Y_iron[2,1] += 1/s/t.Lₘ : nothing #if Lₘ is defined add it to Yiron matrix otherwise do nothing and go next
    (t.Rₘ != 0) ? Y_iron[2,1] += 1/t.Rₘ : nothing #if Rₘ is defined add it to Yiron matrix otherwise do nothing and go next
    #Z_stray matrix
    (t.Cₛ != 0) ? Z_stray = [1 1/s/t.Cₛ; 0 1] : nothing #if Cₛ is defined add it to Yiron matrix otherwise do nothing and go next
    #[A B; C D]=Y_turn*Z*Y_turn
    Z = Y_turn*(Zᵖ_winding * Y_iron * N_tr * Zˢ_winding)*Y_turn # equation(27) pag 18 in the parenthesis

    (t.Cₛ != 0) ? Z = connect_parallel!(Z, Z_stray) : nothing #if Cₛ is defined make the parallel connection, otherwise do nothing

    if (t.pins == 1) #monophase transformer In this case ABCD representation of a transformer has [2x2] dimension
        t.ABCD = Z #if 1-phase transformer I already have the Z matrix from the calculations done at the rows before
    else #3phase transformer
        if (t.organization == :YY) #winding connected YY
            Z₃ₚ = zeros(Basic, 6, 6) #6*6 matrix of zeros
            for i in 1:3 #for i from 1 to 3
                Z₃ₚ[i,i] = Z[1,1] #A₃ₚ [3x3] matrix
                Z₃ₚ[i,3+i] = Z[1,2] #B₃ₚ [3x3] matrix
                Z₃ₚ[3+i,i] = Z[2,1] #C₃ₚ [3x3] matrix
                Z₃ₚ[3+i,3+i] = Z[2,2] #D₃ₚ [3x3] matrix
            end

            t.ABCD = Z₃ₚ #t.ABCD[A₃ₚ B₃ₚ; C₃ₚ D₃ₚ]
        else #3 phase transformer DeltaY winding
            Zˢ_winding = convert(Array{Basic},Diagonal([1 for i in 1:6])) #diagonal 6*6 ones matrix
            Y_turn = convert(Array{Basic},Diagonal([1 for i in 1:6])) #same
            Z_stray = convert(Array{Basic},Diagonal([1 for i in 1:6])) #same

            (A,B,C,D) = Zᵖ_winding * Y_iron * N_tr
            Z_inner = zeros(Basic,6,6)
            current_conversion = [1/sqrt(3) 0 -1/sqrt(3);  #pag19 (29) [3x3] D_inner matrix
                                  -1/sqrt(3) 1/sqrt(3) 0;
                                  0 -1/sqrt(3) 1/sqrt(3)] .* D
            for i in 1:3
                Z_inner[i,i] = A * sqrt(3) #pag19 (29) [3x3] A_inner matrix
                Z_inner[i, 3+i] = B / sqrt(3) #pag19 (29) [3x3] B_inner matrix
                Z_inner[3+i, i] = C * sqrt(3) #pag19 (29) [3x3] C_inner matrix
                for j in 1:3
                    Z_inner[3+i, 3+j] = current_conversion[i, j]
                end
            end

            if (t.Cₛ != 0)
                Z = connect_parallel!(Z_inner, Z_stray) #pag19 (30)
            else
                Z = Z_inner
            end

            t.ABCD = Y_turn * Z * Y_turn
        end
    end

    elem = Element(input_pins = t.pins, output_pins = t.pins, element_value = t,
        transformation = transformation, connection = connection)
end

function eval_abcd(t :: Transformer, s :: ComplexF64)

    if t.hasRω
        # If the transformer has frequency-dependent winding resistance, we need to the scaling factor, wk
        wk = (abs(s)/(2*π*50))^t.k
        # Replace s with complex frequency jw and wk with the calculated value
        value = N.(subs.(t.ABCD, symbols(:s)=> s, symbols(:wk)=>wk))
    else
        # Replace s with complex frequency jw 
        value = N.(subs.(t.ABCD, symbols(:s)=> s))
    end
    return convert(Array{ComplexF64}, value)
end

function eval_y(t :: Transformer, s :: ComplexF64)
    return abcd_to_y(eval_abcd(t, s))
end

function  make_power_flow!(t :: Transformer, data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)
    
    # Initialize an AC branch between both nodes
    key_branch = branch_ac!(data, nodes2bus, bus2nodes, elem2comp, comp2elem, elem, global_dict)

    # Add transformer data)
    ((data["branch"])[string(key_branch)])["transformer"] = true

    ((data["branch"])[string(key_branch)])["shift"] = 0
    ((data["branch"])[string(key_branch)])["c_rating_a"] = 1

    abcd = eval_abcd(t, global_dict["omega"] * 1im)
    n = 3
    (a, b, c, d) = (abcd[1:n,1:n], abcd[1:n, n+1:end], abcd[n+1:end,1:n], abcd[n+1:end,n+1:end])
    Y = [d*inv(b) c-d*inv(b)*a; -inv(b) a*inv(b)] * global_dict["Z"]

    tap = sqrt(real(Y[n+1,n+1]/Y[1,1]))
    ys = -Y[1,n+1]*tap
    yc = Y[n+1,n+1] - ys

    ((data["branch"])[string(key_branch)])["tap"] = tap
    ((data["branch"])[string(key_branch)])["br_r"] = real(1/ys)
    ((data["branch"])[string(key_branch)])["br_x"] = imag(1/ys)
    ((data["branch"])[string(key_branch)])["g_fr"] = real(yc)/2
    ((data["branch"])[string(key_branch)])["b_fr"] = imag(yc)/2
    ((data["branch"])[string(key_branch)])["g_to"] = real(yc)/2
    ((data["branch"])[string(key_branch)])["b_to"] = imag(yc)/2  
end

