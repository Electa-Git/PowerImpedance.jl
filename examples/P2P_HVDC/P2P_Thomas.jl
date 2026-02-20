# For debugging 
# include("../../src/HVDCstability.jl")
# using .HVDCstability

# Activate used packages in file 
using DelimitedFiles
using SymEngine
using Plots
using HVDCstability

s = symbols("s")

# Grid voltage and control references in SI units 
Pref = 500
Qref = 0
Vm = 380 / sqrt(3) #Vln,rms
Vdc = 800

# Create network under study by definition of components and interconnection of component pins 
# Network under study: point-to-point HVDC system 
net = @network begin

    voltageBase = Vm

    # 3 phase AC voltage sources at both ends, transformation to dq (transformation = true)
    G1 = ac_source(pins = 3, V = Vm, transformation = true)
    G2 = ac_source(pins = 3, V = Vm, transformation = true)

    # AC grid impedances in SI units, transformation to dq 
    Zg1 = impedance(z = 0.1 + 0.005*s, pins = 3, transformation = true)
    Zg2 = impedance(z = 0.1 + 0.005*s, pins = 3, transformation = true)

    # Definition of DC voltage controlling MMC, control parameters in PU 
    MMC1 = mmc(Vᵈᶜ = Vdc, vDCbase = 800, vACbase_LL_RMS = 380, vPCC_scaling = 380/380, Vₘ = Vm, Lᵣ = 60e-3, Rᵣ = 0.535,
        P_max = 1500, P_min = -1500, P = -Pref, Q = Qref, Q_max = 500, Q_min = -500,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159, ref = [Qref]),
        dc = PI_control(Kₚ = 5, Kᵢ = 15, ref = [1.0])
        )

    # Definition of active power controlling MMC, control parameters in PU     
    MMC2 = mmc(Vᵈᶜ = Vdc, vDCbase = 800, vACbase_LL_RMS = 380, vPCC_scaling = 380/380, Vₘ = Vm, Lᵣ = 60e-3, Rᵣ = 0.535,
        P_max = 1000, P_min = -1000, P = Pref, Q = Qref, Q_max = 1000, Q_min = -1000,
        occ = PI_control(Kₚ = 0.7691, Kᵢ = 522.7654),
        ccc = PI_control(Kₚ = 0.1048, Kᵢ = 48.1914),
        pll = PI_control(Kₚ = 0.28, Kᵢ = 12.5664),
        p = PI_control(Kₚ = 0.1, Kᵢ = 31.4159, ref = [Pref]),
        q = PI_control(Kₚ = 0.1, Kᵢ = 31.4159, ref = [Qref])
        )

    # DC submarine cable (conductor, sheath, armor)    
    CableDC12 = cable(length = 100e3, positions = [(-0.5,1), (0.5,1)],
        C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
        I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)    
 
    # AC overhead line in AC network 1, transformation to dq    
    OHLAC1g1 = overhead_line(length = 50e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

    # AC overhead line in AC network 2, transformation to dq      
    OHLAC2g2 = overhead_line(length = 50e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

    # Interconnection of component pins     

    # Definition of d- and q-axis grounding 
    G1[2.1] ⟷ gndD
    G1[2.2] ⟷ gndQ
    G2[2.1] ⟷ gndD
    G2[2.2] ⟷ gndQ

    # Connection of AC voltage source 1 to grid impedance 1, in dq (2 pins)
    G1[1.1] ⟷ Zg1[1.1]
    G1[1.2] ⟷ Zg1[1.2]

    # Connection of grid impedance 1 and OHL 1, definition of node names 
    Zg1[2.1] ⟷ OHLAC1g1[1.1] ⟷ NodeDq1
    Zg1[2.2] ⟷ OHLAC1g1[1.2] ⟷ NodeQg1

    # Connection of OHL 1 to AC-side of MMC 1
    OHLAC1g1[2.1] ⟷ MMC1[2.1] ⟷ NodeD1
    OHLAC1g1[2.2] ⟷ MMC1[2.2] ⟷ NodeQ1

    # Connection of DC-sides of MMCs via DC cable 
    MMC1[1.1] ⟷ CableDC12[1.1] ⟷ NodeDC1
    MMC2[1.1] ⟷ CableDC12[2.1] ⟷ NodeDC2

    # Connection of AC-side of MMC 2 to OHL 2
    MMC2[2.1] ⟷ OHLAC2g2[1.1] ⟷ NodeD2
    MMC2[2.2] ⟷ OHLAC2g2[1.2] ⟷ NodeQ2

    # Connection of grid impedance 2 and OHL 2
    Zg2[2.1] ⟷ OHLAC2g2[2.1] ⟷ NodeDg2
    Zg2[2.2] ⟷ OHLAC2g2[2.2] ⟷ NodeQg2

    # Connection of AC voltage source 2 to grid impedance 2
    G2[1.1] ⟷ Zg2[1.1]
    G2[1.2] ⟷ Zg2[1.2]

end

#16/08/2023: changes made in Network.jl and transmission_line.jl to improve power flow 
#For loads, uncommand in Network.jl:
#if is_impedance(element)
#make_shunt_ac_impedance(data, element, dict_ac, new_i, new_o)
#else
#Transmission line: use sequence impedance instead of phase impedance in transmission_line.jl

#=
##### ----- STABILITY ANALYSIS WITH DETERMINE_IMPEDANCE ----- #####
# Classical impedance-based stability analysis at single terminal

# Terminal DC 1
# elim_elements: elimate component to disconnect network 
# input_pins: pins at which impedance is determined 
# output_pins: always ground pins 
# Balanced condition is assumed so DC-side impedance is 1x1, 1 input pin and 1 output pin 
# omega_range: frequency range [Hz] in log scale and number of frequency points 

Z_MMC_DC1, omega = determine_impedance(net, elim_elements = [:CableDC12], input_pins = Any[:NodeDC1], output_pins = Any[:gndD], omega_range = (0, 4, 10000))
Z_BUS_DC1, omega = determine_impedance(net, elim_elements = [:MMC1], input_pins = Any[:NodeDC1], output_pins = Any[:gndD], omega_range = (0, 4, 10000))

# Definition of DC-side loop gain 
L_DC1 = Z_BUS_DC1 ./ Z_MMC_DC1

# Use of nyquistplot function to assess stability, possible to zoom in on (-1, 0j) point by zoom = "yes"
# Stability margins are calculated: "VM" (vector margin), "PM" (phase margin), "GM" (gain margin) or "no"
nyquist_L_DC1 = nyquistplot(L_DC1, omega, zoom = "no", SM = "VM") 

# Terminal AC 2
# Transformation to dq so AC-side impedance is 2x2, 2 input pins and 2 output pins
Z_MMC_AC2, omega = determine_impedance(net, elim_elements = [:OHLAC2g2], input_pins = Any[:NodeD2, :NodeQ2], output_pins = Any[:gndD, :gndQ], omega_range = (0, 4, 10000))
Z_BUS_AC2, omega = determine_impedance(net, elim_elements = [:MMC2], input_pins = Any[:NodeD2, :NodeQ2], output_pins = Any[:gndD, :gndQ], omega_range = (0, 4, 10000))

# Definition of AC-side loop gain matrix 
L_AC2 = Z_BUS_AC2 ./ Z_MMC_AC2

# Use of nyquistplot function to assess stability
nyquist_L_AC2 = nyquistplot(L_AC2, omega, zoom = "no", SM = "VM") 
=#

##### ----- NODE ADMITTANCE MATRIX Yn ----- #####

# Define the frequency points for the calculation of the node and edge admittance matrix 
omega_min = 0
omega_max = 4
omegaₙ = 10000

# The frequency response data of the grid impedances is obtained via the determine_impedance function 
Zg1DQ, omega = determine_impedance(net, elim_elements = [:OHLAC1g1], input_pins = Any[:NodeDq1, :NodeQg1], output_pins = Any[:gndD, :gndQ], omega_range = (omega_min, omega_max, omegaₙ)) 
Yg1DQ = inv.(Zg1DQ)
f = omega/(2*pi)

Zg2DQ, omega = determine_impedance(net, elim_elements = [:OHLAC2g2], input_pins = Any[:NodeDg2, :NodeQg2], output_pins = Any[:gndD, :gndQ], omega_range = (omega_min, omega_max, omegaₙ)) 
Yg2DQ = inv.(Zg2DQ) 
f = omega/(2*pi)

# Transformation to global dq reference frame :
# C. Zhang, M. Molinas, A. Rygg, and X. Cai, “Impedance-based analysis of interconnected power electronics systems: 
# Impedance network modeling and comparative studies of stability criteria,” 
# IEEE J. Emerg. Sel. Top. Power Electron., vol. 8, no. 3, pp. 2520–2533, Sep. 2020, doi: 10.1109/JESTPE.2019.2914560.

# Globale dq reference frame 
# The dq frame in the paper is with d-axis alignment to alpha and q-axis leading the d-axis?
# Tdq(θ₁) = [cos(θ₁) sin(θ₁); -sin(θ₁) cos(θ₁)]

# HVDCstability.jl: The dq frame is with d-axis alignment to alpha and q-axis lagging the d-axis
# Tdq(θ₁) = [cos(θ₁) -sin(θ₁); sin(θ₁) cos(θ₁)]
# Tdq_inv(θ₁) = [cos(θ₁) sin(θ₁); -sin(θ₁) cos(θ₁)]
# Page 30 of simulator tutorial, MMC.jl line 205-206

#Zdq_global = Tdq(-θ₁)*Zdq_local*Tdq(θ₁)

# 3x3 matrix converter 
# Tdq_c(θ₁) = [1 0 0; 0 cos(θ₁) -sin(θ₁); 0 sin(θ₁) cos(θ₁)]
# Zdq_c_global(θ₁) = Tdq_c(-θ₁)*Zdq_c_local*Tdq_c(θ₁)

# Determining frequency response data of 3x3 MMC admittance matrix based on state-state representation of multiple dq model 
# Y_MMC1 = []
# Y_dc1 = []
# for i in 1:length(omega)
#     Y = eval_abcd(net.elements[:MMC1].element_value, 1im*omega[i])              # eval_abcd for MMC gives admittance matrix, see converter.jl
#     push!(Y_MMC1, [transpose(Y[1,:]); transpose(-Y[2,:]); transpose(-Y[3,:])])  # Adapt to current direction towards MMC 
#     push!(Y_dc1, Y[1,1])
# end

# bode_Ydc1 = bodeplot(Y_dc1, omega, legend = "Y_dc1")
# display(bode_Ydc1)

Y_MMC2 = []
Y_dc2 = []
for i in 1:length(omega)
    Y = eval_abcd(net.elements[:MMC2].element_value, 1im*omega[i]) 
    push!(Y_MMC2, [transpose(Y[1,:]); transpose(-Y[2,:]); transpose(-Y[3,:])]) 
    push!(Y_dc2, Y[1,1]) 
end

bode_Ydc2 = bodeplot(Y_dc2, omega, legend = "Y_dc2")
display(bode_Ydc2)

omega = 2*pi*f

# Voltage anlge at AC terminal of MMCs 
θ₁ = net.elements[:MMC1].element_value.θ
θ₂ = net.elements[:MMC2].element_value.θ

# Transformation to global dq reference frame 
Tdq_c1 = [1 0 0; 0 cos(θ₁) -sin(θ₁); 0 sin(θ₁) cos(θ₁)]
for i in 1:length(f)
    Y_MMC1[i] = inv(Tdq_c1)*Y_MMC1[i]*Tdq_c1
end

Tdq_c2 = [1 0 0; 0 cos(θ₂) -sin(θ₂); 0 sin(θ₂) cos(θ₂)]
for i in 1:length(f)
    Y_MMC2[i] = inv(Tdq_c2)*Y_MMC2[i]*Tdq_c2
end

writedlm("./files/Y_MMC1.csv",  Y_MMC1, ',')
writedlm("./files/Y_MMC2.csv",  Y_MMC2, ',')
writedlm("./files/omega.csv",  omega, ',')

MMC2_data = net.elements[:MMC2]
plot_data(MMC2_data, omega_range = (0, 3, 1000), scale = :log)

# Inserting admittance data of MMCs and sources/generators at diagonals of node admittance matrix 
Yn = [] 
for i in 1:length(omega)
    Ynᵢ = zeros(Complex{Float64},10,10)
    Ynᵢ[1:3,1:3] = Y_MMC1[i]
    Ynᵢ[4:6,4:6] = Y_MMC2[i]
    Ynᵢ[7:8,7:8] = Yg1DQ[i]
    Ynᵢ[9:10,9:10] = Yg2DQ[i]
    push!(Yn, Ynᵢ)
end

##### ----- EDGE ADMITTANCE MATRIX Ye ----- #####

##### ----- Y_BUS_DC ----- #####

#Converting two cable poles to single pole under balanced condition 
ABCD_CableDC12 = []
for i in 1:length(omega)
    ABCD = eval_abcd(net.elements[:CableDC12].element_value, 1im*omega[i]) 
    n = Int(size(ABCD, 1)/2)
    (a, b, c, d) = (ABCD[1:n,1:n], ABCD[1:n,n+1:end], ABCD[n+1:end,1:n], ABCD[n+1:end, n+1:end])
    ABCD = [(a[1,1]+a[2,2]-a[1,2]-a[2,1])/2 (b[1,1]+b[2,2]-b[1,2]-b[2,1]); (c[1,1]+c[2,2]-c[1,2]-c[2,1])/4 (d[1,1]+d[2,2]-d[1,2]-d[2,1])/2] # Section 2.5 Tutorial
    push!(ABCD_CableDC12, ABCD) 
end

# Creating admittance matrix of DC network, see equation 3.27 PhD thesis 
Y_BUS_DC = []

for i in 1:length(omega)
    ABCD12 = ABCD_CableDC12[i]
    (a12, b12, c12, d12) = (ABCD12[1,1], ABCD12[1,2], ABCD12[2,1], ABCD12[2,2])
    push!(Y_BUS_DC, [a12/b12 -1/b12; -1/b12 a12/b12])
end

##### ----- Y_BUS_AC1 ----- #####

# Converting ABDC parameters of OHL in abc frame to dq frame
ABCD_OHLAC1g1_DQ = []

for i in 1:length(omega)
    ω₀ = 100*π
    ABCD₁ = eval_abcd(net.elements[:OHLAC1g1].element_value, 1im*omega[i] + 1im*ω₀)
    ABCD₂ = eval_abcd(net.elements[:OHLAC1g1].element_value, 1im*omega[i] - 1im*ω₀)

    n = Int(size(ABCD₁, 1)/2)
    (a₁, b₁, c₁, d₁) = (ABCD₁[1:n,1:n], ABCD₁[1:n,n+1:end], ABCD₁[n+1:end,1:n], ABCD₁[n+1:end, n+1:end])
    (a₂, b₂, c₂, d₂) = (ABCD₂[1:n,1:n], ABCD₂[1:n,n+1:end], ABCD₂[n+1:end,1:n], ABCD₂[n+1:end, n+1:end])

    # Implemented Park transformation: d-axis alignment, q-axis lagging, peak-invariant
    T = [1 -1im; -1im -1]
    CK = (2/3)*[1 -1/2 -1/2; 0 sqrt(3)/2 -sqrt(3)/2]
    CKinv = [1 0; -1/2 sqrt(3)/2; -1/2 -sqrt(3)/2]

    a_dq = T * CK * a₂ * CKinv * conj(T) + conj(T) * CK * a₁ * CKinv * T 
    b_dq = T * CK * b₂ * CKinv * conj(T) + conj(T) * CK * b₁ * CKinv * T
    c_dq = T * CK * c₂ * CKinv * conj(T) + conj(T) * CK * c₁ * CKinv * T
    d_dq = T * CK * d₂ * CKinv * conj(T) + conj(T) * CK * d₁ * CKinv * T

    push!(ABCD_OHLAC1g1_DQ, [a_dq b_dq; c_dq d_dq])

end

# Creating admittance matrix of AC network 1
Y_BUS_AC1 = []

for i in 1:length(omega)
    ABCD1g1 = ABCD_OHLAC1g1_DQ[i]
    n = Int(size(ABCD1g1, 1)/2)
    (a1g1, b1g1, c1g1, d1g1) = (ABCD1g1[1:n,1:n], ABCD1g1[1:n,n+1:end], ABCD1g1[n+1:end,1:n], ABCD1g1[n+1:end, n+1:end])
    push!(Y_BUS_AC1, [inv(b1g1)*a1g1 -inv(b1g1); -inv(b1g1) inv(b1g1)*a1g1])
end

##### ----- Y_BUS_AC2 ----- #####

# Converting ABDC parameters of OHL in abc frame to dq frame
ABCD_OHLAC2g2_DQ = []

for i in 1:length(omega)
    ω₀ = 100*π
    ABCD₁ = eval_abcd(net.elements[:OHLAC2g2].element_value, 1im*omega[i] + 1im*ω₀)
    ABCD₂ = eval_abcd(net.elements[:OHLAC2g2].element_value, 1im*omega[i] - 1im*ω₀)

    n = Int(size(ABCD₁, 1)/2)
    (a₁, b₁, c₁, d₁) = (ABCD₁[1:n,1:n], ABCD₁[1:n,n+1:end], ABCD₁[n+1:end,1:n], ABCD₁[n+1:end, n+1:end])
    (a₂, b₂, c₂, d₂) = (ABCD₂[1:n,1:n], ABCD₂[1:n,n+1:end], ABCD₂[n+1:end,1:n], ABCD₂[n+1:end, n+1:end])

    # Implemented Park transformation: d-axis alignment, q-axis lagging, peak-invariant
    T = [1 -1im; -1im -1]
    CK = (2/3)*[1 -1/2 -1/2; 0 sqrt(3)/2 -sqrt(3)/2]
    CKinv = [1 0; -1/2 sqrt(3)/2; -1/2 -sqrt(3)/2]

    a_dq = T * CK * a₂ * CKinv * conj(T) + conj(T) * CK * a₁ * CKinv * T 
    b_dq = T * CK * b₂ * CKinv * conj(T) + conj(T) * CK * b₁ * CKinv * T
    c_dq = T * CK * c₂ * CKinv * conj(T) + conj(T) * CK * c₁ * CKinv * T
    d_dq = T * CK * d₂ * CKinv * conj(T) + conj(T) * CK * d₁ * CKinv * T

    push!(ABCD_OHLAC2g2_DQ, [a_dq b_dq; c_dq d_dq])

end

# Creating admittance matrix of AC network 2
Y_BUS_AC2 = []

for i in 1:length(omega)
    ABCD2g2 = ABCD_OHLAC2g2_DQ[i]
    n = Int(size(ABCD2g2, 1)/2)
    (a2g2, b2g2, c2g2, d2g2) = (ABCD2g2[1:n,1:n], ABCD2g2[1:n,n+1:end], ABCD2g2[n+1:end,1:n], ABCD2g2[n+1:end, n+1:end])
    push!(Y_BUS_AC2, [inv(b2g2)*a2g2 -inv(b2g2); -inv(b2g2) inv(b2g2)*a2g2])
end

# Ordering of edge admittance matrix

# I = [idc1 id1 iq1 idc2 id2 iq2 idg1 iqg1 idg2 iqg2]^T 
# V = [vdc1 vd1 vq1 vdc2 vd2 vq2 vdg1 vqg1 vdg2 vqg2]^T
# I = Y_BUS*V

Ye = [] #Edges

for i in 1:length(omega)

    Yeᵢ = zeros(Complex{Float64},10,10)
    
    #Y_BUS_DC
    Yeᵢ[1,1] = Y_BUS_DC[i][1,1]
    Yeᵢ[1,4] = Y_BUS_DC[i][1,2]
    Yeᵢ[4,1] = Y_BUS_DC[i][2,1]
    Yeᵢ[4,4] = Y_BUS_DC[i][2,2]

    #Y_BUS_AC1
    Yeᵢ[2:3,2:3] = Y_BUS_AC1[i][1:2,1:2]
    Yeᵢ[2:3,7:8] = Y_BUS_AC1[i][1:2,3:4]
    Yeᵢ[7:8,2:3] = Y_BUS_AC1[i][3:4,1:2]
    Yeᵢ[7:8,7:8] = Y_BUS_AC1[i][3:4,3:4]

    #Y_BUS_AC2
    Yeᵢ[5:6,5:6] = Y_BUS_AC2[i][1:2,1:2]
    Yeᵢ[5:6,9:10] = Y_BUS_AC2[i][1:2,3:4]
    Yeᵢ[9:10,5:6] = Y_BUS_AC2[i][3:4,1:2]
    Yeᵢ[9:10,9:10] = Y_BUS_AC2[i][3:4,3:4]

    push!(Ye, Yeᵢ)

end

# Definition of loop gain matrix for hybrid AC/DC stability assessment 
L = inv.(Ye) .* Yn
nyquist_P2P = nyquistplot(L, omega, zoom = "no", SM = "VM")
# Save Nyquist plot in package folder 
savefig("./files/nyquist_P2P.png")

# Definition of closed-loop bus impedance matrix 
Zcl_bus = inv.(Ye + Yn)

fmin = 1
fmax = 10000

# Determine dominant oscillation mode of bus voltages and bus participation factors via EVD (eigenvalue decomposition) function 
EVD_P2P = EVD(Zcl_bus, omega, fmin, fmax)
# Save EVD plot in package folder 
savefig("./files/EVD_P2P.png")


