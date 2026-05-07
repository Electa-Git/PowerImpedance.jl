# export tlclegacy

# TODO: Implement legacy functionality

function tlclegacy(; kwargs...)
    kwargs = NamedTuple(kwargs)
    legacy_keys = (
        :ω₀, :P, :Q, :P_dc, :P_min, :P_max, :Q_min, :Q_max,
        :θ, :Vₘ, :Vᵈᶜ, :Lᵣ, :Rᵣ, :Lₐᵣₘ, :Rₐᵣₘ,
        :pll, :v_meas_filt, :i_meas_filt, :p, :q, :dc, :occ, :vac, :vac_supp,
        :controls, :equilibrium, :A, :B, :C, :D,
        :timeDelay, :padeOrderNum, :padeOrderDen,
        :vACbase_LL_RMS, :Sbase, :vDCbase, :iDCbase, :vACbase, :iACbase, :debug,
    )

    if any(key -> key in keys(kwargs), legacy_keys)
        return _legacy_tlc_from_kwargs(kwargs)
    end

    return tlc_modular(; kwargs...)
end


_legacy_kwget(kwargs, key, default) = begin
    nt = NamedTuple(kwargs)
    key in keys(nt) ? getproperty(nt, key) : default
end

function _legacy_field(obj, key, default)
    obj === nothing && return default
    hasproperty(obj, key) ? getproperty(obj, key) : default
end

function _legacy_ref(obj, default)
    ref = _legacy_field(obj, :ref, default)
    ref isa AbstractArray && !isempty(ref) && return ref[1]
    return ref
end

function _legacy_pi_control(obj)
    return PIControl(
        Kp = Float64(_legacy_field(obj, :Kₚ, _legacy_field(obj, :Kp, 0.0))),
        Ki = Float64(_legacy_field(obj, :Kᵢ, _legacy_field(obj, :Ki, 0.0))),
    )
end

function _legacy_filter(obj)
    order = Int(_legacy_field(obj, :n_f, 0))
    ωc = Float64(_legacy_field(obj, :ω_f, 0.0))
    return order > 0 && ωc > 0 ? Butterworth(order = order, ωc = ωc) : NoFilter()
end

function _legacy_setpoint(kwargs)
    return SetPoint(
        Pac = Float64(_legacy_kwget(kwargs, :P, 0.0)),
        Qac = Float64(_legacy_kwget(kwargs, :Q, 0.0)),
        θac = Float64(_legacy_kwget(kwargs, :θ, 0.0)),
        Vac = Float64(_legacy_kwget(kwargs, :Vₘ, 220 * sqrt(2 / 3))),
        Pdc = Float64(_legacy_kwget(kwargs, :P_dc, 0.0)),
        Vdc = Float64(_legacy_kwget(kwargs, :Vᵈᶜ, 0.0)),
    )
end

function _legacy_limits(kwargs)
    return Limits(
        P_min = Float64(_legacy_kwget(kwargs, :P_min, 0.9)),
        P_max = Float64(_legacy_kwget(kwargs, :P_max, 1.1)),
        Q_min = Float64(_legacy_kwget(kwargs, :Q_min, -0.5)),
        Q_max = Float64(_legacy_kwget(kwargs, :Q_max, 0.5)),
    )
end

function _legacy_controls(kwargs)
    kwargs = NamedTuple(kwargs)
    controls = OrderedDict{Symbol, Any}()

    if key in keys(kwargs) && false
    end

    if :controls in keys(kwargs) && kwargs.controls !== nothing
        for (key, value) in kwargs.controls
            controls[key] = value
        end
    end

    for key in (:pll, :v_meas_filt, :i_meas_filt, :p, :q, :dc, :occ, :vac, :vac_supp)
        if key in keys(kwargs)
            controls[key] = getproperty(kwargs, key)
        end
    end

    return controls
end

