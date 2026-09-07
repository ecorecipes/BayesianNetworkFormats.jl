# The intermediate representation shared by all readers and writers.

"""
    NodeKind

Kind of a node in a [`NetworkIR`](@ref): [`ChanceNode`](@ref), [`DecisionNode`](@ref) or
[`UtilityNode`](@ref).
"""
@enum NodeKind ChanceNode DecisionNode UtilityNode

@doc """
    ChanceNode

A chance (nature) node with a conditional probability table over `(parents..., self)`.
""" ChanceNode

@doc """
    DecisionNode

A decision node; its `parents` are information arcs and it carries no table.
""" DecisionNode

@doc """
    UtilityNode

A utility (value) node; its `parents` are the value inputs and its table has one entry per
parent configuration.
""" UtilityNode

const _KIND_NAMES = Dict(ChanceNode => "chance", DecisionNode => "decision",
                         UtilityNode => "utility")
const _KIND_FROM_NAME = Dict(v => k for (k, v) in _KIND_NAMES)

"""
    IRVariable(id; title="", kind=ChanceNode, states=String[], parents=Symbol[], table=nothing,
               deterministic=false, position=nothing, comment="", extras=Dict{Symbol,Any}())

One node of a [`NetworkIR`](@ref).

- `id::Symbol`: the identifier used in the file.
- `title::String`: human-readable label; defaults to the id when the file has none (an
  empty `title` argument is replaced by `string(id)`).
- `kind::NodeKind`: chance, decision or utility.
- `states::Vector{String}`: ordered state names (empty for utility nodes).
- `parents::Vector{Symbol}`: ordered as in the source file. For decisions these are the
  information arcs; for utilities the value inputs.
- `table`: `nothing`, or an `Array{Float64}` in the IR convention: chance nodes
  `size == (n(p1), ..., n(pk), n(self))` normalised over the last axis; utility nodes
  `size == (n(p1), ..., n(pk))`; decisions always `nothing`.
- `deterministic::Bool`: the table is a one-hot function of the parents.
- `position`: `nothing` or an `(x, y)` tuple as stored by the source tool (no axis
  conversion is applied between tools).
- `comment::String`: free-text description.
- `extras::Dict{Symbol,Any}`: format-specific data that survives a round trip through the
  same format (Netica `:levels`, BIF `:properties`, ...). Values must be JSON-serialisable.
"""
struct IRVariable
    id::Symbol
    title::String
    kind::NodeKind
    states::Vector{String}
    parents::Vector{Symbol}
    table::Union{Nothing,Array{Float64}}
    deterministic::Bool
    position::Union{Nothing,Tuple{Float64,Float64}}
    comment::String
    extras::Dict{Symbol,Any}
end

function IRVariable(id; title::AbstractString="", kind::NodeKind=ChanceNode,
                    states=String[],
                    parents=Symbol[], table=nothing, deterministic::Bool=false,
                    position=nothing, comment::AbstractString="",
                    extras=Dict{Symbol,Any}())
    t = isempty(title) ? string(id) : String(title)
    return IRVariable(Symbol(id), t, kind, String[string(s) for s in states],
                      Symbol[Symbol(p) for p in parents], _as_table(table), deterministic,
                      _as_position(position), String(comment), Dict{Symbol,Any}(extras))
end

_as_table(::Nothing) = nothing
_as_table(t::Array{Float64}) = t
_as_table(t::AbstractArray) = convert(Array{Float64}, collect(t))
_as_position(::Nothing) = nothing
_as_position(p) = (Float64(p[1]), Float64(p[2]))

"""
    _with(v::IRVariable; kwargs...)

Copy `v` replacing the given fields.
"""
function _with(v::IRVariable; id=v.id, title=v.title, kind=v.kind, states=v.states,
               parents=v.parents, table=v.table, deterministic=v.deterministic,
               position=v.position, comment=v.comment, extras=v.extras)
    return IRVariable(id; title, kind, states, parents, table, deterministic, position,
                      comment, extras)
end

