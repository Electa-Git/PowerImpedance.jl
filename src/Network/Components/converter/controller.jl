export PIControl


@with_kw struct PIControl
    Kp :: Float64  = 0  # Proportional gain
    Ki :: Float64  = 0  # Integral gain
end

