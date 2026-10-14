# PSCAD export and simulation

Overhead-line and cable exports use `YMaxE=AMaxE=0.02%` by default (AC/DC), overridable through `line_options`; all other fitting defaults are unchanged.

`export_pscad(::Network)` and `export_pscad(::NetworkBuilder.NetworkState)`
write runnable PSCAD 5 projects from PowerImpedance networks. Load `PythonCall`
to activate the writer; CondaPkg installs `mhi-xml` and its XML dependencies.
Export runs locally and does not contact PSCAD. `compute(model, PSCADRun();
options)` runs the project on a Windows station with PSCAD 5.1.0, and
`compare_operating_point` compares the simulated steady state with the retained
power-flow solution.

## Export a network

Install `PythonCall` in the Julia environment containing PowerImpedance, then
use an existing classic network or materialized NetworkBuilder state as `net`:

```julia
using PowerImpedance
using PythonCall

settings = PowerImpedance.PSCAD.SimulationSettings(
    simulation_time = 10.0, time_step = 10e-6, sample_step = 250e-6)
mkpath("pscad_exports")
model = export_pscad(net; path = "pscad_exports/my_grid.pscx", settings)
```

The output path must be new and its parent directory must exist. The project
name equals the filename stem. The returned `PSCADModel` retains the project,
probes, settings and operating-point references. The file can also be opened
and run in PSCAD directly.

Classic export calls `power_flow(net)` and retains its setpoint mutations.
To reuse a classic solution, pass `powerflow = power_flow(net)` to the exporter.
Builder export calls `NetworkBuilder.solve`; linear builder networks use source
setpoints without solving power flow and have no solved data for comparison.
`line_options` overrides supported ground and frequency-dependent fitting
fields. `dc_reference = :midpoint_resistors` adds two 10 MΩ ground references
at DC buses without a local source midpoint or grounded shunt; use `:none`
when those additional references are unwanted.

## Prepare the Windows station

The station needs PSCAD 5.1.0, its licence and detected compiler, Julia 1.12
for the station runner, and Python with `mhi-pscad` 3.1.2. Keep a desktop session
logged on: PSCAD cannot build EMTDC cases in Windows session 0. The caller
needs access to the exchange directory and the configured transport.

`RemoteConfig` supports `:ssh`, `:local` (Windows callers) and `:command`.
`local_root` and `shared_root` identify the same exchange directory from the
caller and station; `remote_root` is station scratch space. Store configuration
outside the project export. This TOML template contains placeholders for
station-specific values:

```toml
host = "<WINDOWS_HOST>"
local_root = "<CALLER_EXCHANGE_DIRECTORY>"
shared_root = "<WINDOWS_EXCHANGE_DIRECTORY>"
remote_root = "<WINDOWS_SCRATCH_DIRECTORY>"
julia_executable = "<WINDOWS_JULIA_EXECUTABLE>"
python_executable = "<WINDOWS_PYTHON_EXECUTABLE>"
pscad_version = "5.1.0"
transport = "ssh"
# pscad_port = <DEDICATED_AUTOMATION_PORT>
# timeout = <RUN_TIMEOUT_SECONDS>
```

Replace the placeholders. For SSH, uncomment `pscad_port` and supply a
station-local integer in `1024:65535`, reserved for this automation workflow.
`timeout` is the execution limit in seconds (default 1800). A relative
`local_root` is resolved against the TOML file's directory; station paths are
retained verbatim. For command transport, add a `command` argument array;
an exact `"{host}"` argument is replaced by `host`.

With `pscad_port` set, the runner attaches to a responsive listener. If none
listens, the supervisor starts PSCAD in the logged-on desktop through a
transient interactive scheduled task. An attached existing application is
left running and its original `silence` flag is restored; an application
started for the run is stopped afterwards. Without a port, a private PSCAD
is launched in the caller's Windows session; SSH execution fails fast.
Every application is silenced before settings, loading, building or running.
A separate 60 s responsiveness probe precedes attachment.

## Run and retain results

```julia
remote = RemoteConfig("station-config.toml")
result = compute(model, PSCADRun(); options = (; remote, verbosity = 1))
rows = compare_operating_point(result, model)
all(rows.within_tolerance)
```

