module PowerImpedancePSCADExt

using PythonCall
using PowerImpedance

const PSCAD = PowerImpedance.PSCAD
const _MHI_XML = PythonCall.pynew()

function _mhi_xml()
    if PythonCall.pyisnull(_MHI_XML)
        try
            PythonCall.pycopy!(_MHI_XML, PythonCall.pyimport("mhi.xml.pscad"))
        catch error
            throw(ErrorException(
                "Unable to import mhi.xml.pscad; install mhi-xml==1.3.0 through CondaPkg. " *
                sprint(showerror, error)
            ))
        end
    end
    return _MHI_XML
end

function _mhi_xml_version()::String
    metadata = PythonCall.pyimport("importlib.metadata")
    return PythonCall.pyconvert(String, metadata.version("mhi-xml"))
end

include("PowerImpedancePSCADExt/rowdefn.jl")
include("PowerImpedancePSCADExt/writer.jl")
include("PowerImpedancePSCADExt/verify.jl")

end
