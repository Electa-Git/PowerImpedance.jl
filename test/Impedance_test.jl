# Build analytical impedance models

# Z--> ABCD --> Two-port 
# 1. RL 2. LC


omegas = collect(range(2*pi*0.1, stop=2*pi*5000, step=10))

ω₀ = 2*pi*50
R=0.1
L=0.001
C=5e-5

Z_analytical_ind = []
Z_numerical_ind = []

Z_analytical_cap = []
Z_numerical_cap = []

grid = Network()

add!(
	grid,
	:labanimal_ind,
    impedance(z = (s::Complex)->(R + L*s), pins = 3, transformation = true)
)

add!(
	grid,
	:labanimal_cap,
    impedance(z = (s::Complex)->(R + 1/(s*C)), pins = 3, transformation = true)
)


for i in eachindex(omegas)

    ω=omegas[i]

    # Analytical dq impedance model
    push!(Z_analytical_ind, [R+1im*ω*L ω₀*L; -ω₀*L R+1im*ω*L])
    # Analytical abc impedance model
    push!(Z_analytical_cap, [R - 1im/(ω*C) 0 0; 0 R - 1im/(ω*C) 0; 0 0 R - 1im/(ω*C)])

    # Extract the dq impedance from ABCD matrix in dq frame 🤘🏼
    push!(Z_numerical_ind, PowerImpedance.get_abcd(grid.elements[:labanimal_ind], 1im*ω)[1:2,3:4])
    # Extract the abc impedance from ABCD matrix in abc frame 🤘🏼
    push!(Z_numerical_cap, PowerImpedance.eval_abcd(grid.elements[:labanimal_cap].element_model, 1im*ω)[1:3,4:6])


end


for index in eachindex(omegas)
       

    @test Z_analytical_ind[index] ≈ Z_numerical_ind[index] rtol = 1e-9 atol = 1e-9
    @test Z_analytical_cap[index] ≈ Z_numerical_cap[index] rtol = 1e-9 atol = 1e-9 

    
end
