export cable #function row 81 -> possible up to 4 conducting and insultating layers. Cable group of n cables possible.
export Insulator, Conductor #mutable structures row 4, 13 and 23
# first letter of the variable: Capital -> Mutable Structure (e.g. Cable, Insulator, Conductor), lowercase -> function (e.g. cable)
@with_kw mutable struct Conductor #conducting layer //macro @with_kw which decorates a type definition and allow default values and a keyword construct
    rᵢ :: Union{Int, Float64} = 0              # inner radius
    rₒ :: Union{Int, Float64} = 0              # outer radius
    ρ  :: Union{Int, Float64} = 0              # conductor resistivity [Ωm]
    μᵣ  :: Union{Int, Float64} = 1             # relative permeability

    A :: Union{Int, Float64} = 0               # nominal area
end

@with_kw mutable struct Insulator #insulating layer
    rᵢ :: Union{Int, Float64} = 0               # inner radius
    rₒ :: Union{Int, Float64} = 0               # outer radius #Insulator defined between rᵢ < r < rₒ
    ϵᵣ :: Union{Int, Float64} = 1               # relative permittivity
    μᵣ :: Union{Int, Float64} = 1               # relative permeability
                                                # If a semiconductor is present, in an insulator, we have: rᵢ < semiconductor < a + a < insulator < b + b < semiconductor < rₒ
    a :: Union{Int, Float64} = 0                # inner semiconductor thickness
    b :: Union{Int, Float64} = 0                # outer semiconductor thickness
    # From PSCAD manual:
    # A = outer radius of inner conductor + thickness of inner semiconducting screen
    # B = outer radius of inner conductor + thickness of inner semiconducting screen + thickness of insulator layer
    # rₒ = outer radius of inner conductor + thickness of inner semiconducting screen + thickness of insulator layer + thickness of outer semiconducting screen
    # rᵢ = outer radius of inner conductor
end

@with_kw mutable struct Cable <: Transmission_line #indicates that the mutable struct Cable is a subtype (<:) of abstract type Transmission_line
    length :: Union{Int, Float64} = 0                    # line length [m]. Union -> it could be both Int or Float64
    conductors :: OrderedDict{Symbol, Conductor} = OrderedDict{Symbol, Conductor}() #OrderedDict -> dictionary with a particular order. Key: Symbol-> C1, C2, C3 and C4. Value: Conductor-> Mutable Struct Conductor, defined above
    insulators :: OrderedDict{Symbol, Insulator} = OrderedDict{Symbol, Insulator}() #OrderedDict -> dictionary with a particular order. Key: Symbol-> I1, I2, I3 and I4. Value: Insulator-> Mutable Struct Insulator, defined above
    positions :: Vector{Tuple{Real,Real}} = [] #Real -> indicates all variables are real number, vector composed by tuple of real numbers. e.g. positions=[(0,0),(1,1)]. Cables positions 1st:x=0, y=0. 2nd: x=1, y=1.
    earth_parameters :: NTuple{N, Union{Int,Float64}} where N = (1,1,1) # (μᵣ, ϵᵣ, ρ) in units ([], [], [Ωm]) compact way of representing the type for a tuple of length N where all elements are of type Int or Float64.
    configuration :: Symbol = :coaxial #Configuration is a datatype symbol with value coaxial Symbol -> Type of data. Symbols can be entered using the quote operator ":"
    type :: Symbol = :underground   # or aerial. for the description, see above.

    P :: Array{Basic} = [] #initialization (still no value inside) of the array P with datatype Basic
    Z :: Array{Basic} = [] #same as row above

    eliminate :: Bool = true #eliminate-> variable with Bool datatype and value TRUE (Bool variable can be true or false)-> predifined with true value. If not specified elsewhere in the code, eliminate=true
end

