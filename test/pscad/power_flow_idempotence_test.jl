module PSCADPowerFlowIdempotenceTests
using PowerImpedance, Test
using ..PowerFlowIdempotenceTests: PSCADFixtures, ClassicFixtures,
    pscad_export_after_explicit_power_flow, repeated_converter_power_flow

# The core file reports the existing skip when the extension is unavailable.
if Base.get_extension(PowerImpedance, :PowerImpedancePSCADExt) !== nothing
    pscad_export_after_explicit_power_flow((
        () -> PSCADFixtures.mmc_network(:qv),
        () -> PSCADFixtures.tlc_vac_network()))
end

repeated_converter_power_flow((
    ("MMC VAC", () -> (; classic = ClassicFixtures.mmc_network(:vac),
        state = PSCADFixtures.mmc_network(:vac))),
    ("MMC Q-V", () -> (; classic = ClassicFixtures.mmc_network(:qv),
        state = PSCADFixtures.mmc_network(:qv))),
    ("MMC Vdc", () -> (; classic = ClassicFixtures.mmc_network(:vdc),
        state = PSCADFixtures.mmc_network(:vdc))),
    ("TLC VAC", () -> (; classic = ClassicFixtures.tlc_vac_network(),
        state = PSCADFixtures.tlc_vac_network()))))
end