"""
    MAUNode(id, parents, weights)

A multi-attribute utility node (GeNIe `<mau>`): a weighted sum of the utility nodes listed
in `parents`. Formats without an explicit MAU node (Netica, HUGIN) sum all utility nodes
implicitly, which corresponds to unit weights.
"""
struct MAUNode
    id::Symbol
    parents::Vector{Symbol}
    weights::Vector{Float64}
    function MAUNode(id, parents, weights)
        return new(Symbol(id), Symbol[Symbol(p) for p in parents],
                   Float64[Float64(w) for w in weights])
    end
end

"""
    NetworkIR(name, variables; format=:ir, source="", mau=MAUNode[], extras=Dict{Symbol,Any}())

A Bayesian network or influence diagram as read from (or to be written to) a file.

- `name::String`: network name (`""` when the format has none).
- `variables::Vector{IRVariable}`: in source order.
- `format::Symbol`: the format it was read from (`:dne`, `:xdsl`, `:net`, `:bif`, `:dsc`,
  `:uai`, `:bnir`) or `:ir` when constructed in Julia.
- `source::String`: path or description of the source.
- `mau::Vector{MAUNode}`: multi-attribute utility nodes (GeNIe only).
- `extras::Dict{Symbol,Any}`: network-level format-specific data, for example
  `:skipped` (nodes dropped by a non-strict read) or `:comment`.
"""
struct NetworkIR
    name::String
    variables::Vector{IRVariable}
    format::Symbol
    source::String
    mau::Vector{MAUNode}
    extras::Dict{Symbol,Any}
end

function NetworkIR(name::AbstractString, variables::AbstractVector; format::Symbol=:ir,
                   source::AbstractString="", mau=MAUNode[], extras=Dict{Symbol,Any}())
    return NetworkIR(String(name), IRVariable[v for v in variables], format, String(source),
                     MAUNode[m for m in mau], Dict{Symbol,Any}(extras))
end

function _with(ir::NetworkIR; name=ir.name, variables=ir.variables, format=ir.format,
               source=ir.source, mau=ir.mau, extras=ir.extras)
    return NetworkIR(name, variables; format, source, mau, extras)
end

function Base.show(io::IO, v::IRVariable)
    return print(io, "IRVariable(", repr(v.id), ", ", _KIND_NAMES[v.kind], ", states=",
                 v.states,
                 ", parents=", v.parents, ")")
end

function Base.show(io::IO, ir::NetworkIR)
    nc = count(v -> v.kind == ChanceNode, ir.variables)
    nd = count(v -> v.kind == DecisionNode, ir.variables)
    nu = count(v -> v.kind == UtilityNode, ir.variables)
    print(io, "NetworkIR(", repr(ir.name), ": ", nc, " chance")
    nd > 0 && print(io, ", ", nd, " decision")
    nu > 0 && print(io, ", ", nu, " utility")
    return print(io, "; format=", repr(ir.format), ")")
end

# --- axis helpers ---------------------------------------------------------------------

"""
    from_rowmajor(vals, dims) -> Array{Float64}

Reshape a flat list of numbers laid out row-major over `dims` (the *last* dimension changes
fastest, as in Netica `probs`, HUGIN `data`, GeNIe `<probabilities>` and UAI tables) into a
Julia array of `size == dims`. With `dims == (n(p1), ..., n(pk), n(child))` this yields the IR
convention directly.

```julia
from_rowmajor([0.7, 0.2, 0.1, 0.15, 0.25, 0.6], (2, 3))  # 2×3, row 1 = (0.7, 0.2, 0.1)
```
"""
function from_rowmajor(vals::AbstractVector, dims::Tuple)
    n = prod(dims; init=1)
    length(vals) == n ||
        throw(ArgumentError("from_rowmajor: $(length(vals)) values do not fill dims $(dims) ($(n) entries)"))
    v = Float64[Float64(x) for x in vals]
    N = length(dims)
    N == 0 && return fill(v[1])
    N == 1 && return v
    return permutedims(reshape(v, reverse(dims)...), N:-1:1)
end

from_rowmajor(vals::AbstractVector, dims::AbstractVector) = from_rowmajor(vals, Tuple(dims))

"""
    to_rowmajor(table) -> Vector{Float64}

Inverse of [`from_rowmajor`](@ref): flatten `table` with the last axis fastest.
"""
function to_rowmajor(table::AbstractArray)
    N = ndims(table)
    N <= 1 && return Float64[Float64(x) for x in vec(table)]
    return vec(permutedims(table, N:-1:1))
