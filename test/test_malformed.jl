# Malformed file content raises the package's typed errors, never a Base exception such as
# `InexactError`, `OverflowError`, `BoundsError`, `KeyError` or `MethodError` (ADR 0015).
# Each case changes one well-formed input in one place.
@testset "malformed content (ADR 0015)" begin
    @testset "tokenizer" begin
        bif(n) = "network x { }\nvariable A { type discrete [ $n ] { a, b }; }\n" *
                 "probability ( A ) { table 0.5, 0.5; }\n"
        @test parse_string(bif("2"), BIF()) isa NetworkIR
        @test parse_string(bif("0x2"), BIF()) isa NetworkIR
        @test_throws ParseError parse_string(bif("0xFFFFFFFFFFFFFFFFFFFF"), BIF())
        dne = read(fix("dne/state_index_literals.dne"), String)
        m = match(r"#\d+", dne)
        @test m !== nothing
        @test_throws ParseError parse_string(replace(dne,
                                                     m.match => "#99999999999999999999";
                                                     count=1), NeticaDNE())
    end

    @testset "BIF" begin
        src = "network x { }\nvariable A { type discrete [ 2 ] { a, b }; }\n" *
              "probability ( A ) { table 0.5, 0.5; }\n"
        @test_throws ParseError parse_string(replace(src, "[ 2 ]" => "[ 2.5 ]"), BIF())
        @test_throws ParseError parse_string(replace(src, "[ 2 ]" => "[ 1e30 ]"), BIF())
        positioned = replace(src,
                             "{ a, b };" => "{ a, b };\n property position = (1-2, 3);")
        @test_throws ParseError parse_string(positioned, BIF())
        good = replace(src, "{ a, b };" => "{ a, b };\n property position = (1.5, -3);")
        @test parse_string(good, BIF()) isa NetworkIR
    end

    @testset "DSC" begin
        src = read(fix("dsc/asia.dsc"), String)
        @test_throws ParseError parse_string(replace(src,
                                                     "discrete [ 2 ]" => "discrete [ 2.5 ]";
                                                     count=1), DSC())
        @test_throws ParseError parse_string(replace(src, "(0) : 0.05" => "(0.5) : 0.05";
                                                     count=1), DSC())
    end

    @testset "Netica DNE" begin
        node(attrs) = "bnet t {\nnode A {\n\tkind = NATURE;\n\tdiscrete = $(attrs);\n" *
                      "\tparents = ();\n\tprobs = (0.5, 0.5);\n\t};\n};\n"
        @test parse_string(node("TRUE;\n\tnumstates = 2"), NeticaDNE()) isa NetworkIR
        @test_throws ParseError parse_string(node("TRUE;\n\tnumstates = 2.5"), NeticaDNE())
        @test_throws ParseError parse_string(node("TRUE;\n\tnumstates = two"), NeticaDNE())
        visual(center) = node("TRUE;\n\tstates = (a, b);\n\tvisual V1 {\n\t\tcenter = $(center);\n\t\t}")
        @test parse_string(visual("(10, 20)"), NeticaDNE()) isa NetworkIR
        @test_throws ParseError parse_string(visual("(x, y)"), NeticaDNE())
        # A continuous node with fewer states than level intervals, and a functable value in
        # an interval that has no state.
        det = "bnet t {\nnode T {\n\tkind = NATURE;\n\tdiscrete = FALSE;\n\tchance = DETERMIN;\n" *
              "\tstates = (lo, hi);\n\tlevels = (0, 1, 2, 3);\n\tparents = ();\n" *
              "\tfunctable = (VALUE);\n\t};\n};\n"
        @test parse_string(replace(det, "VALUE" => "0.5"), NeticaDNE()) isa NetworkIR
        @test_throws ParseError parse_string(replace(det, "VALUE" => "2.5"), NeticaDNE())
    end

    @testset "HUGIN NET" begin
        src = "net { }\nnode A { states = STATES; position = POSITION; }\n" *
              "potential (A) { data = (0.3 0.7); }\n"
        net(states, position) = replace(src, "STATES" => states, "POSITION" => position)
        @test parse_string(net("(\"a\" \"b\")", "(10 20)"), HuginNET()) isa NetworkIR
        @test_throws ParseError parse_string(net("foo", "(10 20)"), HuginNET())
        @test_throws ParseError parse_string(net("(\"a\" \"b\")", "(x y)"), HuginNET())
    end

    @testset "GeNIe XDSL" begin
        src = """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <smile version="1.0" id="x" numsamples="10000">
          <nodes>
            <cpt id="A"><state id="a"/><state id="b"/><probabilities>0.4 0.6</probabilities></cpt>
          </nodes>
        </smile>
        """
        @test parse_string(src, GeNIeXDSL()) isa NetworkIR
        @test_throws ParseError parse_string(replace(src,
                                                     "<state id=\"b\"/>" => "<state/>"),
                                             GeNIeXDSL())
    end

    @testset "UAI" begin
        ok = "BAYES\n1\n2\n1\n1 0\n\n2\n0.5 0.5\n"
        @test parse_string(ok, UAI()) isa NetworkIR
        @test_throws ParseError parse_string("BAYES\n-1\n", UAI())
        @test_throws ParseError parse_string("BAYES\n1\n-2\n1\n1 0\n\n2\n0.5 0.5\n", UAI())
        @test_throws ParseError parse_string("BAYES\n1\n2\n-1\n", UAI())
        @test_throws ParseError parse_string("BAYES\n1\n2\n1\n0\n\n1\n1.0\n", UAI())
        mktempdir() do dir
            ir = parse_string(ok, UAI())
            path = joinpath(dir, "e.uai.evid")
            write(path, "2 -3 0")
            @test_throws ParseError read_uai_evidence(path)
            write(path, "1\n1 0 1\n")
            @test read_uai_evidence(path; ir) == [Dict(:X0 => "s1")]
            write(path, "1\n1 5 0\n")
            @test_throws ParseError read_uai_evidence(path; ir)
            write(path, "1\n1 0 7\n")
            @test_throws ParseError read_uai_evidence(path; ir)
        end
    end

    @testset "IR JSON" begin
        text = read(fix("golden/bif_asia.bnir.json"), String)
        @test parse_string(text, IRJSON()) isa NetworkIR
        bad(f) = @test_throws ParseError read_ir_json(IOBuffer(f(text)))
        bad(t -> "[1]")
        bad(t -> replace(t, "\"variables\"" => "\"vars\""; count=1))
        bad(t -> replace(t, r"\"kind\": \"[a-z]+\"" => "\"kind\": 1"; count=1))
        bad(t -> replace(t, r"\"title\": \"[^\"]*\"" => "\"title\": 5"; count=1))
        bad(t -> replace(t, r"\"id\": \"[^\"]*\"" => "\"id\": 3"; count=1))
        bad(t -> replace(t, r"\"states\": \[" => "\"states\": [1, "; count=1))
        bad(t -> replace(t, r"\"dims\": \[\s*2" => "\"dims\": [1.5"; count=1))
        bad(t -> replace(t, r"\"dims\": \[\s*2" => "\"dims\": [-2"; count=1))
        bad(t -> replace(t, r"\"values\": \[" => "\"values\": [\"x\", "; count=1))
        bad(t -> replace(t,
                         r"\"position\": [^,\n]*(,\s*[-0-9.]+\s*\])?" => "\"position\": [1]";
                         count=1))
        bad(t -> replace(t, r"\"extras\": \{\}" => "\"extras\": 3"; count=1))
    end
end
