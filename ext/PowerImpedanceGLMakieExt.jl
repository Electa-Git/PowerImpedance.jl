module PowerImpedanceGLMakieExt

using GLMakie
using PowerImpedance

activate!() = (GLMakie.activate!(); :gl)
function make_screen(title::AbstractString; kwargs...)
    return GLMakie.Screen(; title = String(title), kwargs...)
end

function __init__()
    activate!()
    return nothing
end

end
