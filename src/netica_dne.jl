# Netica .dne reader and writer.
#
# Grammar (recursive descent over DNE_TOKENS):
#   file  := 'bnet' IDENT block
#   block := '{' item* '}' ';'?
#   item  := IDENT '=' value ';'                    (attribute)
#          | IDENT (IDENT | NUMBER | STRING)? block  (nested block: node, visual, NodeSet, link, ...)
#   value := NUMBER | STRING | IDENT | IDENT block | STATEINDEX | '(' entries? ')'
#   entries := entry (',' entry)*                    (an entry may be empty)
#
# Table layout: `probs` and `functable` are row-major over (parents..., child) with the child
# fastest. Old Netica writes them as one flat list, new Netica nests one parenthesis level per
# parent; both are read by collecting every number regardless of nesting. `@imposs` is 0.
# A state-index literal `#k` (0-based) names the k-th state of the node: in a `functable` it
# is that state, in `probs` it stands for a one-hot row, and in `evidence = #k` it is the
# finding entered on the node (kept in `extras[:evidence]` as the state name).
#
# Empty list entries: Netica writes nothing between two commas to mean "no value at this
# position", as in `inputs = (, G);` (an input link with no name of its own) and
# `statetitles = (, , , "greatly decreased");` (states with no display title). An empty entry
# holds a position, so it is parsed as `DneEmpty()` rather than dropped: dropping it would
# shift every later entry and so silently permute parent order or state order. `()` stays the
# empty list, and a trailing comma (`(a, )`) is not an entry.

"""
    DneStateIndex(index)

A Netica `#k` state-index literal (0-based) as it appears in a parsed value.
"""
struct DneStateIndex
    index::Int
end

Base.show(io::IO, si::DneStateIndex) = print(io, "#", si.index)

"""
    DneEmpty()

An empty entry in a Netica parenthesised list, as in `inputs = (, G);`. It marks a position
for which the file gives no value; keeping it in the parsed value is what stops the entries
after it from shifting up.
"""
struct DneEmpty end

Base.show(io::IO, ::DneEmpty) = print(io, "<empty list entry>")

"""
    _dne_isempty(x) -> Bool

`true` for a [`DneEmpty`](@ref) placeholder produced by an empty list entry.
"""
_dne_isempty(x) = x isa DneEmpty

struct DneBlock
    kind::String
    name::String
    attrs::Vector{Pair{String,Any}}
    children::Vector{DneBlock}
end

function _dne_attr(b::DneBlock, key::AbstractString, default=nothing)
    for (k, v) in b.attrs
        k == key && return v
    end
    return default
end

function _dne_child(b::DneBlock, kind::AbstractString)
    i = findfirst(c -> c.kind == kind, b.children)
    return i === nothing ? nothing : b.children[i]
end

function _dne_value(ts::TokenStream)
    t = peek(ts)
    if t.kind == :number
        next!(ts)
        return t.value
    elseif t.kind == :string
        next!(ts)
        return t.text
    elseif t.kind == :stateindex
        next!(ts)
        return DneStateIndex(Int(t.value))
    elseif t.kind == :ident
        next!(ts)
        _is(peek(ts), :punct, "{") && return _dne_block(ts, t.text, "")
        return Symbol(t.text)
    elseif _is(t, :punct, "(")
        next!(ts)
        vals = Any[]
        while true
            u = peek(ts)
            u.kind == :eof && parse_error(ts, t, "unterminated list")
            if _is(u, :punct, ")")
                next!(ts)
                break
            elseif _is(u, :punct, ",")
                # a comma where a value was expected: an empty entry, which keeps its
                # position so that the entries after it are not shifted up
                next!(ts)
                push!(vals, DneEmpty())
            else
                push!(vals, _dne_value(ts))
                accept!(ts, :punct, ",")
            end
        end
        return vals
    end
    return parse_error(ts, t, "expected a value, got $(_describe(t))")
end

