# DSC (Microsoft Bayesian Networks / bnlearn) reader and writer.
#
#   belief network "name"
#   node X { type : discrete [ 2 ] = { "yes", "no" }; }
#   probability ( X | P1, P2 ) {
#     (0, 1) : v, v;      % 0-based parent state indices in parent order, rows in any order
#   }
#   probability ( X ) { v, v; }

function _dsc_name(ts::TokenStream)
    t = peek(ts)
    (t.kind == :ident || t.kind == :string || t.kind == :number) ||
        parse_error(ts, t, "expected a name, got $(_describe(t))")
    next!(ts)
    return t.kind == :number ? _fmt_coord(t.value) : t.text
end

function _dsc_skip_statement!(ts::TokenStream)
    depth = 0
    while true
        t = peek(ts)
        t.kind == :eof && parse_error(ts, t, "unterminated statement")
        if _is(t, :punct, "{") || _is(t, :punct, "(")
            depth += 1
        elseif _is(t, :punct, "}") || _is(t, :punct, ")")
            depth -= 1
        elseif _is(t, :punct, ";") && depth <= 0
            next!(ts)
            return
        end
        next!(ts)
    end
end

"""
    read_dsc(io::IO; file="<string>", strict=true, atol=1e-6, renormalize=false) -> NetworkIR

Parse a `.dsc` file. See [`DSC`](@ref).

The `.dsc` grammar is the one written by MSBNx [Kadie2001](@cite) and by bnlearn: a
`probability` block holds one row per parent configuration, labelled with 0-based state
indices in parent order, so row order does not matter.
"""
function read_dsc(io::IO; file::AbstractString="<string>", strict::Bool=true,
                  atol::Real=1e-6,
                  renormalize::Bool=false)
    ts = TokenStream(read(io, String), DSC_TOKENS; file)
    name = ""
    order = Symbol[]
    states_of = Dict{Symbol,Vector{String}}()
    titles = Dict{Symbol,String}()
    positions = Dict{Symbol,Tuple{Float64,Float64}}()
    parents_of = Dict{Symbol,Vector{Symbol}}()
    tables = Dict{Symbol,Array{Float64}}()
    while peek(ts).kind != :eof
        t = expect!(ts, :ident)
        if t.text == "belief"
            expect!(ts, :ident, "network")
            name = _dsc_name(ts)
            accept!(ts, :punct, ";")
        elseif t.text == "node"
            id = Symbol(_dsc_name(ts))
            haskey(states_of, id) && parse_error(ts, t, "node $(id) is declared twice")
            expect!(ts, :punct, "{")
            states = String[]
            while !_is(peek(ts), :punct, "}")
                a = peek(ts)
                if _is(a, :ident, "type")
                    next!(ts)
                    accept!(ts, :punct, ":") === nothing && accept!(ts, :punct, "=")
                    expect!(ts, :ident, "discrete")
                    expect!(ts, :punct, "[")
                    n = expect_int!(ts)
                    expect!(ts, :punct, "]")
                    expect!(ts, :punct, "=")
                    expect!(ts, :punct, "{")
                    while !_is(peek(ts), :punct, "}")
                        push!(states, _dsc_name(ts))
                        accept!(ts, :punct, ",")
                    end
                    next!(ts)
                    accept!(ts, :punct, ";")
                    length(states) == n ||
                        parse_error(ts, a,
                                    "node $(id) declares $(n) states but lists $(length(states))")
                elseif _is(a, :ident, "name")
                    next!(ts)
                    accept!(ts, :punct, ":") === nothing && accept!(ts, :punct, "=")
                    titles[id] = _dsc_name(ts)
                    accept!(ts, :punct, ";")
                elseif _is(a, :ident, "position")
                    next!(ts)
                    accept!(ts, :punct, ":") === nothing && accept!(ts, :punct, "=")
                    expect!(ts, :punct, "(")
                    x = expect!(ts, :number).value
                    accept!(ts, :punct, ",")
                    y = expect!(ts, :number).value
                    expect!(ts, :punct, ")")
                    accept!(ts, :punct, ";")
                    positions[id] = (x, y)
                elseif a.kind == :ident
                    _dsc_skip_statement!(ts)
                else
                    parse_error(ts, a, "unexpected $(_describe(a)) in node $(id)")
                end
            end
            next!(ts)
            push!(order, id)
            states_of[id] = states
        elseif t.text == "probability"
            expect!(ts, :punct, "(")
            id = Symbol(_dsc_name(ts))
            parents = Symbol[]
            if accept!(ts, :punct, "|") !== nothing
                while !_is(peek(ts), :punct, ")")
                    push!(parents, Symbol(_dsc_name(ts)))
                    accept!(ts, :punct, ",")
                end
            end
            expect!(ts, :punct, ")")
            haskey(states_of, id) ||
                parse_error(ts, t, "probability block for undeclared node $(id)")
            for p in parents
                haskey(states_of, p) ||
                    parse_error(ts, t, "parent $(p) of $(id) is not a declared node")
            end
            haskey(parents_of, id) &&
                parse_error(ts, t, "node $(id) has two probability blocks")
            parents_of[id] = parents
            n = length(states_of[id])
            pdims = Tuple(length(states_of[p]) for p in parents)
            table = fill(NaN, pdims..., n)
            expect!(ts, :punct, "{")
            while !_is(peek(ts), :punct, "}")
                a = peek(ts)
                if _is(a, :punct, "(")
                    next!(ts)
                    idxs = Int[]
                    while !_is(peek(ts), :punct, ")")
                        push!(idxs, expect_int!(ts))
                        accept!(ts, :punct, ",")
                    end
                    next!(ts)
                    expect!(ts, :punct, ":")
                    length(idxs) == length(parents) ||
                        parse_error(ts, a,
                                    "row $(idxs) of $(id) has $(length(idxs)) indices; expected $(length(parents))")
                    for j in eachindex(idxs)
                        0 <= idxs[j] < pdims[j] ||
                            parse_error(ts, a,
                                        "index $(idxs[j]) is out of range for parent $(parents[j]) of $(id)")
                    end
                    vals = _bif_numbers(ts)
                    length(vals) == n || parse_error(ts, a,
                                                     "row $(idxs) of $(id) has $(length(vals)) entries; expected $(n)")
                    table[(idxs .+ 1)..., :] .= vals
                elseif a.kind == :number
                    isempty(parents) ||
                        parse_error(ts, a, "row of $(id) without parent indices")
                    vals = _bif_numbers(ts)
                    length(vals) == n || parse_error(ts, a,
                                                     "table of $(id) has $(length(vals)) entries; expected $(n)")
                    table .= vals
                else
                    parse_error(ts, a,
                                "unexpected $(_describe(a)) in probability block of $(id)")
                end
            end
            next!(ts)
            bad = findfirst(isnan, table)
            bad === nothing ||
                throw(ParseError("probability block of $(id) has no row for parent configuration $(Tuple(CartesianIndices(table)[bad])[1:(end - 1)] .- 1)";
                                 file, line=t.line, column=t.column))
            tables[id] = table
        else
            parse_error(ts, t, "unexpected $(_describe(t)) at top level")
        end
    end
    vars = IRVariable[IRVariable(id; title=get(titles, id, ""), states=states_of[id],
                                 parents=get(parents_of, id, Symbol[]),
                                 table=get(tables, id, nothing),
                                 position=get(positions, id, nothing)) for id in order]
    return _finish_read(name, vars, DSC(), file; atol, renormalize)
