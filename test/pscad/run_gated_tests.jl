# Offline runner, responsiveness-probe and lifecycle protocols. No station connection.
# `julia --project test/pscad/run_gated_tests.jl`
using Pkg

mktempdir(; prefix = "powerimpedance-pscad-protocol-") do environment
    Pkg.activate(environment)
    Pkg.add([Pkg.PackageSpec(name = "PythonCall", version = "0.9"),
        Pkg.PackageSpec(name = "TOML"), Pkg.PackageSpec(name = "Test")])
    python = get(ENV, "JULIA_PYTHONCALL_EXE", something(Sys.which("python3"), ""))
    isempty(python) && error("runner protocol tests require a local Python interpreter")
    powershell = get(ENV, "POWERIMPEDANCE_PSCAD_TEST_POWERSHELL",
        something(Sys.which("pwsh"), Sys.which("powershell"), ""))
    protocol = joinpath(@__DIR__, "remote_runner_protocol.jl")
    withenv("JULIA_CONDAPKG_BACKEND" => "Null", "JULIA_PYTHONCALL_EXE" => python,
        "POWERIMPEDANCE_PSCAD_TEST_POWERSHELL" => powershell) do
        run(`$(Base.julia_cmd()) --startup-file=no --project=$environment $protocol`)
    end
end
