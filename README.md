# BayesianNetworkFormats.jl

[![Build Status](https://github.com/ecorecipes/BayesianNetworkFormats.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/ecorecipes/BayesianNetworkFormats.jl/actions/workflows/CI.yml)
[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://ecorecipes.github.io/BayesianNetworkFormats.jl/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Readers and writers for Bayesian-network and influence-diagram interchange formats (Netica .dne, GeNIe .xdsl, HUGIN .net, BIF, DSC, UAI) via a common intermediate representation.

Part of the ecorecipes compositional Bayesian-network ecosystem:
`MarkovCategories.jl` → `BayesianNetworks.jl` → `BayesianNetworkInference.jl` → `InfluenceDiagrams.jl`,
with `BayesianNetworkFormats.jl` (file formats) and `EcologicalBayesianNetworks.jl` (model zoo).
This package is a leaf: it depends only on EzXML and JSON3, so it can be used on its own.

## Features

- One intermediate representation, `NetworkIR`: variables with ordered states and parents,
  node kinds chance / decision / utility, tables in a single documented axis convention,
  titles, positions, comments and format-specific extras.
- Readers and writers for six formats plus the package's own `.bnir.json`, with format
  detection by extension or by sniffing the file.
- Documented table layouts: Netica `probs` / `functable`, GeNIe `<probabilities>`, HUGIN
  `data` and UAI tables are row-major over `(parents..., child)` with the child fastest;
  BIF `table` lines put the child slowest; BIF and DSC rows are indexed by parent states.
  Each layout is checked against at least one file written by another tool: bnlearn's
  *asia* for `.bif`, `.net` and `.dsc`, Merlin's `ChestClinic.uai` for `.uai`, a
  GeNIe-written BNMA model for `.xdsl`, and the Netica-written BNMA `.dne` models in the
  model zoo (read by the suite when the sibling checkout is present).
- Influence diagrams: decision nodes with information arcs, utility nodes, GeNIe
  multi-attribute utility nodes.
- Netica specifics: flat and nested `probs`, `@imposs`, `DETERMIN` nodes with `functable`,
  continuous nodes with `levels`, `CONSTANT` label nodes skipped.
- Strict and non-strict reading: unsupported nodes (GeNIe equations, noisy-MAX, HUGIN
  continuous nodes) raise a typed error or are skipped together with their descendants.
- Validation of every IR read or written (ids, parents, table sizes, normalisation with
  optional renormalisation, acyclicity) and a brute-force `joint_distribution` /
  `marginal` oracle.
- Committed fixtures (the SPEC reference ecological network and influence diagram in every
  format, the umbrella problem, bnlearn's *asia*, and the externally written
  `uai/ChestClinic.uai` and `xdsl/Habitat_Suitability.xdsl`) reachable through
  `fixture_path`; provenance and licences in `test/fixtures/LICENSES.md`.

## Support matrix

| | `.dne` | `.xdsl` | `.net` | `.bif` | `.dsc` | `.uai` |
|---|---|---|---|---|---|---|
| Read / write | yes | yes | yes | yes | yes | yes |
| Decision and utility nodes | yes | yes | yes (experimental) | no | no | no |
| Multi-attribute utility | implicit sum | `<mau>` | implicit sum | no | no | no |
| Deterministic nodes | `functable` | `<deterministic>` | as tables | as tables | as tables | as tables |
| Titles / positions / comments | yes / yes / yes | yes / yes / yes | yes / yes / yes | no / yes / no | read only | no |
| Unsupported node types | strict / skip | strict / skip | strict / skip | - | - | `MARKOV` rejected |

## Installation

The ecosystem packages are not registered. Install this package by URL:

```julia
using Pkg
Pkg.add(url="https://github.com/ecorecipes/BayesianNetworkFormats.jl")
```

Requires Julia ≥ 1.12.

## Quick Start

```julia
using BayesianNetworkFormats

# read (format from the extension; pass format=BIF() etc. to override)
ir = read_network(fixture_path("bif/asia.bif"))

# inspect: tables are (parents..., child), normalised over the last axis
d = variable(ir, :dysp)
d.parents            # [:bronc, :either]
d.table[2, 1, :]     # P(dysp | bronc = no, either = yes) = [0.7, 0.3]

# brute-force oracle
marginal(ir, :dysp)  # [0.436, 0.564]

# write in other formats
write_network("asia.dne", ir)
write_network("asia.xdsl", ir)
write_network("asia.uai", ir)   # also writes asia.uai.names

# influence diagrams
id = read_network(fixture_path("xdsl/grazing_reference_id.xdsl"))
decisions(id), utilities(id), id.mau

# lenient reading of files with unsupported node types
lenient = read_network("model_with_equations.xdsl"; strict=false)
lenient.extras[:skipped]

# files whose rows do not sum to one
read_network("rounded.dne"; renormalize=true)
```

Gzip-compressed files from the bnlearn repository must be decompressed first
(`gunzip -k asia.bif.gz`).

## Vignettes

Rendered vignettes live in [`vignettes/`](vignettes/) and are published in the
[documentation](https://ecorecipes.github.io/BayesianNetworkFormats.jl/):
reading and writing networks, axis conventions, and influence-diagram files.

## References

The format specifications and vendor documentation this package implements:

- **Netica `.dne`** — Norsys Software Corp., *Netica file formats*.
  <https://www.norsys.com/WebHelp/NETICA/X_File_Formats.htm>
- **GeNIe / SMILE `.xdsl`** — BayesFusion, LLC, *GeNIe Modeler and SMILE Engine
  documentation*. <https://support.bayesfusion.com/docs/>
- **HUGIN `.net`** — HUGIN EXPERT A/S, *HUGIN API Reference Manual: The NET Language*.
  <https://download.hugin.com/webdocs/manuals/api-manual.pdf>
- **BIF** — Cozman, F. G. (1998), *The Interchange Format for Bayesian Networks, version
  0.15*. <http://www.cs.cmu.edu/~fgcozman/Research/InterchangeFormat/>
- **DSC** — Kadie, C. M., Hovel, D. and Horvitz, E. (2001), *MSBNx: A Component-Centric
  Toolkit for Modeling and Inference with Bayesian Networks*, Microsoft Research
  MSR-TR-2001-67.
- **UAI `.uai`** — UAI Inference Competition, *Model file format*.
  <https://uaicompetition.github.io/uci-2022/file-formats/model-format/>

Sources of the fixtures and the models they came from:

- Lauritzen, S. L. and Spiegelhalter, D. J. (1988), "Local computations with probabilities on
  graphical structures and their application to expert systems", *J. R. Stat. Soc. B* 50(2),
  157-224. doi:[10.1111/j.2517-6161.1988.tb01721.x](https://doi.org/10.1111/j.2517-6161.1988.tb01721.x)
  — the *asia* network.
- Scutari, M. (2010), "Learning Bayesian Networks with the bnlearn R Package", *J. Stat.
  Softw.* 35(3), 1-22. doi:[10.18637/jss.v035.i03](https://doi.org/10.18637/jss.v035.i03);
  repository <https://www.bnlearn.com/bnrepository/>.
- Raiffa, H. (1968), *Decision Analysis: Introductory Lectures on Choices under Uncertainty*,
  Addison-Wesley, and Shachter, R. D. (1986), "Evaluating Influence Diagrams", *Oper. Res.*
  34(6), 871-882. doi:[10.1287/opre.34.6.871](https://doi.org/10.1287/opre.34.6.871) — the
  umbrella problem.
- The Bayesian Network Model Archive, <https://bnma.co/bnrepo/> — record 132,
  `Habitat_Suitability.xdsl`.

The same list, with everything cited in the docstrings and the vignettes, is on the
[References](https://ecorecipes.github.io/BayesianNetworkFormats.jl/references/) page of the
documentation. The canonical BibTeX file is `docs/src/references.bib`.

## Fixture licences

`test/fixtures/{bif,net,dsc}/asia.*` are verbatim from the bnlearn repository (CC BY-SA 3.0);
everything else is MIT. See [`test/fixtures/LICENSES.md`](test/fixtures/LICENSES.md).
