# Fixture licences

| Files | Origin | Licence |
|---|---|---|
| `bif/asia.bif`, `net/asia.net`, `dsc/asia.dsc` | The *asia* network from the [bnlearn Bayesian Network Repository](https://www.bnlearn.com/bnrepository/) (Lauritzen and Spiegelhalter 1988), downloaded verbatim from `https://www.bnlearn.com/bnrepository/asia/asia.{bif,net,dsc}.gz` and decompressed. | [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/), attribution: Marco Scutari, bnlearn Bayesian Network Repository. |
| `uai/asia.uai`, `uai/asia.uai.names`, `golden/*asia*.bnir.json` | Derived from the files above with this package's writers. | CC BY-SA 3.0 (derivative work), same attribution. |
| `dne/habitat_reference*.dne`, `xdsl/habitat_reference.xdsl`, `net/habitat_reference.net`, `bif/habitat_reference.bif`, `dsc/habitat_reference.dsc`, `uai/habitat_reference.uai*` | SPEC section 45 reference ecological BN, written as IR in `test/reference_models.jl` and generated with `scripts/regenerate_fixtures.jl`. | MIT (this repository). |
| `dne/grazing_reference_id.dne`, `xdsl/grazing_reference_id.xdsl`, `net/grazing_reference_id.net` | SPEC section 46 reference ecological influence diagram, generated as above. | MIT. |
| `dne/umbrella.dne`, `xdsl/umbrella.xdsl`, `net/umbrella.net` | Shachter's umbrella problem, written from the published numbers in this package's own text (no Norsys or BayesFusion text is reproduced). | MIT. |
| `dne/determin_functable.dne`, `dne/empty_list_entries.dne`, `dne/levels_continuous.dne`, `dne/levels_named_states.dne`, `dne/state_index_literals.dne`, `xdsl/equation_node.xdsl`, `bif/sprinkler_table.bif` | Hand-written grammar fixtures. | MIT. |
| `uai/ChestClinic.uai` | The *Chest Clinic* (asia) network in UAI `BAYES` form, downloaded verbatim from the [Merlin](https://github.com/radum2275/merlin) probabilistic-inference library (`examples/ChestClinic.uai`, `https://raw.githubusercontent.com/radum2275/merlin/master/examples/ChestClinic.uai`, retrieved 2026-09-07, sha256 `46467afee3d108ab7c586ec218d22f10dcba061cd6603b58fa59a82d3a375a9a`). Written by a third-party tool, so it is an external witness for the UAI table layout. | [BSD 3-Clause](https://opensource.org/licenses/BSD-3-Clause); copyright (c) 2015-2018 International Business Machines Corporation and University of California Irvine. Full notice below. |
| `xdsl/Habitat_Suitability.xdsl` | GeNIe-written *Habitat Suitability* (Sumatran tiger relocation) network, record 132 of the [BNMA Bayesian Network Repository](https://bnma.co/bn/132), copied verbatim from `EcologicalBayesianNetworks.jl/models/habitat_suitability_tiger/` (sha256 `063a22b8254a4b3178f865d9bcad687a95abf2e6a7b536747b95ca4771bbcb93`; the space in the served filename `Habitat Suitability.xdsl` was replaced by an underscore, content unchanged). Written by GeNIe 2.0, so it is an external witness for the XDSL table layout. | CC BY, version unstated on the source record. The accompanying zoo notice treats it as [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); that is a documented interpretation, not an explicit version on the record. Attribution: Dhananjay Thiruvady, *Habitat Suitability*, BNMA record 132 (2015). |
| `golden/*.bnir.json` (other than asia) | Generated from the fixtures above. | MIT. |

The Netica example networks from Norsys and the Plexus Ecology `.dne` files that were used
to verify the `.dne` grammar are not redistributed here; they were only read.

## BSD 3-Clause notice for `uai/ChestClinic.uai`

Copyright (c) 2015-2018, International Business Machines Corporation and University of
California Irvine. All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of
  conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright notice, this list of
  conditions and the following disclaimer in the documentation and/or other materials
  provided with the distribution.
* Neither the name of the copyright holder nor the names of its contributors may be used to
  endorse or promote products derived from this software without specific prior written
  permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
