function isgroundnet(net)
    return startswith(lowercase(string(net)), "gnd")
end

function elecdomain(elem, side)
    
    if is_converter(elem)
        return (2-side) #1 for AC, 2 for DC
    
    elseif is_three_phase(elem)
        return 1 # AC   
    else
       return 2 # DC
    end

end
#convenience macro to create typedtable types
macro Table(ex)
    Meta.isexpr(ex, :braces) || throw(ArgumentError("@Table expects {...}"))
    nt_elements = :(@NamedTuple{})
    nt_vectors = :(@NamedTuple{})
 
    for a in ex.args
        if !(a isa LineNumberNode)
            Meta.isexpr(a, :(::)) ||throw(ArgumentError("@Table specification must contain name::type expressions"))
            var = (a.args[1])
            el = esc(a.args[2])
            push!(nt_elements.args[3].args,:($var::$el))
            push!(nt_vectors.args[3].args,:($var::Vector{$el}))
        end
    end
    return :(Table{$nt_elements,1, $nt_vectors})
end
export @Table