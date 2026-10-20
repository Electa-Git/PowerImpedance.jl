export Controller, PI_control, VSE_old, CCQSEM, FFVI

abstract type Controller end


"""
$(TYPEDEF)

Store legacy PI gains, tuning metadata, reference values, and measurement-filter
settings. The block remains available for legacy converter adapters.

$(TYPEDFIELDS)
"""
@with_kw mutable struct PI_control <: Controller
    "Legacy tuning-bandwidth metadata; not read by the current adapter."
    bandwidth :: Union{Int, Float64}  = 0
    "Legacy damping-ratio metadata \\[dimensionless\\]."
    ζ :: Union{Int, Float64}  = 0
    "Proportional gain for normalized signals \\[dimensionless\\]."
    Kₚ :: Union{Int, Float64}  = 0                     # proportional gain [pu]
    "Integral gain for normalized signals \\[s⁻¹\\]."
    Kᵢ :: Union{Int, Float64}  = 0                     # integral gain [pu/s]
    "Reference array; its physical quantity and base depend on the controller slot."
    ref :: Array{Union{Int, Float64}}  = [0]           # reference value
    "Order of the legacy Butterworth measurement filter."
    n_f :: Int = 0                                     # Butterworth Filter order [-]
    "Measurement-filter angular cutoff \\[rad/s\\]."
    ω_f  :: Union{Int, Float64}  = 0                   # Filter cutoff frequency [rad/s]
end

"""
$(TYPEDEF)

Store legacy virtual-swing-equation inertia, damping, droop, reference, and
measurement-filter settings.

$(TYPEDFIELDS)
"""
@with_kw mutable struct VSE_old <: Controller
    "Inertia constant \\[s\\]."
    H :: Union{Int, Float64}  = 0                       # Virtual Inertia [s]
    "Active-power damping gain per normalized frequency difference \\[dimensionless\\]."
    K_d :: Union{Int, Float64}  = 0                     # Damping coefficient [-]
    "Active-power droop gain per normalized frequency difference \\[dimensionless\\]."
    K_ω    :: Union{Int, Float64}  = 0                  # Droop coefficient [-]
    "Active-power reference array \\[MW\\]."
    ref :: Array{Union{Int, Float64}}  = [0]            # Active power reference [MW]
    "Angular-frequency reference on the nominal-frequency base \\[dimensionless\\]."
    ref_ω :: Union{Int, Float64}  = 0                   # Angular frequency reference [pu]
    "Order of the legacy Butterworth measurement filter."
    n_f :: Int = 0                                      # Butterworth Filter order [-]
    "Measurement-filter angular cutoff \\[rad/s\\]."
    ω_f  :: Union{Int, Float64}  = 0                    # Butterworth Filter cutoff frequency [rad/s]
end

"""
$(TYPEDEF)

Store legacy voltage references and virtual-impedance settings for grid-forming control.

$(TYPEDFIELDS)
"""
@with_kw mutable struct CCQSEM <: Controller                 
    "Virtual resistance on the converter base \\[dimensionless\\]."
    Rᵥ :: Union{Int, Float64}  = 0                       # Virtual Resistance [pu]
    "Virtual inductance on the converter base \\[dimensionless\\]."
    Lᵥ :: Union{Int, Float64}  = 0                       # Virtual inductance [pu]
    "d-axis voltage reference on the converter base \\[dimensionless\\]."
    ref_vd :: Union{Int, Float64}  = 0                   # Vd voltage reference [pu]
    "q-axis voltage reference on the converter base \\[dimensionless\\]."
    ref_vq :: Union{Int, Float64}  = 0                   # Vq voltage reference [pu]
    "Order of the legacy Butterworth measurement filter."
    n_f :: Int  = 0                                      # Butterworth Filter order [-]
    "Measurement-filter angular cutoff \\[rad/s\\]."
    ω_f  :: Union{Int, Float64}  = 0                     # Butterworth Filter cutoff frequency [rad/s]


end

