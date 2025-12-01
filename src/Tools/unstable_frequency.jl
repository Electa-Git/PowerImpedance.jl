export unstable_frequency
"""
    unstable_frequency(L, omega, make_plot::Bool = true, title::String = "Unstable oscillatory frequency")

Compute the unstable oscillatory frequency based on the eigenvalues of the loop-gain matrix `L` showing encirclement.
The damping at the unstable mode is estimated based on the sign of the phase angle derivative around the poles of 1/(1+L).
The mode's frequency ωₘ is approximated as the peaks of 1/|1+L| over the frequencies `omega`.
Lastly, phase shift analysis is applied at these frequencies to determine the stability: dθ/dωₘ ≈ -1/(ωₘζ) > 0 → ζ < 0 → unstable mode at ωₘ

# Arguments
- L::Vector{Float64}: The eigen-locus with critical point encirclements. It should have dimensions omegaₙ, 
- omega::Vector{Float64}: A vector of frequency points (in radians per second) at which the eigenvalues of `L` are evaluated.
- make_plot::Bool: (optional) Generate a Bode plot of 1/(1+L) indicating the unstable modes.
- title::String: (optional) The title of the plot. Default is "Unstable oscillatory frequency".

# Returns
The function returns a vector of unstable frequencies, and optionally a plot of 1/(1+L) over the frequency marking the detected unstable frequencies.

# Example: 3rd-order transfer function 1/(s + 1)^3 in negative feedback with a gain K
# The closed-loop oscilaltory mode (ζ and ωₙ) depends on the gain K
omega = 2*pi* 10 .^ range(-2, 2; length=2000)  # Frequency range in rad/s
K = 8.5 # Feedback gain makes the closed-loop unstable around 0.28 Hz
# K = 8 # Feedback gain makes the closed-loop at the limit of stability
# K = 7.5 # Feedback gain makes the closed-loop stable
L = [ K/(1.0im*w + 1)^3 for w in omega]  # Example open-loop function (locus)
unstable_frequency(L, omega)

"""
function unstable_frequency(L, omega; make_plot :: Bool = true, title :: String = "Unstable oscillatory frequency")
    f = real(omega)./(2*pi)

    # Determine the maximum of 1/(1+L)
    G = 1 ./(ones(Complex{Float64},length(omega)) .+ L)
    G_mag = abs.(G)
    G_ph = angle.(G)
    critical_points = argmaxima(G_mag)
    unstable_freqs = Float64[]
    
    if length(critical_points)>0
        for point in critical_points
            # Use the three-point formula to approximate the phase angle derivate
            d1 = omega[point] - omega[point-1]
            d2 = omega[point+1] - omega[point]
            c_minus = -d2 / ( d1*(d1+d2) )
            c_zero  =  (d2 - d1) / ( d1*d2 )
            c_plus  =  d1 / ( d2*(d1+d2) )
            dtheta_dw = c_minus*G_ph[point-1] + c_zero*G_ph[point] + c_plus*G_ph[point+1]
            
            # # Optional: check that the first order approximations also hold around the critical point
            # dtheta1_dw = (G_ph[point] - G_ph[point-1]) / (omega[point] - omega[point-1])
            # dtheta2_dw = (G_ph[point+1] - G_ph[point]) / (omega[point+1] - omega[point])
            # if signbit(dtheta_dw) == signbit(dtheta1_dw) && signbit(dtheta1_dw) == signbit(dtheta2_dw)
                # Phase angle shift analysis: dθ/dωₘ ≈ -1/(ωₘζ) > 0 → ζ < 0 → unstable mode at ωₘ
                if signbit(dtheta_dw) == false # If the derivative is positive the mode is unstable
                    push!(unstable_freqs,f[point])
                end
            # else
            #     # Show a warning if the three derivates do not match
            #     println(" Uncertain phase shift analysis around ",round(f[point],digits=2)," Hz. Try adding more frequency points.")
            # end
        end
    end

    # Bode of 1/(1+L) with the unstable modes indicated
    if make_plot
        # plotly() # To activate interactive plot
        G_mag_dB = 20*log10.(G_mag)
        if minimum(G_mag) != maximum(G_mag) 
            ylims_mag = (minimum(G_mag_dB) - 0.1*abs(minimum(G_mag_dB)), maximum(G_mag_dB) + 0.1*abs(minimum(G_mag_dB)))
        else
            ylims_mag = (maximum(G_mag_dB)-10, maximum(G_mag_dB)+10)
        end
        new_plot= plot(layout=(2,1))
        plot!(new_plot[1], f, G_mag_dB, label = "1/(1+λ)", linewidth = 3, c = :blue, linestyle = :auto, minorgrid=false)
        plot!(new_plot[1],ylabel = "Magnitude [dB]", framestyle = :box, xaxis = :log10)
        plot!(new_plot[1],xlims = (f[1],f[end]), ylims = ylims_mag)
        plot!(new_plot[2], f, G_ph.*(180/π), label =:none, linewidth = 3, c = :blue, linestyle = :auto, minorgrid=false)
        plot!(new_plot[2],xlabel = "Frequency [Hz]", ylabel = "Phase [deg]", framestyle = :box, legend = :none, xaxis = :log10)
        plot!(new_plot[2],xlims = (f[1],f[end]), ylims = (-180,180))
        plot!(new_plot[2],yticks = -360:90:360)
        if length(unstable_freqs)>0
            plot!(new_plot[1], unstable_freqs, seriestype="vline", linestyle=:dash, label = "Unstable mode", legend = :topleft)
            plot!(new_plot[2], unstable_freqs, seriestype="vline", linestyle=:dash, label = :none, legend = :topleft)
        end
        display(new_plot)
    end

    return unstable_freqs
end