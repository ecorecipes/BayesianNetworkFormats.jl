# File formats

Every reader produces a [`NetworkIR`](@ref) and every writer consumes one. This page
summarises, for each format, the grammar the package understands, how the numbers in the
file are laid out, and what is and is not supported. Each section names the specification or
vendor documentation it follows; the full list is on the [References](references.md) page.

## The IR axis convention

For a chance node `Y` with parents `X1, ..., Xk` (in the order they appear in the file) the
IR table has `size == (n(X1), ..., n(Xk), n(Y))` and every row `table[x1, ..., xk, :]` sums to
one. A utility node's table has `size == (n(X1), ..., n(Xk))`. Decision nodes have no table;
their parents are information arcs.

Netica, GeNIe, HUGIN and UAI all flatten a table *row-major over `(parents..., child)` with
the child fastest*, so a single conversion serves all four:

```julia
from_rowmajor(vals, dims) = permutedims(reshape(vals, reverse(dims)...), ndims:-1:1)
```

BIF `table` lines and DSC / BIF rows use different orders; see below.

## Support matrix

| Feature | `.dne` | `.xdsl` | `.net` | `.bif` | `.dsc` | `.uai` | `.bnir.json` |
|---|---|---|---|---|---|---|---|
| Read / write | yes / yes | yes / yes | yes / yes | yes / yes | yes / yes | yes / yes | yes / yes |
| Chance nodes | yes | yes | yes | yes | yes | yes | yes |
| Decision nodes | yes | yes | yes (experimental) | no | no | no | yes |
| Utility nodes | yes | yes | yes (experimental) | no | no | no | yes |
| Multi-attribute utility | implicit sum | `<mau>` | implicit sum | no | no | no | yes |
| Deterministic flag | `DETERMIN` + `functable` | `<deterministic>` | no | no | no | no | yes |
| Titles | `title` | `<name>` | `label` | no | `name :` (read only) | no | yes |
| Positions | `visual { center }` | `<position>` | `position` | `property position` | read only | no | yes |
| Comments | `comment` | `<comment>` | `HR_Desc` | no | no | no | yes |
| Network name | `bnet NAME` | `id` / genie `name` | `name` attribute | `network NAME` | `belief network` | `.names` sidecar | yes |
| Continuous / interval nodes | `levels` (read + write) | `<equation>` rejected or skipped | `continuous node` rejected or skipped | no | no | no | via `extras` |
| Unsupported nodes | `CONSTANT` always skipped; other kinds strict / skip | `noisymax`, `noisyadder`, `equation`, ...: strict / skip | `continuous`, `function`, `class`: strict / skip | - | - | `MARKOV` files rejected | - |

"Strict / skip" means: with `strict=true` (default) [`read_network`](@ref) raises
[`UnsupportedNodeError`](@ref); with `strict=false` the node and every node that depends on it
is dropped and listed in `ir.extras[:skipped]`. Writers raise `UnsupportedNodeError` for
decision and utility nodes in BIF, DSC and UAI, and for MAU nodes with non-unit weights in
Netica and HUGIN. Writers that need bare identifiers (Netica, GeNIe, HUGIN, DSC, and the UAI
names sidecar) also check the names *after* sanitisation: two IR names that collapse to one
identifier raise [`IdentifierCollisionError`](@ref), and an identifier longer than the format
allows (30 characters in Netica) raises [`IdentifierLengthError`](@ref).

Titles default to the variable id, so a file without titles reads as `title == string(id)`,
and the Netica and HUGIN writers omit titles that equal the id.

## Netica `.dne`

Grammar and semantics follow the Netica file-format documentation [NeticaFileFormats](@cite).

```
// ~->[DNET-1]->~
bnet Name {
    comment = "...";
    visual V1 { ... };
    node X {
        kind = NATURE | DECISION | UTILITY | CONSTANT;
        discrete = TRUE | FALSE;
        chance = CHANCE | DETERMIN;
        states = (a, b, c);            // or: levels = (-INFINITY, 10, 20, INFINITY);
        inputs = (, P2);               // input link names, one per parent; empty = unnamed
        parents = (P1, P2);
        probs = ((0.1, 0.9), (0.4, 0.6));   // or a flat list (old Netica); @imposs = 0
        functable = (a, b, c, a);      // DETERMIN nodes: one state per parent configuration
        evidence = b;                  // or #1: a finding entered on the node
        title = "..."; comment = "...";
        visual V1 { center = (x, y); };
    };
};
```

- Tokens: C-style identifiers, decimal and hexadecimal numbers, `"strings"` with `\"`,
  `\n`, `\t` and backslash-newline continuation (the indentation of the continued line is
  dropped), `//` and `/* */` comments, `@imposs`, and the state-index literal `#k`
  (the k-th state of the node, 0-based).
- `#k` names a state wherever a state is expected: in a `functable` it is the state, in
  `probs` it stands for the one-hot row with probability 1 on state k (Netica writes
  `(#0)` for a node it has fixed on one state), and `evidence = #k` is the finding
  entered on the node, recorded in the variable's `extras[:evidence]` as the state name
  (`evidence = name` and a numeric finding are recorded the same way). Evidence is
  written back; it does not change the tables.
