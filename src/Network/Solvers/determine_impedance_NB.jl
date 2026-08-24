export determine_impedance

"""
    determine_impedance(model::NetworkModel; nets, elim_elements=Symbol[],
                        freq_range=(0.001, 10000, 2000))

Calculate the nodal impedance seen at `nets` from an already linearized
[`NetworkModel`](@ref). Elements named by `elim_elements` are omitted before
ground elimination and Kron reduction. `freq_range` is `(minimum, maximum,
count)` in hertz.

Return the complex impedance tensor and angular-frequency vector in radians per
second. The tensor dimensions are `(length(nets), length(nets), count)`.
"""
function determine_impedance(lanw::NetworkModel; nets::AbstractVector{Symbol},
        elim_elements::AbstractVector{Symbol} = Symbol[],
        freq_range = (0.001, 10000, 2000))
    isempty(nets) &&
        throw(ArgumentError("Impedance cannot be determined from nonexistent nets."))

    ## Element integer ids
    elim_elemidvec = getindex.(Ref(lanw.indices.elements), elim_elements)
    elemidvec = setdiff(1:length(lanw.element_admittances), elim_elemidvec)

    ## Net integer ids
    netidvec = [lanw.indices.nodes[key] for key in nets]

    ## Frequency range
    (min_f, max_f, n_f) = freq_range
    n_f = convert(Int, n_f) #Make Int to work with range (error when 1e4)

    omega = Vector{ComplexF64}(undef, n_f)
    omega .= 2*pi*10 .^ range(log10(min_f), log10(max_f), length = n_f) # Frequency in rad/s
    s = im .* omega # Complex frequency vector

    Yred = make_y(lanw, elemidvec, s, netidvec)
    Z = similar(Yred)

    for i in axes(Yred, 3)
        Z[:, :, i] = inv(Yred[:, :, i])
    end

    return Z, omega
end
