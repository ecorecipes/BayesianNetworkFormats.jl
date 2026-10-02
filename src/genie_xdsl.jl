# GeNIe / SMILE .xdsl reader and writer (EzXML).
#
# <smile version="1.0" id="Name" numsamples="10000">
#   <nodes>
#     <cpt id="X"><state id="a"/><state id="b"/><parents>P1 P2</parents>
#          <probabilities>...</probabilities></cpt>
#     <deterministic id="D"><state .../><parents>..</parents><resultingstates>a b ...</resultingstates></deterministic>
#     <decision id="Dec"><state .../><parents>..</parents></decision>
#     <utility id="U"><parents>..</parents><utilities>..</utilities></utility>
#     <mau id="M"><parents>U1 U2</parents><weights>1 1</weights></mau>
#   </nodes>
#   <extensions><genie version="1.0" app=".." name="..">
#     <node id="X"><name>Title</name><position>x1 y1 x2 y2</position><comment>..</comment></node>
#   </genie></extensions>
# </smile>
#
# <probabilities>, <resultingstates> and <utilities> are row-major over (parents..., child)
# with the child (or the last parent, for utilities) fastest.

struct _XdslRaw
    tag::String
    id::String
    states::Vector{String}
    parents::Vector{Symbol}
    numbers::Vector{Float64}
    words::Vector{String}
    properties::Dict{String,String}
end

function _xdsl_text(el, name::AbstractString)
    child = EzXML.findfirst(name, el)
    return child === nothing ? "" : String(EzXML.nodecontent(child))
end

_xdsl_words(el, name) = String.(split(_xdsl_text(el, name)))

function _xdsl_numbers(el, name, id, file)
    out = Float64[]
    for w in _xdsl_words(el, name)
        x = tryparse(Float64, w)
        x === nothing &&
            throw(ParseError("non-numeric entry $(repr(w)) in <$(name)> of node $(id)";
                             file))
        push!(out, x)
    end
    return out
end

