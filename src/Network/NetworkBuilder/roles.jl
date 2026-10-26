topology_role(::P.AbstractElementModel, connected_buses, grounded_ports) = :generic
topology_role(::P.Source, connected_buses, grounded_ports) = :source
topology_role(::P.AbstractConverter, connected_buses, grounded_ports) = :converter
"""
$(TYPEDSIGNATURES)

Return the converter topology role for a scan-based MMC.
"""
topology_role(::P.Blackbox_MMC, connected_buses, grounded_ports) = :converter
topology_role(::P.SynchronousMachine, connected_buses, grounded_ports) = :machine
topology_role(::P.InductionMachine, connected_buses, grounded_ports) = :machine
topology_role(::P.Transformer, connected_buses, grounded_ports) = :transformer

function topology_role(::P.Impedance, connected_buses, grounded_ports)
    isempty(grounded_ports) || return :shunt
    return all(connection -> connection.bus.domain == 2, connected_buses) ?
        :dc_branch : :ac_branch
end

function topology_role(::P.Transmission_line, connected_buses, grounded_ports)
    return all(connection -> connection.bus.domain == 2, connected_buses) ?
        :dc_branch : :ac_branch
end

function refined_role(role::Symbol, model, pmtype, input)
    pmtype === nothing && return role
    pmtype == "convdc" && return :converter
    pmtype == "branchdc" && return :dc_branch
    if pmtype == "branch"
        value = input === nothing ? false :
            get(input, "transformer", get(input, :transformer, false))
        transformer = value isa Number && !iszero(value)
        return transformer ? :transformer : :ac_branch
    end
    pmtype == "load" && return :load
    pmtype == "shunt" && return :shunt
    pmtype == "im" && return :machine
    if pmtype in ("gen", "gendc")
        return P.is_source(model) ? :source : :machine
    end
    return role
end
