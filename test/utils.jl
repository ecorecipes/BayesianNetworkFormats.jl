# Test helpers: round trips through temporary files and random IR generation.

const ALL_WRITABLE = (NeticaDNE(), GeNIeXDSL(), HuginNET(), BIF(), DSC(), UAI(), IRJSON())

"""
    roundtrip(ir, fmt; kwargs...) -> NetworkIR

Write `ir` to a temporary file in format `fmt` and read it back through the path API (so
the UAI names sidecar is exercised).
"""
function roundtrip(ir::NetworkIR, fmt::NetworkFormat; kwargs...)
    mktempdir() do dir
        ext = first(BayesianNetworkFormats._extensions(fmt))
        path = joinpath(dir, "model" * ext)
        write_network(path, ir; format=fmt)
        return read_network(path; format=fmt, kwargs...)
    end
end

"""
    parse_string(text, fmt; kwargs...) -> NetworkIR

Read a network from an in-memory string.
"""
parse_string(text::AbstractString, fmt::NetworkFormat; kwargs...) = read_network(IOBuffer(text),
                                                                                 fmt;
                                                                                 kwargs...)

"""
    write_string(ir, fmt) -> String

Serialise to a string.
"""
function write_string(ir::NetworkIR, fmt::NetworkFormat; kwargs...)
    io = IOBuffer()
    write_network(io, ir, fmt; kwargs...)
    return String(take!(io))
end

function _random_table(rng, pdims, n)
    t = rand(rng, pdims..., n) .+ 0.05
    for cfg in CartesianIndices(pdims)
        row = view(t, Tuple(cfg)..., :)
        row ./= sum(row)
    end
    return t
end

"""
    random_ir(rng; nvars, with_decision=false, with_utility=false) -> NetworkIR

A random DAG over `nvars` chance variables (2-4 states each, at most two parents chosen
among earlier variables), optionally with a decision node (informed by a random subset of
the chance nodes and influencing a further chance node) and a utility node.
"""
function random_ir(rng::AbstractRNG; nvars::Int=rand(rng, 2:6), with_decision::Bool=false,
                   with_utility::Bool=false)
    vars = IRVariable[]
    ids = [Symbol("V$(i)") for i in 1:nvars]
    nst = [rand(rng, 2:4) for _ in 1:nvars]
    for i in 1:nvars
        k = min(i - 1, rand(rng, 0:2))
        parents = sort(shuffle(rng, collect(1:(i - 1)))[1:k])
        pdims = Tuple(nst[p] for p in parents)
        push!(vars,
              IRVariable(ids[i]; states=["s$(j)" for j in 1:nst[i]], parents=ids[parents],
                         table=_random_table(rng, pdims, nst[i])))
    end
    index = Dict(v.id => v for v in vars)
    if with_decision
        k = rand(rng, 0:min(2, nvars))
        info = ids[sort(shuffle(rng, collect(1:nvars))[1:k])]
        nd = rand(rng, 2:3)
        push!(vars,
              IRVariable(:D; kind=DecisionNode, states=["d$(j)" for j in 1:nd],
                         parents=info))
        # a chance node influenced by the decision (and possibly one chance parent)
        extra = rand(rng, Bool) ? [ids[rand(rng, 1:nvars)]] : Symbol[]
        parents = [:D; extra]
        pdims = (nd, (nst[findfirst(==(p), ids)] for p in extra)...)
        push!(vars,
              IRVariable(:W; states=["w1", "w2"], parents,
                         table=_random_table(rng, pdims, 2)))
        index = Dict(v.id => v for v in vars)
    end
    if with_utility
        pool = [v.id for v in vars if v.kind != UtilityNode]
        k = rand(rng, 1:min(2, length(pool)))
        parents = pool[sort(shuffle(rng, collect(1:length(pool)))[1:k])]
        pdims = Tuple(nstates(index[p]) for p in parents)
        push!(vars,
              IRVariable(:U; kind=UtilityNode, parents,
                         table=round.(100 .* rand(rng, pdims...); digits=3)))
    end
    return NetworkIR("random", vars)
end
