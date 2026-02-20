# For debugging 
# include("../../src/HVDCstability.jl")
# using .HVDCstability

using Plots
using PGFPlotsX
using DelimitedFiles
using LinearAlgebra
using Combinatorics

Pref = 500
Qref = 0
Vm = 380 / sqrt(3) 
Vdc = 640
# Old file, not updated. Contains an MMC with SI controller gains.

net = @network begin

    S1 = ac_source(pins = 3, V = Vm, transformation = true)
    S2 = ac_source(pins = 3, V = Vm, transformation = true)

    OHL1 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

    OHL2 = overhead_line(length = 100e3,
        conductors = Conductors(organization = :flat, nᵇ = 3, nˢᵇ = 1, Rᵈᶜ = 0.063, rᶜ = 0.015,  yᵇᶜ = 30,
                        Δyᵇᶜ = 0, Δxᵇᶜ = 10,  Δ̃xᵇᶜ = 0, dˢᵇ = 0,  dˢᵃᵍ = 10),
        groundwires = Groundwires(nᵍ = 2, Rᵍᵈᶜ = 0.92, rᵍ = 0.0062, Δxᵍ = 6.5, Δyᵍ = 7.5, dᵍˢᵃᵍ   = 10),
        earth_parameters = (1,1,100), transformation = true)

    C1 = mmc(Vᵈᶜ = Vdc, Vₘ = Vm,
        P_max = 1000, P_min = -1000, P = Pref, Q = Qref, Q_max = 1000, Q_min = -1000,
        occ = PI_control(Kₚ = 111.0624, Kᵢ = 7.5487e+04),
        ccc = PI_control(Kₚ = 42.9123, Kᵢ = 1.9739e+04),
        pll = PI_control(Kₚ = 2.8351e-04, Kᵢ = 0.0127),
        p = PI_control(Kₚ = 2.1487e-07, Kᵢ = 6.7503e-05),
        #q = PI_control(Kₚ = 2.1487e-07, Kᵢ = 6.7503e-05)
        )

    C2 = mmc(Vᵈᶜ = Vdc, Vₘ = Vm,
        P_max = 1000, P_min = -1000, P = -Pref, Q = Qref, Q_max = 1000, Q_min = -1000,
        occ = PI_control(Kₚ = 111.0624, Kᵢ = 7.5487e+04),
        ccc = PI_control(Kₚ = 42.9123, Kᵢ = 1.9739e+04),
        pll = PI_control(Kₚ = 2.8351e-04, Kᵢ = 0.0127),
        #q = PI_control(Kₚ = 2.1487e-07, Kᵢ = 6.7503e-05),
        dc = PI_control(Kₚ = 0.0168, Kᵢ = 0.0504)
        )

    Cable1 = cable(length = 100e3, positions = [(-0.5,1), (0.5,1)],
        C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8),
        C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
        C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
        I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
        I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
        I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3), transformation = true)   

    S1[2.1] ⟷ gndd
    S1[2.2] ⟷ gndq
    S1[1.1] ⟷ OHL1[1.1]
    S1[1.2] ⟷ OHL1[1.2]

    OHL1[2.1] ⟷ C1[2.1] ⟷ Noded
    OHL1[2.2] ⟷ C1[2.2] ⟷ Nodeq

    C1[1.1] ⟷ Cable1[1.1] ⟷ Nodedc
    C2[1.1] ⟷ Cable1[2.1]

    C2[2.1] ⟷ OHL2[1.1]
    C2[2.2] ⟷ OHL2[1.2]

    S2[1.1] ⟷ OHL2[2.1]
    S2[1.2] ⟷ OHL2[2.2]
    S2[2.1] ⟷ gndd
    S2[2.2] ⟷ gndq
    
end

##### ----- STABILITY ANALYSIS WITH DETERMINE_IMPEDANCE ----- #####

# DC-side
#=
Z_MMC_DC, omega = determine_impedance(net, elim_elements = [:Cable1], input_pins = Any[:Nodedc], output_pins = Any[:gndd], omega_range = (-3, 4, 10000))
Z_BUS_DC, omega = determine_impedance(net, elim_elements = [:C1], input_pins = Any[:Nodedc], output_pins = Any[:gndd], omega_range = (-3, 4, 10000))
L_DC = Z_BUS_DC ./ Z_MMC_DC

