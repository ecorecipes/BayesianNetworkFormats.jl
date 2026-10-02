# Format singletons and helpers shared by the readers and writers.

"""
    NetworkFormat

Abstract supertype of the format singletons [`NeticaDNE`](@ref), [`GeNIeXDSL`](@ref),
[`HuginNET`](@ref), [`BIF`](@ref), [`DSC`](@ref), [`UAI`](@ref) and [`IRJSON`](@ref).
"""
abstract type NetworkFormat end

"""
    NeticaDNE()

Netica text format (`.dne`) [NeticaFileFormats](@cite). Reads and writes chance, decision and
utility nodes, `DETERMIN` nodes with `functable`, continuous `levels`, titles, comments and
positions. `CONSTANT` (title-label) nodes are skipped. The binary `.neta` format is out of
scope: save as `.dne` from Netica.
"""
struct NeticaDNE <: NetworkFormat end

"""
    GeNIeXDSL()

GeNIe / SMILE XML format (`.xdsl`) [GeNIeDocs](@cite). Reads and writes `cpt`,
`deterministic`, `decision`, `utility` and `mau` nodes plus the `genie` extension block
(names, positions, comments). `noisymax`, `noisyadder`, `equation` and other node types raise
[`UnsupportedNodeError`](@ref) in strict mode and are skipped otherwise.
"""
struct GeNIeXDSL <: NetworkFormat end

"""
    HuginNET()

HUGIN NET format (`.net`) [HuginNET](@cite). Reads and writes `node`, `decision` and
`utility` blocks with their `potential` tables, labels, positions and `HR_Desc` comments.
`continuous node` and `function node` blocks are unsupported. Decision and utility support
follows the HUGIN NET grammar but has not been verified against the HUGIN application (see
the docs).
"""
struct HuginNET <: NetworkFormat end

"""
    BIF()

Bayesian Interchange Format (`.bif`) [Cozman1998](@cite) as written by bnlearn
[Scutari2010](@cite) and pgmpy. Reads both the row form `(s1, s2) v v;` and the `table` form;
writes the bnlearn row form. Chance nodes only.
"""
struct BIF <: NetworkFormat end

"""
    DSC()

Microsoft Bayesian Networks (MSBNx) / bnlearn `.dsc` format [Kadie2001](@cite). Chance nodes
only.
"""
struct DSC <: NetworkFormat end

"""
    UAI()

The UAI competition text format (`.uai`) [UAIFormat](@cite), `BAYES` networks only. Variable
and state names are synthesised (`X0`, `X1`, ...; `s0`, `s1`, ...) unless a sidecar
`<file>.names` exists; the writer always emits the sidecar.
"""
struct UAI <: NetworkFormat end

"""
    IRJSON()

The package's own JSON serialisation of a [`NetworkIR`](@ref) (`*.bnir.json`), used for
golden files. See [`write_ir_json`](@ref).
"""
struct IRJSON <: NetworkFormat end

"""
    format_name(fmt::NetworkFormat) -> Symbol

Short name recorded in `NetworkIR.format`: `:dne`, `:xdsl`, `:net`, `:bif`, `:dsc`, `:uai`
or `:bnir`.
"""
format_name(::NeticaDNE) = :dne
format_name(::GeNIeXDSL) = :xdsl
format_name(::HuginNET) = :net
format_name(::BIF) = :bif
format_name(::DSC) = :dsc
format_name(::UAI) = :uai
format_name(::IRJSON) = :bnir

_extensions(::NeticaDNE) = (".dne",)
_extensions(::GeNIeXDSL) = (".xdsl",)
_extensions(::HuginNET) = (".net", ".hugin")
_extensions(::BIF) = (".bif",)
_extensions(::DSC) = (".dsc",)
_extensions(::UAI) = (".uai",)
_extensions(::IRJSON) = (".bnir.json", ".json")

const ALL_FORMATS = (NeticaDNE(), GeNIeXDSL(), HuginNET(), BIF(), DSC(), UAI(), IRJSON())

# Identifier policy: how a writer turns IR names into identifiers, and the maximum length
# the format allows (`0` = unlimited). Formats that quote every name (BIF) need neither.
_id_sanitizer(::NetworkFormat) = nothing
_id_sanitizer(::Union{NeticaDNE,GeNIeXDSL,HuginNET,DSC}) = _identifier
_id_sanitizer(::UAI) = _uai_word
_state_sanitizer(::NetworkFormat) = nothing
_state_sanitizer(::Union{NeticaDNE,GeNIeXDSL}) = _identifier
_state_sanitizer(::UAI) = _uai_word
_identifier_limit(::NetworkFormat) = 0
_identifier_limit(::NeticaDNE) = 30

