# Regenerate the fixtures that are produced by the package's own writers, and the golden
# `*.bnir.json` files for every fixture. Hand-written fixtures (determin_functable.dne,
# empty_list_entries.dne, levels_continuous.dne, levels_named_states.dne,
# state_index_literals.dne, equation_node.xdsl, sprinkler_table.bif) and the externally
# produced ones (bnlearn asia,
# uai/ChestClinic.uai, xdsl/Habitat_Suitability.xdsl) are never overwritten. Run from the
# package root:
#
#     julia --project scripts/regenerate_fixtures.jl
#
# Inspect the diff before committing: the generated files are hand-checked for layout.
using BayesianNetworkFormats
const ROOT = normpath(joinpath(@__DIR__, ".."))
const FIX = joinpath(ROOT, "test", "fixtures")
include(joinpath(ROOT, "test", "reference_models.jl"))

function emit(ir, rel; kwargs...)
    path = joinpath(FIX, rel)
    fmt = detect_format(path)
    open(path, "w") do io
        return write_network(io, ir, fmt; kwargs...)
    end
    fmt isa UAI &&
        open(io -> BayesianNetworkFormats.write_uai_names(io, ir), path * ".names", "w")
    return println("wrote ", rel)
end

habitat = habitat_reference_ir()
for ext in ("dne", "xdsl", "net", "bif", "dsc", "uai")
    emit(habitat, joinpath(ext, "habitat_reference.$ext"))
end
emit(habitat, joinpath("dne", "habitat_reference_flat.dne"); nested=false)

grazing = grazing_reference_ir()
for ext in ("dne", "xdsl", "net")
    emit(grazing, joinpath(ext, "grazing_reference_id.$ext"))
end

umbrella = umbrella_ir()
for ext in ("dne", "xdsl", "net")
    emit(umbrella, joinpath(ext, "umbrella.$ext"))
end

asia = read_network(joinpath(FIX, "bif", "asia.bif"))
emit(BayesianNetworkFormats._with(asia; name="asia"), joinpath("uai", "asia.uai"))

# golden IR for every fixture
for dir in ("dne", "xdsl", "net", "bif", "dsc", "uai"),
    f in sort(readdir(joinpath(FIX, dir)))

    endswith(f, ".names") && continue
    path = joinpath(FIX, dir, f)
    ir = read_network(path; strict=false)
    ir = BayesianNetworkFormats._with(ir; source=f)
    stem = replace(f, r"\.[^.]+$" => "")
    out = joinpath(FIX, "golden", "$(dir)_$(stem).bnir.json")
    write_ir_json(out, ir)
    println("wrote golden/", basename(out))
end