nyquist_P2P_DC = nyquistplot(L_DC, zoom = "no") 
display(nyquist_P2P_DC)
=#

# AC-side
#=
Z_MMC_AC, omega = determine_impedance(net, elim_elements = [:OHL1], input_pins = Any[:Noded, :Nodeq], output_pins = Any[:gndd, :gndq], omega_range = (-3, 4, 10000))
Z_BUS_AC, omega = determine_impedance(net, elim_elements = [:C1], input_pins = Any[:Noded, :Nodeq], output_pins = Any[:gndd, :gndq], omega_range = (-3, 4, 10000))
L_AC = Z_BUS_AC ./ Z_MMC_AC

nyquist_P2P_AC = nyquistplot(L_AC, zoom = "no")
display(nyquist_P2P_AC)
=#

##### ----- MMC ADMITTANCE MATRIX ----- #####

f_min = 10^-3
f_max = 10^4
n = 10000
f = 10 .^ range(log10(f_min), log10(f_max), length = n)
omega = 2*pi*f

#MMC = net.elements[:C1]
#plot_data(MMC, omega_range = (0, 3, 1000), scale = :log)

Ycon1 = []
for i in 1:length(omega)
    Y = eval_abcd(net.elements[:C1].element_value, 1im*omega[i]) #eval_abcd for MMC gives admittance matrix, see converter.jl
    push!(Ycon1, [transpose(Y[1,:]); transpose(-Y[2,:]); transpose(-Y[3,:])]) #adapt for current direction
end

MMC = net.elements[:C2]
plot_data(MMC, omega_range = (0, 3, 1000), scale = :log)

Ycon2 = []
for i in 1:length(omega)
    Y = eval_abcd(net.elements[:C2].element_value, 1im*omega[i]) 
    push!(Ycon2, [transpose(Y[1,:]); transpose(-Y[2,:]); transpose(-Y[3,:])]) 
end

Ycon = []
for i in 1:length(omega)
    push!(Ycon, [Ycon1[i] zeros(Complex{Float64},3,3); zeros(Complex{Float64},3,3) Ycon2[i]])
end

##### ----- Cable1 ABCD ----- #####

#From two poles to single pole
Cable1_ABCD = []
for i in 1:length(omega)
    ABCD = eval_abcd(net.elements[:Cable1].element_value, 1im*omega[i]) 
    n = Int(size(ABCD, 1)/2)
    (a, b, c, d) = (ABCD[1:n,1:n], ABCD[1:n,n+1:end], ABCD[n+1:end,1:n], ABCD[n+1:end, n+1:end])
    ABCD = [(a[1,1]+a[2,2]-a[1,2]-a[2,1])/2 (b[1,1]+b[2,2]-b[1,2]-b[2,1]); (c[1,1]+c[2,2]-c[1,2]-c[2,1])/4 (d[1,1]+d[2,2]-d[1,2]-d[2,1])/2] # Section 2.5 Tutorial
    push!(Cable1_ABCD, ABCD) 
end

YbusDC = []

for i in 1:length(omega)
    ABCD = Cable1_ABCD[i]
    (a, b, c, d) = (ABCD[1,1], ABCD[1,2], ABCD[2,1], ABCD[2,2])
    push!(YbusDC, [a/b -1/b; -1/b a/b])
end

ZbusDC = inv.(YbusDC)

##### ----- OHL1 ABCD ----- #####

#=
#Approach Aleksandra
OHL1_ABCD_dq = []

