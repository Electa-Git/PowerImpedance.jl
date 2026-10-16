tierb_phase_wave(time,dq)=hcat((dq[:,1].*cos.(2π*50*time.+phase)+dq[:,2].*sin.(2π*50*time.+phase)
    for phase in (0.,-2π/3,2π/3))...)
# Included inside PSCADValidationTests; all data and processes here are local.
@testset "Tier B frozen burst, metrics and common mode" begin
    spec=(;tone_peak_pu=.001,carrier_Hz=10.,burst_cycles=8,injection_time=1.,
        ringdown=(2.,4.),mode_seed=-2+2π*10im,fit_residual_limit=.10,
        fit_frequency_uncertainty=.02,fit_zeta_uncertainty=.10)
    time=collect(0.:.001:4.)
    burst=V.burst_wave(time,spec)
    @test all(iszero,burst[time.<1.])
    @test all(iszero,burst[time.>1.8])
    @test burst[1001]==0.
    @test maximum(abs,burst)<=.001
    graph,_,_=V.burst_graph(merge(spec,(;voltage_base_kV=1.)))
    @test count(n->n isa P.Compare,graph.nodes)==2
    @test count(n->n isa P.Trig,graph.nodes)==2
    tau=time.-2.
    y=hcat(exp.(-2tau).*cos.(2π*10tau) .+ .2 .+ .01tau,
        .3exp.(-2tau).*sin.(2π*10tau) .- .1 .- .02tau)
    fit=V.tierb_mode(time,y,spec)
    @test fit["status"]=="extracted"
    @test fit["frequency_Hz"]≈10. rtol=1e-6
    @test fit["alpha_per_s"]≈2. rtol=1e-6
    @test fit["zeta"]≈2/hypot(2,2π*10) rtol=1e-6
    @test fit["residual_relative"]<1e-8
    @test haskey(fit,"zeta_standard_error")
    @test V.tierb_mode_comparison(fit,fit)["status"]=="passed"
    wrong_frequency=copy(fit);wrong_frequency["frequency_Hz"]*=1.03
    @test V.tierb_mode_comparison(wrong_frequency,fit)["status"]=="failed"
    wrong_damping=copy(fit);wrong_damping["zeta"]*=1.11
    @test V.tierb_mode_comparison(wrong_damping,fit)["status"]=="failed"
    wrong_signal=hcat(exp.(-3tau).*cos.(2π*10.8tau),.3exp.(-3tau).*sin.(2π*10.8tau))
    wrong=V.tierb_mode(time,wrong_signal,spec)
    @test wrong["status"]=="extracted"
    @test V.tierb_mode_comparison(wrong,fit)["status"]=="failed"
    @test V.tierb_mode(time,zeros(length(time),2),spec)["status"]=="unextractable"
    @test V.tierb_mode(time[1:3000],y[1:3000,:],spec)["status"]=="unextractable"
    mixed=y.+hcat(sin.(2π*13time),cos.(2π*17time))
    @test V.tierb_mode(time,mixed,spec)["status"]=="unextractable"
    @test all(r["status"]=="passed" for r in V.tierb_metrics(y,y))
    @test all(r["status"]=="failed" for r in V.tierb_metrics(1.06y,y))
    @test all(r["status"]=="invalid_measurement" for r in V.tierb_metrics(y,zero(y)))
    bad=copy(y);bad[1]=NaN
    @test first(V.tierb_metrics(bad,y))["status"]=="invalid_measurement"
    @test_throws ArgumentError V.tierb_grid([0.,1.,2.,3.,4.,5.,6.,8.],zeros(8,2))
    # The shift is an error, never a fitted alignment parameter.
    shifted=circshift(y,(10,0))
    @test any(r["status"]=="failed" for r in V.tierb_metrics(shifted,y))
end

