@testset "IR" begin
    @testset "from_rowmajor / to_rowmajor" begin
        vals = [0.7, 0.2, 0.1, 0.15, 0.25, 0.6]
        t = from_rowmajor(vals, (2, 3))
        @test size(t) == (2, 3)
        @test t[1, :] == [0.7, 0.2, 0.1]
        @test t[2, :] == [0.15, 0.25, 0.6]
        @test to_rowmajor(t) == vals
        t3 = from_rowmajor(collect(1.0:12.0), (2, 3, 2))
        @test t3[1, 1, :] == [1.0, 2.0]
        @test t3[1, 2, :] == [3.0, 4.0]
        @test t3[2, 1, :] == [7.0, 8.0]
        @test to_rowmajor(t3) == collect(1.0:12.0)
        @test from_rowmajor([0.3, 0.7], (2,)) == [0.3, 0.7]
        @test from_rowmajor([5.0], ()) == fill(5.0)
        @test_throws ArgumentError from_rowmajor([1.0, 2.0, 3.0], (2, 2))
    end

    @testset "constructors and accessors" begin
        ir = habitat_reference_ir()
        @test length(ir.variables) == 7
        @test nstates(ir, :Climate) == 3
        @test variable(ir, "Occupancy").parents == [:HabitatQuality]
        @test_throws KeyError variable(ir, :Nope)
        @test [v.id for v in chance_nodes(ir)] == [v.id for v in ir.variables]
        @test isempty(decisions(ir)) && isempty(utilities(ir))
        @test !has_decisions(ir)
        gr = grazing_reference_ir()
        @test has_decisions(gr)
        @test [v.id for v in decisions(gr)] == [:GrazingManagement]
        @test [v.id for v in utilities(gr)] == [:ConservationBenefit, :ManagementCost]
        @test sprint(show, ir) == "NetworkIR(\"habitat_reference\": 7 chance; format=:ir)"
        @test occursin("1 decision, 2 utility", sprint(show, gr))
    end

    @testset "topological order" begin
        ir = habitat_reference_ir()
        order = topological_order(ir)
        pos = Dict(id => i for (i, id) in enumerate(order))
        for v in ir.variables, p in v.parents
            @test pos[p] < pos[v.id]
        end
        cyc = NetworkIR("cyc",
                        [IRVariable(:A; states=["a", "b"], parents=[:B],
                                    table=[0.5 0.5; 0.5 0.5]),
                         IRVariable(:B; states=["a", "b"], parents=[:A],
                                    table=[0.5 0.5; 0.5 0.5])])
        @test_throws ValidationError topological_order(cyc)
        @test_throws ValidationError validate(cyc)
    end

    @testset "validate" begin
        good = habitat_reference_ir()
        @test validate(good) === good
        @test validate(grazing_reference_ir()) isa NetworkIR
        dup = NetworkIR("d",
                        [IRVariable(:A; states=["a", "b"], table=[0.5, 0.5]),
                         IRVariable(:A; states=["a", "b"], table=[0.5, 0.5])])
        @test_throws ValidationError validate(dup)
        e = try
            validate(dup)
            nothing
        catch err
            err
        end
        @test e.id == :A && occursin("duplicate", e.message)
        missing_parent = NetworkIR("m",
                                   [IRVariable(:A; states=["a", "b"], parents=[:Z],
                                               table=[0.5 0.5; 0.5 0.5])])
        @test_throws ValidationError validate(missing_parent)
        wrong_size = NetworkIR("w",
                               [IRVariable(:A; states=["a", "b"], table=[0.5, 0.5]),
                                IRVariable(:B; states=["a", "b"], parents=[:A],
                                           table=[0.5, 0.5])])
        @test_throws ValidationError validate(wrong_size)
        bad_row = NetworkIR("n",
                            [IRVariable(:A; states=["a", "b"], table=[0.5, 0.5]),
                             IRVariable(:B; states=["a", "b"], parents=[:A],
                                        table=[0.2 0.2; 0.5 0.5])])
        err = try
            validate(bad_row)
            nothing
        catch e
            e
        end
        @test err isa NotNormalizedError
        @test err.id == :B && err.index == (1,) && err.total ≈ 0.4
        @test occursin("row (1,)", sprint(showerror, err))
        fixed = validate(bad_row; renormalize=true)
        @test variable(fixed, :B).table[1, :] ≈ [0.5, 0.5]
        @test variable(fixed, :B).table[2, :] == [0.5, 0.5]
        @test variable(bad_row, :B).table[1, :] == [0.2, 0.2]   # input untouched
        zero_row = NetworkIR("z", [IRVariable(:A; states=["a", "b"], table=[0.0, 0.0])])
        @test_throws NotNormalizedError validate(zero_row; renormalize=true)
        @test validate(bad_row; atol=0.7) === bad_row
        dec_table = NetworkIR("dt",
                              [IRVariable(:D; kind=DecisionNode, states=["x", "y"],
                                          table=[0.5, 0.5])])
        @test_throws ValidationError validate(dec_table)
        util_parent = NetworkIR("up",
                                [IRVariable(:U; kind=UtilityNode, table=fill(1.0)),
                                 IRVariable(:A; states=["a", "b"], parents=[:U],
                                            table=[0.5, 0.5])])
        @test_throws ValidationError validate(util_parent)
        util_states = NetworkIR("us",
                                [IRVariable(:U; kind=UtilityNode, states=["a"],
                                            table=[1.0])])
        @test_throws ValidationError validate(util_states)
        no_table = NetworkIR("nt", [IRVariable(:A; states=["a", "b"])])
        @test_throws ValidationError validate(no_table)
        @test validate(no_table; allow_missing_tables=true) === no_table
        bad_mau = NetworkIR("bm", [IRVariable(:A; states=["a", "b"], table=[0.5, 0.5])];
                            mau=[MAUNode(:M, [:A], [1.0])])
        @test_throws ValidationError validate(bad_mau)
        neg = NetworkIR("neg", [IRVariable(:A; states=["a", "b"], table=[-0.5, 1.5])])
        @test_throws ValidationError validate(neg)
    end

    @testset "joint distribution and marginal" begin
        ir = NetworkIR("tiny",
                       [IRVariable(:A; states=["a1", "a2"], table=[0.2, 0.8]),
                        IRVariable(:B; states=["b1", "b2", "b3"], parents=[:A],
                                   table=[0.5 0.3 0.2; 0.1 0.1 0.8])])
        jd = joint_distribution(ir)
        @test jd.variables == [:A, :B]
        @test size(jd.table) == (2, 3)
        @test jd.table[1, 1] ≈ 0.2 * 0.5
        @test jd.table[2, 3] ≈ 0.8 * 0.8
        @test sum(jd.table) ≈ 1
        @test marginal(ir, :A) ≈ [0.2, 0.8]
        @test marginal(ir, :B) ≈
              [0.2 * 0.5 + 0.8 * 0.1, 0.2 * 0.3 + 0.8 * 0.1, 0.2 * 0.2 + 0.8 * 0.8]
        @test marginal(jd, "B") ≈ marginal(ir, :B)
        @test_throws KeyError marginal(jd, :Z)
        @test_throws ValidationError joint_distribution(grazing_reference_ir())
        # parent order matters: swapping parents of a two-parent node changes the joint
        hab = habitat_reference_ir()
        @test sum(joint_distribution(hab).table) ≈ 1
        m = marginal(hab, :Occupancy)
        @test length(m) == 2 && sum(m) ≈ 1
    end

    @testset "equality and differences" begin
        a = habitat_reference_ir()
        b = habitat_reference_ir()
        @test a == b
        @test isequivalent(a, b)
        @test isempty(differences(a, b))
        c = BayesianNetworkFormats._with(a; name="other")
        @test !isequivalent(a, c)
        @test isequivalent(a, c; name=false)
        @test differences(a, c) == ["name: \"habitat_reference\" vs \"other\""]
        v = variable(a, :Climate)
        v2 = BayesianNetworkFormats._with(v; table=[0.3, 0.5, 0.2 + 1e-9])
        d = BayesianNetworkFormats._with(a; variables=[v2; a.variables[2:end]])
        @test !isequivalent(a, d)
        @test isequivalent(a, d; atol=1e-8)
        @test occursin("Climate table entry", only(differences(a, d)))
        # variable order
        e = BayesianNetworkFormats._with(a; variables=reverse(a.variables))
        @test !isequivalent(a, e)
        @test isequivalent(a, e; order=false)
        @test hash(a) == hash(b)
        @test variable(a, :Climate) == variable(b, :Climate)
        # `==` compares content, not provenance, so it agrees with `isequivalent` and
        # `hash`: the same network read from a path and from an IOBuffer is equal.
        frompath = read_network(fix("bif/asia.bif"))
        frombuffer = parse_string(read(fix("bif/asia.bif"), String), BIF())
        @test frompath.source != frombuffer.source
        @test frompath == frombuffer
        @test hash(frompath) == hash(frombuffer)
        @test isequivalent(frompath, frombuffer)
        @test !isequivalent(frompath, frombuffer; source=true)
        @test BayesianNetworkFormats._with(a; format=:dne) == a
    end

    @testset "MAU differences" begin
        gr = grazing_reference_ir()
        @test isempty(differences(gr, grazing_reference_ir()))
        nomau = BayesianNetworkFormats._with(gr; mau=MAUNode[])
        @test differences(gr, nomau) == ["mau: 1 vs 0 nodes"]
        @test isequivalent(gr, nomau; mau=false)
        renamed = BayesianNetworkFormats._with(gr;
                                               mau=[MAUNode(:Total,
                                                            gr.mau[1].parents,
                                                            gr.mau[1].weights)])
        @test differences(gr, renamed) == ["mau id: TotalUtility vs Total"]
        swapped = BayesianNetworkFormats._with(gr;
                                               mau=[MAUNode(:TotalUtility,
                                                            reverse(gr.mau[1].parents),
                                                            gr.mau[1].weights)])
        @test occursin("parents", only(differences(gr, swapped)))
        weighted = BayesianNetworkFormats._with(gr;
                                                mau=[MAUNode(:TotalUtility,
                                                             gr.mau[1].parents,
                                                             [1.0, 2.0])])
        @test occursin("weights", only(differences(gr, weighted)))
        @test gr.mau[1] != weighted.mau[1]
        @test hash(gr.mau[1]) != hash(weighted.mau[1])
    end

    @testset "NaN in a utility table" begin
        # validate checks chance rows entrywise; utility tables are checked for NaN
        u = IRVariable(:U; kind=UtilityNode, parents=[:A], table=[1.0, NaN])
        a = IRVariable(:A; states=["a", "b"], table=[0.5, 0.5])
        ir = NetworkIR("nanu", [a, u])
        e = try
            validate(ir)
            nothing
        catch err
            err
        end
        @test e isa ValidationError && e.id == :U
        @test occursin("NaN", sprint(showerror, e))
        @test_throws ValidationError write_string(ir, NeticaDNE())
        ok = NetworkIR("oku",
                       [a,
                        IRVariable(:U; kind=UtilityNode, parents=[:A],
                                   table=[1.0, 2.0])])
        @test validate(ok) === ok
    end
end
