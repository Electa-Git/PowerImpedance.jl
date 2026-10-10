module PSCADPowerFlowIdempotenceTests
using PowerImpedance, Test
using ..PowerFlowIdempotenceTests: PSCADFixtures, pscad_export_after_explicit_power_flow,
                                   repeated_converter_power_flow

# The core file reports the existing skip when the extension is unavailable.
if Base.get_extension(PowerImpedance, :PowerImpedancePSCADExt) !== nothing
    pscad_export_after_explicit_power_flow((
        () -> PSCADFixtures.mmc_network(:qv).state,
        () -> PSCADFixtures.tlc_vac_network().state))
end

repeated_converter_power_flow((("MMC VAC", () -> PSCADFixtures.mmc_network(:vac).state),
    ("MMC Q-V", () -> PSCADFixtures.mmc_network(:qv).state),
    ("MMC Vdc", () -> PSCADFixtures.mmc_network(:vdc).state),
    ("TLC VAC", () -> PSCADFixtures.tlc_vac_network().state)))
end
