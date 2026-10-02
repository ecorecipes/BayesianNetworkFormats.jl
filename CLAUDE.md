# BayesianNetworkFormats.jl

Readers and writers for Bayesian-network and influence-diagram interchange formats (Netica .dne, GeNIe .xdsl, HUGIN .net, BIF, DSC, UAI) via a common intermediate representation.

## Place in the ecosystem

Dependency order (arrows = depends on):
EcologicalBayesianNetworks → InfluenceDiagrams → BayesianNetworkInference → BayesianNetworks → FiniteKernels,
and BayesianNetworks → BayesianNetworkFormats (a Catlab-free leaf).
This package depends on: nothing else in the ecosystem (ADR 0003). External deps: EzXML, JSON3.
The bridges `BayesModel(::NetworkIR)` / `InfluenceDiagramModel(::NetworkIR)` live downstream, not here.

## File layout

- `src/ir.jl` — `NodeKind`, `IRVariable`, `MAUNode`, `NetworkIR`, `from_rowmajor`/`to_rowmajor`, `validate`,
  accessors, `topological_order`, `joint_distribution`/`marginal` (brute-force oracle), `isequivalent`/`differences`.
- `src/errors.jl` — the root `BayesianNetworkFormatsError` and every exception under it (`ParseError(file, line, column)`,
  `UnsupportedNodeError`, `NotNormalizedError`, `ValidationError`, `FormatDetectionError`, `IdentifierCollisionError`,
  `IdentifierLengthError`) with their `showerror` methods (ADR 0013); included first. `test/test_errors.jl` checks that
  every exception type the package defines subtypes the root and prints as `BayesianNetworkFormats.ParseError` etc.
  from a module that only imports the package, as the conformance inspect adapter serialises it.
- `src/tokenizer.jl` — shared C-like tokenizer (`DNE_TOKENS`, `NET_TOKENS`, `BIF_TOKENS`, `DSC_TOKENS`) and `TokenStream`.
- `src/formats.jl` — format singletons, `format_name`, the size-limit defaults and checks (`DEFAULT_MAX_STATES`,
  `DEFAULT_MAX_TABLE_CELLS`, `_check_limits`, `_check_states`, `_table_length`, `_unnamed_states`), and shared
  reader/writer helpers (`_identifier`, `_onehot`, `_drop_orphans!`, `_check_writable`, `_serialise`, `_write_atomic`).
- `src/netica_dne.jl`, `src/genie_xdsl.jl`, `src/hugin_net.jl`, `src/bif.jl`, `src/dsc.jl`, `src/uai.jl` — one reader + writer each.
- `src/ir_json.jl` — `*.bnir.json` golden serialisation; `src/io.jl` — `read_network`, `write_network`, `detect_format`, `fixture_path`.
- `test/reference_models.jl` — SPEC §45 / §46 / umbrella / sprinkler IRs; `scripts/regenerate_fixtures.jl` regenerates
  the writer-produced fixtures and every golden file (hand-written fixtures are never overwritten).
- `test/fixtures/{dne,xdsl,net,bif,dsc,uai,golden}/` + `LICENSES.md`; bnlearn `asia` files are verbatim CC BY-SA.
  Externally written fixtures (the only witnesses for a table layout that this package did not produce): `uai/ChestClinic.uai`
  (Merlin, BSD 3-Clause) and `xdsl/Habitat_Suitability.xdsl` (GeNIe, BNMA record 132,
  CC BY with version unstated on the record). Never regenerate those.

## Invariants that must not be broken

- Axis conventions: user-facing CPTs are `(parents..., child)` normalised over the last axis; FinStoch kernels internally are outputs-first. Convert with the documented `permutedims`, never by hand.
- Netica `probs`/`functable`, HUGIN `data`, GeNIe `<probabilities>`/`<utilities>` and UAI tables are row-major over
  `(parents..., child)` with the child fastest: `from_rowmajor(vals, dims) = permutedims(reshape(vals, reverse(dims)...), N:-1:1)`.
  BIF `table` is header order `(child, parents...)` with the last variable fastest (child slowest). BIF/DSC rows are
  indexed by the parent states/indices they carry, never by position. Netica nesting is ignored; `@imposs` is 0.
