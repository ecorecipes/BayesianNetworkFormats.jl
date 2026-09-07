# read -> write -> read for every fixture through every format that supports its node kinds,
# plus random-IR property tests.

const FIXTURE_FILES = ["dne/habitat_reference.dne", "dne/habitat_reference_flat.dne",
                       "dne/grazing_reference_id.dne",
                       "dne/umbrella.dne", "dne/determin_functable.dne",
                       "dne/levels_continuous.dne", "dne/levels_named_states.dne",
                       "xdsl/habitat_reference.xdsl", "xdsl/grazing_reference_id.xdsl",
                       "xdsl/umbrella.xdsl",
                       "xdsl/equation_node.xdsl", "xdsl/Habitat_Suitability.xdsl",
                       "net/asia.net", "net/habitat_reference.net",
                       "net/grazing_reference_id.net", "net/umbrella.net",
                       "bif/asia.bif", "bif/habitat_reference.bif",
                       "bif/sprinkler_table.bif",
                       "dsc/asia.dsc", "dsc/habitat_reference.dsc",
                       "uai/asia.uai", "uai/habitat_reference.uai",
                       "uai/ChestClinic.uai"]

# what each format preserves beyond structure and numbers
_keeps(::NeticaDNE) = (titles=true, positions=true, comments=true, deterministic=true)
_keeps(::GeNIeXDSL) = (titles=true, positions=true, comments=true, deterministic=true)
_keeps(::HuginNET) = (titles=true, positions=true, comments=true, deterministic=false)
_keeps(::BIF) = (titles=false, positions=true, comments=false, deterministic=false)
_keeps(::DSC) = (titles=false, positions=false, comments=false, deterministic=false)
_keeps(::UAI) = (titles=false, positions=false, comments=false, deterministic=false)
_keeps(::IRJSON) = (titles=true, positions=true, comments=true, deterministic=true)
# Netica network names must be identifiers; BIF and DSC substitute "unknown" for an empty name
function _keeps_name(ir, fmt)
    fmt isa NeticaDNE && return BayesianNetworkFormats._identifier(ir.name) == ir.name
    fmt isa Union{BIF,DSC} && return !isempty(ir.name)
    return true
end

function _can_write(ir, fmt)
    return !has_decisions(ir) && isempty(utilities(ir)) ||
           BayesianNetworkFormats._supports_decisions(fmt)
end

@testset "round trips" begin
    @testset "fixture $(f) through $(nameof(typeof(fmt)))" for f in FIXTURE_FILES,
                                                               fmt in ALL_WRITABLE

        ir = read_network(fix(f); strict=false)
        _can_write(ir, fmt) || continue
        # Netica state labels derived from `levels` are not identifiers in other formats
        haskey(variable(ir, ir.variables[1].id).extras, :levels) &&
            !(fmt isa Union{NeticaDNE,IRJSON}) && continue
        back = roundtrip(ir, fmt)
        k = _keeps(fmt)
        mau = BayesianNetworkFormats._supports_mau(fmt)
        opts = (atol=1e-12, titles=k.titles, positions=k.positions, comments=k.comments,
                deterministic=k.deterministic, extras=false, mau=mau,
                name=_keeps_name(ir, fmt))
        @test isequivalent(back, ir; opts...)
        isequivalent(back, ir; opts...) ||
            println(f, " via ", fmt, ": ", differences(back, ir; opts...))
    end

    @testset "random Bayesian networks" begin
        rng = MersenneTwister(20260906)
        for trial in 1:25
            ir = random_ir(rng)
            @test validate(ir) === ir
            for fmt in ALL_WRITABLE
                back = roundtrip(ir, fmt)
                @test isequivalent(back, ir; atol=1e-12)
                isequivalent(back, ir; atol=1e-12) ||
                    println("trial ", trial, " ", fmt, ": ",
                            differences(back, ir; atol=1e-12))
            end
            @test marginal(roundtrip(ir, BIF()), ir.variables[end].id) ≈
                  marginal(ir, ir.variables[end].id)
        end
    end

    @testset "random influence diagrams" begin
        rng = MersenneTwister(4711)
        for trial in 1:15
            ir = random_ir(rng; with_decision=true, with_utility=rand(rng, Bool))
            @test validate(ir) === ir
            for fmt in (NeticaDNE(), GeNIeXDSL(), HuginNET(), IRJSON())
                back = roundtrip(ir, fmt)
                @test isequivalent(back, ir; atol=1e-12)
                isequivalent(back, ir; atol=1e-12) ||
                    println("ID trial ", trial, " ", fmt, ": ",
                            differences(back, ir; atol=1e-12))
            end
            for fmt in (BIF(), DSC(), UAI())
                @test_throws UnsupportedNodeError write_string(ir, fmt)
            end
        end
    end

    @testset "flat and nested Netica output" begin
        ir = habitat_reference_ir()
        flat = write_string(ir, NeticaDNE(); nested=false)
        nested = write_string(ir, NeticaDNE(); nested=true)
        @test flat != nested
        @test occursin("(((0.7,", nested) && !occursin("(((", flat)
        @test isequivalent(parse_string(flat, NeticaDNE()), ir; extras=false)
        @test isequivalent(parse_string(nested, NeticaDNE()), ir; extras=false)
    end
end
