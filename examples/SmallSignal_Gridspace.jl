# # Gridspace small-signal stability analysis
#
# This tutorial carries a declarative `Gridspace{BuilderState}` through the
# complete small-signal path. The staged API is shown first because it exposes
# the active-device and passive-network partition. The fused API follows when
# only the loop gain or final stability result is needed.

using Plots
using PowerImpedance
using PowerImpedance.NetworkBuilder: sampled_frequency_response

# ## Construct the parametric systems
#
# The IEEE39 Gridspace tutorial defines the system explicitly and changes one
# common soil-resistivity value on every overhead line and cable. Including it
# here reuses that authoritative network declaration; no response has been
# calculated yet.

include(joinpath(
    pkgdir(PowerImpedance),
    "examples",
    "IEEE39bus_Gridspace.jl"
));

builder_space = ieee39_soil_builder_space((10.0, 100.0, 1000.0));

# These three cases have identical topology and active-device parameters. Soil
# resistivity changes passive line admittances only, so one call can reuse the
# active operating point and linearization after its first case.

frequency_range = (10.0, 1e3, 80);

# ## Explicit staged API
#
# `make_y_node` returns one active-element admittance response per deterministic
# case, an ordered node schema, and the common angular-frequency vector.

Ynode, node_schema, omega = make_y_node(
    builder_space;
    freq_range = frequency_range,
    seed = 2026
);

# Passing the complete schema—not merely one node vector—makes `make_y_edge`
# inherit case order and study identity. For an uncertain builder space it also
# inherits trial count, seeds, and distribution.

Yedge, _, _ = make_y_edge(
    builder_space;
    nodelist = node_schema,
    freq_range = frequency_range
);

# This familiar expression has specialized response dispatch. Each inverse and
# product is applied to a complete numeric matrix at one frequency and trial.
# Aggregated mean±standard-deviation matrices are never inverted.

loopgain_staged = inv.(Yedge) .* Ynode;

staged_nyquist = nyquistplot(
    loopgain_staged,
    omega;
    zoom = "yes",
    SM = "GM",
    display_plot = false
);

staged_plot = plot(
    (case.plots.nyquist for case in staged_nyquist)...;
    layout = (1, length(staged_nyquist)),
    size = (1500, 500),
    plot_title = "Staged IEEE39 loop gain versus soil resistivity"
);
staged_plot

# ## Fused loop-gain API
#
# `make_loopgain` evaluates active and passive admittances from the same sampled
# builder and one active-device linearization per trial.

loopgain_fused, fused_schema, fused_omega = make_loopgain(
    builder_space;
    freq_range = frequency_range,
    seed = 2026
);

fused_nyquist = nyquistplot(
    loopgain_fused,
    fused_omega;
    zoom = "yes",
    SM = "GM",
    display_plot = false
);

fused_plot = plot(
    (case.plots.nyquist for case in fused_nyquist)...;
    layout = (1, length(fused_nyquist)),
    size = (1500, 500),
    plot_title = "Fused IEEE39 loop gain versus soil resistivity"
);
fused_plot

# The terminal convenience call performs both operations:
#
# ```julia
# direct_nyquist = nyquistplot(
#     builder_space;
#     freq_range = frequency_range,
#     trials = 1000,
#     distribution = :normal,
#     seed = 2026,
#     zoom = "yes",
#     SM = "GM",
# )
# ```
#
# `trials` is used only by uncertain cases. If converter or source parameters
# are uncertain, every sampled active object repeats power flow, nonlinear
# equilibrium, and linearization. Passive-only samples may reuse the active
# operating point. No outer Monte Carlo wrapper is needed.

# ## Recover results and call other tools
#
# Every plotting call returns data as well as plots. The case coordinates
# identify the deterministic soil-resistivity value.

first_case = first(fused_nyquist);

(;
    coordinates = first_case.coordinates,
    trials = first_case.trials,
    uncertainty_source = first_case.uncertainty_source,
    assessment = first_case.output.assessment_probabilities,
    encirclements = first_case.output.encirclements,
    margins = first_case.output.margins
)

# The other parametric tools consume the complete response collection and use
# exact retained or replayed trials:
#
# ```julia
# bode = bodeplot(loopgain_fused; return_samples = true)
# passive = passivity(loopgain_fused)
# modes = EVD(loopgain_fused, fused_omega, 10.0, 1e3)
# margins = stabilitymargin(loopgain_fused; SM = "VM")
# unstable = unstable_frequency(loopgain_fused)
# ```
#
# For exact results produced by an external Monte Carlo solver, wrap a numeric
# `(nodes, nodes, frequencies, trials)` tensor with
# `sampled_frequency_response` before calling the same tools.