function _dne_block(ts::TokenStream, kind::AbstractString, name::AbstractString)
    open = expect!(ts, :punct, "{")
    attrs = Pair{String,Any}[]
    children = DneBlock[]
    while true
        t = peek(ts)
        if _is(t, :punct, "}")
            next!(ts)
            accept!(ts, :punct, ";")
            break
        elseif t.kind == :eof
            parse_error(ts, open, "unterminated block $(kind) $(name)")
        elseif t.kind == :ident
            next!(ts)
            nt = peek(ts)
            if _is(nt, :punct, "=")
                next!(ts)
                v = _dne_value(ts)
                accept!(ts, :punct, ";")
                push!(attrs, t.text => v)
            elseif _is(nt, :punct, "{")
                push!(children, _dne_block(ts, t.text, ""))
            elseif nt.kind in (:ident, :number, :string) && _is(peek(ts, 1), :punct, "{")
                next!(ts)
                push!(children, _dne_block(ts, t.text, nt.text))
            else
                parse_error(ts, nt,
                            "expected '=' or '{' after $(repr(t.text)), got $(_describe(nt))")
            end
        else
            parse_error(ts, t, "unexpected $(_describe(t)) in block $(kind) $(name)")
        end
    end
    return DneBlock(String(kind), String(name), attrs, children)
end

const _DNE_SYMBOLS = Dict{Symbol,Float64}(Symbol("@imposs") => 0.0, :INFINITY => Inf,
                                          Symbol("-INFINITY") => -Inf, :TRUE => 1.0,
                                          :FALSE => 0.0)

"""
    read_dne(io::IO; file="<string>", strict=true, atol=1e-6, renormalize=false) -> NetworkIR

Parse a Netica `.dne` file. See [`NeticaDNE`](@ref).

`probs` and `functable` are read row-major over `(parents..., child)` with the child fastest
(nesting is ignored), `@imposs` as `0`, a state-index literal `#k` as the 0-based k-th state
of the node (a one-hot row in `probs`, the state itself in a `functable`), and `evidence`
as a finding kept in `extras[:evidence]`; `levels` gives the interval or value of each state.
These semantics follow the Netica file-format documentation [NeticaFileFormats](@cite).
"""
function read_dne(io::IO; file::AbstractString="<string>", strict::Bool=true,
                  atol::Real=1e-6,
                  renormalize::Bool=false)
    ts = TokenStream(read(io, String), DNE_TOKENS; file)
    while !(_is(peek(ts), :ident, "bnet") || peek(ts).kind == :eof)
        next!(ts)
    end
    peek(ts).kind == :eof && parse_error(ts, "no 'bnet' block found")
    next!(ts)
    name = expect!(ts, :ident).text
    bnet = _dne_block(ts, "bnet", name)
    return _dne_network(bnet, file, strict, atol, renormalize)
end

_dne_sym(x) = x isa Symbol ? x : Symbol(string(x))
_dne_list(x) = x isa AbstractVector ? x : Any[x]

function _dne_network(bnet::DneBlock, file, strict, atol, renormalize)
    skipped = Dict{String,Any}[]
    states_of = Dict{Symbol,Vector{String}}()
    dropped = Dict{Symbol,String}()          # node id => node type, for accurate messages
    keep = DneBlock[]
    for nb in bnet.children
        nb.kind == "node" || continue
        id = nb.name
        kind = _dne_sym(_dne_attr(nb, "kind", :NATURE))
        if kind == :CONSTANT
            _skip!(skipped, id, "CONSTANT",
                   "constant / title nodes are not part of the model")
            dropped[Symbol(id)] = "CONSTANT"
            continue
        elseif !(kind in (:NATURE, :DECISION, :UTILITY))
            strict && throw(UnsupportedNodeError(id, String(kind), :dne))
            _skip!(skipped, id, String(kind), "unsupported node kind")
            dropped[Symbol(id)] = String(kind)
            continue
        end
        names = _dne_attr(nb, "states")
        if names !== nothing && any(_dne_isempty, _dne_list(names))
            # a state with no name has no identity in the IR, so it cannot be represented
            strict && throw(UnsupportedNodeError(id, "state with no name", :dne,
                                                 "node $(id) has an empty entry in its states list; a state with no name cannot be represented in the IR"))
            _skip!(skipped, id, String(kind), "empty entry in states")
            dropped[Symbol(id)] = "state with no name"
            continue
        end
        states = _dne_states(nb, kind, file)
        if states === nothing
            strict &&
                throw(UnsupportedNodeError(id, "continuous node without levels", :dne))
            _skip!(skipped, id, "continuous", "continuous node without levels")
            dropped[Symbol(id)] = "continuous node without levels"
            continue
        end
        states_of[Symbol(id)] = states
        push!(keep, nb)
    end
    vars = IRVariable[]
    for nb in keep
        v = _dne_variable(nb, states_of, file, strict, skipped, dropped)
        v === nothing || push!(vars, v)
    end
    _drop_orphans!(vars, skipped)
    extras = Dict{Symbol,Any}()
    title = _dne_attr(bnet, "title")
    title === nothing || (extras[:title] = string(title))
    comment = _dne_attr(bnet, "comment")
    comment === nothing || (extras[:comment] = string(comment))
    return _finish_read(bnet.name, vars, NeticaDNE(), file; extras, skipped, atol,
                        renormalize)
