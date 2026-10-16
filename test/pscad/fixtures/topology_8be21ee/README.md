These electrical graphs were extracted from the 14 passive and machine fixture exports generated
once from unmodified commit `8be21eecabb85d29d2896bc51562f61344338604`.
Each TOML records that commit and the SHA-256 of its source `.pscx` file. Reference
exports used the XML suite's 0.3 s / 50 μs / 250 μs / 0.2 s snapshot settings;
machine exports used 5 s. The ΔY exports use the existing unsolved XML path.
These settings do not change circuit connectivity or component parameters.

`topology.jl` extracts circuit ports, wire segments (including the old abutments
and multi-segment paths), case-insensitive node labels, and ground. Component
parameters and ordered electrical port numbers are retained. Coordinates,
component ids and internal node label names are omitted from the saved graph.
Transformer winding order and ammeter polarity remain significant.
Equivalent records at cable interfaces are matched by graph isomorphism.

Module graphs retain xnodes and check their correspondence with electrical SVG
ports. Row components retain their complete material and fitting parameters;
row geometry is separate from circuit nodes. Cable wrapper fields are retained,
and its terminal attachments belong to the cable interfaces.

A net requires two attached ports unless it is ground or carries a voltage
probe (including the monitored network buses in these fixtures). Zero-attachment
node labels are retained and rejected. The check describes the written XML.
It cannot establish that the native loader retained its contents or that a
physically identical conductance matrix has the same numerical pivot behavior.

The permitted shunt-meter placement change is listed explicitly in
`../shunt_meter_moves.toml`. `shunt_meter_returns` applies exactly those named
bus -> meter -> passive -> ground to bus -> passive -> meter -> ground moves
to the preserved reference graphs. It checks the original ordered pins and
passive ground connection, leaves every component parameter unchanged, and
reports each move during XML verification. Machine graphs retain their original placements. Unlisted topology changes, meter reversals and parameter changes fail.

`../yy_named_broken.pscx` retains the failing named-node YY export, SHA-256
`9f76519581d73b96018c619ba9a0c932f642e0e1600259bcc4c62bff681791bc`. It reproduces the isolated
secondary's ideal-meter grounding chain in offline XML checks. Historical
abutments let PSCAD reuse the load branch's current; named stubs instantiate
separate ideal meters, so raw graph equality alone could not detect this native
change. The production grounding check applies to the named-node construction.

`../yy_load_return_phasors.toml` records independent native peak current phasors
from the passing d40f623 reference and the passing load-return diagnostic.
It identifies each output file and SHA-256, the 1.8 < t <= 2.0 s window,
2000 samples, and the Fourier convention. Plan and XML tests verify the
exported meter's ordered current pins, RMS value and wrapped phase against this
reference, using the existing comparison tolerances (2% current, 1 degree).
