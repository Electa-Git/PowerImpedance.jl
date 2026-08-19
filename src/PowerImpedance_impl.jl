export NetworkBuilder
"""
Copyright (C) 2024  Etch 
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>. 

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>. 
"""
# Default struct values
using Parameters
using DataStructures
using DocStringExtensions

## Overloading of Base functions (TODO: In future from PowerBlocks overloading)
import Base: convert

using ControlSystemsBase: ControlSystemsBase, tf, ss
using DataStructures: DataStructures, OrderedDict
using DelimitedFiles: DelimitedFiles, readdlm
using DocStringExtensions: DocStringExtensions, SIGNATURES, TYPEDEF,
                            TYPEDFIELDS
using ForwardDiff: ForwardDiff
using Interpolations: Interpolations, Line, linear_interpolation, scale
using Ipopt: Ipopt
using JuMP: JuMP, MOI, index, name, primal_feasibility_report
using LaTeXStrings: LaTeXStrings
using LinearAlgebra: LinearAlgebra, Diagonal, I, UpperHessenberg, det, eigvals,
                    eigvecs, hessenberg, mul!, norm, pinv, rank, svdvals
using Logging: Logging, current_logger
using LsqFit: LsqFit, curve_fit
using Markdown: Markdown, @doc_str
using Munkres: Munkres, munkres
using NonlinearSolve: NonlinearSolve
using Parameters: Parameters, @with_kw
using Peaks: Peaks, argmaxima
using Plots: Plots, hline!, palette, plot, plot!, scatter!, vline!
using RobustAndOptimalControl: RobustAndOptimalControl, modal_form
using SteadyStateDiffEq: SteadyStateDiffEq, NonlinearProblem, SciMLBase, solve




# Power flow
import PowerModels, PowerModelsACDC
import InfrastructureModels
const _IM = InfrastructureModels
const _PM = PowerModels
const _PMACDC = PowerModelsACDC
using Ipopt
using JuMP





# COre
include("core/util.jl")
include("core/logging.jl")

# Including all components    
include("Network/Components/AbstractElement.jl")
include("Network/Components/AbstractStateSpace.jl")

# Impedance
include("Network/Components/impedance/impedance.jl")

# Transfromer
include("Network/Components/transformer/transformer.jl")

# Cables and transmission lines
include("Network/Components/transmission_line/transmission_line.jl")
include("Network/Components/transmission_line/cable.jl")
include("Network/Components/transmission_line/overhead_line.jl")
include("Network/Components/transmission_line/blackbox_line.jl")

# Grid or source
include("Network/Components/source/source.jl")
include("Network/Components/source/dc_source.jl")
include("Network/Components/source/ac_source.jl")

# Converter
include("Network/Components/converter/common/conv_power_flow.jl")
include("Network/Components/converter/controller_old.jl") # TODO: To be removed, now necessary for black-box MMC
include("Network/Components/converter/converter.jl")

include("Network/Components/converter/common/kernels/filter.jl")
include("Network/Components/converter/common/kernels/controller.jl")
include("Network/Components/converter/common/kernels/delay.jl")
include("Network/Components/converter/common/kernels/reference_frames.jl")

include("Network/Components/converter/common/loops/measurement.jl")
include("Network/Components/converter/common/loops/synchronization.jl")
include("Network/Components/converter/common/loops/outer_active.jl")
include("Network/Components/converter/common/loops/outer_reactive.jl")
include("Network/Components/converter/common/loops/inner_voltage.jl")
include("Network/Components/converter/common/loops/inner_current.jl")

include("Network/Components/converter/MMC/MMC.jl")
include("Network/Components/converter/TLC/TLC.jl")
include("Network/Components/converter/blackbox_MMC.jl")

# Machines
include("Network/Components/machine/machine.jl")
include("Network/Components/machine/SynchronousMachine.jl")
include("Network/Components/machine/InductionMachine.jl")

# Including network
include("Network/Network.jl")

# Refactoring attempt
# include("core/base.jl")
# include("core/convert.jl")

# New power flow
include("Network/power_flow.jl")

# Scientific calculation definitions
include("Problems.jl")

# Alternative explicit network construction API
include("Network/NetworkBuilder/NetworkBuilder.jl")
import .NetworkBuilder: determine_impedance, make_loopgain

# Including network solvers
include("Network/Solvers/make_abcd.jl")
include("Network/Solvers/make_y.jl")
include("Network/Solvers/make_z.jl")
include("Network/Solvers/determine_impedance.jl")
include("Network/Solvers/make_y_matrix.jl")
include("Network/Solvers/make_y_edge.jl")
include("Network/Solvers/make_y_edge_old.jl")
include("Network/Solvers/make_y_node.jl")
include("Network/Solvers/stability.jl")

# Including tools
include("Tools/abcd_parameters.jl")
include("Tools/kron.jl")
include("Tools/nyquistplot.jl")
include("Tools/small_gain.jl")
include("Tools/stabilitymargin.jl")
include("Tools/EVD.jl")
include("Tools/bodeplot.jl")
include("Tools/passivity.jl")
include("Tools/unstable_frequency.jl")


include("Tools/parametric_stability.jl")
include("Compute.jl")
