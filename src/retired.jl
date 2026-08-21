const _MIGRATION_DOCUMENTATION = "https://electa.pages.gitlab.kuleuven.be/controlgroup/PowerImpedance.jl/network/" *
                                 "#migration-from-the-removed-networkbuilder-names"

function _retired_name(old::Symbol, replacement::Symbol, example::AbstractString)
    throw(
        ArgumentError(
        "`$old` was removed. Use `$replacement` instead. " *
        "Migration example: $example. Documentation: $_MIGRATION_DOCUMENTATION",
    ),
    )
end

function BuilderState(args...; kwargs...)
    _retired_name(
        :BuilderState,
        :NetworkState,
        "network = define(elements, connections)"
    )
end
function ConnectionsRegistry(args...; kwargs...)
    _retired_name(
        :ConnectionsRegistry,
        :NetworkTopology,
        "topology = NetworkTopology(elements, connections)"
    )
end
function LinearizedAdmittanceCollection(args...; kwargs...)
    _retired_name(
        :LinearizedAdmittanceCollection,
        :AdmittanceLookup,
        "lookup = AdmittanceLookup(admittance_functions, matrix_indices)"
    )
end
function LinearizedInterface(args...; kwargs...)
    _retired_name(
        :LinearizedInterface,
        :NetworkLookup,
        "lookup = NetworkLookup(element_indices, node_indices)"
    )
end
function LinearizedAdmittanceNetwork(args...; kwargs...)
    _retired_name(
        :LinearizedAdmittanceNetwork,
        :NetworkModel,
        "model = convert(network, NetworkModel)"
    )
end
