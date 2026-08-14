# This is an PowerImpedance element in order to model a transmission line based on
# line parameters (Z and Y) or ABCD matrix.
# It is a blackbox model, meaning that the internal structure of the line is not modeled.
# The line is represented by its imported frequency-dependent parameters, e.g. line costants (Z,Y)
# or the ABCD two-port parameters. The parameters are in total length.
# The respective parameters can be imported from PSCAD, Ztool or LCMjl.

export blackbox_line

@with_kw mutable struct Blackbox_line <: Transmission_line 

    n :: Int = 3 # Number of phases
    length :: Float64 = 1 # Line length [m]
    data_type :: Symbol = :PSCAD # :PSCAD, :Ztool, :LCMjl #Type of data to be imported
    path :: String = "" # Path to the file containing the data
    Y ::Vector{Matrix{ComplexF64}} = [] # Imported shunt admittance matrix [Ohms/m]
    Z :: Vector{Matrix{ComplexF64}} = [] # Imported series impedance matrix [Siemens/m]
    ABCD :: Vector{Matrix{ComplexF64}} = [] # Imported ABCD matrix
    f:: Vector{Float64} = [] # Imported frequency vector [Hz]

end


function blackbox_line(;args...)
    
    bbl = Blackbox_line()
    transformation = false #variable transformation is defined false (park transformation not operated)
    connection = true #variable connection is defined true (element is connected to the network)
    for (key, val) in pairs(args)
        if in(key, propertynames(bbl))
            setfield!(bbl, key, val) 
        elseif (key == :transformation)
            transformation = val
        elseif (key == :connection)
            connection = val
        else
            throw(ArgumentError("Unknown power line property name.")) #If no one of the value specified above -> display an error
        end
    end

    # Import line constants Z,Y from PSCAD
    if bbl.data_type == :PSCAD


        # Get line constants in polar format from PSCAD
        zm = readdlm(bbl.path * "_zm.out",skipstart=1)
        zp = readdlm(bbl.path * "_zp.out",skipstart=1)
        ym = readdlm(bbl.path * "_ym.out",skipstart=1)
        yp = readdlm(bbl.path * "_yp.out",skipstart=1)

        num_rows = size(zm, 1)
        num_cols = size(zm, 2) -2 # Substract for log(f) and f

        if num_cols/2 != bbl.n

        throw(ArgumentError("Dimension mismatch: Number of phases does not match import data!"))

        end

        rows_per_matrix = bbl.n
        cols_per_matrix = rows_per_matrix


        f = zeros(Float64, num_rows)
        Z = Vector{Matrix{ComplexF64}}(undef, num_rows)
        Y = Vector{Matrix{ComplexF64}}(undef, num_rows)


        for i in 1:num_rows
        f[i] = zm[i, 2]

        # Parse Z and Y values
        # Magnitudes first [Ohms/m] and [Siemens/m]
        Z_flat = [zm[i, j] for j in 3:(3+rows_per_matrix*rows_per_matrix)-1]
        Z[i] = reshape(Z_flat, cols_per_matrix, rows_per_matrix)'  # transpose to match original orientation
        Y_flat = [ym[i, j] for j in 3:(3+rows_per_matrix*rows_per_matrix)-1]
        Y[i] = reshape(Y_flat, cols_per_matrix, rows_per_matrix)'  # transpose to match original orientation


        # Angles second [degrees]
        Z_flat = [exp(im*deg2rad(zp[i, j])) for j in 3:(3+rows_per_matrix*rows_per_matrix)-1]
        Z[i] = Z[i].*transpose(reshape(Z_flat, cols_per_matrix, rows_per_matrix))  # transpose to match original orientation
        Y_flat = [exp(im*deg2rad(yp[i, j])) for j in 3:(3+rows_per_matrix*rows_per_matrix)-1]
        Y[i] = Y[i].*transpose(reshape(Y_flat, cols_per_matrix, rows_per_matrix)) # transpose to match original orientation

        end

        bbl.Z=Z
        bbl.Y=Y
        bbl.f=f

    # Import two-port Y matrix from Ztool
    elseif bbl.data_type == :Ztool
    # TODO: Do interface to Ztool, convert Y to ABCD matrix

         #bbl.ABCD

    # Import line constants Z,Y from LCMjl
    elseif bbl.data_type == :LCMjl

        
        # Read the tab-delimited file (as strings to parse complex numbers)
        raw_data = readdlm(bbl.path, '\t', skipstart=1, String)

        # Determine dimensions
        num_rows = size(raw_data, 1)
        num_cols = size(raw_data, 2)
        half = div(num_cols - 1, 2)
        rows_per_matrix = bbl.n 
        cols_per_matrix = div(half, rows_per_matrix)

        # Initialize arrays
        bbl.f = zeros(Float64, num_rows)
        bbl.Z = Vector{Matrix{ComplexF64}}(undef, num_rows)
        bbl.Y = Vector{Matrix{ComplexF64}}(undef, num_rows)

        # Parse each row
        for i in 1:num_rows
        bbl.f[i] = real(parse(ComplexF64, raw_data[i, 1]))

        # Parse Z and Y values
        Z_flat = [parse(ComplexF64, raw_data[i, j]) for j in 2:1+half]
        Y_flat = [parse(ComplexF64, raw_data[i, j]) for j in 2+half:num_cols]

        # Reshape into matrices
        bbl.Z[i] = reshape(Z_flat, cols_per_matrix, rows_per_matrix)'  # transpose to match original orientation
        bbl.Y[i] = reshape(Y_flat, cols_per_matrix, rows_per_matrix)'
        end


    else 

        throw(ArgumentError("Unknown data type. Use :PSCAD, :Ztool, :LCMjl"))

    end 


    elem = Element(input_pins = bbl.n, output_pins = bbl.n, element_value = bbl,
        transformation = transformation, connection = connection)
    
