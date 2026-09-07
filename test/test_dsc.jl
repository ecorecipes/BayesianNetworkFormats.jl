@testset "DSC" begin
    ir = read_network(fix("dsc/asia.dsc"))
    @test ir.format == :dsc
    @test ir.name == "unknown"
    @test isequivalent(ir, golden("dsc_asia.bnir.json"))
    d = variable(ir, :dysp)
    @test d.parents == [:bronc, :either]
    @test d.table[2, 1, :] == [0.7, 0.3]            # (1, 0) : 0.7, 0.3
    @test d.table[1, 2, :] == [0.8, 0.2]            # (0, 1) : 0.8, 0.2
    @test marginal(ir, :dysp) ≈ [0.4360, 0.5640] atol = 1e-4
    @test isequivalent(ir, read_network(fix("bif/asia.bif")))
    hab = read_network(fix("dsc/habitat_reference.dsc"))
    @test isequivalent(hab, golden("dsc_habitat_reference.bnir.json"))
    @test isequivalent(hab, habitat_reference_ir(); titles=false, positions=false,
                       comments=false, extras=false)
    # rows in arbitrary order, extra attributes, names and positions
    src = """
    belief network "demo"
    node A {
      type : discrete [ 2 ] = { "a", "b" };
      name : "The A node";
      position : (10, 20);
      colour : 3;
    }
    node B { type : discrete [ 2 ] = { "x", "y" }; }
    probability ( A ) { 0.25, 0.75; }
    probability ( B | A ) {
      (1) : 0.1, 0.9;
      (0) : 0.6, 0.4;
    }
    """
    ir2 = parse_string(src, DSC())
    @test variable(ir2, :A).title == "The A node"
    @test variable(ir2, :A).position == (10.0, 20.0)
    @test variable(ir2, :B).table == [0.6 0.4; 0.1 0.9]
    @test_throws ParseError parse_string(replace(src, "(0) : 0.6, 0.4;" => ""), DSC())
    @test_throws ParseError parse_string(replace(src, "(1) :" => "(2) :"), DSC())
end