@testset "Tier B dependency-free DFT against direct sums" begin
    for n in (2, 8, 32, 128)
        values=ComplexF64[sin(.37k)+im*cos(.19k) for k in 0:n-1]
        expected=[sum(values[j+1]*cispi(-2*j*k/n) for j in 0:n-1) for k in 0:n-1]
        roots=[cispi(-2k/n) for k in 0:n÷2-1]
        transformed=V.tierb_dft!(copy(values),roots)
        @test transformed≈expected rtol=2e-13 atol=2e-13
        @test V.tierb_dft!(transformed,roots;inverse=true)≈values rtol=2e-14 atol=2e-14
    end
    @test_throws ArgumentError V.tierb_dft!(zeros(ComplexF64,3),zeros(ComplexF64,1))
end

@testset "Tier B convolution: exact transport, readout and fixed sample grid" begin
    time=collect(0.:.001:4.)
    spec=(;tone_peak_pu=1.,carrier_Hz=10.,burst_cycles=8,injection_time=.1)
    u=reshape(V.burst_wave(time,spec),:,1)
    # An integer transport delay has an independent sample-exact reference.
    response=s->reshape([exp(-.02s)],1,1)
    prediction=V.tierb_convolve(time,u,response)
    expected=vcat(zeros(20,1),u[1:end-20,:])
    @test norm(prediction-expected)/norm(expected)<1e-8
    @test size(prediction)==size(u)
    # First-order impulse convolution, with smooth drive and a known pole.
    lowpass=V.tierb_convolve(time,u,s->reshape([1/(s+3)],1,1))
    discrete=zeros(length(time),1)
    for k in 2:length(time)
        discrete[k]=exp(-.003)*discrete[k-1]+.001*(u[k-1]+u[k])/2
    end
    @test norm(lowpass-discrete)/norm(lowpass)<.002
    doubled=V.tierb_convolve(time,u,s->reshape([1/(s+3)],1,1);padding=4)
    @test norm(lowpass-doubled)/norm(lowpass)<1e-7
    fine_time=collect(0.:.0005:4.)
    fine_u=reshape(V.burst_wave(fine_time,spec),:,1)
    fine=V.tierb_convolve(fine_time,fine_u,response)
    @test length(fine_time)==size(fine,1)
    @test size(fine,1)>size(prediction,1)
    @test V.tierb_interpolate(time,u,fine_time[1:10]) isa Matrix
end

@testset "Tier B admission and baseline identity" begin
    @test V.M9D_TIERB_IDS==["L3-08","L3-04","L3-06"]
    mktempdir() do directory
        a=joinpath(directory,"a.pscx");b=joinpath(directory,"b.pscx")
        write(a,"<project><param name=\"d_amplitude_pu\" value=\"0.0\"/></project>")
        write(b,"<project><param name=\"d_amplitude_pu\" value=\"0.001\"/></project>")
        @test V.tierb_baseline_hash(a)==V.tierb_baseline_hash(b)
        write(b,read(b,String)*"changed topology")
        @test V.tierb_baseline_hash(a)!=V.tierb_baseline_hash(b)
        record=Dict{String,Any}("fixture_id"=>"L3-06","status"=>"prepared_station_pending")
        path=joinpath(directory,"manifest.toml")
        write(path,sprint(TOML.print,record))
        @test_throws ErrorException V.require_tierc_passed("L3-06";directory)
        record["status"]="passed";record["qualification_status"]="passed"
        write(path,sprint(TOML.print,record))
        @test_throws ErrorException V.require_tierc_passed("L3-06";directory)
        record["groups"]=Dict("composed_coarse"=>Dict("status"=>"passed"))
        record["source_files"]=Dict{String,Any}[]
        write(path,sprint(TOML.print,record))
        @test V.require_tierc_passed("L3-06";directory)["status"]=="passed"
    end
end