- Netica `#k` (0-based state index; token kind `:stateindex`, value `DneStateIndex`) is the k-th state in a `functable`,
  a one-hot row in `probs`, and the finding in `evidence = #k`, which is recorded (as the state name) in the variable's
  `extras[:evidence]` and written back. A `discrete = TRUE` node's `levels` are one value per state and live in
  `extras[:state_values]` (named by `statetitles` if present); only `discrete = FALSE` levels are interval boundaries
  in `extras[:levels]`. `statetitles` alone also name the states. The BNMA files in
  `../EcologicalBayesianNetworks.jl/models/{song_sparrow_bdn,brown_trout_bdn}` are read by `test/test_dne.jl` when present.
- An empty entry in a Netica parenthesised list (`inputs = (, G);`, `statetitles = (, , "x");`) is parsed as
  `DneEmpty()` and keeps its position; it is never dropped, because dropping it would shift the entries after it.
  `inputs` names the input links one per parent, in parent order, and lives in `extras[:inputs]` with an unnamed
  link as `""` (written back in the same form). An empty `statetitles` entry falls back to the state's own id, or
  to the generated name `s0`, `s1`, ... when the node has no `states` list. An empty entry in `states` (a state
  with no name) or in `parents` (an unconnected slot) cannot be represented and raises `UnsupportedNodeError`
  in strict mode. `()` is still the empty list; a trailing comma is not an entry.
- Parent order is the order in the source file and is total; it is never re-sorted.
- Strict / non-strict rule: `read_network(path; strict=true)` raises `UnsupportedNodeError` for any node type the IR cannot hold
  (GeNIe `<equation>`/`<noisymax>`, Netica continuous nodes without `levels`, HUGIN `continuous node`); with `strict=false` the node
  and, transitively, its descendants are skipped and recorded in `ir.extras[:skipped]`. Netica `CONSTANT` nodes are always
  skipped, but a `CONSTANT` used as a *parent* raises `UnsupportedNodeError(id, "CONSTANT", :dne)` in strict mode and drops the
  child with the reason "parent K is a CONSTANT node" otherwise (never "not a node of the network", which is false).
  Writers raise `UnsupportedNodeError` for decisions/utilities in BIF/DSC/UAI and for MAU nodes with non-unit weights in Netica/HUGIN.
- Writers validate the *sanitised* names, not only the IR names: `_check_writable` calls `_check_identifiers`, which raises
  `IdentifierCollisionError` when two ids (or two states of one variable) collapse to one identifier and `IdentifierLengthError`
  past a format's limit (Netica: 30 characters). The policy lives in `_id_sanitizer` / `_state_sanitizer` / `_identifier_limit`
  / `_unwritable`. `_unwritable(::UAI, ...)` makes an empty id or state, and an id starting with `#` (a comment line in the
  `.names` sidecar), a `ValidationError`; `write_uai_names` runs the same check before writing. Only the first non-comment
  line of a sidecar can be its `network` line, and the writer emits one whenever the first variable is called `network`.
- A Netica continuous node that carries both `states` and `levels` keeps the names; the writer emits both. Only when the states
  are exactly the derived interval labels (`0 to 5`) does it write `levels` alone.
- Malformed content raises this package's typed errors, never a Base exception (ADR 0015): convert a number token
  to a count or index with `expect_int!` / `token_int` (tokenizer.jl), a `#k` token with `state_index` (its `Float64`
  value is inexact past 2^53), a UAI count with `_uai_count!`, check list shapes and lengths before indexing, multiply
  table dimensions with `_table_length` (never `prod`, which wraps), and read `*.bnir.json` fields through the
  `_json_get` / `_json_strings` / `_json_numbers` shape checks (`ParseError` naming the field). A declared count is
  never an allocation size: grow lists one item per token read. Parse JSON from `codeunits`, never from a `String`,
  which JSON3 reads as a file path when it names one; `_json_parse` turns only JSON3's `ArgumentError` into
  `ParseError`, so an interrupt or any other exception propagates. `test/test_malformed.jl` holds one case per site.
