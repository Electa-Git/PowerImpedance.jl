# Calculation parity record

The pre-refactor source was frozen at commit
`28553eb6e2cb36df5f86c6d5194dbd4232ea1812`. The numerical comparison uses
the IEEE 39-bus AC/DC fixture, including generators, loads, transformers,
transmission branches, a DC source, and the STATCOM model. The power-flow
options are identical in both calculations: a 267.94 kV line-to-line voltage
base and bounded bus-voltage variables.

## Power flow and operating point

The direct `NetworkState` parameterization and the preserved Classic network
calculation both terminated with `LOCALLY_SOLVED`. Their integer bus numbers
differ because the two representations construct buses in different orders.
Values were therefore compared through element-to-component mappings and
through the complete set of physical node names assigned to each AC or DC bus.

The frozen reference contains every numeric field returned in the `bus`, `gen`,
and `branch` solution groups, together with every numeric field of the calculated
STATCOM `Setpoint`, for:

- 49 AC buses and 2 DC buses;
- 10 AC generators and 1 DC generator;
- 55 AC branches and 1 DC branch;
- the AC/DC converter;
- the calculated STATCOM `Setpoint`.

Passive shunts occur in the PowerModelsACDC input data but have no entries in
the solved `solution` dictionary. Their input counts and mappings are checked
separately. The largest absolute difference among solved component fields was
`1.990074771640593e-14`, in the reactive flow of `Zg31`. The largest absolute
difference among bus fields was `1.1102230246251565e-15`, in the voltage
magnitude of the bus containing `Bus7d` and `Bus7q`. All six STATCOM setpoint
fields agree within an absolute tolerance of `1e-8`.

The regression is implemented in `test/NetworkBuilder_test.jl`. It also checks
termination status, solution-group presence, input-data counts, node mappings,
element mappings, and the compatibility accessors of `PowerFlowResult`.

## Frequency-domain calculations

The same IEEE 39-bus fixture compares the Classic and `NetworkModel` routes
after operating-point calculation. The tests retain the same frequency axis,
node order, grounded-node treatment, and eliminated STATCOM selection. They
compare:

- linearized converter state matrices;
- nodal and edge admittance matrices;
- the reduced harmonic impedance tensor.

The impedance comparison uses relative and absolute tolerances of `1e-12`.
The nodal-admittance comparison uses relative and absolute tolerances of
`1e-7`, matching the existing fixture treatment of the DC-side dummy
admittance.

The separate [network-model performance comparison](network_model_performance.md)
records warmed execution time and allocated bytes on the same frozen source
and refactored working tree.
