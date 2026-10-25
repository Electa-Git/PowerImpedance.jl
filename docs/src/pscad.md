# PSCAD export and simulation

`export_pscad(::NetworkBuilder.NetworkState)` writes runnable PSCAD 5 projects from PowerImpedance networks. Load `PythonCall`
to activate the writer. CondaPkg installs `mhi-xml` and its XML dependencies.
Export runs locally. `compute(model, PSCADRun();
options)` runs the project on a Windows station with PSCAD 5.1.0, and
`compare_operating_point` compares the simulated steady state with the retained
power-flow solution.
Induction machines export with a speed-dependent load torque and their solved equilibrium speed.

## Export a network

Install `PythonCall` in the Julia environment containing PowerImpedance, then
use a materialized `NetworkBuilder.NetworkState` as `net`:

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

With `powerflow = nothing` (the default), export calls
`compute(PowerFlowProblem(net), ACDCPowerFlow())` for every network, including
networks containing only sources and passive components. Bus voltages and
transformer ratings use that solution. To reuse a completed result:

```julia
powerflow = compute(PowerFlowProblem(net), ACDCPowerFlow())
model = export_pscad(net; path = "pscad_exports/solved.pscx", settings, powerflow)
```

`line_options` overrides supported ground and frequency-dependent fitting
fields. AC/DC line and cable fit targets default to `YMaxE=AMaxE=0.02%`. `dc_reference = :midpoint_resistors` adds two 10 MΩ ground references
at DC buses without a local source midpoint or grounded shunt. Use `:none`
when those additional references are unwanted.

## Z-tool scan probes

`ZToolProbe` adds a scan block to an export. The network keeps its elements
and connections. `ACscan` contains a three-phase through-path with current
measurements on both sides and a voltage measurement at the scan node.
`DCscan` has a positive-pole through-path and a separate reference port.
Both blocks contain voltage injection sources. Their default injection and
decoupling times are `1e8` seconds, so they remain idle during an ordinary run.

```julia
probes = [
    ZToolProbe(:ac, "converter_scan"; element = :DUT, port = :ac),
    ZToolProbe(:ac, "bus_scan"; bus = :B2),
    ZToolProbe(:dc, "dc_scan"; element = :DUT, port = :dc),
]
model = export_pscad(net; path = "pscad_exports/scanned.pscx", settings,
    ztool_probes = probes)
```

`element` and `port` place a series probe between that component port and
its bus. `A1` faces the bus and `A2` faces the element. `bus` alone places an
open shunt probe with `A1` connected to the bus. An open shunt leaves `A2`
unconnected, so PSCAD reports a floating-terminal build warning.
The existing recorded terminal currents keep their positive directions.

Bus names are the PSCAD identifiers in `model.netlist.buses`. Probes also
accept topology `BusKey` values. Names must be unique ASCII PSCAD identifiers
of at most 30 characters. Grounded terminals and repeated scans of the same
terminal raise an error.

For DC probes, `A1` and `A2` connect to the positive pole. `B1` connects to
the negative pole of the same bus. `V0_peak` is the full pole-to-pole DC
voltage because the block measures and injects voltage relative to `B1`.
For AC probes, `V0_peak` is the peak line-to-ground voltage. Solved bus
voltages give both values.

An unsolved bus requires `voltage`, an explicit value in kV.
It uses the same voltage convention. `f0` is `settings.frequency` in Hz
for both kinds.

`perturbation` sets `V_perturb_mag` in per unit and defaults to `0.01`.
AC probes accept `vac_control` and `f_control`. DC probes accept
`vdc_control`. These Boolean flags default to `false`. The remaining
parameters use the library defaults: `T_inj=Tdecoupling=1e8`,
`selector=block_id=0` and `single_frequency=1`.

The first export with scan probes downloads Z-tool v0.1.52 into
`artifacts/ztool/v0.1.52` under the first Julia depot and checks its SHA-256.
Later exports reuse and check that file. `ztool_library = "/path/Z_tool.pslx"`
selects a local library. The export copies `Z_tool.pslx` beside the
project and writes a `.pswx` workspace with relative library and project paths.
The workspace opens the library and project for Z-tool scans.

