# JSON serialisation of NetworkIR (`*.bnir.json`), used for golden files.
#
# Keys are written in a fixed order (struct field order; dictionary keys sorted) so that the
# files are diffable. Tables are stored as {"dims": [...], "values": [...]} with the values in
# Julia column-major order (`vec(table)`). Non-finite numbers (Netica levels) are written as
# JSON3's `Infinity` / `-Infinity` extension.

const _BNIR_VERSION = 1

function _json_value(io::IO, x, indent::Int)
    if x === nothing
        print(io, "null")
    elseif x isa Bool
        print(io, x ? "true" : "false")
    elseif x isa Integer
        print(io, x)
    elseif x isa AbstractFloat
        JSON3.write(io, Float64(x); allow_inf=true)
    elseif x isa Union{AbstractString,Symbol}
        JSON3.write(io, string(x))
    elseif x isa NamedTuple
        _json_object(io, [string(k) => v for (k, v) in pairs(x)], indent)
    elseif x isa AbstractDict
        ks = sort!([string(k) for k in keys(x)])
        lookup = Dict(string(k) => v for (k, v) in x)
        _json_object(io, [k => lookup[k] for k in ks], indent)
    elseif x isa Union{AbstractVector,Tuple}
        if isempty(x)
            print(io, "[]")
        elseif all(v -> v isa Union{Number,AbstractString,Symbol,Nothing,Bool}, x)
            print(io, "[")
            for (i, v) in enumerate(x)
                i > 1 && print(io, ", ")
                _json_value(io, v, indent)
            end
            print(io, "]")
        else
            print(io, "[\n")
            for (i, v) in enumerate(x)
                print(io, " "^(indent + 2))
                _json_value(io, v, indent + 2)
                i < length(x) && print(io, ",")
                print(io, "\n")
            end
            print(io, " "^indent, "]")
        end
    else
        throw(ArgumentError("cannot serialise $(typeof(x)) to JSON; extras must hold strings, numbers, booleans, vectors or dicts"))
    end
    return nothing
end

function _json_object(io::IO, kvs, indent::Int)
    if isempty(kvs)
        print(io, "{}")
        return
    end
    print(io, "{\n")
    for (i, (k, v)) in enumerate(kvs)
        print(io, " "^(indent + 2))
        JSON3.write(io, k)
        print(io, ": ")
        _json_value(io, v, indent + 2)
        i < length(kvs) && print(io, ",")
        print(io, "\n")
    end
    return print(io, " "^indent, "}")
end

_table_json(::Nothing) = nothing
_table_json(t::Array{Float64}) = (dims=collect(size(t)), values=vec(t))

function _variable_json(v::IRVariable)
    return (id=v.id, title=v.title, kind=_KIND_NAMES[v.kind], states=v.states,
            parents=v.parents,
            deterministic=v.deterministic, table=_table_json(v.table),
            position=v.position === nothing ? nothing : collect(v.position),
            comment=v.comment,
            extras=v.extras)
end

"""
    write_ir_json(io::IO, ir::NetworkIR)
    write_ir_json(path::AbstractString, ir::NetworkIR)

Serialise `ir` to the package's JSON representation (`*.bnir.json`) with deterministic key
order. Tables are stored as `{"dims", "values"}` in Julia column-major order. The path
method serialises `ir` before touching the file and then replaces it in one step (a
temporary file in the same directory, renamed over `path`), so a failure leaves an existing
file as it was.
"""
function write_ir_json(io::IO, ir::NetworkIR)
    doc = (format="bnir", version=_BNIR_VERSION, name=ir.name, source_format=ir.format,
           source=ir.source, variables=[_variable_json(v) for v in ir.variables],
           mau=[(id=m.id, parents=m.parents, weights=m.weights) for m in ir.mau],
           extras=ir.extras)
    _json_value(io, doc, 0)
    println(io)
    return nothing
end

function write_ir_json(path::AbstractString, ir::NetworkIR)
    _write_atomic(path, _serialise(io -> write_ir_json(io, ir)))
    return nothing
end

_from_json(x::JSON3.Object) = Dict{String,Any}(string(k) => _from_json(v) for (k, v) in x)
_from_json(x::JSON3.Array) = Any[_from_json(v) for v in x]
_from_json(x) = x

