module PSCADOrientationTests
using Test, PowerImpedance
using ..PSCADFixtures
using ..PSCADFixtures: small_ac_network, passive_ohl_network, dc_network, dc_cable_network, transformer_network, sm_network
using ..PSCADValidationTests: V, phase_wave
const P=PowerImpedance.PSCAD

@testset "Probe orientation metadata and AC cable connection" begin
    fixtures = [
        (small_ac_network().classic, Dict("I_source_1"=>:out, "I_line_1"=>:into, "I_line_2"=>:out, "I_load_1"=>:into)),
        (passive_ohl_network().classic, Dict("I_line_1"=>:into, "I_line_2"=>:out)),
        (dc_network().classic, Dict("I_from_1"=>:into, "I_to_1"=>:into, "I_line_1"=>:into, "I_line_2"=>:out)),
        (dc_cable_network().classic, Dict("I_line_1"=>:into, "I_line_2"=>:out)),
        (V.fixture("L1-05").factory(), Dict("I_line_1"=>:into, "I_line_2"=>:out, "I_ohl_1"=>:into, "I_ohl_2"=>:out)),
        (transformer_network().classic, Dict("I_line_1"=>:into,"I_line_2"=>:out)),
        (transformer_network(;organization=:ΔY).classic, Dict("I_line_1"=>:into,"I_line_2"=>:out)),
        (sm_network().classic, Dict("I_sg1_1"=>:out,"I_g2_1"=>:out)),
        (PSCADFixtures.tlc_case1_network().classic, Dict("I_DUT_1"=>:into,"I_DUT_2"=>:out)),
        (PSCADFixtures.mmc_pq_network().classic, Dict("I_DUT_1"=>:into,"I_DUT_2"=>:out))]
    for (net, expected) in fixtures
        # Active emitter initialization needs the solved point; passive network
        # fixtures otherwise use the same retained operating-point contract.
        list=P.netlist(net, power_flow(net))
        plan=P.build_plan(list)
        for (name, direction) in expected
            @test only(filter(c->c.name==name,plan.probes.channels)).orientation==direction
        end
        @test all(c.kind==:current ? c.orientation in (:into,:out) : c.orientation===nothing
                  for c in plan.probes.channels)
        stored=V.recorded_probes(V.probe_record.(plan.probes.channels),plan.probes.reference_bus)
        @test repr(stored)==repr(plan.probes)
    end
    @test_throws ArgumentError P.ProbeChannel("I",:current,"B","line","1",3,"kA")
    @test_throws ArgumentError P.ProbeChannel("I",:current,"B","line","1",3,"kA",:unknown)
    @test_throws ArgumentError P.ProbeChannel("V",:voltage,"B",nothing,nothing,3,"kV",:into)
    net=V.fixture("L1-04").factory()
    list=P.netlist(net, power_flow(net))
    spec,_=V.scan_definition("L1-04",net,list)
    plan,settings=V.scan_plan(list,spec,"baseline")
    meter=only(filter(c->c isa P.ComponentPlan && c.defn=="master:ammeter" &&
                         Dict(c.params)["Name"]=="I_line_2",plan.main.components))
    label(point)=Dict(only(filter(c->c isa P.ComponentPlan && c.defn=="master:nodelabel" &&
                                    (c.x,c.y)==point,plan.main.components)).params)["Name"]
    @test meter.orient==0
    @test label((meter.x-36,meter.y))=="I_line_2_node"
    @test label((meter.x+36,meter.y-36))==spec.buses[2].name
    @test P.check_connectivity(plan)===nothing
    @test only(filter(c->c.name=="I_line_2",plan.probes.channels)).orientation==:out

    # The same physical inward currents must be recovered from old both-inward
    # cable records and the new branch-direction records. Current emitter
    # metadata must never be substituted for the historical project metadata.
    times=[0.0,0.01,0.02]; logical=[1.0,2.0,3.0,4.0]
    for historical in (false,true)
        records=V.probe_record.(plan.probes.channels)
        for c in records
            c["name"]=="I_line_2" && historical && (c["orientation"]="into")
        end
        probes=V.recorded_probes(records,plan.probes.reference_bus)
        channels=PowerImpedance.OrderedDict{String,Vector{Float64}}()
        for (port,bus) in enumerate(spec.buses)
            v=only(filter(c->c.kind==:voltage && c.bus==bus.name,probes.channels))
            i=only(filter(c->c.name=="I_line_$port",probes.channels))
            indices=(2port-1):2port
            vabc=phase_wave(times,zeros(3,2))
            iabc=phase_wave(times,repeat(((i.orientation==:into ? 1 : -1).*logical[indices])',3,1))
            for phase in 1:3
                channels[v.name*":"*string(phase)]=vabc[:,phase]
                channels[i.name*":"*string(phase)]=iabc[:,phase]
            end
        end
        model=P.PSCADModel("stored.pscx","stored",list,probes,settings,list.operating_point,(;))
        result=P.PSCADResult(PSCADRun(),times,channels,probes,settings,(;),(;))
        @test V.scan_samples(result,model,spec).current ≈ repeat(logical',3,1) atol=1e-14
    end
    A=reshape(ComplexF64[1+im,2-im,3,4im],4,1,1); B=A.*1.003
    D=reshape([1.0,1.0,-1.0,-1.0],4,1,1)
    @test V.matrix_change(A,B;epsilon=.01)==V.matrix_change(D.*A,D.*B;epsilon=.01)

    # Metadata addition must not reinterpret the signed acceptance equations.
    for (network, element, side) in ((sm_network().classic, "sg1", "1"),
        (PSCADFixtures.tlc_case2_network().classic, "DUT", "2"),
        (PSCADFixtures.mmc_pq_network().classic, "DUT", "2"))
        nl=P.netlist(network,power_flow(network)); pl=P.build_plan(nl)
        c=only(filter(p->p.kind==:current && p.element==element && p.side==side,pl.probes.channels))
        v=only(filter(p->p.kind==:voltage && p.bus==c.bus,pl.probes.channels))
        times=collect(0.0:250e-6:0.3)
        channels=PowerImpedance.OrderedDict{String,Vector{Float64}}()
        for (probe,signal) in ((v, [10.0,2.0]),(c,[1.0,-0.3]))
            abc=phase_wave(times,repeat(signal',length(times),1))
            for phase in 1:3
                channels[probe.name*":"*string(phase)]=abc[:,phase]
            end
        end
        tables=[]
        for direction in (:into,:out)
            current=P.ProbeChannel(c.name,c.kind,c.bus,c.element,c.side,c.dim,c.unit,direction)
            pm=P.ProbeManifest([v,current],v.bus)
            m=P.PSCADModel("signed.pscx","signed",nl,pm,P.SimulationSettings(),nl.operating_point,(;))
            r=P.PSCADResult(PSCADRun(),times,channels,pm,m.settings,(;),(;))
            push!(tables,collect(compare_operating_point(r,m)))
        end
        @test tables[1]==tables[2]
        @test count(r->r.quantity in (:machine_p,:machine_q,:converter_p,:converter_q),tables[1])==2
    end
end
end