"""
$(TYPEDEF)

Store legacy virtual-impedance and transient-virtual-resistance settings.

$(TYPEDFIELDS)
"""
@with_kw mutable struct FFVI <: Controller                 
    "Virtual resistance on the converter base \\[dimensionless\\]."
    Rᵥ :: Union{Int, Float64}  = 0                       # Virtual Resistance [pu]
    "Virtual inductance on the converter base \\[dimensionless\\]."
    Lᵥ :: Union{Int, Float64}  = 0                       # Virtual inductance [pu]
    "Transient virtual resistance on the converter base \\[dimensionless\\]."
    TVR :: Union{Int, Float64}  = 0                      # Transient virtual resistance (TVR) [pu]
    "Transient virtual-resistance cutoff \\[rad/s\\]."
    ω_ₜᵥᵣ :: Union{Int, Float64}  = 0                     # Cutoff frequency of washout filter for TVR [rad/s]
    "d-axis voltage reference on the converter base \\[dimensionless\\]."
    ref_vd :: Union{Int, Float64}  = 0                   # Vd voltage reference [pu]
    "q-axis voltage reference on the converter base \\[dimensionless\\]."
    ref_vq :: Union{Int, Float64}  = 0                   # Vq voltage reference [pu]
end


#############################################Additional functions used within the model#################################################

# function butterworthMatrices(buttOrder,ω_c,numberVars)

#     # Calculation of the state-space representation of a n-order butterworth filter with a gain of 1.
#     # buttOrder = Order of butterworth filter, ω_c= Cutoff frequency of the filter in [rad/s], numberVars= Variables to be filtered max.2 !
   
#     size_A=buttOrder;
#     Ab=zeros(size_A,size_A);
#     Bb=zeros(size_A,1);
#     Bb[end]=1;
#     Cb=zeros(1,size_A);
#     Cb[1]=1;
#     Db=0;
#     Ab[1:end-1,2:end] = Matrix(1.0I, buttOrder-1, buttOrder-1);
    
#     γ=pi/(2*buttOrder)
    
#     # Calculation of the matrix entries in A 
#     # Calculation of the coefficients of the denominator polynominal aₙ*sⁿ+...+a₀
#     for i=0:buttOrder-1
    
        
#         if i==0
    
#             a_i = 1 
#             Ab[end, i+1] = -a_i;
        
#         else 
    
#             a_i = 1; 
#             for μ=1:i
    
#                 a_i=a_i*cos((μ-1)γ)/(sin(μ*γ));
            
#             end
#             Ab[end, i+1] = -a_i * (1/ω_c)^(i)
    
#         end
    
    
#     end
    
#     # Convert from aₙ*sⁿ+...+a₀ to sⁿ+...+a₀ by dividing numerator and denominator by 1/aₙ
#     Ab[end, 1:end]=Ab[end, 1:end]*(ω_c)^buttOrder;
#     Cb[1]=Cb[1]*(ω_c)^buttOrder;
    

#     # Controllable canonical form can create problems while solving for MMC steady-state, espec. when high-order pade delay approximation is used. 
#     # Related to high conditioning number of controllable canonical form.
#     # Transformation to modal form, which results in lower conditioning number.
#     # sys = ss(Ab,Bb,Cb,Db)
#     # sys_modal = modal_form(sys;C1 = true)
#     # Ab= sys_modal[1].A
#     # Bb = sys_modal[1].B
#     # Cb = sys_modal[1].C
#     # Db = sys_modal[1].D


#     # Adjust matrices for multiple,independent inputs, so far only up to 2 possible
#     if numberVars == 1 #One input, one output
#         A_butt=Ab;
#         B_butt=Bb;
#         C_butt=Cb;
#         D_butt=Db;
#     elseif numberVars == 2 #Two inputs, two outputs 
#         A_butt=cat(Ab,Ab;dims=[1,2]);
#         B_butt=cat(Bb,Bb;dims=[1,2]);
#         C_butt=cat(Cb,Cb;dims=[1,2]);
#         D_butt=cat(Db,Db;dims=[1,2]);
#     end
    
#     return A_butt,B_butt,C_butt,D_butt
   
# end 