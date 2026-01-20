export dc_source

"""
    dc_source(;args...)
Creates dc voltage in Volts.

Internal impedance can be added with a command impedance after
the equality sign.

Pins: `1.x` and `2.x` for x ∈ {1, ..., pins}

Plus pin is connected to `1.x` and minus to `2.x`. To ground the source,
connect the pin to the ground while constructing the network.

Parameters:
```julia
Z :: Union{Float64, Int, Basic} = 0 # source series impedance [Ω]
    V :: Union{Float64, Int} = 0        # DC voltage or voltage magnitude [kV]

    P   :: Union{Float64, Int} = 0      # active power output [MW]
    Q   :: Union{Float64, Int} = 0      # reactive power output [MVAr]
    P_min :: Union{Float64, Int} = 0    # min active power output [MW]
    P_max :: Union{Float64, Int} = 0    # max active power output [MW]
    Q_min :: Union{Float64, Int} = 0    # min reactive power output [MVA]
    Q_max :: Union{Float64, Int} = 0    # max reactive power output [MVA]

    pins :: Int = 1
    ABCD :: Array{Basic} = Basic[]
```
"""
function dc_source(;args...)
    source = Source()
    transformation = false
    connection = true
    for (key, val) in pairs(args)
        if in(key, propertynames(source))
            setfield!(source, key, val)
        elseif (key == :transformation)
            transformation = val
        elseif (key == :connection)
            connection = val
        else
            throw(ArgumentError("Source does not have a property $(key)."))
        end
    end
    make_abcd(source)
    elem = Element(input_pins = source.pins, output_pins = source.pins, element_value = source,
        transformation = transformation, connection = connection)
    elem
end