Alternatively, set `POWERIMPEDANCE_PSCAD_CONFIG` to the TOML filename and use
`RemoteConfig()` or omit `remote` from the options. Remote computation does
not require Python on the caller. Existing hand-built projects can be wrapped
as `PSCADModel("case.pscx")`; their external files and libraries must already
be available on the station, and comparison requires an exported model with
solved references.

Every call starts a fresh run in a persistent `run-XXXXXX/` directory under
`remote.local_root`, or under `work_root` within it. The supervisor copies the
case into station scratch. `result.paths` locates output, console, build messages
and run records; `result.diagnostics` includes settings readback, solver identity
and build warnings. Retain the model alongside the result for comparison.

Completed-run reuse is explicit:

```julia
reused = compute(model, PSCADRun(); options = (;
    remote, resume_run_directory = result.paths.run_directory))
```

`:latest` selects the latest matching completed run. Reuse checks input,
project, runner and output hashes plus the current station identity; it does
not continue an interrupted simulation. `snapshot_time` saves a snapshot
during a fresh run and does not restart from one.

## Supported elements and controls

| Element | Variants | Notes |
|:--|:--|:--|
| Sources and lumped impedances | Three-phase AC; two-pole DC; supported scalar R/L/C realizations | Sources follow solved voltages or source setpoints; terminal probes preserve physical order. |
| Overhead lines | Three-conductor AC; two-conductor DC | Frequency-dependent phase model, with geometry, earth and fitting parameters. |
| Cables | Coaxial underground or aerial, AC/DC | Ordered layers and positions; eliminated sheath/armour interfaces. |
| Transformers | YY and ΔY (Dyn11) | Three-phase winding ratings use the solved primary voltage. |
| Synchronous machines | Native synchronous machine with AVR, governor and steam turbine | Control references and initial states follow the solved operating point. |
| TLC controls | Grid following: P/Q, P-f, Q-V, VAC and Vdc | PLL, current PI control, supported measurement filters and modulation delay. |
| MMC controls | Grid following: P/Q, P-f, Q-V, VAC and Vdc; grid forming: VSM with CCVI/OCC | TEC/ZSCC/CCSC, optional disabled Σ controls, or leg-energy Σ/Δ control with circulating-current control; uncompensated and compensated modulation. |

The [developer mapping](developers/pscad_mapping.md) records supported control
types, equations, units, deliberate realization differences and station evidence.
Unsupported elements or control objects produce element-specific errors.
Transformer `V₁ᵒ`/`V₂ᵒ` power-flow ratings use volts per phase (phase RMS).

## Steady-state comparison and run settings

`compare_operating_point(result, model; rtol_v = 0.01,
atol_angle_deg = 1.0, rtol_i = 0.02)` returns rows containing `quantity`,
`name`, `pscad`, `powerflow`, `error` and `within_tolerance`. It uses the final ten complete
cycles at the configured frequency (or all complete cycles available).
At 50 Hz this is the final 0.2 s, excluding the left endpoint.
`PowerImpedance.PSCAD.steady_state(result; window_cycles = 10)` also exposes
channel means and fundamental phasors. Sampling must be uniform, with an
integer number of samples per cycle. A relative change above `1e-3` between
the window halves warns that a channel has not settled; lengthen the run and
inspect traces and build warnings before interpreting comparison rows.

| Quantity | Default comparison rule |
|:--|:--|
| AC voltage and relative angle | Positive-sequence phase RMS magnitude within 1%; angle relative to the model's reference bus within 1 degree. |
| AC current | Fundamental RMS magnitude within 2%; raw probe signs follow the terminal-current convention below. |
| DC voltage | Mean pole-to-pole voltage within 1%. |
| DC current | Magnitude error within 2%; converter-connected DC networks use `abs(diff)/max(abs(reference), Sbase/vDCbase)` with MVA/kV giving kA. Converter-free networks use relative error. Differing converter current bases in one DC network raise an error. |
| Machine and converter P/Q | Absolute MW/MVAr error divided by the device MVA rating within 1%; converter internal P/Q means use the same rating. Machine terminal voltage also uses the 1% voltage rule. |
| MMC arm capacitors | Each of six capacitor cycle means within 1% of solved pole-to-pole DC voltage; instantaneous ripple is retained. |
| MMC DC current identity | Signed `i_dc = 3 iS_z`, converting `iS_z` from pu with `Sbase/vDC_base`; 2% with the same current-base floor. The identity reference comes from measured `iS_z`; its equilibrium value is diagnostic. |
| Machine or MMC VSM speed | Mean speed within `1e-3` pu of 1. |


