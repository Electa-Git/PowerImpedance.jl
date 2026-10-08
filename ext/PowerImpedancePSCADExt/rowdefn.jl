function row_parameter_value(parameters_type, key, value)
    kind = PythonCall.pygetattr(parameters_type, key).kind
    if PythonCall.pyisinstance(kind, PythonCall.pyimport("mhi.xml.pscad.types").Choice)
        # The IR retains the XML code. MHI's typed setter expects its decoded
        # choice (for example, CDataType="1" means "direct").
        return kind(value)
    end
    return value
end

function write_row_definition!(project, line::PSCAD.LineDefinitionPlan)
    line.kind == :tline ||
        throw(ArgumentError("PSCAD row kind $(line.kind) is not implemented yet"))
    row = project.definition.create_tline(line.name)
    tower_type = PythonCall.pyimport("mhi.xml.pscad.twm_types").TowerUniversal.Parameters
    kwargs = (Symbol(key) => row_parameter_value(tower_type, key, value)
    for (key, value) in line.tower)
    row.tower_universal(0.0,
        PythonCall.pylist(PythonCall.pytuple.(line.conductors)),
        PythonCall.pylist(PythonCall.pytuple.(line.ground_wires)); kwargs...)
    # These are component properties, not component-creation methods.
    for (component, params) in ((row.ground, line.ground),
        (row.freq_phase_options, line.frephase), (row.additional_options, line.outdisp))
        parameters = component.parameters
        parameters_type = PythonCall.pytype(parameters)
        for (key, value) in params
            PythonCall.pysetattr(parameters, key,
                row_parameter_value(parameters_type, key, value))
        end
    end
    return nothing
end

function write_tline_wrapper!(main, namespace, wrapper::PSCAD.TLineWrapperPlan)
    etree = PythonCall.pyimport("lxml.etree")
    random = PythonCall.pyimport("random")
    qualified = namespace * ":" * wrapper.row
    # Match the direct-connection wrapper verified by station spike B.
    wire = etree.Element("Wire"; classid = "TLine",
        id = string(PythonCall.pyconvert(Int, random.randrange(100_000_000, 1_000_000_000))),
        name = qualified, x = string(wrapper.x), y = string(wrapper.y),
        w = "121", h = "68", orient = "0", disable = "false", defn = qualified,
        recv = "-1", send = "-1", back = "-1", crc = "0")
    for (x, y) in ((-54, 18), (-54, 36), (54, 54), (54, 72))
        etree.SubElement(wire, "vertex"; x = string(x), y = string(y))
    end
    user = etree.SubElement(wire, "User"; classid = "UserCmp",
        id = string(PythonCall.pyconvert(Int, random.randrange(100_000_000, 1_000_000_000))),
        name = qualified, x = "0", y = "0", w = "0", h = "0", z = "-1",
        orient = "0", defn = qualified, link = "-1", q = "4", disable = "false")
    params = etree.SubElement(user, "paramlist"; name = "", link = "-1", crc = "0")
    for (key, value) in wrapper.params
        etree.SubElement(params, "param"; name = key, value)
    end
    main.append_indented(main._parse(etree.tostring(wire; encoding = "unicode")))
    return nothing
end
