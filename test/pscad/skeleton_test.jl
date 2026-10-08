using Test
using PowerImpedance

@testset "PSCAD skeleton" begin
    pscad = PowerImpedance.PSCAD
    @test pscad.PSCAD_VERSION == "5.1.0"
    @test pscad.PROJECT_FILE_VERSION == "5.0.2"
    @test pscad.PSCADBackend() isa pscad.PSCADBackend

    if Base.get_extension(PowerImpedance, :PowerImpedancePSCADExt) === nothing
        error = try
            pscad._require_extension()
        catch exception
            exception
        end
        @test error isa ArgumentError
        @test occursin("using PythonCall", sprint(showerror, error))
    end
end
