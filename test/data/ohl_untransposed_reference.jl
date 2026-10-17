# Untransposed parameter evaluation retained from c8a1271.
function untransposed_reference(tl::Overhead_line, s::Complex)
	(μᵣ_earth, ϵᵣ_earth, ρ_earth) = tl.earth_parameters
	μ₀ = 4π * 1e-7
	ϵ₀ = 8.85e-12
	μ_earth = μᵣ_earth * μ₀
	ϵ_earth = ϵᵣ_earth * ϵ₀
	σ_earth = 1 / ρ_earth

	x_array = Float64[]
	y_array = Float64[]
	r_array = Float64[]
	ρ_array = Float64[]   # DC resistance per unit length [Ω/m]
	μ_array = Float64[]

	(x, y) = PI._ohl_conductor_coordinates(tl.conductors)
	(xˢᵇ, yˢᵇ) = PI._ohl_bundle_position(tl.conductors.nˢᵇ, tl.conductors.dˢᵇ)

	for i in 1:tl.conductors.nᵇ, j in 1:tl.conductors.nˢᵇ
		push!(x_array, Float64(x[i]) + xˢᵇ[j])
		push!(y_array, Float64(y[i]) + yˢᵇ[j] - (2/3) * Float64(tl.conductors.dˢᵃᵍ))
		push!(r_array, Float64(tl.conductors.rᶜ))
		push!(ρ_array, Float64(tl.conductors.Rᵈᶜ) * 1e-3)
		push!(μ_array, Float64(tl.conductors.μᵣᶜ) * μ₀)
	end

	nG = tl.groundwires.nᵍ
	if nG > 0
		(xg, yg) = PI._ohl_groundwire_coordinates(tl)
		for i in 1:nG
			push!(x_array, xg[i])
			push!(y_array, yg[i] - (2/3) * Float64(tl.groundwires.dᵍˢᵃᵍ))
			push!(r_array, Float64(tl.groundwires.rᵍ))
			push!(ρ_array, Float64(tl.groundwires.Rᵍᵈᶜ) * 1e-3)
			push!(μ_array, Float64(tl.groundwires.μᵣᵍ) * μ₀)
		end
	end

	Num = tl.conductors.nᵇ * tl.conductors.nˢᵇ + tl.groundwires.nᵍ

	P = zeros(ComplexF64, Num, Num)
	Z = zeros(ComplexF64, Num, Num)

	dₑ = sqrt(1 / (s * μ_earth * (σ_earth + s * ϵ_earth)))  # penetration depth

	for iPhase in 1:Num
		xᵢ = x_array[iPhase]
		yᵢ = y_array[iPhase]
		rᵢ = r_array[iPhase]

		ρ_line = ρ_array[iPhase]
		μ_cond = μ_array[iPhase]

		ρ = ρ_line * (π * rᵢ^2)
		m = sqrt(s * μ_cond / ρ)

		for jPhase in 1:Num
			xⱼ = x_array[jPhase]
			yⱼ = y_array[jPhase]

			Dᵢⱼ = sqrt((xᵢ - xⱼ)^2 + (yᵢ + yⱼ)^2)
			D̂ᵢⱼ = sqrt((xᵢ - xⱼ)^2 + (yᵢ + yⱼ + 2dₑ)^2)
			dᵢⱼ = sqrt((xᵢ - xⱼ)^2 + (yᵢ - yⱼ)^2)

			if iPhase != jPhase
				Z[iPhase, jPhase] += s * log(D̂ᵢⱼ / dᵢⱼ) * μ₀ / (2π)
				P[iPhase, jPhase] = log(Dᵢⱼ / dᵢⱼ) / (2π * ϵ₀)
			else
				Z[iPhase, jPhase] +=
					s * μ₀ / (2π) * log(D̂ᵢⱼ / rᵢ) +
					(m * ρ) / (2π * rᵢ) * coth(0.733 * m * rᵢ) +
					0.3179 * ρ / (π * rᵢ^2)

				P[iPhase, jPhase] = log(Dᵢⱼ / rᵢ) / (2π * ϵ₀)
			end
		end
	end

	if tl.conductors.nˢᵇ != 0
		cond_noElim = [(i-1)*tl.conductors.nˢᵇ + 1 for i in 1:tl.conductors.nᵇ]
		for iPhase in 1:tl.conductors.nᵇ
			cond_noElim_curr = cond_noElim[iPhase]
			for iCond in (tl.conductors.nˢᵇ*(iPhase-1)+2):(tl.conductors.nˢᵇ*iPhase)
				Z[:, iCond] .-= Z[:, cond_noElim_curr]
				Z[iCond, :] .-= Z[cond_noElim_curr, :]

				P[:, iCond] .-= P[:, cond_noElim_curr]
				P[iCond, :] .-= P[cond_noElim_curr, :]
			end
		end
	end

	if (tl.groundwires.nᵍ + tl.conductors.nˢᵇ > 1)
		cond_noElim = [(i-1)*tl.conductors.nˢᵇ + 1 for i in 1:tl.conductors.nᵇ]
		Z = PowerImpedance.kron(Z, cond_noElim)
		P = PowerImpedance.kron(P, cond_noElim)
	end

	Y = s * pinv(P) + Diagonal([tl.conductors.gᶜ for _ in 1:size(P, 1)])

	return (Z, Y)
end
