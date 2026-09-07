@testset "BIF" begin
    @testset "bnlearn asia (row form)" begin
        ir = read_network(fix("bif/asia.bif"))
        @test ir.format == :bif
        @test ir.name == "unknown"
        @test isequivalent(ir, golden("bif_asia.bnir.json"))
        @test [v.id for v in ir.variables] ==
              [:asia, :tub, :smoke, :lung, :bronc, :either, :xray, :dysp]
        e = variable(ir, :either)
        @test e.parents == [:lung, :tub]
        @test e.table[2, 2, :] == [0.0, 1.0]        # (no, no)
        @test e.table[1, 2, :] == [1.0, 0.0]        # (yes, no)
        d = variable(ir, :dysp)
        @test d.table[2, 1, :] == [0.7, 0.3]        # (no, yes): bronc = no, either = yes
        @test marginal(ir, :dysp) ≈ [0.4360, 0.5640] atol = 1e-4
        @test marginal(ir, :either) ≈ [0.0648, 0.9352] atol = 1e-4
    end

    @testset "table form (pgmpy style) and properties" begin
        ir = read_network(fix("bif/sprinkler_table.bif"))
        @test isequivalent(ir, golden("bif_sprinkler_table.bnir.json"))
        @test isequivalent(ir, sprinkler_ir())
        g = variable(ir, :Grass)
        @test g.parents == [:Sprinkler, :Rain]
        @test g.table[1, 1, :] == [0.99, 0.01]      # on, yes
        @test g.table[2, 1, :] == [0.8, 0.2]        # off, yes
        @test g.table[2, 2, :] == [0.0, 1.0]        # off, no
        @test variable(ir, :Sprinkler).table == [0.01 0.99; 0.4 0.6]
        @test variable(ir, :Rain).position == (100.0, 50.0)
        @test variable(ir, :Rain).extras[:properties] == ["weight = 0.5"]
        out = write_string(ir, BIF())
        @test occursin("property weight = 0.5;", out)
        @test occursin("property position = (100, 50) ;", out)
        @test isequivalent(parse_string(out, BIF()), ir)
    end

    @testset "quoted names, default rows, network properties" begin
        src = """
        network "My net" {
          property author = someone ;
        }
        variable "Soil moisture" {
          type discrete [ 2 ] { "very low", high };
        }
        variable X { type discrete [ 2 ] { 1st, 2nd }; }
        probability ( "Soil moisture" ) { table 0.3 0.7; }
        probability ( X | "Soil moisture" ) {
          ("very low") 0.9, 0.1;
          default 0.5, 0.5;
        }
        """
        ir = parse_string(src, BIF())
        @test ir.name == "My net"
        @test ir.extras[:properties] == ["author = someone"]
        sm = variable(ir, Symbol("Soil moisture"))
        @test sm.states == ["very low", "high"]
        x = variable(ir, :X)
        @test x.states == ["1st", "2nd"]
        @test x.table == [0.9 0.1; 0.5 0.5]
        out = write_string(ir, BIF())
        @test occursin("variable \"Soil moisture\"", out)
        @test occursin("(\"very low\") 0.9, 0.1;", out)
        @test isequivalent(parse_string(out, BIF()), ir)
        @test_throws ParseError parse_string(replace(src, "default 0.5, 0.5;" => ""), BIF())
        @test_throws ParseError parse_string("variable A { type discrete [ 3 ] { a, b }; }",
                                             BIF())
        @test_throws ParseError parse_string("probability ( Z ) { table 1; }", BIF())
    end
end
