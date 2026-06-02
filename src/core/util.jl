function isgroundnet(net)
    return startswith(lowercase(string(net)), "gnd")
end

function elecdomain(elem, side)
    
    if is_converter(elem)
        return (2-side) #1 for AC, 2 for DC
    
    elseif is_three_phase(elem)
        return 1 # AC   
    else
       return 2 # DC
    end

end


### Frequency response of state-space models for linearized admittance calculation. Implementation of ControlSystemsBase.jl 
### but with caching of the Hessenberg decomposition to speed up repeated evaluations at different frequencies. Also, custom back-substitution to reuse temporary vectors and avoid allocations.

struct HessenbergFreqResp{TH, TC, TB, TD, TW, TCS}
    H::TH
    C::TC
    B::TB
    D::TD
    workB::TW
    u::Vector{ComplexF64}
    cs::TCS
end

function HessenbergFreqResp(A::AbstractMatrix, B::AbstractMatrix, C::AbstractMatrix, D::AbstractMatrix)
    F = hessenberg(A)
    Q = Matrix(F.Q)
    H = F.H
    Cq = complex.(C * Q)
    Bq = Q \ B
    workB = similar(Bq, ComplexF64)
    u = Vector{ComplexF64}(undef, size(H, 1))
    cs = Vector{Tuple{Float64, ComplexF64}}(undef, length(u))
    return HessenbergFreqResp{typeof(H), typeof(Cq), typeof(Bq), typeof(D), typeof(workB), typeof(cs)}(
        H,
        Cq,
        Bq,
        D,
        workB,
        u,
        cs,
    )
end

Base.size(fr::HessenbergFreqResp) = size(fr.D)

function (fr::HessenbergFreqResp)(Yout::AbstractMatrix, s::ComplexF64)
    size(Yout) == size(fr) || throw(DimensionMismatch("wrong output size"))
    copyto!(fr.workB, fr.B)
    ldiv2!(fr.u, fr.cs, fr.H, fr.workB, shift = -s) #Shift is A+μI so need to negate s
    copyto!(Yout, fr.D)
    mul!(Yout, fr.C, fr.workB, -1, 1)
    return Yout
end

function (fr::HessenbergFreqResp)(s::ComplexF64)
    Yout = Matrix{ComplexF64}(undef, size(fr)...)
    fr(Yout, s)
    return Yout
end

struct FallbackFreqResp{TA, TB, TC, TD}
    A::TA
    B::TB
    C::TC
    D::TD
end

function FallbackFreqResp(A::AbstractMatrix, B::AbstractMatrix, C::AbstractMatrix, D::AbstractMatrix)
    return FallbackFreqResp{typeof(A), typeof(B), typeof(C), typeof(D)}(A, B, C, D)
end

Base.size(fr::FallbackFreqResp) = size(fr.D)

function (fr::FallbackFreqResp)(Yout::AbstractMatrix, s::ComplexF64)
    size(Yout) == size(fr) || throw(DimensionMismatch("wrong output size"))
    Yout .= fr.C * ((s * I - fr.A) \ fr.B)
    Yout .+= fr.D
    return Yout
end

function (fr::FallbackFreqResp)(s::ComplexF64)
    Yout = Matrix{ComplexF64}(undef, size(fr)...)
    fr(Yout, s)
    return Yout
end

function freqresp_cache(A::AbstractMatrix, B::AbstractMatrix, C::AbstractMatrix, D::AbstractMatrix)
    try
        return HessenbergFreqResp(A, B, C, D)
    catch
        return FallbackFreqResp(A, B, C, D)
    end
end

# Custom Hessenberg back-substitution used to reuse temporary vectors.
function ldiv2!(u, cs, F::UpperHessenberg, B::AbstractVecOrMat; shift::Number = false)
    LinearAlgebra.checksquare(F)
    m = size(F, 1)
    m != size(B, 1) && throw(DimensionMismatch("wrong right-hand-side # rows != $m"))
    LinearAlgebra.require_one_based_indexing(B)
    n = size(B, 2)
    H = F.data
    μ = shift
    copyto!(u, 1, H, m * (m - 1) + 1, m)
    u[m] += μ
    X = B
    @inbounds for k = m:-1:2
        c, s, ρ = LinearAlgebra.givensAlgorithm(u[k], H[k, k - 1])
        cs[k] = (c, s)
        for i = 1:n
            X[k, i] /= ρ
            t1 = s * X[k, i]
            t2 = c * X[k, i]
            @simd for j = 1:k-2
                X[j, i] -= u[j] * t2 + H[j, k - 1] * t1
            end
            X[k - 1, i] -= u[k - 1] * t2 + (H[k - 1, k - 1] + μ) * t1
        end
        @simd for j = 1:k-2
            u[j] = H[j, k - 1] * c - u[j] * s'
        end
        u[k - 1] = (H[k - 1, k - 1] + μ) * c - u[k - 1] * s'
    end
    for i = 1:n
        τ1 = X[1, i] / u[1]
        @inbounds for j = 2:m
            τ2 = X[j, i]
            c, s = cs[j]
            X[j - 1, i] = c * τ1 + s * τ2
            τ1 = c * τ2 - s' * τ1
        end
        X[m, i] = τ1
    end
    return X
end

#convenience macro to create typedtable types
macro Table(ex)
    Meta.isexpr(ex, :braces) || throw(ArgumentError("@Table expects {...}"))
    nt_elements = :(@NamedTuple{})
    nt_vectors = :(@NamedTuple{})
 
    for a in ex.args
        if !(a isa LineNumberNode)
            Meta.isexpr(a, :(::)) ||throw(ArgumentError("@Table specification must contain name::type expressions"))
            var = (a.args[1])
            el = esc(a.args[2])
            push!(nt_elements.args[3].args,:($var::$el))
            push!(nt_vectors.args[3].args,:($var::Vector{$el}))
        end
    end
    return :(Table{$nt_elements,1, $nt_vectors})
end
export @Table