end

# --- accessors -------------------------------------------------------------------------

"""
    nstates(v::IRVariable)
    nstates(ir::NetworkIR, id)

Number of states of a variable (zero for utility nodes).
"""
nstates(v::IRVariable) = length(v.states)
nstates(ir::NetworkIR, id) = nstates(variable(ir, id))

"""
    variable(ir::NetworkIR, id) -> IRVariable

Look up a variable by id; throws `KeyError(id)` when absent.
"""
function variable(ir::NetworkIR, id)
    s = Symbol(id)
    i = findfirst(v -> v.id == s, ir.variables)
    i === nothing && throw(KeyError(s))
    return ir.variables[i]
end

"""
    chance_nodes(ir) -> Vector{IRVariable}

Chance nodes in source order.
"""
chance_nodes(ir::NetworkIR) = filter(v -> v.kind == ChanceNode, ir.variables)

"""
    decisions(ir) -> Vector{IRVariable}

Decision nodes in source order.
"""
decisions(ir::NetworkIR) = filter(v -> v.kind == DecisionNode, ir.variables)

"""
    utilities(ir) -> Vector{IRVariable}

Utility nodes in source order.
"""
utilities(ir::NetworkIR) = filter(v -> v.kind == UtilityNode, ir.variables)

"""
    has_decisions(ir) -> Bool

`true` when the network contains at least one decision node (i.e. it is an influence diagram).
"""
has_decisions(ir::NetworkIR) = any(v -> v.kind == DecisionNode, ir.variables)

"""
    topological_order(ir) -> Vector{Symbol}

Variable ids ordered so that every parent precedes its children (ties broken by source
order). Throws [`ValidationError`](@ref) if the graph has a cycle or an unknown parent.
"""
function topological_order(ir::NetworkIR)
    ids = [v.id for v in ir.variables]
    index = Dict(id => i for (i, id) in enumerate(ids))
    indeg = zeros(Int, length(ids))
    children = [Int[] for _ in ids]
    for (i, v) in enumerate(ir.variables), p in v.parents
        haskey(index, p) ||
            throw(ValidationError(v.id,
                                  "parent $(p) of $(v.id) is not a variable of the network"))
        push!(children[index[p]], i)
        indeg[i] += 1
    end
    order = Symbol[]
    ready = [i for i in eachindex(ids) if indeg[i] == 0]
    while !isempty(ready)
        i = popfirst!(ready)
        push!(order, ids[i])
        for c in children[i]
            indeg[c] -= 1
            indeg[c] == 0 && push!(ready, c)
        end
    end
    if length(order) != length(ids)
        stuck = [ids[i] for i in eachindex(ids) if indeg[i] > 0]
        throw(ValidationError(first(stuck), "the network has a cycle through $(stuck)"))
    end
    return order
end

# --- validation ------------------------------------------------------------------------