# Shape checks for a bnir document (ADR 0015). A well-formed JSON document of the wrong shape
# (a missing key, a value of the wrong type, a fractional or negative dimension) is a
# malformed file, so a `ParseError` naming what is wrong, never the `KeyError`,
# `MethodError` or `InexactError` of reading it unchecked.
_json_number(x) = x isa Real && !(x isa Bool)

function _json_require_object(x, what, file)
    x isa AbstractDict || throw(ParseError("$(what) must be a JSON object"; file))
    return x
end

function _json_get(obj, key::Symbol, ::Type{T}, what, file; default=nothing) where {T}
    if !haskey(obj, key)
        default === nothing && throw(ParseError("$(what) has no \"$(key)\""; file))
        return default
    end
    x = obj[key]
    x isa T || throw(ParseError("\"$(key)\" of $(what) must be a $(_json_kind(T))"; file))
    return x
end

_json_kind(::Type{<:AbstractString}) = "string"
_json_kind(::Type{Bool}) = "boolean"
_json_kind(::Type{<:AbstractVector}) = "list"
_json_kind(::Type{<:AbstractDict}) = "object"

function _json_strings(obj, key, what, file)
    xs = _json_get(obj, key, AbstractVector, what, file)
    all(x -> x isa AbstractString, xs) ||
        throw(ParseError("\"$(key)\" of $(what) must be a list of strings"; file))
    return String[x for x in xs]
end

function _json_numbers(obj, key, what, file)
    xs = _json_get(obj, key, AbstractVector, what, file)
    all(_json_number, xs) ||
        throw(ParseError("\"$(key)\" of $(what) must be a list of numbers"; file))
    return Float64[x for x in xs]
end

function _json_extras(x, what, file)
    x === nothing && return Dict{Symbol,Any}()
    _json_require_object(x, "\"extras\" of $(what)", file)
    return Dict{Symbol,Any}(Symbol(k) => _from_json(v) for (k, v) in x)
end

function _json_table(x, id, file, max_table_cells)
    x === nothing && return nothing
    what = "the table of $(id)"
    _json_require_object(x, what, file)
    raw = _json_numbers(x, :dims, what, file)
    all(d -> isinteger(d) && 0 <= d < 2.0^62, raw) ||
        throw(ParseError("\"dims\" of $(what) must be nonnegative integers, got $(raw)";
                         file))
    dims = Int[Int(d) for d in raw]
    n = _table_length(dims, what, file; max_table_cells)
    vals = _json_numbers(x, :values, what, file)
    length(vals) == n ||
        throw(ParseError("table of $(id) has $(length(vals)) values for dims $(dims)";
                         file))
    isempty(dims) && return fill(vals[1])
    return reshape(vals, dims...)
end

# JSON3's parser recurses once per level of nesting and overflows the stack at about 7 500
# levels, which a 15 KB text reaches, so the depth is checked before parsing against the
# limit of every reader, `_MAX_NESTING` (ADR 0015: check, do not catch). A bnir document
# nests about ten levels deep.

# Whether the brackets of a JSON text, outside its strings, nest at most `_MAX_NESTING`
# levels deep.
function _json_depth_ok(bytes::AbstractVector{UInt8})
    depth = 0
    in_string = false
    escaped = false
    for b in bytes
        if in_string
            if escaped
                escaped = false
            elseif b == UInt8('\\')
                escaped = true
            elseif b == UInt8('"')
                in_string = false
            end
        elseif b == UInt8('"')
            in_string = true
        elseif b == UInt8('[') || b == UInt8('{')
            depth += 1
            depth > _MAX_NESTING && return false
        elseif b == UInt8(']') || b == UInt8('}')
            depth -= 1
        end
    end
    return true
end

# `parse(bytes)`, JSON3's reader in `read_ir_json`. JSON3 reports text that is not JSON with
# an `ArgumentError`, which becomes a `ParseError`; any other exception, an
# `InterruptException` included, is not about the document and propagates unchanged, as in
# the JSON decoders of ADR 0015. The parser is an argument so that a test can raise them.
function _json_parse(parse, bytes, file)
    try
        return parse(bytes)
    catch e
        e isa ArgumentError || rethrow()
        throw(ParseError("invalid JSON: $(sprint(showerror, e))"; file))
    end
