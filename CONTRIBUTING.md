# Contributing to BayesianNetworkFormats.jl

## Local setup

The ecosystem packages depend on each other through `[sources]` entries that point at
sibling directories (`../OtherPackage.jl`). Clone every package you need side by side:

```sh
mkdir -p bbn && cd bbn
git clone https://github.com/ecorecipes/BayesianNetworkFormats.jl
cd BayesianNetworkFormats.jl
julia --project -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

`Pkg.test()` is the only run that counts as "the suite passes".

## Style

- Julia ≥ 1.12. Every dependency, including stdlibs and test-only extras, has a `[compat]` entry.
- Format with JuliaFormatter using the repository `.JuliaFormatter.toml` (`style = "yas"`).
- `snake_case` for functions and variables, `CamelCase` for types, a leading underscore for internal helpers.
- Public functions have docstrings with a signature line, a one-sentence summary, and an example where practical.
- Errors are typed exceptions carrying the offending variable / mechanism names, never bare `error("...")` in library code.
- Every optimised code path is tested against a slower reference implementation on small models.

## Adding a vignette

1. Create `vignettes/NN_short_name/NN_short_name.qmd` with front matter including `engine: julia` and
   `pdf: default` under `format:` (copy an existing vignette's front matter).
2. Add any new dependencies to `vignettes/Project.toml`.
3. `cd vignettes && quarto render` renders HTML, GitHub-flavoured Markdown and PDF (the PDF needs
   `lualatex` and the JuliaMono font in `../fonts/JuliaMono/`; see `vignettes/README.md`). Commit the
   `.qmd`, the rendered `.md`, `.html` and `.pdf`, and `NN_short_name_files/`.
4. `julia scripts/sync_vignettes.jl` and commit `docs/src/tutorials/`.

The `Vignettes` workflow re-renders everything weekly and on demand; it is not a required check because
rendering is slow and depends on a Quarto installation. The `vignette-sync` job in CI is required.

## Adding a format

1. Add the singleton to `src/formats.jl` (`struct MyFormat <: NetworkFormat`, a docstring
   saying what it reads and writes, `format_name`, `_extensions`), and the traits that apply:
   `_supports_decisions`, `_supports_mau`, `_allows_missing_tables`, and the identifier
   policy `_id_sanitizer` / `_state_sanitizer` / `_identifier_limit` when the format needs
   bare identifiers rather than quoted names.
2. Add `src/my_format.jl` with `read_myformat(io; file, strict, atol, renormalize)` and
   `write_myformat(io, ir)`. Readers finish with `_finish_read` (which validates); writers
   start with `_check_writable` (which validates and checks the sanitised identifiers).
   Reuse the shared tokenizer (`src/tokenizer.jl`) rather than writing a new lexer.
3. Wire it into `src/BayesianNetworkFormats.jl` (include and export), `src/io.jl` (`_read`,
   `write_network`, `ALL_FORMATS`, and a sniff pattern in `_sniff` when the extension is
   ambiguous) and `test/utils.jl` (`ALL_WRITABLE`).
4. Document the grammar and the table layout in `docs/src/formats.md`, including the support
   matrix row, and say explicitly which axis is fastest.
5. Add `test/test_myformat.jl` to `test/runtests.jl`: a golden-IR test, a round trip, the
   cross-format comparison in `test/test_crossformat.jl`, and the failure modes
   (malformed input, unsupported nodes strict vs non-strict, non-normalised rows).

## Adding a fixture

1. Put the file under `test/fixtures/<format>/`. Prefer a file written by the tool whose
   format it is: those are the only external witnesses for a table layout. Hand-written
   grammar fixtures are fine for corners no real file exercises; say so in a comment at the
   top of the file.
2. Record the origin (URL, retrieval date, sha256) and the licence in
   `test/fixtures/LICENSES.md`, and reproduce any notice the licence requires. Do not commit
   a file whose licence forbids redistribution; read it from the model zoo instead.
3. `julia --project scripts/regenerate_fixtures.jl` writes the golden
   `test/fixtures/golden/<format>_<stem>.bnir.json`. Diff the result: only the new golden
   file should change. Never overwrite a hand-written or externally produced fixture from a
   writer.
4. Add a read test that pins something the file itself asserts (a published marginal, a
   table row quoted from the file) rather than only comparing against the golden IR, and add
   the file to `FIXTURE_FILES` in `test/test_roundtrip.jl` when it round trips.

## Architecture decision records

Significant design decisions are recorded in `docs/adr/NNNN-title.md` (context, decision, consequences).
Add a new record rather than editing an old one when a decision changes.

## Pull requests

Branch from `main`, keep PRs focused, and make sure CI is green (tests on Julia 1.12 and latest,
vignette sync check, docs build).