function _legacy_tlc_from_kwargs(kwargs)
    kwargs = NamedTuple(kwargs)
    controls = _legacy_controls(kwargs)
    setpoint = :setpoint in keys(kwargs) ? kwargs.setpoint : _legacy_setpoint(kwargs)
    limits = :limits in keys(kwargs) ? kwargs.limits : _legacy_limits(kwargs)

    vac_filter = _legacy_filter(get(controls, :v_meas_filt, nothing))
    iac_filter = _legacy_filter(get(controls, :i_meas_filt, nothing))
    vdc_filter = _legacy_filter(get(controls, :dc, nothing))

    meas = :meas in keys(kwargs) ? kwargs.meas : Measurement(
        v_ac = vac_filter,
        i_ac = iac_filter,
        v_dc = vdc_filter,
    )

    pll_ctrl = _legacy_kwget(controls, :pll, nothing)
    sync = :sync in keys(kwargs) ? kwargs.sync : (
        pll_ctrl === nothing ? NoSynchronization() : PLLSynchronization(
            pi_ctrl = _legacy_pi_control(pll_ctrl),
            filter = _legacy_filter(pll_ctrl),
        )
    )

    outerActive = :outerActive in keys(kwargs) ? kwargs.outerActive : begin
        if haskey(controls, :dc)
            ctrl = controls[:dc]
            v_dc_ref = _legacy_field(ctrl, :ref, [setpoint.Vdc / max(_legacy_kwget(kwargs, :vDCbase, 640.0), eps())])
            OuterActiveVdcControl(
                pi_ctrl = _legacy_pi_control(ctrl),
                v_dc_ref = Float64(v_dc_ref isa AbstractArray ? v_dc_ref[1] : v_dc_ref),
            )
        elseif haskey(controls, :p)
            ctrl = controls[:p]
            p_ref = _legacy_field(ctrl, :ref, [setpoint.Pac / max(_legacy_kwget(kwargs, :Sbase, 500.0), eps())])
            OuterActivePowerControl(
                pi_ctrl = _legacy_pi_control(ctrl),
                P_ac_ref = Float64(p_ref isa AbstractArray ? p_ref[1] : p_ref),
            )
        else
            NoOuterActiveControl()
        end
    end

    outerReactive = :outerReactive in keys(kwargs) ? kwargs.outerReactive : begin
        if haskey(controls, :vac_supp)
            ctrl = controls[:vac_supp]
            v_ac_ref = _legacy_field(ctrl, :ref, [setpoint.Vac / max(_legacy_tlc_elec_vacbase(kwargs), eps())])
            q_ctrl = haskey(controls, :q) ? controls[:q] : nothing
            OuterReactiveQControl(
                pi_ctrl = _legacy_pi_control(q_ctrl === nothing ? ctrl : q_ctrl),
                Q_ac_ref = q_ctrl === nothing ? 0.0 : Float64(_legacy_ref(q_ctrl, 0.0)),
                support = VoltageSupportLag(
                    K = Float64(_legacy_field(ctrl, :Kₚ, 0.0)),
                    ωc = Float64(_legacy_field(ctrl, :ω_f, 0.0)),
                    v_ac_ref = Float64(v_ac_ref isa AbstractArray ? v_ac_ref[1] : v_ac_ref),
                ),
            )
        elseif haskey(controls, :vac)
            ctrl = controls[:vac]
            v_ac_ref = _legacy_field(ctrl, :ref, [setpoint.Vac / max(_legacy_tlc_elec_vacbase(kwargs), eps())])
            OuterReactiveVacControl(
                pi_ctrl = _legacy_pi_control(ctrl),
                v_ac_ref = Float64(v_ac_ref isa AbstractArray ? v_ac_ref[1] : v_ac_ref),
            )
        elseif haskey(controls, :q)
            ctrl = controls[:q]
            OuterReactiveQControl(
                pi_ctrl = _legacy_pi_control(ctrl),
                Q_ac_ref = Float64(_legacy_ref(ctrl, setpoint.Qac / max(_legacy_kwget(kwargs, :Sbase, 500.0), eps()))),
            )
        else
            NoOuterReactiveControl()
        end
    end

    innerVoltage = :innerVoltage in keys(kwargs) ? kwargs.innerVoltage : NoInnerVoltageControl()

    innerCurrent = :innerCurrent in keys(kwargs) ? kwargs.innerCurrent : begin
        occ_ctrl = _legacy_kwget(controls, :occ, nothing)
        occ_ctrl === nothing ? NoInnerCurrentControl() : InnerCurrentPIControl(
            pi_ctrl = _legacy_pi_control(occ_ctrl),
            filter = _legacy_filter(occ_ctrl),
        )
    end

    mod = :mod in keys(kwargs) ? kwargs.mod : begin
        timeDelay = Float64(_legacy_kwget(kwargs, :timeDelay, 0.0))
        padeOrderNum = Int(_legacy_kwget(kwargs, :padeOrderNum, 0))
        padeOrderDen = Int(_legacy_kwget(kwargs, :padeOrderDen, 0))
        if !iszero(timeDelay) && (padeOrderNum > 0 || padeOrderDen > 0)
            DelayModulation(timeDelay = timeDelay, padeOrderNum = padeOrderNum, padeOrderDen = padeOrderDen)
        else
            NoModulation()
        end
    end

    elec = :elec in keys(kwargs) ? kwargs.elec : ElectricalTLC(
        ωbase = Float64(_legacy_kwget(kwargs, :ω₀, 100 * π)),
        Lᵣ = Float64(_legacy_kwget(kwargs, :Lᵣ, 60e-3)),
        Rᵣ = Float64(_legacy_kwget(kwargs, :Rᵣ, 0.535)),
        vACbase_LL_RMS = Float64(_legacy_kwget(kwargs, :vACbase_LL_RMS, 220.0)),
        Sbase = Float64(_legacy_kwget(kwargs, :Sbase, 500.0)),
        vDCbase = Float64(_legacy_kwget(kwargs, :vDCbase, 640.0)),
    )

    connection = _legacy_kwget(kwargs, :connection, true)

    return tlc_modular(
        elec = elec,
        meas = meas,
        sync = sync,
        outerActive = outerActive,
        outerReactive = outerReactive,
        innerVoltage = innerVoltage,
        innerCurrent = innerCurrent,
        mod = mod,
        setpoint = setpoint,
        limits = limits,
        connection = connection,
    )
