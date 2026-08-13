module PowerImpedanceMeasurementsExt

using PowerImpedanceACDC
using Measurements
import Random

const NB = PowerImpedanceACDC.NetworkBuilder

NB._is_measurement(::Measurements.Measurement) = true
NB._measurement_nominal(value::Measurements.Measurement) = Measurements.value(value)
NB._measurement_error(value::Measurements.Measurement) = Measurements.uncertainty(value)
NB._make_measurement(mean::Real, standard_deviation::Real) =
    Measurements.measurement(mean, standard_deviation)

function NB._sample_measurement(rng, value::Measurements.Measurement, distribution::Symbol)
    nominal = Measurements.value(value)
    sigma = Measurements.uncertainty(value)
    return iszero(sigma) ? float(nominal) : rand(rng, NB._distribution(distribution, nominal, sigma))
end

function Base.iterate(grid::NB.RelativeGrid, state = nothing)
    iterator = Iterators.product(grid.vals, grid.rel_err)
    item = state === nothing ? iterate(iterator) : iterate(iterator, state)
    item === nothing && return nothing
    ((nominal, error), next_state) = item
    value = Measurements.measurement(nominal, abs(nominal) * error / 100)
    return value, next_state
end

function Base.iterate(grid::NB.AbsoluteGrid, state = nothing)
    iterator = Iterators.product(grid.vals, grid.abs_err)
    item = state === nothing ? iterate(iterator) : iterate(iterator, state)
    item === nothing && return nothing
    ((nominal, error), next_state) = item
    return Measurements.measurement(nominal, error), next_state
end

Base.eltype(::Type{<:NB.RelativeGrid}) = Measurements.Measurement{Float64}
Base.eltype(::Type{<:NB.AbsoluteGrid}) = Measurements.Measurement{Float64}

end