- Nesting: a recursive-descent parser must not see brackets nested deeper than `_MAX_NESTING` (512; tokenizer.jl).
  `read_dne` and `read_net` call `check_nesting(ts)` on the token stream before parsing, and `_json_depth_ok` does the
  same for JSON (JSON3 overflows near 7 500 levels, the Netica and HUGIN parsers near 100 000). BIF and DSC are
  iterative, and libxml2 stops GeNIe at 256 elements. Real files nest at most 7 levels (zoo `water.net`).
- Size limits: `read_network` and every reader (`read_ir_json` too) take `max_states` (default `DEFAULT_MAX_STATES`
  = 65 536, the states of one variable, named or generated) and `max_table_cells` (default `DEFAULT_MAX_TABLE_CELLS`
  = 2^27, the cells of one table), validated by `_check_limits` (`ArgumentError` unless positive). Check a state
  count with `_check_states` and every table size with `_table_length(...; max_table_cells)` *before* allocating;
  generate unnamed states only through `_unnamed_states`. Exceeding either is a `ParseError` naming the variable,
  the size, the limit and the keyword. BIF/DSC check before `fill`, since a `default` row makes any size well-formed;
  Netica counts `probs` values with `_dne_value_count` before expanding `#k` rows. The largest fixture has 4 states
  and 54 cells; the largest zoo model (`mildew`) 100 states and 280 000 cells.
- Every reader, and `detect_format`'s content sniffing, strips a leading UTF-8 BOM with `strip_bom`.
- Path writers (`write_network`, `write_ir_json`, `write_uai_evidence`) serialise with `_serialise` first and
  replace each file with `_write_atomic` (a temporary file in the same directory, then `Base.rename`), so a
  failure never truncates or half-writes an existing file. Never `open(path, "w")` in a writer.
- Every reader validates its result (missing tables allowed); non-normalised rows raise `NotNormalizedError` unless `renormalize=true`.
- Titles default to the id. `deterministic` is an annotation only BIF/DSC/UAI/HUGIN cannot record.
- Every optimised path is checked against a slower oracle: `joint_distribution` pins the convention with `P(dysp = yes) = 0.4360` on `asia`.
- Do not add Catlab, CodecZlib or any ecosystem package as a dependency.

## Commands

```sh
julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'   # the test suite
julia --project scripts/regenerate_fixtures.jl                    # after changing a writer or a reference model; diff before committing
julia --project=docs docs/make.jl                                 # build docs locally
cd vignettes && quarto render                                     # render vignettes to html/gfm/pdf (julia engine; PDF needs lualatex + ../fonts/JuliaMono)
julia scripts/sync_vignettes.jl [--check]                         # copy vignettes into docs/src/tutorials
```

## Files not to edit by hand

- `docs/src/tutorials/` is generated by `scripts/sync_vignettes.jl`.
- `vignettes/*/*.md`, `*.html`, `*.pdf` and `*_files/` are quarto output; edit the `.qmd`.
- `test/fixtures/golden/*.bnir.json` and the writer-produced fixtures (`habitat_reference.*`, `grazing_reference_id.*`,
  `umbrella.*`, `uai/asia.uai*`) are produced by `scripts/regenerate_fixtures.jl`.

## Style

JuliaFormatter `yas`; docstrings on every exported name, which `test/test_docstrings.jl` enforces; the docs
build is strict (no `warnonly`; `checkdocs=:exports`, because the API page leaves private docstrings out), so
an exported docstring left out of the manual or a broken `@ref` fails it; typed exceptions with variable names
in the message, following ADR 0013: they live in `src/errors.jl` and subtype the nearest root
(`FiniteKernelsError`, `BayesianNetworkFormatsError` or `BayesNetError`), invalid arguments and keywords raise
`ArgumentError`, typed errors from a lower package pass through unchanged and documented, content read from a file, document or manifest is checked before it is converted and raises the package's typed error (ADR 0015: never catch the `MethodError` or `InexactError` of an unchecked conversion), and another
package's type is named as a code span, never with `@ref`; immutable structs; no emojis in code or docs.
