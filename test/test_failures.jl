@testset "failure modes" begin
    @testset "malformed input" begin
        e = try
            parse_string("bnet x { node A { kind = NATURE; states = (a, b; }; };",
                         NeticaDNE(); file="bad.dne")
            nothing
        catch err
            err
        end
        @test e isa ParseError
        @test e.file == "bad.dne" && e.line == 1
        @test_throws ParseError parse_string("no bnet here", NeticaDNE())
        @test_throws ParseError parse_string("bnet x { node A { kind = NATURE; states = (a, b); parents = (Z); }; };",
                                             NeticaDNE())
        @test_throws ParseError parse_string("bnet x { node A { states = (a, b); parents = (); probs = (0.5, 0.5, 0.5); }; };",
                                             NeticaDNE())
        @test_throws ParseError parse_string("bnet x { node A { chance = DETERMIN; states = (a, b); parents = (); functable = (c); }; };",
                                             NeticaDNE())
        @test_throws ParseError parse_string("network x {\nvariable A { type discrete [ 2 ] { a, b }; }\nprobability ( A ) { table 0.5, 0.5 }",
                                             BIF())
        @test_throws ParseError parse_string("belief network \"x\"\nnode A { type : discrete [ 2 ] = { \"a\" \"b\" }; }\nprobability ( A ) { 0.5 0.5 }",
                                             DSC())
        @test_throws ParseError parse_string("net { } node A { states = (\"a\" \"b\"); } potential (A) { data = (0.5 0.5 0.5); }",
                                             HuginNET())
        @test_throws ParseError parse_string("<smile version=\"1.0\" id=\"x\"><nodes><cpt id=\"A\"><state id=\"a\"/><state id=\"b\"/><probabilities>0.5</probabilities></cpt></nodes></smile>",
                                             GeNIeXDSL())
        @test_throws ParseError parse_string("<smile version=\"1.0\" id=\"x\"><nodes><cpt id=\"A\"><state id=\"a\"/><state id=\"b\"/><probabilities>0.5 x</probabilities></cpt></nodes></smile>",
                                             GeNIeXDSL())
    end

    @testset "unknown node types: strict vs non-strict" begin
        dne = "bnet x { node A { kind = NATURE; states = (a, b); parents = (); probs = (0.5, 0.5); };\n" *
              "node W { kind = WEIRD; states = (a); parents = (A); }; };"
        e = try
            parse_string(dne, NeticaDNE())
            nothing
        catch err
            err
        end
        @test e isa UnsupportedNodeError && e.id == "W" && e.nodetype == "WEIRD" &&
              e.format == :dne
        ir = parse_string(dne, NeticaDNE(); strict=false)
        @test [v.id for v in ir.variables] == [:A]
        @test ir.extras[:skipped][1]["id"] == "W"
        cont = "bnet x { node C { kind = NATURE; discrete = FALSE; parents = (); }; };"
        @test_throws UnsupportedNodeError parse_string(cont, NeticaDNE())
        @test isempty(parse_string(cont, NeticaDNE(); strict=false).variables)
    end

    @testset "non-normalised rows" begin
        bif = "network x { }\nvariable A { type discrete [ 2 ] { a, b }; }\nvariable B { type discrete [ 2 ] { a, b }; }\n" *
              "probability ( A ) { table 0.5, 0.5; }\nprobability ( B | A ) { (a) 0.2, 0.2; (b) 0.5, 0.5; }\n"
        e = try
            parse_string(bif, BIF())
            nothing
        catch err
            err
        end
        @test e isa NotNormalizedError
        @test e.id == :B && e.index == (1,) && e.total ≈ 0.4
        ir = parse_string(bif, BIF(); renormalize=true)
        @test variable(ir, :B).table[1, :] ≈ [0.5, 0.5]
        @test_throws NotNormalizedError parse_string(bif, BIF(); atol=0.1)
        @test parse_string(bif, BIF(); atol=0.7) isa NetworkIR
        # Netica's 7 significant digits are within the default tolerance
        dne = "bnet x { node A { kind = NATURE; states = (a, b, c); parents = (); probs = (0.3333333, 0.3333333, 0.3333333); }; };"
        @test parse_string(dne, NeticaDNE()) isa NetworkIR
    end

    @testset "duplicate ids" begin
        dne = "bnet x { node A { kind = NATURE; states = (a, b); parents = (); probs = (0.5, 0.5); };\n" *
              "node A { kind = NATURE; states = (a, b); parents = (); probs = (0.5, 0.5); }; };"
        e = try
            parse_string(dne, NeticaDNE())
            nothing
        catch err
            err
        end
        @test e isa ValidationError && e.id == :A
        bif = "network x { }\nvariable A { type discrete [ 2 ] { a, b }; }\nvariable A { type discrete [ 2 ] { a, b }; }\n"
        @test_throws ParseError parse_string(bif, BIF())
        xdsl = "<smile version=\"1.0\" id=\"x\"><nodes><cpt id=\"A\"><state id=\"a\"/><state id=\"b\"/><probabilities>0.5 0.5</probabilities></cpt>" *
               "<cpt id=\"A\"><state id=\"a\"/><state id=\"b\"/><probabilities>0.5 0.5</probabilities></cpt></nodes></smile>"
        @test_throws ValidationError parse_string(xdsl, GeNIeXDSL())
    end

    @testset "identifier collisions after sanitisation" begin
        # Validation runs on the IR names, sanitisation afterwards: two names that differ
        # in the IR but sanitise to one identifier used to produce an unreadable file.
        states = NetworkIR("c", [IRVariable(:A; states=["a b", "a_b"], table=[0.5, 0.5])])
        for fmt in (NeticaDNE(), GeNIeXDSL())
            e = try
                write_string(states, fmt)
                nothing
            catch err
                err
            end
            @test e isa IdentifierCollisionError
            @test e.id == :A && e.kind == :state && e.sanitized == "a_b"
            @test e.originals == ("a b", "a_b") && e.format == format_name(fmt)
            msg = sprint(showerror, e)
            @test occursin("\"a b\"", msg) && occursin("\"a_b\"", msg)
        end
        # BIF and DSC quote state names, so they accept the same IR
        @test write_string(states, BIF()) isa String
        @test write_string(states, DSC()) isa String
        # UAI writes the names sidecar, which cannot tell the two apart either
        @test_throws IdentifierCollisionError write_string(states, UAI())

        ids = NetworkIR("c",
                        [IRVariable(Symbol("a b"); states=["x", "y"], table=[0.5, 0.5]),
                         IRVariable(Symbol("a-b"); states=["x", "y"], table=[0.5, 0.5])])
        for fmt in (NeticaDNE(), GeNIeXDSL(), HuginNET(), DSC())
            e = try
                write_string(ids, fmt)
                nothing
            catch err
                err
            end
            @test e isa IdentifierCollisionError
            @test e.id == :network && e.kind == :variable && e.sanitized == "a_b"
        end
        @test write_string(ids, BIF()) isa String
        @test write_string(ids, IRJSON()) isa String
        # UAI only replaces whitespace, so "a-b" is safe but "a_b" is not
        @test write_string(ids, UAI()) isa String
        uai_ids = NetworkIR("c",
                            [IRVariable(Symbol("a b"); states=["x", "y"],
                                        table=[0.5, 0.5]),
                             IRVariable(Symbol("a_b"); states=["x", "y"],
                                        table=[0.5, 0.5])])
        @test_throws IdentifierCollisionError write_string(uai_ids, UAI())

        # Netica limits node and state names to 30 characters
        long = "A"^31
        e = try
            write_string(NetworkIR("l",
                                   [IRVariable(Symbol(long); states=["x", "y"],
                                               table=[0.5, 0.5])]), NeticaDNE())
            nothing
        catch err
            err
        end
        @test e isa IdentifierLengthError
        @test e.kind == :variable && e.limit == 30 && e.format == :dne
        @test occursin("31 characters", sprint(showerror, e))
        longstate = NetworkIR("l",
                              [IRVariable(:A; states=["x", "s"^31], table=[0.5, 0.5])])
        e2 = try
            write_string(longstate, NeticaDNE())
            nothing
        catch err
            err
        end
        @test e2 isa IdentifierLengthError && e2.id == :A && e2.kind == :state
        # 30 characters exactly are fine, and the other formats do not impose the limit
        @test write_string(NetworkIR("l",
                                     [IRVariable(Symbol("A"^30); states=["x", "y"],
                                                 table=[0.5, 0.5])]), NeticaDNE()) isa
              String
        @test write_string(longstate, GeNIeXDSL()) isa String
    end

    @testset "writers refuse what a format cannot hold" begin
        gr = grazing_reference_ir()
        for fmt in (BIF(), DSC(), UAI())
            e = try
                write_string(gr, fmt)
                nothing
            catch err
                err
            end
            @test e isa UnsupportedNodeError
            @test e.id == "GrazingManagement" && e.nodetype == "decision"
        end
        weighted = BayesianNetworkFormats._with(gr;
                                                mau=[MAUNode(:T,
                                                             [:ConservationBenefit,
                                                              :ManagementCost], [1.0, 2.0])])
        for fmt in (NeticaDNE(), HuginNET())
            e = try
                write_string(weighted, fmt)
                nothing
            catch err
                err
            end
            @test e isa UnsupportedNodeError && e.id == "T"
        end
        @test write_string(weighted, GeNIeXDSL()) isa String
        no_table = NetworkIR("nt", [IRVariable(:A; states=["a", "b"])])
        for fmt in (GeNIeXDSL(), BIF(), DSC(), UAI())
            @test_throws ValidationError write_string(no_table, fmt)
        end
        @test write_string(no_table, NeticaDNE()) isa String
        @test write_string(no_table, HuginNET()) isa String
        bad = NetworkIR("b", [IRVariable(:A; states=["a", "b"], table=[0.7, 0.7])])
        @test_throws NotNormalizedError write_string(bad, BIF())
    end
end
