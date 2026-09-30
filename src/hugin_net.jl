# HUGIN .net reader and writer.
#
#   net { node_size = (80 40); name = "..."; }
#   node X { states = ("a" "b"); label = "Title"; position = (100 200); HR_Desc = "comment"; }
#   decision D { states = ("yes" "no"); }
#   utility U { }
#   potential (X | P1 P2) { data = (((0.1 0.9)(0.4 0.6))((0.2 0.8)(0.3 0.7))); }
#   potential (D | I1 I2) { }
#   potential (U | P1) { data = (10 20); }
#
# `data` is row-major over (parents..., child) with the child fastest (one parenthesis level
# per parent); the nesting is ignored when reading. `%` starts a comment.

function _net_value(ts::TokenStream)
    t = peek(ts)
    if t.kind == :number
        next!(ts)
        return t.value
    elseif t.kind == :string
        next!(ts)
        return t.text
    elseif t.kind == :ident
        next!(ts)
        return Symbol(t.text)
    elseif _is(t, :punct, "(")
        next!(ts)
        vals = Any[]
        while !_is(peek(ts), :punct, ")")
            peek(ts).kind == :eof && parse_error(ts, t, "unterminated list")
            push!(vals, _net_value(ts))
            accept!(ts, :punct, ",")
        end
        next!(ts)
        return vals
    end
    return parse_error(ts, t, "expected a value, got $(_describe(t))")
end

function _net_block(ts::TokenStream, what::AbstractString)
    open = expect!(ts, :punct, "{")
    attrs = Pair{String,Any}[]
    while true
        t = peek(ts)
        if _is(t, :punct, "}")
            next!(ts)
            accept!(ts, :punct, ";")
            return attrs
        elseif t.kind == :eof
            parse_error(ts, open, "unterminated block $(what)")
        elseif t.kind == :ident
            next!(ts)
            expect!(ts, :punct, "=")
            v = _net_value(ts)
            accept!(ts, :punct, ";")
            push!(attrs, t.text => v)
        else
            parse_error(ts, t, "unexpected $(_describe(t)) in $(what)")
        end
    end
end

function _net_attr(attrs, key, default=nothing)
    for (k, v) in attrs
        k == key && return v
    end
    return default
end

_net_state(x) = x isa AbstractString ? String(x) : x isa Number ? _fmt_coord(x) : string(x)

struct _NetPotential
    child::Symbol
    parents::Vector{Symbol}
    attrs::Vector{Pair{String,Any}}
    token::Token
end

"""
    read_net(io::IO; file="<string>", strict=true, atol=1e-6, renormalize=false) -> NetworkIR

Parse a HUGIN `.net` file. See [`HuginNET`](@ref).

The grammar is the NET language of the HUGIN API reference manual [HuginNET](@cite): the
`data` of a `potential` is row-major over `(parents..., child)` with the child fastest and
one parenthesis level per parent, and the nesting is ignored when reading.
"""
function read_net(io::IO; file::AbstractString="<string>", strict::Bool=true,
                  atol::Real=1e-6,
                  renormalize::Bool=false)
    ts = TokenStream(read(io, String), NET_TOKENS; file)
    name = ""
    skipped = Dict{String,Any}[]
    nodeinfo = Pair{Symbol,Tuple{NodeKind,Vector{Pair{String,Any}}}}[]
    potentials = _NetPotential[]
    while peek(ts).kind != :eof
        t = expect!(ts, :ident)
        if t.text == "net"
            attrs = _net_block(ts, "net")
            n = _net_attr(attrs, "name")
            n === nothing || (name = string(n))
        elseif t.text in ("node", "decision", "utility")
            id = expect!(ts, :ident).text
            attrs = _net_block(ts, "$(t.text) $(id)")
            kind = t.text == "node" ? ChanceNode :
                   t.text == "decision" ? DecisionNode : UtilityNode
            push!(nodeinfo, Symbol(id) => (kind, attrs))
        elseif t.text in ("continuous", "discrete", "function", "class", "instance")
            words = [t.text]
            while peek(ts).kind == :ident && !_is(peek(ts, 1), :punct, "{")
                push!(words, next!(ts).text)
            end
            id = peek(ts).kind == :ident ? next!(ts).text : ""
            nodetype = join(words, " ")
            if nodetype in ("discrete node",)
                attrs = _net_block(ts, "node $(id)")
                push!(nodeinfo, Symbol(id) => (ChanceNode, attrs))
            else
                strict && throw(UnsupportedNodeError(id, nodetype, :net))
                _net_block(ts, "$(nodetype) $(id)")
                _skip!(skipped, id, nodetype, "unsupported node type")
            end
        elseif t.text == "potential"
            expect!(ts, :punct, "(")
            targets = Symbol[]
            while peek(ts).kind == :ident
                push!(targets, Symbol(next!(ts).text))
            end
            parents = Symbol[]
            if accept!(ts, :punct, "|") !== nothing
                while peek(ts).kind == :ident
                    push!(parents, Symbol(next!(ts).text))
                end
            end
            expect!(ts, :punct, ")")
            attrs = _net_block(ts, "potential $(targets)")
            length(targets) == 1 ||
                parse_error(ts, t,
                            "potential over several nodes $(targets) is not supported")
            push!(potentials, _NetPotential(targets[1], parents, attrs, t))
        else
            parse_error(ts, t, "unexpected $(_describe(t)) at top level")
        end
    end
    states_of = Dict{Symbol,Vector{String}}()
    for (id, (kind, attrs)) in nodeinfo
        states = _net_attr(attrs, "states", Any[])
        kind == UtilityNode || states isa AbstractVector ||
            throw(ParseError("states of node $(id) must be a parenthesised list, got $(repr(states))";
                             file=ts.file))
        states_of[id] = kind == UtilityNode ? String[] :
                        String[_net_state(s) for s in states]
    end
    pots = Dict{Symbol,_NetPotential}()
    for p in potentials
        haskey(pots, p.child) &&
            parse_error(ts, p.token, "node $(p.child) has two potentials")
        pots[p.child] = p
    end
    vars = IRVariable[]
    for (id, (kind, attrs)) in nodeinfo
        title = string(something(_net_attr(attrs, "label"), ""))
        comment = string(something(_net_attr(attrs, "HR_Desc"), ""))
        pos = _net_attr(attrs, "position")
        position = if pos isa AbstractVector && length(pos) == 2
            all(x -> x isa Real && !(x isa Bool), pos) ||
                throw(ParseError("position of node $(id) is not a pair of numbers: $(repr(pos))";
                                 file=ts.file))
            (Float64(pos[1]), Float64(pos[2]))
        else
            nothing
        end
        states = states_of[id]
        pot = get(pots, id, nothing)
        parents = pot === nothing ? Symbol[] : pot.parents
        ok = true
        for p in parents
            haskey(states_of, p) && continue
            strict && parse_error(ts, pot.token,
                                  "parent $(p) of node $(id) is not a node of the network")
            _skip!(skipped, id, _KIND_NAMES[kind], "parent $(p) was skipped")
            ok = false
            break
        end
        ok || continue
        pdims = Tuple(length(states_of[p]) for p in parents)
        table = nothing
        if pot !== nothing && kind != DecisionNode
            data = _net_attr(pot.attrs, "data")
            if data !== nothing
                vals = _flatten_numbers(data, id, file)
                dims = kind == ChanceNode ? (pdims..., length(states)) : pdims
                length(vals) == prod(dims; init=1) ||
                    throw(ParseError("data of potential ($(id) | $(join(parents, ' '))) has $(length(vals)) entries; expected $(prod(dims; init=1))";
                                     file))
                table = from_rowmajor(vals, dims)
            end
        end
        push!(vars, IRVariable(id; title, kind, states, parents, table, position, comment))
    end
    _drop_orphans!(vars, skipped)
    return _finish_read(name, vars, HuginNET(), file; skipped, atol, renormalize)
