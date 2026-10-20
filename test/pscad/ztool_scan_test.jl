module PSCADZToolScanTests
using Test, PowerImpedance
const P = PowerImpedance.PSCAD

@testset "Z-tool sweep arguments and SI defaults" begin
    scan = ZToolScan()
    settings = P.SimulationSettings()
    arguments = P._ztool_arguments(scan, settings)
    @test scan isa AbstractFormulation
    @test scan.backend === P.PSCADBackend
    @test scan.frequencies === nothing
    @test (scan.f_min, scan.f_max, scan.f_points, scan.f_base) == (1.0, 1000.0, 80, 1.0)
    @test arguments["t_step"] == 10.0
    @test arguments["sample_step"] == 100.0
    @test arguments["t_snap"] == settings.simulation_time
    @test arguments["start_fft"] == arguments["dt_injections"] == 1.0
    @test arguments["t_sim"] == 2.0
    @test arguments["fft_periods"] == arguments["num_parallel_sim"] == 1
    @test arguments["v_perturb_mag"] == 0.01
    @test arguments["multi_freq_scan"] === false
    @test !haskey(arguments, "freq")
    @test P._ztool_arguments(scan, P.SimulationSettings(snapshot_time = 0.5))["t_snap"] == 0.5
    explicit = ZToolScan(frequencies = collect(0.5:0.5:8), f_base = 0.5,
        snapshot_time = 3, start_fft = 2, fft_periods = 2, injection_interval = 0,
        perturbation = 0.001, multi_frequency = true, time_step = 1e-6,
        sample_step = 25e-6, num_parallel_sim = 2)
    args = P._ztool_arguments(explicit, settings)
    @test args["freq"] == collect(0.5:0.5:8)
    @test !haskey(args, "f_min")
    @test args["f_base"] == 0.5
    @test args["t_snap"] == 3.0
    @test args["t_step"] == 1.0
    @test args["sample_step"] == 25.0
    @test args["t_sim"] == 6.0
    @test args["dt_injections"] == 0.0
    @test args["v_perturb_mag"] == 0.001
    @test args["num_parallel_sim"] == 2
    @test args["multi_freq_scan"] === true
    @test P._ztool_arguments(ZToolScan(start_fft = 0), settings)["dt_injections"] == 0
    @test ZToolScan(frequencies = collect(1:8)).frequencies == collect(1.0:8.0)
    for count in (8, 16, 24)
        @test ZToolScan(frequencies = collect(1:count)).frequencies == collect(1.0:count)
        @test ZToolScan(f_points = count).f_points == count
    end
    for count in (16, 24)
        @test ZToolScan(frequencies = collect(1:count), multi_frequency = true).frequencies == collect(1.0:count)
        @test ZToolScan(f_points = count, multi_frequency = true).f_points == count
    end
    for count in (1, 2, 7, 9, 15, 17, 23), multi_frequency in (false, true)
        reason = multi_frequency ? r"divisible by 8 and at least 16: padding repeats" :
            r"divisible by 8: Z-tool pads.*does not run the extra simulations"
        @test_throws reason ZToolScan(frequencies = collect(1:count); multi_frequency)
        @test_throws reason ZToolScan(f_points = count; multi_frequency)
    end
    for count in (1, 7, 8, 15)
        @test_throws r"at least 16:.*PSCAD omits the run index.*only one simulation" ZToolScan(
            frequencies = collect(1:count), multi_frequency = true)
        @test_throws r"at least 16:.*PSCAD omits the run index.*only one simulation" ZToolScan(
            f_points = count, multi_frequency = true)
    end
    for field in (:f_min, :f_max, :f_base, :snapshot_time, :perturbation, :time_step, :sample_step)
        for value in (0, -1, NaN, Inf, true, "1", big"1e400")
            @test_throws ArgumentError ZToolScan(; NamedTuple{(field,)}((value,))...)
        end
    end
    for field in (:start_fft, :injection_interval)
        for value in (-1, NaN, Inf, true, "1")
            @test_throws ArgumentError ZToolScan(; NamedTuple{(field,)}((value,))...)
        end
    end
    for field in (:f_points, :fft_periods, :num_parallel_sim)
        for value in (0, -1, 1.5, NaN, Inf, true, "1", big(typemax(Int)) + 1)
            @test_throws ArgumentError ZToolScan(; NamedTuple{(field,)}((value,))...)
        end
    end
    for values in ([], [0], [-1], [true], [NaN], [Inf], [1, 1], [2, 1], [1, "2"])
        @test_throws ArgumentError ZToolScan(frequencies = values)
    end
    @test_throws ArgumentError ZToolScan(frequencies = (1, 2))
    @test_throws ArgumentError ZToolScan(frequencies = [1, 2], f_min = 1)
    @test_throws ArgumentError ZToolScan(frequencies = [1, 2], f_max = 2)
    @test_throws ArgumentError ZToolScan(frequencies = [1, 2], f_points = 2)
    @test_throws ArgumentError ZToolScan(frequencies = [1.5], f_base = 1)
    @test_throws ArgumentError ZToolScan(f_min = 1.5)
    @test_throws ArgumentError ZToolScan(f_min = 5, f_max = 1)
    @test_throws ArgumentError ZToolScan(multi_frequency = 1)
    @test_throws ArgumentError ZToolScan(time_step = 1e-3, sample_step = 1e-4)
    @test_throws ArgumentError P._ztool_arguments(ZToolScan(sample_step = 1e-6), settings)
    @test_throws ArgumentError P._ztool_arguments(ZToolScan(sample_step = 101e-6), settings)
    @test_throws ArgumentError P._ztool_arguments(ZToolScan(f_max = 5000), settings)
    @test_throws ArgumentError P._ztool_arguments(ZToolScan(f_base = 3, f_min = 3,
        f_max = 30), settings)
    mktempdir() do directory
        path = joinpath(directory, "topology.txt")
        write(path, "scan-1 scan-2\n1 0\n0 1\n")
        @test ZToolScan(topology = path).topology == path
        write(path, "scan-1 scan-2\n! matrix\n1.0 0\n0 1.0\n")
        @test ZToolScan(topology = path).topology == path
        for text in ("", "scan-1\n1", "scan-2 scan-1\n1 0\n0 1",
            "scan-1 other-2\n1 0\n0 1", "scan-1 scan-2\n1 0", "scan-1 scan-2\n1 1\n0 1",
            "scan-1 scan-2\n2 0\n0 1", "scan-1 scan-2\nNaN 0\n0 1",
            "scan-1 scan-2 scan-1 scan-2\n1 0\n0 1")
            write(path, text)
            @test_throws ArgumentError ZToolScan(topology = path)
        end
    end
    @test_throws ArgumentError ZToolScan(topology = "/absent/topology.txt")
    @test_throws ArgumentError ZToolScan(topology = 1)
