function PSCAD.read_project_summary(path::AbstractString)::PSCAD.ProjectSummary
    tree = PythonCall.pyimport("lxml.etree").parse(String(path))
    root = tree.getroot()
    counts = Dict{String, Int}()
    labels = Dict{String, Int}()
    pgbs = String[]
    for component in root.xpath("./definitions/Definition[@name='Main']/schematic/User")
        defn = PythonCall.pyconvert(String, component.get("defn"))
        counts[defn] = get(counts, defn, 0) + 1
        if defn in ("master:nodelabel", "master:pgb")
            name = PythonCall.pyconvert(
                String, component.xpath("string(./paramlist/param[@name='Name']/@value)"))
            defn == "master:nodelabel" ? (labels[name] = get(labels, name, 0) + 1) :
            push!(pgbs, name)
        end
    end
    settings = Dict{String, String}()
    for parameter in root.xpath("./paramlist[@name='Settings']/param")
        key = PythonCall.pyconvert(String, parameter.get("name"))
        settings[key] = PythonCall.pyconvert(String, parameter.get("value"))
    end
    return PSCAD.ProjectSummary(counts, labels, pgbs, settings,
        PythonCall.pyconvert(String, root.get("version")))
end
