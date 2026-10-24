using PowerImpedance
using Test
using LinearAlgebra

# The independent conversion fixes operation order, including floating-point rounding.
function mmc_scaling_before(Y, elec)
    Y = copy(Y)
    Y[1, :] .*= elec.Sbase / elec.vDC_base
    Y[2:3, :] .*= 2 * elec.Sbase / (3 * elec.vAC_base)
    Y[:, 1] ./= elec.vDC_base
    Y[:, 2:3] ./= elec.vAC_base / elec.turnsRatio
    return Y
end

mmc_scaling_bits(Y) = reinterpret(UInt64, vec(Y))

@testset "Modular MMC physical terminal scaling" begin
    # These constructors and the independent element_y reference are defined
    # by adm_MMC_compensated_test.jl, which precedes this file in runtests.jl.
    network = build_mmc_grid()
    original = network.elements[:DUT]
    frequencies = ComplexF64.(im .* [2π * 0.1, 2π * 10, 2π * 1000])
    cached = PowerImpedance.NetworkBuilder.build(original, original.setpoint)
    builder_response = zeros(ComplexF64, 3, 3, length(frequencies))
    cached(builder_response, frequencies)
    for (index, s) in enumerate(frequencies)
        reference = element_y(original, s)
        @test PowerImpedance.get_y(original, s) ≈ reference
        @test builder_response[:, :, index] ≈ reference
    end

    for ratio in (0.5, 320 / 400, 333 / 380, 1.0, 1.25, 2.0)
        element = deepcopy(original)
        model = element.element_model
        elec = model.elec
        fields = ntuple(
            index -> fieldname(typeof(elec), index) == :turnsRatio ? ratio :
                     getfield(elec, index),
            fieldcount(typeof(elec)))
        physical = PowerImpedance.ElectricalMMC(fields...)
        element.element_model = PowerImpedance.MMC(model.meas, model.sync,
            model.delta_control, model.sigma_control, model.modulation, physical,
            model.limits, model.powerflow, PowerImpedance.LinearizationCache())
        old_scale = mmc_scaling_before(ones(3, 3), physical)
        new_scale = PowerImpedance.SI_scale(element)
        @test mmc_scaling_bits(new_scale[1:1, 1:1]) == mmc_scaling_bits(old_scale[1:1, 1:1])
        @test mmc_scaling_bits(new_scale[2:3, 2:3]) == mmc_scaling_bits(old_scale[2:3, 2:3])
        @test new_scale[1:1, 2:3] ≈ old_scale[1:1, 2:3] ./ ratio
        @test new_scale[2:3, 1:1] ≈ old_scale[2:3, 1:1] .* ratio
        if ratio == 1.0
            @test mmc_scaling_bits(new_scale) == mmc_scaling_bits(old_scale)
        end
        cache = PowerImpedance.freqresp_cache(element.A, element.B,
            element.C, element.D; scale = new_scale)
        response = zeros(ComplexF64, 3, 3, length(frequencies))
        cache(response, frequencies)
        old_cache = PowerImpedance.freqresp_cache(element.A, element.B,
            element.C, element.D; scale = old_scale)
        old_response = similar(response)
        old_cache(old_response, frequencies)
        for (index, s) in enumerate(frequencies)
            raw = PowerImpedance.eval_y(element, s; SI_units = false)
            before = mmc_scaling_before(raw, physical)
            actual = PowerImpedance.get_y(element, s)
            reference = element_y(element, s)
            @test mmc_scaling_bits(response[1:1, 1:1, index]) ==
                  mmc_scaling_bits(old_response[1:1, 1:1, index])
            @test mmc_scaling_bits(response[2:3, 2:3, index]) ==
                  mmc_scaling_bits(old_response[2:3, 2:3, index])
            @test actual ≈ reference
            @test response[:, :, index] ≈ reference
            @test mmc_scaling_bits(actual[1:1, 1:1]) == mmc_scaling_bits(before[1:1, 1:1])
            @test mmc_scaling_bits(actual[2:3, 2:3]) == mmc_scaling_bits(before[2:3, 2:3])
            @test actual[1:1, 2:3] ≈ before[1:1, 2:3] ./ ratio
            @test actual[2:3, 1:1] ≈ before[2:3, 1:1] .* ratio
            if ratio == 1.0
                @test mmc_scaling_bits(actual) == mmc_scaling_bits(before)
                @test mmc_scaling_bits(response[:, :, index]) ==
                      mmc_scaling_bits(old_response[:, :, index])
            end
        end
    end
end
