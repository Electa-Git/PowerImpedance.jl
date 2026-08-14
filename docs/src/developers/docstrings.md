# Docstrings

The following docstring standards are adopted across the codebase.

## General principles

1. **Placement:** Place a docstring immediately before the struct, constructor, function, module, or constant that it describes.
2. **Delimiter:** Use triple double quotes (`"""`) for docstrings except for individual struct fields and constants, which use single-line string docstrings.
3. **Implementation first:** Describe the behavior implemented by the code. Do not infer behavior, units, or mathematics from a name alone.
4. **Conciseness:** Avoid redundancy. Present each fact once, in the appropriate section.
5. **Tone:** Use formal, precise scientific language. Avoid contractions, colloquialisms, and ambiguous wording.

## Physical unit formatting

All arguments, return values, struct fields, and constants that represent physical quantities must include their SI units.

1. Enclose units in double-backslash escaped square brackets, for example `\\[m\\]`, `\\[Hz\\]`, `\\[Ω\\]`, and `\\[H/m\\]`.
2. Mark physical quantities without dimensions as `\\[dimensionless\\]`.
3. Do not add unit annotations to non-physical values such as counters, flags, indices, and collection sizes.
4. Use standard SI symbols. Use the Unicode middle dot for multiplication when appropriate, for example `\\[Ω·m\\]`.
5. Inside comments in `julia` example blocks, use ordinary square brackets, for example `# [m]`, because the comment is Julia source rather than docstring prose.

## Mathematical formulation formatting

Use LaTeX whenever a function directly implements a mathematical expression, reduction, approximation, or physical law that is important for understanding its behavior. Put the expression in a `math` block within `# Notes`, followed by definitions of its symbols when they are not already unambiguous from `# Arguments`.

Whether mathematics is required is determined from the implementation, not from a function-name convention. In particular, a `calc_` prefix neither requires nor excuses a formula by itself. Simple accessors, wrappers, dispatch helpers, and bookkeeping functions generally do not need a mathematical section.

Within Julia docstrings, escape LaTeX commands with a second backslash:

````julia
"""
    transfer_impedance(resistance, inductance, frequency)

Calculate the series impedance at a specified frequency.

# Arguments

- `resistance`: Series resistance `\\[Ω\\]`.
- `inductance`: Series inductance `\\[H\\]`.
- `frequency`: Frequency `\\[Hz\\]`.

# Returns

- Complex series impedance `\\[Ω\\]`.

# Notes

This function implements

```math
Z(f) = R + \\mathrm{j} 2 \\pi f L,
```

where ``R`` is the resistance, ``L`` is the inductance, and ``f`` is the frequency.

# Examples

```julia
z = transfer_impedance(0.1, 1e-3, 50.0) # [Ω]
```
"""
function transfer_impedance(resistance, inductance, frequency)
````

## `DocStringExtensions` abbreviations

`DocStringExtensions` abbreviations insert information derived from the documented object. They reduce duplication and keep generated documentation aligned with method and type definitions.

- `$(SIGNATURES)` inserts the documented method signatures without argument type annotations.
- `$(TYPEDSIGNATURES)` inserts the documented method signatures with argument types. Use this at the start of function and constructor docstrings.
- `$(FUNCTIONNAME)` inserts the documented function name. It is useful in examples that should remain valid after a rename.
- `$(TYPEDEF)` inserts the documented type declaration, including type parameters and supertypes.
- `$(TYPEDFIELDS)` inserts the fields, their declared types, and their field docstrings.
- `$(IMPORTS)` inserts the modules imported by a documented module.
- `$(EXPORTS)` inserts the names exported by a documented module.

These expressions are Julia string interpolations evaluated while the docstring is attached. Use only abbreviations that add information to the rendered docstring; do not repeat their generated content manually.

## Documentation templates

### Structs

Use `$(TYPEDEF)` for the declaration and `$(TYPEDFIELDS)` for the field list:

````julia
"""
$(TYPEDEF)

Represent a physical entity with specific properties.

$(TYPEDFIELDS)
"""
struct StructName
    "First physical property `\\[unit\\]`."
    first_property::Float64

    "Dimensionless model parameter `\\[dimensionless\\]`."
    model_parameter::Float64
end
````

Place a single-line string docstring immediately above each field. Do not use block docstrings, inline comments, or a manually maintained field list for field documentation.

