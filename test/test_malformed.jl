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
        # These fit an `Int` but not a `Float64`, which rounds the first up to 2^63: reading
        # the index back from the token's value was an `InexactError`. The index is read from
        # its text, so it is an index out of range like any other.
        for k in ("#9223372036854775807", "#9007199254740993")
            e = try
                parse_string(replace(dne, m.match => k; count=1), NeticaDNE())
                nothing
            catch err
                err
            end
            @test e isa ParseError
            @test occursin("state index $(k) of node", e.message)
        end
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
        # `numstates` names no state, so its count was an allocation size: 10^15 raised
        # `OutOfMemoryError`. It is checked against `max_states` before any name is made, and
        # a structure-only file may count more states than it has tokens (this one has 25).
        structure(n) = "bnet t {\nnode A {\n\tkind = NATURE;\n\tdiscrete = TRUE;\n" *
                       "\tnumstates = $(n);\n\tparents = ();\n\t};\n};\n"
        @test variable(parse_string(structure("3"), NeticaDNE()), :A).states ==
              ["s0", "s1", "s2"]
        @test length(variable(parse_string(structure("50"), NeticaDNE()), :A).states) == 50
        for n in ("1e15", "100000")
            e = try
                parse_string(structure(n), NeticaDNE())
                nothing
            catch err
                err
            end
            @test e isa ParseError
            @test occursin("node A has $(Int(parse(Float64, n))) states", e.message)
            @test occursin("max_states = 65536", e.message)
        end
        # raising the limit reads a moderately large count
        wide = parse_string(structure("100000"), NeticaDNE(); max_states=200_000)
        @test length(variable(wide, :A).states) == 100_000
        @test variable(wide, :A).states[end] == "s99999"
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
        # A declared count is not an allocation size. Each of these declared 10^15 variables,
        # functions or scope members and raised `OutOfMemoryError`; the file ends first.
        for src in ("BAYES 1000000000000000 2", "BAYES 1 2 1000000000000000",
                    "BAYES 1 2 1 1000000000000000 0")
            e = try
                parse_string(src, UAI())
                nothing
            catch err
                err
            end
            @test e isa ParseError
            @test occursin("unexpected end of file", e.message)
        end
        # A table size is a product of cardinalities, checked against `max_table_cells`
        # before its values are read: two variables within `max_states` declare 2^32 cells.
        e = try
            parse_string("BAYES 2 65536 65536 1 2 0 1 4294967296 0.5", UAI())
            nothing
        catch err
            err
        end
        @test e isa ParseError
        @test occursin("table 0 (of variable 1) has 4294967296 cells", e.message)
        @test occursin("max_table_cells = $(2^27)", e.message)
        # Without a names file the states of a variable are generated: `BAYES 1 1000000000 0`,
        # 19 bytes, built 10^9 state names. A cardinality is checked against `max_states` as
        # it is read. (100 000 stands in for 10^9 here, so that a regression fails without the
        # allocation.)
        e = try
            parse_string("BAYES 1 100000 0", UAI())
            nothing
        catch err
            err
        end
        @test e isa ParseError
        @test occursin("variable 0 has 100000 states, more than max_states = 65536",
                       e.message)
        wide = parse_string("BAYES 1 100000 0", UAI(); max_states=100_000)
        @test length(variable(wide, :X0).states) == 100_000
        @test variable(parse_string("BAYES 1 3 0", UAI()), :X0).states == ["s0", "s1", "s2"]
        mktempdir() do dir
            # listed names are counted against the same limit
            model = joinpath(dir, "m.uai")
            write(model, "BAYES 1 5 0")
            write(model * ".names", "A a b c d e\n")
            @test variable(read_network(model), :A).states == ["a", "b", "c", "d", "e"]
            @test_throws ParseError read_network(model; max_states=4)
        end
        # The size of a table is a checked product: a scope of 64 binary variables has 2^64
        # entries, which wrapped to 0 and matched an empty table, and `reshape` then raised
        # `ArgumentError`. (Binary variables, rather than two of 2^32 states, keep a
        # regression from generating 2^32 state names.)
        wide = "BAYES 64 " * join(fill("2", 64), " ") * " 1 64 " * join(0:63, " ") * " 0"
        e = try
            parse_string(wide, UAI())
            nothing
        catch err
            err
        end
        @test e isa ParseError
        @test occursin("more cells than a 64-bit integer can count", e.message)
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
            # `2k` overflowed for these pair counts, the wrapped bound passed, and the
            # comprehension raised `ArgumentError`
            for text in ("9223372036854775807 0 1\n", "1\n4611686018427387904 0 1\n")
                write(path, text)
                @test_throws ParseError read_uai_evidence(path)
            end
        end
    end

    @testset "table sizes that overflow an Int" begin
        # Sixteen parents of sixteen listed states: the parent configurations number
        # 16^16 = 2^64, which wraps to 0, so an empty table matched the unchecked product and
        # `reshape`, `fill` or `zeros` raised `ArgumentError`.
        ps = ["P$(i)" for i in 1:16]
        sts = ["s$(k)" for k in 0:15]
        quoted = join(("\"$(s)\"" for s in sts), " ")
        uniform = join(fill("0.0625", 16), " ")
        dne = "bnet x {\n" *
              join("node $(p) { kind = NATURE; discrete = TRUE; states = ($(join(sts, ", "))); parents = (); };\n"
                   for p in ps) *
              "node C { kind = NATURE; discrete = TRUE; states = (a, b); " *
              "parents = ($(join(ps, ", "))); probs = (); };\n};\n"
        cases = [(BIF(),
                  "network x { }\n" *
                  join("variable $(p) { type discrete [ 16 ] { $(join(sts, ", ")) }; }\n"
                       for p in ps) *
                  "variable C { type discrete [ 2 ] { a, b }; }\n" *
                  "probability ( C | $(join(ps, ", ")) ) { table 0.5, 0.5; }\n"),
                 (DSC(),
                  "belief network \"x\"\n" *
                  join("node $(p) { type : discrete [ 16 ] = { $(join(sts, ", ")) }; }\n"
                       for p in ps) *
                  "node C { type : discrete [ 2 ] = { a, b }; }\n" *
                  "probability ( C | $(join(ps, ", ")) ) { }\n"),
                 (HuginNET(),
                  "net { }\n" * join("node $(p) { states = ($(quoted)); }\n" for p in ps) *
                  "node C { states = (\"a\" \"b\"); }\n" *
                  "potential (C | $(join(ps, " "))) { data = (); }\n"),
                 (GeNIeXDSL(),
                  "<?xml version=\"1.0\"?>\n<smile version=\"1.0\" id=\"x\"><nodes>\n" *
                  join("<cpt id=\"$(p)\">$(join("<state id=\"$(s)\"/>" for s in sts))" *
                       "<probabilities>$(uniform)</probabilities></cpt>\n" for p in ps) *
                  "<cpt id=\"C\"><state id=\"a\"/><state id=\"b\"/>" *
                  "<parents>$(join(ps, " "))</parents><probabilities></probabilities></cpt>\n" *
                  "</nodes></smile>\n"),
                 (NeticaDNE(), dne),
                 (NeticaDNE(),
                  replace(dne, "probs = ();" => "chance = DETERMIN; functable = ();"))]
        for (fmt, src) in cases
            e = try
                parse_string(src, fmt)
                nothing
            catch err
                err
            end
            @test e isa ParseError
            @test occursin("more cells than a 64-bit integer can count", e.message)
        end
    end

    @testset "size limits" begin
        caught(f) =
            try
                f()
                nothing
            catch err
                err
            end
        # Eight parents of 128 listed states and a `default` row: 5.7 KB that declare a table
        # of 2^57 cells, which `fill` tried to allocate (`OutOfMemoryError`). A `default` row
        # makes such a table well-formed, so only a limit can refuse it.
        ps = ["P$(i)" for i in 1:8]
        sts = join(("s$(k)" for k in 0:127), ", ")
        bif(parents, rows) = "network x { }\n" *
                             join("variable $(p) { type discrete [ 128 ] { $(sts) }; }\n"
                                  for p in parents) *
                             "variable C { type discrete [ 2 ] { a, b }; }\n" *
                             "probability ( C | $(join(parents, ", ")) ) { $(rows) }\n"
        huge = bif(ps, "default 0.5, 0.5;")
        @test sizeof(huge) < 6000
        e = caught(() -> parse_string(huge, BIF()))
        @test e isa ParseError
        @test occursin("the table of C has $(2^57) cells", e.message)
        @test occursin("more than max_table_cells = $(2^27)", e.message)
        # DSC allocated its tables before their rows in the same way
        dsc = "belief network \"x\"\n" *
              join("node $(p) { type : discrete [ 128 ] = { $(sts) }; }\n" for p in ps) *
              "node C { type : discrete [ 2 ] = { a, b }; }\n" *
              "probability ( C | $(join(ps, ", ")) ) { }\n"
        e = caught(() -> parse_string(dsc, DSC()))
        @test e isa ParseError && occursin("max_table_cells", e.message)
        # 128 x 128 x 2 = 32 768 cells: refused below that limit, read at it
        two = bif(ps[1:2], "default 0.5, 0.5;")
        @test_throws ParseError parse_string(two, BIF(); max_table_cells=32_767)
        @test size(variable(parse_string(two, BIF(); max_table_cells=32_768), :C).table) ==
              (128, 128, 2)
        # Every format applies both limits, to listed and generated states and to every
        # table, and a limit equal to the largest size reads the file.
        for rel in ("dne/habitat_reference.dne", "xdsl/habitat_reference.xdsl",
                    "net/asia.net", "bif/asia.bif", "dsc/asia.dsc", "uai/asia.uai",
                    "golden/bif_asia.bnir.json")
            ir = read_network(fix(rel))
            states = maximum(length(v.states) for v in ir.variables)
            cells = maximum(length(v.table) for v in ir.variables if v.table !== nothing)
            @test read_network(fix(rel); max_states=states, max_table_cells=cells) == ir
            e = caught(() -> read_network(fix(rel); max_states=states - 1))
            @test e isa ParseError && occursin("max_states = $(states - 1)", e.message)
            e = caught(() -> read_network(fix(rel); max_table_cells=cells - 1))
            @test e isa ParseError && occursin("max_table_cells = $(cells - 1)", e.message)
        end
        @test_throws ParseError read_ir_json(fix("golden/bif_asia.bnir.json"); max_states=1)
        # the limits are positive integers
        @test_throws ArgumentError read_network(fix("bif/asia.bif"); max_states=0)
        @test_throws ArgumentError read_network(fix("bif/asia.bif"); max_table_cells=-1)
        @test_throws TypeError read_network(fix("bif/asia.bif"); max_states=1.5)
    end

    @testset "nesting depth" begin
        caught(f) =
            try
                f()
                nothing
            catch err
                err
            end
        # The Netica and HUGIN parsers recurse once per bracket, and 100 000 levels, 200 KB,
        # overflowed the stack (`StackOverflowError`). The brackets are counted before
        # parsing; 512 levels are allowed, far above the 7 of the deepest real file.
        dne(k) = "bnet t {\nnode A {\n\tkind = NATURE;\n\tdiscrete = TRUE;\n" *
                 "\tstates = (a, b);\n\tparents = ();\n\tprobs = " * "("^k * "0.5, 0.5" *
                 ")"^k * ";\n\t};\n};\n"
        net(k) = "net { }\nnode A { states = (\"a\" \"b\"); }\n" *
                 "potential (A) { data = " * "("^k * "0.5 0.5" * ")"^k * "; }\n"
        # two blocks enclose the Netica list, and one the HUGIN list
        @test variable(parse_string(dne(510), NeticaDNE()), :A).table == [0.5, 0.5]
        @test variable(parse_string(net(511), HuginNET()), :A).table == [0.5, 0.5]
        blocks = "bnet t {" * " a {"^100_000 * " }"^100_000 * " };"
        for (src, fmt) in ((dne(511), NeticaDNE()), (net(512), HuginNET()),
                           (dne(100_000), NeticaDNE()), (net(100_000), HuginNET()),
                           (blocks, NeticaDNE()))
            e = caught(() -> parse_string(src, fmt))
            @test e isa ParseError
            @test occursin("brackets nest more than 512 levels deep", e.message)
        end
        # BIF and DSC never recurse, so deep brackets are just tokens to them, and GeNIe
        # stops at libxml2's limit of 256 elements
        deep = "("^100_000 * ")"^100_000
        @test parse_string("network x { property $(deep); }\n", BIF()) isa NetworkIR
        @test parse_string("belief network \"x\"\nnode A { type : discrete [ 2 ] = { a, b }; " *
                           "extra = $(deep); }\n", DSC()) isa NetworkIR
        xdsl = "<?xml version=\"1.0\"?>\n<smile version=\"1.0\" id=\"x\"><nodes>" *
               "<cpt id=\"A\"><state id=\"a\"/><state id=\"b\"/>" * "<x>"^100_000 *
               "</x>"^100_000 *
               "<probabilities>0.5 0.5</probabilities></cpt></nodes></smile>\n"
        @test_throws ParseError parse_string(xdsl, GeNIeXDSL())
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
        # 2^32 * 2^32 wrapped to 0, so no values matched, and `reshape` raised `ArgumentError`
        bad(t -> "{\"format\": \"bnir\", \"variables\": [{\"id\": \"A\", \"kind\": \"chance\", " *
                 "\"states\": [\"a\", \"b\"], \"parents\": [], \"table\": " *
                 "{\"dims\": [4294967296, 4294967296], \"values\": []}}]}")
        # A document whose whole text is a path is not JSON. JSON3 reads a short `String`
        # that names an existing file as that file, so this returned the asia network, and a
        # path to any other file put that file's first bytes in the error message.
        mktempdir() do dir
            doc = joinpath(dir, "path.bnir.json")
            write(doc, fix("golden/bif_asia.bnir.json"))
            @test_throws ParseError read_network(doc)
            @test_throws ParseError read_ir_json(IOBuffer(fix("golden/bif_asia.bnir.json")))
            secret = joinpath(dir, "secret.txt")
            write(secret, "SECRET CONTENT")
            write(doc, secret)
            e = try
                read_network(doc)
                nothing
            catch err
                err
            end
            @test e isa ParseError
            @test !occursin("SECRET", e.message)
        end
        # 10 000 nested brackets, 20 KB, overflowed JSON3's recursive parser; the depth is
        # checked before parsing
        @test_throws ParseError read_ir_json(IOBuffer("["^10_000 * "]"^10_000))
        # Only JSON3's report of text that is not JSON becomes a `ParseError`. An interrupt
        # while parsing became one too; it and any other exception now propagate.
        parse_json = BayesianNetworkFormats._json_parse
        @test_throws InterruptException parse_json(b -> throw(InterruptException()),
                                                   UInt8[],
                                                   "x")
        @test_throws OutOfMemoryError parse_json(b -> throw(OutOfMemoryError()), UInt8[],
                                                 "x")
        @test_throws ParseError parse_json(b -> throw(ArgumentError("not JSON")), UInt8[],
                                           "x")
    end
end
