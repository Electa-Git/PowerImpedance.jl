export bodeplot

const _BODE_LEGEND_POSITION = :outertop

"""
	bodeplot(L, omegas; legend = [""])

Generate Bode plots for a given set of transfer functions or frequency responses.

# Arguments
- `L::Vector`: A vector containing the frequency response data. Each element can be:
	- A complex number (for Single-Input Single-Output (SISO) systems).
	- A matrix of complex numbers (for Multi-Input Multi-Output (MIMO) systems).
- `omegas::Vector`: A vector of angular frequencies (in radians per second) corresponding to the frequency response data in `L`.
- `legend::Union{Vector{String}, String}` (optional): A legend for the plots. If provided, its length must match the number of elements in `L[x]` for MIMO systems or be a single string for SISO systems. Defaults to `[""]` (no legend).

# Returns
- For MIMO systems: A vector of plots, where each plot corresponds to a specific input-output pair.
- For SISO systems: A single plot with magnitude and phase subplots.

# Behavior
- For MIMO systems:
	- Generates individual Bode plots for each input-output pair in the transfer function matrix.
	- Each plot contains two subplots: magnitude (in dB) and phase (in degrees).
- For SISO systems:
	- Generates a single Bode plot with magnitude and phase subplots.

# Notes
- The function checks that the lengths of `L` and `omegas` match.
- For MIMO systems, the function ensures that the length of the `legend` matches the number of elements in `L[x]` if a legend is provided.
- The frequency axis is displayed on a logarithmic scale.
- Magnitude is displayed in decibels (dB), and phase is displayed in degrees.

# Errors
- Throws an error if the lengths of `L` and `omegas` do not match.
- Throws an error if the length of the `legend` does not match the number of elements in `L[x]` for MIMO systems.
- Throws an error if the input type for `L` is invalid (neither an array nor a number for each frequency).

# Example

ω = 2π .* exp10.(range(0,3,length=20))  # Logarithmically spaced frequency points
H = 1 ./ (1 .+ im .* ω / 100)  # Example transfer function response
bodeplot(H, ω, legend="Low-pass Filter")


"""
function bodeplot(L, omegas; legend = [""], plots = nothing)

	# Do single figure plots, as this is the most generalizable case. Shooting out each single bode plot
	# Have a script handy that generates one plot with subplots
	#Determining dimensions of L

	# Check if length of L and omega match
	length(L)==length(omegas) || error("L and omega must have the same lengths.")

	# Check if entries of L match with entries of legend
	if legend != [""]

		if isa(legend, AbstractArray)
			length(L[1]) == length(legend) ||
				error("Length of legend must match the number of elements in L[x].")
		else
			length(L[1]) == 1 ||
				error("Length of legend must match the number of elements in L[x].")
		end
	end

	if isa(L[1], AbstractArray) #Vector of matrices MIMO

		dim=size(L[1])
		dim[1]*dim[2]

		new_plots =
			isnothing(plots) ? [plot(layout = (2, 1)) for _ in 1:(dim[1]*dim[2])] : plots #Make new layout if no existent plots
		for i in 1:dim[1] # Loop over rows
			for j in 1:dim[2] #Loop over columns

				index=max((i-1)*dim[2], 0)+j #Index for legend & plot
				SISO=[]
				for ω in 1:length(omegas) # Loop over frequencies
					push!(SISO, L[ω][i, j])
				end

				f = real(omegas/(2*π)) #Omega coming from Z-tool was complex number saved
				L_mag = abs.(SISO)
				L_mag_dB = 20*log10.(L_mag)
				L_ph = angle.(SISO) .* (180/π)
				if minimum(L_mag) != maximum(L_mag)
					ylims_mag = (
						minimum(L_mag_dB) - 0.1*abs(minimum(L_mag_dB)),
						maximum(L_mag_dB) + 0.1*abs(minimum(L_mag_dB)),
					)
					ylims_ph = (
						minimum(L_ph) - 0.1*abs(minimum(L_ph)),
						maximum(L_ph) + 0.1*abs(minimum(L_ph)),
					)
				else
					ylims_mag = (maximum(L_mag_dB)-100, maximum(L_mag_dB)+100)
					ylims_ph = (maximum(L_ph)-90, maximum(L_ph)+90)
				end

				pmag = new_plots[index][1]
				pph = new_plots[index][2]

				if legend == [""]
					plot!(
						pmag,
						f,
						L_mag_dB,
						legend = :none,
						linewidth = :auto,
						linestyle = :auto,
						minorgrid = true,
					)  # For different line styles: linestyle = :auto
				else
					plot!(
						pmag,
						f,
						L_mag_dB,
						label = legend[index],
						legend = _BODE_LEGEND_POSITION,
						linewidth = :auto,
						linestyle = :auto,
						minorgrid = true,
					)  # For different line styles: linestyle = :auto   
				end

				plot!(pmag, ylabel = "Magnitude [dB]", framestyle = :box, xaxis = :log10)
				plot!(pmag, xlims = (minimum(f), maximum(f)), ylims = ylims_mag)
				plot!(pph, f, L_ph, linewidth = :auto, linestyle = :auto, minorgrid = true)  # For different line styles: linestyle = :auto
				plot!(
					pph,
					xlabel = "Frequency [Hz]",
					ylabel = "Phase [deg]",
					framestyle = :box,
					legend = :none,
					xaxis = :log10,
				)
				plot!(pph, xlims = (minimum(f), maximum(f)), ylims = (-180, 180))
				plot!(pph, yticks = -360:90:360)

			end
		end
		return new_plots

	elseif isa(L[1], Number) #Vector of complex numbers SISO
		new_plots = isnothing(plots) ? plot(layout = (2, 1)) : plots #Make new layout if no existent plots
		dim=1
		f = omegas/(2*π)
		L_mag = abs.(L)
		L_mag_dB = 20*log10.(L_mag)
		L_ph = angle.(L) .* (180/π)
		if minimum(L_mag) != maximum(L_mag)
			ylims_mag = (
				minimum(L_mag_dB) - 0.1*abs(minimum(L_mag_dB)),
				maximum(L_mag_dB) + 0.1*abs(minimum(L_mag_dB)),
			)
			ylims_ph = (
				minimum(L_ph) - 0.1*abs(minimum(L_ph)),
				maximum(L_ph) + 0.1*abs(minimum(L_ph)),
			)
		else
			ylims_mag = (maximum(L_mag_dB)-100, maximum(L_mag_dB)+100)
			ylims_ph = (maximum(L_ph)-90, maximum(L_ph)+90)
		end

		if legend == [""]
			plot!(
				new_plots[1],
				f,
				L_mag_dB,
				legend = :none,
				linewidth = :auto,
				linestyle = :auto,
				minorgrid = true,
			)  # For different line styles: linestyle = :auto
		else
			plot!(
				new_plots[1],
				f,
				L_mag_dB,
				label = legend,
				legend = _BODE_LEGEND_POSITION,
				linewidth = :auto,
				linestyle = :auto,
				minorgrid = true,
			)  # For different line styles: linestyle = :auto   
		end
		plot!(new_plots[1], ylabel = "Magnitude [dB]", framestyle = :box, xaxis = :log10)
		plot!(new_plots[1], xlims = (minimum(f), maximum(f)), ylims = ylims_mag)
		plot!(new_plots[2], f, L_ph, linewidth = :auto, linestyle = :auto, minorgrid = true)  # For different line styles: linestyle = :auto
		plot!(
			new_plots[2],
			xlabel = "Frequency [Hz]",
			ylabel = "Phase [deg]",
			framestyle = :box,
			legend = :none,
			xaxis = :log10,
		)
		plot!(new_plots[2], xlims = (minimum(f), maximum(f)), ylims = (-180, 180))
		plot!(new_plots[2], yticks = -360:90:360)
		return new_plots


	else
		error("Invalid input type for L. Expected Array or Number for each frequency.")
	end



end
