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

# PSCAD can relocate a meter on load while its wire endpoint remains in
# place, so connectivity checks also use the saved coordinates.
function PSCAD.check_connectivity(path::AbstractString)
    root = PythonCall.pyimport("lxml.etree").parse(String(path)).getroot()
    summary = PSCAD.read_project_summary(path)
    canvases = Dict{String, PSCAD.CanvasPlan}()
    modules = Dict{String, PSCAD.ModuleDefinitionPlan}()
    text(node, key) = PythonCall.pyconvert(String, node.get(key))
    integer(node, key) = parse(Int, text(node, key))
    for definition in root.xpath("./definitions/Definition[@classid='UserCmpDefn']")
        name = text(definition, "name")
        canvas = PSCAD.CanvasPlan()
        for node in definition.xpath("./schematic/User")
            params = [text(p, "name") => text(p, "value")
                      for p in node.xpath("./paramlist/param")]
            defn = text(node, "defn")
            constructor = startswith(defn, "master:") || startswith(defn, "Z_tool:") ?
                          PSCAD.ComponentPlan : PSCAD.ModuleInstancePlan
            push!(canvas.components, constructor(defn, params,
                integer(node, "x"), integer(node, "y"), integer(node, "orient")))
        end
        for node in definition.xpath("./schematic/Wire[@classid='WireOrthogonal']")
            x, y = integer(node, "x"), integer(node, "y")
            vertices = [(x + integer(v, "x"), y + integer(v, "y"))
                        for v in node.xpath("./vertex")]
            push!(canvas.wires, PSCAD.WirePlan(vertices))
        end
        # Remote cable and line wrappers use graphical vertices. Direct line
        # wrappers use their first and last vertices as electrical terminals.
        for node in definition.xpath("./schematic/Wire[@classid='TLine']")
            mode = PythonCall.pyconvert(String,
                node.xpath("string(./User/paramlist/param[@name='Mode']/@value)"))
            mode == "1" || continue
            defn = text(node, "defn")
            row = last(split(defn, ':'))
            vertices = collect(node.xpath("./vertex"))
            length(vertices) >= 2 || throw(ArgumentError("direct line wrapper requires two terminals"))
            ports = [PSCAD.ModulePortPlan("sending", :electrical,
                integer(first(vertices), "x"), integer(first(vertices), "y")),
                PSCAD.ModulePortPlan("receiving", :electrical,
                    integer(last(vertices), "x"), integer(last(vertices), "y"))]
            modules[row] = PSCAD.ModuleDefinitionPlan(row, PSCAD.ModuleParameterPlan[], ports, PSCAD.CanvasPlan())
            push!(canvas.components, PSCAD.ModuleInstancePlan(defn, Pair{String, String}[],
                integer(node, "x"), integer(node, "y"), integer(node, "orient")))
        end
        canvases[name] = canvas
        name == "Main" || (modules[name] = PSCAD.ModuleDefinitionPlan(name,
            PSCAD.ModuleParameterPlan[], summary.modules_and_ports[name], canvas))
    end
    for (name, canvas) in canvases
        PSCAD.check_connectivity(canvas, name, modules)
    end
    return nothing
end

function PSCAD.check_geometry(path::AbstractString)
    root = PythonCall.pyimport("xml.etree.ElementTree").parse(String(path)).getroot()
    text(node, key) = PythonCall.pyconvert(String, node.get(key))
    integer(node, key) = parse(Int, text(node, key))
    for definition in root.findall("./definitions/Definition")
        name = text(definition, "name")
        for canvas in definition.findall("schematic")
            sizes = canvas.findall("./paramlist/param[@name='size']")
            PythonCall.pylen(sizes) == 1 && text(sizes[0], "value") == "5" ||
                throw(ArgumentError("PSCAD canvas $name requires sheet size 5"))
            for node in canvas
                PythonCall.pyis(node.get("x"), PythonCall.pybuiltins.None) && continue
                x, y = integer(node, "x"), integer(node, "y")
                PSCAD._check_coordinate((x, y), name)
                defn = PythonCall.pyconvert(String, node.get("defn", ""))
                if defn in ("Z_tool:ACscan", "Z_tool:DCscan")
                    component = PSCAD.ComponentPlan(defn, Pair{String, String}[],
                        x, y, integer(node, "orient"))
                    for (point, _, _) in PSCAD.component_ports(component, Dict())
                        PSCAD._check_coordinate(point, name)
                    end
                end
                for vertex in node.findall("vertex")
                    PSCAD._check_coordinate((x + integer(vertex, "x"),
                        y + integer(vertex, "y")), name)
                end
            end
        end
    end
    return nothing
end
