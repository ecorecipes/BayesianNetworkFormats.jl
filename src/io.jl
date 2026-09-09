# Top-level read / write / detect API.

"""
    detect_format(path) -> NetworkFormat

Identify the format of `path` from its extension (`.dne`, `.xdsl`, `.net`, `.bif`, `.dsc`,
`.uai`, `.bnir.json`) and, failing that, from its first bytes (`~->[DNET`, `<smile`, `net {`,
`network`, `belief network`, `BAYES`/`MARKOV`). Gzip-compressed files raise
[`FormatDetectionError`](@ref) asking for `gunzip`; the binary Netica `.neta` format is out of
scope.
"""
function detect_format(path::AbstractString)
    lower = lowercase(path)
    endswith(lower, ".gz") &&
        throw(FormatDetectionError(path,
                                   "$(path) is gzip-compressed; decompress it first (gunzip -k $(path))"))
    endswith(lower, ".neta") &&
        throw(FormatDetectionError(path,
                                   "$(path) is a binary Netica .neta file, which is out of scope; save it as .dne from Netica"))
    for fmt in ALL_FORMATS, ext in _extensions(fmt)
        endswith(lower, ext) && return fmt
    end
    isfile(path) || throw(FormatDetectionError(path,
                                               "cannot detect the format of $(path) from its extension and the file does not exist"))
    head = open(path) do io
        return String(read(io, 512))
    end
    startswith(head, "\x1f\x8b") &&
        throw(FormatDetectionError(path,
                                   "$(path) is gzip-compressed; decompress it first (gunzip -k $(path))"))
    fmt = _sniff(head)
    fmt === nothing && throw(FormatDetectionError(path,
                                                  "cannot detect the format of $(path) from its extension or contents"))
    return fmt
end

function _sniff(head::AbstractString)
    s = lstrip(head)
    occursin("~->[DNET", s) && return NeticaDNE()
    (startswith(s, "<?xml") || startswith(s, "<smile") || startswith(s, "<!--")) &&
        occursin("<smile", s) && return GeNIeXDSL()
    occursin(r"^belief\s+network"m, s) && return DSC()
    occursin(r"^\s*(BAYES|MARKOV)\s"m, s) && return UAI()
    occursin(r"^\s*\{\s*\"format\"\s*:\s*\"bnir\"", s) && return IRJSON()
    occursin(r"^network\b"m, s) && return BIF()
    occursin(r"^\s*(//.*\n\s*)*bnet\s+\w+\s*\{", s) && return NeticaDNE()
    occursin(r"^\s*(%.*\n\s*)*net\s*\{", s) && return HuginNET()
    return nothing
end

"""
    read_network(path; format=nothing, strict=true, atol=1e-6, renormalize=false) -> NetworkIR
    read_network(io::IO, format; kwargs...)

Read a network file into a [`NetworkIR`](@ref). The format is detected with
[`detect_format`](@ref) unless a [`NetworkFormat`](@ref) singleton is passed. In strict mode
node types the IR cannot hold raise [`UnsupportedNodeError`](@ref); with `strict=false` they
are skipped (together with their descendants) and listed in `ir.extras[:skipped]`.
The result is validated (missing tables allowed); rows that do not sum to one within `atol`
raise [`NotNormalizedError`](@ref) unless `renormalize=true`. `names` is forwarded to
the UAI reader as the path of a names sidecar and is an error for any other format.

```julia
ir = read_network(fixture_path("bif/asia.bif"))
marginal(ir, :dysp)   # [0.436, 0.564]
```
"""
function read_network(path::AbstractString; format::Union{Nothing,NetworkFormat}=nothing,
                      strict::Bool=true, atol::Real=1e-6, renormalize::Bool=false,
                      names=nothing)
    fmt = format === nothing ? detect_format(path) : format
    isfile(path) || throw(SystemError("opening file $(repr(path))", 2))
    return open(path) do io
        return read_network(io, fmt; file=path, strict, atol, renormalize, names)
    end
end

function read_network(io::IO, fmt::NetworkFormat; file::AbstractString="<string>",
                      strict::Bool=true,
                      atol::Real=1e-6, renormalize::Bool=false, names=nothing)
    if names !== nothing
        fmt isa UAI ||
            throw(ArgumentError("the names keyword is only supported by the UAI format, not by $(format_name(fmt))"))
        return read_uai(io; file, strict, atol, renormalize, names)
    end
    return _read(fmt, io; file, strict, atol, renormalize)
end

_read(::NeticaDNE, io; kw...) = read_dne(io; kw...)
_read(::GeNIeXDSL, io; kw...) = read_xdsl(io; kw...)
_read(::HuginNET, io; kw...) = read_net(io; kw...)
_read(::BIF, io; kw...) = read_bif(io; kw...)
_read(::DSC, io; kw...) = read_dsc(io; kw...)
_read(::UAI, io; kw...) = read_uai(io; kw...)
function _read(::IRJSON, io; file, strict, atol, renormalize)
    return validate(read_ir_json(io; file); atol, renormalize, allow_missing_tables=true)
end

"""
    write_network(path, ir; format=nothing)
    write_network(io::IO, ir, format)

Write `ir` in the given format (detected from the extension of `path` when `format` is
`nothing`). The writer validates the IR first and raises [`UnsupportedNodeError`](@ref) for
node kinds the format cannot hold (decisions and utilities in BIF/DSC/UAI, MAU nodes with
non-unit weights in Netica/HUGIN). Writing `.uai` also writes the `<path>.names` sidecar.
"""
function write_network(path::AbstractString, ir::NetworkIR;
                       format::Union{Nothing,NetworkFormat}=nothing)
    fmt = format === nothing ? detect_format(path) : format
    open(path, "w") do io
        return write_network(io, ir, fmt)
    end
    fmt isa UAI && open(io -> write_uai_names(io, ir), path * ".names", "w")
    return path
end

function write_network(io::IO, ir::NetworkIR, fmt::NeticaDNE; nested::Bool=true)
    return write_dne(io, ir; nested)
end
write_network(io::IO, ir::NetworkIR, ::GeNIeXDSL) = write_xdsl(io, ir)
write_network(io::IO, ir::NetworkIR, ::HuginNET) = write_net(io, ir)
write_network(io::IO, ir::NetworkIR, ::BIF) = write_bif(io, ir)
write_network(io::IO, ir::NetworkIR, ::DSC) = write_dsc(io, ir)
write_network(io::IO, ir::NetworkIR, ::UAI) = write_uai(io, ir)
write_network(io::IO, ir::NetworkIR, ::IRJSON) = write_ir_json(io, ir)

"""
    fixture_path(name) -> String

Absolute path of a fixture committed under `test/fixtures/`, for example
`fixture_path("dne/habitat_reference.dne")`, so downstream packages can reuse them. Throws
`SystemError` when the fixture does not exist.

The fixtures include the SPEC section 45 reference ecological network and the section 46
grazing influence diagram in every format, the umbrella problem
[Raiffa1968, Shachter1986](@cite), and bnlearn's *asia*
[LauritzenSpiegelhalter1988, Scutari2010](@cite).
"""
function fixture_path(name::AbstractString)
    p = normpath(joinpath(@__DIR__, "..", "test", "fixtures", name))
    isfile(p) || throw(SystemError("fixture $(repr(name)) not found at $(p)", 2))
    return p
end
