# Frozen ports of Jan Kircheis study circuits retain all source units. Source and
# translation details: system_model_translation.md. These factories do not read or execute the
# source repository.

function system_original_p2p_network(; redesigned=false)
    elements = (;)
    topology = NetworkBuilder.Bus[]
    voltage_base = 380/sqrt(3)
    for name in (:g1,:g4)
        elements = merge(elements, (; name => ac_source(v = 380sqrt(2/3), p = 100)))
    end
    for (name,active,arm_l) in ((:c1,true,.05),(:c2,false,.03))
        referred=redesigned || name==:c2
        elec=PowerImpedance.ElectricalMMC(Lₐᵣₘ = arm_l, Rₐᵣₘ = 1.07, Cₐᵣₘ = .01, N = 400,
            turnsRatio = referred ? 333/380 : 1., Lᵣ = referred ? .0461 : .06,
            Rᵣ = redesigned ? 1.10889 : referred ? .4103 : .535)
        outer=active ? PowerImpedance.OuterActiveVdcControl(pi_ctrl=PIControl(Kp=redesigned ? 3. : 6.,Ki=redesigned ? 7.5 : 15.)) :
            PowerImpedance.OuterActivePowerControl(pi_ctrl=PIControl(Kp=redesigned ? .05 : .1,Ki=redesigned ? 15.70795 : 31.4159))
        delta=PowerImpedance.ΔdqControlGFL(outer_active=outer,
            outer_reactive=PowerImpedance.OuterReactiveQControl(pi_ctrl=PIControl(Kp=redesigned ? .05 : .1,Ki=redesigned ? 15.70795 : 31.4159)),
            occ=PowerImpedance.InnerCurrentPIControl(pi_ctrl=PIControl(Kp=redesigned ? .25 : .7691,Ki=redesigned ? 100. : 522.7654),
                filter=redesigned ? PowerImpedance.Butterworth(order=2,ωc=2π*500) : PowerImpedance.NoFilter(),
                activate_ω_c_multiplication=redesigned))
        sigma=PowerImpedance.ΣdqzControlTEC(ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(pi_control=PIControl(Kp=.1048,Ki=48.1914)))
        elements = merge(elements, (; name => let model = mmc(;
                vACbase_LL_RMS = referred ? 333 : 380, Sbase = 1000, vDC_base = 640, elec,
                delta_control = delta, sigma_control = sigma,
                sync = PowerImpedance.PLLSynchronization(pi_ctrl=PIControl(
                        Kp=redesigned ? .14 : .28, Ki=redesigned ? 3.1416 : 12.5664),
                    filter=redesigned ? PowerImpedance.Butterworth(order=1,
                        ωc=2π*40) : PowerImpedance.NoFilter()),
                meas = PowerImpedance.Measurement(
                    v_ac=redesigned ? PowerImpedance.Butterworth(order=1,
                        ωc=2π*2000) : PowerImpedance.NoFilter()),
                modulation = PowerImpedance.UncompensatedModulation(
                    timeDelay=redesigned ? 25e-6 : 200e-6, padeOrderNum=5, padeOrderDen=5),
                limits = PowerImpedance.Limits(P_min=active ? -1500 : -1000,
                    P_max=active ? 1500 : 1000,
                    Q_min=active ? -500 : -1000, Q_max=active ? 500 : 1000))
            b = bases(model)
            active_inputs = active ? (; v_dc_ref = 640 / b.v_dc) :
                (; p_ref = 100 / b.S)
            active_seeds = active ? (; p_ac = -100 / b.S) : (; v_dc = 640 / b.v_dc)
            component(model; delta_control = (; outer_active = active_inputs,
                    outer_reactive = (; q_ref = 100 / b.S)),
                powerflow = (; active_seeds..., v_ac = 380sqrt(2/3) / b.v_ac,
                    p_dc = 100 / b.S))
        end))
    end
    elements = merge(elements, (; ugc = cable(length=25e3,positions=[(-.5,1.),(.5,1.)],
        C1=Conductor(rₒ=.02622,ρ=2.354e-8,μᵣ=1.035),
        I1=Insulator(rᵢ=.02622,rₒ=.06006,ϵᵣ=2.67,μᵣ=1.469),
        C2=Conductor(rᵢ=.06006,rₒ=.06336,ρ=2.14e-7,μᵣ=1.),
        I2=Insulator(rᵢ=.06336,rₒ=.06636,ϵᵣ=2.3,μᵣ=1.),
        C3=Conductor(rᵢ=.06636,rₒ=.06651,ρ=2.826e-8,μᵣ=1.),
        I3=Insulator(rᵢ=.06651,rₒ=.07256,ϵᵣ=2.3,μᵣ=1.),
        earth_parameters=(1,1,100))))
    elements = merge(elements, (; ohl = overhead_line(length=75e3,
        conductors=Conductors(organization=:flat,nᵇ=2,nˢᵇ=1,Rᵈᶜ=.0266,rᶜ=.0224,
            yᵇᶜ=18.,Δyᵇᶜ=0.,Δxᵇᶜ=7.3,Δ̃xᵇᶜ=0.,dˢᵇ=0.,dˢᵃᵍ=6.),
        groundwires=Groundwires(nᵍ=2,Rᵍᵈᶜ=.92,rᵍ=.0062,Δxᵍ=7.3,Δyᵍ=7.,dᵍˢᵃᵍ=6.),
        earth_parameters=(1,1,100))))
    elements = merge(elements, (; tl1 = system_study_ohl(25e3)));
        elements = merge(elements, (; tl78 = system_study_ohl(90e3)))
    for (name, port, bus) in ((:c1, :ac, :B3), (:tl1, :side2, :B3),
            (:tl1, :side1, :B2), (:g4, :ac, redesigned ? :G4 : :B2),
            (:c2, :ac, :B6), (:tl78, :side1, :B6), (:tl78, :side2, :B7),
            (:g1, :ac, redesigned ? :G1 : :B7))
        push!(topology, NetworkBuilder.Bus(bus; ports = ((name, port),), domain = ACDQ))
    end
    for (name, port, bus) in ((:c1, :dc, :B4), (:ugc, :side1, :B4),
            (:ugc, :side2, :BX), (:ohl, :side1, :BX), (:ohl, :side2, :B5),
            (:c2, :dc, :B5))
        push!(topology, NetworkBuilder.Bus(bus; ports = ((name, port),)))
    end
    for (source,bus,grid) in ((:G4,:B2,:Z_g4),(:G1,:B7,:Z_g1))
        if redesigned
            r=380^2/1000/8/sqrt(101);l=10r/(100π)
            elements = merge(elements, (; grid => impedance(z=s->r+l*s,conductors =3)))
            push!(topology, NetworkBuilder.Bus(source;
                ports = ((grid, :side1),), domain = ACDQ))
            push!(topology, NetworkBuilder.Bus(bus;
                ports = ((grid, :side2),), domain = ACDQ))
        end
    end
    return NetworkBuilder.define(elements, topology;
        options = (; voltageBase = voltage_base))