`model.ztool_library` stores the copied library path and hash.
`model.workspace_path` stores the workspace path. Simulation staging includes
both files and loads the library before the project. Exports and runs with
probes include idle `Scan_options` frequency tables that the blocks read at
start, and `frequency_sweep()` replaces them.

For an existing project, `PSCADModel(path; ztool_library = library_path)`
records its library for simulation. With `ztool_probes` empty, the output
consists of the original project file.

### Frequency sweeps

`ZToolScan` runs Z-tool's `frequency_sweep()` on the configured PSCAD station.
The runner's Python needs `ztoolacdc==0.1.52`. The model needs a Z-tool library
and scan blocks on Main. This example exports one block and scans both sides:

```julia
scan_model = export_pscad(net; path = "pscad_exports/scan_run.pscx", settings,
    ztool_probes = [ZToolProbe(:ac, "converter_scan"; element = :DUT, port = :ac)])
scan = ZToolScan(frequencies = [1, 2, 5, 10, 20, 40, 100, 500],
    snapshot_time = 5.0, start_fft = 2.0, time_step = 1e-6, sample_step = 25e-6)
result = compute(scan_model, scan;
    options = (; remote = RemoteConfig("station.toml"), verbosity = 1))
```

The caller selects startup and injection settling times for the circuit.
`snapshot_time` ends startup before decoupling. `injection_interval` adds a
delay between decoupling and the snapshot used for injections. Each injection
runs for `start_fft + fft_periods/f_base` seconds. Z-tool starts its FFT after
`start_fft` seconds and uses `fft_periods/f_base` seconds of samples.

| Keyword | Default | Reason |
|---|---|---|
| `frequencies` | `nothing` | Z-tool creates a logarithmic list |
| `f_min`, `f_max`, `f_points` | 1 Hz, 1000 Hz, 80 | Z-tool's `create_freq.loglist` defaults |
| `f_base` | 1 Hz | One-second base period for the FFT |
| `snapshot_time` | Model snapshot time, or model duration | Model startup allowance |
| `start_fft` | 1 s | One second for injection settling |
| `fft_periods` | 1 | One base period in the FFT window |
| `injection_interval` | `start_fft` | Z-tool's delay after decoupling |
| `perturbation` | 0.01 pu | Library injection amplitude |
| `multi_frequency` | `false` | Separate single-tone injections |
| `time_step`, `sample_step` | Model settings, in seconds | Same integration and recording intervals |
| `num_parallel_sim` | 1 | Educational licence |
| `topology` | `nothing` | One scan block on Main |

Explicit frequencies replace `f_min`, `f_max` and `f_points`.
Frequencies and range endpoints are positive multiples of `f_base`.
`f_base` sets FFT resolution and differs from the network's nominal frequency.
The sampling interval spans an integer number of integration steps and divides
the FFT window into an integer number of samples. The highest scan frequency
stays below the Nyquist limit.

Z-tool 0.1.52 needs a frequency count divisible by eight in both sweep modes.
It pads other counts with repeated maximum frequencies, but single-frequency
sweeps do not run the extra simulations.
Multi-frequency sweeps also need at least sixteen frequencies.
Each axis then runs at least two simulations.
PSCAD omits the run index from filenames for one simulation, but Z-tool expects
it for perturbation outputs.
The runner checks the count after Z-tool's `create_freq.loglist` resolves a range.

