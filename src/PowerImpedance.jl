module PowerImpedance

export PowerImpedanceACDC

# Compatibility alias for code that has adopted the new package import while
# retaining qualified references to the former module name.
const PowerImpedanceACDC = PowerImpedance

include("PowerImpedance_impl.jl")

end
