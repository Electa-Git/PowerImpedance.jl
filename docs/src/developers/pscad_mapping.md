# PSCAD mapping and station notes

This page records how PowerImpedance drives PSCAD, the facts measured on the reference station,
and the outcome of every risk experiment of the PSCAD integration. Update it whenever an
experiment closes or a station fact changes.

## Station execution model

A `RemoteConfig` describes how to reach a Windows machine with PSCAD 5.1.0: the transport
(`:local`, `:ssh` or `:command`), the exchange directory seen from both sides
(`local_root`/`shared_root`), a station scratch root, and the station Julia and Python
executables. `compute(model, PSCADRun(); options)` stages `run-XXXXXX/` in the exchange
directory, and the supervisor (`supervisor.ps1`) copies the case into station scratch and runs
the Windows-side runner (`runner.jl`, PythonCall + `mhi.pscad` 3.1.2).

PSCAD can only build and run EMTDC cases from a logged-on desktop session. Commands that arrive
over SSH run in Windows session 0. A PSCAD started there loads projects and accepts settings, but
cannot detect compilers (`app.settings()` raises "Unable to retrieve detected software"), and
`project.build()`/`project.run()` fail with `SystemError('Could not queue task')`. The optional
`pscad_port` key selects how the runner acquires a build-capable PSCAD:

| `pscad_port` | Behaviour |
|---|---|
| unset | The runner launches a private PSCAD in its own session and quits it. Correct for a local Windows desktop; over SSH the runner fails fast with a message naming `pscad_port`. |
| set, a PSCAD listens on it | The runner attaches with `mhi.pscad.connect(host = "127.0.0.1", port)`, never quits that application, and restores its `silence` flag afterwards. |
| set, nothing listens | The supervisor starts `Pscad.exe /startup:au /port:<P> /silence:true /splash:false` in the desktop session through a transient interactive-only scheduled task (deleted immediately after start), the runner attaches, and the supervisor stops that PSCAD after the run. |

Every acquired application is silenced (`app.silence = true`) before any settings, load, build or
run call. An unsilenced instance blocks automation on any modal dialog; for example, loading the
staged `generated.pscx` raises "project namespace ... modified to 'generated'".

Ownership is explicit. `owner.txt` records the runner process and `pscad-owner.txt` a PSCAD
started by the supervisor (PID, executable, port, creation time). `lifecycle.ps1` is the single
implementation of stopping the runner, EMTDC executables under the case directory, and an owned
PSCAD. The supervisor's timeout path and caller-side cancellation (Ctrl-C) both use it.

## Measured station facts (PSCAD 5.1.0, EDU certificate, GFortran 8.1 x64)

- `project.run()` builds and runs and blocks until EMTDC finishes; outputs are complete when it
  returns (the `vdiv` tutorial took 2.4-3.8 s including the build).
- Outputs are written to `project.temp_folder`, which is `<case dir>\<project>.gf81\`.
- Legacy output (`PlotType = OUT`): `<stem>.inf` with one line per channel, for example
  `PGB(1)  Output  Desc="Load Current"  Group="Load Current"  Max=100.0  Min=-100.0  Units="kA"  Path="Main(0):Load Current"`,
  plus `<stem>.infx`, plus `<stem>_01.out`, `<stem>_02.out`, ... with at most 10 channels per file.
  Each `.out` file starts with one line holding the project description (blank if none) followed by
  `round(T / sample_step) + 1` numeric rows (time first); line endings are CRLF.
- An array `pgb` (for example a 3-phase voltmeter signal `V_B2`) produces one channel per element:
  `Desc="V_B2:1"`, `"V_B2:2"`, `"V_B2:3"`.
- Settings set through `Project.parameters` read back exactly; choices decode to names (`"OUT"`,
  `"NONE"`, `"STANDARD"`), and `time_step`/`sample_step` are in microseconds.
- The EDU licence prints "Non-professional licenses are limited to a single, electrical subsystem";
  subsystem splitting is disabled.
- PSCAD restores the user's saved workspace on every start; the runner only loads, unloads and
  modifies its own staged project.
- An ideal `source_3` (`Type = 6`) produces "converted to an ideal branch" notes in the run output;
  they are informational.

## Risk experiments

| # | Question | Outcome |
|---|---|---|
| R1 | Source phase reference | Closed. `source_3` `Ph` is sine-referenced; `Ph = rad2deg(va) + 90` reproduces Julia's cosine reference (spike: angle error 0.000 deg). |
| R2 | `nodelabel` on 3-conductor single-line nodes | Closed. Labels join 3-phase single-line wires (6 live nodes for two 3-phase buses). |
| R3 | Single-line passives on 3-conductor wires | Closed. Master `resistor`/`inductor` expand to 3-phase; steady state matched a hand calculation to four digits. |
| R4 | Array `pgb` naming in `.inf` | Closed. `name:1` ... `name:k`, one `PGB` per element. |
| R5 | `<hierarchy>` for mhi-xml-written projects | Closed. PSCAD regenerates the hierarchy on load; no lxml workaround needed. |
| R7 | mhi-xml API details | Partially closed. `canvas.create("master:<defn>")`, `canvas.add`, `add_wire` (pixels) and `ProjectFile.parameters` work; TLine/Cable wrappers pending (M1 OHL). |
| R8 | Licence and EMTDC build | Closed. Headless licence works; builds require a desktop session (see the execution model above). |
| R13 | `run()` blocking and output latency | Closed. Blocking; outputs complete on return. |
| R16 | mhi-xml through CondaPkg on Linux | Closed. CondaPkg (Pixi backend) resolves `mhi-xml==1.3.0` and `lxml`. |
| R6, R9-R12, R14, R15, R17, R18 | | Open; resolved at their milestones. |
