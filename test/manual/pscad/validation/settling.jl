function gfl_settling(gate; tone_peak_pu = 5e-5)
    decay = -gate["most_positive_located_real_per_s"]
    decay > 0 || error("settling requires stable complete-network modes")
    # Conservative 1 pu transient, divided by the single-tone drive and the
    # unchanged 0.02 entry floor. Target 0.1%, tenfold below the 1% window gate.
    target = 0.001
    decay_times = log(1 / (tone_peak_pu * 0.02 * target))
    start = ceil(max(16.0, 0.2 + decay_times/decay, 2.0 + decay_times/decay))
    return Dict("decay_per_s" => decay, "decay_times" => decay_times,
        "assumed_initial_transient_pu" => 1.0, "prediction_target" => target,
        "entry_floor_pu" => 0.02, "tone_peak_pu" => tone_peak_pu,
        "window_starts_s" => [start, start + 1.0], "window_duration_s" => 1.0,
        "simulation_time_s" => start + 2.0,
        "predicted_normalized_tail" => exp(-decay*(start-2.0))/(tone_peak_pu*0.02),
        "scope" => "native pole envelope sizing; sampled/unmodelled modes and residues unbounded; actual unchanged gates mandatory")
end