end

_legacy_tlc_elec_vacbase(kwargs) = begin
    if haskey(kwargs, :elec)
        return kwargs.elec.vACbase
    end
    vACbase_LL_RMS = Float64(_legacy_kwget(kwargs, :vACbase_LL_RMS, 220.0))
    Sbase = Float64(_legacy_kwget(kwargs, :Sbase, 500.0))
    vACbase_LL_RMS * sqrt(2 / 3)
end






# Test commit adding a comment
# @with_kw mutable struct TLC <: Converter
#     ω₀ :: Union{Int, Float64} = 100*π

#     P :: Union{Int, Float64} = -10              # active power [MW]
#     Q :: Union{Int, Float64} = 3                # reactive power [MVA]
#     P_dc :: Union{Int, Float64} = 100           # DC power [MW]
#     P_min :: Union{Float64, Int} = -100         # min active power output [MW]
#     P_max :: Union{Float64, Int} = 100          # max active power output [MW]
#     Q_min :: Union{Float64, Int} = -50          # min reactive power output [MVA]
#     Q_max :: Union{Float64, Int} = 50           # max reactive power output [MVA]

#     θ :: Union{Int, Float64} = 0
#     Vₘ :: Union{Int, Float64} = 333             # AC voltage, amplitude [kV]
#     Vᵈᶜ :: Union{Int, Float64} = 640            # DC-bus voltage [kV]

#     Lᵣ :: Union{Int, Float64}  = 60e-3         # inductance of the converter transformer at the converter side [H]
#     Rᵣ :: Union{Int, Float64}  = 0.535         # resistance of the converter transformer at the converter side [H]

#     Lₐᵣₘ :: Union{Int, Float64}  = 0        # filter inductance [H] Needed for power flow calculation so default zero
#     Rₐᵣₘ :: Union{Int, Float64}  = 0        # equivalent filter resistance

#     controls :: OrderedDict{Symbol, Controller} = OrderedDict{Symbol, Controller}()
#     equilibrium :: Array{Union{Int, Float64}} = [0]
#     A :: Array{Complex} = [0]
#     B :: Array{Complex} = [0]
#     C :: Array{Complex} = [0]
#     D :: Array{Complex} = [0]

#     timeDelay :: Float64 = 0
#     padeOrderNum :: Int = 0
#     padeOrderDen :: Int = 0

#     vACbase_LL_RMS :: Union{Int, Float64} = 220 # Voltage base in kV
#     Sbase :: Union{Int, Float64} = 500 # Power base in MW
#     vDCbase :: Union{Int, Float64} = 640        # DC voltage base [kV]
#     iDCbase :: Union{Int, Float64} = 0

#     vACbase :: Float64 = 0 # AC voltage base for impedance/admittance calculation
#     iACbase :: Float64 = 0 # AC current base for impedance/admittance calculation

#     debug = nothing
# end

