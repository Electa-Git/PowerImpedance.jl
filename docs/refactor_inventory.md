# Documentation refactor inventory

This is a working implementation record for the documentation refactor. It is not part of the published documentation navigation.

## Public component families and input configuration

The current source exports the following user-facing component families:

| Family | Public constructors or types | Current page / destination |
|---|---|---|
| AC and DC sources | `ac_source`, `dc_source`, `Source` | `docs/src/source.md` |
| Lumped impedances and shunts | `impedance`, `Impedance` | `docs/src/impedance.md`; distinguish two-terminal elements and shunts by supported constructor behavior |
| Transformers | `transformer` | `docs/src/transformer.md` |
| Transmission lines and cables | `overhead_line`, `cable`, `blackbox_line` | `docs/src/transmission_line.md` |
| Modular multilevel converters | `mmc`, `blackbox_MMC` | `docs/src/MMC.md` plus new black-box coverage or linked API material |
| Two-level converters | `tlc` | `docs/src/TLC.md` |
| Synchronous and induction machines | `synchronousmachine`, `inductionmachine` | Add a Machines component page or a clearly linked component guide |

The public input configuration surface is declared in `src/Network/Components/inputs.jl`:

- Constructor keywords initialize model inputs; constructor `powerflow` keywords seed supported power-flow values for several active models.
- `inputs(model)` returns the declared nested `NamedTuple` tree with `Input` leaves and metadata.
- `inputvalues(model)` returns the current values in that tree.
- `withinputs(model; nested...)` returns a configured copy using partial nested keyword trees.
- `component(model; limits, inputs...)` is the convenience wrapper for applying nested inputs and optional limits.
- Network declarations can also carry element values through the `NetworkBuilder` element and topology interfaces; audit the concrete supported forms and document only those used by public APIs.

## SMIB API and build feasibility

The existing source and docs establish these current public calls:

1. Build a synchronous machine with `synchronousmachine(...)` and configure its operating-point seed through constructor keywords or `component(...; powerflow = ...)`.
2. Define an ideal infinite bus with `ac_source(...)`; connect it to a transmission element and the machine using `NetworkBuilder.Bus` and `NetworkBuilder.define`.
3. Render a network using `diagram(network; interactive = false)`.
4. Calculate the operating point with `compute(PowerFlowProblem(network), ACDCPowerFlow())`, then linearize using `compute(LinearizationProblem(network, power_flow), AdmittanceLinearization())`.
5. Calculate nodal impedance and loop gain from `PowerImpedanceProblem(linearized.network_model; nodes, frequency_range)` using `NodalImpedance()` and `LoopGain()`.
6. Calculate a Nyquist result with `compute(StabilityProblem(loop_gain), GeneralizedNyquist())`; plot completed results with `PowerImpedance.plot(result; display_plot = false)` after loading a Makie backend.

These calls are already used in `examples/Converter_machine_interaction.jl`, `examples/IEEE9_bus_impedance.jl`, `examples/Network_Diagram.jl`, and `docs/src/results.md`. The docs environment already includes Literate, CairoMakie, and the plotting/documentation dependencies. Stage 2 must still execute the small assembled SMIB example in both docs targets and confirm convergence and the two plotted outputs; source usage alone does not prove this particular topology converges.

## Content disposition

