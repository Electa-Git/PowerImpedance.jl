module RecordedScreens
using TOML, Dates
using ..PSCADValidation: ROOT, REPOSITORY, preparation_record, manifest_lists!, write_manifest, digest, source_record
using PowerImpedance: RemoteConfig
const NativePSCAD=parentmodule(@__MODULE__).P
const P=(;_require_extension=()->nothing,_dc_precharge_buses=list->[],
    PSCADModel=NativePSCAD.PSCADModel,PSCADResult=NativePSCAD.PSCADResult)
const M9D_B_IDS=String[]
const M9D_C_IDS=String[]
const L3_NATIVE_NODES=Dict("L3-01"=>31,"L3-08"=>55)
const attempts=String[]
const coarse_status=Ref("model_mismatch")
const screen=Dict{String,Any}("status"=>"failed","most_positive_located_real_per_s"=>10.,"root_scope"=>"test roots")
const sensitivity=[Dict("passed"=>false,"native_real_per_s"=>10.)]
fixture(id)=(;id,factory=()->(;elements=Dict()),estimated_nodes=1,description="test circuit",
    parent="",topology="test",physics=String[],tiers=["C"],differences=String[])
power_flow(net)=nothing
fixture_netlist(net,point)=(;buses=[])
stability_gate(net,entry)=copy(screen)
composed_stability(c)=copy(screen)
l4_stability(c)=copy(screen)
l3_network(id)=fixture(id).factory()
l3_circuit(id,net)=(;net,devices=Symbol[])
l4_system(id,net)=l3_circuit(id,net)
function test_spec(id;protocol="composed_coarse")
    return (;id,protocol,quantity="Y",axes=["p1_d"],frequencies=[1.],dimension=2,time_step=1e-6,sample_step=5e-6,
        tone_peak_pu=1e-7,driven_axis="p1_d",travel_lower_bound_s=0.,power_base_MVA=1.,
        voltage_bases=[1.],current_bases=[1.],carrier_Hz=1.,burst_polarization=ComplexF64[1,0])
end
function applicable_scan(id,net,list;definition=nothing)
    spec=test_spec(id)
    id=="L2-16" && (spec=merge(spec,(;machine_stability=copy(screen))))
    return spec,zeros(ComplexF64,1,1,1)
end
l3_spec(id,list)=test_spec(id)
l3_specs(id,list)=[test_spec(id),test_spec(id;protocol="composed_local")]
l4_spec(id,list)=test_spec(id)
l4_sizing(c,spec)=Dict("passed"=>true)
scan_record(spec)=Dict("protocol"=>spec.protocol,"frequencies"=>spec.frequencies,"axes"=>spec.axes)
scan_prefix(spec)=spec.protocol*"_"
step_prefix(spec)="step_"
step_definition(spec,f)=spec
composed_step_spec(spec,f;local_scan=false)=spec
reference_filename(spec)="reference.tsv"
write_response(path,reference,frequencies;kwargs...)=write(path,"test reference")
read_response(args...)=zeros(ComplexF64,1,1,1)
write_operating_point(path,model)=write(path,"test point")
check_recorder_sampling(spec)=5
record_native_reference!(args...;kwargs...)=nothing
interface_step_reference(args...)=nothing
interface_step_eligible(model)=false
check_prepared_run_paths(args...)=Dict("checked"=>true)
composed_run_axes(specs)=[scan_prefix(s)*"baseline" for s in specs]
composed_targets(c)=String[]
exported_composed_passives(args...)=Dict()
composed_reference_files!(args...;kwargs...)=nothing
native_operating_point_check(args...)=Dict("passed"=>true)
verify_inputs(args...)=nothing
require_committed_m9d_b()=nothing
function prepare_scan_projects(directory,list,spec,axes;prefix="",kwargs...)
    return [begin
        key=prefix*axis
        path=joinpath(mkpath(joinpath(directory,key)),"test.pscx")
        write(path,"<project/>")
        model=NativePSCAD.PSCADModel(path,"test",list,NativePSCAD.ProbeManifest(),
            NativePSCAD.SimulationSettings(),nothing,(;mhi_xml_version="test",baseline_axis="baseline"))
        key=>model
    end for axis in ["baseline";axes]]