"""
    validate(ir::NetworkIR; atol=1e-6, renormalize=false, allow_missing_tables=false) -> NetworkIR

Check the structural invariants of the IR and return it (with rows rescaled when
`renormalize=true`). Checks: unique variable ids; every parent exists; states are unique and
non-empty for chance/decision nodes and empty for utility nodes; decision nodes have no
table; utility nodes are never parents; the graph is acyclic; MAU nodes reference utility
nodes; every table has the size implied by its parents; chance rows are non-negative and sum
to one within `atol`; utility tables are free of `NaN`. A non-normalised row raises [`NotNormalizedError`](@ref) unless
`renormalize=true` and the row sum is positive. Missing tables raise
[`ValidationError`](@ref) unless `allow_missing_tables=true` (readers allow them, since
Netica files often carry structure without probabilities).
"""
function validate(ir::NetworkIR; atol::Real=1e-6, renormalize::Bool=false,
                  allow_missing_tables::Bool=false)
    index = Dict{Symbol,IRVariable}()
    for v in ir.variables
        haskey(index, v.id) && throw(ValidationError(v.id, "duplicate variable id $(v.id)"))
        index[v.id] = v
    end
    for v in ir.variables
        for p in v.parents
            haskey(index, p) ||
                throw(ValidationError(v.id,
                                      "parent $(p) of $(v.id) is not a variable of the network"))
            index[p].kind == UtilityNode &&
                throw(ValidationError(v.id, "utility node $(p) is a parent of $(v.id)"))
        end
        length(unique(v.parents)) == length(v.parents) ||
            throw(ValidationError(v.id,
                                  "variable $(v.id) lists a parent twice: $(v.parents)"))
        if v.kind == UtilityNode
            isempty(v.states) ||
                throw(ValidationError(v.id, "utility node $(v.id) must not have states"))
        else
            isempty(v.states) &&
                throw(ValidationError(v.id, "variable $(v.id) has no states"))
            length(unique(v.states)) == length(v.states) ||
                throw(ValidationError(v.id,
                                      "variable $(v.id) has duplicate states: $(v.states)"))
        end
        v.kind == DecisionNode && v.table !== nothing &&
            throw(ValidationError(v.id, "decision node $(v.id) must not have a table"))
    end
    topological_order(ir)
    for m in ir.mau
        for p in m.parents
            haskey(index, p) && index[p].kind == UtilityNode ||
                throw(ValidationError(m.id,
                                      "MAU node $(m.id) references $(p), which is not a utility node"))
        end
        length(m.weights) == length(m.parents) ||
            throw(ValidationError(m.id,
                                  "MAU node $(m.id) has $(length(m.weights)) weights for $(length(m.parents)) parents"))
    end
    newvars = IRVariable[]
    changed = false
    for v in ir.variables
        t = v.table
        if t === nothing
            v.kind == DecisionNode || allow_missing_tables ||
                throw(ValidationError(v.id, "variable $(v.id) has no table"))
            push!(newvars, v)
            continue
        end
        pdims = Tuple(nstates(index[p]) for p in v.parents)
        expected = v.kind == UtilityNode ? pdims : (pdims..., nstates(v))
        size(t) == expected ||
            throw(ValidationError(v.id,
                                  "table of $(v.id) has size $(size(t)); expected $(expected) for parents $(v.parents)"))
        if v.kind == ChanceNode
            n = nstates(v)
            newt = t
            for cfg in CartesianIndices(pdims)
                idx = Tuple(cfg)
                row = view(t, idx..., :)
                any(x -> x < 0 || isnan(x), row) &&
                    throw(ValidationError(v.id,
                                          "row $(idx) of the table of $(v.id) has negative or NaN entries"))
                s = sum(row)
                if abs(s - 1) > atol
                    (renormalize && s > 0) || throw(NotNormalizedError(v.id, idx, s))
                    newt === t && (newt = copy(t))
                    for k in 1:n
                        newt[idx..., k] = t[idx..., k] / s
                    end
                    changed = true
                end
            end
            push!(newvars, newt === t ? v : _with(v; table=newt))
        else
            k = findfirst(isnan, t)
            k === nothing ||
                throw(ValidationError(v.id,
                                      "entry $(Tuple(k)) of the table of $(v.id) is NaN"))
            push!(newvars, v)
        end
    end
    return changed ? _with(ir; variables=newvars) : ir
end

# --- comparison ------------------------------------------------------------------------

_canon(x::AbstractDict) = Dict{String,Any}(string(k) => _canon(v) for (k, v) in x)
_canon(x::Union{AbstractVector,Tuple}) = Any[_canon(v) for v in x]
_canon(x::Symbol) = string(x)
_canon(x) = x

function _approx(a::Float64, b::Float64, atol)
    return a == b || abs(a - b) <= atol || (isnan(a) && isnan(b))
end