end

_dne_discrete(nb::DneBlock) = _dne_sym(_dne_attr(nb, "discrete", :TRUE)) != :FALSE

# A `states = (...)` entry as a state name; numeric names print like the other formats
# (`0`, not `0.0`).
_dne_state_name(s) = s isa Real ? _fmt_coord(s) : string(s)

# `statetitles` entries as strings. An empty entry is a state Netica gave no display title,
# so it falls back to the state's own id: `fallback[i]` is the `states` entry at that
# position, or the generated name `s(i-1)` when the node has no `states` list of its own.
function _dne_state_titles(titles, fallback)
    return String[_dne_isempty(t) ? fallback[i] : string(t) for (i, t) in enumerate(titles)]
end

# State names, in order of preference: `states`; `levels` (one value per state of a
# discrete node, named by `statetitles` when present, or the interval labels of a
# continuous node); `statetitles` alone; `numstates`. `nothing` for a continuous node
# without levels. `states` with an empty entry is rejected by the caller.
function _dne_states(nb::DneBlock, kind::Symbol, file)
    kind == :UTILITY && return String[]
    states = _dne_attr(nb, "states")
    states === nothing || return String[_dne_state_name(s) for s in _dne_list(states)]
    titles = _dne_attr(nb, "statetitles")
    if titles !== nothing
        entries = _dne_list(titles)
        titles = _dne_state_titles(entries,
                                   String["s$(i - 1)" for i in eachindex(entries)])
    end
    levels = _dne_attr(nb, "levels")
    if levels !== nothing
        lv = _flatten_numbers(levels, nb.name, file; symbols=_DNE_SYMBOLS)
        _dne_discrete(nb) || return _level_labels(lv)
        titles !== nothing && length(titles) == length(lv) && return titles
        return String[_fmt_coord(x) for x in lv]
    end
    titles === nothing || return titles
    numstates = _dne_attr(nb, "numstates")
    numstates === nothing && return nothing
    (numstates isa Real && !(numstates isa Bool) && isinteger(numstates) &&
     0 <= numstates < 2.0^63) ||
        throw(ParseError("numstates of node $(nb.name) must be a nonnegative integer, got $(repr(numstates))";
                         file))
    return String["s$(i - 1)" for i in 1:Int(numstates)]
end

