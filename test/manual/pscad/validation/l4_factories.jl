# Frozen ports of Jan Kircheis study circuits retain all source units. Source and
# translation details: l4_translation.md. These factories do not read or execute the
# source repository.

function l4_original_p2p_network(; redesigned=false)
    net=Network()
    net.voltageBase[1]=380/sqrt(3)
    for name in (:g1,:g4)
        add!(net,name,ac_source(pins=3,transformation=true,
            setpoint=Setpoint(Vac=380sqrt(2/3),Pac=100),
            limits=PowerImpedance.Limits(P_min=-2000,P_max=2000,Q_min=-1000,Q_max=1000)))
    end
    for (name,active,arm_l) in ((:c1,true,.05),(:c2,false,.03))
        referred=redesigned || name==:c2
        elec=PowerImpedance.ElectricalMMC(Lₐᵣₘ=arm_l,Rₐᵣₘ=1.07,Cₐᵣₘ=.01,N=400,
            turnsRatio=referred ? 333/380 : 1.,Lᵣ=referred ? .0461 : .06,
            Rᵣ=redesigned ? 1.10889 : referred ? .4103 : .535,
            vACbase_LL_RMS=referred ? 333 : 380,Sbase=1000,vDC_base=640)
        outer=active ? PowerImpedance.OuterActiveVdcControl(pi_ctrl=PIControl(Kp=redesigned ? 3. : 6.,Ki=redesigned ? 7.5 : 15.)) :
            PowerImpedance.OuterActivePowerControl(pi_ctrl=PIControl(Kp=redesigned ? .05 : .1,Ki=redesigned ? 15.70795 : 31.4159))
        delta=PowerImpedance.ΔdqControlGFL(outer_active=outer,
            outer_reactive=PowerImpedance.OuterReactiveQControl(pi_ctrl=PIControl(Kp=redesigned ? .05 : .1,Ki=redesigned ? 15.70795 : 31.4159)),
            occ=PowerImpedance.InnerCurrentPIControl(pi_ctrl=PIControl(Kp=redesigned ? .25 : .7691,Ki=redesigned ? 100. : 522.7654),
                filter=redesigned ? PowerImpedance.Butterworth(order=2,ωc=2π*500) : PowerImpedance.NoFilter(),
                activate_ω_c_multiplication=redesigned))
        sigma=PowerImpedance.ΣdqzControlTEC(ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(pi_control=PIControl(Kp=.1048,Ki=48.1914)))
        add!(net,name,mmc(;elec,delta_control=delta,sigma_control=sigma,
            sync=PowerImpedance.PLLSynchronization(pi_ctrl=PIControl(Kp=redesigned ? .14 : .28,Ki=redesigned ? 3.1416 : 12.5664),
                filter=redesigned ? PowerImpedance.Butterworth(order=1,ωc=2π*40) : PowerImpedance.NoFilter()),
            meas=PowerImpedance.Measurement(v_ac=redesigned ? PowerImpedance.Butterworth(order=1,ωc=2π*2000) : PowerImpedance.NoFilter()),
            modulation=PowerImpedance.UncompensatedModulation(timeDelay=redesigned ? 25e-6 : 200e-6,padeOrderNum=5,padeOrderDen=5),
            setpoint=Setpoint(Pac=active ? -100 : 100,Qac=100,Vac=380sqrt(2/3),Vdc=640,Pdc=100),
            limits=PowerImpedance.Limits(P_min=active ? -1500 : -1000,P_max=active ? 1500 : 1000,
                Q_min=active ? -500 : -1000,Q_max=active ? 500 : 1000)))
    end
    add!(net,:ugc,cable(length=25e3,positions=[(-.5,1.),(.5,1.)],
        C1=Conductor(rₒ=.02622,ρ=2.354e-8,μᵣ=1.035),
        I1=Insulator(rᵢ=.02622,rₒ=.06006,ϵᵣ=2.67,μᵣ=1.469),
        C2=Conductor(rᵢ=.06006,rₒ=.06336,ρ=2.14e-7,μᵣ=1.),
        I2=Insulator(rᵢ=.06336,rₒ=.06636,ϵᵣ=2.3,μᵣ=1.),
        C3=Conductor(rᵢ=.06636,rₒ=.06651,ρ=2.826e-8,μᵣ=1.),
        I3=Insulator(rᵢ=.06651,rₒ=.07256,ϵᵣ=2.3,μᵣ=1.),
        earth_parameters=(1,1,100),transformation=true))
    add!(net,:ohl,overhead_line(length=75e3,
        conductors=Conductors(organization=:flat,nᵇ=2,nˢᵇ=1,Rᵈᶜ=.0266,rᶜ=.0224,
            yᵇᶜ=18.,Δyᵇᶜ=0.,Δxᵇᶜ=7.3,Δ̃xᵇᶜ=0.,dˢᵇ=0.,dˢᵃᵍ=6.),
        groundwires=Groundwires(nᵍ=2,Rᵍᵈᶜ=.92,rᵍ=.0062,Δxᵍ=7.3,Δyᵍ=7.,dᵍˢᵃᵍ=6.),
        earth_parameters=(1,1,100),transformation=true))
    add!(net,:tl1,l4_study_ohl(25e3));add!(net,:tl78,l4_study_ohl(90e3))
    for (name,side,bus) in ((:c1,2,:B3),(:tl1,2,:B3),(:tl1,1,:B2),(:g4,1,redesigned ? :G4 : :B2),
            (:g4,2,:gnd),(:c2,2,:B6),(:tl78,1,:B6),(:tl78,2,:B7),(:g1,1,redesigned ? :G1 : :B7),(:g1,2,:gnd))
        composed_ac!(net,name,side,bus)
    end
    for (name,side,bus) in ((:c1,1,:B4),(:ugc,1,:B4),(:ugc,2,:BX),(:ohl,1,:BX),(:ohl,2,:B5),(:c2,1,:B5))
        connect!(net,(name,Symbol("$side.1")),bus)
    end
    for (source,bus,grid) in ((:G4,:B2,:Z_g4),(:G1,:B7,:Z_g1))
        if redesigned
            r=380^2/1000/8/sqrt(101);l=10r/(100π)
            add!(net,grid,impedance(z=s->r+l*s,pins=3,transformation=true))
            composed_ac!(net,grid,1,source);composed_ac!(net,grid,2,bus)
        end
    end
    connect!(net)
    return net
