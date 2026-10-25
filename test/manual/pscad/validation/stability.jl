# Complete source-referenced converter + RL network. Native Jacobian blocks compute
# control physics; native get_y supplies the grid's dq signs. The descriptor imposes
# network KCL without distributed-line state truncation.
function network_poles(A, B, C, D, resistance, inductance, rotation)
    n = size(A,1)
    identity = Matrix{Float64}(I,2,2)
    dynamics = [A zeros(n,2) B;
        zeros(2,n) -resistance*identity-inductance*rotation identity;
        C identity D]
    storage = diagm([ones(n); fill(inductance,2); zeros(2)])
    # Singular KCL rows have algebraic infinity, which eigvals can round to a
    # finite 1e18 quotient. Classify the QZ denominator at backward-error scale
    # before scoring finite roots; the strict stability margin is unchanged.
    pencil=schur(dynamics,storage)
    finite=abs.(pencil.β) .> 100eps(Float64)*max(norm(storage),1.)
    poles=pencil.α[finite]./pencil.β[finite]
    return sort!(poles; by=real, rev=true)
end

function network_stability(A, B, C, D, grid_y, resistance, inductance, rotation;
        frequencies = exp10.(range(-2,5; length=6001)))
    poles = network_poles(A,B,C,D,resistance,inductance,rotation)
    loops = cat((grid_y(ComplexF64(im*2π*f)) \ (C*((im*2π*f*I-A)\B)+D)
        for f in frequencies)...; dims=3)
    loci = PowerImpedance._trajectory_eigenvalues(loops)
    nyquist = PowerImpedance._nyquist_trial(loci,2π.*frequencies)
    # The complete conjugate-frequency contour includes real-axis unstable roots below the
    # first positive-band sample, which positive-band eigenlocus crossings alone miss.
    # Native models have real coefficients, and the proper TLC/RL loop has a finite
    # high-frequency limit. VAC has an open-subsystem integrator at zero. The complete
    # contour is shifted infinitesimally right, includes its real-axis endpoint and counts
    # enclosed open-loop poles. Strictly stable complete-network roots are required;
    # device modes are neither removed nor tuned.
    contour_shift=1e-6
    characteristic=[det(I + grid_y(s) \ (C*((s*I-A)\B)+D))
        for s in ComplexF64.(contour_shift .+ im*2π.*[0.;frequencies])]
    contour=[conj.(reverse(characteristic[2:end]));characteristic]
    turns=sum(angle(contour[mod1(k+1,length(contour))]/contour[k])
        for k in eachindex(contour))/(2π)
    net=-round(Int,turns)
    abs(turns+net)<1e-6 || error("unresolved complete Nyquist contour")
    open_rhp=count(s->real(s)>contour_shift,eigvals(A))
    residuals = [minimum(svdvals(grid_y(s)+C*((s*I-A)\B)+D)) /
        max(norm(grid_y(s)),1e-12) for s in poles if minimum(abs.(s.-eigvals(A)))>1e-6]
    stable = maximum(real,poles)<-1e-7 && net+open_rhp==0
    return Dict("method"=>"complete-network native-admittance generalized Nyquist plus descriptor roots",
        "status"=>stable ? "passed" : "failed", "frequency_band_Hz"=>[first(frequencies),last(frequencies)],
        "frequency_count"=>length(frequencies), "nyquist_net"=>net,
        "nyquist_contour_shift_per_s"=>contour_shift, "nyquist_open_RHP_poles"=>open_rhp,
        "nyquist_closed_RHP_count"=>net+open_rhp, "positive_band_eigenlocus_net"=>nyquist.net,
        "subsystem_max_real_per_s"=>maximum(real,eigvals(A)),
        "most_positive_located_real_per_s"=>maximum(real,poles),
        "poles_real_per_s"=>real.(poles), "poles_imag_rad_per_s"=>imag.(poles),
        "max_characteristic_residual"=>isempty(residuals) ? 0.0 : maximum(residuals),
        "root_scope"=>"all finite complete-network descriptor roots; ideal source voltages clamped; RL dq states retained")
end

function stability_gate(net, entry)
    entry.category == :passive && return passive_gate(net,entry)
    entry.category == :device || error("no complete-network gate for $(entry.id)")
    dut=net.elements[:DUT]
    bases=device_bases(dut.elec)
    form=P.identify_rlc(net.elements[:Grid]; name=:Grid).form
    grid_y(s)=physical_y(net.elements[:Grid],s)[1:2,1:2]
    inductance = something(form.L, 0.0)
    rotation = iszero(inductance) ? zeros(2, 2) :
        real.((inv(grid_y(0.0im))-form.R*I)/inductance)
    A=dut.cache.A
    B=dut.cache.B ./ bases.voltage_inputs'
    C=dut.cache.C .* bases.current_outputs
    D=dut.cache.D .* bases.current_outputs ./ bases.voltage_inputs'
    if haskey(net.elements,:DC_load)
        # Only the algebraic DC node is eliminated, with converter states retained. KCL:
        # (Ddc + 1/R)*vdc = -Cdc*x - Ddc,ac*vac. Aeff retains all coupled DC-control
        # modes. The native get_y resistor supplies its physical conductance.
        g=real(physical_y(net.elements[:DC_load],0.0im)[1,1])
        denom=D[1,1]+g
        A=A-B[:,1:1]*(C[1:1,:]/denom)
        Bac=B[:,2:3]-B[:,1:1]*(D[1:1,2:3]/denom)
        Cac=C[2:3,:]-D[2:3,1:1]*(C[1:1,:]/denom)
        Dac=D[2:3,2:3]-D[2:3,1:1]*(D[1:1,2:3]/denom)
    else
        indices=bases.ac_indices
        Bac,Cac,Dac=B[:,indices],C[indices,:],D[indices,indices]
    end
    gate=network_stability(A,Bac,Cac,Dac,grid_y,form.R,inductance,rotation)
    if iszero(inductance)
        gate["root_scope"] = "all finite device-state roots; resistive grid algebraic; ideal source voltages clamped"
    end
    gate["DC_termination"]=haskey(net.elements,:DC_load) ?
        "physical DC resistor; exact algebraic node elimination, converter DC states retained" : bases.dc_voltage===nothing ? "not applicable: AC-only machine" : "ideal DC voltage source"
    return gate
end
