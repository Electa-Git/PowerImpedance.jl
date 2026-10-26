export stabilitymargin

"""
$(TYPEDSIGNATURES)

Log phase, gain, or vector margins of a sampled scalar loop gain.
Crossings use the second sample of each crossing pair. Reported values are rounded
to two decimal places, with crossover frequencies in \\[Hz\\].

# Arguments

- `L`: Scalar loop-gain samples \\[dimensionless\\], ordered by frequency.
- `omega`: Corresponding angular frequencies \\[rad/s\\].
- `SM`: Margin selector, `"PM"`, `"GM"`, or `"VM"`. Default: `""`, which logs
  the available selectors.

# Returns

- `nothing`. Margins are written as informational log messages. Phase and gain margins
  are reported as infinite when the scan has no crossing.

# Notes

For phase ``\\theta`` in degrees, wrapped to ``(-360, 0]``, the reported margins are

```math
\\mathrm{PM} = 180 + \\theta, \\qquad
\\mathrm{GM} = -20 \\log_{10}|L|, \\qquad
\\mathrm{VM} = 100 \\min_k |L_k + 1|.
```

Phase margins above 180 degrees are reduced by 360 degrees. Gain margins use negative
real-axis crossings. Vector margin is reported as a percentage at its first minimum.

# Errors

- Propagates `BoundsError` when a reported margin requires a missing frequency entry.
- Throws `ArgumentError` when vector margin is requested for an empty scan.
"""
function stabilitymargin(L, omega; SM :: String = "")

# Stability margins
L_mag = abs.(L)
# L_mag_dB = 20*log10.(L_mag)
L_ph = angle.(L).*(180/π)
for i in 1:length(L_ph)
    if L_ph[i] > 0
        L_ph[i] = L_ph[i] - 360 # Wrapping angle between 0° and -360°
    end
end

##### Phase margin
if SM == "PM"
    counter_PM = 0 
    for i in 2:length(L)
        if (abs(L[i-1]) > 1 && abs(L[i]) < 1) || (abs(L[i-1]) < 1 && abs(L[i]) > 1)
            PM = L_ph[i] + 180
            if PM > 180
                PM = PM - 360
            end
            PM = round(PM, digits = 2)
            f_gcf = round(omega[i]/(2*π), digits = 2)
        
            @info "\t Phase margin is $PM ° at gain crossover frequency $f_gcf Hz"
            counter_PM = counter_PM + 1
        end
    end

    if counter_PM == 0
        @info "\t Infinite phase margin"
    end

##### Gain margin
elseif SM == "GM"
    counter_GM = 0 
    for i in 2:length(L)
        if ((L_ph[i-1] > -180 && L_ph[i] < -180) || (L_ph[i-1] < -180 && L_ph[i] > -180)) && (real(L[i]) < 0)
            GM = -20*log10(L_mag[i])
            GM = round(GM, digits = 2)
            f_pcf = round(omega[i]/(2*π), digits = 2)

            @info "\t Gain margin is $GM dB at phase crossover frequency $f_pcf Hz"
            counter_GM = counter_GM + 1
        end
    end

    if counter_GM == 0
        @info "\t Infinite gain margin"
    end

##### Vector margin
elseif SM == "VM"
    L_VM_dif = abs.(L .+ 1)
    index_VM = findall(x -> x == minimum(L_VM_dif), L_VM_dif)
    index_VM = index_VM[1]
    VM = L_VM_dif[index_VM]*100
    VM = round(VM, digits = 2)
    f_VM = round(omega[index_VM]/(2*π), digits = 2)

    @info "\t Vector margin is $VM % at frequency $f_VM Hz"

else
    @info "\t Indicate the type of stability margin: PM, GM, VM or no"
end

end