end
prepare_composed_projects(directory,list,c,specs,remote)=vcat([
    prepare_scan_projects(directory,list,s,s.axes;prefix=scan_prefix(s)) for s in specs]...)
function run_composed_group!(record,c,list,spec;kwargs...)
    push!(attempts,spec.protocol)
    group=Dict("status"=>spec.protocol=="composed_coarse" ? coarse_status[] : "passed")
    get!(record,"groups",Dict{String,Any}())[spec.protocol]=group
    return group
end
function existing_model(record,key,list,spec,directory;kwargs...)
    path=joinpath(directory,"test.pscx");write(path,"<project/>")
    return NativePSCAD.PSCADModel(path)
end
function execute_axis!(record,key,model,directory,remote,deadline)
    push!(attempts,key)
    error("local execution reached")
end
function replace_local_witness_projects!(record,directory,models,prefix)
    record["local_repeat_prepared"]=true
    return record
end
l4_growth_reference(c)=[(;root=10. + im,signed_root=10. + im),(;root=11. + im,signed_root=11. - im)]
l4_growth_sensitivity(c,modes)=deepcopy(sensitivity)
l4_growth_spec(id,list,modes)=test_spec(id)
using ..PSCADValidation: l4_growth_variants, L4_GROWTH_WINDOW, L4_GROWTH_STEPS
# Execute the current entry points with local project writers and fixed screen results.
for (file,names) in (("execution.jl",(:prepare_fixture,)),("scan.jl",(:run_fixture,)),
        ("composed_execution.jl",(:prepare_composed,:run_composed,:prepare_m9d_a_local_witness)),
        ("l4_execution.jl",(:l4_system_setup,:prepare_l4_system)),
        ("l4_growth.jl",(:l4_growth_setup,:prepare_l4_growth)))
    for expression in Meta.parseall(read(joinpath(ROOT,file),String)).args
        expression isa Expr && expression.head==:function || continue
        first(expression.args).args[1] in names && Core.eval(@__MODULE__,expression)
    end
end
end

