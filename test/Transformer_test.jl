


Lₚ=0.1
Lₛ=0.05
Rₚ=10
Rₛ=1
n=320/400

omegas = collect(range(2*pi*0.1, stop=2*pi*5000, step=10))

ABCD_analytical=[]
ABCD_numerical=[]


grid = Network()

add!(
	grid,
	:labanimal,
    transformer(n = n , Lₚ = Lₚ, Rₚ = Rₚ, Rₛ = Rₛ, 
    Lₛ = Lₛ,
    pins = 3, transformation = true)
)





for i in eachindex(omegas)

    ω=omegas[i]

    Z_p=[Rₚ+1im*ω*Lₚ 0 0;
      0 Rₚ+1im*ω*Lₚ 0;
      0 0 Rₚ+1im*ω*Lₚ]

    ABCD_p=[Diagonal([1,1,1]) Z_p;
      zeros(3,3) Diagonal([1,1,1])]   

    Z_s=[Rₛ+1im*ω*Lₛ 0 0;
      0 Rₛ+1im*ω*Lₛ 0;
      0 0 Rₛ+1im*ω*Lₛ]

    ABCD_s=[Diagonal([1,1,1]) Z_s;
      zeros(3,3) Diagonal([1,1,1])]


    ABCD_n=[Diagonal([n,n,n]) zeros(3,3);
            zeros(3,3) Diagonal([1/n,1/n,1/n])]

    # Analytical transformer model
    push!(ABCD_analytical, ABCD_p*ABCD_n*ABCD_s)
    push!(ABCD_numerical, PowerImpedanceACDC.eval_abcd(grid.elements[:labanimal].element_value, 1im*ω))




end


for index in eachindex(omegas)
       
    @test ABCD_analytical[index] ≈ ABCD_numerical[index] rtol = 1e-9 atol = 1e-9
    
end