end



function eval_parameters(bbl :: Blackbox_line, s :: Complex) #function eval_parameters with in input two variables: blackbox_line c and s variable

    if bbl.data_type == :Ztool
        error("No line parameters (Z,Y) available!")
    end

    # Take the imported Y and Z values 
    if s/(2pi*1im) ∈ bbl.f

        Z=bbl.Z[findfirst(==(s/(2pi*1im)), bbl.f)] #Find the index of the frequency point in the frequency vector f that is equal to s/(2pi*1im) and use this index to get the corresponding Z matrix from the list of Z matrices
        Y=bbl.Y[findfirst(==(s/(2pi*1im)), bbl.f)] 
    else # Inter- or extrapolation needed
        #TODO: Implement in a more efficient way, as this creates a new interpolation object every time the function is called.
        Z_interp = linear_interpolation(bbl.f, bbl.Z,extrapolation_bc=Line())
        Y_interp = linear_interpolation(bbl.f, bbl.Y,extrapolation_bc=Line())
        Z=Z_interp(real(s/(2pi*1im))) #
        Y=Y_interp(real(s/(2pi*1im))) # 

    end

    return (Z,Y) #This function returns the value of series impedance Z [Ohm/m] and shunt admittance Y [S/m].

end


# Only function that is called externally, the interface with the rest of the code!
# Two cases: Either the user provides Z and Y, or the user provides the ABCD matrix directly.
function eval_abcd(bbl :: Blackbox_line, s :: Complex)
    
    
    if bbl.data_type == :PSCAD || bbl.data_type == :LCMjl 
    # Case 1: User provides Z and Y directly, calculation of the ABCD matrix as in a normal transmission line!
    (Z, Y) = eval_parameters(bbl, s) #function eval_parameters receives in input variables c and s and gives in output the series impedance matrix Z and the shunt admittance matrix Y
    γ = sqrt(convert(Array{Complex}, Z*Y)) # conversion of arrays product Z*Y and then Γ=sqrt(Z*Y) -> Simulator tutorial pag 19, bottom page (Calculations same as transmission line case)
    # γ = sqrt(Z*Y) #TODO: This line is added to replace the one on the top, which was giving problems for single DC cables (no transformation). Need to see if this will cause any issue with other components, but so far so good.
    Yc = Z \ γ #Always ottom page 19 simulator_tutorial
    n = Int(size(Yc,1)) #Saves in n the number of rows present in the vector Yc
    abcd = zeros(Complex, 2n, 2n) #Creation of the ABCD matrix-> zeros matrix with dimension 2n*2n

    abcd[1:n, 1:n] = cosh(γ*bbl.length) #Eq 33 pag 19 simulator_tutorial. Matrix A[n*n]=cosh(Γl)
    abcd[1:n,n+1:end] = Yc \ sinh(γ*bbl.length) #Eq 33 pag 19 simulator_tutorial. Matrix B[n*n]=Yc^-1sinh(Γl)
    abcd[n+1:end,1:n] = Yc * sinh(γ*bbl.length) #Eq 33 pag 19 simulator_tutorial. Matrix C[n*n]=Ycsinh(Γl)
    abcd[n+1:end, n+1:end] = cosh(γ*bbl.length) #Eq 33 pag 19 simulator_tutorial. Matrix D[n*n]=cosh(Γl)

    # Case 2: User provides the ABCD matrix directly, no calculation needed!

    else

    # Take the imported ABCD matrix 
        if s/(2pi*1im) ∈ bbl.f

            Z=bbl.ABCD[findfirst(==(s/(2pi*1im)), bbl.f)] #Find the index of the frequency point in the frequency vector f that is equal to s/(2pi*1im) and use this index to get the corresponding ABDC matrix from the list of ABCD matrices

        else # Inter- or extrapolation needed
            #TODO: Implement in a more efficient way, as this creates a new interpolation object every time the function is called.
            ABCD_interp = linear_interpolation(bbl.f, bbl.ABCD,extrapolation_bc=Line())
            abcd=ABCD_interp(real(s/(2pi*1im))) #

        end



    end

    return abcd

end
