@testset "GeNIe .xdsl" begin
    @testset "habitat reference" begin
        ir = read_network(fix("xdsl/habitat_reference.xdsl"))
        @test ir.format == :xdsl
        @test isequivalent(ir, golden("xdsl_habitat_reference.bnir.json"))
        @test isequivalent(ir, habitat_reference_ir(); extras=false)
        sm = variable(ir, :SoilMoisture)
        @test sm.table[1, 2, :] == [0.3, 0.5, 0.2]
        @test variable(ir, :Climate).position == (100.0, 60.0)   # centre of x1 y1 x2 y2
        @test variable(ir, :Climate).comment == "Regional climate regime."
    end

    @testset "Habitat_Suitability.xdsl written by GeNIe" begin
        # An external witness for the XDSL table layout: BNMA record 132, written by
        # GeNIe 2.0 (CC BY 4.0; see fixtures/LICENSES.md). Only the child-fastest
        # row-major reading of <probabilities> normalises, so reading it at all pins the
        # layout against a file this package did not write.
        ir = read_network(fix("xdsl/Habitat_Suitability.xdsl"))
        @test ir.format == :xdsl
        @test isequivalent(ir, golden("xdsl_Habitat_Suitability.bnir.json"))
        @test ir.name == "Network1"
        @test length(ir.variables) == 11
        @test variable(ir, :TerrainTypes).states ==
              ["Jungle", "Mountains", "Desert", "Savanna"]
        # <probabilities>0.2 0.8 0.6 0.4 0.3 0.7 0.1 0.9</probabilities> for
        # Temperature | TerrainTypes: one row of two per terrain type
        temp = variable(ir, :Temperature)
        @test temp.parents == [:TerrainTypes]
        @test temp.table == [0.2 0.8; 0.6 0.4; 0.3 0.7; 0.1 0.9]
        @test variable(ir, :PreyNumbers).table[1, :] == [0.1, 0.3, 0.6]
        @test size(variable(ir, :Abiotic).table) == (2, 2, 2, 2)
        @test variable(ir, :Habitat_Suitability).parents ==
              [:Abiotic, :Biotic, :PreyNumbers, :MateNumbers]
        @test marginal(ir, :Habitat_Suitability) ≈ [0.91878, 0.08122] atol = 1e-5
        # the <genie> extension block carries the layout
        @test variable(ir, :TerrainTypes).position == (510.0, 88.5)
        @test isequivalent(roundtrip(ir, GeNIeXDSL()), ir; extras=false)
    end

    @testset "submodel groups keep names, comments and positions" begin
        # GeNIe puts grouped nodes inside <submodel> elements, so the <genie> block has to
        # be searched recursively.
        src = """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <smile version="1.0" id="grouped" numsamples="10000">
          <nodes>
            <cpt id="A"><state id="a"/><state id="b"/><probabilities>0.4 0.6</probabilities></cpt>
          </nodes>
          <extensions>
            <genie version="1.0" name="Grouped network">
              <submodel id="group1">
                <node id="A">
                  <name>Node A</name>
                  <comment>inside a submodel</comment>
                  <position>10 20 30 40</position>
                </node>
              </submodel>
            </genie>
          </extensions>
        </smile>
        """
        ir = parse_string(src, GeNIeXDSL())
        @test ir.name == "Grouped network"
        @test variable(ir, :A).title == "Node A"
        @test variable(ir, :A).comment == "inside a submodel"
        @test variable(ir, :A).position == (20.0, 30.0)
    end

    @testset "equation node: strict vs non-strict" begin
        path = fix("xdsl/equation_node.xdsl")
        e = try
            read_network(path)
            nothing
        catch err
            err
        end
        @test e isa UnsupportedNodeError
        @test e.id == "Runoff" && e.nodetype == "equation" && e.format == :xdsl
        @test occursin("Runoff", sprint(showerror, e))
        ir = read_network(path; strict=false)
        @test isequivalent(ir, golden("xdsl_equation_node.bnir.json"))
        @test [v.id for v in ir.variables] == [:Rain, :Wet]
        sk = ir.extras[:skipped]
        @test [s["id"] for s in sk] == ["Runoff", "Flood"]
        @test sk[1]["type"] == "equation"
        @test occursin("Runoff", sk[2]["reason"])
        @test variable(ir, :Wet).title == "Wet ground"
        @test ir.name == "Equation example"
        @test validate(ir) === ir
    end

    @testset "influence diagram: decision, utility, mau" begin
        gr = read_network(fix("xdsl/grazing_reference_id.xdsl"))
        @test isequivalent(gr, golden("xdsl_grazing_reference_id.bnir.json"))
        @test isequivalent(gr, grazing_reference_ir(); extras=false)
        @test length(gr.mau) == 1
        @test gr.mau[1].id == :TotalUtility
        @test gr.mau[1].parents == [:ConservationBenefit, :ManagementCost]
        @test gr.mau[1].weights == [1.0, 1.0]
        um = read_network(fix("xdsl/umbrella.xdsl"))
        @test isequivalent(um, golden("xdsl_umbrella.bnir.json"))
        @test isequivalent(um, umbrella_ir())
        @test variable(um, :U).table == [20.0 100.0; 70.0 0.0]
    end

    @testset "deterministic nodes and properties" begin
        ir = read_network(fix("dne/determin_functable.dne"))
        out = write_string(ir, GeNIeXDSL())
        @test occursin("<deterministic id=\"C\">", out)
        @test occursin("<resultingstates>low low high low high high</resultingstates>", out)
        rt = parse_string(out, GeNIeXDSL())
        @test isequivalent(rt, ir; extras=false)
        @test variable(rt, :C).deterministic
        src = """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <smile version="1.0" id="props" numsamples="10000">
          <nodes>
            <cpt id="A"><state id="a"/><state id="b"/><probabilities>0.4 0.6</probabilities>
              <property id="literature">Some reference</property></cpt>
            <noisymax id="N"><state id="x"/><state id="y"/><parents>A</parents>
              <strengths>0 1</strengths><parameters>0.1 0.9 0.2 0.8 0 1</parameters></noisymax>
          </nodes>
        </smile>
        """
        @test_throws UnsupportedNodeError parse_string(src, GeNIeXDSL())
        ir2 = parse_string(src, GeNIeXDSL(); strict=false)
        @test ir2.name == "props"
        @test variable(ir2, :A).extras[:properties] ==
              Dict("literature" => "Some reference")
        @test ir2.extras[:skipped][1]["type"] == "noisymax"
        rt2 = parse_string(write_string(ir2, GeNIeXDSL()), GeNIeXDSL())
        @test variable(rt2, :A).extras[:properties] ==
              Dict("literature" => "Some reference")
        @test_throws ParseError parse_string("<smile><nodes><cpt/></nodes></smile>",
                                             GeNIeXDSL())
        @test_throws ParseError parse_string("<other/>", GeNIeXDSL())
        @test_throws ParseError parse_string("not xml", GeNIeXDSL())
    end
end