_supports_decisions(::NetworkFormat) = false
_supports_decisions(::Union{NeticaDNE,GeNIeXDSL,HuginNET,IRJSON}) = true
_supports_mau(::NetworkFormat) = false
_supports_mau(::Union{GeNIeXDSL,IRJSON}) = true
_allows_missing_tables(::NetworkFormat) = false
_allows_missing_tables(::Union{NeticaDNE,HuginNET,IRJSON}) = true

# --- shared helpers --------------------------------------------------------------------

"""
    _identifier(s; default="_") -> String

Turn an arbitrary string into a C-style identifier for formats that require one (Netica,
GeNIe, HUGIN): `>=`/`<=`/`>`/`<` become `ge`/`le`/`gt`/`lt`, runs of other characters become
`_`, and a leading digit gets a `_` prefix.
"""
function _identifier(s::AbstractString; default::AbstractString="_")
    t = String(s)
    t = replace(t, ">=" => "ge", "<=" => "le", ">" => "gt", "<" => "lt")
    t = replace(t, r"[^A-Za-z0-9_]+" => "_")
    isempty(t) && (t = String(default))
    isdigit(t[1]) && (t = "_" * t)
    return t
end
_identifier(s::Symbol; kwargs...) = _identifier(String(s); kwargs...)

"""
    _fmt(x) -> String

Shortest round-trip decimal representation of a number for table entries.
"""
_fmt(x::Float64) = string(x)
_fmt(x::Real) = string(Float64(x))

"""
    _fmt_coord(x) -> String

Number formatting for coordinates and levels: integer-valued numbers print without `.0`.
"""
_fmt_coord(x::Real) = (isinteger(x) && abs(x) < 2.0^63) ? string(Int(x)) :
                      string(Float64(x))

_index(ir::NetworkIR) = Dict(v.id => v for v in ir.variables)

"""
    _parent_dims(index, v) -> Tuple

State counts of the parents of `v`, in parent order.
"""
_parent_dims(index, v::IRVariable) = Tuple(nstates(index[p]) for p in v.parents)

"""
    _rowmajor_configs(dims) -> iterator of tuples

Every index tuple over `dims` in row-major order (last dimension fastest), 1-based.
"""
_rowmajor_configs(dims::Tuple) = vec([reverse(Tuple(ci))
                                      for ci in CartesianIndices(reverse(dims))])

"""
    _flatten_numbers(x, id, file; symbols=Dict()) -> Vector{Float64}

Collect every number from a possibly nested list, ignoring the nesting; `symbols` maps
identifier tokens (`@imposs`, `INFINITY`) to values.
"""
function _flatten_numbers(x, id, file; symbols=Dict{Symbol,Float64}())
    out = Float64[]
    _flatten_numbers!(out, x, id, file, symbols)
    return out
end

function _flatten_numbers!(out, x, id, file, symbols)
    if x isa Number
        push!(out, Float64(x))
    elseif x isa AbstractVector
        for y in x
            _flatten_numbers!(out, y, id, file, symbols)
        end
    elseif x isa Symbol && haskey(symbols, x)
        push!(out, symbols[x])
    else
        throw(ParseError("unexpected entry $(repr(x)) in the table of $(id)"; file))
    end
    return out
end

# --- size limits -------------------------------------------------------------------------
#
# A reader allocates a variable's states and a table's cells from sizes that the file
# declares, and a short file can declare any size. Two keywords of every reader bound them
# before anything is allocated, and exceeding either is a `ParseError` that names the
# keyword (ADR 0015).

"""
    DEFAULT_MAX_STATES

Default of the `max_states` keyword of [`read_network`](@ref) and the readers: at most
65 536 states per variable, named or generated.
"""
const DEFAULT_MAX_STATES = 65_536

"""
    DEFAULT_MAX_TABLE_CELLS

Default of the `max_table_cells` keyword of [`read_network`](@ref) and the readers: at
most 2^27 cells per table, 1 GiB of `Float64`.
"""
const DEFAULT_MAX_TABLE_CELLS = 2^27