"""
    function tlc(;args...)
It constructs tlc operating both as a rectifier and an inverter. TLC is constructed as a struct with the
following fields.
```julia
ω₀ :: Union{Int, Float64} = 100*π

    P :: Union{Int, Float64} = -10              # active power [MW]
    Q :: Union{Int, Float64} = 3                # reactive power [MVA]
    P_dc :: Union{Int, Float64} = 100           # DC power [MW]
    P_min :: Union{Float64, Int} = -100         # min active power output [MW]
    P_max :: Union{Float64, Int} = 100          # max active power output [MW]
    Q_min :: Union{Float64, Int} = -50          # min reactive power output [MVA]
    Q_max :: Union{Float64, Int} = 50           # max reactive power output [MVA]

    θ :: Union{Int, Float64} = 0
    Vₘ :: Union{Int, Float64} = 333             # AC voltage, amplitude [kV]
    Vᵈᶜ :: Union{Int, Float64} = 640            # DC-bus voltage [kV]

    Lₐᵣₘ :: Union{Int, Float64}  = 0        # arm inductance [H]
    Rₐᵣₘ :: Union{Int, Float64}  = 0        # equivalent arm resistance

    Lᵣ :: Union{Int, Float64}  = 60e-3          # inductance of the phase reactor [H]
    Rᵣ :: Union{Int, Float64}  = 0.535          # resistance of the phase reactor [Ω]

    controls :: OrderedDict{Symbol, Controller} = OrderedDict{Symbol, Controller}()
    equilibrium :: Array{Union{Int, Float64}} = [0]
    A :: Array{Complex} = [0]
    B :: Array{Complex} = [0]
    C :: Array{Complex} = [0]
    D :: Array{Complex} = [0]

    timeDelay :: Float64 = 0
    padeOrderNum :: Int = 0
    padeOrderDen :: Int = 0

    vACbase_LL_RMS :: Union{Int, Float64} = 220 # Voltage base in kV
    Sbase :: Union{Int, Float64} = 500 # Power base in MW

    vACbase :: Float64 = 0 # AC voltage base for impedance/admittance calculation
    iACbase :: Float64 = 0 # AC current base for impedance/admittance calculation
```
"""
function tlc(;args...)
    converter = TLC()
    connection = true
    for (key, val) in pairs(args)
        if isa(val, Controller)
            if key == :vac_supp
                #error("AC voltage support is not yet implemented")
            end
            converter.controls[key] = val
        elseif in(key, propertynames(converter))
            setfield!(converter, key, val)
        elseif (key == :connection)
            connection = val
        else
            throw(ArgumentError("TLC does not have a property $(key)."))
        end
    end
    # Transformation property set to false, as model is natively defined in dq-frame
    elem = Element(input_pins = 1, output_pins = 2, element_value = converter, transformation = false, connection = connection)
end

