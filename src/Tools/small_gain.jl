export small_gain
"""
    small_gain(G1, G2, omega, title::String = "Small gain theorem evaluation via SVD")

Performs a small gain analysis by computing the maximum singular values of two system transfer function 
matrices `G1` and `G2` across a range of frequencies `omega` and visualizing their product.

## Parameters
- `G1::Array{Matrix{Complex}}`: A collection of system matrices evaluated at different frequencies (first system).
- `G2::Array{Matrix{Complex}}`: A collection of system matrices evaluated at different frequencies (second system).
- `omega::Vector{Real}`: A vector of angular frequencies (in rad/s) at which `G1` and `G2` are evaluated.
- `title::String`: (Optional) Title of the small gain plot. Default is `"Small gain theorem evaluation via SVD"`.

## Returns
- `Vector{Float64}`: The maximum singular values of the product `G1(ω) * G2(ω)` at each frequency.

## Methodology
1. **Compute Singular Values**:
   - The singular values of `G1(ω)`, `G2(ω)`, and their product `G1(ω) * G2(ω)` are computed.
   - The maximum singular value at each frequency is extracted.

2. **Visualization**:
   - A logarithmic plot is generated for `σ_max(G1(ω) * G2(ω))` (black solid line).
   - Individual singular values for `G1(ω)` (blue dashed) and `G2(ω)` (red dashed) are also displayed.
   - The x-axis and y-axis are plotted on a logarithmic scale.

## Example Usage
```julia
# Define example data
omega = 2 * pi * logspace(-3, 6, 100)  # Frequency range in rad/s
G1 = [rand(ComplexF64, 2, 2) for _ in omega]  # Example transfer function matrices for G1
G2 = [rand(ComplexF64, 2, 2) for _ in omega]  # Example transfer function matrices for G2

# Small gain analysis
small_gain_index = small_gain(G1, G2, omega)

println("Small Gain Index:\n", small_gain_index)
```
"""
function small_gain(G1, G2, omega, title :: String = "Small gain theorem evaluation via SVD")

    f = real(omega)./(2*pi)

    # Determine maximum singular values of the matrices and their product at each frequency
    S1 = maximum.(svdvals.(G1))
    S2 = maximum.(svdvals.(G2))
    S12 = maximum.(svdvals.(G1.*G2))

    #plotly() # To activate interactive plot
    p_abs = plot(f, S12, linewidth = 3, c = :black, label = "max(sigma( G1*G2 ))")  
    plot!(f, 1 ./ S1, linewidth = 3, c = :blue, label = "1/max(sigma( G1 ))")  
    plot!(f, S2, linewidth = 3, c = :red, label = "max(sigma( G2 ))")
    plot!([f[1], f[end]], [1,1], linewidth = 1, line = :dash, c = :green, label = :none)  
    plot!(xlabel = "Frequency [Hz]", ylabel = "Singular values", title = title, framestyle = :box, xaxis = :log10, yaxis = :log10) 
    plot!(xlims = (minimum(f),maximum(f)), legend = :topleft)  #xticks = [10^-3, 10^-2, 10^-1, 10^0, 10^1, 10^2, 10^3, 10^4, 10^5, 10^6]
    plot!(size=(1000,1000))
    display(p_abs)
    return S12

end