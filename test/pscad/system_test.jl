@testset "complete systems redesigned P2P physical data" begin
    redesigned=V.fixture("p2p_redesigned").factory()
    original=V.fixture("p2p_original").factory()
    @test length(redesigned.elements)==10
    @test length(original.elements)==8
    @test redesigned.elements[:ugc].element_model.length==25e3
    @test redesigned.elements[:ohl].element_model.length==75e3
    for id in V.SYSTEM_PORT_IDS
        @test all(e.element_model.transposition==:none for e in values(V.fixture(id).factory().elements)
            if e.element_model isa Overhead_line)
    end
    for name in (:c1,:c2)
        m=redesigned.elements[name].element_model
        @test m.elec.turnsRatio==333/380
        @test m.elec.Rₑ*m.elec.zAC_base-m.elec.Rₐᵣₘ*(640^2/1000)/2 ≈ 1.10889
        @test m.modulation.delay1.timeDelay==25e-6
        @test m.delta_control.occ.pi_ctrl==PIControl(Kp=.25,Ki=100.)
        @test m.delta_control.occ.activate_ω_c_multiplication
        @test m.delta_control.occ.filter.order==2
        @test m.delta_control.occ.filter.ωc==2π*500
        @test original.elements[name].element_model.modulation.delay1.timeDelay==200e-6
    end
end

@testset "System transfer matrices use native incidence and units" begin
    for id in ("p2p_redesigned","p2p_ac_grids")
        net=V.fixture(id).factory();point=power_flow(net)
        c=V.complete_system(id,net);list=V.fixture_netlist(net,point)
        spec=merge(V.system_spec(id,list),(;frequencies=[7.,137.],phases=[0.,0.]))
        @test length(c.ports)==2
        @test length(c.nodes)>4
        @test all(n ∉ c.nodes for n in values(net.elements[:g1].pins))
        refs=V.composed_reference(c,spec)
        @test size(refs["direct_Z"])==(4,4,2)
        @test all(haskey(refs,"Z_p$(p)_p$q") for p in 1:2 for q in 1:2)
        @test all(haskey(refs,"AC_I_"*string(n)) && haskey(refs,"DC_I_"*string(n)) for n in c.devices)
        # Independent native network assembly, followed by explicit current drive.
        names=Symbol[n for (n,e) in net.elements if !(e.element_model isa PowerImpedance.Source)]
        dictionary=Dict{Symbol,Array{Union{Symbol,Int}}}(:node_list=>Union{Symbol,Int}[c.nodes...],:element_list=>Union{Symbol,Int}[names...])
        for (k,f) in enumerate(spec.frequencies)
            y=PowerImpedance.make_y(net,dictionary,ComplexF64(2π*im*f))
            for (node,resistance) in c.dc_references
                j=only(findall(==(node),c.nodes));y[j,j]+=inv(resistance)
            end
            drive=zeros(ComplexF64,length(c.nodes),4);drive[1:4,:]=I(4)
            voltage=y\drive
            @test refs["direct_Z"][:,:,k] ≈ voltage[1:4,:] rtol=1e-9
            for p in 1:2, q in 1:2
                @test refs["Z_p$(p)_p$q"][:,:,k] ≈ voltage[2p-1:2p,:] rtol=1e-9
                @test V.composed_score_columns(c,"Z_p$(p)_p$q",spec)==collect(2q-1:2q)
            end
            for name in c.devices
                e=net.elements[name]
                pins=[e.pins[Symbol("1.1")],e.pins[Symbol("2.1")],e.pins[Symbol("2.2")]]
                local_voltage=zeros(ComplexF64,3,4)
                for (row,node) in enumerate(pins)
                    j=findfirst(==(node),c.nodes);j===nothing || (local_voltage[row,:]=voltage[j,:])
                end
                current=PowerImpedance.get_y(e,ComplexF64(2π*im*f))*local_voltage
                @test refs["AC_I_"*string(name)][:,:,k] ≈ current[2:3,:] rtol=1e-9
                @test refs["DC_I_"*string(name)][:,:,k] ≈ current[1:1,:] rtol=1e-9
            end
        end
        for target in keys(refs)
            @test length(V.composed_target_spec(spec,c,target).response_output_bases)==size(refs[target],1)
        end
        if id=="p2p_ac_grids"
            discrete=V.composed_reference(c,spec;time_step=spec.time_step)
            @test norm(discrete["direct_Z"]-refs["direct_Z"])>1e-9
        end
        # The measurement graph retains intermediate DC buses and both winding
        # currents, as well as converter terminals away from the injection ports.
        plan,_=V.scan_plan(list,merge(spec,(;recorder_scope="measurement")),"baseline")
        time=collect(0.:.0001:.002)
        channels=Dict{String,Vector{Float64}}()
        for (index,probe) in enumerate(plan.probes.channels)
            for component in 1:probe.dim
                key=probe.dim==1 ? probe.name : probe.name*":"*string(component)
                channels[key]=fill(Float64(index+component),length(time))
            end
        end
        sampled=V.composed_samples((;time,channels),(;netlist=list,probes=plan.probes),spec,c)
        @test Set(keys(sampled.outputs))==Set(keys(refs))
        @test all(size(sampled.outputs[target],2)==size(refs[target],1) for target in keys(refs))
        for name in c.devices
            element=net.elements[name];
            b=V.device_bases(element.element_model.elec)
            bus=V.port_probe(list, name, b.ac_side).name
            vp=only(filter(p->p.kind==:voltage && p.bus==bus, plan.probes.channels))
            ip=only(filter(p->p.kind==:current && p.element==string(name) && p.port==
                :ac, plan.probes.channels))
            v0=element.setpoint.Vac*cis(element.setpoint.θac)
            i0=-2complex(element.setpoint.Pac,-element.setpoint.Qac)/(3conj(v0))
            for (probe,value) in ((vp,v0),(ip,(ip.orientation==:out ? -1 : 1)*i0))
                for (j,phase) in enumerate((0.,-2π/3,2π/3))
                    channels[probe.name*":"*string(j)]=real.(value.*cis.(2π*50 .*time .+phase))
                end
            end
        end
        carriers=V.system_growth_channels((;time,channels),(;netlist=list,probes=plan.probes),c)
        @test length(carriers.reference)==2length(c.devices)
        # Power-flow summaries and nonlinear solved currents have different
        # numerical residuals. Compare on the existing physical scale.
        @test V.system_growth_quality(time,carriers,spec)["passed"]
        mktempdir() do directory
            V.composed_reference_files!(nothing,c,spec,directory,Dict{Symbol,P.RLCForm}())
            stored=V.composed_frozen_references(directory,spec,c,"plain")
            for (k,f) in enumerate(spec.frequencies)
                theta=2π*50*spec.time_step
                transport=exp(im*2π*f*spec.time_step).*[cos(theta) sin(theta) 0 0;
                    -sin(theta) cos(theta) 0 0;0 0 cos(theta) sin(theta);0 0 -sin(theta) cos(theta)]
                @test stored["direct_Z"][:,:,k] ≈ refs["direct_Z"][:,:,k]*transport rtol=1e-12
            end
        end
        @test V.check_recorder_sampling(spec)==25
        @test V.composed_step_spec(spec,137.).window_starts==(16.,24.)
    end
