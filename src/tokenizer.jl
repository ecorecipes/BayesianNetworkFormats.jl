# A small C-like tokenizer shared by the Netica, HUGIN, BIF and DSC readers.

"""
    Token(kind, text, value, line, column, start, stop)

A lexical token. `kind` is `:ident`, `:number`, `:string`, `:stateindex`, `:punct` or
`:eof`; `text` is the identifier / punctuation / unescaped string content; `value` is the
`Float64` value of a number token or the 0-based index of a `#k` state-index token
(`nothing` otherwise); `start`/`stop` are byte offsets into the source.
"""
struct Token
    kind::Symbol
    text::String
    value::Union{Nothing,Float64}
    line::Int
    column::Int
    start::Int
    stop::Int
end

"""
    TokenizerOptions(; line_comments, block_comments, ident_chars, punct, string_continuation,
                     state_index)

Per-format lexical settings: which strings start a line comment (`//`, `%`), whether
`/* */` comments are recognised, extra characters allowed inside identifiers, the set of
single-character punctuation tokens, whether a backslash-newline inside a string is a
continuation (Netica), and whether `#k` (a 0-based state index, Netica) is a token.
"""
struct TokenizerOptions
    line_comments::Vector{String}
    block_comments::Bool
    ident_chars::String
    punct::String
    string_continuation::Bool
    state_index::Bool
end

function TokenizerOptions(; line_comments=["//"], block_comments::Bool=true,
                          ident_chars::AbstractString="", punct::AbstractString="(){}=;,|",
                          string_continuation::Bool=false, state_index::Bool=false)
    return TokenizerOptions(String[line_comments...], block_comments, String(ident_chars),
                            String(punct), string_continuation, state_index)
end

const DNE_TOKENS = TokenizerOptions(; line_comments=["//"], block_comments=true,
                                    ident_chars="",
                                    punct="(){}=;,|", string_continuation=true,
                                    state_index=true)
const NET_TOKENS = TokenizerOptions(; line_comments=["%"], block_comments=false,
                                    ident_chars="",
                                    punct="(){}=;|,", string_continuation=false)
const BIF_TOKENS = TokenizerOptions(; line_comments=["//"], block_comments=true,
                                    ident_chars="-.",
                                    punct="(){}[],;|=", string_continuation=false)
const DSC_TOKENS = TokenizerOptions(; line_comments=["//"], block_comments=true,
                                    ident_chars="-.",
                                    punct="(){}[],;|=:", string_continuation=false)

const _NUMBER_RE = r"^[+-]?(?:0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)"
const _STATE_INDEX_RE = r"^#[0-9]+"

_ident_start(c::Char) = isletter(c) || c == '_' || c == '@'
function _ident_char(c::Char, extra::String)
    return isletter(c) || isdigit(c) || c == '_' || occursin(c, extra)
end

"""
    tokenize(src::AbstractString, opts::TokenizerOptions; file="<string>") -> Vector{Token}

Split `src` into tokens, dropping comments. Throws [`ParseError`](@ref) with the file, line
and column on an unterminated string or comment, or an unexpected character.
"""
function tokenize(src::AbstractString, opts::TokenizerOptions;
                  file::AbstractString="<string>")
    s = String(src)
    toks = Token[]
    i = firstindex(s)
    n = lastindex(s)
    line = 1
    linestart = i
    while i <= n
        c = s[i]
        if c == '\n'
            line += 1
            i = nextind(s, i)
            linestart = i
            continue
        elseif isspace(c)
            i = nextind(s, i)
            continue
        end
        col = i - linestart + 1
        rest = SubString(s, i)
        # comments
        skipped = false
        for lc in opts.line_comments
            if startswith(rest, lc)
                j = findnext('\n', s, i)
                i = j === nothing ? n + 1 : j
                skipped = true
                break
            end
        end
        skipped && continue
        if opts.block_comments && startswith(rest, "/*")
            j = findnext("*/", s, i)
            j === nothing &&
                throw(ParseError("unterminated block comment"; file, line, column=col))
            for k in eachindex(SubString(s, i, first(j)))
                SubString(s, i, first(j))[k] == '\n' && (line += 1)
            end
            linestart = something(findprev('\n', s, last(j)), 0) + 1
            i = nextind(s, last(j))
            continue
        end
        if c == '"'
            buf = IOBuffer()
            j = nextind(s, i)
            closed = false
            while j <= n
                d = s[j]
                if d == '"'
                    closed = true
                    break
                elseif d == '\\'
                    j = nextind(s, j)
                    j > n && break
                    e = s[j]
                    if e == 'n'
                        write(buf, '\n')
                    elseif e == 't'
                        write(buf, '\t')
                    elseif e == 'r'
                        write(buf, '\r')
                    elseif e == '\n' || e == '\r'
                        # backslash-newline continuation
                        line += 1
                        if e == '\r' && j < n && s[nextind(s, j)] == '\n'
                            j = nextind(s, j)
                        end
                        linestart = nextind(s, j)
                        if opts.string_continuation
                            while j < n &&
                                (s[nextind(s, j)] == ' ' || s[nextind(s, j)] == '\t')
                                j = nextind(s, j)
                            end
                        else
                            write(buf, '\n')
                        end
                    else
                        write(buf, e)
                    end
                elseif d == '\n'
                    line += 1
                    linestart = nextind(s, j)
                    write(buf, d)
                else
                    write(buf, d)
                end
                j = nextind(s, j)
            end
            closed ||
                throw(ParseError("unterminated string literal"; file, line, column=col))
            push!(toks, Token(:string, String(take!(buf)), nothing, line, col, i, j))
            i = nextind(s, j)
            continue
        end
        m = match(_NUMBER_RE, rest)
        if m !== nothing
            txt = m.match
            after = i + ncodeunits(txt)
            if after <= n && _ident_char(s[after], opts.ident_chars) &&
               !(txt[end] in ('.',))
                # identifier that starts with a digit (e.g. BIF state name `1st`)
                j = after
                while j <= n && _ident_char(s[j], opts.ident_chars)
                    j = nextind(s, j)
                end
                push!(toks,
                      Token(:ident, s[i:prevind(s, j)], nothing, line, col, i,
                            prevind(s, j)))
                i = j
                continue
            end
            val = if occursin(r"^[+-]?0[xX]", txt)
                hex = tryparse(Int, replace(txt, r"^[+-]?0[xX]" => ""); base=16)
                hex === nothing &&
                    throw(ParseError("hexadecimal number $(txt) does not fit a 64-bit integer";
                                     file, line, column=col))
                Float64(hex) * (startswith(txt, "-") ? -1 : 1)
            else
                parse(Float64, txt)
            end
            push!(toks, Token(:number, String(txt), val, line, col, i, after - 1))
            i = after
            continue
        end
        if opts.state_index && c == '#'
            m = match(_STATE_INDEX_RE, rest)
            m === nothing &&
                throw(ParseError("expected a state index after '#'"; file, line,
                                 column=col))
            txt = m.match
            after = i + ncodeunits(txt)
            k = tryparse(Int, txt[2:end])
            k === nothing &&
                throw(ParseError("state index $(txt) does not fit a 64-bit integer"; file,
                                 line, column=col))
            push!(toks,
                  Token(:stateindex, String(txt), Float64(k), line, col, i, after - 1))
            i = after
            continue
        end
        if _ident_start(c) || (c == '-' && i < n && isletter(s[nextind(s, i)]))
            j = nextind(s, i)
            while j <= n && _ident_char(s[j], opts.ident_chars)
                j = nextind(s, j)
            end
            push!(toks,
                  Token(:ident, s[i:prevind(s, j)], nothing, line, col, i, prevind(s, j)))
            i = j
            continue
        end
        if occursin(c, opts.punct)
            push!(toks, Token(:punct, string(c), nothing, line, col, i, i))
            i = nextind(s, i)
            continue
        end
        throw(ParseError("unexpected character $(repr(c))"; file, line, column=col))
    end
    push!(toks, Token(:eof, "", nothing, line, max(i - linestart + 1, 1), i, i))
    return toks
