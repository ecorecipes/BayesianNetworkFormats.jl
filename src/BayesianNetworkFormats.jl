"""
    BayesianNetworkFormats

Readers and writers for Bayesian-network and influence-diagram interchange formats
(Netica `.dne`, GeNIe `.xdsl`, HUGIN `.net`, BIF, DSC, UAI) via a common intermediate
representation, [`NetworkIR`](@ref).

The IR axis convention (ADR 0002, SPEC §8.2): a chance node's `table` has
`size == (n(p1), ..., n(pk), n(child))`, normalised over the last axis, where the parent
order is the order of `parents` in the source file. Utility tables are `(n(p1), ..., n(pk))`.

Part of the ecorecipes compositional Bayesian-network ecosystem; this package depends on
nothing else in the ecosystem (ADR 0003).
"""
module BayesianNetworkFormats

using EzXML
using JSON3

export NodeKind, ChanceNode, DecisionNode, UtilityNode
export IRVariable, MAUNode, NetworkIR, JointDistribution
export from_rowmajor, to_rowmajor, validate, nstates, variable, chance_nodes, decisions,
       utilities, has_decisions, topological_order, joint_distribution, marginal,
       isequivalent, differences
export ParseError, UnsupportedNodeError, NotNormalizedError, ValidationError,
       FormatDetectionError, IdentifierCollisionError, IdentifierLengthError
export NetworkFormat, NeticaDNE, GeNIeXDSL, HuginNET, BIF, DSC, UAI, IRJSON
export read_network, write_network, detect_format, format_name, fixture_path
export read_ir_json, write_ir_json, read_uai_evidence, write_uai_evidence

include("exceptions.jl")
include("ir.jl")
include("tokenizer.jl")
include("formats.jl")
include("netica_dne.jl")
include("genie_xdsl.jl")
include("hugin_net.jl")
include("bif.jl")
include("dsc.jl")
include("uai.jl")
include("ir_json.jl")
include("io.jl")

end # module
