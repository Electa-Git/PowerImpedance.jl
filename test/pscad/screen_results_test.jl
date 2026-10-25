module RecordedScreens
using TOML, Dates
using ..PSCADValidation: ROOT, REPOSITORY, preparation_record, manifest_lists!, write_manifest, digest, source_record
using PowerImpedance: RemoteConfig
const NativePSCAD=parentmodule(@__MODULE__).P
const P=(;_require_extension=()->nothing,_dc_precharge_buses=list->[],
    PSCADModel=NativePSCAD.PSCADModel,PSCADResult=NativePSCAD.PSCADResult)
const COUPLED_LINE_CONVERTER_IDS=String[]
const MACHINE_DC_COUPLING_IDS=String[]
const COUPLED_NATIVE_NODES=Dict("two_tlc_shared_bus"=>31,"mmc_rc_shunt"=>55)
const attempts=String[]
const coarse_status=Ref("model_mismatch")
const screen=Dict{String,Any}("status"=>"failed","most_positive_located_real_per_s"=>10.,"root_scope"=>"test roots")
const sensitivity=[Dict("passed"=>false,"native_real_per_s"=>10.)]
fixture(id)=(;id,category=parentmodule(@__MODULE__).V.fixture(id).category,factory=()->(;elements=Dict()),estimated_nodes=1,description="test circuit",
    parent="",topology="test",physics=String[],measurements=["frequency_response"],differences=String[])
PowerFlowProblem(net)=net
ACDCPowerFlow()=nothing
compute(net, formulation)=(;operating_point=nothing)
const NetworkBuilder=(;NetworkModel=(net,point)->nothing)
fixture_netlist(net,point)=(;buses=[])
stability_gate(net,entry)=copy(screen)
composed_stability(c)=copy(screen)
system_stability(c)=copy(screen)
coupled_network(id)=fixture(id).factory()
coupled_circuit(id,net)=(;net,devices=Symbol[])
complete_system(id,net)=coupled_circuit(id,net)
function test_spec(id;protocol="composed_coarse")
    return (;id,protocol,quantity="Y",axes=["p1_d"],frequencies=[1.],dimension=2,time_step=1e-6,sample_step=5e-6,
        tone_peak_pu=1e-7,driven_axis="p1_d",travel_lower_bound_s=0.,power_base_MVA=1.,
        voltage_bases=[1.],current_bases=[1.],carrier_Hz=1.,burst_polarization=ComplexF64[1,0])
end
function applicable_scan(id,net,list;definition=nothing)
    spec=test_spec(id)
    id=="synchronous_machine" && (spec=merge(spec,(;machine_stability=copy(screen))))
    return spec,zeros(ComplexF64,1,1,1)
end
coupled_spec(id,list)=test_spec(id)
coupled_specs(id,list)=[test_spec(id),test_spec(id;protocol="composed_local")]
system_spec(id,list)=test_spec(id)
system_sizing(c,spec)=Dict("passed"=>true)
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
require_committed_coupled_line_converter()=nothing
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
system_growth_reference(c)=[(;root=10. + im,signed_root=10. + im),(;root=11. + im,signed_root=11. - im)]
system_growth_sensitivity(c,modes)=deepcopy(sensitivity)
system_growth_spec(id,list,modes)=test_spec(id)
using ..PSCADValidation: system_growth_variants, GROWTH_WINDOW, GROWTH_STEPS
# Execute the current entry points with local project writers and fixed screen results.
for (file,names) in (("execution.jl",(:prepare_fixture,)),("scan.jl",(:run_fixture,)),
        ("composed_execution.jl",(:prepare_composed,:run_composed,:prepare_shunt_local_witness)),
        ("systems.jl",(:system_setup,:prepare_system)),
        ("growth.jl",(:system_growth_setup,:prepare_system_growth)))
    for expression in Meta.parseall(read(joinpath(ROOT,file),String)).args
        expression isa Expr && expression.head==:function || continue
        first(expression.args).args[1] in names && Core.eval(@__MODULE__,expression)
    end
