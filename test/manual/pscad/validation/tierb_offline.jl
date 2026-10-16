# Numerical reproduction only; exports, frequency-response records and native runs remain
# unchanged.
function verify_tierb_offline(;directory=joinpath(ROOT,"data","m9d5"))
    mkpath(directory)
    report=Dict{String,Any}("julia_version"=>string(VERSION),"scope"=>"Julia linear self-consistency; no station qualification",
        "HEAD"=>readchomp(`git -C $REPOSITORY rev-parse HEAD`),"source_files"=>source_record())
    for id in M9D_TIERB_IDS
        net=l3_network(id);point=power_flow(net);list=fixture_netlist(net,point);c=l3_circuit(id,net);spec=tierb_spec(id,list)
        descriptor=composed_descriptor(c)
        native=descriptor.poles[argmin(abs.(descriptor.poles.-spec.mode_seed))]
        channels=tierb_channels(c,spec)
        row=Dict{String,Any}("protocol"=>tierb_protocol(spec),"channels"=>channels.labels,
            "native_pole_real_per_s"=>real(native),"native_pole_imag_rad_per_s"=>imag(native))
        for (label,h,discrete) in (("continuous",spec.time_step,false),("discrete",spec.time_step,true),
                ("half_step_discrete",spec.time_step/2,true))
            ss=merge(spec,(;time_step=h,sample_step=25h))
            check_recorder_sampling(ss)==25 || error("B offline sampling protocol changed")
            # Ideal zero prehistory allows starting at onset for this offline
            # calculation only. Measured records keep their entire time grid.
            timegrid=collect(ss.injection_time:ss.sample_step:ss.simulation_time)
            w=burst_wave(timegrid.-h,ss).*ss.current_base_kA
            angle=2π*ss.frequency*h
            drive=hcat(w.*cos(angle),w.*sin(angle))
            println(id," ",label," samples=",length(timegrid));flush(stdout)
            timing=@timed tierb_prediction(c,ss,timegrid,drive;discrete)
            predicted=timing.value;elapsed=timing.time
            fit=tierb_mode(timegrid,predicted[:,ss.fit_channels],ss)
            functions=composed_device_functions(c;time_step=discrete ? h : nothing)
            pole,residual=composed_refine_root(c,functions,native)
            reference=Dict("status"=>"extracted","frequency_Hz"=>abs(imag(pole))/(2π),"zeta"=>-real(pole)/abs(pole))
            comparison=tierb_mode_comparison(fit,reference)
            nv=length(c.nodes)
            vpeak=maximum(abs,predicted[:,1:nv]./channels.bases[1:nv]')
            ipeak=maximum(abs,predicted[:,nv+1:end]./channels.bases[nv+1:end]')
            result=Dict{String,Any}("fit"=>fit,"pole_real_per_s"=>real(pole),"pole_imag_rad_per_s"=>imag(pole),
                "characteristic_residual"=>residual,"matching_pole_comparison"=>comparison,
                "continuous_pole_comparison"=>tierb_mode_comparison(fit,Dict("status"=>"extracted",
                    "frequency_Hz"=>imag(native)/(2π),"zeta"=>-real(native)/abs(native))),
                "voltage_peak_pu"=>vpeak,"current_peak_pu"=>ipeak,
                "driven_d_voltage_rms_V"=>1000sqrt(mean(abs2,predicted[:,1])),"prediction_seconds"=>elapsed)
            result["status"]=comparison["status"]=="passed"&&residual<=1e-6&&vpeak<=.0045&&ipeak<=.008 ? "passed" : "failed"
            row[label]=result
            # Compact, lossless-in-time trace at the actual recorder grid.
            path=joinpath(directory,id*"_"*label*"_prediction.tsv")
            write_tierb_trace(path,timegrid,drive,channels.labels,[label=>predicted])
            println(id," ",label," f=",get(fit,"frequency_Hz",NaN)," alpha=",get(fit,"alpha_per_s",NaN),
                " zeta=",get(fit,"zeta",NaN)," ",result["status"]);flush(stdout)
        end
        row["status"]=all(row[label]["status"]=="passed" for label in ("continuous","discrete","half_step_discrete")) ? "passed" : "failed"
        report[id]=row
        open(io->TOML.print(io,report;sorted=true),joinpath(directory,"offline.toml"),"w")
    end
    report["status"]=all(report[id]["status"]=="passed" for id in M9D_TIERB_IDS) ? "passed" : "failed"
    open(io->TOML.print(io,report;sorted=true),joinpath(directory,"offline.toml"),"w")
    return report
end