"""
    read_xdsl(io::IO; file="<string>", strict=true, atol=1e-6, renormalize=false,
              max_states=65_536, max_table_cells=2^27) -> NetworkIR

Parse a GeNIe `.xdsl` file. See [`GeNIeXDSL`](@ref).

`<probabilities>`, `<resultingstates>` and `<utilities>` are read row-major over
`(parents..., child)` with the child (or, for a utility, the last parent) fastest, as
documented for the GeNIe / SMILE XDSL format [GeNIeDocs](@cite).

A node with more than `max_states` states, or a table with more than `max_table_cells`
cells, raises [`ParseError`](@ref) before its table is allocated.
"""
function read_xdsl(io::IO; file::AbstractString="<string>", strict::Bool=true,
                   atol::Real=1e-6,
                   renormalize::Bool=false, max_states::Integer=DEFAULT_MAX_STATES,
                   max_table_cells::Integer=DEFAULT_MAX_TABLE_CELLS)
    _check_limits(max_states, max_table_cells)
    doc = try
        EzXML.parsexml(read(io, String))
    catch e
        e isa EzXML.XMLError || rethrow()
        throw(ParseError("invalid XML: " * e.message; file))
    end
    root = doc.root
    EzXML.nodename(root) == "smile" ||
        throw(ParseError("expected a <smile> root element, got <$(EzXML.nodename(root))>";
                         file))
    netid = haskey(root, "id") ? root["id"] : ""
    nodes_el = EzXML.findfirst("nodes", root)
    nodes_el === nothing && throw(ParseError("no <nodes> element"; file))
    skipped = Dict{String,Any}[]
    raws = _XdslRaw[]
    maus = MAUNode[]
    for el in EzXML.eachelement(nodes_el)
        tag = EzXML.nodename(el)
        id = haskey(el, "id") ? el["id"] : ""
        isempty(id) && throw(ParseError("<$(tag)> element without id"; file))
        props = Dict{String,String}()
        for p in EzXML.findall("property", el)
            props[haskey(p, "id") ? p["id"] : ""] = String(EzXML.nodecontent(p))
        end
        states = String[]
        for s in EzXML.findall("state", el)
            haskey(s, "id") ||
                throw(ParseError("a <state> of node $(id) has no id attribute"; file))
            push!(states, s["id"])
        end
        # a node that becomes a variable has at most `max_states` states; a skipped one is
        # not read
        tag in ("cpt", "deterministic", "decision") &&
            _check_states(length(states), "node $(id)", file, max_states)
        parents = Symbol.(_xdsl_words(el, "parents"))
        if tag == "cpt"
            push!(raws,
                  _XdslRaw(tag, id, states, parents,
                           _xdsl_numbers(el, "probabilities", id, file), String[], props))
        elseif tag == "deterministic"
            push!(raws,
                  _XdslRaw(tag, id, states, parents, Float64[],
                           _xdsl_words(el, "resultingstates"), props))
        elseif tag == "decision"
            push!(raws, _XdslRaw(tag, id, states, parents, Float64[], String[], props))
        elseif tag == "utility"
            push!(raws,
                  _XdslRaw(tag, id, String[], parents,
                           _xdsl_numbers(el, "utilities", id, file), String[], props))
        elseif tag == "mau"
            push!(maus, MAUNode(id, parents, _xdsl_numbers(el, "weights", id, file)))
        else
            strict && throw(UnsupportedNodeError(id, tag, :xdsl))
            _skip!(skipped, id, tag, "unsupported node type <$(tag)>")
        end
    end
    # genie extension: names, positions, comments
    titles = Dict{String,String}()
    positions = Dict{String,Tuple{Float64,Float64}}()
    comments = Dict{String,String}()
    name = netid
    genie = EzXML.findfirst("extensions/genie", root)
    if genie !== nothing
        haskey(genie, "name") && (name = genie["name"])
        # `.//node` so that nodes inside <submodel> groups keep their names, comments
        # and positions (GeNIe writes one <submodel> per group under <genie>).
        for n in EzXML.findall(".//node", genie)
            haskey(n, "id") || continue
            nid = n["id"]
            t = _xdsl_text(n, "name")
            isempty(t) || (titles[nid] = t)
            c = _xdsl_text(n, "comment")
            isempty(c) || (comments[nid] = c)
            pos = _xdsl_words(n, "position")
            if length(pos) == 4
                xs = tryparse.(Float64, pos)
                any(isnothing, xs) ||
                    (positions[nid] = ((xs[1] + xs[3]) / 2, (xs[2] + xs[4]) / 2))
            end
        end
    end
    states_of = Dict{Symbol,Vector{String}}(Symbol(r.id) => r.states for r in raws)
    vars = IRVariable[]
    for r in raws
        id = Symbol(r.id)
        ok = true
        for p in r.parents
            haskey(states_of, p) && continue
            strict &&
                throw(ParseError("parent $(p) of node $(r.id) is not a node of the network";
                                 file))
            _skip!(skipped, r.id, r.tag, "parent $(p) was skipped")
            ok = false
            break
        end
        ok || continue
        pdims = Tuple(length(states_of[p]) for p in r.parents)
        title = get(titles, r.id, "")
        comment = get(comments, r.id, "")
        position = get(positions, r.id, nothing)
        extras = Dict{Symbol,Any}()
        isempty(r.properties) || (extras[:properties] = r.properties)
        if r.tag == "cpt"
            dims = (pdims..., length(r.states))
            n = _table_length(dims, "the <probabilities> of $(r.id)", file;
                              max_table_cells)
            length(r.numbers) == n ||
                throw(ParseError("<probabilities> of $(r.id) has $(length(r.numbers)) entries; expected $(n) for parents $(r.parents) and $(length(r.states)) states";
                                 file))
            push!(vars,
                  IRVariable(id; title, kind=ChanceNode, states=r.states, parents=r.parents,
                             table=from_rowmajor(r.numbers, dims), position, comment,
                             extras))
        elseif r.tag == "deterministic"
            table = _onehot(r.words, r.states, pdims, r.id, file; max_table_cells)
            push!(vars,
                  IRVariable(id; title, kind=ChanceNode, states=r.states, parents=r.parents,
                             table, deterministic=true, position, comment, extras))
        elseif r.tag == "decision"
            push!(vars,
                  IRVariable(id; title, kind=DecisionNode, states=r.states,
                             parents=r.parents,
                             position, comment, extras))
        else
            n = _table_length(pdims, "the <utilities> of $(r.id)", file; max_table_cells)
            length(r.numbers) == n ||
                throw(ParseError("<utilities> of $(r.id) has $(length(r.numbers)) entries; expected $(n) for parents $(r.parents)";
                                 file))
            push!(vars,
                  IRVariable(id; title, kind=UtilityNode, parents=r.parents,
                             table=from_rowmajor(r.numbers, pdims), position, comment,
                             extras))
        end
    end
    _drop_orphans!(vars, skipped)
    ids = Set(v.id for v in vars)
    maus = filter(m -> all(p -> p in ids, m.parents), maus)
    return _finish_read(name, vars, GeNIeXDSL(), file; mau=maus, skipped, atol, renormalize)