# The limit keywords must be positive integers; anything else is an invalid keyword, an
# `ArgumentError` (ADR 0013, rule v).
function _check_limits(max_states::Integer, max_table_cells::Integer)
    max_states >= 1 ||
        throw(ArgumentError("max_states must be a positive integer, got $(max_states)"))
    max_table_cells >= 1 ||
        throw(ArgumentError("max_table_cells must be a positive integer, got $(max_table_cells)"))
    return nothing
end

"""
    _check_states(n, what, file, max_states; line=0, column=0) -> Int

`n`, the number of states of `what` (a variable or node, as the message should name it),
or a [`ParseError`](@ref) when it exceeds `max_states`.
"""
function _check_states(n::Integer, what, file, max_states::Integer; line::Integer=0,
                       column::Integer=0)
    n <= max_states ||
        throw(ParseError("$(what) has $(n) states, more than max_states = $(max_states); pass a larger max_states to read it";
                         file, line, column))
    return Int(n)
end

"""
    _table_length(dims, what, file; max_table_cells, line=0, column=0) -> Int

The number of cells of a table whose dimensions `dims` come from file content: their
product, checked before anything is allocated. A product that does not fit an `Int` is a
[`ParseError`](@ref) naming `what` (at `line` and `column` when the reader has a token), as
is one larger than `max_table_cells` (ADR 0015). `prod` would wrap around, and a wrapped
size can match a short list of values, or reach `reshape` or `fill` as an
`ArgumentError`. A zero dimension makes the product zero whatever the others are, as it
does for an `Array`. Pass `max_table_cells=typemax(Int)` for a count that is not a table.
"""
function _table_length(dims, what, file; max_table_cells::Integer, line::Integer=0,
                       column::Integer=0)
    ds = collect(Int, dims)
    any(iszero, ds) && return 0
    shown() = length(ds) <= 8 ? join(ds, " x ") : join(first(ds, 8), " x ") * " x ..."
    n = 1
    for d in ds
        n, overflow = Base.Checked.mul_with_overflow(n, d)
        overflow &&
            throw(ParseError("$(what) has dimensions $(shown()), more cells than a 64-bit integer can count";
                             file, line, column))
    end
    n <= max_table_cells ||
        throw(ParseError("$(what) has $(n) cells (dimensions $(shown())), more than max_table_cells = $(max_table_cells); pass a larger max_table_cells to read it";
                         file, line, column))
    return n
end

"""
    _unnamed_states(n, what, file, max_states) -> Vector{String}

The generated names `s0`, `s1`, ... of `n` states that a file counts but does not name (a
Netica `numstates`, a UAI cardinality with no names-file entry), after checking `n`
against `max_states` (`_check_states`), so that a declared count is never an allocation
size of its own.
"""
function _unnamed_states(n::Integer, what, file, max_states::Integer)
    _check_states(n, what, file, max_states)
    return String["s$(k - 1)" for k in 1:n]
end

"""
    _onehot(entries::Vector{String}, states, pdims, id, file; max_table_cells) -> Array{Float64}

Build a deterministic `(parents..., child)` table from one resulting state per parent
configuration, listed row-major over the parents. The size of the table is checked
against `max_table_cells` before it is allocated.
"""
function _onehot(entries::AbstractVector{<:AbstractString}, states, pdims::Tuple, id, file;
                 max_table_cells::Integer)
    _table_length((pdims..., length(states)), "the table of $(id)", file; max_table_cells)
    n = _table_length(pdims, "the function table of $(id)", file;
                      max_table_cells=typemax(Int))
    length(entries) == n ||
        throw(ParseError("function table of $(id) has $(length(entries)) entries; expected $(n)";
                         file))
    table = zeros(Float64, pdims..., length(states))
    for (k, cfg) in enumerate(_rowmajor_configs(pdims))
        j = findfirst(==(entries[k]), states)
        j === nothing &&
            throw(ParseError("function table of $(id) names $(repr(entries[k])), which is not a state of $(id)";
                             file))
        table[cfg..., j] = 1.0
    end
    return table
end

"""
    _is_onehot(table) -> Bool

`true` when every row of a chance table is a unit vector.
"""
function _is_onehot(table::Array{Float64})
    pdims = size(table)[1:(end - 1)]
    for cfg in CartesianIndices(pdims)
        row = view(table, Tuple(cfg)..., :)
        count(==(1.0), row) == 1 && all(x -> x == 0.0 || x == 1.0, row) || return false
    end
    return true
end

"""
    _onehot_entries(table, states) -> Vector{String}

Resulting state per parent configuration (row-major over parents) of a one-hot table.
"""
function _onehot_entries(table::Array{Float64}, states)
    pdims = size(table)[1:(end - 1)]
    return String[states[findfirst(==(1.0), view(table, cfg..., :))]
                  for cfg in _rowmajor_configs(pdims)]
