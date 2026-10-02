# UAI competition format reader and writer (BAYES networks only).
#
#   BAYES
#   n
#   card_1 ... card_n
#   n
#   k p1 ... p(k-1) child      one scope per line; the child is the LAST variable
#   ...
#   T v v v ...                one table per scope, row-major with the last scope variable fastest
#
# Names come from a sidecar `<file>.names` (one `id state1 state2 ...` line per variable,
# optional `network NAME` first line, `#` comments); otherwise they are synthesised.

"""
    read_uai_names(path) -> (name, ids, states)

Read a `.names` sidecar. Returns the network name (`""` if absent), the variable ids and the
state names per variable (`nothing` for variables without listed states).

Blank lines and lines that start with `#` are skipped. The first other line names the
network when its first word is `network`; every later line names a variable, so a variable
may itself be called `network`. A leading UTF-8 byte-order mark is ignored, as by every
reader.
"""
function read_uai_names(path::AbstractString)
    name = ""
    ids = Symbol[]
    states = Vector{Union{Nothing,Vector{String}}}()
    first = true
    for line in eachsplit(strip_bom(read(path, String)), '\n')
        s = strip(line)
        (isempty(s) || startswith(s, "#")) && continue
        words = split(s)
        if first && words[1] == "network"
            name = join(words[2:end], " ")
            first = false
            continue
        end
        first = false
        push!(ids, Symbol(words[1]))
        push!(states, length(words) > 1 ? String.(words[2:end]) : nothing)
    end
    return name, ids, states
end

function _uai_next!(words, pos, file, what)
    pos[] > length(words) &&
        throw(ParseError("unexpected end of file while reading $(what)"; file))
    w = words[pos[]]
    pos[] += 1
    return w
end

function _uai_int!(words, pos, file, what)
    w = _uai_next!(words, pos, file, what)
    x = tryparse(Int, w)
    x === nothing &&
        throw(ParseError("expected an integer for $(what), got $(repr(w))"; file))
    return x
end

# A count, cardinality or size: a negative one is malformed input (ADR 0015).
function _uai_count!(words, pos, file, what)
    x = _uai_int!(words, pos, file, what)
    x >= 0 || throw(ParseError("$(what) must be nonnegative, got $(x)"; file))
    return x
end

function _uai_float!(words, pos, file, what)
    w = _uai_next!(words, pos, file, what)
    x = tryparse(Float64, w)
    x === nothing &&
        throw(ParseError("expected a number for $(what), got $(repr(w))"; file))
    return x
end