end

# --- writer ----------------------------------------------------------------------------

"""
    write_xdsl(io::IO, ir::NetworkIR)

Write `ir` as a GeNIe `.xdsl` file [GeNIeDocs](@cite), including a `genie` extension block
with names, positions and comments.
"""
function write_xdsl(io::IO, ir::NetworkIR)
    _check_writable(ir, GeNIeXDSL())
    index = _index(ir)
    doc = EzXML.XMLDocument()
    root = EzXML.ElementNode("smile")
    EzXML.setroot!(doc, root)
    root["version"] = "1.0"
    root["id"] = _identifier(ir.name; default="network")
    root["numsamples"] = "10000"
    nodes = EzXML.addelement!(root, "nodes")
    for v in ir.variables
        onehot = v.kind == ChanceNode && v.deterministic && v.table !== nothing &&
                 _is_onehot(v.table)
        tag = v.kind == DecisionNode ? "decision" :
              v.kind == UtilityNode ? "utility" :
              onehot ? "deterministic" : "cpt"
        el = EzXML.addelement!(nodes, tag)
        el["id"] = _identifier(v.id)
        for s in v.states
            st = EzXML.addelement!(el, "state")
            st["id"] = _identifier(s)
        end
        isempty(v.parents) ||
            EzXML.addelement!(el, "parents", join(_identifier.(v.parents), " "))
        if v.kind == ChanceNode
            table = _require_table(v, GeNIeXDSL())
            if onehot
                EzXML.addelement!(el, "resultingstates",
                                  join(_onehot_entries(table, _identifier.(v.states)), " "))
            else
                EzXML.addelement!(el, "probabilities", join(_fmt.(to_rowmajor(table)), " "))
            end
        elseif v.kind == UtilityNode
            EzXML.addelement!(el, "utilities",
                              join(_fmt.(to_rowmajor(_require_table(v, GeNIeXDSL()))), " "))
        end
        props = get(v.extras, :properties, nothing)
        if props isa AbstractDict
            for k in sort!(collect(keys(props)))
                p = EzXML.addelement!(el, "property", string(props[k]))
                p["id"] = string(k)
            end
        end
    end
    for m in ir.mau
        el = EzXML.addelement!(nodes, "mau")
        el["id"] = _identifier(m.id)
        EzXML.addelement!(el, "parents", join(_identifier.(m.parents), " "))
        EzXML.addelement!(el, "weights", join(_fmt.(m.weights), " "))
    end
    ext = EzXML.addelement!(root, "extensions")
    genie = EzXML.addelement!(ext, "genie")
    genie["version"] = "1.0"
    genie["app"] = "BayesianNetworkFormats.jl"
    genie["name"] = ir.name
    for v in ir.variables
        n = EzXML.addelement!(genie, "node")
        n["id"] = _identifier(v.id)
        EzXML.addelement!(n, "name", v.title)
        if v.position !== nothing
            x, y = v.position
            EzXML.addelement!(n, "position",
                              join(_fmt_coord.((x - 40, y - 20, x + 40, y + 20)), " "))
        end
        isempty(v.comment) || EzXML.addelement!(n, "comment", v.comment)
    end
    for m in ir.mau
        n = EzXML.addelement!(genie, "node")
        n["id"] = _identifier(m.id)
        EzXML.addelement!(n, "name", String(m.id))
    end
    EzXML.prettyprint(io, doc)
    return nothing
end
