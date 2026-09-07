@testset "HUGIN .net" begin
    @testset "bnlearn asia" begin
        ir = read_network(fix("net/asia.net"))
        @test ir.format == :net
        @test isequivalent(ir, golden("net_asia.bnir.json"))
        d = variable(ir, :dysp)
        @test d.parents == [:bronc, :either]
        # data = (((0.9 0.1)(0.8 0.2))((0.7 0.3)(0.1 0.9))): outer = bronc, inner = either
        @test d.table[1, 1, :] == [0.9, 0.1]
        @test d.table[1, 2, :] == [0.8, 0.2]
        @test d.table[2, 1, :] == [0.7, 0.3]
        @test marginal(ir, :dysp) ≈ [0.4360, 0.5640] atol = 1e-4
    end

    @testset "habitat reference and influence diagrams" begin
        ir = read_network(fix("net/habitat_reference.net"))
        @test isequivalent(ir, golden("net_habitat_reference.bnir.json"))
        @test isequivalent(ir, habitat_reference_ir(); extras=false)
        @test variable(ir, :SoilMoisture).title == "Soil moisture"
        @test variable(ir, :SoilMoisture).position == (200.0, 150.0)
        gr = read_network(fix("net/grazing_reference_id.net"))
        @test isequivalent(gr, golden("net_grazing_reference_id.bnir.json"))
        @test isequivalent(gr, grazing_reference_ir(); mau=false, extras=false)
        @test variable(gr, :GrazingManagement).kind == DecisionNode
        @test variable(gr, :GrazingManagement).parents ==
              [:ClimateForecast, :CurrentVegetation]
        @test variable(gr, :ConservationBenefit).table == [0.0, 100.0]
        um = read_network(fix("net/umbrella.net"))
        @test isequivalent(um, golden("net_umbrella.bnir.json"))
        @test isequivalent(um, umbrella_ir())
    end

    @testset "grammar corners and unsupported nodes" begin
        src = """
        net { node_size = (80 40); }
        node A { states = (yes no); label = "A label"; }   % unquoted states, comment
        node B { states = ("1" "2"); }
        potential (A) { data = (0.3 0.7); }
        potential (B | A) { data = ((0.5 0.5) (0.2 0.8)); }
        """
        ir = parse_string(src, HuginNET())
        @test variable(ir, :A).states == ["yes", "no"]
        @test variable(ir, :A).title == "A label"
        @test variable(ir, :B).title == "B"
        @test variable(ir, :B).table[2, :] == [0.2, 0.8]
        @test ir.name == ""
        cont = src *
               "continuous node C { }\npotential (C | A) { data = (normal(0, 1) normal(1, 2)); }\n"
        e = try
            parse_string(cont, HuginNET())
            nothing
        catch err
            err
        end
        @test e isa UnsupportedNodeError
        @test e.id == "C" && e.nodetype == "continuous node"
        ir2 = parse_string(cont, HuginNET(); strict=false)
        @test [v.id for v in ir2.variables] == [:A, :B]
        @test ir2.extras[:skipped][1]["id"] == "C"
        @test_throws ParseError parse_string("node A { states = (yes no) }\npotential (A B) { }",
                                             HuginNET())
        @test_throws ParseError parse_string("node A { states = (yes no); }\npotential (A | Z) { }",
                                             HuginNET())
        @test_throws ParseError parse_string("node A { states = (yes no); ", HuginNET())
    end

    @testset "discrete node and a utility without parents" begin
        # HUGIN's long form `discrete node X` is the same as `node X`
        src = """
        net { name = "d"; }
        discrete node A { states = ("yes" "no"); }
        decision D { states = ("go" "stay"); }
        utility U0 { }
        utility U { }
        potential (A) { data = (0.25 0.75); }
        potential (U0) { data = (7.5); }
        potential (U | A D) { data = ((1 2) (3 4)); }
        """
        ir = parse_string(src, HuginNET())
        @test ir.name == "d"
        @test variable(ir, :A).kind == ChanceNode
        @test variable(ir, :A).states == ["yes", "no"]
        @test variable(ir, :A).table == [0.25, 0.75]
        u0 = variable(ir, :U0)
        @test u0.kind == UtilityNode && isempty(u0.parents)
        @test u0.table == fill(7.5)                     # a 0-dimensional utility
        @test variable(ir, :U).table == [1.0 2.0; 3.0 4.0]
        # the writer emits `data = (7.5);` for the parentless utility and reads back
        out = write_string(ir, HuginNET())
        @test occursin("data = (7.5);", out)
        @test occursin("discrete", out) == false        # the writer uses the short form
        back = parse_string(out, HuginNET())
        @test isequivalent(back, ir; name=false, deterministic=false)
    end
end
