export Controller, PIControl

abstract type Controller end

@with_kw struct PIControl <: Controller
    Kp :: Float64  = 0  # Proportional gain
    Ki :: Float64  = 0  # Integral gain
end

