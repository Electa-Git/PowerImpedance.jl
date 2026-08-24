module NumericReference

using DelimitedFiles

export ReferenceData, load_reference, load_metadata
export reference_array, reference_names, reference_scalar, reference_vector

struct ReferenceData
    rows::Dict{String,Vector{NTuple{5,Any}}}
end

function load_reference(path::AbstractString)
    table, _ = readdlm(path, ',', Any; header=true)
    rows = Dict{String,Vector{NTuple{5,Any}}}()
    for row in axes(table, 1)
        name = String(table[row, 1])
        values = (
            table[row, 2],
            table[row, 3],
            table[row, 4],
            table[row, 5],
            table[row, 6],
        )
        push!(get!(rows, name, NTuple{5,Any}[]), values)
    end
    return ReferenceData(rows)
end

function load_metadata(path::AbstractString)
    metadata = Dict{String,String}()
    for line in eachline(path)
        key, value = split(line, '='; limit=2)
        metadata[key] = value
    end
    return metadata
end

reference_names(reference::ReferenceData, prefix::AbstractString="") =
    sort!(filter(name -> startswith(name, prefix), collect(keys(reference.rows))))

function reference_array(reference::ReferenceData, name::AbstractString, dimensions::Tuple)
    rows = reference.rows[String(name)]
    values = Array{ComplexF64}(undef, dimensions)
    assigned = falses(dimensions)
    for row in rows
        i, j, k = Int.(row[1:3])
        index = CartesianIndex((i, j, k)[1:length(dimensions)]...)
        values[index] = complex(Float64(row[4]), Float64(row[5]))
        assigned[index] = true
    end
    all(assigned) || throw(ArgumentError("reference dataset $name is incomplete"))
    return values
end

function reference_scalar(reference::ReferenceData, name::AbstractString)
    rows = reference.rows[String(name)]
    length(rows) == 1 || throw(DimensionMismatch("reference dataset $name is not scalar"))
    row = only(rows)
    return complex(Float64(row[4]), Float64(row[5]))
end

function reference_vector(reference::ReferenceData, name::AbstractString)
    rows = reference.rows[String(name)]
    return reference_array(reference, name, (maximum(Int(row[1]) for row in rows),))
end

end
