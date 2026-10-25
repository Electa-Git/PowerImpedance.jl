@testset "TLC current initialization" begin
    P = PowerImpedance
    plant = ElectricalTLC(Sbase = 100.0, vACbase_LL_RMS = 220.0, vDCbase = 640.0)
    conv = tlc(elec = plant,
        meas = Measurement(
            v_ac = P.Butterworth(order = 2, ωc = 0.5e4),
            i_ac = P.Butterworth(order = 2, ωc = 0.5e4)))

    @testset "Nonzero seeds and measurement filters" begin
        cases = (
            (inputs = (v_dc = 1.0, vG_d = 1.0, vG_q = 0.0),
                setpoint = P.TerminalValuesPU(p_ac = 0.7, q_ac = -0.2),
                expected = (0.7, 0.2)),
            (inputs = (v_dc = 1.0, vG_d = 0.8, vG_q = -0.6),
                setpoint = P.TerminalValuesPU(p_ac = -0.35, q_ac = 0.15),
                expected = (-0.37, 0.09))
        )
        for case in cases
            inputs, terminal_pu = case.inputs, case.setpoint
            seed = P.initialvalues(plant; inputs, terminal_pu)
            @test keys(seed) == P.statenames(plant)
            @test collect(values(seed)) ≈ collect(case.expected)
            @test P.orderedinitialvalues(plant; inputs, terminal_pu) == seed

            ordered = P.orderedinitialvalues(conv; inputs, terminal_pu)
            @test keys(ordered) == P.statenames(conv)
            @test ordered.i_d == seed.i_d
            @test ordered.i_q == seed.i_q
            for (measurement, current) in ((conv.meas.i_d, seed.i_d),
                (conv.meas.i_q, seed.i_q))
                states = [getproperty(ordered, name) for name in P.statenames(measurement)]
                filter = measurement.filter
                output = only(filter.C * states + filter.D * [current])
                @test output ≈ current
            end
        end
    end

    @testset "Zero AC voltage" begin
        inputs = (v_dc = 1.0, vG_d = 0.0, vG_q = 0.0)
        terminal_pu = P.TerminalValuesPU(p_ac = 0.7, q_ac = -0.2)
        seed = P.initialvalues(plant; inputs, terminal_pu)
        @test keys(seed) == P.statenames(plant)
        @test seed == (i_d = 0.0, i_q = 0.0)
        @test P.orderedinitialvalues(plant; inputs, terminal_pu) == seed
        ordered = P.orderedinitialvalues(conv; inputs, terminal_pu)
        @test keys(ordered) == P.statenames(conv)
        @test (ordered.i_d, ordered.i_q) == (0.0, 0.0)
        for measurement in (conv.meas.i_d, conv.meas.i_q)
            @test all(iszero(getproperty(ordered, name))
            for name in P.statenames(measurement))
        end
    end
end