@testset "Screen results are recorded while preparation and execution proceed" begin
    S=RecordedScreens
    mktempdir() do root
        directory=joinpath(root,"L2-17")
        models=@test_logs (:warn,r"L2-17 complete-network stability result: failed") S.prepare_fixture("L2-17";directory)
        @test !isempty(models) && all(isfile(m.second.project_path) for m in models)
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["stability"]==S.screen
        @test record["status"]=="prepared_station_pending"
        empty!(S.attempts)
        @test_logs (:warn,r"L2-17 complete-network stability result: failed") begin
            @test_throws r"local execution reached" S.run_fixture("L2-17";directory,remote=:offline)
        end
        @test S.attempts==["composed_coarse_baseline"]
        @test TOML.parsefile(joinpath(directory,"manifest.toml"))["stability"]==S.screen
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        record["status"]="explained: recorded deviation"
        S.write_manifest(directory,record);empty!(S.attempts)
        @test_logs (:warn,r"L2-17 complete-network stability result: failed") (:warn,r"L2-17 earlier result: explained:") begin
            @test_throws r"local execution reached" S.run_fixture("L2-17";directory,remote=:offline)
        end
        @test S.attempts==["composed_coarse_baseline"]
        @test TOML.parsefile(joinpath(directory,"manifest.toml"))["previous_result_status"]=="explained: recorded deviation"

        directory=joinpath(root,"L2-16")
        @test_logs (:warn,r"L2-16 complete-network stability result: failed") S.prepare_fixture("L2-16";directory)
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["machine_stability"]==S.screen
        @test !haskey(record["tier_c"],"machine_stability")
        S.screen["most_positive_located_real_per_s"]=20.;empty!(S.attempts)
        try
            @test_logs (:warn,r"L2-16 complete-network stability result: failed") begin
                @test_throws r"local execution reached" S.run_fixture("L2-16";directory,remote=:offline)
            end
            @test S.attempts==["composed_coarse_baseline"]
            @test TOML.parsefile(joinpath(directory,"manifest.toml"))["machine_stability"]==S.screen
        finally
            S.screen["most_positive_located_real_per_s"]=10.
        end

        directory=joinpath(root,"L3-01")
        models=@test_logs (:warn,r"L3-01 composed stability result: failed") S.prepare_composed("L3-01";directory,remote=:offline)
        @test !isempty(models)
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["stability"]==S.screen
        @test record["status"]=="prepared_station_pending"
        empty!(S.attempts)
        record=@test_logs (:warn,r"L3-01 composed stability result: failed") S.run_composed("L3-01";directory,remote=:offline)
        @test S.attempts==["composed_coarse","composed_local"]
        @test record["stability"]==S.screen
        @test record["groups"]["composed_local"]["status"]=="passed"
        @test record["status"]=="model_mismatch"
        S.coarse_status[]="passed";empty!(S.attempts)
        record=@test_logs (:warn,r"L3-01 composed stability result: failed") S.run_composed("L3-01";directory,remote=:offline)
        @test S.attempts==["composed_coarse","composed_local"]
        @test record["status"]=="passed"
        S.coarse_status[]="model_mismatch"

        directory=joinpath(root,"L3-08")
        @test_logs (:warn,r"L3-08 composed stability result: failed") S.prepare_composed("L3-08";directory,remote=:offline)
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        record["groups"]=Dict("composed_coarse"=>Dict("status"=>"failed"),
            "composed_local"=>Dict("discrete"=>Dict("DUT"=>Dict("status"=>"invalid_measurement")),
                "selection"=>Dict("frequency_Hz"=>1.)))
        S.write_manifest(directory,record)
        record=@test_logs (:warn,r"L3-08 earlier coarse comparison result: failed") (:warn,r"L3-08 earlier local comparison results:.*invalid_measurement") (:warn,r"L3-08 composed stability result: failed") begin
            S.prepare_m9d_a_local_witness(;directory,remote=:offline)
        end
        @test record["local_repeat_prepared"]
        @test record["status"]=="local_witness_pending"
        @test record["local_repeat_prior_results"]["coarse_status"]=="failed"
        @test record["local_repeat_prior_results"]["local_status"]["DUT"]=="invalid_measurement"
        @test record["stability"]==S.screen

        setup=@test_logs (:warn,r"L4-01 complete-network finite screen result: failed") S.l4_system_setup("L4-01")
        directory=joinpath(root,"L4-01")
        @test !isempty(S.prepare_l4_system(setup;directory,remote=:offline))
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["stability"]==S.screen
        @test record["status"]=="prepared_station_pending"

        setup=@test_logs (:warn,r"L4-00D growth sensitivity result: outside limits") S.l4_growth_setup("L4-00D")
        directory=joinpath(root,"L4-00D")
        @test !isempty(S.prepare_l4_growth(setup;directory,remote=:offline))
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["growth_sensitivity"]==S.sensitivity
        @test record["status"]=="prepared_station_pending"
    end
end

module MachineScreen
using ..PSCADValidation: ROOT, device_bases, port_probe, l1_settings, scan_reference, fixture
const root=Ref(0.)
stability_gate(net,entry)=Dict("status"=>"failed","most_positive_located_real_per_s"=>root[])
for expression in Meta.parseall(read(joinpath(ROOT,"coverage.jl"),String)).args
    expression isa Expr && expression.head==:function || continue
    first(expression.args).args[1]==:device_scan_definition && Core.eval(@__MODULE__,expression)
end
end

