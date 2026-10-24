# Offline system screens and short exports for separate native builds.
using PowerImpedance, PythonCall, LinearAlgebra, TOML, Dates
include("validation/validation.jl")
const V=PSCADValidation
const P=PowerImpedance.PSCAD

function run_system_screens(;directory=get(ENV,"SYSTEM_SCREEN_DATA",joinpath(V.ROOT,"data","system_screens")),
        exports=get(ENV,"SYSTEM_SCREEN_EXPORTS","/tmp/system_exports"),ids=V.SYSTEM_PORT_IDS)
    mkpath(directory);mkpath(exports)
    summary=Dict{String,Any}("analysis_scope"=>"post-line-fix","julia_version"=>string(VERSION),
        "created_utc"=>string(now(UTC)),"worktree"=>V.REPOSITORY,
        "commit"=>readchomp(`git -C $(V.REPOSITORY) rev-parse HEAD`),
        "source_files"=>V.source_record(),"runner_sha256"=>V.digest(@__FILE__),
        "results"=>Dict{String,Any}(),"live_node_limit_exclusive"=>200,
        "required_subsystems"=>1,"export_directory"=>exports)
    for id in ids
        println("Screening $id");flush(stdout)
        evidence=mkpath(joinpath(directory,id))
        record=Dict{String,Any}("analysis_scope"=>"post-line-fix","blockers"=>String[])
        summary["results"][id]=record
        activity="construction"
        try
            net=V.fixture(id).factory()
            static=V.PSCADNetworks.inventory(V.fixture_netlist(net,nothing))
            record["inventory"]=Dict(string(k)=>v for (k,v) in pairs(static))
            record["inventory"]["static_electrical_partitions"]=pop!(record["inventory"],"subsystems")
            activity="power flow"
            point=power_flow(net);result=first(point)
            converters=[Dict("name"=>string(name),"Pac_MW"=>e.setpoint.Pac,"Qac_MVAr"=>e.setpoint.Qac,
                "Vdc_kV"=>e.setpoint.Vdc,"Vac_phase_peak_kV"=>e.setpoint.Vac)
                for (name,e) in net.elements if e.element_model isa Union{PowerImpedance.MMC,PowerImpedance.TLC}]
            record["power_flow"]=Dict("termination_status"=>string(result["termination_status"]),
                "converters"=>converters,
                "ac_voltage_min_pu"=>minimum(b["vm"] for b in values(result["solution"]["bus"])),
                "ac_voltage_max_pu"=>maximum(b["vm"] for b in values(result["solution"]["bus"])))
            activity="netlist"
            list=V.fixture_netlist(net,point)
            V.write_table(joinpath(evidence,"operating_point.tsv"),V.operating_point_rows(list))
            try
                settings=P.SimulationSettings(simulation_time=.01,time_step=2.5e-6,
                    sample_step=62.5e-6,output_stem="build")
                name=lowercase(replace(id,"-"=>"_"));path=joinpath(exports,name*".pscx")
                base=V.system_spec(id=="p2p_original" ? "p2p_redesigned" : id=="p2p_ac_single_line" ? "p2p_ac_grids" : id,list)
                short=merge(base,(;id,simulation_time=.01,time_step=2.5e-6,sample_step=62.5e-6))
                plan,settings=V.scan_plan(list,short,"baseline";name)
                output=P._write_project(plan,path)
                model=P.PSCADModel(abspath(path),name,list,plan.probes,settings,list.operating_point,
                    (source=:validation,mhi_xml_version=output.mhi_xml_version,baseline_axis="baseline"))
                P.check_geometry(path);written=P.read_project_summary(path)
                record["export"]=Dict("path"=>path,"sha256"=>V.digest(path),"bytes"=>filesize(path),
                    "simulation_time_s"=>.01,"sheet_size"=>5,"line_rows"=>length(written.row_definitions),
                    "module_definitions"=>length(written.modules_and_ports),"injection_ports"=>length(base.buses),"top_level_subsystems"=>1,"native_build"=>"not_run")
                V.write_operating_point(joinpath(evidence,"export_operating_point.tsv"),model)
                println("Exported $path");flush(stdout)
            catch failure
                failure isa InterruptException && rethrow()
                push!(record["blockers"],"export: "*sprint(showerror,failure))
            end
            activity="complete-network assembly"
            circuit=V.complete_system(id,net)
            try
                rows,conditioning=V.system_conditioning(circuit)
                V.write_table(joinpath(evidence,"conditioning.tsv"),rows)
                record["conditioning"]=conditioning
            catch failure
                failure isa InterruptException && rethrow()
                push!(record["blockers"],"conditioning: "*sprint(showerror,failure))
            end
            try
                record["stability"]=V.system_stability(circuit;checkpoint=joinpath(evidence,"stability.toml"))
            catch failure
                failure isa InterruptException && rethrow()
                checkpoint=joinpath(evidence,"stability.toml")
                isfile(checkpoint) && (record["stability"]=TOML.parsefile(checkpoint))
                push!(record["blockers"],"stability: "*sprint(showerror,failure))
            end
        catch failure
            failure isa InterruptException && rethrow()
            push!(record["blockers"],activity*": "*sprint(showerror,failure))
        end
        open(io->TOML.print(io,record;sorted=true),joinpath(evidence,"screen.toml"),"w")
        open(io->TOML.print(io,summary;sorted=true),joinpath(directory,"screens.toml"),"w")
        println("Finished $id; blockers=",record["blockers"]);flush(stdout)
    end
    return summary
end

if abspath(PROGRAM_FILE)==@__FILE__
    BLAS.set_num_threads(1)
    run_system_screens(;ids=isempty(ARGS) ? V.SYSTEM_PORT_IDS : ARGS)
end
