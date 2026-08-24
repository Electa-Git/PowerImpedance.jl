using Pkg

Pkg.instantiate(; allow_autoprecomp = false)
include(joinpath(@__DIR__, "..", "package_stats.jl"))
main()