@testset "Tier B composed signal inventory and injection graph" begin
    for id in V.M9D_TIERB_IDS
        net=V.l3_network(id);point=power_flow(net);list=V.fixture_netlist(net,point)
        c=V.l3_circuit(id,net);spec=V.tierb_spec(id,list)
        inventory=V.tierb_channels(c,spec)
        plan,settings=V.scan_plan(list,spec,spec.driven_axis)
        @test all(p.kind in (:voltage,:current,:injection_current,:machine_speed,:machine_p,:machine_q)
            for p in plan.probes.channels)
        @test settings.simulation_time==spec.simulation_time
        @test settings.sample_step/settings.time_step≈25
        @test V.check_recorder_sampling(spec)==25
        @test V.check_recorder_sampling(V.tierb_variants(spec)[end].spec)==25
        @test length(inventory.labels)==length(inventory.bases)
        @test all(>(0),inventory.bases)
        port=only(filter(m->m.name=="CurrentPort_1",plan.modules))
        @test any(c->c isa P.ComponentPlan&&c.defn=="master:compare",port.canvas.components)
        @test count(c->c isa P.ComponentPlan&&c.defn=="master:compare",port.canvas.components)==2
        @test length(V.tierb_variants(spec))==5
        @test V.tierb_variants(spec)[end].spec.sample_step==spec.sample_step/2
        id=="L3-06" && @test any(p->p.kind==:machine_speed,plan.probes.channels)
        id=="L3-06" && @test any(p->p.kind==:machine_p,plan.probes.channels)
        time=collect(0.:.001:.02)
        channels=Dict{String,Vector{Float64}}()
        for p in plan.probes.channels
            if p.dim==3
                abc=tierb_phase_wave(time,hcat(fill(1.,length(time)),fill(.2,length(time))))
                for k in 1:3;channels[p.name*":"*string(k)]=abc[:,k];end
            else
                channels[p.name]=zeros(length(time))
            end
        end
        result=(;time,channels);model=(;probes=plan.probes,netlist=list)
        samples=V.tierb_samples(result,model,c)
        @test size(samples.signals)==(length(time),length(inventory.labels))
        @test size(samples.drive)==(length(time),2)
        @test samples.drive[:,1]≈ones(length(time))
        @test samples.signals[:,1]≈ones(length(time))
        mktempdir() do directory
            basepath=joinpath(directory,"base.pscx");burstpath=joinpath(directory,"burst.pscx")
            base="<param name=\"d_amplitude_pu\" value=\"0.0\"/><param name=\"q_amplitude_pu\" value=\"0.0\"/>"
            write(basepath,base);write(burstpath,replace(base,"0.0"=>"0.001";count=1))
            bm=merge(model,(;project_path=basepath));injected_model=merge(model,(;project_path=burstpath))
            zeroresult=(;time,channels=Dict(k=>zero(v) for (k,v) in channels))
            difference=V.tierb_subtract(result,zeroresult,injected_model,bm,c)
            @test difference.signals≈samples.signals
            @test difference.drive≈samples.drive
            @test_throws ArgumentError V.tierb_subtract(result,zeroresult,injected_model,injected_model,c)
            write(burstpath,read(burstpath,String)*"changed passive")
            @test_throws ArgumentError V.tierb_subtract(result,zeroresult,injected_model,bm,c)
        end
        @test V.tierb_protocol(spec)["damping_metric"]=="zeta = alpha / hypot(alpha, omega); alpha retained"
        # Exact full-vector readout, including the null-axis rotation.
        native=V.tierb_response(c,spec)
        discrete=V.tierb_response(c,spec;discrete=true)
        s=complex(1.,2π*spec.carrier_Hz)
        @test size(native(s))==(length(inventory.labels),2)
        angle=2π*spec.frequency*spec.time_step
        rotation=[cos(angle) sin(angle);-sin(angle) cos(angle)]
        functions=V.composed_device_functions(c;time_step=spec.time_step)
        nodal=V.composed_nodal(c,s,functions)
        injection=zeros(ComplexF64,length(c.nodes),2);injection[1:2,:]=I(2)
        expected=exp(s*spec.time_step).*((nodal\injection)*rotation)
        @test discrete(s)[1:length(c.nodes),:]≈expected rtol=1e-10
    end
end