"""
    differences(a::NetworkIR, b::NetworkIR; atol=0.0, name=true, titles=true, comments=true,
                positions=true, extras=true, mau=true, deterministic=true, order=true,
                format=false, source=false) -> Vector{String}

Human-readable list of the ways `a` and `b` differ (empty when equivalent). Keyword flags
switch individual comparisons off (`deterministic=false` ignores the deterministic flag,
which BIF, DSC, UAI and HUGIN cannot record); `order=false` matches variables by id instead
of position; `atol` is the tolerance for table entries, utilities, MAU weights and positions.
"""
function differences(a::NetworkIR, b::NetworkIR; atol::Real=0.0, name::Bool=true,
                     titles::Bool=true, comments::Bool=true, positions::Bool=true,
                     extras::Bool=true, mau::Bool=true, deterministic::Bool=true,
                     order::Bool=true,
                     format::Bool=false, source::Bool=false)
    out = String[]
    name && a.name != b.name && push!(out, "name: $(repr(a.name)) vs $(repr(b.name))")
    format && a.format != b.format && push!(out, "format: $(a.format) vs $(b.format)")
    source && a.source != b.source &&
        push!(out, "source: $(repr(a.source)) vs $(repr(b.source))")
    ida = [v.id for v in a.variables]
    idb = [v.id for v in b.variables]
    if order
        ida != idb && push!(out, "variables: $(ida) vs $(idb)")
    else
        Set(ida) != Set(idb) && push!(out, "variables: $(sort(ida)) vs $(sort(idb))")
    end
    bindex = Dict(v.id => v for v in b.variables)
    for va in a.variables
        haskey(bindex, va.id) || continue
        vb = bindex[va.id]
        _variable_differences!(out, va, vb; atol, titles, comments, positions, extras,
                               deterministic)
    end
    if mau
        if length(a.mau) != length(b.mau)
            push!(out, "mau: $(length(a.mau)) vs $(length(b.mau)) nodes")
        else
            for (ma, mb) in zip(a.mau, b.mau)
                ma.id == mb.id || push!(out, "mau id: $(ma.id) vs $(mb.id)")
                ma.parents == mb.parents ||
                    push!(out, "mau $(ma.id) parents: $(ma.parents) vs $(mb.parents)")
                (length(ma.weights) == length(mb.weights) &&
                 all(_approx(x, y, atol) for (x, y) in zip(ma.weights, mb.weights))) ||
                    push!(out, "mau $(ma.id) weights: $(ma.weights) vs $(mb.weights)")
            end
        end
    end
    extras && _canon(a.extras) != _canon(b.extras) &&
        push!(out, "network extras: $(a.extras) vs $(b.extras)")
    return out
end

function _variable_differences!(out, va::IRVariable, vb::IRVariable; atol, titles, comments,
                                positions, extras, deterministic=true)
    id = va.id
    va.kind != vb.kind && push!(out, "$(id) kind: $(va.kind) vs $(vb.kind)")
    va.states != vb.states && push!(out, "$(id) states: $(va.states) vs $(vb.states)")
    va.parents != vb.parents && push!(out, "$(id) parents: $(va.parents) vs $(vb.parents)")
    deterministic && va.deterministic != vb.deterministic &&
        push!(out, "$(id) deterministic: $(va.deterministic) vs $(vb.deterministic)")
    ta, tb = va.table, vb.table
    if (ta === nothing) != (tb === nothing)
        push!(out,
              "$(id) table: $(ta === nothing ? "missing" : "present") vs $(tb === nothing ? "missing" : "present")")
    elseif ta !== nothing
        if size(ta) != size(tb)
            push!(out, "$(id) table size: $(size(ta)) vs $(size(tb))")
        else
            bad = findfirst(i -> !_approx(ta[i], tb[i], atol), eachindex(ta))
            bad === nothing ||
                push!(out,
                      "$(id) table entry $(Tuple(CartesianIndices(ta)[bad])): $(ta[bad]) vs $(tb[bad])")
        end
    end
    titles && va.title != vb.title &&
        push!(out, "$(id) title: $(repr(va.title)) vs $(repr(vb.title))")
    comments && va.comment != vb.comment &&
        push!(out, "$(id) comment: $(repr(va.comment)) vs $(repr(vb.comment))")
    if positions
        pa, pb = va.position, vb.position
        if (pa === nothing) != (pb === nothing)
            push!(out, "$(id) position: $(pa) vs $(pb)")
        elseif pa !== nothing &&
               !(_approx(pa[1], pb[1], atol) && _approx(pa[2], pb[2], atol))
            push!(out, "$(id) position: $(pa) vs $(pb)")
        end
    end
    extras && _canon(va.extras) != _canon(vb.extras) &&
        push!(out, "$(id) extras: $(va.extras) vs $(vb.extras)")
    return out