@testset "Machine preparation records growing and zero-real-part roots" begin
    net=V.fixture("L2-16").factory();point=power_flow(net);list=V.fixture_netlist(net,point)
    for root in (0.,1.)
        MachineScreen.root[]=root
        spec,reference=@test_logs (:warn,r"L2-16 machine stability result: failed") MachineScreen.device_scan_definition(net,list;id="L2-16")
        record=V.scan_record(spec)
        @test spec.machine_stability["status"]=="failed"
        @test spec.machine_stability["most_positive_located_real_per_s"]==root
        @test !haskey(record,"machine_stability")
        @test spec.window_starts==(8.,10.)
        @test spec.simulation_time==12.
        @test all(isfinite,reference)
    end
end

module EarlierTimeDomainResults
using TOML
using ..PSCADValidation: tierb_variants, tierb_metrics, tierb_interpolate
using ..RecordedScreens: fixture, l3_network, power_flow, l3_circuit, fixture_netlist,
    composed_stability, check_prepared_run_paths, prepare_scan_projects, preparation_record,
    write_operating_point, write_manifest, manifest_lists!, digest, existing_model,
    native_operating_point_check, verify_inputs, exported_composed_passives, test_spec, NativePSCAD
const P=NativePSCAD
const ROOT=mktempdir()
const REPOSITORY=parentmodule(@__MODULE__).V.REPOSITORY
const M9D_TIERB_IDS=["L3-06"]
const attempts=String[]
const quality_status=Ref("valid")
const comparison_status=Ref("passed")
const amplitude_scale=Ref(.5)
require_committed_tierb()=nothing
tierb_c_reference_check(args...)=Dict("passed"=>true)
tierb_spec(id,list)=merge(test_spec(id),(;fit_channels=[1],injection_time=0.,simulation_time=1.))
tierb_protocol(spec)=Dict("axis"=>spec.driven_axis)
tierb_channels(c,spec)=(;labels=["V"],bases=[1.])
function execute_axis!(record,key,model,directory,remote,deadline)
    push!(attempts,key)
    return (;time=[0.,1.],key)
end
function tierb_subtract(result,base,model,basemodel,c)
    scale=startswith(result.key,"b_half_amplitude_") ? amplitude_scale[] : 1.
    return (;signals=fill(scale,2,1),drive=ones(2,1))
end
tierb_quality(args...)=Dict("status"=>quality_status[])
tierb_prediction(c,spec,timegrid,drive;kwargs...)=ones(2,1)
tierb_compare(args...;kwargs...)=Dict("status"=>comparison_status[])
write_tierb_trace(path,args...;kwargs...)=write(path,"local time-domain samples")
for expression in Meta.parseall(read(joinpath(parentmodule(@__MODULE__).V.ROOT,"tierb.jl"),String)).args
    expression isa Expr && expression.head==:function || continue
    first(expression.args).args[1] in (:read_tierc_record,:prepare_m9d_b_tier,:run_tierb) && Core.eval(@__MODULE__,expression)
end
end

