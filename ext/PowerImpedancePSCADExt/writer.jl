function PSCAD._write_project(plan::PSCAD.ProjectPlan,
        path::AbstractString)::NamedTuple{(:path, :mhi_xml_version), Tuple{String, String}}
    project = _mhi_xml().ProjectFile.create(String(path))
    main = project.canvas("Main")
    parameters = project.parameters
    for (key, value) in plan.settings.params
        PythonCall.pysetattr(parameters, key, value)
    end
    for component in plan.main.components
        kwargs = (Symbol(key) => value for (key, value) in component.params)
        instance = main.create(component.defn; kwargs...)
        main.add(instance, component.x, component.y, component.orient)
    end
    for wire in plan.main.wires
        a, b = wire.vertices
        main.add_wire(PythonCall.pytuple(a), PythonCall.pytuple(b))
    end
    for line in plan.lines
        write_row_definition!(project, line)
    end
    for wrapper in plan.wrappers
        write_line_wrapper!(main, plan.name, wrapper)
    end
    project.save()
    return (path = abspath(path), mhi_xml_version = _mhi_xml_version())
end
