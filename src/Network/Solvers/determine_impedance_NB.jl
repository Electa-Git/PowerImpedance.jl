export determine_impedance

"""
    function determine_impedance(network::Network; input_pins :: Array{Any},
        output_pins :: Array{Any}, elim_elements :: Array{Symbol},
         freq_range = (0.001, 10000, 2000))

Estimation of the impedance visible from the port, between input and
output pins. Port pins can possibly be connected to some elements, which
should not be considered for the impedance estimation. Those elements
are listed as `elim_elements`.

Specification for the impedance estimation is given on the example of the following
network that consists of the DC voltage source and a cable.
```
net = @network begin
    vs = dc_source(voltage = 500e3)
    c = cable(length = 100e3, positions = [(0,1)], earth_parameters = (1,1,1),
    C1 = Conductor(rₒ = 24.25e-3, ρ = 1.72e-8), C2 = Conductor(rᵢ = 41.75e-3, rₒ = 46.25e-3, ρ = 22e-8),
    C3 = Conductor(rᵢ = 49.75e-3, rₒ = 60.55e-3, ρ = 18e-8, μᵣ = 10),
    I1 = Insulator(rᵢ = 24.25e-3, rₒ = 41.75e-3, ϵᵣ = 2.3),
    I2 = Insulator(rᵢ = 46.25e-3, rₒ = 49.75e-3, ϵᵣ = 2.3),
    I3 = Insulator(rᵢ = 60.55e-3, rₒ = 65.75e-3, ϵᵣ = 2.3))
    vs[1.1] ⟷ c[1.1] ⟷ Node1
    vs[2.1] ⟷ c[2.1] ⟷  gnd
end
```
To determine impedance visible from the voltage source `vs`, the following command
should be called:
```
imp, omega = determine_impedance(net, elim_elements = [:vs], input_pins = Any[:Node1], output_pins = Any[:gnd],
         freq_range = (0.01, 10000, 2000))
```
Impedance is determined inside network `net`, from the element `vs` and the port defined
with `input_pins` as array consisting of `Node1` and the `output_pins` containing
array with `gnd`. Impedance is estimated for the frequency in Hz within the range
0.01 to 10000 over 2000 points.

The function returns complex impedance map and two arrays: first is the impedance
array and the second one is complex frequency array.
"""
function determine_impedance(lanw :: LinearizedAdmittanceNetwork; nets :: AbstractVector{Symbol},
    elim_elements :: AbstractVector{Symbol}=Symbol[],
    freq_range = (0.001, 10000, 2000))

   
    isempty(nets) && throw(ArgumentError("Impedance cannot be determined from nonexistent nets."))

    ## Element integer ids
    elim_elemidvec = getindex.(Ref(lanw.interface.elem), elim_elements)
    elemidvec = setdiff(1:length(lanw.admittances), elim_elemidvec)
    
    ## Net integer ids
    netidvec = [lanw.interface.net[key] for key in nets]

    ## Frequency range
    (min_f, max_f, n_f) = freq_range
    n_f = convert(Int, n_f) #Make Int to work with range (error when 1e4)

    omega = Vector{ComplexF64}(undef, n_f)
    omega .= 2*pi*10 .^range(log10(min_f), log10(max_f), length= n_f) # Frequency in rad/s
    s = im .* omega # Complex frequency vector
    
    Yred = make_y(lanw, elemidvec, s, netidvec) 
    Z = similar(Yred)

    for i in axes(Yred,3) 
        Z[:,:,i] = inv(Yred[:,:,i])
    end


    return Z, omega
end
