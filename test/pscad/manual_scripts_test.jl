module PSCADManualScriptTests
using Test, PowerImpedance

# Inspect source syntax only: macros are checked, never expanded. The walker
# covers the binding forms used by these scripts and their regression examples.
function bind!(bound, expression)
    if expression isa Symbol
        push!(bound, expression)
    elseif expression isa Expr
        if expression.head in (:tuple, :parameters)
            foreach(argument -> bind!(bound, argument), expression.args)
        elseif expression.head in (:(::), :kw, :(=), :(...))
            bind!(bound, first(expression.args))
        end
    end
    return bound
end

function definitions!(bound, expression)
    expression isa Expr || return bound
    if expression.head in (:(=), :function)
        target = first(expression.args)
        if target isa Expr && target.head == :call
            bind!(bound, first(target.args))
        else
            bind!(bound, target)
        end
    elseif expression.head == :struct
        bind!(bound,expression.args[2])
    elseif expression.head in
           (:toplevel, :block, :if, :elseif, :try, :const, :global, :local)
        foreach(argument -> definitions!(bound, argument), expression.args)
    end
    return bound
end

function unresolved_globals(expression, namespace)
    missing = Set{Symbol}()

    function annotations(target, bound)
        target isa Expr || return
        if target.head in (:(::), :kw, :(=))
            annotations(first(target.args), bound)
            foreach(argument -> visit(argument, bound), target.args[2:end])
        elseif target.head in (:tuple, :parameters, :(...))
            foreach(argument -> annotations(argument, bound), target.args)
        end
    end

    function visit(node, bound)
        if node isa Symbol
            reference = Base.isoperator(node) && startswith(string(node), ".") ?
                        Symbol(string(node)[2:end]) : node
            reference in bound || isdefined(namespace, reference) ||
                push!(missing, reference)
        elseif node isa Expr
            head, arguments = node.head, node.args
            if head in (:error, :incomplete)
                error("Invalid script syntax: $(first(arguments))")
            elseif head in (:using, :import, :quote)
                return
            elseif head == :.
                # Property names are QuoteNodes; computed/broadcast arguments
                # still contain references that must be checked.
                foreach(argument -> visit(argument, bound), arguments)
            elseif head == :kw
                visit(last(arguments), bound)
            elseif head == :ref
                visit(first(arguments), bound)
                inner = union(copy(bound), Set([:begin, :end]))
                foreach(argument -> visit(argument, inner), arguments[2:end])
            elseif head == :tuple
                for argument in arguments
                    if argument isa Expr && argument.head == :(=)
                        visit(last(argument.args), bound) # Named-tuple label.
                    else
                        visit(argument, bound)
                    end
                end
            elseif head == :module
                child = getfield(namespace, arguments[2])
                union!(missing, unresolved_globals(last(arguments), child))
            elseif head == :struct
                visit(arguments[2],bound)
                inner=union(copy(bound),Set([:new]))
                for field in last(arguments).args
                    if field isa Symbol || field isa Expr && field.head==:(::)
                        annotations(field,inner)
                    else
                        visit(field,inner)
                    end
                end
            elseif head == :try
                visit(arguments[1], bound)
                inner = copy(bound)
                arguments[2] isa Symbol && bind!(inner, arguments[2])
                visit(arguments[3], inner)
                foreach(argument -> visit(argument, bound), arguments[4:end])
            elseif head == :function ||
                   (head == :(=) && first(arguments) isa Expr &&
                    first(arguments).head == :call)
                signature, body = arguments
                inner = definitions!(copy(bound), body)
                foreach(argument -> bind!(inner, argument), signature.args[2:end])
                visit(first(signature.args), bound)
                foreach(argument -> annotations(argument, inner), signature.args[2:end])
                visit(body, inner)
            elseif head == :->
                parameters, body = arguments
                inner = definitions!(bind!(copy(bound), parameters), body)
                annotations(parameters, inner)
                visit(body, inner)
            elseif head in (:for, :generator)
                bindings, body = head == :for ? arguments :
                                 (arguments[2:end], first(arguments))
                inner = copy(bound)
                iterations = bindings isa Vector ? bindings :
                             bindings isa Expr && bindings.head == :block ? bindings.args :
                             [bindings]
                for binding in iterations
                    binding isa LineNumberNode && continue
                    if binding.head == :filter
                        for iteration in binding.args[2:end]
                            visit(last(iteration.args), inner)
                            bind!(inner, first(iteration.args))
                        end
                        visit(first(binding.args), inner)
                    else
                        visit(last(binding.args), inner)
                        bind!(inner, first(binding.args))
                    end
                end
                visit(body, definitions!(inner, body))
            elseif head == :(=)
                target, value = arguments
                if target isa Expr && target.head in (:ref, :.)
                    visit(target, bound)
                else
                    annotations(target, bound)
                end
                visit(value, bound)
            else
                # Includes macro names and arguments, keyword shorthand,
                # string interpolation, calls, and do-block lambdas.
                foreach(argument -> visit(argument, bound), arguments)
            end
        end
    end

    # Imports evaluated above may create world-aged bindings on Julia 1.12.
    Base.invokelatest(visit, expression, definitions!(Set{Symbol}(), expression))
    return sort!(collect(missing); by = string)
