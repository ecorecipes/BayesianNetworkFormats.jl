@testset "Netica .dne" begin
    @testset "habitat reference (nested and flat probs)" begin
        ir = read_network(fix("dne/habitat_reference.dne"))
        @test ir.format == :dne
        @test isequivalent(ir, golden("dne_habitat_reference.bnir.json"))
        @test isequivalent(ir, habitat_reference_ir(); extras=false)
        @test ir.extras[:comment] ==
              "SPEC section 45 reference ecological Bayesian network."
        flat = read_network(fix("dne/habitat_reference_flat.dne"))
        @test isequivalent(flat, ir)
        @test isequivalent(flat, golden("dne_habitat_reference_flat.bnir.json"))
        sm = variable(ir, :SoilMoisture)
        @test sm.parents == [:Climate, :Irrigation]
        @test sm.table[1, 2, :] == [0.3, 0.5, 0.2]      # dry, high
        @test sm.table[3, 1, :] == [0.1, 0.4, 0.5]      # wet, low
        @test variable(ir, :Climate).position == (100.0, 60.0)
        @test variable(ir, :Climate).comment == "Regional climate regime."
    end

    @testset "DETERMIN functable, @imposs, CONSTANT nodes" begin
        ir = read_network(fix("dne/determin_functable.dne"))
        @test isequivalent(ir, golden("dne_determin_functable.bnir.json"))
        @test [v.id for v in ir.variables] == [:A, :B, :C, :D]
        c = variable(ir, :C)
        @test c.deterministic
        @test c.title == "Deterministic combination"
        @test size(c.table) == (2, 3, 2)
        @test c.table[1, 1, :] == [1.0, 0.0]     # a1, b1 -> low
        @test c.table[1, 3, :] == [0.0, 1.0]     # a1, b3 -> high
        @test c.table[2, 2, :] == [0.0, 1.0]     # a2, b2 -> high
        @test variable(ir, :D).table[2, :] == [0.0, 1.0]   # @imposs -> 0
        @test ir.extras[:skipped][1]["id"] == "TITLE1"
        @test ir.extras[:skipped][1]["type"] == "CONSTANT"
        rt = roundtrip(ir, NeticaDNE())
        @test isequivalent(rt, ir; extras=false)
        @test variable(rt, :C).deterministic
        @test occursin("functable", write_string(ir, NeticaDNE()))
    end

    @testset "levels, continuation strings, positions" begin
        ir = read_network(fix("dne/levels_continuous.dne"))
        @test isequivalent(ir, golden("dne_levels_continuous.bnir.json"))
        t = variable(ir, :Temperature)
        @test t.states == ["< 10", "10 to 20", ">= 20"]
        @test t.extras[:levels] == [-Inf, 10.0, 20.0, Inf]
        @test t.comment ==
              "A continuous node discretised\ninto three intervals with a \"quoted\" word."
        @test t.position == (120.0, 60.0)
        @test variable(ir, :Activity).table[3, :] == [0.1, 0.9]
        rt = roundtrip(ir, NeticaDNE())
        @test isequivalent(rt, ir)
        @test occursin("levels = (-INFINITY, 10, 20, INFINITY)",
                       write_string(ir, NeticaDNE()))
    end

    @testset "continuous node with both states and levels" begin
        # Regression for the writer emitting `levels` instead of `states`, which renamed
        # the states to the interval labels on the next read.
        ir = read_network(fix("dne/levels_named_states.dne"))
        @test isequivalent(ir, golden("dne_levels_named_states.bnir.json"))
        r = variable(ir, :Rainfall)
        @test r.states == ["Dry", "Normal", "Wet"]
        @test r.extras[:levels] == [0.0, 50.0, 150.0, Inf]
        @test marginal(ir, :Growth) ≈ [0.5, 0.5]
        out = write_string(ir, NeticaDNE())
        @test occursin("states = (Dry, Normal, Wet);", out)
        @test occursin("levels = (0, 50, 150, INFINITY);", out)
        rt = roundtrip(ir, NeticaDNE())
        @test variable(rt, :Rainfall).states == ["Dry", "Normal", "Wet"]
        @test isempty(differences(rt, ir; source=false))
        # a continuous node whose states are the derived interval labels still writes
        # `levels` alone
        lv = read_network(fix("dne/levels_continuous.dne"))
        text = write_string(lv, NeticaDNE())
        @test !occursin("states = (_lt_10", text)
        @test isequivalent(parse_string(text, NeticaDNE()), lv; extras=false)
    end

    @testset "CONSTANT parent" begin
        # A Netica CONSTANT node used as a parent is a node of the network, so the old
        # "is not a node of the network" ParseError was false.
        src = """
        bnet constparent {
        node K {
        \tkind = CONSTANT;
        \tdiscrete = TRUE;
        \tstates = (x);
        \tparents = ();
        \t};
        node A {
        \tkind = NATURE;
        \tdiscrete = TRUE;
        \tstates = (yes, no);
        \tparents = (K);
        \tprobs = ((0.5, 0.5));
        \t};
        };
        """
        e = try
            parse_string(src, NeticaDNE())
            nothing
        catch err
            err
        end
        @test e isa UnsupportedNodeError
        @test e.id == "K" && e.nodetype == "CONSTANT" && e.format == :dne
        @test occursin("parent of A", sprint(showerror, e))
        ir = parse_string(src, NeticaDNE(); strict=false)
        @test isempty(ir.variables)
        skipped = ir.extras[:skipped]
        @test skipped[1]["id"] == "K" && skipped[1]["type"] == "CONSTANT"
        @test skipped[2]["id"] == "A" &&
              skipped[2]["reason"] == "parent K is a CONSTANT node"
        # a parent that really is absent still raises ParseError
        absent = "bnet x { node A { kind = NATURE; states = (a, b); parents = (Z); probs = ((0.5, 0.5)); }; };"
        @test_throws ParseError parse_string(absent, NeticaDNE())
        lenient = parse_string(absent, NeticaDNE(); strict=false)
        @test lenient.extras[:skipped][1]["reason"] ==
              "parent Z is not a node of the network"
    end

    @testset "numeric state names and numeric functable entries" begin
        # `states = (0, 1)` gives "0"/"1", as BIF, DSC and HUGIN do, not "0.0"/"1.0"
        src = "bnet num { node S { kind = NATURE; states = (0, 1); parents = (); probs = (0.5, 0.5); }; };"
        @test variable(parse_string(src, NeticaDNE()), :S).states == ["0", "1"]
        # a DETERMIN functable of a continuous node names its states by a value inside
        # the interval
        flow = """
        bnet flow {
        node Season {
        \tkind = NATURE;
        \tdiscrete = TRUE;
        \tstates = (dry, mid, wet);
        \tparents = ();
        \tprobs = (0.2, 0.3, 0.5);
        \t};
        node Flow {
        \tkind = NATURE;
        \tdiscrete = FALSE;
        \tchance = DETERMIN;
        \tlevels = (0, 10, 20, INFINITY);
        \tparents = (Season);
        \tfunctable = (5, 15, 25);
        \t};
        };
        """
        ir = parse_string(flow, NeticaDNE())
        f = variable(ir, :Flow)
        @test f.states == ["0 to 10", "10 to 20", ">= 20"]
        @test f.deterministic
        @test f.table[1, :] == [1.0, 0.0, 0.0]
        @test f.table[3, :] == [0.0, 0.0, 1.0]
        @test marginal(ir, :Flow) ≈ [0.2, 0.3, 0.5]
        # a value outside every interval is an error
        @test_throws ParseError parse_string(replace(flow, "(5, 15, 25)" => "(5, 15, -1)"),
                                             NeticaDNE())
    end

    @testset "influence diagrams" begin
        um = read_network(fix("dne/umbrella.dne"))
        @test isequivalent(um, golden("dne_umbrella.bnir.json"))
        @test isequivalent(um, umbrella_ir())
        u = variable(um, :U)
        @test u.kind == UtilityNode && u.parents == [:Weather, :Umbrella]
        @test u.table == [20.0 100.0; 70.0 0.0]
        d = variable(um, :Umbrella)
        @test d.kind == DecisionNode && d.parents == [:Forecast] && d.table === nothing
        gr = read_network(fix("dne/grazing_reference_id.dne"))
        @test isequivalent(gr, golden("dne_grazing_reference_id.bnir.json"))
        @test isequivalent(gr, grazing_reference_ir(); mau=false, extras=false)
        @test isempty(gr.mau)
        @test variable(gr, :Climate).title == "Climate"        # titles default to the id
        @test variable(gr, :ManagementCost).table == [-40.0, -15.0, 0.0]
    end

    @testset "state-index literals, discrete levels, statetitles" begin
        ir = read_network(fix("dne/state_index_literals.dne"))
        @test isequivalent(ir, golden("dne_state_index_literals.bnir.json"))
        @test [v.id for v in ir.variables] ==
              [:Season, :Year, :SeasonCode, :Rainfall, :Growth, :Plant, :Reward]
        season = variable(ir, :Season)
        @test season.states == ["spring", "summer", "autumn"]
        @test season.extras[:state_values] == [0.0, 1.0, 2.0]     # discrete levels
        @test season.extras[:evidence] == "summer"                # evidence = #1
        @test !haskey(season.extras, :levels)
        year = variable(ir, :Year)
        @test year.states == ["Year 1", "Year 5"]                 # statetitles + levels
        @test year.extras[:state_values] == [1.0, 5.0]
        @test year.table == [0.0, 1.0]                            # probs = (#1)
        @test year.extras[:evidence] == "Year 5"
        code = variable(ir, :SeasonCode)
        @test code.deterministic && code.table == [1.0 0.0 0.0; 0.0 1.0 0.0; 0.0 0.0 1.0]
        rain = variable(ir, :Rainfall)
        @test rain.states == ["0 to 100", "100 to 200", ">= 200"]
        @test rain.extras[:levels] == [0.0, 100.0, 200.0, Inf]
        @test rain.deterministic
        @test rain.table == [1.0 0.0 0.0; 0.0 0.0 1.0; 0.0 1.0 0.0]   # functable = (#0, #2, #1)
        @test rain.extras[:evidence] == "0 to 100"
        growth = variable(ir, :Growth)
        @test size(growth.table) == (3, 2, 2)
        @test growth.table[1, 1, :] == [0.6, 0.4]
        @test growth.table[1, 2, :] == [1.0, 0.0]                  # (#0) as a row
        @test growth.table[2, 2, :] == [0.0, 1.0]                  # (#1) as a row
        @test growth.table[3, 2, :] == [0.3, 0.7]
        @test !growth.deterministic
        plant = variable(ir, :Plant)
        @test plant.kind == DecisionNode && plant.states == ["Do nothing", "Plant trees"]
        @test plant.extras[:evidence] == "Plant trees"
        @test variable(ir, :Reward).table == [0.0 -10.0; 50.0 40.0]
        @test validate(ir) === ir
        # Round trip: state values, evidence and index-named functables survive; state
        # names that are not identifiers are sanitised.
        rt = roundtrip(ir, NeticaDNE())
        out = write_string(ir, NeticaDNE())
        @test occursin("functable", out) && occursin(r"\(#0,\s+#2,\s+#1\);", out)
        @test occursin("evidence = #0;", out) && occursin("evidence = summer;", out)
        @test occursin("states = (spring, summer, autumn);\n\tlevels = (0, 1, 2);", out)
        for v in (season, rain, growth, code)
            w = variable(rt, v.id)
            @test w.states == v.states && w.parents == v.parents && w.table == v.table
            @test w.deterministic == v.deterministic && w.extras == v.extras
        end
        @test variable(rt, :Year).states == ["Year_1", "Year_5"]
        @test variable(rt, :Year).extras[:state_values] == [1.0, 5.0]
        @test variable(rt, :Year).extras[:evidence] == "Year_5"
        @test variable(rt, :Plant).extras[:evidence] == "Plant_trees"
        # Out-of-range and misplaced literals are reported.
        bad = replace(read(fix("dne/state_index_literals.dne"), String),
                      "evidence = #1;\n\tbelief" => "evidence = #3;\n\tbelief")
        e = try
            parse_string(bad, NeticaDNE())
        catch err
            err
        end
        @test e isa ParseError && occursin("#3", e.message) && occursin("Season", e.message)
        bad = replace(read(fix("dne/state_index_literals.dne"), String),
                      "functable = (0, -10, 50, 40)" => "functable = (0, #1, 50, 40)")
        @test_throws ParseError parse_string(bad, NeticaDNE())
        bad = replace(read(fix("dne/state_index_literals.dne"), String),
                      "levels = (0, 1, 2);\n\tkind = NATURE;\n\tparents = ();" => "levels = (0, 1);\n\tkind = NATURE;\n\tparents = ();")
        @test_throws ParseError parse_string(bad, NeticaDNE())
    end

    @testset "empty list entries (inputs, statetitles)" begin
        ir = read_network(fix("dne/empty_list_entries.dne"))
        @test isequivalent(ir, golden("dne_empty_list_entries.bnir.json"))
        @test [v.id for v in ir.variables] == [:Weather, :Season, :Phase, :Trend, :Growth]
        # An empty `statetitles` entry falls back to the state id, and holds its position.
        @test variable(ir, :Season).states == ["s0", "Summer", "Autumn"]
        @test variable(ir, :Phase).states == ["Early", "s1", "Late"]
        @test variable(ir, :Season).table == [0.5, 0.25, 0.25]
        @test variable(ir, :Phase).table == [0.2, 0.3, 0.5]
        # `states` names the states; the empty titles beside them are display-only.
        trend = variable(ir, :Trend)
        @test trend.states == ["increased", "same_as_now", "decreased"]
        @test trend.table[1, :] == [0.5, 0.3, 0.2]
        @test trend.table[2, :] == [0.1, 0.4, 0.5]
        # An empty `inputs` slot leaves the parent order (and so the table axes) alone.
        growth = variable(ir, :Growth)
        @test growth.parents == [:Season, :Weather]
        @test growth.extras[:inputs] == ["", "Weather"]
        @test size(growth.table) == (3, 2, 2)
        @test growth.table[1, 1, :] == [0.9, 0.1]     # s0, sunny
        @test growth.table[2, 1, :] == [0.7, 0.3]     # Summer, sunny
        @test growth.table[3, 2, :] == [0.4, 0.6]     # Autumn, rainy
        @test validate(ir) === ir
        # Round trip: the unnamed input slot is written back as the empty entry.
        out = write_string(ir, NeticaDNE())
        @test occursin("inputs = (, Weather);", out)
        rt = roundtrip(ir, NeticaDNE())
        @test isequivalent(rt, ir)
        @test variable(rt, :Growth).extras[:inputs] == ["", "Weather"]
        @test variable(rt, :Season).states == ["s0", "Summer", "Autumn"]
        # `()` is still the empty list, and a trailing comma is not an entry.
        src = read(fix("dne/empty_list_entries.dne"), String)
        @test isempty(variable(ir, :Weather).parents)
        @test variable(parse_string(replace(src,
                                            "states = (sunny, rainy);" => "states = (sunny, rainy, );"),
                                    NeticaDNE()),
                       :Weather).states == ["sunny", "rainy"]
        # Constructs an empty entry cannot stand for are named, not guessed.
        bad = replace(src,
                      "states = (increased, same_as_now, decreased);" => "states = (increased, , decreased);")
        e = try
            parse_string(bad, NeticaDNE())
        catch err
            err
        end
        @test e isa UnsupportedNodeError && e.nodetype == "state with no name" &&
              occursin("Trend", e.message)
        @test parse_string(bad, NeticaDNE(); strict=false).extras[:skipped][1]["reason"] ==
              "empty entry in states"
        e = try
            parse_string(replace(src,
                                 "parents = (Season, Weather);" => "parents = (, Weather);"),
                         NeticaDNE())
        catch err
            err
        end
        @test e isa UnsupportedNodeError && e.nodetype == "parent slot with no node" &&
              occursin("Growth", e.message)
        bad = replace(src, "inputs = (, Weather);" => "inputs = (, Weather, Season);")
        e = try
            parse_string(bad, NeticaDNE())
        catch err
            err
        end
        @test e isa ParseError && occursin("inputs of node Growth", e.message)
    end

    @testset "BNMA decision networks (EcologicalBayesianNetworks models)" begin
        models = normpath(joinpath(@__DIR__, "..", "..", "EcologicalBayesianNetworks.jl",
                                   "models"))
        files = [("song_sparrow_bdn", "SongSparrowBDN_v250804.dne", 12, 15, 7),
                 ("brown_trout_bdn", "BrownTroutBDN_v250804.dne", 9, 13, 6)]
        for (dir, name, nnodes, narcs, nskipped) in files
            path = joinpath(models, dir, name)
            if !isfile(path)
                @info "skipping $(name): $(path) not found"
                continue
            end
            ir = read_network(path)
            @test ir.format == :dne
            @test length(ir.variables) == nnodes
            @test sum(length(v.parents) for v in ir.variables) == narcs
            @test length(ir.extras[:skipped]) == nskipped
            @test all(d["type"] == "CONSTANT" for d in ir.extras[:skipped])
            # Finding nodes (evidence without probs) have no table.
            @test_throws ValidationError validate(ir)
            @test validate(ir; allow_missing_tables=true) === ir
            @test any(haskey(v.extras, :evidence) for v in ir.variables)
            @test any(v.kind == DecisionNode for v in ir.variables)
        end
        if isfile(joinpath(models, files[1][1], files[1][2]))
            ir = read_network(joinpath(models, files[1][1], files[1][2]))
            t = variable(ir, :Time)
            @test t.states ==
                  ["Year 1", "Year 5", "Year 10", "Year 15", "Year 20", "Year 30"]
            @test t.extras[:state_values] == [1.0, 5.0, 10.0, 15.0, 20.0, 30.0]
            @test t.extras[:evidence] == "Year 5"
            @test size(variable(ir, :RiparianHabitatQuality).table) == (4, 2, 6, 3)
            @test variable(ir, :RiparianPlantCost_infl_adj).extras[:evidence] == "0 to 2.5"
            @test count(v.kind == UtilityNode for v in ir.variables) == 2
        end
        if isfile(joinpath(models, files[2][1], files[2][2]))
            ir = read_network(joinpath(models, files[2][1], files[2][2]))
            d = variable(ir, :InHabRest)
            @test d.kind == DecisionNode && d.states == ["Not implement", "Implement"]
            @test d.extras[:evidence] == "Implement"
        end
    end

    @testset "real-world grammar features" begin
        src = """
        // ~->[DNET-1]->~
        // File created by Netica 5.00 on Feb 12, 2011.
        bnet demo {
        AutoCompile = TRUE;
        whenchanged = 1297537675;
        visual V1 {
        \tdefdispform = BELIEFBARS;
        \tnodefont = font {shape= "Arial"; size= 9;};
        \tNodeSet Node {BuiltIn = 1; Color = 0xc0c0c0;};
        \tPrinterSetting A {
        \t\tmargins = (1270, 1270, 1270, 1270);
        \t\t};
        \t};
        node P1 {
        \tkind = NATURE;
        \tdiscrete = TRUE;
        \tstates = (High, Low);
        \tparents = ();
        \tbelief = (0.5, 0.5);
        \tvisual V1 {
        \t\tcenter = (112, 192);
        \t\tlink 1 {
        \t\t\tpath = ((190, 147), (157, 166));
        \t\t\t};
        \t\t};
        \t};
        node Dec1 {
        \tkind = DECISION;
        \tdiscrete = TRUE;
        \tchance = DETERMIN;
        \tstates = (Choice_1, Choice_2);
        \tparents = (P1);
        \tfunctable = (Choice_1, Choice_2);
        \t};
        node Unnamed {
        \tkind = NATURE;
        \tdiscrete = TRUE;
        \tnumstates = 3;
        \tparents = ();
        \t};
        };
        """
        ir = parse_string(src, NeticaDNE())
        @test ir.name == "demo"
        @test variable(ir, :P1).table === nothing             # structure only
        @test variable(ir, :P1).position == (112.0, 192.0)
        @test variable(ir, :Dec1).kind == DecisionNode
        @test variable(ir, :Unnamed).states == ["s0", "s1", "s2"]
        @test_throws ValidationError validate(ir)                # missing tables
        @test validate(ir; allow_missing_tables=true) === ir
        out = write_string(ir, NeticaDNE())
        @test occursin("node P1 {", out) && !occursin("probs", out)
    end
end
