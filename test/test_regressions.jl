@testset "positional trailing unnamed Netica links" begin
    for cells in ([""], ["", ""], ["named", ""], ["", "middle", ""],
                  ["", "middle", "last"])
        n = length(cells)
        parents = [Symbol(:P, i) for i in 1:n]
        vars = [IRVariable(p; states=["no", "yes"], table=[0.5, 0.5]) for p in parents]
        push!(vars,
              IRVariable(:X; states=["no", "yes"], parents=parents,
                         table=fill(0.5, ntuple(_ -> 2, n + 1)),
                         extras=Dict(:inputs => cells)))
        ir = NetworkIR("unnamed-links", vars)
        back = parse_string(write_string(ir, NeticaDNE()), NeticaDNE())
        @test variable(back, :X).extras[:inputs] == cells
        @test variable(back, :X).parents == parents
        @test variable(back, :X).table == variable(ir, :X).table
    end
end

@testset "renormalization cannot bless nonfinite rows" begin
    for row in
        ([Inf, 1.0], [-Inf, 1.0], [NaN, 1.0], [floatmax(Float64), floatmax(Float64)])
        ir = NetworkIR("nonfinite", [IRVariable(:X; states=["a", "b"], table=row)])
        for renormalize in (false, true)
            @test_throws ValidationError validate(ir; renormalize)
        end
        @test isequal(variable(ir, :X).table, row)
    end
    ir = NetworkIR("finite", [IRVariable(:X; states=["a", "b"], table=[2.0, 6.0])])
    @test variable(validate(ir; renormalize=true), :X).table == [0.25, 0.75]
    @test variable(ir, :X).table == [2.0, 6.0]
    for atol in (-1.0, Inf, NaN)
        @test_throws ArgumentError validate(ir; atol, renormalize=true)
    end
end

@testset "writers keep a name that needed sanitising" begin
    # The .dne and .net writers emit `_identifier(v.id)` as the node name but used to suppress
    # the title/label whenever it equalled the *raw* id, so a name containing a space was
    # silently unrecoverable. Compare against the sanitised identifier instead.
    ir = NetworkIR("t",
                   [IRVariable(Symbol("Habitat quality"); states=["lo", "hi"],
                               table=[0.3, 0.7])])
    for (ext, fmt) in (("net", HuginNET()), ("dne", NeticaDNE()))
        path = joinpath(mktempdir(), "sanitised." * ext)
        write_network(path, ir; format=fmt)
        back = read_network(path)
        @test back.variables[1].title == "Habitat quality"
        @test back.variables[1].table ≈ [0.3, 0.7]
    end
end

@testset "a UTF-8 BOM does not defeat the readers" begin
    # Netica and GeNIe are Windows tools and their files are routinely saved with a
    # byte-order mark. Left in place it is just an unexpected character at 1:1, which every
    # tokenizer-based reader rejected (`.uai` complained of a missing BAYES header);
    # only `.xdsl` survived, because EzXML strips it.
    cases = [("dne", "dne/habitat_reference.dne"), ("net", "net/habitat_reference.net"),
             ("bif", "bif/habitat_reference.bif"), ("dsc", "dsc/habitat_reference.dsc"),
             ("uai", "uai/ChestClinic.uai"), ("xdsl", "xdsl/habitat_reference.xdsl")]
    for (ext, rel) in cases
        src = fixture_path(rel)
        plain = read_network(src)
        withbom = joinpath(mktempdir(), "bom." * ext)
        write(withbom, "﻿" * read(src, String))
        ir = read_network(withbom)
        @test length(ir.variables) == length(plain.variables)
        @test [v.id for v in ir.variables] == [v.id for v in plain.variables]
    end
end
