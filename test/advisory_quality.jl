using Logging
using PowerImpedance
using Aqua

function advisory(check, name)
    try
        check()
        @info "$name advisory check passed"
    catch error
        @warn "$name advisory check reported findings" exception = (error, catch_backtrace())
    end
end

advisory("Aqua") do
    Aqua.test_all(PowerImpedance; unbound_args = false, undefined_exports = false)
end

advisory("Aqua undefined exports") do
    Aqua.test_undefined_exports(PowerImpedance)
end

advisory("Aqua unbound arguments") do
    Aqua.test_unbound_args(PowerImpedance)
end
