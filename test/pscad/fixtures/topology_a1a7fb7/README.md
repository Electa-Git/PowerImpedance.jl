Electrical graphs extracted from commit `a1a7fb71d6ac189ddf06d58e2817dc4197dd4031`.
Each TOML records the commit and SHA-256 of its source `.pscx` file.
Exports use 0.3 s / 50 μs / 250 μs / 0.2 s snapshot settings;
networks containing machines use 5 s.

`topology.jl` extracts circuit ports, wire segments, node labels and ground.
Component parameters and ordered electrical port numbers are retained.
Coordinates and component ids are omitted. Graphs are compared with
`PSCADTopology.equivalent`. Probe names are listed in
`../export_probe_names_a1a7fb7.tsv`.
