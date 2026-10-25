# # Hybrid AC/DC network diagram
#
# Network diagrams are an optional GraphMakie extension. The active Makie
# backend owns display and export; `diagram` only builds and returns a figure.
# A legend beside the diagram identifies the glyphs for its buses, branches and components.

using PowerImpedance
using PowerImpedance.NetworkBuilder: Bus, define
using GraphMakie
using CairoMakie

# This compact network has two physical AC buses, two DC buses, one converter,
# parallel AC coordinates on each physical bus, and a grounded DC load.
# Diagram details identify each connected `port` and list `grounded_ports`
# for components connected to ground.

elements = (
    source = ac_source(),
    ac_branch = impedance(z = 0.2 + 0.8im, conductors = 3),
    converter = tlc(),
    dc_branch = impedance(z = 1.0, conductors = 1),
    load = impedance(z = 10.0, conductors = 1)
)

connections = (
    Bus(:ac_1_; ports = ((:source, :ac), (:ac_branch, :side1)), domain = ACDQ),
    Bus(:ac_2_; ports = ((:ac_branch, :side2), (:converter, :ac)), domain = ACDQ),
    Bus(:dc_1; ports = ((:converter, :dc), (:dc_branch, :side1))),
    Bus(:dc_2; ports = ((:dc_branch, :side2), (:load, :side1))),
    Bus(:gnd_dc; ports = ((:load, :side2),))
)

network = define(elements, connections)
view = diagram(network; interactive = false)
view.figure

# CairoMakie uses its ordinary save path; no PowerImpedance-specific export
# helper is needed.

output = joinpath(mktempdir(), "hybrid-network.svg")
CairoMakie.save(output, view.figure)
output