function _dne_variable(nb::DneBlock, states_of, file, strict, skipped,
                       dropped=Dict{Symbol,String}())
    id = Symbol(nb.name)
    kind = _dne_sym(_dne_attr(nb, "kind", :NATURE))
    plist = _dne_list(_dne_attr(nb, "parents", Any[]))
    slot = findfirst(_dne_isempty, plist)
    if slot !== nothing
        # an unconnected parent slot: there is no node to put in `parents`, and dropping the
        # slot would renumber every later parent against the columns of the table
        strict &&
            throw(UnsupportedNodeError(String(id), "parent slot with no node", :dne,
                                       "entry $(slot) of the parents list of node $(id) is empty; an unconnected parent slot cannot be represented in the IR"))
        _skip!(skipped, id, String(kind), "empty entry $(slot) in parents")
        return nothing
    end
    parents = Symbol[Symbol(p) for p in plist]
    for p in parents
        haskey(states_of, p) && continue
        why = get(dropped, p, nothing)
        if why === nothing
            strict &&
                throw(ParseError("parent $(p) of node $(id) is not a node of the network";
                                 file))
            _skip!(skipped, id, String(kind), "parent $(p) is not a node of the network")
        else
            # `p` is a node of the network, but one the IR cannot hold (a CONSTANT, most
            # often used as a named constant in an equation node).
            strict &&
                throw(UnsupportedNodeError(String(p), why, :dne,
                                           "node $(p) of type $(why) is a parent of $(id); the $(why) node cannot be represented in the IR"))
            _skip!(skipped, id, String(kind),
                   why == "CONSTANT" ? "parent $(p) is a CONSTANT node" :
                   "parent $(p) was skipped")
        end
        return nothing
    end
    pdims = Tuple(length(states_of[p]) for p in parents)
    states = states_of[id]
    title = string(something(_dne_attr(nb, "title"), ""))
    comment = string(something(_dne_attr(nb, "comment"), ""))
    position = nothing
    vis = _dne_child(nb, "visual")
    if vis !== nothing
        center = _dne_attr(vis, "center")
        if center isa AbstractVector && length(center) == 2
            all(x -> x isa Real && !(x isa Bool), center) ||
                throw(ParseError("visual center of node $(id) is not a pair of numbers: $(repr(center))";
                                 file))
            position = (Float64(center[1]), Float64(center[2]))
        end
    end
    extras = Dict{Symbol,Any}()
    levels = _dne_attr(nb, "levels")
    if levels !== nothing
        lv = _flatten_numbers(levels, id, file; symbols=_DNE_SYMBOLS)
        if _dne_discrete(nb) && kind != :UTILITY
            # a discrete node's levels are the numeric values of its states
            length(lv) == length(states) ||
                throw(ParseError("levels of discrete node $(id) has $(length(lv)) entries; expected one per state ($(length(states)))";
                                 file))
            extras[:state_values] = lv
        else
            extras[:levels] = lv
        end
    end
    inputs = _dne_attr(nb, "inputs")
    if inputs !== nothing
        # `inputs` names the input links of the node, one per parent and in parent order; an
        # empty entry is a link Netica gave no name of its own. The gap is kept as `""` so
        # that the names stay aligned with `parents`.
        names = _dne_list(inputs)
        length(names) == length(parents) ||
            throw(ParseError("inputs of node $(id) has $(length(names)) entries; expected one per parent ($(length(parents)))";
                             file))
        extras[:inputs] = String[_dne_isempty(x) ? "" : string(x) for x in names]
    end
    if kind != :UTILITY
        evidence = _dne_evidence(_dne_attr(nb, "evidence"), states, id, file)
        evidence === nothing || (extras[:evidence] = evidence)
    end
    chance = _dne_sym(_dne_attr(nb, "chance", :CHANCE))
    table = nothing
    deterministic = false
    if kind == :NATURE
        functable = _dne_attr(nb, "functable")
        probs = _dne_attr(nb, "probs")
        if chance == :DETERMIN && functable !== nothing
            table = _dne_onehot(functable, states, pdims, id, extras, file)
            deterministic = true
        elseif probs !== nothing
            probs = _dne_expand_state_indices(probs, states, id, file)
            vals = _flatten_numbers(probs, id, file; symbols=_DNE_SYMBOLS)
            dims = (pdims..., length(states))
            length(vals) == prod(dims) ||
                throw(ParseError("probs of $(id) has $(length(vals)) entries; expected $(prod(dims)) for parents $(parents) and $(length(states)) states";
                                 file))
            table = from_rowmajor(vals, dims)
            deterministic = chance == :DETERMIN
        end
        return IRVariable(id; title, kind=ChanceNode, states, parents, table, deterministic,
                          position, comment, extras)
    elseif kind == :UTILITY
        src = something(_dne_attr(nb, "functable"), _dne_attr(nb, "probs"), Some(nothing))
        if src !== nothing
            vals = _flatten_numbers(src, id, file; symbols=_DNE_SYMBOLS)
            length(vals) == prod(pdims; init=1) ||
                throw(ParseError("functable of utility $(id) has $(length(vals)) entries; expected $(prod(pdims; init=1)) for parents $(parents)";
                                 file))
            table = from_rowmajor(vals, pdims)
        end
        return IRVariable(id; title, kind=UtilityNode, parents, table, position, comment,
                          extras)
    else
        return IRVariable(id; title, kind=DecisionNode, states, parents, position, comment,
                          extras)
    end
