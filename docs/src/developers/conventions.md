# Development conventions

The `prose_check` job uses Vale to lint documentation in CI. Automated formatting,
other linting, and release checks are planned after the remaining details are settled.

## Versioning

Use [Semantic Versioning](https://semver.org/):

- Increment `MAJOR` for incompatible public API changes.
- Increment `MINOR` for backward-compatible functionality.
- Increment `PATCH` for backward-compatible fixes.

During initial development (`0.y.z`), minor releases can contain breaking public API changes. Describe them clearly in the changelog.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) in the form:

```text
<type>[optional scope]: <short description>
```

Common types are `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, and `chore`. Use a concise imperative description. Mark breaking changes with `!` before the colon or with a `BREAKING CHANGE:` footer.

Keep commits focused. Each commit represents one coherent change and leaves the repository in a usable state.

## Changelog

Maintain `CHANGELOG.md` using the [Keep a Changelog](https://keepachangelog.com/) structure. Record user-visible changes under `Unreleased`, grouped where appropriate under `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, and `Security`. Move entries into a dated version section when releasing.

## Branches

Use short, descriptive branch names:

- Use lowercase words separated by hyphens.
- Use only ASCII letters, digits, hyphens, and one slash after the prefix.
- Spaces, `_`, other punctuation, consecutive hyphens, and trailing hyphens are invalid.
- Prefer `feature/` for new functionality, `bugfix/` for fixes, `hotfix/` for urgent production fixes, `release/` for release preparation, and `docs/` for documentation-only work.
- Delete short-lived branches after merge. Protect the default branch and merge into it through review after tests pass.

Examples include `feature/network-builder`, `bugfix/edge-indexing`, `hotfix/invalid-admittance`, `release/0.3.0`, and `docs/api-reference`.

## Formatting

Format Julia source with [JuliaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl) using its SciML style. The intended formatter configuration is:

```toml
style = "sciml"
```

Until formatter checks are automated, format changed Julia files before review and avoid unrelated formatting changes.

## General naming principles

- Type, struct, and module names use `CamelCase`.
- Function and variable names use lowercase `snake_case`.
- Constant names use uppercase `SNAKE_CASE`.
- Abstract type names begin with `Abstract`, as in `AbstractElementModel`.
- Type variables are one capital letter, preferably related to the value being typed, such as `T`.
- Prefer whole words over abbreviations or single letters when they make the code clearer.
- Prefix package-internal or private names with two `_` characters, as in `__internal_cache`.
- Public API names use ASCII. Internal code can use Unicode when it improves legibility.

Single-letter names are appropriate for mathematical entities whose domain meaning is supplied by the caller. `a` and `b` are suitable in `*(a::AbstractMatrix, b::AbstractMatrix)`.

An additional exception applies when an implementation directly follows a mathematical expression with physical meaning and the technical literature consistently uses a short symbol. Names such as `v` for voltage, `i` for current, and `f` for frequency are acceptable when they preserve a clear correspondence between the code and the documented equation. Use this exception locally and only where the formula makes the meaning unambiguous.

Public API names must remain typeable in ASCII, including keyword arguments. If notation uses a symbol such as ``\eta``, expose an ASCII name such as `eta`. Unicode notation may still be used in the mathematical documentation.

## Component models and topology

Constructors return component models directly. Declare electrical ports with
`electricalconnections` and configurable inputs with `inputs`. Input metadata
uses `Input`. Configured values are read with `inputvalues`. Use `withinputs`
or `component` for configured copies, `bases` for model bases, and `limits`
for stored operating limits.

Control references use per-unit values on the model bases. Source inputs use
physical units. Physical terminal powers and signed currents are positive into
each component port. Linearized admittances use `Y = I_in / V`.

Topology declarations use `NetworkBuilder.Bus` and `NetworkBuilder.Net` with
named ports and symbol terminal labels. The bus selects the AC frame. Keep
component-specific equations in the component implementation. Network assembly
uses the declared ports, input data and solved terminal values.