end
end

@testset "Screen results are recorded while preparation and execution proceed" begin
    S=RecordedScreens
    mktempdir() do root
        directory=joinpath(root,"mmc_gfm_weak_grid")
        models=@test_logs (:warn,r"mmc_gfm_weak_grid complete-network stability result: failed") S.prepare_fixture("mmc_gfm_weak_grid";directory)
        @test !isempty(models) && all(isfile(m.second.project_path) for m in models)
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["stability"]==S.screen
        @test record["status"]=="prepared_station_pending"
        empty!(S.attempts)
        @test_logs (:warn,r"mmc_gfm_weak_grid complete-network stability result: failed") begin
            @test_throws r"local execution reached" S.run_fixture("mmc_gfm_weak_grid";directory,remote=:offline)
        end
        @test S.attempts==["composed_coarse_baseline"]
        @test TOML.parsefile(joinpath(directory,"manifest.toml"))["stability"]==S.screen
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        record["status"]="explained: recorded deviation"
        S.write_manifest(directory,record);empty!(S.attempts)
        @test_logs (:warn,r"mmc_gfm_weak_grid complete-network stability result: failed") (:warn,r"mmc_gfm_weak_grid earlier result: explained:") begin
            @test_throws r"local execution reached" S.run_fixture("mmc_gfm_weak_grid";directory,remote=:offline)
        end
        @test S.attempts==["composed_coarse_baseline"]
        @test TOML.parsefile(joinpath(directory,"manifest.toml"))["previous_result_status"]=="explained: recorded deviation"

        directory=joinpath(root,"synchronous_machine")
        @test_logs (:warn,r"synchronous_machine complete-network stability result: failed") S.prepare_fixture("synchronous_machine";directory)
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["machine_stability"]==S.screen
        @test !haskey(record["frequency_response"],"machine_stability")
        S.screen["most_positive_located_real_per_s"]=20.;empty!(S.attempts)
        try
            @test_logs (:warn,r"synchronous_machine complete-network stability result: failed") begin
                @test_throws r"local execution reached" S.run_fixture("synchronous_machine";directory,remote=:offline)
            end
            @test S.attempts==["composed_coarse_baseline"]
            @test TOML.parsefile(joinpath(directory,"manifest.toml"))["machine_stability"]==S.screen
        finally
            S.screen["most_positive_located_real_per_s"]=10.
        end

        directory=joinpath(root,"two_tlc_shared_bus")
        models=@test_logs (:warn,r"two_tlc_shared_bus composed stability result: failed") S.prepare_composed("two_tlc_shared_bus";directory,remote=:offline)
        @test !isempty(models)
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["stability"]==S.screen
        @test record["status"]=="prepared_station_pending"
        empty!(S.attempts)
        record=@test_logs (:warn,r"two_tlc_shared_bus composed stability result: failed") S.run_composed("two_tlc_shared_bus";directory,remote=:offline)
        @test S.attempts==["composed_coarse","composed_local"]
        @test record["stability"]==S.screen
        @test record["groups"]["composed_local"]["status"]=="passed"
        @test record["status"]=="model_mismatch"
        S.coarse_status[]="passed";empty!(S.attempts)
        record=@test_logs (:warn,r"two_tlc_shared_bus composed stability result: failed") S.run_composed("two_tlc_shared_bus";directory,remote=:offline)
        @test S.attempts==["composed_coarse","composed_local"]
        @test record["status"]=="passed"
        S.coarse_status[]="model_mismatch"

        directory=joinpath(root,"mmc_rc_shunt")
        @test_logs (:warn,r"mmc_rc_shunt composed stability result: failed") S.prepare_composed("mmc_rc_shunt";directory,remote=:offline)
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        record["groups"]=Dict("composed_coarse"=>Dict("status"=>"failed"),
            "composed_local"=>Dict("discrete"=>Dict("DUT"=>Dict("status"=>"invalid_measurement")),
                "selection"=>Dict("frequency_Hz"=>1.)))
        S.write_manifest(directory,record)
        record=@test_logs (:warn,r"mmc_rc_shunt earlier coarse comparison result: failed") (:warn,r"mmc_rc_shunt earlier local comparison results:.*invalid_measurement") (:warn,r"mmc_rc_shunt composed stability result: failed") begin
            S.prepare_shunt_local_witness(;directory,remote=:offline)
        end
        @test record["local_repeat_prepared"]
        @test record["status"]=="local_witness_pending"
        @test record["local_repeat_prior_results"]["coarse_status"]=="failed"
        @test record["local_repeat_prior_results"]["local_status"]["DUT"]=="invalid_measurement"
        @test record["stability"]==S.screen

        setup=@test_logs (:warn,r"p2p_redesigned complete-network finite screen result: failed") S.system_setup("p2p_redesigned")
        directory=joinpath(root,"p2p_redesigned")
        @test !isempty(S.prepare_system(setup;directory,remote=:offline))
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["stability"]==S.screen
        @test record["status"]=="prepared_station_pending"

        setup=@test_logs (:warn,r"p2p_original growth sensitivity result: outside limits") S.system_growth_setup("p2p_original")
        directory=joinpath(root,"p2p_original")
        @test !isempty(S.prepare_system_growth(setup;directory,remote=:offline))
        record=TOML.parsefile(joinpath(directory,"manifest.toml"))
        @test record["growth_sensitivity"]==S.sensitivity
        @test record["status"]=="prepared_station_pending"
    end
