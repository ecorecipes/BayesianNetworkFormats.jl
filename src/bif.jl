# BIF (Bayesian Interchange Format) reader and writer, bnlearn / pgmpy dialect.
#
#   network Name { property ...; }
#   variable X { type discrete [ 2 ] { yes, no }; property position = (x, y) ; }
#   probability ( X | P1, P2 ) {
#     table v, v, ...;            % header order (X, P1, P2), LAST variable fastest (child slowest)
#     (s1, s2) v, v;              % one child row per parent configuration, rows in any order
#     default v, v;
#   }
#
# Names may be quoted strings. `property` lines are kept verbatim in `extras[:properties]`,
# except `position = (x, y)`, which becomes the variable position.

const _POSITION_RE = r"position\s*=\s*\(\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*\)"

function _bif_name(ts::TokenStream)
    t = peek(ts)
    (t.kind == :ident || t.kind == :string || t.kind == :number) ||
        parse_error(ts, t, "expected a name, got $(_describe(t))")
    next!(ts)
    return t.kind == :number ? _fmt_coord(t.value) : t.text
end

function _bif_property(ts::TokenStream)
    first = expect!(ts, :ident, "property")
    last = first
    while !_is(peek(ts), :punct, ";")
        peek(ts).kind == :eof && parse_error(ts, first, "unterminated property")
        last = next!(ts)
    end
    next!(ts)
    return String(strip(source_text(ts, first, last)[(length("property") + 1):end]))
end

function _bif_numbers(ts::TokenStream)
    vals = Float64[]
    while !_is(peek(ts), :punct, ";")
        t = peek(ts)
        if t.kind == :number
            push!(vals, t.value)
            next!(ts)
        elseif _is(t, :punct, ",")
            next!(ts)
        else
            parse_error(ts, t, "expected a number, got $(_describe(t))")
        end
    end
    next!(ts)
    return vals
end

"""
    read_bif(io::IO; file="<string>", strict=true, atol=1e-6, renormalize=false) -> NetworkIR

Parse a BIF file. See [`BIF`](@ref).

Both dialects of the Interchange Format for Bayesian Networks [Cozman1998](@cite) are read:
the bnlearn / pgmpy row form `(s1, s2) v, v;`, whose rows are labelled by parent state names
and so may appear in any order, and the specification's `table` form, whose numbers are in
header order `(child, parents...)` with the last variable fastest.
"""
function read_bif(io::IO; file::AbstractString="<string>", strict::Bool=true,
                  atol::Real=1e-6,
                  renormalize::Bool=false)
    ts = TokenStream(read(io, String), BIF_TOKENS; file)
    name = ""
    netprops = String[]
    order = Symbol[]
    states_of = Dict{Symbol,Vector{String}}()
    props_of = Dict{Symbol,Vector{String}}()
    positions = Dict{Symbol,Tuple{Float64,Float64}}()
    parents_of = Dict{Symbol,Vector{Symbol}}()
    tables = Dict{Symbol,Array{Float64}}()
    while peek(ts).kind != :eof
        t = expect!(ts, :ident)
        if t.text == "network"
            name = _bif_name(ts)
            expect!(ts, :punct, "{")
            while !_is(peek(ts), :punct, "}")
                _is(peek(ts), :ident, "property") ||
                    parse_error(ts, "expected 'property' or '}' in network block")
                push!(netprops, _bif_property(ts))
            end
            next!(ts)
        elseif t.text == "variable"
            id = Symbol(_bif_name(ts))
            haskey(states_of, id) && parse_error(ts, t, "variable $(id) is declared twice")
            expect!(ts, :punct, "{")
            states = String[]
            props = String[]
            while !_is(peek(ts), :punct, "}")
                a = peek(ts)
                if _is(a, :ident, "type")
                    next!(ts)
                    expect!(ts, :ident, "discrete")
                    expect!(ts, :punct, "[")
                    n = Int(expect!(ts, :number).value)
                    expect!(ts, :punct, "]")
                    expect!(ts, :punct, "{")
                    while !_is(peek(ts), :punct, "}")
                        push!(states, _bif_name(ts))
                        accept!(ts, :punct, ",")
                    end
                    next!(ts)
                    accept!(ts, :punct, ";")
                    length(states) == n ||
                        parse_error(ts, a,
                                    "variable $(id) declares $(n) states but lists $(length(states))")
                elseif _is(a, :ident, "property")
                    p = _bif_property(ts)
                    m = match(_POSITION_RE, p)
                    if m !== nothing
                        positions[id] = (parse(Float64, m.captures[1]),
                                         parse(Float64, m.captures[2]))
                    else
                        push!(props, p)
                    end
                else
                    parse_error(ts, a, "unexpected $(_describe(a)) in variable $(id)")
                end
            end
            next!(ts)
            push!(order, id)
            states_of[id] = states
            props_of[id] = props
        elseif t.text == "probability"
            expect!(ts, :punct, "(")
            id = Symbol(_bif_name(ts))
            parents = Symbol[]
            if accept!(ts, :punct, "|") !== nothing
                while !_is(peek(ts), :punct, ")")
                    push!(parents, Symbol(_bif_name(ts)))
                    accept!(ts, :punct, ",")
                end
            end
            expect!(ts, :punct, ")")
            haskey(states_of, id) ||
                parse_error(ts, t, "probability block for undeclared variable $(id)")
            for p in parents
                haskey(states_of, p) ||
                    parse_error(ts, t, "parent $(p) of $(id) is not a declared variable")
            end
            haskey(parents_of, id) &&
                parse_error(ts, t, "variable $(id) has two probability blocks")
            parents_of[id] = parents
            n = length(states_of[id])
            pdims = Tuple(length(states_of[p]) for p in parents)
            table = fill(NaN, pdims..., n)
            expect!(ts, :punct, "{")
            while !_is(peek(ts), :punct, "}")
                a = peek(ts)
                if _is(a, :ident, "table")
                    next!(ts)
                    vals = _bif_numbers(ts)
                    dims = (n, pdims...)
                    length(vals) == prod(dims) ||
                        parse_error(ts, a,
                                    "table of $(id) has $(length(vals)) entries; expected $(prod(dims)) for parents $(parents) and $(n) states")
                    A = from_rowmajor(vals, dims)              # (child, parents...)
                    table = isempty(pdims) ? A :
                            permutedims(A, (2:(length(pdims) + 1)..., 1))
                elseif _is(a, :ident, "default")
                    next!(ts)
                    vals = _bif_numbers(ts)
                    length(vals) == n || parse_error(ts, a,
                                                     "default row of $(id) has $(length(vals)) entries; expected $(n)")
                    for cfg in CartesianIndices(pdims), k in 1:n
                        isnan(table[Tuple(cfg)..., k]) &&
                            (table[Tuple(cfg)..., k] = vals[k])
                    end
                elseif _is(a, :ident, "property")
                    push!(get!(props_of, id, String[]), _bif_property(ts))
                elseif _is(a, :punct, "(")
                    next!(ts)
                    names = String[]
                    while !_is(peek(ts), :punct, ")")
                        push!(names, _bif_name(ts))
                        accept!(ts, :punct, ",")
                    end
                    next!(ts)
                    length(names) == length(parents) ||
                        parse_error(ts, a,
                                    "row $(names) of $(id) has $(length(names)) parent states; expected $(length(parents))")
                    idx = ntuple(length(parents)) do j
                        k = findfirst(==(names[j]), states_of[parents[j]])
                        k === nothing && parse_error(ts, a,
                                                     "$(repr(names[j])) is not a state of $(parents[j]) (row of $(id))")
                        return k
                    end
                    vals = _bif_numbers(ts)
                    length(vals) == n || parse_error(ts, a,
                                                     "row $(names) of $(id) has $(length(vals)) entries; expected $(n)")
                    table[idx..., :] .= vals
                else
                    parse_error(ts, a,
                                "unexpected $(_describe(a)) in probability block of $(id)")
                end
            end
            next!(ts)
            bad = findfirst(isnan, table)
            bad === nothing ||
                throw(ParseError("probability block of $(id) has no row for parent configuration $(Tuple(CartesianIndices(table)[bad])[1:(end - 1)])";
                                 file, line=t.line, column=t.column))
            tables[id] = table
        else
            parse_error(ts, t, "unexpected $(_describe(t)) at top level")
        end
    end
    vars = IRVariable[]
    for id in order
        extras = Dict{Symbol,Any}()
        isempty(props_of[id]) || (extras[:properties] = props_of[id])
        push!(vars,
              IRVariable(id; states=states_of[id], parents=get(parents_of, id, Symbol[]),
                         table=get(tables, id, nothing),
                         position=get(positions, id, nothing), extras))
    end
    extras = Dict{Symbol,Any}()
    isempty(netprops) || (extras[:properties] = netprops)
    return _finish_read(name, vars, BIF(), file; extras, atol, renormalize)
