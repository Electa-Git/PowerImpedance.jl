# Replace the dependency's signed-active-power initial value with apparent current.
function _initialize_converter_current!(pm)
    for (id, converter) in _PM.ref(pm, :convdc)
        voltage = _PM.ref(pm, :bus, converter["busac_i"])["vm"]
        current = hypot(converter["P_g"], converter["Q_g"]) / voltage
        JuMP.set_start_value(_PM.var(pm, :iconv_ac, id), current)
    end
    return nothing
end