end

function system_ieee14_network()
    P_MMC1=-1000
    Q_MMC1= 0
    P_MMC2=-1000
    Q_MMC2=0
    Q_MMC3=0.0
    Q_MMC4=0.0
    R_B2=system_shunt_parameter(72.333,380,"R")
    L_B2=system_shunt_parameter(42.333,380,"L")
    R_B5=system_shunt_parameter(25.333,380,"R")
    L_B5=system_shunt_parameter(05.333,380,"L")
    R_B3=system_shunt_parameter(314,380,"R")
    L_B3=system_shunt_parameter(63.333,380,"L")
    R_B4=system_shunt_parameter(159.333,380,"R")
    C_B4=system_shunt_parameter(13.000,380,"C")
    R_B6=system_shunt_parameter(37.333,380,"R")
    L_B6=system_shunt_parameter(25.0,380,"L")
    Vm=380/sqrt(3)
    elements = (;)
    topology = NetworkBuilder.Bus[]
    voltage_base = Vm
    elements = merge(elements, (; G1 = ac_source(v = Vm*sqrt(2))))
    elements = merge(elements, (; G2 = ac_source(v = Vm*sqrt(2))))
    elements = merge(elements, (; DC_WF1 = dc_source(v = 640)))
    elements = merge(elements, (; DC_WF2 = dc_source(v = 640)))
    elements = merge(elements, (; DC_WF3 = dc_source(v = 640)))
    elements = merge(elements, (; Zg1 = impedance(z=s->0.2874  + 0.0091*s, conductors = 3)))
    elements = merge(elements, (; Zg2 = impedance(z=s->1.026 + 1*0.0327*s, conductors = 3)))
    elements = merge(elements, (; MMC1 = let model = mmc(
            vACbase_LL_RMS = 333, Sbase = 1000, vDC_base = 640,
            elec = PowerImpedance.ElectricalMMC(Lₐᵣₘ = 46.125e-3, Rₐᵣₘ = 0.4,
                Cₐᵣₘ = 11.3867e-3,
                N = 400, Lᵣ = 0.18 * (333^2/1000) /2/pi/50, Rᵣ = 0.001 *(333^2/1000),
                turnsRatio = 333/380),
            meas = PowerImpedance.Measurement(
                P_ac=PowerImpedance.Butterworth(order=2, ωc=140*2*pi),
                Q_ac=PowerImpedance.Butterworth(order=2, ωc=140*2*pi)
            ),
            sync = PowerImpedance.VSEWithDamping(
                H=5,
                K_d=100,
                K_ω=10,
                ω_ref=1,
                pll=PowerImpedance.PLLSynchronization(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                    filter=PowerImpedance.Butterworth(order=1, ωc=75*2*pi)
                )
            ),
            delta_control = PowerImpedance.ΔdqControlGFM(
                outer_reactive=PowerImpedance.OuterReactiveQControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.0, Ki=3),
                    support=PowerImpedance.NoVoltageSupport()
                ),
                vi=PowerImpedance.CCVI(
                    R_v=0.01,
                    L_v=0.25,
                    V_d_ref=1,
                    V_q_ref=0,
                    filter=PowerImpedance.Butterworth(order=2, ωc=200)
                ),
                occ=PowerImpedance.InnerCurrentPIControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.6532, Ki=281.1370),
                    filter=PowerImpedance.Butterworth(order=2, ωc=200*2*pi),
                    activate_ω_c_multiplication=false
                )
            ),
            sigma_control = PowerImpedance.ΣdqzControlTEC(
                tec=PowerImpedance.TotalEnergyControl(
                    pi_control=PowerImpedance.PIControl(Kp=1.469, Ki=31.4819),
                    power_filter=PowerImpedance.Butterworth(order=2, ωc=140*2*pi)
                ),
                zscc=PowerImpedance.ZeroSequenceCurrentControl(
                    PowerImpedance.PIControl(Kp=0.0936, Ki=40.5396)
                ),
                ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(
                    PowerImpedance.PIControl(Kp=0.0936, Ki=40.5396)
                )
            ),
            modulation = PowerImpedance.UncompensatedModulation(
                timeDelay=200e-6,
                padeOrderNum=5,
                padeOrderDen=5
            ),
            limits = PowerImpedance.Limits(P_min=-1500, P_max=1500, Q_min=-500, Q_max=500))
            b = bases(model)
            component(model; sync = (; p_ref = (P_MMC1) / b.S),
                delta_control = (; outer_reactive = (; q_ref = (Q_MMC1) / b.S)),
                powerflow = (; v_ac = ((Vm)*sqrt(2)) / b.v_ac,
                    v_dc = (640) / b.v_dc, p_dc = (100.) / b.S))
        end))
    elements = merge(elements, (; MMC2 = let model = mmc(
            vACbase_LL_RMS = 333, Sbase = 1000, vDC_base = 640,
            elec = PowerImpedance.ElectricalMMC(Lₐᵣₘ = 46.125e-3, Rₐᵣₘ = 0.4,
                Cₐᵣₘ = 11.3867e-3,
                N = 400, Lᵣ = 0.18 * (333^2/1000) /2/pi/50, Rᵣ = 0.001 *(333^2/1000),
                turnsRatio = 333/380),
            meas = PowerImpedance.Measurement(
                P_ac=PowerImpedance.Butterworth(order=2, ωc=140*2*pi),
                Q_ac=PowerImpedance.Butterworth(order=2, ωc=140*2*pi)
            ),
            sync = PowerImpedance.VSEWithDamping(
                H=5,
                K_d=100,
                K_ω=10,
                ω_ref=1,
                pll=PowerImpedance.PLLSynchronization(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                    filter=PowerImpedance.Butterworth(order=1, ωc=75*2*pi)
                )
            ),
            delta_control = PowerImpedance.ΔdqControlGFM(
                outer_reactive=PowerImpedance.OuterReactiveQControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.0, Ki=3),
                    support=PowerImpedance.NoVoltageSupport()
                ),
                vi=PowerImpedance.CCVI(
                    R_v=0.0,
                    L_v=0.4,
                    V_d_ref=1,
                    V_q_ref=0,
                    filter=PowerImpedance.Butterworth(order=2, ωc=200)
                ),
                occ=PowerImpedance.InnerCurrentPIControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.6532, Ki=281.1370),
                    filter=PowerImpedance.Butterworth(order=2, ωc=400*2*pi),
                    activate_ω_c_multiplication=false
                )
            ),
            sigma_control = PowerImpedance.ΣdqzControlTEC(
                tec=PowerImpedance.TotalEnergyControl(
                    pi_control=PowerImpedance.PIControl(Kp=1.469, Ki=31.4819),
                    power_filter=PowerImpedance.Butterworth(order=2, ωc=140*2*pi)
                ),
                zscc=PowerImpedance.ZeroSequenceCurrentControl(
                    PowerImpedance.PIControl(Kp=0.0936, Ki=40.5396)
                ),
                ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(
                    PowerImpedance.PIControl(Kp=0.0936, Ki=40.5396)
                )
            ),
            modulation = PowerImpedance.UncompensatedModulation(
                timeDelay=250e-6,
                padeOrderNum=5,
                padeOrderDen=5
            ),
            limits = PowerImpedance.Limits(P_min=-1500, P_max=1500, Q_min=-500, Q_max=500))
            b = bases(model)
            component(model; sync = (; p_ref = (P_MMC2) / b.S),
                delta_control = (; outer_reactive = (; q_ref = (Q_MMC2) / b.S)),
                powerflow = (; v_ac = ((Vm)*sqrt(2)) / b.v_ac,
                    v_dc = (640) / b.v_dc, p_dc = (100.) / b.S))
        end))
    elements = merge(elements, (; MMC3 = let model = mmc(
            vACbase_LL_RMS = 333, Sbase = 1000, vDC_base = 640,
            elec = PowerImpedance.ElectricalMMC(Lₐᵣₘ = 50e-3, Rₐᵣₘ = 1.07, Cₐᵣₘ = 10e-3,
                N = 400, Lᵣ = 0.1305*(333^2/1000)/2/pi/50, Rᵣ = 0.0037*(333^2/1000),
                turnsRatio = 333/380), meas = PowerImpedance.Measurement(),
            sync = PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                filter=PowerImpedance.NoFilter()
            ),
            delta_control = PowerImpedance.ΔdqControlGFL(
                outer_active=PowerImpedance.OuterActiveVdcControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=5, Ki=15),
                    filter=PowerImpedance.NoFilter()
                ),
                outer_reactive=PowerImpedance.OuterReactiveQControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.1, Ki=31.4159),
                    support=PowerImpedance.NoVoltageSupport()
                ),
                occ=PowerImpedance.InnerCurrentPIControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.7691, Ki=522.7654),
                    filter=PowerImpedance.NoFilter(),
                    activate_ω_c_multiplication=false
                )
            ),
            sigma_control = PowerImpedance.ΣdqzControlTEC(
                tec=PowerImpedance.TotalEnergyControl(
                    pi_control=PowerImpedance.PIControl(Kp=1.2894, Ki=27.63),
                    power_filter=PowerImpedance.NoFilter()
                ),
                zscc=PowerImpedance.ZeroSequenceCurrentControl(
                    PowerImpedance.PIControl(Kp=0.0992, Ki=42.9719)
                ),
                ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(
                    PowerImpedance.PIControl(Kp=0.1048, Ki=48.1914)
                )
            ),
            modulation = PowerImpedance.UncompensatedModulation(
                timeDelay=200e-6,
                padeOrderNum=5,
                padeOrderDen=5
            ),
            limits = PowerImpedance.Limits(P_min=-1500, P_max=1500, Q_min=-500, Q_max=500))
            b = bases(model)
            component(model; delta_control = (; outer_active = (; v_dc_ref =
                (640) / b.v_dc),
                    outer_reactive = (; q_ref = (Q_MMC3) / b.S)),
                powerflow = (; p_ac = (-10.) / b.S, v_ac = ((Vm)*sqrt(2)) / b.v_ac,
                    p_dc = (100.) / b.S))
        end))
    elements = merge(elements, (; MMC4 = let model = mmc(
            vACbase_LL_RMS = 333, Sbase = 1000, vDC_base = 640,
            elec = PowerImpedance.ElectricalMMC(Lₐᵣₘ = 50e-3, Rₐᵣₘ = 1.07, Cₐᵣₘ = 10e-3,
                N = 400, Lᵣ = 0.1305*(333^2/1000)/2/pi/50, Rᵣ = 0.0037*(333^2/1000),
                turnsRatio = 333/380), meas = PowerImpedance.Measurement(),
            sync = PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                filter=PowerImpedance.NoFilter()
            ),
            delta_control = PowerImpedance.ΔdqControlGFL(
                outer_active=PowerImpedance.OuterActiveVdcControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=5, Ki=15),
                    filter=PowerImpedance.NoFilter()
                ),
                outer_reactive=PowerImpedance.OuterReactiveQControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.1, Ki=31.4159),
                    support=PowerImpedance.NoVoltageSupport()
                ),
                occ=PowerImpedance.InnerCurrentPIControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.7691, Ki=522.7654),
                    filter=PowerImpedance.NoFilter(),
                    activate_ω_c_multiplication=false
                )
            ),
            sigma_control = PowerImpedance.ΣdqzControlTEC(
                tec=PowerImpedance.TotalEnergyControl(
                    pi_control=PowerImpedance.PIControl(Kp=1.2894, Ki=27.63),
                    power_filter=PowerImpedance.NoFilter()
                ),
                zscc=PowerImpedance.ZeroSequenceCurrentControl(
                    PowerImpedance.PIControl(Kp=0.0992, Ki=42.9719)
                ),
                ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(
                    PowerImpedance.PIControl(Kp=0.1048, Ki=48.1914)
                )
            ),
            modulation = PowerImpedance.UncompensatedModulation(
                timeDelay=200e-6,
                padeOrderNum=5,
                padeOrderDen=5
            ),
            limits = PowerImpedance.Limits(P_min=-1500, P_max=1500, Q_min=-500, Q_max=500))
            b = bases(model)
            component(model; delta_control = (; outer_active = (; v_dc_ref =
                (640) / b.v_dc),
                    outer_reactive = (; q_ref = (Q_MMC4) / b.S)),
                powerflow = (; p_ac = (-10.) / b.S, v_ac = ((Vm)*sqrt(2)) / b.v_ac,
                    p_dc = (100.) / b.S))
        end))
    elements = merge(elements, (; WF1 = system_windfarm()))
    elements = merge(elements, (; WF2 = system_windfarm()))
    elements = merge(elements, (; WF3 = system_windfarm()))
    elements = merge(elements, (; T1_2 = system_study_ohl(100e3)))
    elements = merge(elements, (; T1_5 = system_study_ohl(100e3)))
    elements = merge(elements, (; T2_5 = system_study_ohl(100e3)))
    elements = merge(elements, (; T4_5 = system_study_ohl(100e3)))
    elements = merge(elements, (; T2_4 = system_study_ohl(100e3)))
    elements = merge(elements, (; T2_3 = system_study_ohl(100e3)))
    elements = merge(elements, (; T3_4 = system_study_ohl(100e3)))
    elements = merge(elements, (; T12_13 = system_study_ohl(100e3)))
    elements = merge(elements, (; T6_12 = system_study_ohl(100e3)))
    elements = merge(elements, (; T6_13 = system_study_ohl(20e3)))
    elements = merge(elements, (; T6_11 = system_study_ohl(5e3)))
    elements = merge(elements, (; T10_11 = system_study_ohl(5e3)))
    elements = merge(elements, (; T13_14 = system_study_ohl(20e3)))
    elements = merge(elements, (; T9_14 = system_study_ohl(20e3)))
    elements = merge(elements, (; T9_10 = system_study_ohl(5e3)))
    elements = merge(elements, (; T7_9 = system_study_ohl(5e3)))
    elements = merge(elements, (; CableDC23 = cable(
            length = 200e3,
            positions = [(0,1.5), (1,1.5)],
            C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
            I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
            C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
            I2 = Insulator(rᵢ = 55.4e-3, rₒ = 61.2e-3, ϵᵣ = 2.3))))
    elements = merge(elements, (; CableDC23_1 = cable(
            length = 200e3,
            positions = [(0,1.5), (1,1.5)],
            C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
            I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
            C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
            I2 = Insulator(rᵢ = 55.4e-3, rₒ = 61.2e-3, ϵᵣ = 2.3))))
    elements = merge(elements, (; LoadB2 = impedance(z=s->1/((1/R_B2)+(1/(s*L_B2))),
        conductors = 3)))
    elements = merge(elements, (; LoadB5 = impedance(z=s->1/((1/R_B5)+(1/(s*L_B5))),
        conductors = 3)))
    elements = merge(elements, (; LoadB3 = impedance(z=s->1/((1/R_B3)+(1/(s*L_B3))),
        conductors = 3)))
    elements = merge(elements, (; LoadB4 = impedance(z=s->1/((1/R_B4)+(s*C_B4)),
        conductors = 3)))
    elements = merge(elements, (; LoadB6 = impedance(z=s->1/((1/R_B6)+(1/(s*L_B6))),
        conductors = 3)))
    push!(topology, NetworkBuilder.Bus(:gnd; ports = ((:LoadB2, :side2),), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:gnd; ports = ((:LoadB5, :side2),), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:gnd; ports = ((:LoadB3, :side2),), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:gnd; ports = ((:LoadB4, :side2),), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:gnd; ports = ((:LoadB6, :side2),), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Zg1_side1; ports = ((:Zg1, :side1), (:G1, :ac)),
        domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus1; ports = ((:Zg1, :side2), (:T1_2, :side1),
        (:T1_5, :side1)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus2; ports = ((:T2_3, :side1), (:T2_4, :side1),
        (:T2_5, :side1), (:T1_2, :side2), (:LoadB2, :side1)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus3; ports = ((:T2_3, :side2), (:T3_4, :side1),
        (:LoadB3, :side1)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus4; ports = ((:T4_5, :side1), (:T2_4, :side2),
        (:T3_4, :side2), (:LoadB4, :side1), (:MMC4, :ac)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus5; ports = ((:T4_5, :side2), (:T2_5, :side2),
        (:T1_5, :side2), (:LoadB5, :side1), (:MMC3, :ac)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:BusDC1; ports = ((:CableDC23, :side1), (:MMC1,
        :dc))))
    push!(topology, NetworkBuilder.Bus(:BusDC2; ports = ((:CableDC23_1, :side1), (:MMC2,
        :dc))))
    push!(topology, NetworkBuilder.Bus(:BusDC3; ports = ((:CableDC23, :side2), (:MMC3,
        :dc))))
    push!(topology, NetworkBuilder.Bus(:BusDC4; ports = ((:CableDC23_1, :side2), (:MMC4,
        :dc))))
    push!(topology, NetworkBuilder.Bus(:WF1_dc; ports = ((:WF1, :dc), (:DC_WF1, :dc))))
    push!(topology, NetworkBuilder.Bus(:WF2_dc; ports = ((:WF2, :dc), (:DC_WF2, :dc))))
    push!(topology, NetworkBuilder.Bus(:WF3_dc; ports = ((:WF3, :dc), (:DC_WF3, :dc))))
    push!(topology, NetworkBuilder.Bus(:Zg2_side1; ports = ((:Zg2, :side1), (:G2, :ac)),
        domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus6; ports = ((:Zg2, :side2), (:MMC1, :ac),
        (:T6_12, :side1), (:T6_13, :side1), (:T6_11, :side1), (:LoadB6, :side1)),
        domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus12; ports = ((:T6_12, :side2), (:T12_13,
        :side1), (:WF1, :ac)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus13; ports = ((:T12_13, :side2), (:T6_13,
        :side2), (:T13_14, :side1), (:WF2, :ac)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus14; ports = ((:T9_14, :side1), (:T13_14,
        :side2), (:WF3, :ac)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus9; ports = ((:T9_14, :side2), (:T7_9, :side1),
        (:T9_10, :side1)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus7; ports = ((:MMC2, :ac), (:T7_9, :side2)),
        domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus10; ports = ((:T10_11, :side1), (:T9_10,
        :side2)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bus11; ports = ((:T10_11, :side2), (:T6_11,
        :side2)), domain = ACDQ))
    return NetworkBuilder.define(elements, topology;
        options = (; voltageBase = voltage_base))
end
# Source calc_RLC: S is one-phase power, V is line-to-line RMS kV.

function system_shunt_parameter(S,V,component)
    component == "R" && return V^2/(3S)
    component == "L" && return V^2/(3S*2π*50)
    component == "C" && return 3S/(V^2*2π*50)
    error("unknown shunt component $component")
end

function system_p2p_ac_network(; unstable=false)
    transmissionVoltage=380/sqrt(3)
    pHVDC1=600; qC1=0; qC2=300
    elements = (;)
    topology = NetworkBuilder.Bus[]
    voltage_base = transmissionVoltage
    elements = merge(elements, (; g1 = ac_source(v = (0.9*transmissionVoltage)*sqrt(2))))
    elements = merge(elements, (; Zg1 = impedance(z=s->1+s*0.03, conductors =3)))
    elements = merge(elements, (; g2 = ac_source(v = (transmissionVoltage)*sqrt(2))))
    elements = merge(elements, (; Zg2 = impedance(z=s->1+s*0.01, conductors =3)))
    elements = merge(elements, (; g3 = ac_source(v = (transmissionVoltage)*sqrt(2))))
    elements = merge(elements, (; Zg3 = impedance(z=s->1+s*0.01, conductors =3)))
    elements = merge(elements, (; c1 = let model = mmc(
            vACbase_LL_RMS = 380, Sbase = 1000, vDC_base = 800,
            elec = PowerImpedance.ElectricalMMC(Lₐᵣₘ = 50e-3, Rₐᵣₘ = 1.07, Cₐᵣₘ = 10e-3,
                N = 400, Lᵣ = 60e-3, Rᵣ = 0.535, turnsRatio = 1),
            meas = PowerImpedance.Measurement(),
            sync = PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                filter=PowerImpedance.NoFilter()
            ),
            delta_control = PowerImpedance.ΔdqControlGFL(
                outer_active=PowerImpedance.OuterActiveVdcControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=5, Ki=15),
                    filter=PowerImpedance.NoFilter()
                ),
                outer_reactive=PowerImpedance.OuterReactiveQControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.1, Ki=31.4159),
                    support=PowerImpedance.NoVoltageSupport()
                ),
                occ=PowerImpedance.InnerCurrentPIControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.7691, Ki=522.7654),
                    filter=PowerImpedance.NoFilter(),
                    activate_ω_c_multiplication=false
                )
            ),
            sigma_control = PowerImpedance.ΣdqzControlTEC(
                ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(
                    PowerImpedance.PIControl(Kp=0.1048, Ki=48.1914)
                )
            ),
            modulation = PowerImpedance.UncompensatedModulation(
                timeDelay=0.,
                padeOrderNum=0,
                padeOrderDen=0
            ),
            limits = PowerImpedance.Limits(P_min=-100., P_max=100., Q_min=-50., Q_max=50.))
            b = bases(model)
            component(model; delta_control = (; outer_active = (; v_dc_ref =
                (800) / b.v_dc),
                    outer_reactive = (; q_ref = (qC1) / b.S)),
                powerflow = (; p_ac = (-pHVDC1) / b.S, v_ac = ((220.)*sqrt(2)) / b.v_ac,
                    p_dc = (100.) / b.S))
        end))
    elements = merge(elements, (; c2 = let model = mmc(
            vACbase_LL_RMS = 333, Sbase = 1000, vDC_base = 800,
            elec = PowerImpedance.ElectricalMMC(Lₐᵣₘ = 50e-3, Rₐᵣₘ = 1.07, Cₐᵣₘ = 10e-3,
                N = 400, Lᵣ = 0.0461, Rᵣ = 0.4103, turnsRatio = 333/380),
            meas = PowerImpedance.Measurement(),
            sync = PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=7, Ki=12.5664),
                filter=PowerImpedance.Butterworth(order=1, ωc=2*pi*50)
            ),
            delta_control = PowerImpedance.ΔdqControlGFL(
                outer_active=PowerImpedance.OuterActivePowerControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.1, Ki=31.4159),
                    support=PowerImpedance.NoFrequencySupport()
                ),
                outer_reactive=PowerImpedance.OuterReactiveQControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.1, Ki=31.4159),
                    support=PowerImpedance.NoVoltageSupport()
                ),
                occ=PowerImpedance.InnerCurrentPIControl(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.7691, Ki=522.7654),
                    filter=PowerImpedance.NoFilter(),
                    activate_ω_c_multiplication=false
                )
            ),
            sigma_control = PowerImpedance.ΣdqzControlTEC(
                ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(
                    PowerImpedance.PIControl(Kp=0.1048, Ki=48.1914)
                )
            ),
            modulation = PowerImpedance.UncompensatedModulation(
                timeDelay=0.,
                padeOrderNum=0,
                padeOrderDen=0
            ),
            limits = PowerImpedance.Limits(P_min=-100., P_max=100., Q_min=-50., Q_max=50.))
            b = bases(model)
            component(model; delta_control = (; outer_active = (; p_ref = (pHVDC1) / b.S),
                    outer_reactive = (; q_ref = (qC2) / b.S)),
                powerflow = (; v_dc = (800) / b.v_dc, v_ac = ((220.)*sqrt(2)) / b.v_ac,
                    p_dc = (100.) / b.S))
        end))
    elements = merge(elements, (; dc_line = cable(
            length = 100e3,
            positions = [(-0.5,1), (0.5,1)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3))))
    elements = merge(elements, (; tl1 = system_study_ohl(25e3)))
    elements = merge(elements, (; tl2 = system_study_ohl(25e3)))
    elements = merge(elements, (; tl3 = system_study_ohl(50e3)))
    elements = merge(elements, (; tl67 = system_study_ohl(90e3)))
    push!(topology, NetworkBuilder.Bus(:Bg3; ports = ((:g3, :ac), (:Zg3, :side1)),
        domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:Bg2; ports = ((:g2, :ac), (:Zg2, :side1)),
        domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:B3; ports = ((:c1, :ac), (:tl3, :side2), (:tl2,
        :side2)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:B2; ports = ((:Zg2, :side2), (:tl2, :side1),
        (:tl1, :side2)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:B1; ports = ((:Zg3, :side2), (:tl1, :side1),
        (:tl3, :side1)), domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:B4; ports = ((:c1, :dc), (:dc_line, :side1))))
    push!(topology, NetworkBuilder.Bus(:B5; ports = ((:c2, :dc), (:dc_line, :side2))))
    push!(topology, NetworkBuilder.Bus(:B6; ports = ((:c2, :ac), (:tl67, :side1)),
        domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:B7; ports = ((:Zg1, :side2), (:tl67, :side2)),
        domain = ACDQ))
    push!(topology, NetworkBuilder.Bus(:B8; ports = ((:g1, :ac), (:Zg1, :side1)),
        domain = ACDQ))
    if !unstable
        elements = merge(elements, (; tl67_2 = system_study_ohl(80e3)))
        push!(topology, NetworkBuilder.Bus(:B6;
            ports = ((:tl67_2, :side1),), domain = ACDQ))
        push!(topology, NetworkBuilder.Bus(:B7;
            ports = ((:tl67_2, :side2),), domain = ACDQ))
    end
    return NetworkBuilder.define(elements, topology;
        options = (; voltageBase = voltage_base))
end
# The active case is specified in the source comments; the executable source scans a
# passive grid with a dummy source. T6_11 is open. Source wind farm: 600 MVA / 380 kV /
# 640 kV.

function system_windfarm()
    return let model = tlc(vACbase_LL_RMS = 380, Sbase = 600, vDCbase = 640,
            elec = PowerImpedance.ElectricalTLC(Lᵣ = 0.08*(380^2/600)/2/pi/50,
                Rᵣ = 0.0008*(380^2/600)),
            meas = PowerImpedance.Measurement(
                v_ac=PowerImpedance.Butterworth(order=1, ωc=1e4),
                i_ac=PowerImpedance.Butterworth(order=1, ωc=1e4)
            ),
            sync = PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.397887357729738,
                    Ki=7.957747154594767),
                filter=PowerImpedance.Butterworth(order=1, ωc=2*pi*80)
            ),
            outerActive = PowerImpedance.OuterActivePowerControl(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.01, Ki=10),
                support=PowerImpedance.NoFrequencySupport()
            ),
            outerReactive = PowerImpedance.OuterReactiveQControl(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.01, Ki=10),
                support=PowerImpedance.NoVoltageSupport()
            ), innerVoltage = PowerImpedance.NoInnerVoltageControl(),
            innerCurrent = PowerImpedance.InnerCurrentPIControl(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.254647908947033, Ki=0.8),
                filter=PowerImpedance.NoFilter(),
                activate_ω_c_multiplication=true
            ), mod = PowerImpedance.NoModulation(),
            limits = PowerImpedance.Limits(P_min=-100., P_max=100., Q_min=-50., Q_max=50.))
            b = bases(model)
            component(model; outerActive = (; p_ref = (600) / b.S),
                outerReactive = (; q_ref = (0) / b.S),
                powerflow = (; v_dc = (640) / b.v_dc, v_ac = (380*sqrt(2/3)) / b.v_ac,
                    p_dc = (100.) / b.S))
        end