"""
    cable(;args...)
Generates the element `elem` with the  `element_value` of the type `Cable`. Arguments should be given in the
form of struct `Cable` fields:
- length - length of the cable in [m]
- earth\\_parameters - (μᵣᵍ, ϵᵣᵍ, ρᵍ) in units ([], [], [Ωm])
meaning ground (earth) relative premeability, relative permittivity and
ground resistivity
- conductors - dictionary with the key symbol being: C1, C2, C3 or C4, and the value
given with the struct `Conductor`. If the sheath consists of metalic screen and sheath,
then add screen with a key symbol SC and sheath with C2.
```julia
struct Conductor
    rᵢ :: Union{Int, Float64} = 0              # inner radius
    rₒ :: Union{Int, Float64} = 0              # outer radius
    ρ  :: Union{Int, Float64} = 0              # conductor resistivity [Ωm]
    μᵣ  :: Union{Int, Float64} = 1             # relative premeability

    A :: Union{Int, Float64} = 0               # nominal area

    screen_r :: Union{Int, Float64} = 0        # metalic screen outer radius
    screen_ρ :: Union{Int, Float64} = 0        # metalic screen resistivity [Ωm]
end
```
- insulators - dictionary with the key being symbol: I1, I2, I3 and I4, and the value #FP Keys: I1, I2, I3, I4
given with the struct `Insulator`. For the insulator 2 the semiconducting layers #FP: Capital letters -> Struct
can be added by specifying outer radius of the inner semiconducting layer and
inner radius of the outer semiconducting layer.
```julia
struct Insulator
    rᵢ :: Union{Int, Float64} = 0               # inner radius
    rₒ :: Union{Int, Float64} = 0               # outer radius
    ϵᵣ :: Union{Int, Float64} = 1               # relative permittivity
    μᵣ :: Union{Int, Float64} = 1               # relative permeability

    a :: Union{Int, Float64} = 0                # inner semiconductor thickness
    b :: Union{Int, Float64} = 0                # outer semiconductor thickness
end
```
- positions - given as an array in (x,y) format
- configuration - symbol with two possible values: coaxial (default) and pipe-type
- type - symbol representing underground or aerial cable
"""
function cable(;args...) # in parenthesis the input of the function julia uses "..." to describe a variable number of arguments. Variable because depends on the cable/insulator/sheath structure
    c = Cable() #variable c is become a mutable structure type-> Cable
    transformation = false #variable transformation is defined false (park transformation not operated)
    connection = true
    for (key, val) in pairs(args)
        if key == :positions
            for v in val
                push!(c.positions, v) #insert v at the end of c.position ->variable position in c
            end
        elseif in(key, propertynames(c))
            setfield!(c, key, val) #assign val to a key field in c??
        elseif isa(val, Conductor) #if val is a Conductor -> enter
            c.conductors[key] = val
        elseif isa(val, Insulator) #if val is an Insulator -> enter
            c.insulators[key] = val
        elseif (key == :transformation)
            transformation = val
        elseif (key == :connection)
            connection = val
        else
            throw(ArgumentError("Unknown cable property name.")) #If no one of the value specified above -> display an error
        end
    end

    # conversion procedure #not FP
    # core outer radius    #not FP
    # TODO: Add a check for positions to see if the cable positions make sense (when compared to the radii)
    (c.conductors[:C1].A != 0 && c.conductors[:C1].A != 0.0) ? c.conductors[:C1].ρ = c.conductors[:C1].ρ * π *
                        c.conductors[:C1].rₒ^2 / c.conductors[:C1].A : nothing #If the equivalent area of C1 is different from 0 -> "conversion" operation, othewise do nothing.
    # add metalic screen conversions, equivalent sheat layer
    if in(:SC, keys(c.conductors)) #true if in the keys of the variable conductors (Mutable structure Conductor) it is defined a semiconductor-> key :SC, row 48 of this code
        !in(:C2, keys(c.conductors)) && throw(ArgumentError("There must be present sheath together with screen layer.")) #If key C2 is not present in conductors variable (Conductor mutable structure) throw a message error: "C2 must be...""
        if (c.conductors[:SC].A != 0 && c.conductors[:SC].A != 0.0) #if the equivalent area of the semi conductor is defined and different from zero-> enter
            c.conductors[:C2].rᵢ = sqrt(c.conductors[:SC].rₒ^2 - c.conductors[:SC].A / π) #The internal radium of the conductor C2 is -> External radius of the Screen - Equivalent Screen radius
        else
            c.conductors[:C2].rᵢ = c.conductors[:SC].rᵢ #If the screen equivalent area is not defined -> put the internal radius of the conductor C2 equal to the internal screen radius
        end
        c.conductors[:C2].rₒ = sqrt((c.conductors[:C2].rₒ^2 - c.conductors[:SC].rₒ^2) *
                    c.conductors[:SC].ρ / c.conductors[:C2].ρ + c.conductors[:SC].rₒ^2) # Rₒc₂= sqrt( (Rₒc₂²-Rₒsc²) * ρsc/ρc₂ + Rₒsc²)
        delete!(c.conductors, :SC) #delete!(collection, key)-> Delete the mapping for the given key in a collection, and return the collection. In this case, returns the value of the collection conductors, withouth the key :SC.

        # change Insulator 1
        c.insulators[:I1].rₒ = c.conductors[:C2].rᵢ #external radius of the Insulator 1 = Internal radius of the conductor C2 -> Rₒ(I₁)= Rᵢ(C₂)
        # change Insulator 2
        if in(:I2, keys(c.insulators)) #if I2 is present in the keywords of the variable insulators -> enter the if cycle
            x = log(c.insulators[:I2].rₒ / c.conductors[:C2].rₒ) / log(c.insulators[:I2].rₒ / c.insulators[:I2].rᵢ) # x = log(rₒI₂/rₒC₂)/log(rₒI₂/rᵢI₂)
            c.insulators[:I2].rᵢ = c.conductors[:C2].rₒ # RᵢI₂ = RₒC₂ -> The internal radius of insulator I2 is equal to the outer radius of conductor C2.
            c.insulators[:I2].ϵᵣ *=  x #Same as c.insulators[:I₂].ϵᵣ =  c.insulators[:I₂].ϵᵣ*x ->  ϵᵣI₂ = ϵᵣI₂ * x
            c.insulators[:I2].μᵣ /= x #Same as c.insulators[:I₂].μᵣ =  c.insulators[:I₂].μᵣ/x ->  μᵣI₂ = μᵣI₂ / x
        end
    end
    # semiconductor configuration
    if in(:I1, keys(c.insulators)) && (c.insulators[:I1].a != 0) && (c.insulators[:I1].a != 0.0) #If in the keys of the variable c is defined I₁ AND I₁ has a semiconductor section (outer radius, inner semiconductor different from 0) -> enter
        A = c.insulators[:I1].rᵢ + c.insulators[:I1].a
        B = c.insulators[:I1].rₒ - c.insulators[:I1].b
        x = log(c.insulators[:I1].rₒ / c.insulators[:I1].rᵢ) / log(B / A) # x = log(rₒI₁/rᵢI₁)/log(bI₁/aI₁)
        c.insulators[:I1].ϵᵣ *=  x #Same as c.insulators[:I₁].ϵᵣ =  c.insulators[:I₁].ϵᵣ*x ->  ϵᵣI1 = ϵᵣI₁ * x
        #TODO: The impact of the semiconducting layers on permeability is disabled, as it is not represented in PSCAD.
        # N = 1.4
        # c.insulators[:I1].μᵣ = c.insulators[:I1].μᵣ * (1 + 2*π^2 * N^2 * (c.insulators[:I1].rₒ^2 - c.insulators[:I1].rᵢ^2) / log(c.insulators[:I1].rₒ / c.insulators[:I1].rᵢ)) # μᵣI₁ = μᵣI₁ * (1+2π²N² * (rₒI₁²-rᵢI₁²) / log(rₒI₁-rᵢI₁))
    end

    (μᵣᵍ, ϵᵣᵍ, ρᵍ) = c.earth_parameters

    μ₀ = 4π*1e-7 #vacuum permeability
    ϵ₀ = 8.85e-12 #vacuum permittivity
    μᵍ = μᵣᵍ*μ₀ #ground permittivity  μᵍ = relative ground permittivity μᵣᵍ * vacuum permittivity μ₀
    ϵᵍ = ϵᵣᵍ*ϵ₀ #ground permeability ϵᵍ = relative ground permeability ϵᵣᵍ * vacuum permeability ϵ₀
    σᵍ = 1/ρᵍ #ground conductivity σᵍ = 1/ground resistivity ρᵍ
    γ = 0.5772156649
    g = 1e-11
    s = symbols(:s) #definition of the variable S -> used for the implementation in the frequency domain

    nₗ = length(c.conductors)       # number of cable layers -> the number of layers is defined on the length of the conductors ordered dictionary
    n = length(c.positions)        # number of cables -> the number of cables is defined on the length of the position vector
    Z = zeros(Basic,n*nₗ,n*nₗ)      # Impedance matrix dimension [(number of cables*number of conductive layers),(number of cables*number of conductive layers)]
    P = zeros(Basic,n*nₗ,n*nₗ)

    # make series impedance #pag24 simulator_tutorial
    i = 1 #between rows 153 and 181 -> CONDUCTORS Case (no insulators) -> i need as external indicator. It is needed to compute the Z matrix position until key is inside the number of keys present in conductors
    for key in keys(c.conductors) #depending on how many keys are present in the variable conductors -> it makes the same process for all the conductors present in the variable c
        (rᵢ, rₒ, μ, ρ) = (c.conductors[key].rᵢ, c.conductors[key].rₒ, c.conductors[key].μᵣ*μ₀, c.conductors[key].ρ) #Assigns to the local (inside the for cycle) variables rᵢ, rₒ, μ, ρ -> the values defined for each cable conductor. Done with [Key]
        m = sqrt(s*μ/ρ) #defined at eq.(39) pag 24 simulator_tutorial
        Δr = rₒ - rᵢ #external conductor radius - internam conductor radius.
        if (rᵢ != 0) #if the cable is hollow -> enter
            Zᵃᵃ = ρ*m/(2π*rᵢ)*coth(m*Δr) - ρ/(2π*rᵢ*(rᵢ+rₒ)) #inner surface impedance Zₐₐ-> eq 39 pag 24 simulator_tutorial
            Zᵇᵇ = ρ*m/(2π*rₒ)*coth(m*Δr) + ρ/(2π*rₒ*(rᵢ+rₒ)) #outer surface impedance Zbb-> eq 39 pag 24 simulator_tutorial
        else #non-hollow cable: rᵢ=0
            Zᵇᵇ = ρ*m/(2π*rₒ)*coth(0.733m*rₒ) + 0.3179ρ/(π*rₒ^2) #outer surface impedance Zbb -> eq 40 pag 24
        end
        Zᵃᵇ = ρ*m/(π*(rₒ+rᵢ))*csch(m*Δr) #eq 39 pag 24 simulator_tutorial

        Z[i,i] += Zᵇᵇ
        if (i > 1) #if there is more than one conducting layer -> enter
            Z[i,i-1] += -Zᵃᵇ #eq 44 pag 24 simulator tutorial -> not taking into account the insulator material Zi
            Z[i-1,i] += -Zᵃᵇ #same as row above
            Z[i-1,i-1] += Zᵃᵃ #diagonal term eq 44 pag 24 without insulator Zi and last layer ground Zg impedance
        end
        if (i == nₗ) #for the conductor impedance at the last cable layer -> need to consider also the ground. 3rd eq of eq 44 pag 24 simulator_tutorial
            m = sqrt(s*μᵍ/ρᵍ) #same as row 156, this time with ground permeability μᵍ and resistivity ρᵍ
            H = 2c.positions[1][2] # H = 2yi
            dᵢⱼ = max(maximum([r.rₒ for r in values(c.conductors)]), maximum([r.rₒ for r in values(c.insulators)])) #return the maximum cable radius independently if it's an insulator or a conductor
            x = dᵢⱼ # x will be used later
            Zᵍ = s*μᵍ/(2π) * (-log(γ*m*dᵢⱼ/2) + 0.5 - 2*m*H/3) #equation 42 at pag 24 of simulator_tutorial
            Z[i,i] += Zᵍ #eq 44 pag 24 simulator tutorial, adding Zg at the Zii(nc,nc) expression
        end
        i += 1
    end

    # make shunt admittance -> Insulator
    i = 1 #re-assign the value 1 to i
    for key in keys(c.insulators) #As described at row 154 for the conductors-> depending on how many keys are present in the variable insulators -> it makes the same process for all the insulating layers present in the variable c
        (rᵢ, rₒ, μ, ϵ) = (c.insulators[key].rᵢ, c.insulators[key].rₒ, c.insulators[key].μᵣ*μ₀, c.insulators[key].ϵᵣ*ϵ₀)
        # The lines below are supposed to be true, but are changing the stability analysis results. To be checked.
        # if (c.insulators[key].b != 0) && (c.insulators[key].b != 0.0)
        #     rₒ -= c.insulators[key].b 
        # end
        Zⁱ = s*μ/(2π) * log(rₒ/rᵢ) #insulator layer impedance -> eq 41 pag 24
        Pⁱ = log(rₒ/rᵢ) / (2π*ϵ) #p expression pag25 2nd row simulator_tutorial

        Z[i,i] += Zⁱ #for the impedance matrix diagonal values add also the insulator impedance-> showed in 1st row eq 44 pag 24 simulator_tutorial
        P[1:i,1:i] += ones(i,i) * Pⁱ
        i += 1 #FP check this for cycle better
    end

    for i in 1:n #n= number of cables
        Z[(i-1)*nₗ+1:i*nₗ, (i-1)*nₗ+1:i*nₗ] = Z[1:nₗ,1:nₗ] #copy and translate the same conductor impedance matrix dependently on how many cables are present (assumption all the cable same)-> does the mutual contribution between cables are accounted? it seems not e.g. if n=2 Z13=0 -> no mutual effect between 1st conducting layer of cable 1 and 1st conducting layer of cable 2-> test change distance between cables and see if there is any effect
        P[(i-1)*nₗ+1:i*nₗ, (i-1)*nₗ+1:i*nₗ] = P[1:nₗ,1:nₗ] #nₗ also for the insulators? Why?
        for j in i+1:n      # adding earth return impedance FP: and MUTUAL IMPEDANCE BETWEEN CABLES -> why j starts from i+1 and not i? Already considered at row 175 the auto-effect
            m = sqrt(s*μᵍ/ρᵍ) #m defined below eq 39 pag24
            H = c.positions[i][2] + c.positions[j][2] #H= sum of depth of ith and jth cables-> yi+yj eq 43 pag 24 simulator tutorial. if i=j ->2yj -> correct result
            dᵢⱼ = sqrt((c.positions[i][1] - c.positions[j][1])^2 + (c.positions[i][2] - c.positions[j][2])^2) #dij= distance between the center points of the ith and the jth cables sqrt((xi-xj)^2+(yi-yj)^2)
            x = abs(c.positions[i][1] - c.positions[j][1]) #Why is computed here x? it is not used here in this for cycle. -> x= horizontal distance between the ith and the jth cables
            Zᵍ = s*μᵍ/(2π) * (-log(γ*m*dᵢⱼ/2) + 0.5 - 2*m*H/3) #eq 45 pag 24 simulator_tutorial s=jω
            Z[i*nₗ, j*nₗ] += Zᵍ #values added every nl-> where nl stands for "number of layers" -> assumpion: cables all at the same distance -> same effect between them
            Z[j*nₗ, i*nₗ] += Zᵍ #same as the row above, but in the mutual position -> mutual impedances between two cables -> same e.g. Z12=Z21
        end
    end

    # reduction for represention core, sheath and armor
    for k in 1:n, l in 1:n #nested for cycle with a short notation. assuming 3 conductors: n=3 -> (k,l)= (1,1) -> (1,2) -> (1,3) -> (2,1) -> (2,2) -> (2,3) -> (3,1) -> (3,2) -> (3,3)
        for i in nₗ-1:-1:1, j in 1:i #another time (as above) nested for cycle if nₗ=2-> just i=j=1 if nₗ=3 -> (i,j)= (2,1) -> (2,2) -> (1)
            Z[(l-1)nₗ+1:l*nₗ, (k-1)*nₗ + j] += Z[(l-1)nₗ+1:l*nₗ, (k-1)*nₗ + i+1]
        end
        for i in nₗ-1:-1:1, j in 1:i
            Z[(k-1)*nₗ + j, (l-1)nₗ+1:l*nₗ] += Z[(k-1)*nₗ + i+1, (l-1)nₗ+1:l*nₗ] #  See pictures on the phone
        end
    end

    if (c.type == :underground) #if the cable is underground-> by definition it is.
        for i in 1:n, j in 1:n #n= number of cables present-> for cycle between different cables -> i and j
            H = c.positions[i][2] + c.positions[j][2] #equation 43 pag 24 simulator_tutorial ->sum of the two cables burial depths
            x = abs(c.positions[i][1] - c.positions[j][1]) #horizontal distance between the two considered cables
            y = abs(c.positions[i][2] - c.positions[j][2]) #vertical distance between the two considered cables
            (i == j) ? (D₁ = max(maximum([r.rₒ for r in values(c.conductors)]), maximum([r.rₒ for r in values(c.insulators)])); D₂ = H) : (D₁ = sqrt(x^2 + y^2); D₂ = sqrt(x^2 + H^2)) # ? -> Ternary operator e.g. "a ? b : c" -> evaluate b if a is true, otherwise evaluate c. In this case-> first expression if the cable is the same -> compute quantities for Pii calculation. Otherwise, second expression -> compute quantities for Pij computation.
            Pᵢⱼ = log(D₂ / D₁) / (2π*ϵ₀) #third row below eq 45 pag 25 simulator_tutorial // Above, it is used in the first conditional expression D₂=H and not D₂=2H as reported on the simulator_tutorial, because here H is already computed as hi+hj, or better in this case, hi+hi

            P[(i-1)nₗ+1:i*nₗ , (j-1)nₗ+1:j*nₗ] += ones(nₗ, nₗ) * Pᵢⱼ
        end
    end

    c.P = P
    c.Z = Z

    elem = Element(input_pins = n, output_pins = n, element_value = c,
            transformation = transformation, connection = connection)
