# # Hybrid AC/DC network diagram
#
# Network diagrams are an optional GraphMakie extension. The active Makie
# backend owns display and export; `diagram` only builds and returns a figure.

using PowerImpedance
using PowerImpedance.NetworkBuilder: define
using GraphMakie
using CairoMakie

# This compact network has two physical AC buses, two DC buses, one converter,
# parallel AC coordinates on each physical bus, and a grounded DC load.

elements = (
    source = ac_source(pins = 3, transformation = true),
    ac_branch = impedance(z = 0.2 + 0.8im, pins = 3, transformation = true),
    converter = tlc(),
    dc_branch = impedance(z = 1.0, pins = 1),
    load = impedance(z = 10.0, pins = 1)
)

connections = (
    (node = :ac_1_d, element = :source, side = 1, terminal = 1),
    (node = :ac_1_q, element = :source, side = 1, terminal = 2),
    (node = :ac_1_d, element = :ac_branch, side = 1, terminal = 1),
    (node = :ac_1_q, element = :ac_branch, side = 1, terminal = 2),
    (node = :ac_2_d, element = :ac_branch, side = 2, terminal = 1),
    (node = :ac_2_q, element = :ac_branch, side = 2, terminal = 2),
    (node = :dc_1, element = :converter, side = 1, terminal = 1),
    (node = :ac_2_d, element = :converter, side = 2, terminal = 1),
    (node = :ac_2_q, element = :converter, side = 2, terminal = 2),
    (node = :dc_1, element = :dc_branch, side = 1, terminal = 1),
    (node = :dc_2, element = :dc_branch, side = 2, terminal = 1),
    (node = :dc_2, element = :load, side = 1, terminal = 1),
    (node = :gnd_dc, element = :load, side = 2, terminal = 1)
)

network = define(elements, connections)
view = diagram(network; interactive = false)
view.figure

# CairoMakie uses its ordinary save path; no PowerImpedance-specific export
# helper is needed.

output = joinpath(mktempdir(), "hybrid-network.svg")
CairoMakie.save(output, view.figure)
output