end

function script_namespace(expression, path)
    namespace = Module(:ManualPSCADScript)
    Core.eval(namespace, :(include(path) = Base.include($namespace, path)))
    for statement in expression.args
        statement isa Expr || continue
        if statement.head == :using
            for dependency in statement.args
                # PythonCall supplies none of these scripts' identifiers and remains
                # unloaded for offline extension tests. Every reference must resolve
                # through the other imports and fixtures; an unresolved name fails the
                # test.
                dependency == Expr(:., :PythonCall) && continue
                Core.eval(namespace, Expr(:using, dependency))
            end
        elseif statement.head == :call && first(statement.args) == :include
            fixture = only(statement.args[2:end])
            fixture isa String || error("Expected a literal fixture include in $path")
            Base.include(namespace, normpath(joinpath(dirname(path), fixture)))
        end
    end
    return namespace
end

@testset "PSCAD manual script globals" begin
    directory = normpath(joinpath(@__DIR__, "../manual/pscad"))
    validation_directory = joinpath(directory, "validation")
    validation_parent = Module(:ValidationManualScripts)
    Base.include(validation_parent, joinpath(validation_directory, "validation.jl"))
    paths = [joinpath(root, file) for (root, _, files) in walkdir(directory)
             for file in files
             if endswith(file, ".jl") && !occursin(joinpath("validation", "data"), root)]
    for path in sort(paths)
        endswith(path, ".jl") || continue
        source = read(path, String)
        expression = Meta.parseall(source; filename = path)
        namespace = if dirname(path) == validation_directory &&
                       basename(path) ∉ ("prepare.jl", "run_station.jl", "check_projects.jl", "reanalyse.jl")
            basename(path) == "validation.jl" ? validation_parent :
            getfield(validation_parent, :PSCADValidation)
        else
            script_namespace(expression, path)
        end
        @testset "$(basename(path))" begin
            @test isempty(unresolved_globals(expression, namespace))
            if basename(path) == "acceptance.jl"
                for name in ("SimulationSettings", "steady_state")
                    qualified = "PowerImpedance.PSCAD.$name"
                    @test occursin(qualified, source)
                    original = Meta.parseall(replace(source, qualified => name))
                    @test unresolved_globals(original, namespace) == [Symbol(name)]
                end
                @testset "Acceptance continues after run and comparison failures" begin
                    loop = only(filter(expression.args) do statement
                        statement isa Expr && statement.head == :for &&
                            last(statement.args[1].args) == :cases
                    end)
                    harness = Module(:AcceptanceFailureTest)
                    Core.eval(harness, :(const PowerImpedance = $PowerImpedance))
                    Core.eval(harness, quote
                        failures = Pair{String, String}[]
                        attempted = String[]
                        remote = nothing
                        exports = mktempdir()
                        cases = [( (; project_name = name,
                            netlist = (; elements = [], buses = []),
                            operating_point = (; bus_states = Dict())), nothing, 0.01)
                            for name in ("run_error", "first_pass", "comparison_error", "last_pass")]
                        PSCADRun() = nothing
                        function compute(model, run; options)
                            push!(attempted, model.project_name)
                            model.project_name == "run_error" && error("recorded build failure")
                            return model.project_name
                        end
                        function compare_operating_point(result, reference; rtol_v)
                            return PowerImpedance.PSCAD.Table((;
                                quantity = ["voltage"], name = [result],
                                pscad = [1.0], powerflow = [1.0], error = [0.0],
                                within_tolerance = [result != "comparison_error"]))
                        end
                    end)
                    redirect_stdout(devnull) do
                        redirect_stderr(devnull) do
                            Core.eval(harness, loop)
                        end
                    end
                    @test harness.attempted ==
                        ["run_error", "first_pass", "comparison_error", "last_pass"]
                    @test first.(harness.failures) == ["run_error", "comparison_error"]
                    @test occursin("recorded build failure", first(harness.failures).second)
                    @test occursin("PSCAD acceptance failed", last(harness.failures).second)
                    @test isfile(joinpath(harness.exports, "last_pass_comparison.tsv"))
                    rm(harness.exports; recursive = true)
                    final_verdict = last(filter(s -> s isa Expr, expression.args))
                    code = "failures = [\"failed_case\" => \"recorded failure\"]\n" *
                           string(final_verdict)
                    child = run(pipeline(`$(Base.julia_cmd()) --startup-file=no -e $code`;
                        stdout = devnull, stderr = devnull); wait = false)
                    wait(child)
                    @test child.exitcode == 1
                end
            elseif basename(path) == "acceptance_networks.jl"
                # Evaluate only the message classifier, never exports or runs.
                definition = only(filter(
                    statement -> statement isa Expr &&
                                 statement.head == :function &&
                                 first(first(statement.args).args) == :build_verdict,
                    expression.args))
                Core.eval(namespace, definition)
                verdict(text) = Base.invokelatest(getproperty(namespace, :build_verdict), text)
                licence = "error\tbuild\t\tThe current license is limited to a maximum of 200 electrical nodes. This project contains 528 electrical nodes.\n"
                normal = "normal\tbuild\t\tThe total number of live nodes: 528\n"
                summary = "normal\tbuild\t\t======== Build: 1 errors, 0 warnings ========\n"
                @testset "network licence build verdict" begin
                    @test verdict(normal * licence * summary) ==
                          "export verified (licence-blocked)"
                    @test verdict(licence * normal * summary) ==
                          "export verified (licence-blocked)"
                    @test verdict(normal * summary * licence) ==
                          "export verified (licence-blocked)"
                    @test verdict(normal * licence * summary *
                                  "warning\tbuild\t\tUnexpected warning\n") == "fail"
                    @test verdict(normal * licence * summary *
                                  "error\tbuild\t\tUnrelated build error\n") == "fail"
                    @test verdict(normal * licence * licence * summary) == "fail"
                    @test verdict(normal * summary) == "fail"
                    @test verdict(normal * licence) == "fail"
                    @test verdict(replace(normal * licence * summary,
                        "0 warnings" => "1 warnings")) == "fail"
                    @test verdict(normal * licence * summary *
                                  replace(summary, "0 warnings" => "1 warnings")) == "fail"
                    @test verdict(replace(normal * licence * summary,
                        "The current license is limited" => "Another error: The current license is limited")) ==
                          "fail"
                    @test verdict("error\tbuild\n" * licence * summary) == "fail"
                    @test verdict("") == "fail"
                end
            elseif dirname(path) == validation_directory &&
                   basename(path) == "run_station.jl"
                original = Meta.parseall(replace(source, "PSCADValidation.run_fixture" => "run_fixture"))
                @test unresolved_globals(original, namespace) == [:run_fixture]
            end
        end
    end

    namespace = Module(:ManualSyntaxFixture)
    @testset "Syntax and local bindings" begin
        valid = Meta.parseall("""
            function diagnostic(record; label = :voltage)
                value = record.mean
                @show label value
                return abs(value)
            end
            local_diagnostic(record) = diagnostic(record; label = :current)
            records = [(mean = 1.0,)]
            for (index, record) in enumerate(records)
                map(records) do item
                    local_diagnostic(item)
                end
                filter(item -> item.mean > 0, records)
                local_diagnostic(record)
            end
            options = (; records, field_label = :value)
            text = raw"field"
            """)
        @test isempty(unresolved_globals(valid, namespace))
        for source in ("[(n, side) for n in 1:2 for side in 1:n]",
            "Dict(n => side for n in 1:2, side in 1:n)",
            "[n for n in 1:2 if n > 1]", "[1,2][begin:end] .+ [3,4]",
            "try; values = [1,2]; values[end]; catch failure; sprint(showerror, failure); end",
            "struct LocalRecord; value::Float64; label::String; end")
            @test isempty(unresolved_globals(Meta.parseall(source), namespace))
        end
        for (source, names) in (
            ("@missing_macro abs(unknown)", [Symbol("@missing_macro"), :unknown]),
            ("abs(1; keyword_label = unknown)", [:unknown]),
            ("(; keyword_label = unknown)", [:unknown]),
            ("unknown.field_name", [:unknown]),
            ("f(x) = missing_function(x)", [:missing_function]),
            ("function f(x); x; end; x", [:x]),
            ("for x in 1:2; y = x; end; y", [:y]),
            ("[n + unknown for n in 1:2]", [:unknown]),
            ("[n for n in 1:2 if missing_function(n)]", [:missing_function]),
            ("[n for n in 1:2]; n", [:n]),
            ("struct LocalRecord; value::UnknownType; end", [:UnknownType]),
            ("struct LocalRecord; value::Float64; end; value", [:value]))
            @test unresolved_globals(Meta.parseall(source), namespace) == names
        end
    end
end
end
