# BayesianNetworkFormats.jl

Readers and writers for Bayesian-network and influence-diagram interchange formats
(Netica `.dne`, GeNIe `.xdsl`, HUGIN `.net`, BIF, DSC, UAI) via a common intermediate
representation, [`NetworkIR`](@ref).

```julia
using BayesianNetworkFormats

ir = read_network(fixture_path("bif/asia.bif"))   # format detected from the extension
variable(ir, :dysp).table                          # size (2, 2, 2): (bronc, either, dysp)
marginal(ir, :dysp)                                # [0.436, 0.564] by brute force
write_network("asia.xdsl", ir)                     # GeNIe
write_network("asia.dne", ir)                      # Netica
```

## What the IR holds

- Variables in file order, each with an id, a kind (chance, decision, utility), ordered
  states, ordered parents, a table, a deterministic flag, a title, a position, a comment and
  format-specific `extras`.
- Chance tables have `size == (n(parent1), ..., n(parentk), n(child))`, normalised over the
  last axis; utility tables `size == (n(parent1), ..., n(parentk))`; decisions have none.
- Multi-attribute utility nodes (GeNIe `<mau>`) and network-level `extras`.

The [File formats](formats.md) page documents each grammar, its table layout and the support
matrix. The [API Reference](api.md) lists every exported name, the [References](references.md)
page collects the format specifications and the literature cited throughout, and the
Tutorials are rendered vignettes: reading and writing, axis conventions, and
influence-diagram files.

## Design

- `BayesianNetworkFormats.jl` is a leaf of the ecorecipes ecosystem: it depends only on
  EzXML and JSON3, never on Catlab or the other ecosystem packages (ADR 0003). The bridges
  to `BayesModel` and `InfluenceDiagramModel` live in `BayesianNetworks.jl` and
  `InfluenceDiagrams.jl`.
- Every reader validates its result ([`validate`](@ref)): unique ids, known parents, table
  sizes, normalisation (with `renormalize=true` to rescale), acyclicity.
- Node types the IR cannot represent raise [`UnsupportedNodeError`](@ref) in strict mode and
  are skipped, with their descendants, when `strict=false`.
- The brute-force [`joint_distribution`](@ref) is the oracle that pins the axis convention
  in the test suite.
- Fixtures under `test/fixtures/` (reachable through [`fixture_path`](@ref)) include the
  SPEC section 45 reference ecological network and the section 46 influence diagram in every
  format, the umbrella problem [Raiffa1968, Shachter1986](@cite), and bnlearn's *asia*
  [LauritzenSpiegelhalter1988, Scutari2010](@cite).

## References

The specifications and vendor documentation this package implements:

- Netica `.dne`: Norsys Software Corp., *Netica file formats*,
  <https://www.norsys.com/WebHelp/NETICA/X_File_Formats.htm> [NeticaFileFormats](@cite).
- GeNIe / SMILE `.xdsl`: BayesFusion, LLC, *GeNIe Modeler and SMILE Engine documentation*,
  <https://support.bayesfusion.com/docs/> [GeNIeDocs](@cite).
- HUGIN `.net`: HUGIN EXPERT A/S, *HUGIN API Reference Manual: The NET Language*,
  <https://download.hugin.com/webdocs/manuals/api-manual.pdf> [HuginNET](@cite).
- BIF: F. G. Cozman, *The Interchange Format for Bayesian Networks, version 0.15*, 1998,
  <http://www.cs.cmu.edu/~fgcozman/Research/InterchangeFormat/> [Cozman1998](@cite).
- DSC: C. M. Kadie, D. Hovel and E. Horvitz, *MSBNx*, MSR-TR-2001-67, 2001
  [Kadie2001](@cite).
- UAI: UAI Inference Competition, *Model file format*,
  <https://uaicompetition.github.io/uci-2022/file-formats/model-format/> [UAIFormat](@cite).

The full bibliography, including the sources of the fixtures, is on the
[References](references.md) page.