@testset "Tier B queue continues after failures and stops on interrupts" begin
    expressions=Meta.parseall(read(joinpath(V.ROOT,"tierb.jl"),String)).args
    definition=only(filter(expressions) do statement
        statement isa Expr && statement.head==:function &&
            first(first(statement.args).args)==:run_m9d_tierb
    end)
    mktempdir() do directory
        harness=Module(:TierBQueueFixture)
        Core.eval(harness,:(using TOML))
        Core.eval(harness,:(const ROOT=$directory))
        Core.eval(harness,:(const M9D_TIERB_IDS=$(copy(V.M9D_TIERB_IDS))))
        Core.eval(harness,quote
            attempts=String[]
            interrupt_at=Ref("")
            require_committed_tierb()=nothing
            function run_tierb(id;remote,deadline)
                push!(attempts,id)
                id==interrupt_at[] && throw(InterruptException())
                id=="L3-08" && error("offline build failure")
                return Dict("status"=>id=="L3-04" ? "unextractable" : "passed")
            end
        end)
        Core.eval(harness,definition)
        attempts=Base.invokelatest(getproperty,harness,:attempts)
        interrupt_at=Base.invokelatest(getproperty,harness,:interrupt_at)
        runner=Base.invokelatest(getproperty,harness,:run_m9d_tierb)
        record=@test_logs (:warn,r"Tier B fixture failed; continuing queue") begin
            Base.invokelatest(runner;timeout=10.,remote=:offline)
        end
        @test attempts==V.M9D_TIERB_IDS
        @test record["outcomes"]["L3-08"]["status"]=="run_or_analysis_failed"
        @test record["outcomes"]["L3-04"]["status"]=="unextractable"
        @test record["outcomes"]["L3-06"]["status"]=="passed"
        path=joinpath(directory,"data","m9d5","queue.toml")
        @test TOML.parsefile(path)==record
        @test_throws ErrorException Base.invokelatest(runner;timeout=0.,remote=:offline)
        empty!(attempts);interrupt_at[]="L3-04"
        @test_logs (:warn,r"Tier B fixture failed; continuing queue") begin
            @test_throws InterruptException Base.invokelatest(runner;timeout=10.,remote=:offline)
        end
        @test attempts==["L3-08","L3-04"]
    end
end

@testset "Tier B synthetic comparison and measurement qualification" begin
    net=V.l3_network("L3-08");point=power_flow(net);list=V.fixture_netlist(net,point)
    c=V.l3_circuit("L3-08",net);spec=merge(V.tierb_spec("L3-08",list),
        (;injection_time=.05,simulation_time=.4,ringdown=(.12,.27)))
    time=collect(0.:spec.sample_step:spec.simulation_time)
    inventory=V.tierb_channels(c,spec);a=-real(spec.mode_seed);w=imag(spec.mode_seed)
    signals=hcat(([t<.1 ? 0. : .0001inventory.bases[j]*exp(-a*(t-.1))*cos(w*(t-.1)+j)
        for t in time] for j in eachindex(inventory.labels))...)
    wave=V.burst_wave(time.-spec.time_step,spec).*spec.current_base_kA
    angle=2π*spec.frequency*spec.time_step
    drive=hcat(wave.*cos(angle),wave.*sin(angle))
    sample=(;signals,drive,baseline=zero(signals))
    quality=V.tierb_quality(time,sample,c,spec)
    @test quality["status"]=="valid"
    @test quality["drive_amplitude_error"]<1e-12
    @test V.tierb_compare(time,signals,signals,spec)["status"]=="passed"
    @test V.tierb_compare(time,1.06signals,signals,spec)["status"]=="failed"
    @test V.tierb_compare(time,signals,signals,spec;valid=false)["status"]=="invalid_measurement"
    @test V.tierb_compare(time,signals,zero(signals),spec)["status"]=="invalid_measurement"
    @test all(m["status"]=="passed" for m in V.tierb_metrics(2*(signals/2),signals;limits=(rms=.02,peak=.02,gain=.02)))
    @test all(m["status"]=="failed" for m in V.tierb_metrics(1.03signals,signals;limits=(rms=.02,peak=.02,gain=.02)))
    @test V.tierb_quality(time,merge(sample,(;signals=200signals)),c,spec)["status"]=="invalid_measurement"
    @test V.tierb_quality(time,merge(sample,(;drive=zero(drive))),c,spec)["status"]=="invalid_measurement"
    drift=hcat((.02 .* time .* b for b in inventory.bases)...)
    @test V.tierb_quality(time,merge(sample,(;baseline=drift)),c,spec)["status"]=="invalid_measurement"
    @test_throws ArgumentError V.tierb_quality(time, sample,c,merge(spec,(;sample_step=spec.sample_step/2)))
end
