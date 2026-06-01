export EVD

"""
    EVD(Zcl_bus::Matrix{ComplexF64}, freq::Vector{Float64}; determinant::Bool=false)

Performs Eigenvalue Decomposition (EVD) on the closed-loop bus impedance matrix (`Zcl_bus`) 
across a range of frequencies (`freq`). The function analyzes oscillatory modes, 
determines stability, and computes observability, controllability, and participation factors.

## Parameters
- `Zcl_bus::Matrix{ComplexF64}`: The closed-loop bus impedance matrix as a function of frequency.
- `freq::Vector{Float64}`: The vector of frequency points at which `Zcl_bus` is evaluated.
- `determinant::Bool=false`: If `true`, the function plots the determinant of `Zcl_bus` over frequency.

## Returns
A named tuple containing:
- `eigenvalues::Matrix{ComplexF64}`: Eigenvalues of `Zcl_bus` at each frequency.
- `eigenvectors::Matrix{ComplexF64}`: Corresponding right eigenvectors.
- `observability::Matrix{Float64}`: Observability factors for each eigenvalue.
- `controllability::Matrix{Float64}`: Controllability factors for each eigenvalue.
- `participation::Matrix{Float64}`: Participation factors for each eigenvalue.
- `dominant_mode::Int`: Index of the most critical oscillation mode.
- `critical_freq::Float64`: Frequency at which instability is detected.
- `pmd_stability::Bool`: Stability indicator based on Positive Mode Damping (PMD).
- `pnd_stability::Bool`: Stability indicator based on Positive Net Damping (PND).

## Methodology
1. **Eigenvalue Computation**:
   - Computes eigenvalues (`Λ`) and eigenvectors (`Φ`) for `Zcl_bus` across frequencies.
   - Ensures continuity in eigenvalue sorting using the Hungarian Algorithm (Munkres method).
   - Normalizes eigenvectors for consistency.

2. **Critical Eigenvalue Identification**:
   - Extracts real (`λ_real`), imaginary (`λ_imag`), and magnitude (`λ_mag_dB`) components.
   - Identifies the dominant oscillation mode based on peak eigenvalue magnitude.

3. **Observability, Controllability & Participation Factors**:
   - Computes observability (`O`), controllability (`C`), and participation (`P`) factors.
   - Determines buses with the highest contributions to oscillation modes.

4. **Stability Analysis**:
   - **Positive Mode Damping (PMD)**: Evaluates stability by checking the slope of `λ_imag`.
   - **Positive Net Damping (PND)**: Detects instability based on zero-crossings of `λ_imag`.

5. **Plotting**:
   - Plots magnitude, real, and imaginary parts of eigenvalues vs. frequency.
   - If `determinant=true`, plots the determinant of `Zcl_bus`.

## Example Usage
```julia
Zcl_bus = rand(5, 5) .+ im * rand(5, 5)  # Random complex impedance matrix
freq = range(0, stop=100, length=100)   # Frequency vector from 0 to 100 Hz
result = EVD(Zcl_bus, freq, determinant=true)

println("Dominant Mode: ", result.dominant_mode)
println("Critical Frequency: ", result.critical_freq)
println("PMD Stability: ", result.pmd_stability)
println("PND Stability: ", result.pnd_stability)
```
"""
function EVD(Zcl_bus, omega, fmin, fmax,determinant=false)

    f = real(omega)./(2*pi)

    # Determine eigenvalues of the closed-loop bus impedance matrix at each frequency point 
    Λ = eigvals.(Zcl_bus)
    # Determine the related eigenvectors 
    Φ = eigvecs.(Zcl_bus)

    # Number of frequency points
    omegaₙ = size(Λ, 1)
    # Number of eigenvalues for each frequency point
    λₙ = size(Λ[1], 1)
    # Zcl_bus has dimensions λₙxλₙxomegaₙ 

    # Sorting algorithm of eigenvalues to create continuous lines in EVD plot 
    # Create empty matrix for sorted eigenvalues 
    Λₛ = zeros(Complex{Float64}, omegaₙ, λₙ)
    # First row of eigenvalues remains the same 
    Λₛ[1,:] = Λ[1]

    for i in 2:omegaₙ
        # Row of eigenvalues at previous frequency point 
        Λ₁ = Λ[i-1]
        # Row of eigenvalues at current frequency point
        Λ₂ = Λ[i]

        # Algorithm: 
        # see Munkres.jl https://juliapackages.com/p/munkres
        # see eigenshuffle.m https://nl.mathworks.com/matlabcentral/fileexchange/22885-eigenshuffle
        # Sorting eigenvalues of row i to obtain minimum distance between row i and row i-1
        Λ₁_Re = real(Λ₁)
        Λ₂_Re = real(Λ₂)

        Λ₁_Re_Grid = [i for i in Λ₁_Re, j in 1:length(Λ₂_Re)]
        Λ₂_Re_Grid = [j for i in 1:length(Λ₁_Re), j in Λ₂_Re]

        Λ_Re = abs.(Λ₁_Re_Grid - Λ₂_Re_Grid)

        Λ₁_Im = imag(Λ₁)
        Λ₂_Im = imag(Λ₂)

        Λ₁_Im_Grid = [i for i in Λ₁_Im, j in 1:length(Λ₂_Im)]
        Λ₂_Im_Grid = [j for i in 1:length(Λ₁_Im), j in Λ₂_Im]

        Λ_Im = abs.(Λ₁_Im_Grid - Λ₂_Im_Grid)

        # Possible distances between eigenvalues
        D = sqrt.(Λ_Re.^2 + Λ_Im.^2)
        # Sequence of sorted eigenvalues
        S = munkres(D)

        Λ[i] = Λ[i][S]
        # Insert sorted eigenvalues in matrix Λₛ
        Λₛ[i, :] = Λ[i]
        # Eigenvectors are sorted based on same sequence 
        Φ[i] = Φ[i][:,S]

    end

    Λ = Λₛ

    # Normalizing eigenvectors
    for i in 1:omegaₙ
        for j in 1:λₙ
            N = 1/sqrt(transpose(Φ[i][:,j]) * Φ[i][:,j])
            Φ[i][:,j] = N * Φ[i][:,j]
        end
    end

    Ψ = inv.(Φ)

    # Oscillation modes are determined based on peak value of eigenvalue magnitude 
    λ_real = real.(Λ[:,1])
    λ_imag = imag.(Λ[:,1])
    λ_mag_dB = 20*log10.(abs.(Λ[:,1]))

    # Determining x-axis limits 
    index_fmin = findmin(abs.(f .- fmin))[2]
    index_fmax = findmin(abs.(f .- fmax))[2]

    # Determining y-axis limits
    max_lambda = zeros(λₙ, 1)
    min_lambda = zeros(λₙ, 1)

    abs_lambda = abs.(Λ)
    for i in 1:λₙ
        max_lambda[i] = maximum(abs_lambda[index_fmin:index_fmax, i])
        min_lambda[i] = minimum(abs_lambda[index_fmin:index_fmax, i])
    end

    max_mode = maximum(max_lambda) # Based on the peak magnitude
    y_max = maximum(max_lambda)
    y_min = minimum(min_lambda)

    # Find mode/eigenvalue with highest magnitude 
    mode = findmin(abs.(max_lambda .- max_mode))[2][1]
    index_mode = findmin(abs.(abs_lambda[:, mode] .- max_mode))[2]
    # Dominant oscillation mode is determined based on the frequency at which eigenvalue reaches highest magnitude 
    @info "The oscillation frequency is $(round(f[index_mode]; digits = 1)) Hz"
    @info "The critical eigenvalue is $mode"

    #plotly() # To activate interactive plot
    # Plotting of magnitude eigenvalues 
    p_abs = plot(f, λ_mag_dB, linewidth = 3, c = :blue, label = "Lambda " * string(1))  
    plot!(xlabel = "Frequency [Hz]", ylabel = "abs(lambda) [dB]", framestyle = :box, xaxis = :log10) 
    plot!(xlims = (fmin, fmax), ylims = (20*log10(y_min)-10, 20*log10(y_max)+10), legend = :topleft) #xticks = [10^-3, 10^-2, 10^-1, 10^0, 10^1, 10^2, 10^3, 10^4, 10^5, 10^6]
    color = palette(:default,λₙ) #palette(:tab10)
    for i in 2:λₙ
        λ_mag_dB = 20*log10.(abs.(Λ[:,i]))
        plot!(f, λ_mag_dB, linewidth = 3, c = color[i], label = "Lambda " * string(i))  
    end
    plot!(size=(1000,1000))
    display(p_abs)

    p_im = plot(f, λ_imag, linewidth = 3, c = :blue, label = "Lambda " * string(1))  
    plot!(xlabel = "Frequency [Hz]", ylabel = "Im(lambda)", framestyle = :box, xaxis = :log10) 
    plot!(xlims = (fmin, fmax),  legend = :topleft) 
    color = palette(:default,λₙ) #palette(:tab10)
    for i in 2:λₙ
        λ_imag= imag.(Λ[:,i])
        plot!(f, λ_imag, linewidth = 3, c = color[i], label = "Lambda " * string(i))  
    end
    plot!(size=(1000,1000))
    display(p_im)

    p_re = plot(f, λ_real, linewidth = 3, c = :blue, label = "Lambda " * string(1))  
    plot!(xlabel = "Frequency [Hz]", ylabel = "Re(lambda)", framestyle = :box, xaxis = :log10) 
    plot!(xlims = (fmin, fmax),legend = :topleft) 
    for i in 2:λₙ
        λ_real= real.(Λ[:,i])
        plot!(f, λ_real, linewidth = 3, c = color[i], label = "Lambda " * string(i))  
    end
    plot!(size=(1000,1000))
    display(p_re)

    p = plot(p_abs, p_re, p_im, layout = (3, 1))
    display(p)
    
    # Observability, controllability and participation factors can be determined for dominant oscillation mode at the related frequency point 
    for idx = 1:λₙ
        index_mode_lambda = findmin(abs.(abs_lambda[:, idx] .- max_lambda[idx]))[2]
        O = zeros(λₙ, λₙ);
        for i = 1:λₙ
            for k = 1:λₙ
                O[k,i] = abs(Φ[index_mode_lambda][k, i]);
            end
            Tot = sum(O[:,i])
            for k = 1:λₙ
                O[k, i] = O[k, i]/Tot;   
            end  
        end
        @info "The mode from lambda $idx at $(round(f[index_mode_lambda]; digits=1)) Hz has observability $(round.(O[:,idx]; digits = 2))" 
    end
    
    # Observability eigenvalue decomposition
    O = zeros(λₙ, λₙ);
    # k (Bus) = row; i (Mode) = column
    for i = 1:λₙ
        for k = 1:λₙ
            O[k,i] = abs(Φ[index_mode][k, i]);
        end

        Tot = sum(O[:,i])

        for k = 1:λₙ
            O[k, i] = O[k, i]/Tot;   
        end  
    end
   @info "The observability of the critical eigenvalue at the buses is $(round.(O[:,mode]; digits = 2))"

    # Controllability eigenvalue decomposition
    C = zeros(λₙ, λₙ);
    # k (Bus) = row; i (Mode) = column
    for i = 1:λₙ
        for k = 1:λₙ
            C[k,i] = abs(Ψ[index_mode][i, k]);
        end
        Tot = sum(C[:,i])
        for k = 1:λₙ
            C[k, i] = C[k, i]/Tot;   
        end  
    end
    @info "The controllability of the critical eigenvalue at the buses is $(round.(C[:,mode]; digits = 2))"

    # Participation factors eigenvalue decomposition
    P = zeros(λₙ, λₙ);
    # k (Bus) = row; i (Mode) = column
    for i = 1:λₙ
        for k = 1:λₙ
            P[k,i] = abs(Φ[index_mode][k, i] * Ψ[index_mode][i, k]);
        end
        Tot = sum(P[:,i])
        for k = 1:λₙ
            P[k, i] = P[k, i]/Tot;   
        end  
    end
    @info "The participation factors of the buses in the critical eigenvalue are $(round.(P[:,mode]; digits = 2))"

    # Two ways of finding and assessing the oscillatory modes: (1) PMD and (2) PND
    # Positive mode damping (PMD) criterion 
    # Find more information here: Luis Orellana, et al. "Study of black-box models and participation factors for the Positive-Mode Damping stability criterion",2023
    # https://doi.org/10.1016/j.ijepes.2023.108957
    PMD_modes = Vector{Vector{Float64}}(undef,λₙ) # Vector with the oscillatory modes for each eigenvalue of the closed-loop impedance matrix
    PMD_unstable = false # Initialize variable
    # Positive Net Damping (PND) criterion https://upcommons.upc.edu/bitstream/handle/2117/114185/PND%20criterion%20post-print-1.pdf
    PND_modes = Vector{Vector{Float64}}(undef,λₙ) # Vector with the oscillatory modes for each eigenvalue of the closed-loop impedance matrix
    PND_unstable = false # Initialize variable

    real_lambda = real.(Λ) # also the real and imaginary parts
    imag_lambda = imag.(Λ)
    
    # (1) For each eigenvalue the PMD criterion is applied
    for i in 1:λₙ
        # PMD: Find the peaks of the magnitude (oscillatory modes)
        critical_points_PMD = argmaxima(abs_lambda[index_fmin:index_fmax,i])
        if length(critical_points_PMD)>0
            modes = []  
            # println("Eigenvalue ",i," has the following local maxima")
            for point in critical_points_PMD
                if abs(f[index_fmin+point]-50.0) > 0.5
                    # Around the synchronous frequency, the stability assessment might be blurred by the frame transformation effects so skip it
                    # println(" ",abs_lambda[index_fmin+point,i]," at ",f[index_fmin+point]," Hz")
                    # Compute the slope of the imaginary part (PMD)
                    if index_fmin+point-1 > 0
                        kx = imag_lambda[index_fmin+point, i] - imag_lambda[index_fmin+point-1, i]
                    else
                        kx = imag_lambda[index_fmin+point+1, i] - imag_lambda[index_fmin+point, i]
                    end
                    
                    # PMD criteria
                    if (kx > 0 && real_lambda[index_fmin+point, i]<0) || (kx < 0 && real_lambda[index_fmin+point, i]>0)
                    # Stable iff real part of the dominant state-space eigenvalue is negative
                    # However, for some local maxima, the PMD result is unstable even if the system is stable
                    else
                        # Unstable with an oscillatory mode at this frequency
                        PMD_unstable = true
                        push!(modes,f[index_fmin+point])
                    end
                end
            end
            PMD_modes[i] = modes # Af the oscillatory modes to the list
        else
            PMD_modes[i] = []
        end
    end

    if PMD_unstable
        @info "Unstable according to the PMD criterion:"
        for i in 1:λₙ
            if length(PMD_modes[i])>0
                for mode in PMD_modes[i]
                    @info " Eigenvalue $i is unstable at $(round(mode; digits = 2)) Hz"
                end
            end
        end
    else
        @info "Stable according to the PMD criterion"
    end


    # (2) For each eigenvalue the PND criterion is applied
    min_real_lambda = zeros(λₙ, 2) # First column is the minimum real part of each lambda at the osc freqs, and second the index
    for i in 1:λₙ
        # Find the zero crossing of the imaginary part (oscillatory modes)
        sign_changes = diff(signbit.(imag_lambda[index_fmin:index_fmax,i])) .!= 0
        critical_points_PND = findall(sign_changes)
        if length(critical_points_PND)>0
            modes = []
            real_parts = []
            idx_reals = []
            # println("Zero-crossings of the imaginary part of eigenvalue ",i)
            for point in critical_points_PND
                if abs(f[index_fmin+point]-50.0) > 0.5
                    # Around the synchronous frequency, the stability assessment might be blurred by the frame transformation effects so skip it
                    # println(" Crossing at ",f[index_fmin+point]," Hz")
                    
                    # PND criteria
                    if real_lambda[index_fmin+point, i]>0
                        # Stable: if the closed-loop has positive damping at the resonance points (imag = 0)
                        # More conservative than the PMD criteria
                    else
                        # Unstable with an oscillatory mode at this frequency
                        PND_unstable = true
                        push!(modes,f[index_fmin+point])
                    end
                    push!(real_parts,real_lambda[index_fmin+point, i])
                    push!(idx_reals,index_fmin+point)
                end
            end
            PND_modes[i] = modes # Add the oscillatory modes to the list
            if length(real_parts)>0
                min_real_lambda[i,1] = findmin(real_parts)[1]
                min_real_lambda[i,2] = idx_reals[findmin(real_parts)[2]]
            else
                min_real_lambda[i,1] = 1e20 # Very large value
                min_real_lambda[i,2] = 1
            end
        else
            PND_modes[i] = []
            min_real_lambda[i,1] = 1e20 # Very large value to handle missing modes in a given lambda
            min_real_lambda[i,2] = 1
        end
    end

    if PND_unstable
        @info "Unstable according to the PND criterion:"
        for i in 1:λₙ
            if length(PND_modes[i])>0
                for mode in PND_modes[i]
                    @info " Eigenvalue $i is unstable at $(round(mode; digits = 2)) Hz"
                end
            end
        end
    else
        @info "Stable according to the PND criterion"
    end

    min_mode_PND = findmin(min_real_lambda[:,1])[2]
    index_mode_PND =  Int.(min_real_lambda[min_mode_PND,2])
    # Dominant oscillation mode is determined based on the minimum real part
    @info "The critical frequency based on PND is $(round(f[index_mode_PND]; digits = 1)) Hz at eigenvalue $min_mode_PND"

    # Participation factors eigenvalue decomposition
    P = zeros(λₙ, λₙ);
    # k (Bus) = row; i (Mode) = column
    for i = 1:λₙ
        for k = 1:λₙ
            P[k,i] = abs(Φ[index_mode_PND][k, i] * Ψ[index_mode_PND][i, k]);
        end
        Tot = sum(P[:,i])
        for k = 1:λₙ
            P[k, i] = P[k, i]/Tot;   
        end  
    end
    @info "The participation factors of the buses in the critical eigenvalue based on PND are $(round.(P[:,min_mode_PND]; digits = 2))"

    if determinant
        d = abs.(inv.(det.(Zcl_bus)))
        # d = abs.(det.(Zcl_bus))
        det_plot = plot(f, d, linewidth = 3, c = :blue, label = "G^-1 " * string(1))  
        plot!(xlabel = "Frequency [Hz]", ylabel = "Magnitude", framestyle = :box, xaxis = :log10, yaxis = :log10) 
        plot!(xlims = (fmin, fmax), ylims = (0.9*minimum(d), 1.1*maximum(d)), legend = :topleft) 
    end

end