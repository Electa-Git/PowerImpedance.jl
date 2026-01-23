# Anything numeric matrix-like; we internally compute in ComplexF64.
const Parameters_types = AbstractMatrix{<:Number}

function connect_series!(A::Parameters_types, B::Parameters_types)
	return ComplexF64.(A) * ComplexF64.(B)
end

function connect_parallel!(ABCD₁::Parameters_types, ABCD₂::Parameters_types)
	M1 = ComplexF64.(ABCD₁)
	M2 = ComplexF64.(ABCD₂)

	n = Int(size(M1, 1) ÷ 2)

	a₁ = @view M1[1:n, 1:n]
	b₁ = @view M1[1:n, (n+1):end]
	c₁ = @view M1[(n+1):end, 1:n]
	d₁ = @view M1[(n+1):end, (n+1):end]

	a₂ = @view M2[1:n, 1:n]
	b₂ = @view M2[1:n, (n+1):end]
	c₂ = @view M2[(n+1):end, 1:n]
	d₂ = @view M2[(n+1):end, (n+1):end]

	if n == 1
		b1 = b₁[1];
		b2 = b₂[1]
		denom = b1 + b2
		a = (b2*a₁[1] + b1*a₂[1]) / denom
		b = (b1*b2) / denom
		c = c₁[1] + c₂[1] + (d₂[1] - d₁[1]) * (a₁[1] - a₂[1]) / denom
		d = d₁[1] + (d₂[1] - d₁[1]) * b1 / denom
		return ComplexF64[a b; c d]
	end

	# Multiport case
	# Old code checked "all(b₁[i] == 0 for i in 1:n)" which is nonsense for matrices.
	# Interpret it as "B block is (numerically) zero matrix".
	iszeroB(B) = all(iszero, B)  # exact; if you want tolerance, use a norm-based check.

	if iszeroB(b₁)
		a = copy(a₂)
		b = zeros(ComplexF64, n, n)
		c = c₁ + c₂ + (d₂ - d₁) * (b₂ \ (a₁ - a₂))
		d = copy(d₁)
	elseif iszeroB(b₂)
		a = copy(a₁)
		b = zeros(ComplexF64, n, n)
		c = c₁ + c₂ + (d₂ - d₁) * (b₁ \ (a₁ - a₂))
		d = copy(d₁)
	else
		# Algebra-identical but without explicit inv(inv(.)).
		# b = inv(inv(b₁)+inv(b₂))  =>  b = (b₁ \ I + b₂ \ I) \ I
		I = Matrix{ComplexF64}(I, n, n)

		S = (b₁ \ I) + (b₂ \ I)          # S = inv(b₁) + inv(b₂)
		b = S \ I                         # b = inv(S)

		a = b * ((b₁ \ a₁) + (b₂ \ a₂))    # a = inv(S) * (inv(b₁)a₁ + inv(b₂)a₂)
		c = c₁ + c₂ + (d₂ - d₁) * ((b₁ + b₂) \ (a₁ - a₂))
		d = d₁ + (d₂ - d₁) * ((b₁ + b₂) \ b₁)
	end

	return [a b; c d]
end

function closing_impedance(
	ABCD::Parameters_types,
	Zₜ::Union{Parameters_types, Number},
	direction = :output,
)
	M = ComplexF64.(ABCD)
	n = Int(size(M, 1) ÷ 2)
	m = Int(size(M, 2) ÷ 2)

	a = @view M[1:n, 1:m]
	b = @view M[1:n, (m+1):end]
	c = @view M[(n+1):end, 1:m]
	d = @view M[(n+1):end, (m+1):end]

	if Zₜ isa Number
		Zt = ComplexF64(Zₜ)
		if direction == :output
			return (a .* Zt .+ b) ./ (c .* Zt .+ d)
		else
			return (d .* Zt .- b) ./ (c .* Zt .- a)
		end
	else
		Zt = ComplexF64.(Zₜ)
		if direction == :output
			return (a * Zt + b) * pinv(c * Zt + d)
		else
			return pinv(Zt * c - a) * (Zt * d - b)
		end
	end
end

# making 2×2 matrix (modal domain) from 4×4 matrix (phase domain)
function transformation_dc(ABCD::Parameters_types)
	M = ComplexF64.(ABCD)
	n = Int(size(M, 1) ÷ 2)

	a = @view M[1:n, 1:n]
	b = @view M[1:n, (n+1):end]
	c = @view M[(n+1):end, 1:n]
	d = @view M[(n+1):end, (n+1):end]

	return ComplexF64[
		(a[1, 1] + a[2, 2] - a[1, 2] - a[2, 1]) / 2 (b[1, 1] + b[2, 2] - b[1, 2] - b[2, 1]);
		(c[1, 1] + c[2, 2] - c[1, 2] - c[2, 1]) / 4 (d[1, 1] + d[2, 2] - d[1, 2] - d[2, 1]) / 2
	]
end

# making 4×4 ABCD matrix (dq domain) from 6x6 ABCD matrix (phase domain)
function transformation_dq(ABCD₁::Parameters_types, ABCD₂::Parameters_types)
	M1 = ComplexF64.(ABCD₁)
	M2 = ComplexF64.(ABCD₂)

	n = Int(size(M1, 1) ÷ 2)

	a₁ = @view M1[1:n, 1:n];
	b₁ = @view M1[1:n, (n+1):end]
	c₁ = @view M1[(n+1):end, 1:n];
	d₁ = @view M1[(n+1):end, (n+1):end]

	a₂ = @view M2[1:n, 1:n];
	b₂ = @view M2[1:n, (n+1):end]
	c₂ = @view M2[(n+1):end, 1:n];
	d₂ = @view M2[(n+1):end, (n+1):end]

	T = 0.5 * ComplexF64[1 -1im; -1im -1]
	CK = (2/3) * ComplexF64[1 -1/2 -1/2; 0 sqrt(3)/2 -sqrt(3)/2]
	CKinv = ComplexF64[1 0; -1/2 sqrt(3)/2; -1/2 -sqrt(3)/2]

	a_dq = T*CK*a₂*CKinv*conj(T) + conj(T)*CK*a₁*CKinv*T
	b_dq = T*CK*b₂*CKinv*conj(T) + conj(T)*CK*b₁*CKinv*T
	c_dq = T*CK*c₂*CKinv*conj(T) + conj(T)*CK*c₁*CKinv*T
	d_dq = T*CK*d₂*CKinv*conj(T) + conj(T)*CK*d₁*CKinv*T

	return [a_dq b_dq; c_dq d_dq]
end

function y_to_abcd(Y::Parameters_types)
	M = ComplexF64.(Y)
	n = Int(size(M, 1) ÷ 2)
	Yee = @view M[1:n, 1:n]
	Yei = @view M[1:n, (n+1):end]
	Yie = @view M[(n+1):end, 1:n]
	Yii = @view M[(n+1):end, (n+1):end]

	Yie_inv = inv(Matrix(Yie))
	return [        -Yie_inv*Yii  -Yie_inv;
		Yei - Yee*Yie_inv*Yii   -Yie_inv*Yee]
end

function abcd_to_y(ABCD::Parameters_types)
	M = ComplexF64.(ABCD)
	n = Int(size(M, 1) ÷ 2)
	a = @view M[1:n, 1:n]
	b = @view M[1:n, (n+1):end]
	c = @view M[(n+1):end, 1:n]
	d = @view M[(n+1):end, (n+1):end]

	b_inv = inv(Matrix(b))
	return [    d*b_inv           c - d*b_inv*a;
		-b_inv            b_inv*a]
end