end

"""
    _skip!(skipped, id, nodetype, reason)

Record a node dropped by a non-strict read.
"""
function _skip!(skipped::Vector{Dict{String,Any}}, id, nodetype, reason)
    push!(skipped,
          Dict{String,Any}("id" => String(id), "type" => String(nodetype),
                           "reason" => String(reason)))
    return skipped
end

"""
    _drop_orphans!(vars, skipped)

Remove (transitively) every variable whose parent was skipped, recording it in `skipped`.
"""
function _drop_orphans!(vars::Vector{IRVariable}, skipped::Vector{Dict{String,Any}})
    changed = true
    while changed
        changed = false
        ids = Set(v.id for v in vars)
        for (i, v) in enumerate(vars)
            missing_parent = findfirst(p -> !(p in ids), v.parents)
            if missing_parent !== nothing
                _skip!(skipped, v.id, _KIND_NAMES[v.kind],
                       "parent $(v.parents[missing_parent]) was skipped")
                deleteat!(vars, i)
                changed = true
                break
            end
        end
    end
    return vars
end

"""
    _finish_read(name, vars, fmt, file; mau, extras, skipped, atol, renormalize) -> NetworkIR

Assemble and validate a freshly parsed network (missing tables allowed).
"""
function _finish_read(name, vars, fmt::NetworkFormat, file; mau=MAUNode[],
                      extras=Dict{Symbol,Any}(),
                      skipped=Dict{String,Any}[], atol=1e-6, renormalize=false)
    isempty(skipped) || (extras[:skipped] = skipped)
    ir = NetworkIR(name, vars; format=format_name(fmt), source=String(file), mau, extras)
    return validate(ir; atol, renormalize, allow_missing_tables=true)
end

"""
    _check_writable(ir, fmt)

Validate `ir` and raise [`UnsupportedNodeError`](@ref) for node kinds the format cannot hold.
"""
function _check_writable(ir::NetworkIR, fmt::NetworkFormat)
    validate(ir; allow_missing_tables=_allows_missing_tables(fmt))
    name = format_name(fmt)
    if !_supports_decisions(fmt)
        for v in ir.variables
            v.kind == ChanceNode ||
                throw(UnsupportedNodeError(v.id, _KIND_NAMES[v.kind], name))
        end
    end
    if !_supports_mau(fmt)
        for m in ir.mau
            all(==(1.0), m.weights) ||
                throw(UnsupportedNodeError(String(m.id), "mau with non-unit weights", name,
                                           "MAU node $(m.id) has weights $(m.weights); the $(name) format only sums utility nodes with unit weights"))
        end
    end
    _check_identifiers(ir, fmt)
    return ir
end

"""
    _check_identifiers(ir, fmt)

Check the names of `ir` *after* the sanitisation the writer for `fmt` applies: two variable
(or MAU) ids, or two states of the same variable, that become the same identifier raise
[`IdentifierCollisionError`](@ref), an identifier longer than the format allows raises
[`IdentifierLengthError`](@ref), and a name the format still cannot hold (`_unwritable`)
raises [`ValidationError`](@ref). Validation alone is not enough, because sanitisation
happens after it and can map distinct IR names onto one file identifier.
"""
function _check_identifiers(ir::NetworkIR, fmt::NetworkFormat)
    name = format_name(fmt)
    limit = _identifier_limit(fmt)
    idfun = _id_sanitizer(fmt)
    if idfun !== nothing
        seen = Dict{String,String}()
        for v in ir.variables
            word = idfun(v.id)
            _check_writable_name(fmt, :variable, word, v.id, v.id)
            _record_identifier!(seen, word, v.id, :network, :variable, limit, name)
        end
        if _supports_mau(fmt)
            for m in ir.mau
                _record_identifier!(seen, idfun(m.id), m.id, :network, :mau, limit, name)
            end
        end
    end
    stfun = _state_sanitizer(fmt)
    if stfun !== nothing
        for v in ir.variables
            seen = Dict{String,String}()
            for s in v.states
                word = stfun(s)
                _check_writable_name(fmt, :state, word, v.id, s)
                _record_identifier!(seen, word, s, v.id, :state, limit, name)
            end
        end
    end
    return ir
end

