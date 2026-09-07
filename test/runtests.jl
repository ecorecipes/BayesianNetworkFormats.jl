using Test
using Random
using BayesianNetworkFormats

const FIX = joinpath(@__DIR__, "fixtures")
fix(name) = joinpath(FIX, name)
golden(name) = read_ir_json(fix(joinpath("golden", name)))

include("reference_models.jl")
include("utils.jl")

@testset "BayesianNetworkFormats" begin
    include("test_ir.jl")
    include("test_tokenizer.jl")
    include("test_dne.jl")
    include("test_xdsl.jl")
    include("test_net.jl")
    include("test_bif.jl")
    include("test_dsc.jl")
    include("test_uai.jl")
    include("test_json.jl")
    include("test_io.jl")
    include("test_roundtrip.jl")
    include("test_crossformat.jl")
    include("test_failures.jl")
end
