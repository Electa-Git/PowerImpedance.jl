using PowerImpedance
using Test
using LinearAlgebra

if !isdefined(@__MODULE__, :build_compensated_mmc_grid)
    include("adm_MMC_compensated_test.jl")
end

function mmc_raw_y(model, s)
    A, B, C, D = model.cache.A, model.cache.B, model.cache.C, model.cache.D
    return C * ((s * I - A) \ B) + D
end

# The independent conversion fixes operation order, including floating-point rounding.
function mmc_scaling_before(Y, elec, b)
    Y = copy(Y)
    Y[1, :] .*= b.S / b.v_dc
    Y[2:3, :] .*= 2 * b.S / (3 * b.v_ac)
    Y[:, 1] ./= b.v_dc
    Y[:, 2:3] ./= b.v_ac / elec.turnsRatio
    return Y
end

mmc_scaling_bits(Y) = reinterpret(UInt64, vec(Y))

@testset "Modular MMC physical terminal scaling" begin
    # These constructors and the independent element_y reference are defined
    # by adm_MMC_compensated_test.jl, which precedes this file in runtests.jl.
    network = build_compensated_mmc_grid()
    original = network.elements[:DUT]
    frequencies = ComplexF64.(im .* [2π * 0.1, 2π * 10, 2π * 1000])
    values = original.cache.values
    cached = PowerImpedance.NetworkBuilder.build(original, values, :dq)
    builder_response = zeros(ComplexF64, 3, 3, length(frequencies))
    cached(builder_response, frequencies)
    for (index, s) in enumerate(frequencies)
        reference = element_y(original, s)
        @test PowerImpedance._mmc_si_scale!(mmc_raw_y(original, s), original.elec,
            original.bases) ≈
              reference
        @test builder_response[:, :, index] ≈ reference
    end

    for ratio in (0.5, 320 / 400, 333 / 380, 1.0, 1.25, 2.0)
        model = deepcopy(original)
        elec = model.elec
        fields = ntuple(
            index -> fieldname(typeof(elec), index) == :turnsRatio ? ratio :
                     getfield(elec, index),
            fieldcount(typeof(elec)))
        physical = PowerImpedance.ElectricalMMC(fields...)
        element = PowerImpedance.MMC(model.meas, model.sync, model.delta_control,
            model.sigma_control, model.modulation, physical, model.limits, model.bases,
            model.powerflow, deepcopy(model.cache))
        old_scale = mmc_scaling_before(ones(3, 3), physical, model.bases)
        new_scale = PowerImpedance.SI_scale(element)
        @test mmc_scaling_bits(new_scale[1:1, 1:1]) == mmc_scaling_bits(old_scale[1:1, 1:1])
        @test mmc_scaling_bits(new_scale[2:3, 2:3]) == mmc_scaling_bits(old_scale[2:3, 2:3])
        @test new_scale[1:1, 2:3] ≈ old_scale[1:1, 2:3] ./ ratio
        @test new_scale[2:3, 1:1] ≈ old_scale[2:3, 1:1] .* ratio
        if ratio == 1.0
            @test mmc_scaling_bits(new_scale) == mmc_scaling_bits(old_scale)
        end
        cache = PowerImpedance.freqresp_cache(element.cache.A, element.cache.B,
            element.cache.C, element.cache.D; scale = new_scale)
        response = zeros(ComplexF64, 3, 3, length(frequencies))
        cache(response, frequencies)
        old_cache = PowerImpedance.freqresp_cache(element.cache.A, element.cache.B,
            element.cache.C, element.cache.D; scale = old_scale)
        old_response = similar(response)
        old_cache(old_response, frequencies)
        for (index, s) in enumerate(frequencies)
            raw = mmc_raw_y(element, s)
            before = mmc_scaling_before(raw, physical, model.bases)
            actual = PowerImpedance._mmc_si_scale!(copy(raw), element.elec, element.bases)
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