end

function eval_parameters(c :: Cable, s :: Complex) #function eval_parameters with in input two variables: cable c and s variable
    P = N.(subs.(c.P, symbols(:s), s)) #TBC
    P = convert(Array{Float64}, real(P)) + 1im*convert(Array{Float64}, imag(P)) #converts the Real part of P in a float 64 array + imaginary part of P (always float 64), multiplied by 1im because imag(P) returns a real value
    P = convert(Array{ComplexF64}, P) #convert P in a complex array and save it in P

    Z = N.(subs.(c.Z, symbols(:s), s)) #TBC
    Z = convert(Array{Float64}, real(Z)) + 1im*convert(Array{Float64}, imag(Z)) #converts the Real part of Z in a float 64 array + imaginary part of Z (always float 64), multiplied by 1im because imag(P) returns a real value
    Z = convert(Array{ComplexF64}, Z) #convert Z in a complex array and save it in Z

    if (c.eliminate)            #apply Kron elimination to additional layers -> eliminate = boolean variable with predifined value= true. If we don't want to operate the lines in this cycle: define eliminate = false (in the variable c)
        nₗ = length(c.conductors) #nₗ indicates the number of layers present
        n = length(c.positions) #n indicates, based on the length of the position array, how many cables are present in the electric circuit
        cond_noElim = [(i-1)*nₗ + 1 for i in 1:n] #cond_noElim gives in output the position of the core conductors -> conductors that must not be eliminated. e.g. nₗ = 4; n = 3, cond_noElim = [1 5 9]
        Z = kron(Z, cond_noElim) #Assumption -> sheath and armor grounded-> Kron reduction -> only the cores voltage/current relation remain
        P = kron(P, cond_noElim) #Assumption -> sheath and armor grounded-> Kron reduction -> only the cores of the conductors remain
    end
    Y = s*inv(P) #Shunt admittance matrix: Y=sP^-1 -> pag24 simulator_tutorial
    return (Z,Y) #This function returns the value of series impedance Z and shunt admittance Y.