end

@testset "Z-tool admittance fixtures keep matrix order and siemens" begin
    data = joinpath(@__DIR__, "../data")
    for (filename, block, spot) in (
        ("IM_Ztool_1us#Y_AC#-1#.txt", "", -7.183432325735715e-3 - 1.5687230089880072e-2im),
        ("P2P_HVDC_1us#Y_AC#MMC2-1#.txt", "MMC2", 2.9218461004174636e-4 + 8.007047777668716e-7im),
        ("SGvalidation_idealvac_1us#Y_AC#C-AC-1#.txt", "C-AC", 1.0507602307570281e-2 + 3.271653553541787e-4im))
        path = joinpath(data, filename)
        result = read_ztool_admittance(path)
        rows = split.(readlines(path)[2:end])
        # Match the independent readers in adm_IM_test.jl and adm_SM_test.jl.
        expected = cat((transpose(reshape(parse.(ComplexF64,
            replace.(row[2:end], "(" => "")), 2, 2)) for row in rows)...; dims = 3)
        frequencies = real.([parse(ComplexF64, replace(row[1], "(" => "")) for row in rows])
        @test result.name == (; type = :AC, blocks = [block], sides = [1])
        @test result.axes == [block * "-1_d", block * "-1_q"]
        @test result.frequencies == frequencies
        @test result.admittance == expected
        @test size(result.admittance) == (2, 2, length(rows))
        @test result.admittance[1, 2, 1] ≈ spot rtol = 1e-15
        @test result.admittance[2, 1, 1] != result.admittance[1, 2, 1]
    end
    path = joinpath(@__DIR__, "fixtures/ztool/mixed#Y_ACDC#MMC_AC-2#MMC_DC-1#.txt")
    mixed = read_ztool_admittance(path)
    @test mixed.name == (; type = :ACDC, blocks = ["MMC_AC", "MMC_DC"], sides = [2, 1])
    @test mixed.axes == ["MMC_DC-1_dc", "MMC_AC-2_d", "MMC_AC-2_q"]
    @test mixed.frequencies == [0.1, 0.125, 0.175]
    @test size(mixed.admittance) == (3, 3, 3)
    @test mixed.admittance[1, 2, 1] ≈ 1.7530298612929526e-5 + 5.065985681044347e-4im
    @test mixed.admittance[2, 1, 1] ≈ -2.067832584562485e-5 - 2.5464956345689965e-4im
    @test mixed.admittance[3, 3, 1] ≈ -4.640788551451846e-3 - 1.412138876333291e-6im
    mktempdir() do directory
        path = joinpath(directory, "result#Y_DC#dc-2#.txt")
        write(path, "f\tdc-2_dc\n(1+0j) (2-3j)\n(1+0j) (4+5j)\n")
        dc = read_ztool_admittance(path)
        @test dc.name == (; type = :DC, blocks = ["dc"], sides = [2])
        @test dc.axes == ["dc-2_dc"]
        @test size(dc.admittance) == (1, 1, 2)
        @test dc.admittance[1, 1, :] == [2 - 3im, 4 + 5im]
        for text in ("", "f dc-2_dc\n", "x dc-2_dc\n1 2", "f other-2_dc\n1 2",
            "f dc-2_d dc-2_q\n1 2 3 4 5", "f dc-2_dc dc-2_dc\n1 2 3 4 5",
            "f dc-2_dc\n1 2 3", "f dc-2_dc\n(NaN+0j) 1", "f dc-2_dc\n(1+2j) 3",
            "f dc-2_dc\n0 2", "f dc-2_dc\n2 3\n1 4", "f dc-2_dc\n1 invalid")
            write(path, text)
            @test_throws ArgumentError read_ztool_admittance(path)
        end
        for value in ("nan+nanj", "inf+0j", "0-infj")
            write(path, "f dc-2_dc\n1 ($value)\n")
            @test !isfinite(only(read_ztool_admittance(path).admittance))
        end
        for filename in ("invalid.txt", "result#Y_X#dc-2#.txt", "result#Y_DC#dc-3#.txt")
            invalid = joinpath(directory, filename)
            write(invalid, "f dc-2_dc\n1 2")
            @test_throws ArgumentError read_ztool_admittance(invalid)
        end
    end
    @test_throws ArgumentError read_ztool_admittance("/absent/result.txt")
end
end