| Current page or section | Disposition | Destination / action |
|---|---|---|
| `index.md`: purpose, capabilities, installation | Rewrite and retain | Concise home page; installation and link to Getting started first, with a short capability summary |
| `index.md`: Where to start | Replace | Task-ordered links, with Getting started first |
| `index.md`: user statistics | Retain, move lower | Keep only after first-use material; preserve asset and attribution |
| `introduction.md`: multiport ABCD theory | Move/review | Retire as a top-level page; retain accurate general theory in Fundamental concepts only if it describes current behavior |
| `introduction.md`: interconnecting multiports | Move/review | Place valid user choices in Network construction; derivation belongs in Fundamental concepts |
| `introduction.md`: analysis workflow | Transfer and remove standalone page | Briefly orient Getting started/home and link to the analysis guide |
| `network.md`: Models and named ports | Rewrite | User-level terminal choices in Network construction; component-specific port contracts on component pages and API reference |
| `network.md`: Buses and individual nets | Retain and refocus | Network construction; explain compatible domains/frames, construction, observable validation, and a minimal example |
| `network.md`: Inputs, bases and limits | Move and rewrite | Component/input guidance; exact metadata and exhaustive fields in API reference |
| `network.md`: Power flow and per-port values | Split | User decisions in initialization; result interpretation in analysis; exact structures in API reference |
| `network.md`: Calculation sequence | Rewrite | Brief workflow in Getting started and analysis guide; implementation ordering in Developers only when needed |
| `network.md`: Single-line network diagrams | Move/condense | Network construction with `diagram` example and link to Network Diagram example |
| `network.md`: Migrating from Element and Setpoint | Move | Developers migration/history page; add user-guide link for legacy readers |
| `manual/fundamental_concepts.md`: Why impedance-based analysis; ABCD basics and input/output impedance | Audit and curate | Keep valid conceptual framing in one Fundamental concepts chapter; remove package-behavior claims made obsolete by the current model |
| `manual/fundamental_concepts.md`: ABCD combination, abc/dqz and bipolar transformations, ABCD reduction, Y/Z relationships | Audit equation-by-equation | Retain only scientifically valid and relevant background in the single chapter; preserve stable cross-reference IDs where retained |
| `manual/fundamental_concepts.md`: impedance, transformer, line, cable, MMC, and shunt model theory | Split by audience | Short model choices and constructor contracts on component pages; valid derivations in Fundamental concepts; stale implementation descriptions removed |
| `manual/fundamental_concepts.md`: MMC controls and steady-state solution | Audit | Move use/configuration guidance to MMC page; retain validated theory in Fundamental concepts; exact implementation behavior in API/developer material |
| `manual/fundamental_concepts.md`: operating-point initialization and branch/component equivalent rules | Split | User decisions and troubleshooting in initialization; validated equations in Fundamental concepts; low-level conversion details in API/developer reference |
| `initialization.md` | Refocus and retain | When initialization is required, what is solved/reused, references/setpoints, result interpretation, and failure diagnosis; move detailed equations out |
| `results.md`: primitive calculations and stability calculations | Retain and refocus | User task guide from calculate to inspect, interpret, and plot; link full signatures and fields to API reference |
| `results.md`: plot completed results | Retain | Concise result plotting path with link to relevant API and PlotBuilder developer guide |
| `results.md`: composite results | Condense or move details | User-facing overview only; complete structures belong in API reference |
| `source.md`, `impedance.md`, `transformer.md`, `transmission_line.md`, `MMC.md`, `TLC.md` | Standardize and audit | Purpose, minimal constructor, parameters/units, ports/domain, supported inputs/defaults, limitations, links to theory/API; add machine and black-box coverage |
| `gridspace.md` | Retain as advanced task guide | Link to core network and analysis workflow; avoid repeating setup |
| `pscad.md`, `package_extensions.md` | Retain as specialist guides | Recheck links and terminology after navigation changes |
| `examples/` and generated examples index | Extend and reorder | Add Getting started SMIB first; retain complex examples as follow-on material and audit executable/self-contained setup |
| `reference.md` | Expand or reorganize | Exact public signatures, exports, complete option and result-field details, and supported schemas only |
| `developers/` pages | Retain and extend | Add migration/history material; keep maintenance-only behavior and internal mappings out of user guides |
| `bibliography.md`, bibliography data, assets, statistics page | Retain and audit | Preserve valid citations and figure attribution; verify targets, alt text, captions, and paths |

## Scientific and reference review flags

- The Fundamental concepts chapter describes an earlier ABCD-centered package architecture. Verify each claim about the current calculation path before retaining it; do not infer that the equations are invalid merely because the architecture changed.
- Validate ABCD/Y/Z derivations, transformations, reduction assumptions, and component-equivalent equations against their cited sources and current supported models.
- Preserve the existing `reduction_ABCD` and `transformation-y-abcd` anchors if their destinations remain; update inbound links if material moves.
- Review historical component/control descriptions for current MMC, TLC, machine, and initialization behavior.
- The prose pipeline covers generated documentation. Keep source comments and rendered tutorial prose within the existing Vale/CSpell checks.

## Stage 1 gate result

- Page and section dispositions: recorded above for all current Markdown pages in `docs/src`; specialist and developer pages are retained with link/content review, and the key refactor pages have section-level dispositions.
- Component families and input interfaces: identified from exported constructors, type declarations, and `inputs.jl`.
- SMIB APIs and dependency constraints: identified from current constructors, examples, `docs/src/results.md`, `docs/make.jl`, and `docs/Project.toml`. Convergence remains an explicit Stage 2 executable check.
- Scientific and citation review flags: recorded above.

**Stage 1 passes. Stage 2 may begin.**

## Stage 2 gate result

