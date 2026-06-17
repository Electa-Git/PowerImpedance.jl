function kron(matrix, no_eliminate)
	# Old approach
	# n = size(matrix, 1)
	# eliminate = setdiff(1:n, no_eliminate)
	# matrix = matrix[[no_eliminate; eliminate],:]
	# matrix = matrix[:,[no_eliminate; eliminate]]

	# n_noElim = length(no_eliminate)
	# return matrix[1:n_noElim,1:n_noElim] - matrix[1:n_noElim,1+n_noElim:end]*
	#         (matrix[1+n_noElim:end,1+n_noElim:end]\matrix[1+n_noElim:end,1:n_noElim])

	# matrix = matrix[1:n_noElim,1:n_noElim] - matrix[1:n_noElim,1+n_noElim:end]*
	#         inv(matrix[1+n_noElim:end,1+n_noElim:end])*matrix[1+n_noElim:end,1:n_noElim]
	# return matrix[1:n_noElim,1:n_noElim] - matrix[1:n_noElim,1+n_noElim:end]*
	#         inv(matrix[1+n_noElim:end,1+n_noElim:end])*matrix[1+n_noElim:end,1:n_noElim]
	# New approach
	n = size(matrix, 1)
	eliminate = setdiff(1:n, no_eliminate)

	Y11 = matrix[no_eliminate, no_eliminate]
	Y12 = matrix[no_eliminate, eliminate]
	Y21 = matrix[eliminate, no_eliminate]
	Y22 = matrix[eliminate, eliminate]

	if norm(abs.(Y12), Inf) < 1e-12 #Y12 = 0 -> no influence of second subsystem on system of interest
		Ykron = Y11
	else
		Ykron = Y11 - (Y12*inv(Y22))*Y21
	end

	return Ykron


end

function kron_abcd(matrix::Array{Complex}, Zₛ::Union{Int, Float64, Complex},
	no_eliminate::Array{Int})
	n = Int(size(matrix, 1)/2)
	eliminate = setdiff(1:n, no_eliminate)
	Z = Diagonal([Zₛ for i in 1:length(eliminate)])

	(a, b, c, d) = (
		matrix[1:n, 1:n],
		matrix[1:n, (n+1):end],
		matrix[(n+1):end, 1:n],
		matrix[(n+1):end, (n+1):end],
	)
	(a11, a12, a21, a22) = (
		a[no_eliminate, no_eliminate],
		a[no_eliminate, eliminate],
		a[eliminate, no_eliminate],
		a[eliminate, eliminate],
	)
	(b11, b12, b21, b22) = (
		b[no_eliminate, no_eliminate],
		b[no_eliminate, eliminate],
		b[eliminate, no_eliminate],
		b[eliminate, eliminate],
	)
	(c11, c12, c21, c22) = (
		c[no_eliminate, no_eliminate],
		c[no_eliminate, eliminate],
		c[eliminate, no_eliminate],
		c[eliminate, eliminate],
	)
	(d11, d12, d21, d22) = (
		d[no_eliminate, no_eliminate],
		d[no_eliminate, eliminate],
		d[eliminate, no_eliminate],
		d[eliminate, eliminate],
	)

	e = inv((a22*Z + b22) + Z*(c22*Z + d22))
	a = a11 - (a12*Z + b12)*e*(Z*c21 + a21)
	b = b11 - (a12*Z + b12)*e*(Z*d21 + b21)
	c = c11 - (c12*Z + d12)*e*(Z*c21 + a21)
	d = d11 - (c12*Z + d12)*e*(Z*d21 + b21)

	return [a b; c d]
end