end

# Entries of a `functable` are state names, `#k` state indices, or numbers: a state value
# of a discrete node with `levels`, or a value inside one of the intervals of a continuous
# node.
function _dne_onehot(functable, states, pdims, id, extras, file)
    entries = Any[]
    _dne_flatten!(entries, functable)
    names = String[]
    values = get(extras, :state_values, nothing)
    levels = get(extras, :levels, nothing)
    for e in entries
        if e isa Symbol
            push!(names, String(e))
        elseif e isa DneStateIndex
            push!(names, states[_dne_state_number(e, states, id, file)])
        elseif e isa Number && values !== nothing
            k = findfirst(==(e), values)
            k === nothing &&
                throw(ParseError("functable value $(e) of $(id) is not one of its state values";
                                 file))
            push!(names, states[k])
        elseif e isa Number && levels !== nothing
            k = _level_bin(levels, e)
            k == 0 &&
                throw(ParseError("functable value $(e) of $(id) is outside its levels";
                                 file))
            k <= length(states) ||
                throw(ParseError("functable value $(e) of $(id) falls in level interval $(k), but the node has only $(length(states)) states";
                                 file))
            push!(names, states[k])
        else
            throw(ParseError("unexpected entry $(repr(e)) in the functable of $(id)"; file))
        end
    end
    return _onehot(names, states, pdims, id, file)
end

function _dne_flatten!(out, x)
    if x isa AbstractVector
        foreach(y -> _dne_flatten!(out, y), x)
    else
        push!(out, x)
    end
    return out
end

# 1-based position of the state named by a `#k` literal, checked against the node's states.
function _dne_state_number(si::DneStateIndex, states, id, file)
    0 <= si.index < length(states) ||
        throw(ParseError("state index $(si) of node $(id) is out of range; the node has $(length(states)) states";
                         file))
    return si.index + 1
end

# Replace every `#k` in a `probs` value by the one-hot row over the node's states.
function _dne_expand_state_indices(x, states, id, file)
    if x isa DneStateIndex
        row = zeros(Float64, length(states))
        row[_dne_state_number(x, states, id, file)] = 1.0
        return row
    elseif x isa AbstractVector
        return Any[_dne_expand_state_indices(y, states, id, file) for y in x]
    end
    return x
end

# The `evidence` attribute (a finding entered on the node) as a state name, or a number for
# a continuous finding; `nothing` when absent.
function _dne_evidence(ev, states, id, file)
    ev === nothing && return nothing
    ev isa DneStateIndex && return states[_dne_state_number(ev, states, id, file)]
    ev isa Symbol && return String(ev)
    ev isa Number && return Float64(ev)
    return throw(ParseError("unexpected evidence $(repr(ev)) on node $(id)"; file))
end

# --- writer ----------------------------------------------------------------------------

function _dne_string(s::AbstractString)
    t = replace(String(s), "\\" => "\\\\", "\"" => "\\\"", "\n" => "\\n", "\t" => "\\t")
    return "\"" * t * "\""
end

"""
    write_dne(io::IO, ir::NetworkIR; nested=true)

Write `ir` as a Netica `.dne` file [NeticaFileFormats](@cite). `nested=true` writes `probs`
with one parenthesis level per parent (modern Netica); `nested=false` writes the flat list of
old Netica versions. Both forms are row-major over `(parents..., child)` with the child
fastest; continuous nodes are written with `levels`, and their `states` as well when the IR
has both.
"""
function write_dne(io::IO, ir::NetworkIR; nested::Bool=true)
    _check_writable(ir, NeticaDNE())
    index = _index(ir)
    println(io, "// ~->[DNET-1]->~")
    println(io)
    println(io, "// File created by BayesianNetworkFormats.jl")
    println(io)
    println(io, "bnet ", _identifier(ir.name; default="network"), " {")
    println(io, "autoupdate = TRUE;")
    haskey(ir.extras, :title) &&
        println(io, "title = ", _dne_string(string(ir.extras[:title])), ";")
    haskey(ir.extras, :comment) &&
        println(io, "comment = ", _dne_string(string(ir.extras[:comment])), ";")
    println(io)
    println(io, "visual V1 {")
    println(io, "\tdefdispform = BELIEFBARS;")
    println(io, "\tnodelabeling = NAMETITLE;")
    println(io, "\t};")
    println(io)
    for v in ir.variables
        _write_dne_node(io, v, index, nested)
    end
    return println(io, "};")
