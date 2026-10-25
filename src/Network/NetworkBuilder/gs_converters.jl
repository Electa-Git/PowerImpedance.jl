@gridconstructor P.ElectricalMMC P.ElectricalMMC
@gridconstructor P.NoTotalEnergyControl P.NoTotalEnergyControl
@gridconstructor P.TotalEnergyControl P.TotalEnergyControl
@gridconstructor P.ΣEnergyControl P.ΣEnergyControl
@gridconstructor P.ΔEnergyControl P.ΔEnergyControl
@gridconstructor P.NoZeroSequenceCurrentControl P.NoZeroSequenceCurrentControl
@gridconstructor P.NoCirculatingCurrentSuppressionControl P.NoCirculatingCurrentSuppressionControl
@gridconstructor P.ZeroSequenceCurrentControl P.ZeroSequenceCurrentControl
@gridconstructor P.CirculatingCurrentSuppressionControl P.CirculatingCurrentSuppressionControl
@gridconstructor P.CirculatingCurrentControl P.CirculatingCurrentControl
@gridconstructor P.UncompensatedModulation P.UncompensatedModulation
@gridconstructor P.CompensatedModulation P.CompensatedModulation
@gridconstructor P.ΔdqControlGFL P.ΔdqControlGFL
@gridconstructor P.ΔdqControlGFM P.ΔdqControlGFM
@gridconstructor P.ΣdqzControlTEC P.ΣdqzControlTEC
@gridconstructor P.ΣdqzControlLEC P.ΣdqzControlLEC
@gridconstructor P.MMC P.MMC

@gridconstructor P.ElectricalTLC P.ElectricalTLC
@gridconstructor P.NoModulation P.NoModulation
@gridconstructor P.DelayModulation P.DelayModulation
@gridconstructor P.PadeModulation P.PadeModulation
@gridconstructor P.TLC P.TLC

"""
    mmc(Grid; kwargs...)

Construct a lazy `Gridspace{MMC}` with the modular constructor keywords.
"""
P.mmc(::typeof(Grid); kwargs...) = _keyword_gridspace(P.MMC, P.mmc; kwargs...)

"""
    tlc(Grid; kwargs...)

Construct a lazy `Gridspace{TLC}` with the modular constructor keywords.
"""
P.tlc(::typeof(Grid); kwargs...) = _keyword_gridspace(P.TLC, P.tlc; kwargs...)
