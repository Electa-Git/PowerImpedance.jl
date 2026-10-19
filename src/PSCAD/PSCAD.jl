"""
    PSCAD

Export PSCAD projects and execute simulations on a configured station.
Module loading does not contact the station or access files.
"""
module PSCAD

using Base64: base64encode
using SHA: sha256
import Downloads
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
$(TYPEDSIGNATURES)

Write a project with `mhi-xml`. Use `PythonCall` to enable this method.

# Arguments

- `plan`: Project components, wires, settings and output channels.
- `path`: Output `.pscx` filename.

# Returns

- `path`: Absolute project filename.
- `mhi_xml_version`: Version of the XML writer.
"""
function _write_project end

"""
$(TYPEDSIGNATURES)

Read a PSCAD project summary through `mhi-xml`. This method requires `PythonCall`.

# Arguments

- `path`: Input `.pscx` filename.

# Returns

- A `ProjectSummary` with component counts, labels, output channels, line rows,
  wrappers, module ports, settings and file version.
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
include("ztool.jl")
include("blocks.jl")
include("emitters/probes.jl")
include("emitters/sources.jl")
include("emitters/impedance.jl")
include("emitters/transformer.jl")
include("emitters/lines.jl")
include("emitters/cables.jl")
include("emitters/machine.jl")
include("emitters/converter_common.jl")
include("emitters/tlc.jl")
include("emitters/mmc.jl")
include("emitters/mmc_energy.jl")
include("emitters/dc_precharge.jl")
include("export.jl")
include("compute.jl")

end