end

function eval_abcd(c :: Cable, s :: Complex)
    (Z, Y) = eval_parameters(c, s) #function eval_parameters receives in input variables c and s and gives in output the series impedance matrix Z and the shunt admittance matrix Y
    γ = sqrt(convert(Array{ComplexF64}, Z*Y)) # conversion of arrays product Z*Y and then Γ=sqrt(Z*Y) -> Simulator tutorial pag 19, bottom page (Calculations same as transmission line case)
    # γ = sqrt(Z*Y) #TODO: This line is added to replace the one on the top, which was giving problems for single DC cables (no transformation). Need to see if this will cause any issue with other components, but so far so good.
    Yc = Z \ γ #Always ottom page 19 simulator_tutorial
    n = Int(size(Yc,1)) #Saves in n the number of rows present in the vector Yc
    abcd = zeros(Complex, 2n, 2n) #Creation of the ABCD matrix-> zeros matrix with dimension 2n*2n

    abcd[1:n, 1:n] = cosh(γ*c.length) #Eq 33 pag 19 simulator_tutorial. Matrix A[n*n]=cosh(Γl)
    abcd[1:n,n+1:end] = Yc \ sinh(γ*c.length) #Eq 33 pag 19 simulator_tutorial. Matrix B[n*n]=Yc^-1sinh(Γl)
    abcd[n+1:end,1:n] = Yc * sinh(γ*c.length) #Eq 33 pag 19 simulator_tutorial. Matrix C[n*n]=Ycsinh(Γl)
    abcd[n+1:end, n+1:end] = cosh(γ*c.length) #Eq 33 pag 19 simulator_tutorial. Matrix D[n*n]=cosh(Γl)
    return abcd
end
