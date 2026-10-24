"""
$(TYPEDSIGNATURES)

Return whether the model represents an ideal voltage source.

# Arguments

- `model`: Component model.

# Returns

- `true` for `Source`, otherwise `false`.
"""
is_source(::AbstractElementModel) = false

"""
$(TYPEDSIGNATURES)

Return whether the model represents a converter.

# Arguments

- `model`: Component model.

# Returns

- `true` for MMC, TLC and black-box MMC models, otherwise `false`.
"""
is_converter(::AbstractLinFreqDomain) = false
is_converter(::AbstractStateSpace) = false

"""
$(TYPEDSIGNATURES)

Return whether the model represents a synchronous generator.

# Arguments

- `model`: Component model.

# Returns

- `true` for `SynchronousMachine`, otherwise `false`.
"""
is_generator(::AbstractElementModel) = false

"""
$(TYPEDSIGNATURES)

Return whether the model represents an induction machine.

# Arguments

- `model`: Component model.

# Returns

- `true` for `InductionMachine`, otherwise `false`.
"""
is_inductionmachine(::AbstractElementModel) = false

"""
$(TYPEDSIGNATURES)

Return whether the model represents a passive component.

# Arguments

- `model`: Component model.

# Returns

- `false` for sources, converters and machines, otherwise `true`.
"""
is_passive(::AbstractElementModel) = true

"""
$(TYPEDSIGNATURES)

Return the complement of `is_passive(model)`.

# Arguments

- `model`: Component model.

# Returns

- `true` for sources, converters and machines, otherwise `false`.
"""
is_active(model) = !is_passive(model)

"""
$(TYPEDSIGNATURES)

Return whether the model declares exactly one electrical port.

# Arguments

- `model`: Component model with declared electrical ports.

# Returns

- `true` for one port, otherwise `false`.
"""
issingleport(model) = length(electricalconnections(model)) == 1

"""
$(TYPEDSIGNATURES)

Return whether every port is an AC port.

# Arguments

- `model`: Component model with declared electrical ports.

# Returns

- `true` when every declared port is an AC port, otherwise `false`.
"""
is_three_phase(model) = all(port -> isac(port.domain), electricalconnections(model))

"""
$(TYPEDSIGNATURES)

Return the port and terminal labels in the model's admittance row order.

# Arguments

- `model`: Component model with declared electrical ports.

# Returns

- Tuple of `(port, terminal)` symbol pairs in the model's own coordinates.
  The default follows port declaration order and each port's terminal order.
  MMC and TLC rows follow DC, AC d, AC q. Machine rows follow AC d, AC q.
"""
admittance_order(model) = Tuple((name, terminal)
    for (name, port) in pairs(electricalconnections(model)) for terminal in port.terminals)
