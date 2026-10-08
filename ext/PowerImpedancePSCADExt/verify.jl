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
    rows = Dict{String, Dict{String, Int}}()
    for row in root.xpath("./definitions/Definition[@classid='RowDefn']")
        name = PythonCall.pyconvert(String, row.get("name"))
        row_counts = Dict{String, Int}()
        for component in row.xpath("./schematic/User")
            defn = PythonCall.pyconvert(String, component.get("defn"))
            row_counts[defn] = get(row_counts, defn, 0) + 1
        end
        rows[name] = row_counts
    end
    wrappers = Dict{String, Int}()
    for wrapper in root.xpath("./definitions/Definition[@name='Main']/schematic/Wire[@classid='TLine' or @classid='Cable']")
        defn = PythonCall.pyconvert(String, wrapper.get("defn"))
        wrappers[defn] = get(wrappers, defn, 0) + 1
    end
    modules = Dict{String, Vector{PSCAD.ModulePortPlan}}()
    for definition in root.xpath("./definitions/Definition[@classid='UserCmpDefn'][@name!='Main']")
        name = PythonCall.pyconvert(String, definition.get("name"))
        ports = PSCAD.ModulePortPlan[]
        for port in definition.xpath("./svg/port")
            kind = Symbol(lowercase(PythonCall.pyconvert(String, port.get("mode"))))
            datatype = kind == :electrical ? 0 :
                       parse(Int,
                PythonCall.pyconvert(String,
                    PythonCall.pygetattr(_mhi_xml().SignalType,
                        uppercase(PythonCall.pyconvert(String, port.get("type")))).value))
            push!(ports,
                PSCAD.ModulePortPlan(PythonCall.pyconvert(String, port.get("name")), kind,
                    parse(Int, PythonCall.pyconvert(String, port.get("x"))),
                    parse(Int, PythonCall.pyconvert(String, port.get("y"))),
                    parse(Int, PythonCall.pyconvert(String, port.get("dim"))), datatype))
        end
        modules[name] = ports
    end
    settings = Dict{String, String}()
    for parameter in root.xpath("./paramlist[@name='Settings']/param")
        key = PythonCall.pyconvert(String, parameter.get("name"))
        settings[key] = PythonCall.pyconvert(String, parameter.get("value"))
    end
    return PSCAD.ProjectSummary(counts, labels, pgbs, rows, wrappers, modules, settings,
        PythonCall.pyconvert(String, root.get("version")))
end
