export passivity
"""
    passivity(G, omega, title::String = "Passivity assessment")

Assesses the passivity of a system by computing the minimum real part of the eigenvalues of a given 
transfer function matrix `G` across a frequency range `omega` and visualizing the results.

## Parameters
- `G::Array{Matrix{Complex}}`: A collection of system matrices evaluated at different frequencies.
- `omega::Vector{Real}`: A vector of angular frequencies (in rad/s) at which `G` is evaluated.
- `title::String`: (Optional) Title of the passivity plot. Default is `"Passivity assessment"`.

## Returns
- `Vector{Float64}`: The passivity index, which is the minimum real part of the eigenvalues of `G(omega)` at each frequency.

## Methodology
1. **Compute Eigenvalues**:
   - The eigenvalues of `G(omega)` are calculated at each frequency.
   - The passivity index is determined as the minimum real part of these eigenvalues.

2. **Visualization**:
   - A plot is generated showing the passivity index across the frequency range.
   - A dashed red line at `y = 0` serves as a reference.
   - The x-axis is displayed on a logarithmic scale.

## Example Usage
```julia
# Define example data
omega = 2 * pi * logspace(-3, 6, 100)  # Frequency range in rad/s
G = [rand(ComplexF64, 2, 2) for _ in omega]  # Example transfer function matrices

# Passivity analysis
passivity_index = passivity(G, omega)

println("Passivity Index:\n", passivity_index)
```
"""
function passivity(G, omega, title :: String = "Passivity assessment")

    f = real(omega)./(2*pi)

    # Determine minimum real part of the eigenvalues of the matrix at each frequency
    passivity_index = minimum.(real.(eigvals.(G .+ adjoint.(G))))
    # plotly() # To activate interactive plot
    p_plot = plot(f, passivity_index, linewidth = 3, c = :blue, label = "G(s)")  
    plot!([f[1],f[end]], [0,0], linewidth = 1.5, c = :red, line = :dash, label = "Zero")  
    plot!(xlabel = "Frequency [Hz]", ylabel = "Re( lambda( . ) )", title = title, framestyle = :box, xaxis = :log10) 
    plot!(xlims = (minimum(f),maximum(f)), legend = :topleft)  #xticks = [10^-3, 10^-2, 10^-1, 10^0, 10^1, 10^2, 10^3, 10^4, 10^5, 10^6] ,ylims = (minimum(passivity_index),maximum(passivity_index))
    plot!(size=(1000,1000))
    display(p_plot)
    return passivity_index

end