"""
    read_uai(io::IO; file="<string>", strict=true, atol=1e-6, renormalize=false,
             names=nothing, max_states=65_536, max_table_cells=2^27) -> NetworkIR

Parse a UAI `BAYES` file. `names` is the path of a sidecar names file; by default
`<file>.names` is used when it exists. `MARKOV` files raise [`UnsupportedNodeError`](@ref).

Following the UAI model-format description [UAIFormat](@cite), the **last** variable of each
function scope is the child and the table that follows is listed with that last scope
variable varying fastest, so a scope is `(parents..., child)` in IR order.

Malformed content raises [`ParseError`](@ref) (ADR 0015). A count is never an allocation
size: every list grows one item per word read, so a count larger than the file ends in
"unexpected end of file", and table sizes are multiplied with an overflow check. A
cardinality larger than `max_states`, or a table with more than `max_table_cells` cells,
raises `ParseError` before anything is allocated for it, so a variable whose states the
names file does not list gets at most `max_states` generated names `s0`, `s1`, ....
"""
function read_uai(io::IO; file::AbstractString="<string>", strict::Bool=true,
                  atol::Real=1e-6,
                  renormalize::Bool=false, names=nothing,
                  max_states::Integer=DEFAULT_MAX_STATES,
                  max_table_cells::Integer=DEFAULT_MAX_TABLE_CELLS)
    _check_limits(max_states, max_table_cells)
    words = split(strip_bom(read(io, String)))
    isempty(words) && throw(ParseError("empty UAI file"; file))
    pos = Ref(1)
    kind = _uai_next!(words, pos, file, "network type")
    if kind != "BAYES"
        kind == "MARKOV" && throw(UnsupportedNodeError("network", "MARKOV", :uai,
                                                       "$(file) is a MARKOV network; only BAYES networks can be read into the IR"))
        throw(ParseError("expected BAYES or MARKOV, got $(repr(kind))"; file))
    end
    # Each list grows by one item per word read, never from the count that precedes it, so a
    # count of 10^15 reaches the end of the file, not an allocation of 10^15 items.
    nvar = _uai_count!(words, pos, file, "number of variables")
    cards = Int[]
    for i in 1:nvar
        card = _uai_count!(words, pos, file, "cardinality of variable $(i - 1)")
        push!(cards, _check_states(card, "variable $(i - 1)", file, max_states))
    end
    nfun = _uai_count!(words, pos, file, "number of functions")
    scopes = Vector{Int}[]
    for f in 1:nfun
        k = _uai_int!(words, pos, file, "size of scope $(f - 1)")
        # the last variable of a scope is the function's child, so a scope is never empty
        k >= 1 ||
            throw(ParseError("size of scope $(f - 1) must be at least 1, got $(k)"; file))
        scope = Int[]
        for _ in 1:k
            v = _uai_int!(words, pos, file, "scope $(f - 1)")
            0 <= v < nvar ||
                throw(ParseError("scope $(f - 1) references variable $(v); only $(nvar) variables are declared";
                                 file))
            push!(scope, v)
        end
        push!(scopes, scope)
    end
    tables = Vector{Float64}[]
    for f in 1:nfun
        n = _uai_int!(words, pos, file, "size of table $(f - 1)")
        expected = _table_length((cards[s + 1] for s in scopes[f]),
                                 "table $(f - 1) (of variable $(scopes[f][end]))", file;
                                 max_table_cells)
        n == expected ||
            throw(ParseError("table $(f - 1) declares $(n) entries; scope $(scopes[f]) needs $(expected)";
                             file))
        vals = Float64[]
        for _ in 1:n
            push!(vals, _uai_float!(words, pos, file, "table $(f - 1)"))
        end
        push!(tables, vals)
    end
    pos[] <= length(words) &&
        throw(ParseError("trailing data after the last table: $(repr(words[pos[]]))"; file))
    name = ""
    ids = [Symbol("X$(i - 1)") for i in 1:nvar]
    listed = Vector{Union{Nothing,Vector{String}}}(nothing, nvar)
    sidecar = names === nothing ? (file * ".names") : String(names)
    if isfile(sidecar)
        name, sid, sstates = read_uai_names(sidecar)
        length(sid) == nvar ||
            throw(ParseError("names file $(sidecar) lists $(length(sid)) variables; the UAI file has $(nvar)";
                             file=sidecar))
        for i in 1:nvar
            ids[i] = sid[i]
            if sstates[i] !== nothing
                length(sstates[i]) == cards[i] ||
                    throw(ParseError("variable $(sid[i]) lists $(length(sstates[i])) states; the UAI file says $(cards[i])";
                                     file=sidecar))
                listed[i] = sstates[i]
            end
        end
    end
    # A variable whose states are not listed gets generated names, at most `max_states`.
    states = Vector{String}[listed[i] === nothing ?
                            _unnamed_states(cards[i], "variable $(ids[i])", file,
                                            max_states) :
                            listed[i] for i in 1:nvar]
    parents_of = Dict{Int,Vector{Int}}()
    table_of = Dict{Int,Array{Float64}}()
    for f in 1:nfun
        child = scopes[f][end]
        haskey(parents_of, child) &&
            throw(ParseError("variable $(ids[child + 1]) is the child of two functions";
                             file))
        ps = scopes[f][1:(end - 1)]
        parents_of[child] = ps
        table_of[child] = from_rowmajor(tables[f], Tuple(cards[s + 1] for s in scopes[f]))
    end
    vars = IRVariable[]
    for i in 1:nvar
        ps = get(parents_of, i - 1, Int[])
        push!(vars,
              IRVariable(ids[i]; states=states[i], parents=[ids[p + 1] for p in ps],
                         table=get(table_of, i - 1, nothing)))
    end
    return _finish_read(name, vars, UAI(), file; atol, renormalize)