end
# Shared source OHL geometry; each circuit factory specifies its physical length.

function system_study_ohl(length;transposition=:none)
    return overhead_line(
        length=length,
        transposition=transposition,
        conductors = Conductors(
            organization = :flat,
            nᵇ = 3,
            nˢᵇ = 1,
            Rᵈᶜ = 0.063,
            rᶜ = 0.015,
            yᵇᶜ = 30,
            Δyᵇᶜ = 0,
            Δxᵇᶜ = 10,
            Δ̃xᵇᶜ = 0,
            dˢᵇ = 0,
            dˢᵃᵍ = 10
        ),
        groundwires = Groundwires(
            nᵍ = 2,
            Rᵍᵈᶜ = 0.92,
            rᵍ = 0.0062,
            Δxᵍ = 6.5,
            Δyᵍ = 7.5,
            dᵍˢᵃᵍ   = 10
        ),
        earth_parameters = (1,1,100))
end
for (id,description,parent,measurements,factory) in (
    ("p2p_redesigned","Redesigned P2P at 100 MW","local P2P; selected redesigned parameters",["operating_point", "frequency_response"],()->system_original_p2p_network(redesigned=true)),
    ("ieee14","IEEE14 stable baseline","IEEE14bus/IEEE14bus.jl",["operating_point", "frequency_response"],system_ieee14_network),
    ("p2p_ac_grids","P2P with AC grids and both lines","P2P_HVDC/P2P_HVDC_AC_grid.jl",["operating_point", "frequency_response"],system_p2p_ac_network),
    ("p2p_original","Original P2P early instability","local P2P",["growth"],system_original_p2p_network),
    ("p2p_ac_single_line","P2P with the 80 km line disconnected","P2P_HVDC/P2P_HVDC_AC_grid.jl",["growth"],()->system_p2p_ac_network(unstable=true)))
    push!(REGISTRY,(;id,category=:system,description,parent,factory,topology=description,
        physics=["complete AC/DC network interaction"],
        dissipativity="finite distributed-network contours and located roots; infinite spectrum unenumerated",
        differences=["See system_model_translation.md"],measurements,estimated_nodes=-1))
end
const SYSTEM_PORT_IDS = [entry.id for entry in REGISTRY if entry.category == :system]