end

module SystemPreparation
using ..PSCADValidation: ROOT,REPOSITORY,source_record,SYSTEM_PORT_IDS
const head=let paths=[source["path"] for source in source_record()]
    append!(paths,["test/manual/pscad/run_system_screens.jl","test/manual/pscad/validation/README.md",
        "test/manual/pscad/validation/system_model_translation.md","test/pscad/system_factories_test.jl",
        "test/pscad/system_test.jl","test/pscad/growth_test.jl","test/pscad/validation_test.jl",
        "test/pscad/manual_scripts_test.jl","test/pscad/dc_precharge_test.jl","Project.toml"])
    Dict(path=>Base.read(joinpath(REPOSITORY,path)) for path in unique(paths))
end
read(command::Cmd)=copy(head[replace(last(command.exec),"HEAD:"=>"")])
read(command::Base.CmdRedirect)=read(command.cmd)
read(path::String)=Base.read(path)
# Use the actual functions with a simulated HEAD so local edits and station
# settings cannot change which source checks pass or fail.
for expression in Meta.parseall(Base.read(joinpath(ROOT,"systems.jl"),String)).args
    expression isa Expr && expression.head==:function || continue
    name=first(expression.args).args[1]
    name in (:require_committed_systems,:system_selection,:prepare_systems) && Core.eval(@__MODULE__,expression)
end
end

@testset "System preparation checks sources and timeout before writing" begin
    @test all(V.native_node_limit(id)==100 for id in ("passive_ac_rlc","tlc_pq_freq_support","two_mmc_dc_cable"))
    @test all(V.native_node_limit(id)==200 for id in V.SYSTEM_PORT_IDS)
    @test_throws ArgumentError V.prepare_systems(["unknown_system"])
    @test_throws ArgumentError V.prepare_systems(["p2p_redesigned","p2p_redesigned"])
    @test_throws ArgumentError V.run_systems(timeout=NaN)
    @test_throws ArgumentError V.run_systems(timeout=0.)
    @test SystemPreparation.require_committed_systems()===nothing
    mktempdir() do root
        destination=joinpath(root,"unwritten")
        for path in keys(SystemPreparation.head)
            original=SystemPreparation.head[path]
            SystemPreparation.head[path]=[original;0x00]
            try
                @test_throws r"HEAD to contain" SystemPreparation.require_committed_systems()
                @test_throws r"HEAD to contain" SystemPreparation.prepare_systems(["p2p_redesigned"];directory=destination)
                @test !ispath(destination)
            finally
                SystemPreparation.head[path]=original
            end
            @test SystemPreparation.require_committed_systems()===nothing
        end
    end
end

@testset "Original P2P opposite circular roots" begin
    net=V.fixture("p2p_original").factory();power_flow(net)
    c=V.complete_system("p2p_original",net);functions=V.composed_device_functions(c)
    modes=V.system_growth_reference(c)
    @test length(modes)==2
    @test sign.(imag.([m.signed_root for m in modes]))==[1.,-1.]
    # Independent starting values from the original analytical study exercise
    # both branches; a single Newton basin must not hide the faster mode.
    for seed in (1374.3591140382964+21542.016858405703im,1426.120848505274+22158.007650239444im)
        root,residual=V.composed_refine_root(c,functions,seed)
        @test residual<1e-6
        @test any(isapprox(m.root,root;rtol=1e-8) for m in modes)
    end
end