end

function _write_dne_node(io::IO, v::IRVariable, index, nested::Bool)
    println(io, "node ", _identifier(v.id), " {")
    levels = get(v.extras, :levels, nothing)
    values = get(v.extras, :state_values, nothing)
    values !== nothing && length(values) != length(v.states) && (values = nothing)
    if v.kind == ChanceNode
        println(io, "\tkind = NATURE;")
        onehot = v.deterministic && v.table !== nothing && _is_onehot(v.table)
        if levels !== nothing
            println(io, "\tdiscrete = FALSE;")
        else
            println(io, "\tdiscrete = TRUE;")
        end
        println(io, "\tchance = ", onehot ? "DETERMIN" : "CHANCE", ";")
    elseif v.kind == DecisionNode
        println(io, "\tkind = DECISION;")
        println(io, "\tdiscrete = TRUE;")
    else
        println(io, "\tkind = UTILITY;")
        println(io, "\tdiscrete = FALSE;")
        println(io, "\tchance = DETERMIN;")
    end
    if levels !== nothing
        # A continuous node whose states carry names of their own (Netica writes both
        # `states` and `levels`) must keep them: writing only `levels` would rename the
        # states to the interval labels on the next read.
        v.kind == UtilityNode || _dne_interval_labels(v, levels) ||
            println(io, "\tstates = (", join(_identifier.(v.states), ", "), ");")
        println(io, "\tlevels = (", join((_dne_level(x) for x in levels), ", "), ");")
    elseif v.kind != UtilityNode
        println(io, "\tstates = (", join(_identifier.(v.states), ", "), ");")
        values === nothing ||
            println(io, "\tlevels = (", join((_dne_level(x) for x in values), ", "), ");")
    end
    _write_dne_inputs(io, v)
    println(io, "\tparents = (", join(_identifier.(v.parents), ", "), ");")
    pdims = _parent_dims(index, v)
    pstates = [index[p].states for p in v.parents]
    pnames = [_identifier(p) for p in v.parents]
    if v.kind == ChanceNode && v.table !== nothing
        if v.deterministic && _is_onehot(v.table)
            # interval states have no identifier; name them by index (#k)
            names = levels === nothing ? _identifier.(v.states) :
                    ["#$(k - 1)" for k in eachindex(v.states)]
            entries = _onehot_entries(v.table, names)
            _write_dne_table(io, "functable", entries, pdims, pstates, pnames, String[],
                             nested)
        else
            vals = _fmt.(to_rowmajor(v.table))
            _write_dne_table(io, "probs", vals, pdims, pstates, pnames,
                             _identifier.(v.states), nested)
        end
    elseif v.kind == UtilityNode && v.table !== nothing
        vals = _fmt.(to_rowmajor(v.table))
        _write_dne_table(io, "functable", vals, pdims, pstates, pnames, String[], nested)
    end
    v.title == _identifier(v.id) || println(io, "\ttitle = ", _dne_string(v.title), ";")
    isempty(v.comment) || println(io, "\tcomment = ", _dne_string(v.comment), ";")
    evidence = get(v.extras, :evidence, nothing)
    evidence === nothing ||
        println(io, "\tevidence = ", _dne_evidence_text(v, evidence), ";")
    if v.position !== nothing
        println(io, "\tvisual V1 {")
        println(io, "\t\tcenter = (", _fmt_coord(v.position[1]), ", ",
                _fmt_coord(v.position[2]), ");")
        println(io, "\t\t};")
    end
    return println(io, "\t};")
end

