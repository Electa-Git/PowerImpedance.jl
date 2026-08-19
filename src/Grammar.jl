export ProblemDefinition, AbstractFormulation, AbstractResult, compute

"Abstract supertype for scientific calculation specifications."
abstract type ProblemDefinition end

"Abstract supertype for numerical formulations."
abstract type AbstractFormulation end

"Abstract supertype for typed calculation results."
abstract type AbstractResult end

"Generic entry point for a problem and numerical formulation."
function compute end
