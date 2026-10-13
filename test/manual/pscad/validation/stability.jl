# Complete source-clamped TLC + RL network. Native Jacobian blocks own control
# physics; native get_y owns the grid's dq signs. The descriptor imposes KCL,
# rather than testing a converter alone. No distributed-line state truncation.
function network_poles(A, B, C, D, resistance, inductance, rotation)
    n = size(A,1)
    identity = Matrix{Float64}(I,2,2)
    dynamics = [A zeros(n,2) B;
        zeros(2,n) -resistance*identity-inductance*rotation identity;
        C identity D]
    storage = diagm([ones(n); fill(inductance,2); zeros(2)])
    poles = filter(isfinite, eigvals(dynamics, storage))
    return sort!(poles; by=real, rev=true)
end

function network_stability(A, B, C, D, grid_y, resistance, inductance, rotation;
        frequencies = exp10.(range(-2,5; length=6001)))
    poles = network_poles(A,B,C,D,resistance,inductance,rotation)
    loops = cat((grid_y(ComplexF64(im*2π*f)) \ (C*((im*2π*f*I-A)\B)+D)
        for f in frequencies)...; dims=3)
    loci = PowerImpedance._trajectory_eigenvalues(loops)
    nyquist = PowerImpedance._nyquist_trial(loci,2π.*frequencies)
    # Close the complete conjugate-frequency contour. Counting positive-band
    # eigenlocus crossings alone misses a real-axis unstable root already
    # present below the first sample. The native models have real coefficients
    # and this proper TLC/RL loop has a finite high-frequency limit.
    characteristic=[det(I+loops[:,:,k]) for k in eachindex(frequencies)]
    contour=[conj.(reverse(characteristic));characteristic]
    turns=sum(angle(contour[mod1(k+1,length(contour))]/contour[k])
        for k in eachindex(contour))/(2π)
    net=-round(Int,turns)
    abs(turns+net)<1e-6 || error("unresolved complete Nyquist contour")
    residuals = [minimum(svdvals(grid_y(s)+C*((s*I-A)\B)+D)) /
        max(norm(grid_y(s)),1e-12) for s in poles if minimum(abs.(s.-eigvals(A)))>1e-6]
    stable = maximum(real,poles)<-1e-7 && maximum(real,eigvals(A))<-1e-7 && net==0
    return Dict("method"=>"complete-network native-admittance generalized Nyquist plus descriptor roots",
        "status"=>stable ? "passed" : "failed", "frequency_band_Hz"=>[first(frequencies),last(frequencies)],
        "frequency_count"=>length(frequencies), "nyquist_net"=>net, "positive_band_eigenlocus_net"=>nyquist.net,
        "subsystem_max_real_per_s"=>maximum(real,eigvals(A)),
        "most_positive_located_real_per_s"=>maximum(real,poles),
        "poles_real_per_s"=>real.(poles), "poles_imag_rad_per_s"=>imag.(poles),
        "max_characteristic_residual"=>isempty(residuals) ? 0.0 : maximum(residuals),
        "root_scope"=>"all finite complete-network descriptor roots; ideal source voltages clamped; RL dq states retained")
end

function stability_gate(net, entry)
    startswith(entry.id,"L1-") && return passive_gate(net,entry)
    entry.id == "L2-01" || error("no complete-network gate for $(entry.id)")
    # A/B/C/D are produced by the same native linearisation as get_y.
    dut=net.elements[:DUT]
    elec=dut.element_model.elec
    form=P.identify_rlc(net.elements[:Grid]; name=:Grid).form
    grid_y(s)=PowerImpedance.get_y(net.elements[:Grid],s)[1:2,1:2]
    rotation=real.((inv(grid_y(0.0im))-form.R*I)/form.L)
    gate=network_stability(dut.A,dut.B[:,2:3]/elec.vACbase,
        dut.C[2:3,:]*elec.iACbase,dut.D[2:3,2:3]*elec.iACbase/elec.vACbase,
        grid_y,form.R,form.L,rotation)
    gate["status"]=="passed" || error("L2-01 failed complete-network stability gate: $gate")
    return gate
end