function update!(converter :: TLC, Vm, θ,Pac, Qac, Vdc, Pdc)
    

    wbase = 100*pi
    vAC_base = converter.vACbase_LL_RMS*sqrt(2/3)
    Sbase = converter.Sbase
    vDC_base = converter.vDCbase
    iDC_base = Sbase/vDC_base
    iAC_base = 2*Sbase/3/vAC_base
    zAC_base = (3/2)*vAC_base^2/Sbase
    zDC_base = vDC_base/iDC_base
    lAC_base = zAC_base/wbase
    lDC_base = zDC_base/wbase
    cbase = 1/wbase/zDC_base

    converter.vACbase = vAC_base
    converter.iACbase = iAC_base
    converter.iDCbase = iDC_base

    Lᵣ = converter.Lᵣ / lAC_base
    Rᵣ = converter.Rᵣ / zAC_base
    Cₑ = 1e-6/ cbase #Helper cap to arrange equilibrium in case of DC voltage control
    ω₀ = converter.ω₀

    Qac *=-1 # Correction for reactive power sign

    converter.Vₘ = Vm
    converter.θ = θ
    converter.Vᵈᶜ = Vdc
    # Vdc = converter.Vᵈᶜ
    converter.P = Pac
    converter.Q = Qac
    converter.P_dc = Pdc # Has the same sign as Pac
    # Pdc = converter.P_dc

    Vm /= vAC_base
    Vdc /= vDC_base
    Pac /= Sbase
    Qac /= Sbase
    Pdc /= Sbase
    
    Vᴳd = Vm * cos(θ)
    Vᴳq = -Vm * sin(θ)

    Id = ((Vᴳd * Pac + Vᴳq * Qac) / (Vᴳd^2 + Vᴳq^2)) 
    Iq = ((Vᴳq * Pac - Vᴳd * Qac) / (Vᴳd^2 + Vᴳq^2)) 

    # setup control parameters and equations
    init_x = zeros(2, 1)

    # TODO: These have to be updated to be compliant with the PU model!
    for (key, val) in (converter.controls)
        # fix coefficients
        if (val.Kₚ == 0) && (val.Kᵢ == 0)
            if (key == :occ)                            # pole placement
                val.Kᵢ = Lₑ * val.bandwidth^2
                val.Kₚ = 2 * val.ζ * val.bandwidth * Lₑ - Rₑ
            end
        end

        # fix reference values
        if (key == :occ)
            if (length(val.ref) == 1) && (val.ref[1] == 0)
                val.ref = [Id Iq]
            end
            init_x[1] = val.ref[1]
            init_x[2] = val.ref[2]
        elseif (key == :p)
            if (length(val.ref) == 1) && (val.ref[1] == 0)
                val.ref = [Pac]
            end
        elseif (key == :q)
            if (length(val.ref) == 1) && (val.ref[1] == 0)
                val.ref = [Qac]
            end
        elseif (key == :dc)
            if (length(val.ref) == 1) && (val.ref[1] == 0)
                val.ref = [Vdc]
            end
        elseif (key == :vac) || (key == :vac_supp)
            if (length(val.ref) == 1) && (val.ref[1] == 0)
                val.ref = [Vm]
            end
        end
    end

    index = 2
    index_PLL_angle = 0

    Idc_in = Pdc/Vdc
    init_x[1] = Pac
    init_x[2] = Qac

    function state_space!(converter,F,x,inputs;solve) 
        
        index = 2
        index_PLL_angle = 0

        
        if in(:pll, keys(converter.controls))
            index_PLL_angle = index + 1*(converter.controls[:pll].n_f) +2
            if in(:v_meas_filt, keys(converter.controls))
                index_PLL_angle +=  2*(converter.controls[:v_meas_filt].n_f)  
            end        
            
            T_θ = [cos(x[index_PLL_angle]) -sin(x[index_PLL_angle]); sin(x[index_PLL_angle]) cos(x[index_PLL_angle])];
            I_θ = [cos(x[index_PLL_angle]) sin(x[index_PLL_angle]); -sin(x[index_PLL_angle]) cos(x[index_PLL_angle])];          
        
        else
            
            T_θ = [1 0; 0 1];
            I_θ = [1 0; 0 1];
        
        end

        Vdc = inputs[1];
        (Vᴳd, Vᴳq) = T_θ * [inputs[2]; inputs[3]];

        # add voltage measurement filter
        if in(:v_meas_filt, keys(converter.controls))
            

            voltagesIn = [Vᴳd;Vᴳq];
            statesButt= x[index + 1 : index + 2*(converter.controls[:v_meas_filt].n_f)]; 
            F[index + 1 : index + 2*(converter.controls[:v_meas_filt].n_f)] = Abutt*statesButt + Bbutt*voltagesIn;
            voltagesOut=Cbutt*statesButt+Dbutt*voltagesIn;
            Vᴳd_f=voltagesOut[1];
            Vᴳq_f=voltagesOut[2];
            
            index += 2*(converter.controls[:v_meas_filt].n_f) 
           
        else

            (Vᴳd_f, Vᴳq_f) = (Vᴳd, Vᴳq);
            
        end
        

        # add PLL
        if in(:pll, keys(converter.controls))
            if (converter.controls[:pll].ω_f != 0) # A PLL filter is implemented
                
            
                statesButt_pll= x[index + 1 : index + 1*(converter.controls[:pll].n_f)]; 
                F[index + 1 : index + 1*(converter.controls[:pll].n_f)] = Abutt_pll*statesButt_pll + Bbutt_pll*Vᴳq_f;
                vₚₗₗ=dot(Cbutt_pll,statesButt_pll)+Dbutt_pll*Vᴳq_f;# Get rid of 1-element array
            

            
                index += 1*(converter.controls[:pll].n_f)
                
            else
                
                vₚₗₗ = Vᴳq
            
            end

            F[index+1] = -vₚₗₗ*(converter.controls[:pll].Kᵢ);
            Δω = (converter.controls[:pll].Kₚ) * (-vₚₗₗ) + x[index+1];
            ω = (converter.ω₀)/wbase + Δω;
            F[index+2] = wbase*Δω;
        
            index += 2
        else

            Δω = 0;

        end

        (i_d_pcc_c, i_q_pcc_c) = T_θ * [x[1]; x[2]]

        # add current measurement filter
        if in(:i_meas_filt, keys(converter.controls))
            

            currentsIn = [i_d_pcc_c;i_q_pcc_c];
            statesButt_i= x[index + 1 : index + 2*(converter.controls[:i_meas_filt].n_f)]; 
            F[index + 1 : index + 2*(converter.controls[:i_meas_filt].n_f)] = Abutt_i*statesButt_i + Bbutt_i*currentsIn;
            currentsOut=Cbutt_i*statesButt_i+Dbutt_i*currentsIn;
            i_d_pcc_f=currentsOut[1];
            i_q_pcc_f=currentsOut[2];

            # init_x = [init_x;zeros(index-length(init_x))]
            index += 2*(converter.controls[:i_meas_filt].n_f)
            # init_x = [init_x;Id;Iq]

        else

            (i_d_pcc_f, i_q_pcc_f) = (i_d_pcc_c, i_q_pcc_c);
                
        end

        # TODO:  Generalize the case for the absence of power controllers
        if in(:p, keys(converter.controls))
            # add frequency support
            if in(:f_supp, keys(converter.controls))
        
                F[index+1] = (converter.controls[:f_supp].ω_f) *(-(converter.controls[:f_supp].Kₚ)*Δω - x[index+1]);
                p_ref = (converter.controls[:p].ref[1]) + x[index+1]

                index +=1
            else
            
                p_ref = (converter.controls[:p].ref[1])

            end
            # active power control

            P_ac = (Vᴳd_f * i_d_pcc_f + Vᴳq_f * i_q_pcc_f);
            # iΔd_ref = (Kp_Pac * (Pac_ref - Pac) + Ki_Pac * xiPac);
            id_ref = ((converter.controls[:p].Kₚ) * (p_ref - P_ac) +
                            x[index+1]);
            F[index+1] = (converter.controls[:p].Kᵢ) *(p_ref - P_ac)
            index += 1

        elseif in(:dc, keys(converter.controls)) # DC voltage control


            if ((converter.controls[:dc].n_f)) >= 1 # Filtering of Vdc

                

                
                statesButt_vdc= x[index + 1 : index + 1*(converter.controls[:vdc].n_f)]; 
                F[index + 1 : index + 1*(converter.controls[:vdc].n_f)] = Abutt_vdc*statesButt_vdc + Bbutt_vdc*Vdc;
                Vdc_f=dot(Cbutt_vdc,statesButt_vdc)+Dbutt_vdc*Vdc;
            

                # init_x = [init_x;zeros(index-length(init_x))];
                # init_x = [init_x; 1*zeros(converter.controls[:dc].n_f)];
                index += 1*(converter.controls[:dc].n_f)


            else # No filtering of Vdc

                Vdc_f= Vdc;
        
            end


            # DC voltage controller equations

            F[index+1] = (converter.controls[:dc].Kᵢ) * ((converter.controls[:dc].ref[1]) - Vdc_f);
                id_ref = -((converter.controls[:dc].Kₚ) * ((converter.controls[:dc].ref[1]) - Vdc_f) +
                                x[index+1]);

            epsilon_vdc_index = index + 1
            index += 1    

        end
        if in(:q, keys(converter.controls))
            # add voltage support
            if in(:vac_supp, keys(converter.controls))
                #converter.controls[:vac_supp].ref[1] /= vAC_base #Per unitize voltage reference
                
                Vᴳ_mag = sqrt(Vᴳd_f^2 + Vᴳq_f^2);
                Δq_unf = (converter.controls[:vac_supp].Kₚ)*((converter.controls[:vac_supp].ref[1])-Vᴳ_mag);
                F[index+1] = (converter.controls[:vac_supp].ω_f) *(Δq_unf - x[index+1]);
                q_ref = (converter.controls[:q].ref[1]) + x[index+1]

                # init_x = [init_x;zeros(index-length(init_x))] #Initalize states before voltage support to zero
                index +=1
                # init_x = [init_x;converter.controls[:vac_supp].ref[1]]
            else
        
                q_ref = (converter.controls[:q].ref[1])
            end
            # reactive power control

            Q_ac =  (-Vᴳq_f * i_d_pcc_f + Vᴳd_f * i_q_pcc_f);
            iq_ref = ((converter.controls[:q].Kₚ) * (q_ref - Q_ac) +
                            x[index+1]);
            F[index+1] = (converter.controls[:q].Kᵢ) *(q_ref - Q_ac)

            index += 1
            #Small value to converge
        end
        # add control equations         
        if in(:occ, keys(converter.controls))
            # output current control

            F[index+1] = (converter.controls[:occ].Kᵢ) * (id_ref - i_d_pcc_f);
            F[index+2] = (converter.controls[:occ].Kᵢ) * (iq_ref - i_q_pcc_f);

            md_c = 2 * ( x[index+1] +
                        (converter.controls[:occ].Kₚ) * (id_ref - i_d_pcc_f) + Lᵣ * (1 + Δω) * i_q_pcc_f + Vᴳd_f) / Vdc; # 
            mq_c = 2 * ( x[index+2] +
                        (converter.controls[:occ].Kₚ) * (iq_ref - i_q_pcc_f) - Lᵣ * (1 + Δω) * i_d_pcc_f + Vᴳq_f) / Vdc; # 
            (md, mq) = I_θ * [md_c; mq_c]

            index += 2
        end
        

        if !in(:occ, keys(converter.controls))

            md = 0;
            mq = 0

        end


        # add time delays here, if there are controllers implemented
        if (converter.timeDelay != 0.0) && (in(:occ, keys(converter.controls)))
        
            T_ab_dq=0.5*[1 im;-im 1];# from alpha-beta to dq
            T_dq_ab=0.5*[1 -im;im 1];#from dq to alpha-beta
                
            if in(:occ, keys(converter.controls))
                
                timeDelayIn = [md;mq];
                statesDelay = x[index + 1 : index + 2*converter.padeOrderDen]; 
                F[index + 1 : index + 2*converter.padeOrderDen] = A_delay*statesDelay + B_delay*timeDelayIn;
                # timeDelayOut = C_delay*statesDelay + D_delay*timeDelayIn;
                # Implement phase shifts by transforming the dq voltage references to alpha-beta
                m_ab_ref = (cos(converter.ω₀*converter.timeDelay)-sin(converter.ω₀*converter.timeDelay)*im)*(T_dq_ab*(C_delay*statesDelay + D_delay*timeDelayIn));
                m_dq_ref = real(T_ab_dq * conj(m_ab_ref) + conj(T_ab_dq) * m_ab_ref);
                md = m_dq_ref[1];
                mq = m_dq_ref[2];
            
                index += 2*converter.padeOrderDen
            end
            
        end

        # add state variables

        (vMd, vMq) =  0.5* Vdc .* [md; mq]; # 0.5 
        
        # dw neglected here
        F[1] = (vMd - inputs[2] - Rᵣ*x[1] - Lᵣ*x[2])/Lᵣ;             
        F[2] = (vMq - inputs[3] - Rᵣ*x[2] + Lᵣ*x[1])/Lᵣ;       
        F[1:2] *= wbase;

        if solve == :equilibrium
            
            if in(:dc, keys(converter.controls))  
                       
                F[index+1] = wbase * (Idc_in - ((vMd * x[1] + vMq * x[2]) / Vdc)) / Cₑ;
                F[epsilon_vdc_index] = (converter.controls[:dc].Kᵢ) * ((converter.controls[:dc].ref[1]) - x[end]);
        
            end


        elseif solve == :jacobian
            nb_output_var = 3

            F[end-(nb_output_var-1)] = (vMd * x[1] + vMq * x[2]) / Vdc ; # Idc derived based in AC-DC power balance
            F[end-(nb_output_var-2)] = x[1] ; 
            F[end] = x[2] 

        end

        

    end


    ##################################################################################################################################################################################################################
    # Here we iterate over the existing controls in order to determine the dimensions of the state vector 
    # Also we calculate the matrices of the butterworth filters
    # TODO: Passing the matrices as a parameter to state_space!()?

    # add voltage measurement filter
    if in(:v_meas_filt, keys(converter.controls))
        Abutt, Bbutt, Cbutt, Dbutt =  butterworthMatrices(converter.controls[:v_meas_filt].n_f, converter.controls[:v_meas_filt].ω_f, 2);
        index += 2*(converter.controls[:v_meas_filt].n_f) 
        init_x = [init_x;Vᴳd;Vᴳq] #Initalize to avoid steady-state solver problems
    end
    

    # add PLL
    if in(:pll, keys(converter.controls))
        if (converter.controls[:pll].ω_f != 0) # A PLL filter is implemented
            Abutt_pll, Bbutt_pll, Cbutt_pll, Dbutt_pll =  butterworthMatrices(converter.controls[:pll].n_f, converter.controls[:pll].ω_f, 1);

            index += 1*(converter.controls[:pll].n_f)
            
        end

        index += 2
    end


    # add current measurement filter
    if in(:i_meas_filt, keys(converter.controls))
        Abutt_i, Bbutt_i, Cbutt_i, Dbutt_i =  butterworthMatrices(converter.controls[:i_meas_filt].n_f, converter.controls[:i_meas_filt].ω_f, 2);

        index += 2*(converter.controls[:i_meas_filt].n_f)

    end

    # TODO:  Generalize the case for the absence of power controllers
    if in(:p, keys(converter.controls))

        if in(:f_supp, keys(converter.controls))

            index +=1


        end

        index += 1
    elseif in(:dc, keys(converter.controls)) # DC voltage control


        if ((converter.controls[:dc].n_f)) >= 1 # Filtering of Vdc

            Abutt_vdc, Bbutt_vdc, Cbutt_vdc, Dbutt_vdc =  butterworthMatrices(converter.controls[:dc].n_f, converter.controls[:dc].ω_f, 1);
            index += 1*(converter.controls[:dc].n_f)

        end

        epsilon_vdc_index = index + 1
        index += 1    

    end
    if in(:q, keys(converter.controls))
        # add voltage support
        if in(:vac_supp, keys(converter.controls))
            converter.controls[:vac_supp].ref[1] /= vAC_base #Per unitize voltage reference

            index +=1

        end

        index += 1

    end
    # add control equations
    for (key, val) in (converter.controls)                
        if (key == :occ)
            index += 2
        end
    end


    # add time delays here, if there are controllers implemented
    if (converter.timeDelay != 0.0) && (in(:occ, keys(converter.controls)))

            timeDelayOut = timeDelayPadeMatrices(converter.padeOrderNum,converter.padeOrderDen,converter.timeDelay,2);
            
            A_delay = timeDelayOut[1];
            B_delay = timeDelayOut[2];
            C_delay = timeDelayOut[3];
            D_delay = timeDelayOut[4];

            index += 2*converter.padeOrderDen

    end

   
    # Arrange input and state vectors 
    vector_inputs = [Vdc, Vᴳd, Vᴳq]
    #init_x = [init_x;Vᴳd;Vᴳq] #Initalize to avoid steady-state solver problems
    init_x = [init_x; zeros(index-length(init_x))] # We need the index here to determining the number of states in x

    # If there is a dc voltage controller, add an additional equation to represent the dc voltage, only for the steady-state solution
    if in(:dc, keys(converter.controls))  
        init_x =[init_x;Vdc]

    end

    ##################################################Steady state solution###############################################################
    
    g!(du,u,p) = state_space!(p[1], du, u, p[2];solve=p[3]) # g is the state-space formulation used to obtain the steady-state operation point, copy from f, see some lines above
    # g!(du,u,p) = f!(exp, du,u, vector_inputs)

    println("Starting to solve for Steady-State Solution!")
    prob = NonlinearProblem(g!, init_x, (converter, vector_inputs, :equilibrium))
    sol=solve(prob,SSRootfind(TrustRegion()),maxiters=100,abstol = 1e-1,reltol = 1e-1)

    # steady_state_jacobian = ForwardDiff.jacobian(equil!, init_x)
    # converter.debug = [steady_state_jacobian, sol]

    # Command to show solver results
    # println(sol.trace)
    converter.debug = sol
    if SciMLBase.successful_retcode(sol)
        println("TLC steady-state solution found!")
    else
       error("TLC steady-state solution not found!")
    end
    
    # Delete solution for additional equation in case of DC voltage control
    if in(:dc, keys(converter.controls))
        converter.equilibrium = sol.u[1:end-1] 
    else
        converter.equilibrium = sol.u
    end

    number_output = 3
    number_input =3

    h(F,x) = state_space!(converter,F, x[1:end-number_input], x[end-number_input+1:end];solve=:jacobian)
    ha = x -> (F = fill(zero(promote_type(eltype(x), Float64)), index + number_output); h(F, x); return F) # 
    jac = zeros(index + number_output , index + number_input)
    ForwardDiff.jacobian!(jac, ha, [converter.equilibrium' vector_inputs'])
    converter.A = jac[1:index, 1:index] # index indicates the number of state variables
    converter.B = jac[1:index, index+1:end]
    converter.C = jac[index+1:end, 1:index]
    converter.D = jac[index+1:end, index+1:end]

end

function eval_parameters(converter :: TLC, s :: Complex)
    # numerical
    I = Matrix{Complex}(Diagonal([1 for dummy in 1:size(converter.A,1)]))
    # Y = (converter.C*inv(s*I-converter.A))*converter.B + converter.D # This matrix is in pu
    Y = converter.C * ((s*I-converter.A) \ converter.B) + converter.D # This matrix is in pu
    
    #Conversion of admittance from pu to SI
    Y[1,:] *= converter.iDCbase
    Y[:,1] /= converter.vDCbase
    Y[2:3,:] *= converter.iACbase # Base current of the converter side 
    # # # Multiplication with the AC voltage base converts the pu admittance to SI.
    # # # The double division with the turns ratio is actually a multiplication,
    # # # and is needed to bring the grid-side voltage to the converter side.
    Y[:,2:3] /= (converter.vACbase) # Base voltage at the grid side 
    
    # Y *= converter.iACbase / converter.vACbase
    return Y
end


