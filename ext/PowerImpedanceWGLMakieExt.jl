module PowerImpedanceWGLMakieExt

using PowerImpedance
using WGLMakie

activate!() = (WGLMakie.activate!(); :wgl)
make_screen(::AbstractString; kwargs...) = nothing

function __init__()
    activate!()
    return nothing
end

end
