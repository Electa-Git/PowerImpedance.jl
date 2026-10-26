module PSCADPowerFlowIdempotenceTests
using PowerImpedance, Test
using ..PowerFlowIdempotenceTests: PSCADFixtures,
    pscad_export_after_explicit_solve, repeated_converter_solves

# The core file reports the existing skip when the extension is unavailable.
if Base.get_extension(PowerImpedance, :PowerImpedancePSCADExt) !== nothing
    pscad_export_after_explicit_solve((
        () -> PSCADFixtures.mmc_network(:qv),
        () -> PSCADFixtures.tlc_vac_network()))
end

repeated_converter_solves((
    ("MMC VAC", () -> PSCADFixtures.mmc_network(:vac)),
    ("MMC Q-V", () -> PSCADFixtures.mmc_network(:qv)),
    ("MMC Vdc", () -> PSCADFixtures.mmc_network(:vdc)),
    ("TLC VAC", PSCADFixtures.tlc_vac_network)))
end