end

# --- writer ----------------------------------------------------------------------------

"""
    write_uai(io::IO, ir::NetworkIR)

Write the `BAYES` model file. Use [`write_uai_names`](@ref) for the sidecar (done
automatically by [`write_network`](@ref)). Chance nodes only; variables are numbered in
source order. The names are checked as the sidecar will hold them, so a name that it cannot
hold raises here too, before anything is written.
"""
function write_uai(io::IO, ir::NetworkIR)
    _check_writable(ir, UAI())
    idx = Dict(v.id => i - 1 for (i, v) in enumerate(ir.variables))
    println(io, "BAYES")
    println(io, length(ir.variables))
    println(io, join((nstates(v) for v in ir.variables), " "))
    println(io, length(ir.variables))
    for v in ir.variables
        scope = [idx[p] for p in v.parents]
        push!(scope, idx[v.id])
        println(io, length(scope), " ", join(scope, " "))
    end
    for v in ir.variables
        table = _require_table(v, UAI())
        println(io)
        println(io, length(table))
        vals = to_rowmajor(table)
        n = nstates(v)
        for r in 1:(length(vals) ÷ n)
            println(io, " ", join(_fmt.(vals[((r - 1) * n + 1):(r * n)]), " "))
        end
    end
    return nothing
end

"""
    write_uai_names(io::IO, ir::NetworkIR)

Write the `.names` sidecar: a `network NAME` line, then one line per variable with its id
followed by its state names. The network line is written when `ir` has a name, and also
when the first variable is called `network`, so that [`read_uai_names`](@ref) reads that
variable's line as a variable and not as the name of the network.

The sidecar is whitespace-delimited, so a name containing whitespace cannot be written as
it stands and has its whitespace replaced by `_` (in the network name, each run of
whitespace becomes one space). That is a lossy rename -- `"Rainfall (mm)"` is written
`Rainfall_(mm)` and reads back that way -- so it is reported with a warning rather than
done silently. Before writing anything, the names are checked as [`write_uai`](@ref)
checks them: two names that collide after renaming raise
[`IdentifierCollisionError`](@ref), and a name that the sidecar cannot hold raises
[`ValidationError`](@ref). Those are an empty id or state name, which would vanish from its
line, and an id that starts with `#`, whose line would be read as a comment.
"""
function write_uai_names(io::IO, ir::NetworkIR)
    _check_identifiers(ir, UAI())
    netname = join(split(ir.name), " ")
    renamed = String[]
    netname == ir.name || push!(renamed, string(ir.name, " -> ", netname))
    println(io,
            "# variable and state names for the UAI file; written by BayesianNetworkFormats.jl")
    first_is_network = !isempty(ir.variables) && _uai_word(ir.variables[1].id) == "network"
    if !isempty(netname) || first_is_network
        println(io, isempty(netname) ? "network" : "network " * netname)
    end
    for v in ir.variables
        for name in vcat(string(v.id), v.states)
            word = _uai_word(name)
            word == name || push!(renamed, string(name, " -> ", word))
        end
        println(io, _uai_word(v.id), " ", join(_uai_word.(v.states), " "))
    end
    isempty(renamed) ||
        @warn "the .names sidecar is whitespace-delimited, so these names were rewritten and will not round-trip" renamed
    return nothing
end

_uai_word(s) = replace(String(string(s)), r"\s+" => "_")

# --- evidence --------------------------------------------------------------------------