for i in 1:length(omega)
    ω₀ = 100*π
    ABCD₁ = eval_abcd(net.elements[:OHL1].element_value, 1im*omega[i] + 1im*ω₀)
    ABCD₂ = eval_abcd(net.elements[:OHL1].element_value, 1im*omega[i] - 1im*ω₀)

    n = Int(size(ABCD₁, 1)/2)
    (a₁, b₁, c₁, d₁) = (ABCD₁[1:n,1:n], ABCD₁[1:n,n+1:end], ABCD₁[n+1:end,1:n], ABCD₁[n+1:end, n+1:end])
    (a₂, b₂, c₂, d₂) = (ABCD₂[1:n,1:n], ABCD₂[1:n,n+1:end], ABCD₂[n+1:end,1:n], ABCD₂[n+1:end, n+1:end])

    ϕ = 2π/3
    e = exp(1im*ϕ)
    a = [1 e e^2; 1im 1im*e 1im*e^2; 0 0 0]

    a_dq = (1/3 * (a * a₁ + conj(a) * a₂) * transpose(real(a)))[1:2,1:2]
    b_dq = (1/3 * (a * b₁ + conj(a) * b₂) * transpose(real(a)))[1:2,1:2]
    c_dq = (1/3 * (a * c₁ + conj(a) * c₂) * transpose(real(a)))[1:2,1:2]
    d_dq = (1/3 * (a * d₁ + conj(a) * d₂) * transpose(real(a)))[1:2,1:2]

    push!(OHL1_ABCD_dq, [a_dq b_dq; c_dq d_dq])

end
=#

#Approach Philippe
OHL1_ABCD_dq = []

for i in 1:length(omega)
    ω₀ = 100*π
    ABCD₁ = eval_abcd(net.elements[:OHL1].element_value, 1im*omega[i] + 1im*ω₀)
    ABCD₂ = eval_abcd(net.elements[:OHL1].element_value, 1im*omega[i] - 1im*ω₀)

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

    push!(OHL1_ABCD_dq, [a_dq b_dq; c_dq d_dq])

end

YbusAC1 = []
ZbusAC1 = [] # Ideal AC voltage source at one end

for i in 1:length(omega)
    ABCD = OHL1_ABCD_dq[i]
    n = Int(size(ABCD, 1)/2)
    (a, b, c, d) = (ABCD[1:n,1:n], ABCD[1:n,n+1:end], ABCD[n+1:end,1:n], ABCD[n+1:end, n+1:end])
    push!(YbusAC1, [inv(b)*a -inv(b); -inv(b) inv(b)*a])
    push!(ZbusAC1, inv(a)*b)
end

ZbusAC2 = ZbusAC1

# AC/DC bus impedance matrix

# V = [vdc1 vd1 vq1 vdc2 vd2 vq2 vsd1 vsq1 vsd2 vsq2]^T
# I = [idc1 id1 iq1 idc2 id2 iq2 isd1 isq1 isd2 isq2]^T 
# V = Zbus*i

# For ideal AC voltage sources

# V = [vdc1 vd1 vq1 vdc2 vd2 vq2]^T
# I = [idc1 id1 iq1 idc2 id2 iq2]^T 
# V = Zbus*i

Zbus = []
for i in 1:length(omega)
    ZbusDCi = ZbusDC[i]     #[vdc1 vdc2]^T = ZbusDC = [idc1 idc2]^T
    ZbusAC1i = ZbusAC1[i]   #[vd1 vq1]^T = ZbusAC2 = [id1 iq1]^T
    ZbusAC2i = ZbusAC2[i]   #[vd2 vq2]^T = ZbusAC2 = [id2 iq2]^T

    # 10x10 if AC voltage sources are included
    push!(Zbus, 
   [ZbusDCi[1,1] 0 0 ZbusDCi[1,2] 0 0; 
    0 ZbusAC1i[1,1] ZbusAC1i[1,2] 0 0 0;
    0 ZbusAC1i[2,1] ZbusAC1i[2,2] 0 0 0; 
    ZbusDCi[2,1] 0 0 ZbusDCi[2,2] 0 0;
    0 0 0 0 ZbusAC2i[1,1] ZbusAC2i[1,2];
    0 0 0 0 ZbusAC2i[2,1] ZbusAC2i[2,2]])
end

# AC/DC loop gain matrix

L_ACDC = Zbus .* Ycon

nyquist_P2P_ACDC = nyquistplot(L_ACDC, omega, zoom = "yes", SM = "PM")
savefig("nyquist_P2P_ACDC.png")
println("Pole at the origin due to integrator of DC voltage control")

# Eigenvalue decomposition

Ybus = inv.(Zbus)
Zcl_bus = inv.(Ybus + Ycon)

fmin = 1
fmax = 10000

EVD(Zcl_bus, omega, fmin, fmax)

