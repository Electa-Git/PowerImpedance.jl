module PowerImpedancePlotsExt

using PowerImpedance
import Plots

import PowerImpedance: hline!, palette, plot, plot!, scatter!, vline!

plot(args...; kwargs...) = Plots.plot(args...; kwargs...)
plot!(args...; kwargs...) = Plots.plot!(args...; kwargs...)
palette(args...; kwargs...) = Plots.palette(args...; kwargs...)
hline!(args...; kwargs...) = Plots.hline!(args...; kwargs...)
scatter!(args...; kwargs...) = Plots.scatter!(args...; kwargs...)
vline!(args...; kwargs...) = Plots.vline!(args...; kwargs...)

end
