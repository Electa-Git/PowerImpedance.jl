module PowerImpedanceACDC

# Existing manifests may still resolve this UUID under its former name. The
# shared implementation retains their API while new environments load the
# canonical PowerImpedance module.
const PowerImpedance = PowerImpedanceACDC

include("PowerImpedance_impl.jl")

end
