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
- `src/exceptions.jl` — `ParseError(file, line, column)`, `UnsupportedNodeError`, `NotNormalizedError`, `ValidationError`, `FormatDetectionError`.
- `src/tokenizer.jl` — shared C-like tokenizer (`DNE_TOKENS`, `NET_TOKENS`, `BIF_TOKENS`, `DSC_TOKENS`) and `TokenStream`.
- `src/formats.jl` — format singletons, `format_name`, shared reader/writer helpers (`_identifier`, `_onehot`, `_drop_orphans!`, `_check_writable`).
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
  past a format's limit (Netica: 30 characters). The policy lives in `_id_sanitizer` / `_state_sanitizer` / `_identifier_limit`.
- A Netica continuous node that carries both `states` and `levels` keeps the names; the writer emits both. Only when the states
  are exactly the derived interval labels (`0 to 5`) does it write `levels` alone.
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
in the message; immutable structs; no emojis in code or docs.