Multiple blocks need a Z-tool topology file. `topology` names this local file,
which staging copies and hashes. Its header pairs each block's sides as
`Name-1 Name-2`, followed by a square binary matrix.
The [sweep mapping](developers/pscad_mapping.md#Z-tool-sweep-inputs) describes these inputs.

The runner loads the library and project into its silenced PSCAD application.
A temporary replacement for Z-tool's `connect` returns that same application.
The runner restores the original callable after success or failure.
Z-tool runs simulations with all plotting and display flags off.
The runner derives the build suffix from the detected GFortran version.

`result.frequencies` gives the common frequencies in Hz.
Each entry in `result.results` holds a parsed `name` with `type`, `blocks` and
`sides`. It also holds the header `axes` and
`admittance[row, column, frequency_index]` in S.
AC blocks contribute d and q axes, and DC blocks contribute one dc axis.
Rows and columns follow the file header, whose block order can differ from
the filename. The values use Z-tool's current signs and coordinate frame.

The public `read_ztool_admittance(path)` reader also reads saved Z-tool files.
It keeps nonfinite admittances so that a diverged simulation remains a recorded outcome.
`result.paths.outputs` contains the admittance files, power-flow and angle
files, plus `ztool.toml` with the package version and arguments passed.
`result.diagnostics.ztool` holds that metadata. The usual
`resume_run_directory` option reuses a completed sweep after checking the
input hashes, output hashes and PSCAD installation.

[Z-tool](https://github.com/Electa-Git/Z-tool) uses the GPL v3 licence.

The citation is F.J. Cifuentes Garcia and J. Beerten,
“Z-Tool: frequency-domain characterization of EMT models for small-signal
stability analysis,” *Electr. Power Syst. Res.* 252, 112405 (2026),
[doi:10.1016/j.epsr.2025.112405](https://doi.org/10.1016/j.epsr.2025.112405).

## Prepare the Windows station

The station needs PSCAD 5.1.0, its licence and detected compiler, Julia 1.12
for the station runner, and Python with `mhi-pscad` 3.1.2. Keep a desktop session
logged on: PSCAD cannot build EMTDC cases in Windows session 0. The caller
needs access to the exchange directory and the configured transport.

`RemoteConfig` supports `:ssh`, `:local` (Windows callers) and `:command`.
`local_root` and `shared_root` identify the same exchange directory from the
caller and station. `remote_root` is station scratch space. Store configuration
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
`local_root` is resolved against the TOML file's directory. Station paths are
retained verbatim. For command transport, add a `command` argument array.
An exact `"{host}"` argument is replaced by `host`.

With `pscad_port` set, the runner attaches to a responsive listener. If none
listens, the supervisor starts PSCAD in the logged-on desktop through a
transient interactive scheduled task. An attached existing application is
left running and its original `silence` flag is restored. An application
started for the run is stopped afterwards. Without a port, a private PSCAD
is launched in the caller's Windows session. SSH execution fails fast.
The runner sets `app.silence=true` before applying settings or loading projects.
Before attachment, a separate probe checks responsiveness with a 60 s timeout.

## Run and retain results

```julia
remote = RemoteConfig("station-config.toml")
result = compute(model, PSCADRun(); options = (; remote, verbosity = 1))
rows = compare_operating_point(result, model)
all(rows.within_tolerance)
```

Alternatively, set `POWERIMPEDANCE_PSCAD_CONFIG` to the TOML filename and use
`RemoteConfig()` or omit `remote` from the options. Python runs on the station for remote computation. Existing hand-built projects can be wrapped
as `PSCADModel("case.pscx")`. Their external files and libraries must already
be available on the station, and comparison requires an exported model with
solved references.

A call starts a fresh run in a persistent `run-XXXXXX/` directory under
`remote.local_root`, or under `work_root` within it. The supervisor copies the
case into station scratch. `result.paths` locates output, console, build messages
and run records. `result.diagnostics` includes settings readback, solver identity
and build warnings. Retain the model alongside the result for comparison.

Completed-run reuse is explicit:

```julia
reused = compute(model, PSCADRun(); options = (;
    remote, resume_run_directory = result.paths.run_directory))
```

`:latest` selects the latest matching completed run. Reuse checks input,
project, runner and output hashes plus the current station identity. Interrupted
simulations require a fresh run. `snapshot_time` saves a snapshot during a fresh run.
Snapshot restarts are unsupported.

## Supported elements and controls

| Component | Variants | Notes |
|:--|:--|:--|
| Sources and lumped impedances | Three-phase AC, two-pole DC, supported scalar R/L/C realizations | Sources follow solved voltages. Terminal probes preserve physical order. |
| Overhead lines | Three-conductor AC. Two-conductor DC | Frequency-dependent phase model, with geometry, earth and fitting parameters. |
| Cables | Coaxial underground or aerial, AC/DC | Ordered layers and positions. Eliminated sheath and armour interfaces. |
| Transformers | YY and ΔY (Dyn11) | Three-phase winding ratings use the solved primary voltage. |
| Synchronous machines | Native synchronous machine with AVR, governor and steam turbine | Control references and initial states follow the solved operating point. |
| TLC controls | Grid-following P/Q, P-f, Q-V, VAC and Vdc | PLL, current PI control, supported measurement filters and modulation delay. |
| MMC controls | Grid-following P/Q, P-f, Q-V, VAC and Vdc. Grid-forming VSM with CCVI/OCC | TEC/ZSCC/CCSC, optional disabled Σ controls, or leg-energy Σ/Δ control with circulating-current control. Uncompensated and compensated modulation. |

The [developer mapping](developers/pscad_mapping.md) records supported control
types, equations, units, realization differences and station evidence.
Unsupported elements or control objects produce element-specific errors.
Transformer `V₁ᵒ`/`V₂ᵒ` power-flow ratings use volts per phase (phase RMS).

## Steady-state comparison and run settings

`compare_operating_point(result, model; rtol_v = 0.01,
atol_angle_deg = 1.0, rtol_i = 0.02, settling_fraction = 0.1)` returns rows containing
`quantity`, `name`, `pscad`, `powerflow`, `error`, `settling` and `within_tolerance`.
It uses the final ten complete
cycles at the configured frequency (or all complete cycles available).
At 50 Hz this is the final 0.2 s, excluding the left endpoint.

Each row passes when `error <= tolerance` and
`settling <= settling_fraction * tolerance`. Settling is the absolute change in
the compared quantity between the two window halves. It uses the same base and
absolute or wrapped-angle rule as the error.

Default settling limits are 0.1%
for voltages and MMC capacitor means, 0.1° for angles, and 0.2% for currents.
Machine and converter P/Q use 0.1% of rating. Speed uses `1e-4` pu.
`settling_fraction` must be finite and nonnegative. Unsettled rows fail without
throwing.

`PowerImpedance.PSCAD.steady_state(result; window_cycles = 10)` also exposes
channel means and fundamental phasors. Sampling must be uniform, with an
integer number of samples per cycle. A relative change above `1e-3` between
the window halves warns that a channel has not settled. Lengthen the run and
inspect traces and build warnings before interpreting comparison rows.

| Quantity | Default comparison rule |
|:--|:--|
| AC voltage and relative angle | Positive-sequence phase RMS magnitude within 1%. Angle relative to the model's reference bus within 1 degree. |
| AC current | Fundamental RMS magnitude within 2%. Raw probe signs follow the terminal-current convention below. |
| DC voltage | Mean pole-to-pole voltage within 1%. |
| DC current | Magnitude error within 2%. Converter-connected DC networks use `abs(diff)/max(abs(reference), Sbase/vDCbase)` with MVA/kV giving kA. Converter-free networks use relative error. Differing converter current bases in one DC network raise an error. |
| Machine and converter P/Q | Absolute MW/MVAr error divided by the device MVA rating within 1%. Converter internal P/Q means use the same rating. Machine terminal voltage also uses the 1% voltage rule. |
| MMC arm capacitors | Each of six capacitor cycle means within 1% of solved pole-to-pole DC voltage. Instantaneous ripple is retained. |
| MMC DC current identity | Signed `i_dc = 3 iS_z`, converting `iS_z` from pu with `Sbase/vDC_base`. 2% with the same current-base floor. The identity reference comes from measured `iS_z`. Its equilibrium value is diagnostic. |
| Machine or MMC VSM speed | Mean speed within `1e-3` pu of 1. |


Terminal-current probes use `I_<element>_<port>`, such as `I_c1_ac`,
`I_c1_dc`, or `I_tl1_side1`. Every exported current probe measures current
**into the component** at that port and records `orientation = :into`.
Other channels have `orientation = nothing`. The direction is fixed regardless
of operating power flow. Bus-voltage names remain `V_<bus>` (with `_P` and `_N`
for the DC pole channels).

| Component | Port | Positive probe current |
|:--|:--|:--|
| AC/DC impedance, overhead line, cable, YY or Dyn11 transformer | `side1`, `side2` | Into the component at each end. |
| Grounded impedance | Nongrounded port | Into the component. |
| AC source, synchronous machine, induction machine | `ac` | From the AC bus into the component. |
| DC source | `dc` | Into the positive-pole terminal. |
| TLC/MMC | `ac`, `dc` | Into the converter at each port. |

These directions agree with Julia's port admittance `Y = I_in / V` and its
`OperatingPoint` powers. A source delivering 900 MW has `ac.p = -900`.
A converter receiving 603 MW from DC and delivering 600 MW to AC has
`dc.p = 603` and `ac.p = -600`. Reactive power follows the same inward rule.
For a source used to measure network impedance, network injection is the
negative of its inward source current.

Use the metadata saved with an older project when reading its recordings.
Previous exports used outward current at some ports. AC RMS and DC magnitude
comparison rows alone cannot detect reversed polarity.

All durations and steps in Julia are in seconds. A 10 μs integration step is
typical. Use the measured 1 μs step for compensated MMC modulation
(10 μs grew unstable in the recorded case). Export warns above 1 μs without
changing the requested step. Machines use 15 s runs to settle. Converter
validation cases commonly use 10 s, or 5 s at 1 μs for compensated MMCs. Output sampling
is independent, must be at least the integration step, and 250 μs is a typical
50 Hz comparison interval. The default source ramp is 0.05 s. Any finite,
nonnegative ramp is accepted.

The MMC startup selector fixes the measured DC-voltage divisor at its solved value
for `t < 0.2 s`. All current and energy feedback remains live. TLC startup
uses nominal DC voltage in its measurement, modulation and electrical power
divisions until 0.2 s. Both retain converged controller states and delay histories.
After startup, the selectors use the measured voltage directly.

Residual modulation delays are rounded to the nearest integration step, with
half-step ties upward. For a positive model delay, the requested residual is
`tau_model - dt`. The realized total is `dt + rounded_residual`. A warning identifies
the converter and records the model delay, step, requested and realized residuals and
error, bounded by `dt/2`. Carrier corrections and initialization use the realized
residual. Positive delays below one step remain rejected. A zero model delay
retains one inherent interface step.

A DC island without a permanent DC voltage source is pre-charged when it contains
at least one TLC with `OuterActiveVdcControl`, or a GFL MMC with that active
controller. DC branches define the islands independently of shared ground and converter AC terminals. Every bus selected for pre-charge requires positive solved pole voltages.
Temporary ideal DC sources fix each bus at `+vm_pu * base_kV` and its negative
until their series breakers open at 0.2 s, including at nonzero current. Sources
have zero ramp. Breakers have `RON=0` and `1e100 ohm` open resistance
(residual conductance `1e-100 S`). Feedback, gains, loads and the solved final
operating point are retained. A source anywhere in the island suppresses this
startup addition. Pre-charge is independent of `dc_reference`. Existing final
midpoint references remain in place.

The validation suite includes measured Vdc-controlled load cases with pre-charge.
Inspect release and startup again after changing the circuit or settings. The
developer mapping lists the saved source and breaker fields, pins and release command.

## Limitations

- The educational licence permits 200 electrical nodes and one subsystem.
  Licence-blocked cases can be **export verified** when offline checks pass and
  a fresh station build reports only the node-cap error, with zero warnings.
  The recorded IEEE39 builds have 528 live nodes. The complete IEEE14 circuit has 216 live nodes.
- A distributed line or cable cannot run when its travel time is shorter than
  one integration step. Export warns conservatively using length divided by the
  speed of light. PSCAD uses its calculated travel time. Reduce the step or
  change the physical section length explicitly.
- `DCVoltageSupportLag` and controller-local VAC/DC filters are not yet
  exportable. Cable `eliminate = false` requires unsupported exposed
  sheath and armour interfaces. AC phase counts other than three and DC line
  conductor counts other than two are unsupported.
- Untransposed AC lines can produce negative-sequence unbalance and ±100 Hz image coupling,
  invalidating fixed-frame dq comparisons. Compare in the phase domain. The option
  `transposition = :ideal` maps to `Transp = 1`. PSCAD 5.1 runs with this flag exit
  abnormally at termination in the validation measurement projects.
- An unstable Julia operating point diverges in PSCAD. The P2P example reproduces the predicted
  mode near 3.48 kHz, within 2 % in frequency. Its growth rate cannot be fitted from a fresh start
  because AC line energisation makes the record nonlinear. See the
  [P2P record](developers/pscad_mapping.md#P2P-instability).

Voltage probes on temporarily pre-charged DC networks measure an existing
conducting node label directly, using the same line-to-ground voltage function
and output names as the standalone meter. This avoids a separate meter whose
position can change during native project loading. With `PythonCall` loaded,
`PowerImpedance.PSCAD.check_connectivity(path)` also checks the coordinates in
an exported project or a project saved after loading. Export performs this
serialized check automatically. Native build checks and scientific comparisons
use a PSCAD run.

## Abbreviations

| Term | Meaning |
|---|---|
| API | Application programming interface |
| XML / SVG | Extensible Markup Language / Scalable Vector Graphics |
| UTF-16 | Unicode Transformation Format with 16-bit code units |
| SHA-256 | Secure Hash Algorithm with a 256-bit digest |
| AC / DC | Alternating current / direct current |
| TLC / MMC | Two-level converter / modular multilevel converter |
| GFL / GFM | Grid-following / grid-forming control |
| PLL | Phase-locked loop |
| OCC | Output-current control |
| TEC | Total-energy control |
| ZSCC | Zero-sequence current control |
| CCSC / CCC | Circulating-current suppression control / circulating-current control |
| LEC | Leg-energy control |
| CCVI | Current-controlled virtual impedance, which maps voltage error to current references through virtual resistance and inductance |
| VSM / VSE | Virtual synchronous machine / virtual swing equation. `VSEWithDamping` implements the synchronization equation |
| AVR | Automatic voltage regulator |
| PI | Proportional-integral control |
| SCR | Short-circuit ratio: grid short-circuit apparent power divided by the declared converter MVA rating, at rated external voltage |
| X/R | Grid reactance-to-resistance ratio at nominal frequency |
| KCL | Kirchhoff's current law |
| EMT | Electromagnetic transient |
| DFT | Discrete Fourier transform |
| RMS / LL | Root mean square / line-to-line |
| pu / SI | Per unit on the declared base / International System of Units |
| RL / RLC | Resistance and inductance / resistance, inductance and capacitance |
| OHL / P2P | Overhead line / point-to-point link |
| RC | Resistance and capacitance |
| YY / Dyn11 | Star-star transformer / delta-star transformer with neutral and a 30 degree secondary lead |
| IEEE9 | Institute of Electrical and Electronics Engineers nine-bus test network |
| LTI | Linear model with coefficients constant in time |
| abc / dq | Phase coordinates a/b/c / direct and quadrature rotating coordinates |
| Y / Z / ABCD | Admittance / impedance / multiport voltage-current transmission matrices |
| P/Q, P-f, Q-V | Active and reactive power regulation, active power support from frequency, reactive power support from voltage |
| VAC / Vdc | AC-voltage regulation / DC-voltage regulation |
| DSOUT / DSDYN | EMTDC electrical-output / dynamics execution phases |