@testset "Time-domain preparation records earlier results and runs every variant" begin
    B=EarlierTimeDomainResults
    id="L3-06";directory=joinpath(B.ROOT,"data",id*"-tierb")
    cdir=mkpath(joinpath(B.ROOT,"data",id))
    prior=Dict("fixture_id"=>id,"status"=>"failed","qualification_status"=>"failed",
        "groups"=>Dict("composed_coarse"=>Dict("status"=>"failed")),"source_files"=>[])
    write(joinpath(cdir,"manifest.toml"),sprint(TOML.print,prior))
    @test_logs (:warn,r"L3-06 earlier frequency-response results: failed") (:warn,r"L3-06 time-domain stability result: failed") begin
        @test B.prepare_m9d_b_tier([id];remote=:offline)==[id]
    end
    record=TOML.parsefile(joinpath(directory,"manifest.toml"))
    @test record["status"]=="prepared_station_pending"
    @test record["stability"]["status"]=="failed"
    @test record["tier_c_record"]["status"]=="failed"
    @test record["tier_c_record"]["groups"]==prior["groups"]
    expected=["b_baseline","b_p1_d","b_half_amplitude_p1_d","bh_baseline","bh_p1_d"]
    for (quality,comparison,scale,status) in (("invalid_measurement","passed",.5,"invalid_measurement"),
            ("valid","failed",.5,"failed"),("valid","passed",.8,"failed"),("valid","passed",.5,"passed"))
        B.quality_status[]=quality;B.comparison_status[]=comparison;B.amplitude_scale[]=scale
        empty!(B.attempts)
        patterns=Any[(:warn,r"L3-06 earlier frequency-response results: failed")]
        if quality!="valid"
            append!(patterns,[(:warn,Regex("L3-06 time-domain result for $key: invalid_measurement"))
                for key in expected[[2,3,5]]])
        elseif comparison!="passed"
            append!(patterns,[(:warn,Regex("L3-06 time-domain result for $key: failed")) for key in expected[[2,3,5]]])
        elseif scale!=.5
            push!(patterns,(:warn,r"L3-06 time-domain half-amplitude result: failed"))
        end
        record=@test_logs patterns... B.run_tierb(id;directory,remote=:offline,deadline=time()+60)
        @test B.attempts==expected
        @test record["status"]==status
        @test length(record["comparisons"])==3
        @test TOML.parsefile(joinpath(directory,"manifest.toml"))["status"]==status
    end
end

module ComposedMeasuredResults
using PowerImpedance
using ..RecordedScreens: NativePSCAD, test_spec, existing_model, exported_composed_passives,
    composed_reference_files!, interface_step_eligible, scan_prefix, step_prefix,
    composed_step_spec, prepare_scan_projects, write_manifest
const P=NativePSCAD
const attempts=String[]
const measured_status=Ref("invalid_measurement")
compare_operating_point(result,model)=(;within_tolerance=[true])
write_table(path,rows)=write(path,"local comparison")
function execute_axis!(record,key,model,directory,remote,deadline)
    push!(attempts,key)
    return P.PSCADResult(PSCADRun(),[0.,1.],PowerImpedance.OrderedDict{String,Vector{Float64}}(),
        model.probes,model.settings,(;),(;))
end
composed_frozen_references(args...)=Dict("direct_Z"=>zeros(ComplexF64,1,1,1))
function composed_comparison(args...;kwargs...)
    comparisons=Dict("direct_Z"=>Dict("status"=>measured_status[],"invalid_reasons"=>["test result"]))
    return (;comparisons,selection=(;column=1,frequency=1.),kcl=[])
end
record_project!(args...)=nothing
composed_column(args...)=nothing
composed_readout_evidence(args...;kwargs...)=Dict("passed"=>true)
function composed_witnesses!(group,args...)
    group["witnesses"]=Dict("direct_Z"=>Dict("status"=>"passed","invalid_reasons"=>String[]))
    return group["witnesses"]
end
for expression in Meta.parseall(read(joinpath(parentmodule(@__MODULE__).V.ROOT,"composed_execution.jl"),String)).args
    expression isa Expr && expression.head==:function || continue
    first(expression.args).args[1]==:run_composed_group! && Core.eval(@__MODULE__,expression)
end
end

@testset "Composed repeats run after each measured outcome" begin
    C=ComposedMeasuredResults
    for status in ("invalid_measurement","model_mismatch")
        C.measured_status[]=status;empty!(C.attempts)
        mktempdir() do directory
            spec=C.test_spec("L3-01")
            record=Dict{String,Any}("fixture_id"=>spec.id)
            c=(;devices=Symbol[])
            group=@test_logs (:warn,Regex("L3-01 frequency-response results:.*$status")) C.run_composed_group!(
                record,c,nothing,spec;directory,remote=:offline,deadline=time()+60)
            @test length(C.attempts)==5
            @test C.attempts[3:5]==["composed_coarse_half_amplitude_p1_d","step_baseline","step_p1_d"]
            @test group["status"]==status
            @test group["measurand_summary"]["direct_Z"]["status"]==status
            @test group["witnesses"]["direct_Z"]["status"]=="passed"
        end
    end
end
