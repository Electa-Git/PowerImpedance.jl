"""
    PSCAD

Provide interfaces for PSCAD project export and remote PSCAD execution.
Loading this module performs no I/O and never contacts the PSCAD station.
"""
module PSCAD

using Base64: base64encode
using SHA: sha256
import TOML
using Dates: now, UTC
using Printf: @sprintf
using Statistics: mean
using TypedTables: Table
using ..PowerImpedance: PowerImpedance, TYPEDEF, TYPEDFIELDS, TYPEDSIGNATURES
using ..PowerImpedance: AbstractFormulation, AbstractProblemResult, OrderedDict
using ..PowerImpedance: _register_backend!, _require_backend
import ..PowerImpedance: compute

"""
$(TYPEDEF)

Identify the PSCAD execution backend.
"""
struct PSCADBackend end

const PSCAD_VERSION = "5.1.0"
const PROJECT_FILE_VERSION = "5.0.2"

"""
    _write_project(plan, path)

Write the project `plan` to `path` through `mhi-xml`. Implemented by the
`PowerImpedancePSCADExt` extension, which loads with `PythonCall`.
"""
function _write_project end

"""
    read_project_summary(path)

Read a summary of the PSCAD project at `path` through `mhi-xml`. Implemented by
the `PowerImpedancePSCADExt` extension, which loads with `PythonCall`.
"""
function read_project_summary end

function _require_extension()
    if Base.get_extension(PowerImpedance, :PowerImpedancePSCADExt) === nothing
        throw(ArgumentError(
            "export_pscad requires PythonCall: run `using PythonCall` (CondaPkg installs mhi-xml)"
        ))
    end
    return nothing
end

include("types.jl")
include("remote/configuration.jl")
include("remote/files.jl")
include("remote/remote.jl")
include("results.jl")
include("names.jl")
include("netlist.jl")
include("rlc.jl")
include("units.jl")
include("plan.jl")
include("emitters/probes.jl")
include("emitters/sources.jl")
include("emitters/impedance.jl")
include("emitters/lines.jl")
include("export.jl")
include("compute.jl")

end
