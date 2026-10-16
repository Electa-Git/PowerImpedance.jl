# Analysis only: read stored matrices and write a separate local report.
using PowerImpedance
include("validation.jl")
length(ARGS) >= 2 || error("usage: reanalyse_line_chain.jl <data-root> <output-root> [fixture ...]")
ids = length(ARGS) == 2 ? PSCADValidation.LINE_CHAIN_IDS : ARGS[3:end]
PSCADValidation.reanalyse_line_chain(ids; data_root = ARGS[1], output_root = ARGS[2])