end

function l4_ieee14_network()
    P_MMC1=-1000
    Q_MMC1= 0
    P_MMC2=-1000
    Q_MMC2=0
    Q_MMC3=0.0
    Q_MMC4=0.0
    R_B2=l4_shunt_parameter(72.333,380,"R")
    L_B2=l4_shunt_parameter(42.333,380,"L")
    R_B5=l4_shunt_parameter(25.333,380,"R")
    L_B5=l4_shunt_parameter(05.333,380,"L")
    R_B3=l4_shunt_parameter(314,380,"R")
    L_B3=l4_shunt_parameter(63.333,380,"L")
    R_B4=l4_shunt_parameter(159.333,380,"R")
    C_B4=l4_shunt_parameter(13.000,380,"C")
    R_B6=l4_shunt_parameter(37.333,380,"R")
    L_B6=l4_shunt_parameter(25.0,380,"L")
    Vm=380/sqrt(3)
    net=Network()
    net.voltageBase[1]=Vm
    add!(net,:G1,ac_source(pins=3, setpoint=Setpoint(Vac=Vm*sqrt(2)), transformation=true))
    add!(net,:G2,ac_source(pins=3, setpoint=Setpoint(Vac=Vm*sqrt(2)), transformation=true))
    add!(net,:DC_WF1,dc_source(pins=2, setpoint=Setpoint(Vdc=640), transformation=true))
    add!(net,:DC_WF2,dc_source(pins=2, setpoint=Setpoint(Vdc=640), transformation=true))
    add!(net,:DC_WF3,dc_source(pins=2, setpoint=Setpoint(Vdc=640), transformation=true))
    add!(net,:Zg1,impedance(z=s->0.2874  + 0.0091*s, pins = 3, transformation = true))
    add!(net,:Zg2,impedance(z=s->1.026 + 1*0.0327*s, pins = 3, transformation = true))
    add!(
        net,
        :MMC1,
        mmc(
            elec=PowerImpedance.ElectricalMMC(
                Lₐᵣₘ=46.125e-3,
                Rₐᵣₘ=0.4,
                Cₐᵣₘ=11.3867e-3,
                N=400,
                Lᵣ=0.18 * (333^2/1000) /2/pi/50,
                Rᵣ=0.001 *(333^2/1000),
                vACbase_LL_RMS=333,
                Sbase=1000,
                vDC_base=640,
                turnsRatio=333/380
            ),
            meas=PowerImpedance.Measurement(
                P_ac=PowerImpedance.Butterworth(order=2, ωc=140*2*pi),
                Q_ac=PowerImpedance.Butterworth(order=2, ωc=140*2*pi)
            ),
            sync=PowerImpedance.VSEWithDamping(
                H=5,
                K_d=100,
                K_ω=10,
                ω_ref=1,
                pll=PowerImpedance.PLLSynchronization(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                    filter=PowerImpedance.Butterworth(order=1, ωc=75*2*pi)
                )
            ),
            delta_control=PowerImpedance.ΔdqControlGFM(
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
            sigma_control=PowerImpedance.ΣdqzControlTEC(
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
            modulation=PowerImpedance.UncompensatedModulation(
                timeDelay=200e-6,
                padeOrderNum=5,
                padeOrderDen=5
            ),
            setpoint=Setpoint(Pac=P_MMC1, Qac=Q_MMC1, Vac=(Vm)*sqrt(2), θac=0., Vdc=640, Pdc=100.),
            limits=PowerImpedance.Limits(P_min=-1500, P_max=1500, Q_min=-500, Q_max=500)
        )
    )
    add!(
        net,
        :MMC2,
        mmc(
            elec=PowerImpedance.ElectricalMMC(
                Lₐᵣₘ=46.125e-3,
                Rₐᵣₘ=0.4,
                Cₐᵣₘ=11.3867e-3,
                N=400,
                Lᵣ=0.18 * (333^2/1000) /2/pi/50,
                Rᵣ=0.001 *(333^2/1000),
                vACbase_LL_RMS=333,
                Sbase=1000,
                vDC_base=640,
                turnsRatio=333/380
            ),
            meas=PowerImpedance.Measurement(
                P_ac=PowerImpedance.Butterworth(order=2, ωc=140*2*pi),
                Q_ac=PowerImpedance.Butterworth(order=2, ωc=140*2*pi)
            ),
            sync=PowerImpedance.VSEWithDamping(
                H=5,
                K_d=100,
                K_ω=10,
                ω_ref=1,
                pll=PowerImpedance.PLLSynchronization(
                    pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                    filter=PowerImpedance.Butterworth(order=1, ωc=75*2*pi)
                )
            ),
            delta_control=PowerImpedance.ΔdqControlGFM(
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
            sigma_control=PowerImpedance.ΣdqzControlTEC(
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
            modulation=PowerImpedance.UncompensatedModulation(
                timeDelay=250e-6,
                padeOrderNum=5,
                padeOrderDen=5
            ),
            setpoint=Setpoint(Pac=P_MMC2, Qac=Q_MMC2, Vac=(Vm)*sqrt(2), θac=0., Vdc=640, Pdc=100.),
            limits=PowerImpedance.Limits(P_min=-1500, P_max=1500, Q_min=-500, Q_max=500)
        )
    )
    add!(
        net,
        :MMC3,
        mmc(
            elec=PowerImpedance.ElectricalMMC(
                Lₐᵣₘ=50e-3,
                Rₐᵣₘ=1.07,
                Cₐᵣₘ=10e-3,
                N=400,
                Lᵣ=0.1305*(333^2/1000)/2/pi/50,
                Rᵣ=0.0037*(333^2/1000),
                vACbase_LL_RMS=333,
                Sbase=1000,
                vDC_base=640,
                turnsRatio=333/380
            ),
            meas=PowerImpedance.Measurement(),
            sync=PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                filter=PowerImpedance.NoFilter()
            ),
            delta_control=PowerImpedance.ΔdqControlGFL(
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
            sigma_control=PowerImpedance.ΣdqzControlTEC(
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
            modulation=PowerImpedance.UncompensatedModulation(
                timeDelay=200e-6,
                padeOrderNum=5,
                padeOrderDen=5
            ),
            setpoint=Setpoint(Pac=-10., Qac=Q_MMC3, Vac=(Vm)*sqrt(2), θac=0., Vdc=640, Pdc=100.),
            limits=PowerImpedance.Limits(P_min=-1500, P_max=1500, Q_min=-500, Q_max=500)
        )
    )
    add!(
        net,
        :MMC4,
        mmc(
            elec=PowerImpedance.ElectricalMMC(
                Lₐᵣₘ=50e-3,
                Rₐᵣₘ=1.07,
                Cₐᵣₘ=10e-3,
                N=400,
                Lᵣ=0.1305*(333^2/1000)/2/pi/50,
                Rᵣ=0.0037*(333^2/1000),
                vACbase_LL_RMS=333,
                Sbase=1000,
                vDC_base=640,
                turnsRatio=333/380
            ),
            meas=PowerImpedance.Measurement(),
            sync=PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                filter=PowerImpedance.NoFilter()
            ),
            delta_control=PowerImpedance.ΔdqControlGFL(
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
            sigma_control=PowerImpedance.ΣdqzControlTEC(
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
            modulation=PowerImpedance.UncompensatedModulation(
                timeDelay=200e-6,
                padeOrderNum=5,
                padeOrderDen=5
            ),
            setpoint=Setpoint(Pac=-10., Qac=Q_MMC4, Vac=(Vm)*sqrt(2), θac=0., Vdc=640, Pdc=100.),
            limits=PowerImpedance.Limits(P_min=-1500, P_max=1500, Q_min=-500, Q_max=500)
        )
    )
    add!(net,:WF1,l4_windfarm())
    add!(net,:WF2,l4_windfarm())
    add!(net,:WF3,l4_windfarm())
    add!(net,:T1_2,l4_study_ohl(100e3))
    add!(net,:T1_5,l4_study_ohl(100e3))
    add!(net,:T2_5,l4_study_ohl(100e3))
    add!(net,:T4_5,l4_study_ohl(100e3))
    add!(net,:T2_4,l4_study_ohl(100e3))
    add!(net,:T2_3,l4_study_ohl(100e3))
    add!(net,:T3_4,l4_study_ohl(100e3))
    add!(net,:T12_13,l4_study_ohl(100e3))
    add!(net,:T6_12,l4_study_ohl(100e3))
    add!(net,:T6_13,l4_study_ohl(20e3))
    add!(net,:T6_11,l4_study_ohl(5e3))
    add!(net,:T10_11,l4_study_ohl(5e3))
    add!(net,:T13_14,l4_study_ohl(20e3))
    add!(net,:T9_14,l4_study_ohl(20e3))
    add!(net,:T9_10,l4_study_ohl(5e3))
    add!(net,:T7_9,l4_study_ohl(5e3))
    add!(
        net,
        :CableDC23,
        cable(
            length = 200e3,
            positions = [(0,1.5), (1,1.5)],
            C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
            I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
            C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
            I2 = Insulator(rᵢ = 55.4e-3, rₒ = 61.2e-3, ϵᵣ = 2.3),
            transformation = true
        )
    )
    add!(
        net,
        :CableDC23_1,
        cable(
            length = 200e3,
            positions = [(0,1.5), (1,1.5)],
            C1 = Conductor(rₒ = 30.00e-3, ρ = 2.82e-8),
            I1 = Insulator(rᵢ = 30.00e-3, rₒ = 51.5e-3,  ϵᵣ = 2.5),
            C2 = Conductor(rᵢ = 51.5e-3, rₒ = 55.4e-3, ρ = 1.72e-8),
            I2 = Insulator(rᵢ = 55.4e-3, rₒ = 61.2e-3, ϵᵣ = 2.3),
            transformation = true
        )
    )
    add!(net,:LoadB2,impedance(z=s->1/((1/R_B2)+(1/(s*L_B2))), pins = 3, transformation = true))
    add!(net,:LoadB5,impedance(z=s->1/((1/R_B5)+(1/(s*L_B5))), pins = 3, transformation = true))
    add!(net,:LoadB3,impedance(z=s->1/((1/R_B3)+(1/(s*L_B3))), pins = 3, transformation = true))
    add!(net,:LoadB4,impedance(z=s->1/((1/R_B4)+(s*C_B4)), pins = 3, transformation = true))
    add!(net,:LoadB6,impedance(z=s->1/((1/R_B6)+(1/(s*L_B6))), pins = 3, transformation = true))
    connect!(net,(:LoadB2,Symbol("2.1")), :gndD)
    connect!(net,(:LoadB2,Symbol("2.2")), :gndQ)
    connect!(net,(:LoadB5,Symbol("2.1")), :gndD)
    connect!(net,(:LoadB5,Symbol("2.2")), :gndQ)
    connect!(net,(:LoadB3,Symbol("2.1")), :gndD)
    connect!(net,(:LoadB3,Symbol("2.2")), :gndQ)
    connect!(net,(:LoadB4,Symbol("2.1")), :gndD)
    connect!(net,(:LoadB4,Symbol("2.2")), :gndQ)
    connect!(net,(:LoadB6,Symbol("2.1")), :gndD)
    connect!(net,(:LoadB6,Symbol("2.2")), :gndQ)
    connect!(net,(:G1,Symbol("2.1")), :gndD)
    connect!(net,(:G1,Symbol("2.2")), :gndQ)
    connect!(net,(:G2,Symbol("2.1")), :gndD)
    connect!(net,(:G2,Symbol("2.2")), :gndQ)
    connect!(net,(:DC_WF1,Symbol("2.1")), :gndDC)
    connect!(net,(:DC_WF2,Symbol("2.1")), :gndDC)
    connect!(net,(:DC_WF3,Symbol("2.1")), :gndDC)
    connect!(net,(:Zg1,Symbol("1.1")), (:G1,Symbol("1.1")))
    connect!(net,(:Zg1,Symbol("1.2")), (:G1,Symbol("1.2")))
    connect!(net,(:Zg1,Symbol("2.1")), (:T1_2,Symbol("1.1")), (:T1_5,Symbol("1.1")), :Bus1d)
    connect!(net,(:Zg1,Symbol("2.2")), (:T1_2,Symbol("1.2")), (:T1_5,Symbol("1.2")), :Bus1q)
    connect!(net,(:T2_3,Symbol("1.1")), (:T2_4,Symbol("1.1")), (:T2_5,Symbol("1.1")), (:T1_2,Symbol("2.1")), (:LoadB2,Symbol("1.1")), :Bus2d)
    connect!(net,(:T2_3,Symbol("1.2")), (:T2_4,Symbol("1.2")), (:T2_5,Symbol("1.2")), (:T1_2,Symbol("2.2")), (:LoadB2,Symbol("1.2")), :Bus2q)
    connect!(net,(:T2_3,Symbol("2.1")), (:T3_4,Symbol("1.1")), (:LoadB3,Symbol("1.1")), :Bus3d)
    connect!(net,(:T2_3,Symbol("2.2")), (:T3_4,Symbol("1.2")), (:LoadB3,Symbol("1.2")), :Bus3q)
    connect!(net,(:T4_5,Symbol("1.1")), (:T2_4,Symbol("2.1")), (:T3_4,Symbol("2.1")), (:LoadB4,Symbol("1.1")), (:MMC4,Symbol("2.1")), :Bus4d)
    connect!(net,(:T4_5,Symbol("1.2")), (:T2_4,Symbol("2.2")), (:T3_4,Symbol("2.2")), (:LoadB4,Symbol("1.2")), (:MMC4,Symbol("2.2")), :Bus4q)
    connect!(net,(:T4_5,Symbol("2.1")), (:T2_5,Symbol("2.1")), (:T1_5,Symbol("2.1")), (:LoadB5,Symbol("1.1")), (:MMC3,Symbol("2.1")), :Bus5d)
    connect!(net,(:T4_5,Symbol("2.2")), (:T2_5,Symbol("2.2")), (:T1_5,Symbol("2.2")), (:LoadB5,Symbol("1.2")), (:MMC3,Symbol("2.2")), :Bus5q)
    connect!(net,(:CableDC23,Symbol("1.1")), (:MMC1,Symbol("1.1")), :BusDC1)
    connect!(net,(:CableDC23_1,Symbol("1.1")), (:MMC2,Symbol("1.1")), :BusDC2)
    connect!(net,(:CableDC23,Symbol("2.1")), (:MMC3,Symbol("1.1")), :BusDC3)
    connect!(net,(:CableDC23_1,Symbol("2.1")), (:MMC4,Symbol("1.1")), :BusDC4)
    connect!(net,(:WF1,Symbol("1.1")), (:DC_WF1,Symbol("1.1")))
    connect!(net,(:WF2,Symbol("1.1")), (:DC_WF2,Symbol("1.1")))
    connect!(net,(:WF3,Symbol("1.1")), (:DC_WF3,Symbol("1.1")))
    connect!(net,(:Zg2,Symbol("1.1")), (:G2,Symbol("1.1")))
    connect!(net,(:Zg2,Symbol("1.2")), (:G2,Symbol("1.2")))
    connect!(net,(:Zg2,Symbol("2.1")), (:MMC1,Symbol("2.1")), (:T6_12,Symbol("1.1")), (:T6_13,Symbol("1.1")), (:T6_11,Symbol("1.1")), (:LoadB6,Symbol("1.1")), :Bus6d)
    connect!(net,(:Zg2,Symbol("2.2")), (:MMC1,Symbol("2.2")), (:T6_12,Symbol("1.2")), (:T6_13,Symbol("1.2")), (:T6_11,Symbol("1.2")), (:LoadB6,Symbol("1.2")), :Bus6q)
    connect!(net,(:T6_12,Symbol("2.1")), (:T12_13,Symbol("1.1")), (:WF1,Symbol("2.1")), :Bus12d)
    connect!(net,(:T6_12,Symbol("2.2")), (:T12_13,Symbol("1.2")), (:WF1,Symbol("2.2")), :Bus12q)
    connect!(net,(:T12_13,Symbol("2.1")), (:T6_13,Symbol("2.1")), (:T13_14,Symbol("1.1")), (:WF2,Symbol("2.1")), :Bus13d)
    connect!(net,(:T12_13,Symbol("2.2")), (:T6_13,Symbol("2.2")), (:T13_14,Symbol("1.2")), (:WF2,Symbol("2.2")), :Bus13q)
    connect!(net,(:T9_14,Symbol("1.1")), (:T13_14,Symbol("2.1")), (:WF3,Symbol("2.1")), :Bus14d)
    connect!(net,(:T9_14,Symbol("1.2")), (:T13_14,Symbol("2.2")), (:WF3,Symbol("2.2")), :Bus14q)
    connect!(net,(:T9_14,Symbol("2.1")), (:T7_9,Symbol("1.1")), (:T9_10,Symbol("1.1")), :Bus9d)
    connect!(net,(:T9_14,Symbol("2.2")), (:T7_9,Symbol("1.2")), (:T9_10,Symbol("1.2")), :Bus9q)
    connect!(net,(:MMC2,Symbol("2.1")), (:T7_9,Symbol("2.1")), :Bus7d)
    connect!(net,(:MMC2,Symbol("2.2")), (:T7_9,Symbol("2.2")), :Bus7q)
    connect!(net,(:T10_11,Symbol("1.1")), (:T9_10,Symbol("2.1")), :Bus10d)
    connect!(net,(:T10_11,Symbol("1.2")), (:T9_10,Symbol("2.2")), :Bus10q)
    connect!(net,(:T10_11,Symbol("2.1")), (:T6_11,Symbol("2.1")), :Bus11d)
    connect!(net,(:T10_11,Symbol("2.2")), (:T6_11,Symbol("2.2")), :Bus11q)
    connect!(net)
    return net
end

# Source calc_RLC: S is one-phase power, V is line-to-line RMS kV.
function l4_shunt_parameter(S,V,component)
    component == "R" && return V^2/(3S)
    component == "L" && return V^2/(3S*2π*50)
    component == "C" && return 3S/(V^2*2π*50)
    error("unknown shunt component $component")
end

function l4_p2p_ac_network(; unstable=false)
    transmissionVoltage=380/sqrt(3)
    pHVDC1=600; qC1=0; qC2=300
    net=Network()
    net.voltageBase[1]=transmissionVoltage
    add!(
        net,
        :g1,
        ac_source(
            setpoint=Setpoint(Vac=(0.9*transmissionVoltage)*sqrt(2)),
            pins=3,
            transformation=true
        )
    )
    add!(net,:Zg1,impedance(z=s->1+s*0.03, pins=3, transformation=true))
    add!(
        net,
        :g2,
        ac_source(setpoint=Setpoint(Vac=(transmissionVoltage)*sqrt(2)), pins=3, transformation=true)
    )
    add!(net,:Zg2,impedance(z=s->1+s*0.01, pins=3, transformation=true))
    add!(
        net,
        :g3,
        ac_source(setpoint=Setpoint(Vac=(transmissionVoltage)*sqrt(2)), pins=3, transformation=true)
    )
    add!(net,:Zg3,impedance(z=s->1+s*0.01, pins=3, transformation=true))
    add!(
        net,
        :c1,
        mmc(
            elec=PowerImpedance.ElectricalMMC(
                Lₐᵣₘ=50e-3,
                Rₐᵣₘ=1.07,
                Cₐᵣₘ=10e-3,
                N=400,
                Lᵣ=60e-3,
                Rᵣ=0.535,
                vACbase_LL_RMS=380,
                Sbase=1000,
                vDC_base=800,
                turnsRatio=1
            ),
            meas=PowerImpedance.Measurement(),
            sync=PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=0.28, Ki=12.5664),
                filter=PowerImpedance.NoFilter()
            ),
            delta_control=PowerImpedance.ΔdqControlGFL(
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
            sigma_control=PowerImpedance.ΣdqzControlTEC(
                ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(
                    PowerImpedance.PIControl(Kp=0.1048, Ki=48.1914)
                )
            ),
            modulation=PowerImpedance.UncompensatedModulation(
                timeDelay=0.,
                padeOrderNum=0,
                padeOrderDen=0
            ),
            setpoint=Setpoint(Pac=-pHVDC1, Qac=qC1, Vac=(220.)*sqrt(2), θac=0., Vdc=800, Pdc=100.),
            limits=PowerImpedance.Limits(P_min=-100., P_max=100., Q_min=-50., Q_max=50.)
        )
    )
    add!(
        net,
        :c2,
        mmc(
            elec=PowerImpedance.ElectricalMMC(
                Lₐᵣₘ=50e-3,
                Rₐᵣₘ=1.07,
                Cₐᵣₘ=10e-3,
                N=400,
                Lᵣ=0.0461,
                Rᵣ=0.4103,
                vACbase_LL_RMS=333,
                Sbase=1000,
                vDC_base=800,
                turnsRatio=333/380
            ),
            meas=PowerImpedance.Measurement(),
            sync=PowerImpedance.PLLSynchronization(
                pi_ctrl=PowerImpedance.PIControl(Kp=7, Ki=12.5664),
                filter=PowerImpedance.Butterworth(order=1, ωc=2*pi*50)
            ),
            delta_control=PowerImpedance.ΔdqControlGFL(
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
            sigma_control=PowerImpedance.ΣdqzControlTEC(
                ccsc=PowerImpedance.CirculatingCurrentSuppressionControl(
                    PowerImpedance.PIControl(Kp=0.1048, Ki=48.1914)
                )
            ),
            modulation=PowerImpedance.UncompensatedModulation(
                timeDelay=0.,
                padeOrderNum=0,
                padeOrderDen=0
            ),
            setpoint=Setpoint(Pac=pHVDC1, Qac=qC2, Vac=(220.)*sqrt(2), θac=0., Vdc=800, Pdc=100.),
            limits=PowerImpedance.Limits(P_min=-100., P_max=100., Q_min=-50., Q_max=50.)
        )
    )
    add!(
        net,
        :dc_line,
        cable(
            length = 100e3,
            positions = [(-0.5,1), (0.5,1)],
            C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
            C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
            C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
            I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
            I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
            I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3),
            transformation = true
        )
    )
    add!(net,:tl1,l4_study_ohl(25e3))
    add!(net,:tl2,l4_study_ohl(25e3))
    add!(net,:tl3,l4_study_ohl(50e3))
    add!(net,:tl67,l4_study_ohl(90e3))
    connect!(net,(:g3,Symbol("1.1")), (:Zg3,Symbol("1.1")), :Bg3d)
    connect!(net,(:g3,Symbol("1.2")), (:Zg3,Symbol("1.2")), :Bg3q)
    connect!(net,(:g2,Symbol("1.1")), (:Zg2,Symbol("1.1")), :Bg2d)
    connect!(net,(:g2,Symbol("1.2")), (:Zg2,Symbol("1.2")), :Bg2q)
    connect!(net,(:g3,Symbol("2.1")), :gndD)
    connect!(net,(:g3,Symbol("2.2")), :gndQ)
    connect!(net,(:g2,Symbol("2.1")), :gndD)
    connect!(net,(:g2,Symbol("2.2")), :gndQ)
    connect!(net,(:c1,Symbol("2.1")), (:tl3,Symbol("2.1")), (:tl2,Symbol("2.1")), :B3d)
    connect!(net,(:c1,Symbol("2.2")), (:tl3,Symbol("2.2")), (:tl2,Symbol("2.2")), :B3q)
    connect!(net,(:Zg2,Symbol("2.1")), (:tl2,Symbol("1.1")), (:tl1,Symbol("2.1")), :B2d)
    connect!(net,(:Zg2,Symbol("2.2")), (:tl2,Symbol("1.2")), (:tl1,Symbol("2.2")), :B2q)
    connect!(net,(:Zg3,Symbol("2.1")), (:tl1,Symbol("1.1")), (:tl3,Symbol("1.1")), :B1d)
    connect!(net,(:Zg3,Symbol("2.2")), (:tl1,Symbol("1.2")), (:tl3,Symbol("1.2")), :B1q)
    connect!(net,(:c1,Symbol("1.1")), (:dc_line,Symbol("1.1")), :B4)
    connect!(net,(:c2,Symbol("1.1")), (:dc_line,Symbol("2.1")), :B5)
    connect!(net,(:c2,Symbol("2.1")), (:tl67,Symbol("1.1")), :B6d)
    connect!(net,(:c2,Symbol("2.2")), (:tl67,Symbol("1.2")), :B6q)
    connect!(net,(:Zg1,Symbol("2.1")), (:tl67,Symbol("2.1")), :B7d)
    connect!(net,(:Zg1,Symbol("2.2")), (:tl67,Symbol("2.2")), :B7q)
    connect!(net,(:g1,Symbol("1.1")), (:Zg1,Symbol("1.1")), :B8d)
    connect!(net,(:g1,Symbol("1.2")), (:Zg1,Symbol("1.2")), :B8q)
    connect!(net,(:g1,Symbol("2.1")), :gndd)
    connect!(net,(:g1,Symbol("2.2")), :gndq)
    connect!(net)
    if !unstable
        add!(net,:tl67_2,l4_study_ohl(80e3))
        for (pin,bus) in (("1.1",:B6d),("1.2",:B6q),("2.1",:B7d),("2.2",:B7q))
            connect!(net,(:tl67_2,Symbol(pin)),bus)
        end
        connect!(net)
    end
    return net
end

# The active case is specified in the source comments; the executable source scans a
# passive grid with a dummy source. T6_11 is open. Source wind farm: 600 MVA / 380 kV /
# 640 kV.
function l4_windfarm()
    return tlc(
        elec=PowerImpedance.ElectricalTLC(
            Lᵣ=0.08*(380^2/600)/2/pi/50,
            Rᵣ=0.0008*(380^2/600),
            vACbase_LL_RMS=380,
            Sbase=600,
            vDCbase=640
        ),
        meas=PowerImpedance.Measurement(
            v_ac=PowerImpedance.Butterworth(order=1, ωc=1e4),
            i_ac=PowerImpedance.Butterworth(order=1, ωc=1e4)
        ),
        sync=PowerImpedance.PLLSynchronization(
            pi_ctrl=PowerImpedance.PIControl(Kp=0.397887357729738, Ki=7.957747154594767),
            filter=PowerImpedance.Butterworth(order=1, ωc=2*pi*80)
        ),
        outerActive=PowerImpedance.OuterActivePowerControl(
            pi_ctrl=PowerImpedance.PIControl(Kp=0.01, Ki=10),
            support=PowerImpedance.NoFrequencySupport()
        ),
        outerReactive=PowerImpedance.OuterReactiveQControl(
            pi_ctrl=PowerImpedance.PIControl(Kp=0.01, Ki=10),
            support=PowerImpedance.NoVoltageSupport()
        ),
        innerVoltage=PowerImpedance.NoInnerVoltageControl(),
        innerCurrent=PowerImpedance.InnerCurrentPIControl(
            pi_ctrl=PowerImpedance.PIControl(Kp=0.254647908947033, Ki=0.8),
            filter=PowerImpedance.NoFilter(),
            activate_ω_c_multiplication=true
        ),
        mod=PowerImpedance.NoModulation(),
        setpoint=Setpoint(Pac=600, Qac=0, Vac=380*sqrt(2/3), θac=0., Vdc=640, Pdc=100.),
        limits=PowerImpedance.Limits(P_min=-100., P_max=100., Q_min=-50., Q_max=50.)
    )
end

# Shared source OHL geometry; each circuit factory specifies its physical length.
function l4_study_ohl(length)
    return overhead_line(
        length=length,
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
        earth_parameters = (1,1,100),
        transformation = true
    )
end

for (id,description,parent,tiers,factory) in (
    ("L4-01","P6 redesigned P2P at 100 MW","local P2P; selected P6 parameters",["A","C"],()->l4_original_p2p_network(redesigned=true)),
    ("L4-03","IEEE14 stable baseline","IEEE14bus/IEEE14bus.jl",["A","C"],l4_ieee14_network),
    ("L4-04","P2P with AC grids and both lines","P2P_HVDC/P2P_HVDC_AC_grid.jl",["A","C"],l4_p2p_ac_network),
    ("L4-00D","Original P2P early instability","local P2P",["D"],l4_original_p2p_network),
    ("L4-04D","P2P with the 80 km line disconnected","P2P_HVDC/P2P_HVDC_AC_grid.jl",["D"],()->l4_p2p_ac_network(unstable=true)))
    push!(REGISTRY,(;id,description,parent,factory,topology=description,
        physics=["complete AC/DC network interaction"],
        dissipativity="finite distributed-network contours and located roots; infinite spectrum unenumerated",
        differences=["See l4_translation.md"],tiers,estimated_nodes=-1))
end
const L4_PORT_IDS = [entry.id for entry in REGISTRY if startswith(entry.id,"L4-")]