end

module MachineScreen
using ..PSCADValidation: ROOT, device_bases, port_probe, passive_settings, scan_reference, fixture
const root=Ref(0.)
stability_gate(net,entry)=Dict("status"=>"failed","most_positive_located_real_per_s"=>root[])
for expression in Meta.parseall(read(joinpath(ROOT,"coverage.jl"),String)).args
    expression isa Expr && expression.head==:function || continue
    first(expression.args).args[1]==:device_scan_definition && Core.eval(@__MODULE__,expression)
end
end

@testset "Machine preparation records growing and zero-real-part roots" begin
    net=V.fixture("synchronous_machine").factory();point=compute(PowerFlowProblem(net),
        ACDCPowerFlow());list=V.fixture_netlist(net,point)
    for root in (0.,1.)
        MachineScreen.root[]=root
        spec,reference=@test_logs (:warn,r"synchronous_machine machine stability result: failed") MachineScreen.device_scan_definition(net,list;id="synchronous_machine")
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
using ..PSCADValidation: time_domain_variants, time_domain_metrics, time_domain_interpolate
using ..RecordedScreens: fixture, coupled_network, compute, PowerFlowProblem, ACDCPowerFlow,
    NetworkBuilder, coupled_circuit, fixture_netlist,
    composed_stability, check_prepared_run_paths, prepare_scan_projects, preparation_record,
    write_operating_point, write_manifest, manifest_lists!, digest, existing_model,
    native_operating_point_check, verify_inputs, exported_composed_passives, test_spec, NativePSCAD
const P=NativePSCAD
const ROOT=mktempdir()
const REPOSITORY=parentmodule(@__MODULE__).V.REPOSITORY
const TIME_DOMAIN_IDS=["machine_mmc_shared_bus"]
const attempts=String[]
const quality_status=Ref("valid")
const comparison_status=Ref("passed")
const amplitude_scale=Ref(.5)
require_committed_time_domain()=nothing
time_domain_frequency_reference_check(args...)=Dict("passed"=>true)
time_domain_spec(id,list)=merge(test_spec(id),(;fit_channels=[1],injection_time=0.,simulation_time=1.))
time_domain_protocol(spec)=Dict("axis"=>spec.driven_axis)
time_domain_channels(c,spec)=(;labels=["V"],bases=[1.])
function execute_axis!(record,key,model,directory,remote,deadline)
    push!(attempts,key)
    return (;time=[0.,1.],key)
