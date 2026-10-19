# Local comparison with the independent admittance data; no native execution.
include("validation.jl")
length(ARGS) == 2 || error("usage: crosscheck_induction_machine.jl <data_file> <output_directory>")
report = PSCADValidation.induction_machine_crosscheck(ARGS[1]; directory = ARGS[2])
PSCADValidation.TOML.print(stdout, report; sorted = true)
