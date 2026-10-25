# Included inside PSCADSystemValidationTests, which defines V and imports the test APIs.
@testset "Frozen system factories and offline power flow" begin
    @test V.SYSTEM_PORT_IDS == ["p2p_redesigned","ieee14","p2p_ac_grids","p2p_original","p2p_ac_single_line"]
    @test V.fixture("p2p_ac_single_line").measurements == ["growth"]
    @test_throws ArgumentError V.fixture("unknown_system")
    ieee=V.system_ieee14_network()
    @test sort!([n for n in keys(ieee.elements) if startswith(string(n),"Load")]) ==
        [:LoadB2,:LoadB3,:LoadB4,:LoadB5,:LoadB6]
    first_mmc=ieee.elements[:MMC1]
    @test PowerImpedance.powerflow_targets(first_mmc).p_ac * bases(first_mmc).S == -1000
    @test ieee.elements[:MMC2].modulation.delay1.timeDelay == 250e-6
    for name in (:MMC1,:MMC2,:MMC3,:MMC4)
        m=ieee.elements[name]
        @test !m.delta_control.occ.activate_ω_c_multiplication
        @test ieee.elements[name].limits.Q_max == 500
    end
    for name in (:WF1,:WF2,:WF3)
        m=ieee.elements[name]
        @test m.sync.pi_ctrl.Kp == 0.397887357729738
        @test m.sync.pi_ctrl.Ki == 7.957747154594767
        @test m.innerCurrent.activate_ω_c_multiplication
        @test m.mod isa PowerImpedance.NoModulation
    end
    # Independent source formulas for each active shunt load.
    for (name,p,q) in ((:LoadB2,72.333,42.333),(:LoadB3,314.,63.333),
            (:LoadB4,159.333,-13.),(:LoadB5,25.333,5.333),(:LoadB6,37.333,25.))
        s=ComplexF64(2π*50im)
        actual=V.physical_y(ieee.elements[name],ComplexF64(2π*137im))
        @test all(isfinite,actual)
        r=380^2/(3p)
        reactive=q>0 ? inv(s*380^2/(3q*2π*50)) : s*3abs(q)/(380^2*2π*50)
        expected=inv(inv(r)+reactive)
        @test V.P.identify_rlc(ieee.elements[name]; name).form.topology ==
              :parallel
        # Physical scalar impedance remains independently evaluable.
        @test ieee.elements[name].value(s)[1,1] ≈ expected
    end
    stable=V.system_p2p_ac_network();unstable=V.system_p2p_ac_network(unstable=true)
    @test haskey(stable.elements,:tl67_2)
    @test !haskey(unstable.elements,:tl67_2)
    @test stable.elements[:tl67_2].length == 80e3
    @test stable.elements[:tl67].length == 90e3
    @test Set(keys(stable.elements)) == union(Set(keys(unstable.elements)),Set([:tl67_2]))
    for net in (stable,unstable)
        @test all(PowerImpedance.powerflow_targets(model).v_ac ==
            220sqrt(2) / bases(model).v_ac for model in (net.elements.c1, net.elements.c2))
        c2=net.elements[:c2]
        @test c2.sync.pi_ctrl == PowerImpedance.PIControl(Kp=7,Ki=12.5664)
        @test c2.sigma_control.tec isa PowerImpedance.NoTotalEnergyControl
        @test c2.sigma_control.zscc isa PowerImpedance.NoZeroSequenceCurrentControl
        @test iszero(c2.modulation.delay1.timeDelay)
    end
    fresh=V.system_ieee14_network()
    @test fresh !== ieee && fresh.elements[:MMC1] !== ieee.elements[:MMC1]
    # Full solves, not isolated controller construction, exercise each factory.
    for (id,net) in zip(("ieee14","p2p_ac_grids","p2p_ac_single_line"),(ieee,stable,unstable))
        @testset "$id complete power flow" begin
            point=compute(PowerFlowProblem(net), ACDCPowerFlow())
            result=point.result
            @test string(result["termination_status"])=="LOCALLY_SOLVED" || get(result,"primal_feasible",false)
            list=V.fixture_netlist(net,point)
            @test !isempty(list.operating_point.bus_states)
            @test all(isfinite(point.vm_pu) && (point.va_rad===nothing || isfinite(point.va_rad))
                for point in values(list.operating_point.bus_states))
            if id == "ieee14"
                plan = V.P.build_plan(list)
                for name in (:DC_WF1, :DC_WF2, :DC_WF3)
                    @test inputvalues(net.elements[name]).v == 640
                    @test length(electricalconnections(net.elements[name])) == 1
                    for pole in ("P", "N")
                        source = only(filter(c -> c isa V.P.ComponentPlan &&
                            c.defn == "master:source_1" &&
                            get(Dict(c.params), "Name", "") == string(name, "_", pole),
                            plan.main.components))
                        @test Dict(source.params)["Vm"] == V.P.pscad_value(320.0; unit="kV")
                    end
                end
            end
            @test all(all(isfinite,e.cache.A) for e in values(net.elements) if
                e isa Union{PowerImpedance.MMC,PowerImpedance.TLC})
        end
    end
end