end

# --- writer ----------------------------------------------------------------------------

const _SIMPLE_NAME_RE = r"^[A-Za-z_][A-Za-z0-9_\-.]*$"

function _bif_quote(s::AbstractString)
    return occursin(_SIMPLE_NAME_RE, s) ? String(s) :
           "\"" * replace(String(s), "\\" => "\\\\", "\"" => "\\\"") * "\""
end
_bif_quote(s::Symbol) = _bif_quote(String(s))

"""
    write_bif(io::IO, ir::NetworkIR)

Write `ir` as a BIF file in the bnlearn dialect: `table` for root nodes, one
`(s1, s2) v, v;` row per parent configuration (first parent fastest) otherwise. Positions are
written as `property position = (x, y) ;`. Chance nodes only.
"""
function write_bif(io::IO, ir::NetworkIR)
    _check_writable(ir, BIF())
    index = _index(ir)
    println(io, "network ", _bif_quote(isempty(ir.name) ? "unknown" : ir.name), " {")
    for p in get(ir.extras, :properties, String[])
        println(io, "  property ", p, ";")
    end
    println(io, "}")
    for v in ir.variables
        println(io, "variable ", _bif_quote(v.id), " {")
        println(io, "  type discrete [ ", nstates(v), " ] { ",
                join(_bif_quote.(v.states), ", "), " };")
        v.position === nothing ||
            println(io, "  property position = (", _fmt_coord(v.position[1]), ", ",
                    _fmt_coord(v.position[2]), ") ;")
        for p in get(v.extras, :properties, String[])
            println(io, "  property ", p, ";")
        end
        println(io, "}")
    end
    for v in ir.variables
        table = _require_table(v, BIF())
        print(io, "probability ( ", _bif_quote(v.id))
        isempty(v.parents) || print(io, " | ", join(_bif_quote.(v.parents), ", "))
        println(io, " ) {")
        pdims = _parent_dims(index, v)
        if isempty(pdims)
            println(io, "  table ", join(_fmt.(table), ", "), ";")
        else
            for cfg in CartesianIndices(pdims)      # first parent fastest, as bnlearn writes
                idx = Tuple(cfg)
                names = [_bif_quote(index[v.parents[j]].states[idx[j]])
                         for j in eachindex(idx)]
                println(io, "  (", join(names, ", "), ") ",
                        join(_fmt.(table[idx..., :]), ", "), ";")
            end
        end
        println(io, "}")
    end
    return nothing
end