"""
    read_uai_evidence(path; ir=nothing) -> Vector{Dict}

Read a UAI evidence file (`<model>.uai.evid`): the number of samples followed by one line per
sample, `k var val var val ...` with 0-based variable indices and state indices. Returns one
`Dict` per sample. Without `ir` the keys are 0-based variable indices and the values 0-based
state indices; with `ir` they are variable ids and state names. Files that omit the sample
count (older single-sample files) are accepted.
"""
function read_uai_evidence(path::AbstractString; ir::Union{Nothing,NetworkIR}=nothing)
    words = split(strip_bom(read(path, String)))
    ints = Int[]
    for w in words
        x = tryparse(Int, w)
        x === nothing &&
            throw(ParseError("expected an integer in the evidence file, got $(repr(w))";
                             file=path))
        push!(ints, x)
    end
    samples = Vector{Vector{Pair{Int,Int}}}()
    pos = 1
    function read_sample!()
        pos > length(ints) &&
            throw(ParseError("unexpected end of evidence file"; file=path))
        k = ints[pos]
        pos += 1
        k >= 0 ||
            throw(ParseError("evidence sample declares $(k) pairs; the count must be nonnegative";
                             file=path))
        # compare `k` with the pairs that remain: `pos + 2k` overflows for a count near
        # typemax(Int), and the wrapped value would pass the check (ADR 0015)
        k <= (length(ints) - pos + 1) ÷ 2 ||
            throw(ParseError("evidence sample declares $(k) pairs but the file ends early";
                             file=path))
        s = [ints[pos + 2j] => ints[pos + 2j + 1] for j in 0:(k - 1)]
        pos += 2k
        return s
    end
    if isempty(ints)
        return Dict[]
    end
    # try "nsamples" form first, fall back to the single-sample form
    nsamples = ints[1]
    consistent = false
    if nsamples >= 0
        pos = 2
        try
            for _ in 1:nsamples
                push!(samples, read_sample!())
            end
            consistent = pos == length(ints) + 1
        catch e
            e isa ParseError || rethrow()
        end
    end
    if !consistent
        empty!(samples)
        pos = 1
        push!(samples, read_sample!())
        pos == length(ints) + 1 ||
            throw(ParseError("evidence file does not parse as either the multi- or the single-sample form";
                             file=path))
    end
    ir === nothing && return [Dict{Int,Int}(s) for s in samples]
    for s in samples, (v, k) in s
        0 <= v < length(ir.variables) ||
            throw(ParseError("evidence names variable index $(v); the network has $(length(ir.variables)) variables";
                             file=path))
        n = length(ir.variables[v + 1].states)
        0 <= k < n ||
            throw(ParseError("evidence names state index $(k) of $(ir.variables[v + 1].id), which has $(n) states";
                             file=path))
    end
    return [Dict{Symbol,String}(ir.variables[v + 1].id => ir.variables[v + 1].states[k + 1]
                                for (v, k) in s)
            for s in samples]
end

"""
    write_uai_evidence(path, samples; ir=nothing)

Write a UAI evidence file. Each sample is a `Dict` (or vector of pairs) mapping 0-based
variable indices to 0-based state indices, or, when `ir` is given, variable ids to state names;
an id or a state that `ir` does not have raises [`ValidationError`](@ref). Every sample is
checked before the file is touched, and the file is then replaced in one step (a temporary
file in the same directory, renamed over `path`), so a failure leaves an existing file as it
was.
"""
function write_uai_evidence(path::AbstractString, samples;
                            ir::Union{Nothing,NetworkIR}=nothing)
    bytes = _serialise() do io
        println(io, length(samples))
        for s in samples
            pairs = Pair{Int,Int}[]
            for (k, v) in s
                if ir === nothing
                    push!(pairs, Int(k) => Int(v))
                else
                    i = findfirst(x -> x.id == Symbol(k), ir.variables)
                    i === nothing && throw(ValidationError(Symbol(k),
                                                           "$(repr(Symbol(k))) is not a variable of the network"))
                    j = findfirst(==(string(v)), ir.variables[i].states)
                    j === nothing && throw(ValidationError(Symbol(k),
                                                           "$(repr(v)) is not a state of $(k)"))
                    push!(pairs, (i - 1) => (j - 1))
                end
            end
            sort!(pairs; by=first)
            println(io, length(pairs), " ", join(("$(a) $(b)" for (a, b) in pairs), " "))
        end
    end
    _write_atomic(path, bytes)
    return path
end