end

"""
    isequivalent(a::NetworkIR, b::NetworkIR; kwargs...) -> Bool

`true` when [`differences`](@ref)`(a, b; kwargs...)` is empty. Use it for cross-format
comparisons, for example `isequivalent(bif, net; name=false, positions=false)`.
"""
isequivalent(a::NetworkIR, b::NetworkIR; kwargs...) = isempty(differences(a, b; kwargs...))

function Base.:(==)(a::IRVariable, b::IRVariable)
    return isempty(_variable_differences!(String[], a, b; atol=0.0, titles=true,
                                          comments=true,
                                          positions=true, extras=true)) && a.id == b.id
end
function Base.hash(v::IRVariable, h::UInt)
    return hash(v.id, hash(v.kind, hash(v.states, hash(v.parents, h))))
end

function Base.:(==)(a::MAUNode, b::MAUNode)
    return a.id == b.id && a.parents == b.parents && a.weights == b.weights
end
Base.hash(m::MAUNode, h::UInt) = hash(m.id, hash(m.parents, hash(m.weights, h)))

function Base.:(==)(a::NetworkIR, b::NetworkIR)
    # `format` and `source` are provenance, not content: excluding them makes `==` agree
    # with `isequivalent` and with `hash`, so the same network read from a path and from an
    # `IOBuffer` compares equal.
    return isequivalent(a, b)
end
Base.hash(ir::NetworkIR, h::UInt) = hash(ir.name, hash([v.id for v in ir.variables], h))

# --- brute-force joint -----------------------------------------------------------------

"""
    JointDistribution(variables, states, table)

Result of [`joint_distribution`](@ref): `table` has one axis per chance variable, in the
order of `variables`, and sums to one.
"""
struct JointDistribution
    variables::Vector{Symbol}
    states::Vector{Vector{String}}
    table::Array{Float64}
end

"""
    joint_distribution(ir::NetworkIR) -> JointDistribution

Brute-force product of all chance-node CPTs, enumerating every joint configuration. Only
for small networks without decision nodes; utility nodes are ignored. This is the oracle
that pins the axis convention: `marginal(read_network(fixture_path("bif/asia.bif")), :dysp)`
must give `[0.4360, 0.5640]`, the published marginal of the *asia* network
[LauritzenSpiegelhalter1988](@cite) as distributed by bnlearn [Scutari2010](@cite).
"""
function joint_distribution(ir::NetworkIR)
    has_decisions(ir) &&
        throw(ValidationError(:network,
                              "joint_distribution requires a network without decision nodes"))
    vars = chance_nodes(ir)
    ids = [v.id for v in vars]
    pos = Dict(id => i for (i, id) in enumerate(ids))
    dims = Tuple(nstates(v) for v in vars)
    axes_of = Vector{Vector{Int}}(undef, length(vars))
    for (i, v) in enumerate(vars)
        v.table === nothing && throw(ValidationError(v.id, "variable $(v.id) has no table"))
        for p in v.parents
            haskey(pos, p) ||
                throw(ValidationError(v.id, "parent $(p) of $(v.id) is not a chance node"))
        end
        axes_of[i] = [[pos[p] for p in v.parents]; pos[v.id]]
    end
    table = zeros(Float64, dims)
    for idx in CartesianIndices(dims)
        p = 1.0
        for (i, v) in enumerate(vars)
            ax = axes_of[i]
            p *= v.table[ntuple(j -> idx[ax[j]], length(ax))...]
            p == 0 && break
        end
        table[idx] = p
    end
    return JointDistribution(ids, [copy(v.states) for v in vars], table)
end

"""
    marginal(ir::NetworkIR, id) -> Vector{Float64}
    marginal(jd::JointDistribution, id) -> Vector{Float64}

Marginal distribution of chance variable `id`, computed from the brute-force joint.
"""
marginal(ir::NetworkIR, id) = marginal(joint_distribution(ir), id)

function marginal(jd::JointDistribution, id)
    s = Symbol(id)
    i = findfirst(==(s), jd.variables)
    i === nothing && throw(KeyError(s))
    others = Tuple(j for j in 1:ndims(jd.table) if j != i)
    return vec(sum(jd.table; dims=others))
end
