# Development conventions

These conventions declare the project's current intent. Automated formatting, linting, and release checks will be introduced separately after the team has settled the remaining details.

## Versioning

Use [Semantic Versioning](https://semver.org/):

- Increment `MAJOR` for incompatible public API changes.
- Increment `MINOR` for backward-compatible functionality.
- Increment `PATCH` for backward-compatible fixes.

During initial development (`0.y.z`), the public API is not yet stable. Minor releases may therefore contain breaking changes. Describe them clearly in the changelog.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) in the form:

```text
<type>[optional scope]: <short description>
```

Common types are `feat`, `fix`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, and `chore`. Use a concise imperative description. Mark breaking changes with `!` before the colon or with a `BREAKING CHANGE:` footer.

Keep commits focused. A commit should represent one coherent change and should leave the repository in a usable state.

## Changelog

Maintain `CHANGELOG.md` using the [Keep a Changelog](https://keepachangelog.com/) structure. Record user-visible changes under `Unreleased`, grouped where appropriate under `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, and `Security`. Move entries into a dated version section when releasing.

## Branches

Use short, descriptive branch names:

- Use lowercase words separated by hyphens.
- Use only ASCII letters, digits, hyphens, and the single slash after the prefix.
- Do not use spaces, underscores, punctuation, consecutive hyphens, or a trailing hyphen.
- Prefer `feature/` for new functionality, `bugfix/` for fixes, `hotfix/` for urgent production fixes, `release/` for release preparation, and `docs/` for documentation-only work.
- Delete short-lived branches after merge. Protect the default branch and merge into it through review after tests pass.

Examples include `feature/network-builder`, `bugfix/edge-indexing`, `hotfix/invalid-admittance`, `release/0.3.0`, and `docs/api-reference`.

## Formatting

Format Julia source with [JuliaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl) using its SciML style. The intended formatter configuration is:

```toml
style = "sciml"
```

Until formatter checks are automated, contributors should format changed Julia files before review and avoid unrelated formatting changes.

## General naming principles

- Type, struct, and module names use `CamelCase`.
- Function and variable names use lowercase `snake_case`.
- Constant names use uppercase `SNAKE_CASE`.
- Abstract type names begin with `Abstract`, for example `AbstractElement`.
- Type variables are a single capital letter, preferably related to the value being typed, for example `T`.
- Prefer whole words over abbreviations or single letters when they make the code clearer.
- Prefix package-internal or private names with two underscores, for example `__internal_cache`.
- Do not use Unicode in public APIs. Unicode is acceptable in internal code when it materially improves legibility.

Single-letter names are appropriate for mathematical entities whose domain meaning is supplied by the caller. For example, `a` and `b` are suitable in `*(a::AbstractMatrix, b::AbstractMatrix)`.

An additional exception applies when an implementation directly follows a mathematical expression with physical meaning and the technical literature consistently uses a short symbol. Names such as `v` for voltage, `i` for current, and `f` for frequency are acceptable when they preserve a clear correspondence between the code and the documented equation. Use this exception locally and only where the formula makes the meaning unambiguous.

Public API names must remain typeable in ASCII, including keyword arguments. If notation uses a symbol such as ``\eta``, expose an ASCII name such as `eta`. Unicode notation may still be used in the mathematical documentation.