### Constructors

Julia attaches an ordinary docstring to an outer constructor defined at module
scope. Do not add `@doc` to an outer constructor:

````julia
"""
$(TYPEDSIGNATURES)

Construct a [`StructName`](@ref) instance.

# Arguments

- `first_property`: First physical property `\\[unit\\]`.
- `model_parameter`: Dimensionless model parameter `\\[dimensionless\\]`.

# Returns

- A [`StructName`](@ref) instance.

# Examples

```julia
instance = $(FUNCTIONNAME)(1.0, 0.5)
```
"""
function StructName(first_property, model_parameter)
````

An inner constructor is a method written inside the `struct` body. Julia does
not attach a bare string there as the constructor's documentation, so an inner
constructor requires `@doc`:

````julia
"""
$(TYPEDEF)

Represent a physical entity with specific properties.

$(TYPEDFIELDS)
"""
struct StructName
    "First physical property `\\[unit\\]`."
    first_property::Float64

    "Dimensionless model parameter `\\[dimensionless\\]`."
    model_parameter::Float64

    @doc """
    $(TYPEDSIGNATURES)

    Construct a [`StructName`](@ref) instance.

    # Arguments

    - `first_property`: First physical property `\\[unit\\]`.
    - `model_parameter`: Dimensionless model parameter `\\[dimensionless\\]`.

    # Returns

    - A [`StructName`](@ref) instance.

    # Examples

    ```julia
    instance = $(FUNCTIONNAME)(1.0, 0.5)
    ```
    """
    function StructName(first_property, model_parameter)
        new(first_property, model_parameter)
    end
end
````

The distinction is structural: use `@doc` for methods inside a `struct`, and
use an ordinary immediately preceding docstring for methods outside it.

### Functions and methods

Start with `$(TYPEDSIGNATURES)` and use the following section order:

1. Description, without a heading.
2. `# Arguments`.
3. `# Returns`.
4. `# Notes`, only when useful. Include LaTeX here when the implementation requires mathematical explanation.
5. `# Errors`, only when the function deliberately throws or propagates errors that callers should anticipate.
6. `# Examples`.

Separate the description and each section with exactly one blank line. List arguments in declaration order and state defaults where applicable. Document every member of a returned tuple individually.

````julia
"""
$(TYPEDSIGNATURES)

Describe the function's purpose concisely.

# Arguments

- `arg1`: Description and physical unit `\\[unit\\]`. Default: `value`.
- `arg2`: Description `\\[dimensionless\\]`.

# Returns

- Description of the return value and its physical unit `\\[unit\\]`.

# Notes

Include implementation-relevant assumptions, limitations, or LaTeX mathematics here.

# Errors

- Throws `ArgumentError` when the input is outside the supported domain.

# Examples

```julia
result = $(FUNCTIONNAME)(1.0, 0.5) # [unit]
```
"""
function function_name(arg1, arg2)
````

Examples must use meaningful input values. Include an expected result or behavior only when it can be stated accurately. Dedicated cross-reference lists are not maintained in docstrings.

### Modules

Begin with the module name indented by four spaces. Describe the module's purpose and main capabilities explicitly:

````julia
"""
    ModuleName

Describe the module's purpose within PowerImpedance.

# Overview

- Summarize the principal capability.
- Summarize another principal capability.

# Dependencies

$(IMPORTS)

# Exports

$(EXPORTS)
"""
module ModuleName
````

### Constants

Use a single-line docstring. Include the conventional symbol and SI unit when the constant represents a physical quantity:

```julia
"Magnetic constant (vacuum permeability), μ₀ = 4π × 10⁻⁷ `\\[H/m\\]`."
const VACUUM_PERMEABILITY = 4π * 1e-7
```

## Common mistakes to avoid

- Omitting a central formula when it materially explains the implementation.
- Inventing physical meaning, symbols, units, defaults, or expected numerical results.
- Omitting `@doc` from an inner constructor defined inside a `struct`.
- Adding unnecessary `@doc` to an outer constructor defined at module scope.
- Using a block docstring or inline comment for a struct field.
- Using the wrong section order or retaining empty optional sections.
- Adding a dedicated cross-reference section.
- Escaping units inside Julia example comments, or failing to escape units and LaTeX commands in docstring prose.
- Repeating information already generated by a `DocStringExtensions` abbreviation.