end

# --- writer ----------------------------------------------------------------------------

function _net_string(s::AbstractString)
    return "\"" * replace(String(s), "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n") * "\""
end

"""
    write_net(io::IO, ir::NetworkIR)

Write `ir` as a HUGIN `.net` file [HuginNET](@cite) with one parenthesis level per parent in
`data` and a `%` comment per row naming the parent configuration. Titles become `label`,
comments the HUGIN GUI attribute `HR_Desc`.
"""
function write_net(io::IO, ir::NetworkIR)
    _check_writable(ir, HuginNET())
    index = _index(ir)
    println(io, "net")
    println(io, "{")
    println(io, "  node_size = (80 40);")
    isempty(ir.name) || println(io, "  name = ", _net_string(ir.name), ";")
    println(io, "}")
    for v in ir.variables
        head = v.kind == ChanceNode ? "node" :
               v.kind == DecisionNode ? "decision" : "utility"
        println(io)
        println(io, head, " ", _identifier(v.id))
        println(io, "{")
        v.title == _identifier(v.id) || println(io, "  label = ", _net_string(v.title), ";")
        isempty(v.comment) || println(io, "  HR_Desc = ", _net_string(v.comment), ";")
        v.position === nothing ||
            println(io, "  position = (", _fmt_coord(v.position[1]), " ",
                    _fmt_coord(v.position[2]), ");")
        v.kind == UtilityNode ||
            println(io, "  states = (", join(_net_string.(v.states), " "), ");")
        println(io, "}")
    end
    for v in ir.variables
        println(io)
        print(io, "potential (", _identifier(v.id))
        isempty(v.parents) || print(io, " | ", join(_identifier.(v.parents), " "))
        println(io, ")")
        println(io, "{")
        if v.kind != DecisionNode && v.table !== nothing
            _write_net_data(io, v, index)
        end
        println(io, "}")
    end
    return nothing
end

function _write_net_data(io::IO, v::IRVariable, index)
    pdims = _parent_dims(index, v)
    vals = _fmt.(to_rowmajor(v.table))
    if v.kind == UtilityNode
        if isempty(pdims)
            println(io, "  data = (", vals[1], ");")
            return
        end
        rowdims = pdims[1:(end - 1)]
        rowlen = pdims[end]
    else
        rowdims = pdims
        rowlen = nstates(v)
    end
    rowparents = v.parents[1:length(rowdims)]
    configs = collect(_rowmajor_configs(rowdims))
    nrows = length(configs)
    println(io, "  data = ")
    for (r, cfg) in enumerate(configs)
        cells = vals[((r - 1) * rowlen + 1):(r * rowlen)]
        pre = ""
        post = ""
        for j in eachindex(rowdims)
            all(cfg[j:end] .== 1) && (pre *= "(")
            all(cfg[j:end] .== rowdims[j:end]) && (post *= ")")
        end
        line = "    " * lpad(pre, length(rowdims)) * "(" * join(cells, " ") * ")" * post
        r == nrows && (line *= ";")
        if !isempty(rowdims)
            line = rpad(line, 40) * "% " *
                   join(("$(_identifier(rowparents[j]))=$(index[rowparents[j]].states[cfg[j]])"
                         for j in eachindex(rowdims)), " ")
        end
        println(io, rstrip(line))
    end
    return
end