end

# --- writer ----------------------------------------------------------------------------

_dsc_string(s) = "\"" * replace(String(s), "\\" => "\\\\", "\"" => "\\\"") * "\""

"""
    write_dsc(io::IO, ir::NetworkIR)

Write `ir` as a `.dsc` file in the bnlearn dialect (rows with 0-based parent indices, first
parent fastest). Chance nodes only; titles and positions are not written.
"""
function write_dsc(io::IO, ir::NetworkIR)
    _check_writable(ir, DSC())
    index = _index(ir)
    println(io, "belief network ", _dsc_string(isempty(ir.name) ? "unknown" : ir.name))
    for v in ir.variables
        println(io, "node ", _identifier(v.id), " {")
        println(io, "  type : discrete [ ", nstates(v), " ] = { ",
                join(_dsc_string.(v.states), ", "), " };")
        println(io, "}")
    end
    for v in ir.variables
        table = _require_table(v, DSC())
        print(io, "probability ( ", _identifier(v.id))
        isempty(v.parents) || print(io, " | ", join(_identifier.(v.parents), ", "))
        println(io, " ) {")
        pdims = _parent_dims(index, v)
        if isempty(pdims)
            println(io, "   ", join(_fmt.(table), ", "), ";")
        else
            for cfg in CartesianIndices(pdims)
                idx = Tuple(cfg)
                println(io, "  (", join(idx .- 1, ", "), ") : ",
                        join(_fmt.(table[idx..., :]), ", "), ";")
            end
        end
        println(io, "}")
    end
    return nothing
end
