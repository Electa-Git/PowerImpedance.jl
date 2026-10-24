module ClassicFixtures
using PowerImpedance
import ..PSCADFixtures
include("../../../pscad/ieee9_network.jl")

function network(circuit)
    (; elements, rows, options) = circuit
    net = Network()
    net.voltageBase[1] = options.voltageBase
    for (name, element) in pairs(elements)
        add!(net, name, deepcopy(element))
    end
    for row in rows
        connect!(net, (row.element, Symbol("$(row.side).$(row.terminal)")), row.node)
    end
    for (name, element) in net.elements
        PowerImpedance.issingleport(element) || continue
        for terminal in 1:PowerImpedance.nop(element)
            connect!(net, (name, Symbol("2.$terminal")), :gnd)
        end
    end
    connect!(net)
    return net
end

im_network(; kwargs...) =
    network(PSCADFixtures._im_circuit(; kwargs...))
small_ac_network() =
    network(PSCADFixtures._small_ac_circuit())
sm_network() =
    network(PSCADFixtures._sm_circuit())
passive_ohl_network() =
    network(PSCADFixtures._passive_ohl_circuit())
transformer_network(; kwargs...) =
    network(PSCADFixtures._transformer_circuit(; kwargs...))
dc_network() =
    network(PSCADFixtures._dc_circuit())
dc_cable_network() =
    network(PSCADFixtures._dc_cable_circuit())
tlc_network(args...) =
    network(PSCADFixtures._tlc_circuit(args...))
mmc_network(args...) =
    network(PSCADFixtures._mmc_circuit(args...))
mmc_gfm_network() =
    network(PSCADFixtures._mmc_gfm_circuit())
mmc_compensated_network() =
    network(PSCADFixtures._mmc_compensated_circuit())
mmc_pq_network() = mmc_network(:pq)
mmc_vdc_network() = mmc_network(:vdc)
mmc_pf_network() = mmc_network(:pf)
mmc_qv_network() = mmc_network(:qv)
mmc_vac_network() = mmc_network(:vac)
tlc_case1_network() = tlc_network(true)
tlc_case2_network() = tlc_network(false)
tlc_vac_network() = tlc_network(false,
    PowerImpedance.OuterReactiveVacControl(
        pi_ctrl = PowerImpedance.PIControl(Kp = 0.0, Ki = 100.0)))
end
