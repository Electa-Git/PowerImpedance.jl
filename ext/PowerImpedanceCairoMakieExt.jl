module PowerImpedanceCairoMakieExt

using CairoMakie
using PowerImpedance

activate!() = (CairoMakie.activate!(); :cairo)
make_screen(::AbstractString; kwargs...) = nothing

function __init__()
    activate!()
    return nothing
end

end