end
function time_domain_subtract(result,base,model,basemodel,c)
    scale=startswith(result.key,"time_domain_half_amplitude_") ? amplitude_scale[] : 1.
    return (;signals=fill(scale,2,1),drive=ones(2,1))
end
time_domain_quality(args...)=Dict("status"=>quality_status[])
time_domain_prediction(c,spec,timegrid,drive;kwargs...)=ones(2,1)
time_domain_compare(args...;kwargs...)=Dict("status"=>comparison_status[])
write_time_domain_trace(path,args...;kwargs...)=write(path,"local time-domain samples")
for expression in Meta.parseall(read(joinpath(parentmodule(@__MODULE__).V.ROOT,"time_domain.jl"),String)).args
    expression isa Expr && expression.head==:function || continue
    first(expression.args).args[1] in (:read_frequency_response_record,:prepare_time_domain,:run_time_domain) && Core.eval(@__MODULE__,expression)
end
end

@testset "Time-domain preparation records earlier results and runs every variant" begin
    B=EarlierTimeDomainResults
    id="machine_mmc_shared_bus";directory=joinpath(B.ROOT,"data",id*"_time_domain")
    cdir=mkpath(joinpath(B.ROOT,"data",id))
    prior=Dict("fixture_id"=>id,"status"=>"failed","qualification_status"=>"failed",
        "groups"=>Dict("composed_coarse"=>Dict("status"=>"failed")),"source_files"=>[])
    write(joinpath(cdir,"manifest.toml"),sprint(TOML.print,prior))
    @test_logs (:warn,r"machine_mmc_shared_bus earlier frequency-response results: failed") (:warn,r"machine_mmc_shared_bus time-domain stability result: failed") begin
        @test B.prepare_time_domain([id];remote=:offline)==[id]
    end
    record=TOML.parsefile(joinpath(directory,"manifest.toml"))
    @test record["status"]=="prepared_station_pending"
    @test record["stability"]["status"]=="failed"
    @test record["frequency_response_record"]["status"]=="failed"
    @test record["frequency_response_record"]["groups"]==prior["groups"]
    expected=["time_domain_baseline","time_domain_p1_d","time_domain_half_amplitude_p1_d","time_domain_half_step_baseline","time_domain_half_step_p1_d"]
    for (quality,comparison,scale,status) in (("invalid_measurement","passed",.5,"invalid_measurement"),
            ("valid","failed",.5,"failed"),("valid","passed",.8,"failed"),("valid","passed",.5,"passed"))
        B.quality_status[]=quality;B.comparison_status[]=comparison;B.amplitude_scale[]=scale
        empty!(B.attempts)
        patterns=Any[(:warn,r"machine_mmc_shared_bus earlier frequency-response results: failed")]
        if quality!="valid"
            append!(patterns,[(:warn,Regex("machine_mmc_shared_bus time-domain result for $key: invalid_measurement"))
                for key in expected[[2,3,5]]])
        elseif comparison!="passed"
            append!(patterns,[(:warn,Regex("machine_mmc_shared_bus time-domain result for $key: failed")) for key in expected[[2,3,5]]])
        elseif scale!=.5
            push!(patterns,(:warn,r"machine_mmc_shared_bus time-domain half-amplitude result: failed"))
        end
        record=@test_logs patterns... B.run_time_domain(id;directory,remote=:offline,deadline=time()+60)
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
            spec=C.test_spec("two_tlc_shared_bus")
            record=Dict{String,Any}("fixture_id"=>spec.id)
            c=(;devices=Symbol[])
            group=@test_logs (:warn,Regex("two_tlc_shared_bus frequency-response results:.*$status")) C.run_composed_group!(
                record,c,nothing,spec;directory,remote=:offline,deadline=time()+60)
            @test length(C.attempts)==5
            @test C.attempts[3:5]==["composed_coarse_half_amplitude_p1_d","step_baseline","step_p1_d"]
            @test group["status"]==status
            @test group["measurand_summary"]["direct_Z"]["status"]==status
            @test group["witnesses"]["direct_Z"]["status"]=="passed"
        end
    end
end
