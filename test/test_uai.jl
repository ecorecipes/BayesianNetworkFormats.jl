@testset "UAI" begin
    @testset "asia written by the package" begin
        ir = read_network(fix("uai/asia.uai"))
        @test ir.format == :uai
        @test ir.name == "asia"
        @test isequivalent(ir, golden("uai_asia.bnir.json"))
        @test isequivalent(ir, read_network(fix("bif/asia.bif")); name=false)
        @test marginal(ir, :dysp) ≈ [0.4360, 0.5640] atol = 1e-4
        text = read(fix("uai/asia.uai"), String)
        @test startswith(text, "BAYES\n8\n2 2 2 2 2 2 2 2\n8\n")
        @test occursin("\n3 4 5 7\n", text)          # dysp: parents bronc(4), either(5), child 7
    end

    @testset "without a names sidecar" begin
        ir = parse_string(read(fix("uai/asia.uai"), String), UAI())
        @test [v.id for v in ir.variables] == [Symbol("X$(i)") for i in 0:7]
        @test variable(ir, :X0).states == ["s0", "s1"]
        @test isequivalent(ir, read_network(fix("uai/habitat_reference.uai"));
                           name=false) == false
        hab = read_network(fix("uai/habitat_reference.uai"))
        @test isequivalent(hab, golden("uai_habitat_reference.bnir.json"))
        @test isequivalent(hab, habitat_reference_ir(); titles=false, positions=false,
                           comments=false, extras=false)
    end

    @testset "ChestClinic.uai written outside this package" begin
        # An external witness for the UAI table layout: the chest-clinic (asia) network in
        # BAYES form from the Merlin library (BSD 3-Clause; see fixtures/LICENSES.md).
        # It has no names sidecar, so the ids are the synthesised X0...X7.
        ir = read_network(fix("uai/ChestClinic.uai"))
        @test ir.format == :uai
        @test isequivalent(ir, golden("uai_ChestClinic.bnir.json"))
        @test [v.id for v in ir.variables] == [Symbol("X$(i)") for i in 0:7]
        # scopes are read child-last: `2 0 1` is P(X1 | X0), `3 1 5 7` is P(X7 | X1, X5)
        @test variable(ir, :X1).parents == [:X0]
        @test variable(ir, :X7).parents == [:X1, :X5]
        @test variable(ir, :X5).parents == [:X4, :X2]
        # X7 is dysp, X6 is xray: the published asia marginals, computed from a file this
        # package did not write. Only the child-fastest row-major reading normalises, so
        # this pins the layout against an external file.
        @test marginal(ir, :X7) ≈ [0.4360, 0.5640] atol = 1e-4
        @test marginal(ir, :X6) ≈ [0.1103, 0.8897] atol = 1e-4
        asia = read_network(fix("bif/asia.bif"))
        @test marginal(ir, :X7) ≈ marginal(asia, :dysp)
        @test variable(ir, :X7).table ≈ variable(asia, :dysp).table
        @test variable(ir, :X5).table ≈ variable(asia, :either).table
    end

    @testset "errors" begin
        e = try
            parse_string("MARKOV\n1\n2\n1\n1 0\n\n2\n0.5 0.5\n", UAI())
            nothing
        catch err
            err
        end
        @test e isa UnsupportedNodeError
        @test e.nodetype == "MARKOV"
        @test_throws ParseError parse_string("BAYES\n1\n2\n1\n1 0\n\n3\n0.5 0.5 0.1\n",
                                             UAI())
        @test_throws ParseError parse_string("BAYES\n1\n2\n1\n1 0\n\n2\n0.5\n", UAI())
        @test_throws ParseError parse_string("BAYES\n1\n2\n1\n1 5\n\n2\n0.5 0.5\n", UAI())
        @test_throws ParseError parse_string("", UAI())
        @test_throws ParseError parse_string("OTHER\n", UAI())
    end

    @testset "evidence files" begin
        asia = read_network(fix("uai/asia.uai"))
        mktempdir() do dir
            p = joinpath(dir, "asia.uai.evid")
            write_uai_evidence(p,
                               [Dict(:asia => "yes", :xray => "no"), Dict(:smoke => "yes")];
                               ir=asia)
            @test read(p, String) == "2\n2 0 0 6 1\n1 2 0\n"
            ev = read_uai_evidence(p)
            @test ev == [Dict(0 => 0, 6 => 1), Dict(2 => 0)]
            ev2 = read_uai_evidence(p; ir=asia)
            @test ev2 == [Dict(:asia => "yes", :xray => "no"), Dict(:smoke => "yes")]
            write(p, "2 1 0 2 1\n")                 # single-sample form without a count line
            @test read_uai_evidence(p) == [Dict(1 => 0, 2 => 1)]
            write(p, "1\n2 1 0\n")
            @test_throws ParseError read_uai_evidence(p)
            @test_throws KeyError write_uai_evidence(p, [Dict(:nope => "yes")]; ir=asia)
            @test_throws ValidationError write_uai_evidence(p, [Dict(:asia => "maybe")];
                                                            ir=asia)
        end
    end
end
