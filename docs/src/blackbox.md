```@meta
CurrentModule = PowerImpedance
```

# Black-box models

Use a black-box model when frequency-response data comes from an external
simulation or measurement. These models preserve the sampled response for
network assembly. They do not reconstruct the internal physical components.

## Imported transmission-line data

`blackbox_line` reads sampled line constants or full-length ABCD data. The
supported import selectors are `:PSCAD` and `:LCMjl`. The `:Ztool` path is not
implemented. For line-constant data, the model uses per-unit-length series
impedance in Ω/m and shunt admittance in S/m, plus the declared physical
length. The ports and conductor count follow the other line models.

```julia
line = blackbox_line(
    n = 3,
    length = 10_000.0,
    data_type = :PSCAD,
    path = "path/to/line-data-prefix",
)
```

The PSCAD importer reads its magnitude and angle files from the prefix. The
`:LCMjl` importer reads a tab-delimited frequency table. See the
[PSCAD guide](pscad.md) and [`blackbox_line`](@ref) for file formats and
complete argument details.

## Scan-based MMC data

`blackbox_MMC` reads frequency points and an operating-point scan from files.
Its AC port is in dq coordinates and its DC port is differential. Set the AC
and DC voltage bases in kV and provide files that describe matching frequency
and operating-point grids.

```julia
converter = blackbox_MMC(
    path_f = "scan_frequency.tsv",
    path_MMC = "scan_admittance.txt",
    vACbase = 380.0,
    vDCbase = 640.0,
    ac_control = :pq,
    dc_control = :p,
)
```

The inputs specify AC active power in MW and reactive power in MVAr. They also
specify AC voltage in phase-peak kV and DC voltage pole-to-pole in kV.
Power-flow initialization must provide an operating point within the scan
data's supported range before the model can be evaluated. Use
[`blackbox_MMC`](@ref) for the file layout and declared inputs, and see
[Power-flow initialization](initialization.md) for the solved values.
