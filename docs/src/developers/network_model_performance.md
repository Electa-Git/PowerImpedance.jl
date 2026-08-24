# Network-model performance comparison

The topology and model-name refactor was compared with the frozen source at
commit `28553eb6e2cb36df5f86c6d5194dbd4232ea1812`. The current measurement used
the uncommitted refactor working tree based on the same commit.

## Host and method

- Date: 2026-08-19
- Julia: 1.12.6
- Operating system: Linux 5.14.0-687.33.1.el9_8.x86_64
- Processor: Intel Core i9-13950HX
- Fixture: three parallel scalar impedance elements between one retained node
  and ground
- Frequency vector: 400 logarithmically spaced points from 1 Hz to 10 kHz
- Calculation: passive `make_y_edge` evaluation from the linearized network
  model
- Warm-up: two complete evaluations before measurement
- Samples: 200 execution-time and allocation measurements
- Reported statistic: median

The baseline used the former pin grammar and
`LinearizedAdmittanceNetwork`. The refactored case used equivalent named
topology rows and `NetworkModel`. Component values, node selection, frequency
axis, Julia process settings, and host were otherwise identical.

## Results

| Source | Median time | Median allocated bytes |
|:--|--:|--:|
| Frozen baseline | 0.9135885 ms | 2,305,856 B |
| Refactored working tree | 0.9194500 ms | 2,305,776 B |
| Relative change | +0.64% | −0.0035% |

The measured time increase is below the 10% acceptance limit. Allocated bytes
decreased by 80 bytes and therefore satisfy the 5% allocation limit.

These measurements describe warmed admittance evaluation on this host. CI job
duration includes dependency loading, compilation, solver fixtures, and runner
scheduling and is not a substitute for this comparison.