end

"""
    TokenStream(tokens, file, source)

Cursor over a token vector with the helpers `peek`, `next!`, `accept!` and `expect!`.
"""
mutable struct TokenStream
    tokens::Vector{Token}
    pos::Int
    file::String
    source::String
end

"""
    strip_bom(s) -> AbstractString

`s` without a leading UTF-8 byte-order mark. Netica and GeNIe run on Windows and their
files are routinely saved with one; left in place it is just an unexpected character at
1:1, which every tokenizer-based reader rejects.
"""
strip_bom(s::AbstractString) = startswith(s, '\ufeff') ? SubString(s, nextind(s, 1)) : s

function TokenStream(src::AbstractString, opts::TokenizerOptions;
                     file::AbstractString="<string>")
    stripped = strip_bom(src)
    return TokenStream(tokenize(stripped, opts; file), 1, String(file), String(stripped))
end

peek(ts::TokenStream, k::Int=0) = ts.tokens[min(ts.pos + k, length(ts.tokens))]

function next!(ts::TokenStream)
    t = peek(ts)
    ts.pos = min(ts.pos + 1, length(ts.tokens))
    return t
end

function _is(t::Token, kind::Symbol, text=nothing)
    return t.kind == kind && (text === nothing || t.text == text)
end

function accept!(ts::TokenStream, kind::Symbol, text=nothing)
    t = peek(ts)
    _is(t, kind, text) || return nothing
    return next!(ts)
end

_describe(t::Token) = t.kind == :eof ? "end of input" : "$(t.kind) $(repr(t.text))"

function parse_error(ts::TokenStream, t::Token, msg::AbstractString)
    throw(ParseError(msg; file=ts.file, line=t.line, column=t.column))
end
parse_error(ts::TokenStream, msg::AbstractString) = parse_error(ts, peek(ts), msg)

# The integer a number token spells. A count, index or size written as a fraction, or too
# large for an `Int`, is malformed input, so a `ParseError` at the token (ADR 0015), never
# the `InexactError` of `Int(x)`.
function token_int(ts::TokenStream, t::Token)
    v = t.value
    (isinteger(v) && -2.0^63 <= v < 2.0^63) ||
        parse_error(ts, t, "expected an integer, got $(_describe(t))")
    return Int(v)
end
expect_int!(ts::TokenStream) = token_int(ts, expect!(ts, :number))

function expect!(ts::TokenStream, kind::Symbol, text=nothing)
    t = peek(ts)
    _is(t, kind, text) ||
        parse_error(ts, t,
                    "expected $(text === nothing ? kind : repr(text)), got $(_describe(t))")
    return next!(ts)
end

"""
    source_text(ts, from::Token, to::Token) -> String

The raw source text spanning two tokens (used to keep BIF `property` lines verbatim).
"""
source_text(ts::TokenStream, from::Token, to::Token) = String(ts.source[(from.start):(to.stop)])