- The first-use page, Literate SMIB source, and navigation/index registration are implemented.
- The docs manifest initially omitted newly added package dependencies; the CI `Pkg.develop`/`Pkg.instantiate`/`Pkg.precompile` setup refreshed the local environment before building.
- The GitLab-target and GitHub-target builds both completed through `include("docs/make.jl")` under Julia 1.12.2 with exit code 0.
- Documenter executed the SMIB workflow, generated the network diagram, impedance plot, and Nyquist plot, and passed doctest, cross-reference, exported-doc, and HTML rendering checks.
- The generated examples index lists the SMIB tutorial first. The generated home page and Getting started page are present.
- The first local attempt could not launch Julia because the PATH alias was inaccessible; the matching Julia installation and CI build setup were then located and used.

**Stage 2 passes. Stage 3 may begin.**

## Stage 3 gate result

- Added a component and input guide covering constructor keywords, declared input trees, `inputvalues`, copy-based `withinputs` updates, `component` updates, and references/limits.
- Added component guides for synchronous and induction machines and for black-box line and MMC models; linked all component families from the component overview and navigation.
- Refocused Network construction on user-visible bus and net choices, compatible frames/domains, and diagrams. Removed the connection-table schema and bus-numbering/ground internals from this user guide.
- Reworked initialization and analysis pages around the solve–linearize–calculate–inspect–plot path and added links among the guides.
- GitLab-target and GitHub-target docs builds both completed with exit code 0. Documenter executed doctests and passed reference, export, and rendering checks for the new pages and examples.

**Stage 3 passes. Stage 4 may begin.**

## Stage 4 final disposition and gate result

- Replaced the inherited 1,464-line theory chapter with one curated chapter on impedance-based small-signal analysis, port representations, AC frames, linear reduction assumptions, and operating-point context. Kept the historical-manual attribution and download link. Historical device-specific derivations, implementation-specific ABCD assembly, detailed MMC control algorithms, and component initialization recipes were retired from this general chapter; current component behavior remains in the component guides and exact interfaces in API reference.
- Kept the `reduction_ABCD` and `transformation-y-abcd` anchors with concise descriptions of applicability and singularity limits, preserving inbound link compatibility without presenting unsupported universal formulas.
- Migration from `Element` and `Setpoint` moved to `developers/migrations.md`; linked from Network construction. User-facing network docs continue to describe named buses/nets and contain no bus numbering, ground mapping, or connection-table schema.
- The API reference exposes exported symbols through `@autodocs` and documents supported `Bus`, `Net`, and `define` behavior. Exact signatures/options remain on API entries rather than duplicated in the conceptual chapter.
- Content dispositions above are final for the audited concept and network sections. No duplicate authoritative procedural explanations were retained in the concept chapter; it links to the relevant workflow and component pages.
- The source review found bus-numbering/connection-table details only in developer maintenance records and the migration description of the old API, not as current user guidance.
- GitLab-target and GitHub-target `include("docs/make.jl")` builds both reached `Finished docs build` with exit code 0. Documenter doctests, cross-reference/document checks, exported-doc checks, citations, and HTML rendering completed for both targets.
- Documenter emitted existing size/image-fallback warnings and warned about dollar delimiters in the curated math chapter; it did not report unresolved references or fail either build. The chapter's equations render through the configured math engine and this rendering will be reviewed during Stage 5.

**Stage 4 passes. Stage 5 may begin.**

## Stage 5 current gate status

- GitLab-target and GitHub-target builds both completed through the `include("docs/make.jl")` path with exit code 0. Documenter doctests, cross-reference/document checks, exported-doc checks, citation expansion, and HTML rendering passed for both. It emitted existing size and image-fallback warnings only.
- Generated HTML contains the expected concepts headings and retained anchors. Desktop and true 390px CSS viewport reviews confirmed the home page wraps cleanly, the curated concepts chapter has no horizontal overflow, and all four displayed formulas render through MathJax. At 390px, the concepts page document width is 390px and article width is 358px.
- Vale's fixture suite passed (4 files; 203 passed, 0 failed). A focused run over edited prose pages returned exit code 0 with 136 suggestions/warnings and no errors. The latest all-CI-files Vale run could not be rerun: although the Vale executable is installed, this process receives `Access is denied` when launching it. A previous full selection run before the latest edits failed with errors; its result is not evidence that the current source passes.
- The user explicitly waived CSpell for Stage 5 because it is available only on Linux. CSpell is therefore not a blocking criterion.
- `git diff --check` reported no whitespace errors.
- Stage 5 has **not passed**: the configured full Vale selection has not passed on the final source, and the required user walkthroughs (component/input lookup, compatible network construction, initialization decisions, API lookup, and migration guidance) have not all been recorded. Per the execution rule, the refactor remains gated at Stage 5.