end

"""
    read_ir_json(io::IO; file="<string>", max_states=65_536, max_table_cells=2^27) -> NetworkIR
    read_ir_json(path::AbstractString; max_states=65_536, max_table_cells=2^27) -> NetworkIR

Read a `*.bnir.json` file written by [`write_ir_json`](@ref). A leading UTF-8 byte-order
mark is ignored, as by every reader. Text that is not JSON, a document nested more than 512
levels deep, a document of the wrong shape, a variable with more than `max_states` states
and a table with more than `max_table_cells` cells raise [`ParseError`](@ref). Any other
exception, an interrupt included, propagates unchanged.
"""
function read_ir_json(io::IO; file::AbstractString="<string>",
                      max_states::Integer=DEFAULT_MAX_STATES,
                      max_table_cells::Integer=DEFAULT_MAX_TABLE_CELLS)
    _check_limits(max_states, max_table_cells)
    # The text is parsed as bytes: `JSON3.read` of a `String` shorter than 255 bytes that
    # names an existing file reads that file instead, so a document whose whole content is
    # a path would be read from somewhere else.
    bytes = codeunits(String(strip_bom(read(io, String))))
    _json_depth_ok(bytes) ||
        throw(ParseError("the document nests more than $(_MAX_NESTING) levels deep";
                         file))
    doc = _json_parse(b -> JSON3.read(b; allow_inf=true), bytes, file)
    _json_require_object(doc, "a bnir document", file)
    get(doc, :format, "") == "bnir" ||
        throw(ParseError("not a bnir document (missing \"format\": \"bnir\")"; file))
    vars = IRVariable[]
    for (i, v) in
        enumerate(_json_get(doc, :variables, AbstractVector, "the document", file))
        _json_require_object(v, "variable $(i)", file)
        id = _json_get(v, :id, AbstractString, "variable $(i)", file)
        what = "variable $(id)"
        kindname = _json_get(v, :kind, AbstractString, what, file)
        kind = get(_KIND_FROM_NAME, String(kindname), nothing)
        kind === nothing &&
            throw(ParseError("unknown node kind $(repr(kindname)) for $(id)"; file))
        pos = get(v, :position, nothing)
        pos === nothing ||
            (pos isa AbstractVector && length(pos) == 2 && all(_json_number, pos)) ||
            throw(ParseError("\"position\" of $(what) must be a pair of numbers"; file))
        states = _json_strings(v, :states, what, file)
        _check_states(length(states), what, file, max_states)
        push!(vars,
              IRVariable(String(id);
                         title=_json_get(v, :title, AbstractString, what, file; default=""),
                         kind, states,
                         parents=Symbol.(_json_strings(v, :parents, what, file)),
                         table=_json_table(get(v, :table, nothing), id, file,
                                           max_table_cells),
                         deterministic=_json_get(v, :deterministic, Bool, what, file;
                                                 default=false),
                         position=pos === nothing ? nothing :
                                  (Float64(pos[1]), Float64(pos[2])),
                         comment=_json_get(v, :comment, AbstractString, what, file;
                                           default=""),
                         extras=_json_extras(get(v, :extras, nothing), what, file)))
    end
    mau = MAUNode[]
    for (i, m) in enumerate(_json_get(doc, :mau, AbstractVector, "the document", file;
                                      default=Any[]))
        _json_require_object(m, "MAU node $(i)", file)
        mid = _json_get(m, :id, AbstractString, "MAU node $(i)", file)
        push!(mau,
              MAUNode(String(mid),
                      Symbol.(_json_strings(m, :parents, "MAU node $(mid)", file)),
                      _json_numbers(m, :weights, "MAU node $(mid)", file)))
    end
    return NetworkIR(String(_json_get(doc, :name, AbstractString, "the document", file;
                                      default="")), vars;
                     format=Symbol(_json_get(doc, :source_format, AbstractString,
                                             "the document", file; default="bnir")),
                     source=String(_json_get(doc, :source, AbstractString, "the document",
                                             file; default="")), mau,
                     extras=_json_extras(get(doc, :extras, nothing), "the document", file))
end

function read_ir_json(path::AbstractString; kwargs...)
    return open(io -> read_ir_json(io; file=path, kwargs...), path)
end