- `probs` and `functable` are row-major over `(parents..., child)` with the child fastest,
  as the row comments Netica writes show (`// Present Present Absent` etc.). Nesting is
  ignored when reading; the writer nests one level per parent (`nested=false` writes the
  flat form).
- `chance = DETERMIN` with a `functable` of state names gives a one-hot table and
  `deterministic = true`; a utility node's values live in its `functable`.
- `discrete = FALSE` with `levels` produces interval-labelled states (`< 10`, `10 to 20`,
  `>= 20`); the levels are kept in `extras[:levels]` and written back as `levels`, and a
  DETERMIN node with interval states writes its `functable` as `#k` indices. When the file
  gives `states` as well as `levels` (Netica writes both when the intervals have names of
  their own) the names win, and the writer emits both, so the names survive a round trip.
- `discrete = TRUE` with `levels` (Netica's numeric value of each state) has one state per
  level, named by `statetitles` when present (`Year 1`, `Year 5`) and by the value
  otherwise (`2020`, `2030`); the values are kept in `extras[:state_values]` and written
  back as `levels` after `states`. A node with `statetitles` but neither `states`,
  `levels` nor `numstates` takes the titles as its state names. Titles are not
  identifiers, so a round trip through the writer sanitises them (`Year_1`).
- An **empty entry** in a parenthesised list (nothing between two commas) is Netica's way of
  writing "no value at this position". It keeps its place, because dropping it would shift
  every entry after it and so silently permute parent order or state order. Two forms occur
  in real files: `inputs = (, G);`, where the input link at that position has no name of its
  own, and `statetitles = (, , , "greatly decreased");`, where those states have no display
  title. `inputs` names the input links one per parent and in parent order; it is kept in
  `extras[:inputs]` with an unnamed link as `""` and written back in the same form (a stored
  list whose length does not match `parents` is not written). An empty `statetitles` entry
  falls back to the state's own id — the `states` entry at that position, or the generated
  name `s0`, `s1`, ... when the node has no `states` list. `()` is still the empty list and a
  trailing comma is not an entry. An empty entry in `states` (a state with no name) or in
  `parents` (an unconnected slot) has nothing to fall back on, so it raises
  `UnsupportedNodeError(id, "state with no name", :dne)` or
  `UnsupportedNodeError(id, "parent slot with no node", :dne)` in strict mode and skips the
  node otherwise.
- Nodes with a finding but no table (`evidence` without `probs`, or an `equation` that
  Netica has not expanded) read with `table === nothing`; `validate(ir;
  allow_missing_tables=true)` accepts them.
- `CONSTANT` nodes (Netica's title labels) are skipped and recorded in `extras[:skipped]`.
  A `CONSTANT` used as a parent (Netica allows it for equation nodes) raises
  `UnsupportedNodeError(id, "CONSTANT", :dne)` in strict mode; in non-strict mode the child
  is dropped with the reason `parent K is a CONSTANT node`.
- Netica identifiers only: ids and states that are not identifiers are sanitised (`>= 30`
  becomes `ge_30`), and Netica's 30-character limit applies. Because sanitisation can map
  two distinct IR names onto one identifier, the writer checks the sanitised names and
  raises [`IdentifierCollisionError`](@ref) (or [`IdentifierLengthError`](@ref)) rather than
  writing a file that cannot be read back.
- The binary `.neta` format is out of scope; save as `.dne` from Netica.

## GeNIe `.xdsl`

The XDSL schema is documented by BayesFusion with the GeNIe Modeler and the SMILE engine
[GeNIeDocs](@cite).

```xml
<smile version="1.0" id="Name" numsamples="10000">
  <nodes>
    <cpt id="X"><state id="a"/><state id="b"/><parents>P1 P2</parents>
      <probabilities>0.1 0.9 0.4 0.6 ...</probabilities></cpt>
    <deterministic id="D">...<resultingstates>a b a</resultingstates></deterministic>
    <decision id="Dec"><state id="yes"/><state id="no"/><parents>X</parents></decision>
    <utility id="U"><parents>X Dec</parents><utilities>10 0 5 5</utilities></utility>
    <mau id="Total"><parents>U1 U2</parents><weights>1 1</weights></mau>
  </nodes>
  <extensions><genie version="1.0" app="..." name="...">
    <node id="X"><name>Title</name><position>x1 y1 x2 y2</position><comment>...</comment></node>
  </genie></extensions>
</smile>
```

- Parsed with EzXML. `<probabilities>`, `<resultingstates>` and `<utilities>` are row-major
  over `(parents..., child)` with the child (or the last parent) fastest, verified on the
  GeNIe-written `test/fixtures/xdsl/Habitat_Suitability.xdsl` (record 132 of the Bayesian
  Network Model Archive [BNMA](@cite)) and on the zoo's GeNIe models: under any other reading
  their rows do not sum to one.
- `<property id="k">` elements are kept in `extras[:properties]`.
- The `<genie>` extension block is searched recursively (`.//node`), so nodes grouped in
  `<submodel>` elements keep their names, comments and positions.
- Positions are the centre of the `x1 y1 x2 y2` rectangle; the writer emits an 80 x 40 box.
- `<equation>`, `<noisymax>`, `<noisyadder>` and any other node type are rejected in strict
  mode and skipped otherwise.

## HUGIN `.net`

The NET language is specified in the HUGIN API reference manual [HuginNET](@cite).

```
net { node_size = (80 40); }
node X { states = ("a" "b"); label = "Title"; position = (100 200); HR_Desc = "comment"; }
decision D { states = ("yes" "no"); }
utility U { }
potential (X | P1 P2) { data = (((0.1 0.9)(0.4 0.6))((0.2 0.8)(0.3 0.7))); }
potential (D | X) { }
potential (U | X D) { data = ((10 0)(5 5)); }
```

- `%` starts a comment. Lists have no commas; states may be quoted strings, identifiers or
  numbers.
- `data` is row-major over `(parents..., child)` with the child fastest and one parenthesis
  level per parent (verified on bnlearn's `asia.net` [Scutari2010](@cite)); nesting is
  ignored when reading.
- Decision and utility blocks follow the HUGIN NET grammar and round-trip through this
  package and GeNIe-style readers, but have not been checked in the HUGIN application, so
  influence-diagram support for `.net` is marked experimental.
- `continuous node`, `function node`, `class` and `instance` blocks are unsupported
  (strict / skip). A potential over several nodes is a `ParseError`.

## BIF (`.bif`)

The Interchange Format for Bayesian Networks [Cozman1998](@cite), in the dialect written by
bnlearn [Scutari2010](@cite) and pgmpy.

```
network Name { property ...; }
variable X {
  type discrete [ 2 ] { yes, no };
  property position = (100, 50) ;
}
probability ( X | P1, P2 ) {
  (yes, yes) 0.9, 0.1;     // one row per parent configuration, any order
  default 0.5, 0.5;
}
probability ( Y ) { table 0.2, 0.8; }
```

- Names may be quoted strings. `//` and `/* */` comments are allowed.
- Row form: rows are labelled with parent states in parent order and indexed by name, so
  their order does not matter. bnlearn writes the first parent fastest.
- `table` form (pgmpy, the original BIF specification): numbers in header order
  `(child, parent1, ..., parentk)` with the last variable fastest, i.e. the child slowest.
  The reader converts with `from_rowmajor(vals, (n(child), n(p1), ..., n(pk)))` followed by a
  `permutedims` that moves the child axis last.
- `property` lines are kept verbatim in `extras[:properties]`, except
  `position = (x, y)`, which becomes the variable position.
- The writer emits the bnlearn row form (and `table` for root nodes).

## DSC (`.dsc`)

The Microsoft Bayesian Networks (MSBNx) `.dsc` grammar [Kadie2001](@cite), in the subset
bnlearn [Scutari2010](@cite) writes.

```
belief network "Name"
node X { type : discrete [ 2 ] = { "yes", "no" }; }
probability ( X | P1, P2 ) {
  (0, 1) : 0.9, 0.1;       // 0-based parent state indices in parent order, any order
}
probability ( Y ) { 0.2, 0.8; }
```

- Rows carry 0-based indices in parent order; bnlearn writes the first parent fastest. The
  reader indexes by the given indices, so row order does not matter.
- `name : "..."` and `position : (x, y)` are read when present; other node attributes are
  ignored. The writer emits only the bnlearn subset.

## UAI (`.uai`)

The UAI inference-competition model format [UAIFormat](@cite).

```
BAYES
3
2 2 3
3
1 0
2 0 1
3 0 1 2

2
0.4 0.6
...
```

- Only `BAYES` networks; `MARKOV` files raise [`UnsupportedNodeError`](@ref).
- The last variable of each scope is the child; scopes are `(parents..., child)`. Tables are
  row-major with the last scope variable fastest (the "least significant digit" of the UAI
  description [UAIFormat](@cite)). This is checked against
  `test/fixtures/uai/ChestClinic.uai`, written outside this package (the Merlin library):
  read that way it reproduces the published *asia* marginal `P(dysp = yes) = 0.436`
  [LauritzenSpiegelhalter1988](@cite), and no other reading normalises.
- Names: a sidecar `<file>.names` with an optional `network NAME` line and one
  `id state1 state2 ...` line per variable. The writer always produces it; without it the
  reader synthesises `X0, X1, ...` and `s0, s1, ...`.
- Evidence files (`<model>.uai.evid`) are read and written by [`read_uai_evidence`](@ref)
  and [`write_uai_evidence`](@ref).

## `.bnir.json`

The package's own serialisation, used for golden files: fixed key order, tables stored as
`{"dims": [...], "values": [...]}` in Julia column-major order, and JSON3's
`Infinity` / `-Infinity` for non-finite numbers (Netica levels). See
[`write_ir_json`](@ref) and [`read_ir_json`](@ref).

## Compressed files

The bnlearn repository [Scutari2010](@cite) serves gzip-compressed files. Decompress them first
(`gunzip -k asia.bif.gz`); [`detect_format`](@ref) raises [`FormatDetectionError`](@ref) for
`.gz` files rather than adding a compression dependency.
