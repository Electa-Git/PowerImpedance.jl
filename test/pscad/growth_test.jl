@testset "Fixed-interval circular growth fit" begin
    time=collect(0.:5e-6:.002)
    roots=ComplexF64[1374. + 2π*3478im,1426. - 2π*3476im]
    function signal(roots)
        z=zeros(ComplexF64,length(time),2)
        for (j,root) in enumerate(roots)
            f=imag(root)/(2π);companion=complex(real(root),2π*(100-f))
            for channel in 1:2
                z[:,channel] .+= (.0001cis(.4channel+j)).*exp.(root.*time)
                z[:,channel] .+= (.000002cis(channel-j)).*exp.(companion.*time)
            end
        end
        z .+= cis.(2π*50 .*time).*[1.2 .7]
        z .+= ones(length(time))*[.04im .03]
        return z
    end
    data=signal(roots)
    seeds=ComplexF64[1100. + 2π*3300im,1700. - 2π*3700im]
    fit=V.system_growth_fit(time,data,seeds)
    @test fit["status"]=="extracted"
    @test fit["window_s"]==[.0003,.0018]
    @test V.system_growth_comparison(fit,roots)["status"]=="passed"
    for (mode,root) in zip(fit["modes"],roots)
        @test mode["growth_per_s"] ≈ real(root) rtol=1e-4
        @test mode["signed_frequency_Hz"] ≈ imag(root)/(2π) rtol=1e-5
    end
    wrong=ComplexF64[1.4real(z)+1.1im*imag(z) for z in roots]
    bad=V.system_growth_fit(time,signal(wrong),seeds)
    @test bad["status"]=="extracted"
    @test V.system_growth_comparison(bad,roots)["status"]=="failed"
    @test V.system_growth_fit(time[1:200],data[1:200,:],seeds)["status"]=="unextractable"
    @test V.system_growth_fit(time,zero(data),seeds)["status"]=="unextractable"
    irregular=copy(time);irregular[20]+=1e-6
    @test V.system_growth_fit(irregular,data,seeds)["status"]=="unextractable"
    abc=hcat([cos.(2π*3478 .*time .+phase) for phase in (0.,-2π/3,2π/3)]...)
    @test V.system_space_vector(abc) ≈ cis.(2π*3478 .*time)
    spec=(time_step=1e-6,sample_step=5e-6,tone_peak_pu=1e-7,driven_axis="p1_d")
    variants=V.system_growth_variants(spec)
    @test length(variants)==5
    @test variants[4].spec.time_step==.5e-6
    @test variants[4].spec.sample_step==2.5e-6
    @test all(variants) do variant
        ratio=variant.spec.sample_step/variant.spec.time_step
        isapprox(ratio,round(ratio)) && isodd(round(Int,ratio))
    end
    @test variants[3].spec.tone_peak_pu==5e-8
    probes=P.ProbeChannel[P.ProbeChannel(
        "precharge_dc_open", :precharge_command, nothing, nothing, nothing, 1, "pu")]
    append!(probes,
        [P.ProbeChannel(
             "m_$(half)_$phase", :converter_diagnostic, nothing, "c1", :ac, 1, "pu")
         for half in ("u", "l") for phase in ("a", "b", "c")])
    channels=Dict(p.name=>fill(p.kind==:precharge_command ? 0.0 : 0.5, length(time))
    for p in probes)
    model=(; probes = (; channels = probes))
    @test V.system_growth_internal_quality((; time, channels), model)["passed"]
    channels["m_u_a"][200]=1.01
    @test !V.system_growth_internal_quality((;time,channels),model)["passed"]
    channels["m_u_a"][200]=.5;channels["precharge_dc_open"][200]=1.
    @test !V.system_growth_internal_quality((;time,channels),model)["passed"]
    nominal=ComplexF64[1.,.5]
    small=cis.(2π*50 .*time)*transpose(nominal)+.0001exp.(roots[1].*time)*[1. .5]
    small[1,:].=0
    quality_channels=(signals=small,bases=[1.,1.],reference=nominal)
    @test V.system_growth_quality(time,quality_channels,(frequency=50.,))["passed"]
    @test !V.system_growth_quality(time,merge(quality_channels,(reference=nominal.+.02,)),(frequency=50.,))["passed"]
    @test V.GROWTH_WINDOW==(.0003,.0018)
    @test V.GROWTH_LIMITS==(frequency=.02,growth=.10,growth_floor=.5)
end

module GrowthExecution
using PowerImpedance: RemoteConfig,PSCADRun
using ..PSCADValidation: ROOT,budget_remote,digest,native_node_limit,write_manifest
const remotes=RemoteConfig[]
# Fix the clock so both timeout limits can be checked exactly.
time()=1000.
function compute(model,::PSCADRun;options)
    push!(remotes,options.remote)
    messages=joinpath(options.work_root,"build_messages.txt")
    write(messages,"The total number of live nodes: 12\n")
    return (paths=(build_messages=messages,),
        diagnostics=(solver_identity="fixture",elapsed_seconds=.1))
end
for expression in Meta.parseall(Base.read(joinpath(ROOT,"growth.jl"),String)).args
    expression isa Expr && expression.head==:function || continue
    name=first(expression.args).args[1]
    name==:execute_system_growth! && Core.eval(@__MODULE__,expression)
end
end

@testset "system growth passes whole seconds to the station timeout" begin
    mktempdir() do root
        project=joinpath(root,"model.pscx");write(project,"fixture")
        model=(project_path=project,)
        deadline=1120.75
        remaining=deadline-GrowthExecution.time()
        for timeout in (60,600)
            remote=RemoteConfig("fixture",root,"unused","julia","python";local_root=root,timeout)
            directory=mkpath(joinpath(root,"output-$timeout"))
            record=Dict{String,Any}("fixture_id"=>"p2p_original","run_records"=>Any[])
            GrowthExecution.execute_system_growth!(record,"g_driven",model,directory,remote,deadline)
            observed=last(GrowthExecution.remotes)
            @test observed.timeout isa Int
            @test observed.timeout==min(remote.timeout,floor(Int,remaining))
        end
    end
end
