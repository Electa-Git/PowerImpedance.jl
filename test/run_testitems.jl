using TestItems
include("testitems.jl")
using TestItemRunner

TestItemRunner.run_tests(@__DIR__)
