function write_parameter!(category, parameter::PSCAD.ModuleParameterPlan{Float64})
    return category.add_real(parameter.name, parameter.name; default = parameter.default,
        unit = parameter.unit, content_type = "Constant", intent = "Input",
        min = -1e308, max = 1e308, group = "", cond = "", help = "", vis = "")
end

function write_parameter!(category, parameter::PSCAD.ModuleParameterPlan{Int})
    return category.add_integer(
        parameter.name, parameter.name; default = parameter.default,
        content_type = "Constant", intent = "Input", min = typemin(Int32),
        max = typemax(Int32), group = "", cond = "", help = "", vis = "")
end

function write_parameter!(category, parameter::PSCAD.ModuleParameterPlan{String})
    return category.add_text(parameter.name, parameter.name; default = parameter.default,
        intent = "Input", min = 0, max = 0, group = "", cond = "", help = "", vis = "")
end

function write_port!(svg, port, ::Val{:input})
    etree = PythonCall.pyimport("lxml.etree")
    node = etree.SubElement(svg, "port"; model = "Transfer", name = port.name,
        x = string(port.x), y = string(port.y), dim = string(port.dim),
        mode = "Input", type = _mhi_xml().SignalType(port.datatype).name.title(),
        internal = "false")
    PythonCall.pysetattr(node, "text", etree.CDATA("true"))
    return nothing
end
function write_port!(svg, port, ::Val{:output})
    etree = PythonCall.pyimport("lxml.etree")
    node = etree.SubElement(svg, "port"; model = "Transfer", name = port.name,
        x = string(port.x), y = string(port.y), dim = string(port.dim),
        mode = "Output", type = _mhi_xml().SignalType(port.datatype).name.title(),
        internal = "false")
    PythonCall.pysetattr(node, "text", etree.CDATA("true"))
    return nothing
end
function write_port!(svg, port, ::Val{:electrical})
    etree = PythonCall.pyimport("lxml.etree")
    node = etree.SubElement(svg, "port"; model = "Natural", name = port.name,
        x = string(port.x), y = string(port.y), dim = string(port.dim),
        mode = "Electrical", type = "NonRemovable", internal = "false")
    PythonCall.pysetattr(node, "text", etree.CDATA("true"))
    return nothing
end

function write_component!(project, canvas, component::PSCAD.ComponentPlan)
    kwargs = (Symbol(key) => value for (key, value) in component.params)
    instance = canvas.create(component.defn; kwargs...)
    canvas.add(instance, component.x, component.y, component.orient)
    return nothing
end

function write_component!(project, canvas, component::PSCAD.ModuleInstancePlan)
    definition = project.definition[last(split(component.defn, ':'))]
    kwargs = (Symbol(key) => value for (key, value) in component.params)
    definition.create_instance(canvas, component.x ÷ 18, component.y ÷ 18,
        component.orient; kwargs...)
    return nothing
end

function write_sheet_size!(canvas)
    # Native load/build experiments (diag/relo): size 0 clamped meters at
    # y=3168 to 3150; preset size 5 retained all origins with zero build errors.
    settings = canvas.find("paramlist")
    sizes = settings.findall("param[@name='size']")
    if PythonCall.pylen(sizes) == 0
        PythonCall.pyimport("lxml.etree").SubElement(settings, "param"; name = "size", value = "5")
    else
        for size in sizes
            size.set("value", "5")
        end
    end
    return nothing
end

function write_canvas!(project, canvas, plan::PSCAD.CanvasPlan)
    for component in plan.components
        write_component!(project, canvas, component)
    end
    for wire in plan.wires
        a, b = wire.vertices
        canvas.add_wire(PythonCall.pytuple(a), PythonCall.pytuple(b))
    end
    return nothing
end

function write_module_definition!(project, plan::PSCAD.ModuleDefinitionPlan)
    definition = project.definition.create(plan.name)
    definition.module = true
    category = definition.form.category.create("Configuration")
    for parameter in plan.parameters
        node = write_parameter!(category, parameter)
        PythonCall.pysetattr(node, "help_mode", "Append")
        # Scalar dimension has no parameter API option.
        node.set("dim", "1")
    end
    # The graphics API emits the older Port/paramlist format. PSCAD 5 uses SVG.
    etree = PythonCall.pyimport("lxml.etree")
    svg = etree.Element("svg"; viewBox = "-200 -200 200 200", size = "4")
    for port in plan.ports
        write_port!(svg, port, Val(port.kind))
    end
    PythonCall.pysetattr(etree.SubElement(svg, "cond"), "text", etree.CDATA("true"))
    height = max(72, maximum(p -> p.y, plan.ports; init = 0) + 72)
    etree.SubElement(
        svg, "rect"; x = "-54", y = "-36", width = "108", height = string(height),
        stroke = "Black", (Symbol("stroke-width") => "0.2",
            Symbol("stroke-dasharray") => "none", Symbol("fill-style") => "Hollow",
            Symbol("fill-fg") => "Black", Symbol("fill-bg") => "")...)
    label = etree.SubElement(svg, "text"; x = "0", y = "-18", stroke = "Black",
        (Symbol("font-size") => "small", Symbol("text-anchor") => "Middle")...)
    PythonCall.pysetattr(label, "text", etree.CDATA(plan.name))
    definition.replace(definition.find("graphics"), svg)
    # Retain explicit saved canvas settings instead of relying on load defaults:
    # local/TLC/Simple_2L_VSC_RL.pscx:2069–2083 (dq2abc), and
    # local/SG/SG_Project.pscx:978–992 (the machine module).
    settings = definition.schematic.find("paramlist")
    for (key, value) in (("show_grid", "1"), ("size", "5"), ("orient", "1"),
        ("show_border", "0"), ("monitor_bus_voltage", "0"), ("show_signal", "0"),
        ("show_virtual", "0"), ("show_sequence", "0"), ("auto_sequence", "1"),
        ("show_terminals", "0"), ("virtual_filter", ""), ("animation_freq", "500"))
        etree.SubElement(settings, "param"; name = key, value)
    end
    write_canvas!(project, definition.schematic, plan.canvas)
    return nothing
end

function PSCAD._write_project(plan::PSCAD.ProjectPlan,
        path::AbstractString)::NamedTuple{(:path, :mhi_xml_version), Tuple{String, String}}
    PSCAD.check_connectivity(plan)
    project = _mhi_xml().ProjectFile.create(String(path))
    main = project.canvas("Main")
    parameters = project.parameters
    for (key, value) in plan.settings.params
        PythonCall.pysetattr(parameters, key, value)
    end
    for definition in plan.modules
        write_module_definition!(project, definition)
    end
    write_canvas!(project, main, plan.main)
    for line in plan.lines
        write_row_definition!(project, line)
    end
    for wrapper in plan.wrappers
        write_line_wrapper!(main, plan.name, wrapper)
    end
    for canvas in main.getroottree().findall("./definitions/Definition/schematic")
        write_sheet_size!(canvas)
    end
    project.save()
    PSCAD.check_geometry(path)
    PSCAD.check_connectivity(path)
    return (path = abspath(path), mhi_xml_version = _mhi_xml_version())
end