# A sanitised name that the format still cannot hold: the reason, or `nothing`. Only the UAI
# names file restricts names after sanitisation. It separates names by whitespace, so an
# empty name would vanish and shift the names after it, and a line that starts with `#` is a
# comment, so a variable id, which starts its line, cannot start with `#`.
_unwritable(::NetworkFormat, kind::Symbol, word) = nothing
function _unwritable(::UAI, kind::Symbol, word)
    isempty(word) &&
        return "the names file separates names by whitespace, so an empty name would vanish"
    kind == :variable && startswith(word, '#') &&
        return "a line of the names file that starts with # is a comment"
    return nothing
end

function _check_writable_name(fmt::NetworkFormat, kind::Symbol, word, id, original)
    why = _unwritable(fmt, kind, word)
    why === nothing && return nothing
    what = kind == :state ? "the state $(repr(string(original))) of $(id)" :
           "the variable id $(repr(string(original)))"
    throw(ValidationError(Symbol(id),
                          "$(what) cannot be written in the $(format_name(fmt)) format: $(why); rename it"))
end

function _record_identifier!(seen::Dict{String,String}, sanitized::AbstractString, original,
                             id, kind::Symbol, limit::Int, format::Symbol)
    limit > 0 && length(sanitized) > limit &&
        throw(IdentifierLengthError(id, kind, sanitized, limit, format))
    prev = get(seen, sanitized, nothing)
    prev === nothing ||
        throw(IdentifierCollisionError(id, kind, (prev, string(original)), sanitized,
                                       format))
    seen[String(sanitized)] = String(string(original))
    return seen
end

"""
    _serialise(f) -> Vector{UInt8}

The bytes that `f(io)` writes, collected in memory. The path methods of the writers
serialise first, so that a writer that rejects its input raises before any file is
touched, and then hand the bytes to `_write_atomic`.
"""
function _serialise(f)
    io = IOBuffer()
    f(io)
    return take!(io)
end

"""
    _write_atomic(path, bytes) -> path

Replace the file at `path` with `bytes` in one step: write a temporary file in the same
directory, then rename it over `path`. On any failure the temporary file is removed and
`path` is left as it was, so a failed write never leaves a truncated or partial file. A
symbolic link to an existing file is followed, so its target is replaced, as
`open(path, "w")` would write through it, and an existing file keeps its permission bits.
A missing directory raises `SystemError`, as `open` does.
"""
function _write_atomic(path::AbstractString, bytes::AbstractVector{UInt8})
    target = islink(path) && isfile(path) ? realpath(path) : String(path)
    dir = dirname(abspath(target))
    # name the target, not the temporary file, when the directory is missing
    isdir(dir) || throw(SystemError("opening file $(repr(String(path)))", 2))
    tmp = joinpath(dir,
                   "." * basename(target) * "." * string(rand(UInt64); base=16) * ".tmp")
    try
        open(io -> write(io, bytes), tmp, "w")
        isfile(target) && chmod(tmp, filemode(target) & 0o777)
        Base.rename(tmp, target)
    catch
        rm(tmp; force=true)
        rethrow()
    end
    return path
end

"""
    _require_table(v, fmt)

The table of `v`, or a [`ValidationError`](@ref) when the format needs one and it is missing.
"""
function _require_table(v::IRVariable, fmt::NetworkFormat)
    v.table === nothing &&
        throw(ValidationError(v.id,
                              "variable $(v.id) has no table, which the $(format_name(fmt)) format requires"))
    return v.table
end

"""
    _level_labels(levels) -> Vector{String}

Netica-style interval labels for a `levels` vector (`>= 30`, `20 to 30`, `< 20`).
"""
function _level_labels(levels::AbstractVector{<:Real})
    labels = String[]
    for i in 1:(length(levels) - 1)
        a, b = levels[i], levels[i + 1]
        lo, hi = min(a, b), max(a, b)
        if hi == Inf
            push!(labels, ">= " * _fmt_coord(lo))
        elseif lo == -Inf
            push!(labels, "< " * _fmt_coord(hi))
        else
            push!(labels, _fmt_coord(lo) * " to " * _fmt_coord(hi))
        end
    end
    return labels
end

"""
    _level_bin(levels, x) -> Int

Index of the interval of `levels` containing `x` (lower bound inclusive), or `0`.
"""
function _level_bin(levels::AbstractVector{<:Real}, x::Real)
    for i in 1:(length(levels) - 1)
        lo, hi = minmax(levels[i], levels[i + 1])
        (lo <= x < hi || (x == hi && hi == Inf)) && return i
    end
    return 0
end
