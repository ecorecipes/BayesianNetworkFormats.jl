# Exceptions of BayesianNetworkFormats (ADR 0013). Every exception the package defines lives
# in this file, with its `showerror` method, and subtypes the root
# `BayesianNetworkFormatsError`. The module includes this file first: the types have only
# Base field types, and the readers, writers and `validate` throw them.
#
# - Carry the offending file, node or variable in the fields and the message. Library code
#   never calls a bare `error("...")`.
# - Invalid arguments and keywords raise `ArgumentError`, not a type from this file (for
#   example a negative `atol`, or `names` passed to a reader other than UAI's). A missing
#   file raises Base's `SystemError`, and looking up a variable id that the IR does not
#   have (`variable`, `marginal`) raises `KeyError`. `write_uai_evidence` checks sample
#   content, so an unknown id or state there is a `ValidationError` (ADR 0015).
# - The package has no ecosystem dependencies (ADR 0003), so there is no lower root to
#   subtype. A docstring names another package's type as a code span, never with `@ref`.

"""
    BayesianNetworkFormatsError

Abstract supertype of every exception that BayesianNetworkFormats defines:
[`ParseError`](@ref), [`UnsupportedNodeError`](@ref), [`NotNormalizedError`](@ref),
[`ValidationError`](@ref), [`FormatDetectionError`](@ref),
[`IdentifierCollisionError`](@ref) and [`IdentifierLengthError`](@ref). It marks the
package that introduced an error, not a kind of failure, and catches any error that a
reader, a writer or [`validate`](@ref) raises for the content of a file or an IR.
Invalid arguments and keywords raise Base's `ArgumentError` instead, a missing file
raises `SystemError`, and looking up a variable id that the IR does not have raises
`KeyError`; all three are outside this root.

```jldoctest
julia> try
           read_network(IOBuffer("network {"), BIF())
       catch e
           e isa BayesianNetworkFormatsError
       end
true
```
"""
abstract type BayesianNetworkFormatsError <: Exception end

"""
    ParseError(message, file, line, column)

Raised when a network file cannot be tokenised or parsed. `file` is the path that was read
(`"<string>"` for in-memory input) and `line`/`column` locate the offending token
(1-based; `0` when the location is unknown).
"""
struct ParseError <: BayesianNetworkFormatsError
    message::String
    file::String
    line::Int
    column::Int
end

function ParseError(message::AbstractString; file::AbstractString="<string>",
                    line::Integer=0,
                    column::Integer=0)
    return ParseError(String(message), String(file), Int(line), Int(column))
end

function Base.showerror(io::IO, e::ParseError)
    print(io, "ParseError: ", e.file)
    e.line > 0 && print(io, ":", e.line, ":", e.column)
    return print(io, ": ", e.message)
end

"""
    UnsupportedNodeError(id, nodetype, format, message)

Raised when a file contains a node (or a whole-network feature) that the reader or writer
for `format` cannot represent in the IR, for example a GeNIe `<equation>` node or a HUGIN
`continuous node`. `id` is the node id in the file and `nodetype` the offending construct.
Readers raise this only in strict mode; in non-strict mode the node is skipped and recorded
in `ir.extras[:skipped]`.
"""
struct UnsupportedNodeError <: BayesianNetworkFormatsError
    id::String
    nodetype::String
    format::Symbol
    message::String
end

function UnsupportedNodeError(id, nodetype, format::Symbol)
    return UnsupportedNodeError(String(id), String(nodetype), format,
                                "node $(id) of type $(nodetype) is not supported by the $(format) format")
end

function Base.showerror(io::IO, e::UnsupportedNodeError)
    return print(io, "UnsupportedNodeError: ", e.message)
end

"""
    NotNormalizedError(id, index, total)

Raised by [`validate`](@ref) (and therefore by [`read_network`](@ref)) when the conditional
distribution of chance node `id` for parent configuration `index` (a tuple of 1-based state
indices, one per parent, in parent order) sums to `total` instead of one.
Pass `renormalize=true` to rescale rows instead.
"""
struct NotNormalizedError <: BayesianNetworkFormatsError
    id::Symbol
    index::Tuple
    total::Float64
end

function Base.showerror(io::IO, e::NotNormalizedError)
    return print(io, "NotNormalizedError: row ", e.index, " of the table of ", e.id,
                 " sums to ", e.total, ", not 1")
end

"""
    ValidationError(id, message)

Raised by [`validate`](@ref) for structural problems: duplicate ids, unknown parents, wrong
table sizes, cycles, decision nodes with tables, utility nodes used as parents. `id` is the
variable concerned, or `:network` for network-level problems.
"""
struct ValidationError <: BayesianNetworkFormatsError
    id::Symbol
    message::String
end

Base.showerror(io::IO, e::ValidationError) = print(io, "ValidationError: ", e.message)

"""
    FormatDetectionError(path, message)

Raised by [`detect_format`](@ref) when neither the file extension nor the first bytes of
`path` identify a supported format (or when the file is gzip-compressed).
"""
struct FormatDetectionError <: BayesianNetworkFormatsError
    path::String
    message::String
end

function Base.showerror(io::IO, e::FormatDetectionError)
    return print(io, "FormatDetectionError: ", e.message)
end

"""
    IdentifierCollisionError(id, kind, originals, sanitized, format)

Raised by a writer when two names that are distinct in the IR become the same identifier
after sanitisation (see `_identifier`), which would produce a file that cannot be read back.
`kind` is `:variable`, `:state` or `:mau`, `id` names the variable whose states collide (or
`:network` for variable and MAU ids), `originals` is the pair of original names and
`sanitized` the identifier they share. Rename one of the two names before writing.
"""
struct IdentifierCollisionError <: BayesianNetworkFormatsError
    id::Symbol
    kind::Symbol
    originals::Tuple{String,String}
    sanitized::String
    format::Symbol
end

function IdentifierCollisionError(id, kind::Symbol, originals, sanitized, format::Symbol)
    return IdentifierCollisionError(Symbol(id), kind,
                                    (String(string(originals[1])),
                                     String(string(originals[2]))), String(sanitized),
                                    format)
end

function Base.showerror(io::IO, e::IdentifierCollisionError)
    where_ = e.kind == :state ? "states of $(e.id)" : "$(e.kind) ids"
    return print(io, "IdentifierCollisionError: the ", where_, " ",
                 repr(e.originals[1]), " and ", repr(e.originals[2]),
                 " both become $(repr(e.sanitized)) in the $(e.format) format; rename one of them")
end

"""
    IdentifierLengthError(id, kind, name, limit, format)

Raised by a writer when a sanitised identifier is longer than the format allows (Netica
limits node and state names to 30 characters). `kind` is `:variable`, `:state` or `:mau`,
`id` names the variable whose state is too long (or `:network` for variable and MAU ids) and
`name` is the offending identifier.
"""
struct IdentifierLengthError <: BayesianNetworkFormatsError
    id::Symbol
    kind::Symbol
    name::String
    limit::Int
    format::Symbol
end

function IdentifierLengthError(id, kind::Symbol, name, limit::Integer, format::Symbol)
    return IdentifierLengthError(Symbol(id), kind, String(string(name)), Int(limit), format)
end

function Base.showerror(io::IO, e::IdentifierLengthError)
    where_ = e.kind == :state ? "state of $(e.id)" : "$(e.kind) id"
    return print(io, "IdentifierLengthError: the ", where_, " ", repr(e.name), " is ",
                 length(e.name), " characters long; the $(e.format) format allows at most ",
                 e.limit)
end