Terminal-current probe metadata records `orientation = :into` or `:out`, relative
to the element at the named terminal. Other channels have `orientation = nothing`.
These signs describe measured currents, independently of power direction.

| Element | Positive probe current |
|:--|:--|
| Passive AC/DC two-port: impedance, OHL, cable, YY or Dyn11 transformer | Side 1 into the element; side 2 out of the element (branch direction 1 → 2). |
| Grounded impedance | Into the sole nongrounded terminal. |
| AC source, synchronous machine | Out of the element, toward the AC bus (injection). |
| DC source | Into its positive-pole terminal. |
| TLC/MMC | DC side 1 into the element; AC side 2 out toward the AC bus. |

To compare with Julia's inward port admittance, negate every `:out` terminal
current. For a shunt-source network impedance measurement, the input is current
injected into the network, so retain `:out` source current instead. Use the
metadata of the project that produced the run: AC cable projects exported before
the orientation correction measured inward current at both ends. AC RMS and DC
magnitude acceptance rows do not detect sign reversal; signed machine/converter
power and MMC DC-current identity rows retain their existing conventions.

All durations and steps in Julia are in seconds. A 10 μs integration step is
typical; **use the validated 1 μs step for compensated MMC modulation**
(10 μs grew unstable in the recorded case). Export warns above 1 μs without
changing the requested step. Machines use 15 s runs to settle; converter
fixtures commonly use 10 s, or 5 s at 1 μs for compensated MMCs. Output sampling
is independent, must be at least the integration step, and 250 μs is a typical
50 Hz comparison interval. The default source ramp is 0.05 s; any finite,
nonnegative ramp is accepted.

The measurement start-up hold keeps the DC-voltage divisor at its solved
value for `t < 0.2 s`. Feedback remains live from the first step; converged
controller states and delay histories are retained. This hold is a start-up
handover, without a permanent voltage floor or changed comparison tolerance.

Residual modulation delays are rounded to the nearest integration step, with
half-step ties upward. For a positive model delay, the requested residual is
`tau_model - dt`; the realized total is `dt + rounded_residual`. A warning names
the converter and records the model delay, step, requested/realized residual and
error, bounded by `dt/2`. Carrier corrections and initialization use the realized
residual. Positive delays below one step remain rejected; a zero model delay
retains one inherent interface step.

A DC island without a permanent DC voltage source is pre-charged when it contains
at least one TLC with `OuterActiveVdcControl`, or a GFL MMC with that active
controller. DC branches join islands; shared ground and converter AC terminals
do not. Every bus in a qualifying island requires positive solved pole voltages.
Two ideal DC sources hold each bus at `+vm_pu * base_kV` and its negative until
0.2 s, then their series breakers open at arbitrary current. Sources have zero
ramp; breakers use zero closed resistance and `1e100 ohm` open resistance
(residual conductance `1e-100 S`). Feedback, gains, loads and the solved final
operating point are retained. A source anywhere in the island suppresses this
startup addition. Pre-charge is independent of `dc_reference`; existing final
midpoint references remain in place.

The pre-charge composite is export/XML verified offline; native release and
startup qualification must be measured on fresh runs. The saved source/breaker
fields, pins and release-command convention are cited in the developer mapping.

## Limitations

- The educational licence permits 200 electrical nodes and one subsystem.
  Licence-blocked cases can be **export verified** when offline checks pass and
  a fresh station build reports only the node-cap error, with zero warnings.
  The recorded IEEE39 builds meet that criterion; they have no simulation acceptance.
- A distributed line or cable cannot run when its travel time is shorter than
  one integration step. Export warns conservatively using length divided by the
  speed of light; PSCAD uses its calculated travel time. Reduce the step or
  change the physical section length explicitly.
- `DCVoltageSupportLag` and controller-local VAC/DC filters are not yet
  exportable. Cable `eliminate = false` requires unsupported exposed
  sheath/armour interfaces. AC phase counts other than three and DC line
  conductor counts other than two are unsupported.
- An unstable Julia operating point can diverge in PSCAD. The recorded P2P
  example reproduces an unstable mode near 3.48 kHz with a growth time near
  0.7 ms; that is dynamic-validation evidence, without steady-state acceptance.
  See the [P2P record](developers/pscad_mapping.md#P2P-dynamic-validation-record).