# Write `extras[:inputs]` back as the `inputs` list, with an unnamed link written as the
# empty entry Netica uses (`inputs = (, G);`). The list is positional against `parents`, so a
# stored list of the wrong length is dropped rather than written out of step (the same rule
# as `extras[:state_values]` above).
function _write_dne_inputs(io::IO, v::IRVariable)
    inputs = get(v.extras, :inputs, nothing)
    (inputs === nothing || length(inputs) != length(v.parents) || isempty(inputs)) && return
    cells = [isempty(string(x)) ? "" : _identifier(string(x)) for x in inputs]
    # A trailing separator is not an entry; terminate a final empty slot explicitly.
    ending = isempty(last(cells)) ? "," : ""
    return println(io, "\tinputs = (", join(cells, ", "), ending, ");")
end

_dne_level(x) = x == Inf ? "INFINITY" : x == -Inf ? "-INFINITY" : _fmt_coord(x)

# `true` when the states of a continuous node are exactly the interval labels its `levels`
# generate, so writing `levels` alone reproduces them.
function _dne_interval_labels(v::IRVariable, levels)
    return v.states == _level_labels(levels)
end

# A finding is written as the state identifier, or as `#k` for interval (levels) states.
function _dne_evidence_text(v::IRVariable, evidence)
    evidence isa Number && return _fmt_coord(evidence)
    k = findfirst(==(string(evidence)), v.states)
    k === nothing && return _identifier(string(evidence))
    haskey(v.extras, :levels) && return "#$(k - 1)"
    return _identifier(v.states[k])
end

# `cells` is the flat row-major list of table entries (strings). When `child_states` is
# non-empty the innermost row runs over the child states; otherwise (utility / functable)
# the innermost row runs over the last parent.
function _write_dne_table(io::IO, key, cells::Vector{String}, pdims::Tuple, pstates, pnames,
                          child_states::Vector{String}, nested::Bool)
    if isempty(child_states)
        if isempty(pdims)
            println(io, "\t", key, " = (", cells[1], ");")
            return
        end
        rowdims = pdims[1:(end - 1)]
        rowlen = pdims[end]
        header = pstates[end]
        rowstates = pstates[1:(end - 1)]
        rownames = pnames[1:(end - 1)]
    else
        rowdims = pdims
        rowlen = length(child_states)
        header = child_states
        rowstates = pstates
        rownames = pnames
    end
    width = maximum(length, cells; init=1) + 2
    hwidth = max(width, maximum(length, header; init=1) + 2)
    nrows = prod(rowdims; init=1)
    configs = collect(_rowmajor_configs(rowdims))
    cw = [max(maximum(length, rowstates[j]; init=1), length(rownames[j])) + 1
          for j in eachindex(rowdims)]
    println(io, "\t", key, " = ")
    hdr = "\t\t// " * join((rpad(h, hwidth) for h in header), "")
    if !isempty(rowdims)
        hdr *= " // " * join((rpad(rownames[j], cw[j]) for j in eachindex(rowdims)), "")
    end
    println(io, rstrip(hdr))
    for (r, cfg) in enumerate(configs)
        cellstrs = cells[((r - 1) * rowlen + 1):(r * rowlen)]
        pre = ""
        post = ""
        if nested
            for j in eachindex(rowdims)
                all(cfg[j:end] .== 1) && (pre *= "(")
                all(cfg[j:end] .== rowdims[j:end]) && (post *= ")")
            end
            body = "(" * join((rpad(c * ",", hwidth) for c in cellstrs[1:(end - 1)]), "") *
                   rpad(cellstrs[end] * ")" * post * (r == nrows ? ";" : ","), hwidth + 2)
        else
            pre = r == 1 ? "(" : ""
            last = cellstrs[end] * (r == nrows ? ");" : ",")
            body = join((rpad(c * ",", hwidth) for c in cellstrs[1:(end - 1)]), "") *
                   rpad(last, hwidth + 2)
        end
        line = "\t\t  " * lpad(pre, length(rowdims)) * body
        if !isempty(rowdims)
            line *= "  // " *
                    join((rpad(rowstates[j][cfg[j]], cw[j]) for j in eachindex(rowdims)),
                         "")
        end
        println(io, rstrip(line))
    end
    return
end
