# API reference

## Gridspace

```@docs; canonical=false
PowerImpedanceACDC.NetworkBuilder.Grid
PowerImpedanceACDC.NetworkBuilder.DeterministicGrid
PowerImpedanceACDC.NetworkBuilder.RelativeGrid
PowerImpedanceACDC.NetworkBuilder.AbsoluteGrid
PowerImpedanceACDC.NetworkBuilder.AbsoluteError
PowerImpedanceACDC.NetworkBuilder.Gridspace
PowerImpedanceACDC.NetworkBuilder.@gridspace
PowerImpedanceACDC.NetworkBuilder.@relax
```

## Parametric results

```@docs; canonical=false
PowerImpedanceACDC.NetworkBuilder.ImpedanceCase
PowerImpedanceACDC.NetworkBuilder.ParametricImpedance
PowerImpedanceACDC.NetworkBuilder.SolveCase
PowerImpedanceACDC.NetworkBuilder.ParametricSolve
PowerImpedanceACDC.NetworkBuilder.FrequencyResponseCase
PowerImpedanceACDC.NetworkBuilder.ParametricFrequencyResponse
PowerImpedanceACDC.NetworkBuilder.ParametricNodeSchema
PowerImpedanceACDC.NetworkBuilder.StabilityCase
PowerImpedanceACDC.NetworkBuilder.ParametricStability
```

## Parametric small-signal analysis

```@docs; canonical=false
PowerImpedanceACDC.NetworkBuilder.make_y_node
PowerImpedanceACDC.NetworkBuilder.make_y_edge
PowerImpedanceACDC.NetworkBuilder.make_loopgain
PowerImpedanceACDC.NetworkBuilder.sampled_frequency_response
PowerImpedanceACDC.nyquistplot
PowerImpedanceACDC.bodeplot
PowerImpedanceACDC.small_gain
PowerImpedanceACDC.passivity
PowerImpedanceACDC.EVD
PowerImpedanceACDC.stabilitymargin
PowerImpedanceACDC.unstable_frequency
PowerImpedanceACDC.check_stability
```

Component shadow constructors deliberately remain qualified under
`PowerImpedanceACDC.NetworkBuilder` and are not exported.
