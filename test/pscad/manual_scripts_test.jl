module PSCADManualScriptTests
using Test

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
    elseif expression.head in (:toplevel, :block, :if, :elseif, :const, :global, :local)
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
            node in bound || isdefined(namespace, node) || push!(missing, node)
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
            elseif head == :tuple
                for argument in arguments
                    if argument isa Expr && argument.head == :(=)
                        visit(last(argument.args), bound) # Named-tuple label.
                    else
                        visit(argument, bound)
                    end
                end
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
            elseif head == :for
                bindings, body = arguments
                inner = copy(bound)
                iterations = bindings isa Expr && bindings.head == :block ?
                             bindings.args : [bindings]
                for binding in iterations
                    binding isa LineNumberNode && continue
                    visit(last(binding.args), inner)
                    bind!(inner, first(binding.args))
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
                # PythonCall is unused as a source of identifiers in these
                # scripts. Leave it unloaded to preserve offline extension
                # tests; every reference must resolve through the other imports
                # and fixtures, so an unverified name still fails this guard.
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
    for path in sort(readdir(directory; join = true))
        endswith(path, ".jl") || continue
        source = read(path, String)
        expression = Meta.parseall(source; filename = path)
        namespace = script_namespace(expression, path)
        @testset "$(basename(path))" begin
            @test isempty(unresolved_globals(expression, namespace))
            if basename(path) == "acceptance.jl"
                for name in ("SimulationSettings", "steady_state")
                    qualified = "PowerImpedance.PSCAD.$name"
                    @test occursin(qualified, source)
                    original = Meta.parseall(replace(source, qualified => name))
                    @test unresolved_globals(original, namespace) == [Symbol(name)]
                end
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
        for (source, names) in (
            ("@missing_macro abs(unknown)", [Symbol("@missing_macro"), :unknown]),
            ("abs(1; keyword_label = unknown)", [:unknown]),
            ("(; keyword_label = unknown)", [:unknown]),
            ("unknown.field_name", [:unknown]),
            ("f(x) = missing_function(x)", [:missing_function]),
            ("function f(x); x; end; x", [:x]),
            ("for x in 1:2; y = x; end; y", [:y]))
            @test unresolved_globals(Meta.parseall(source), namespace) == names
        end
    end
end
end
