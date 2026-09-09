@testset "positional trailing unnamed Netica links" begin
    for cells in ([""], ["", ""], ["named", ""], ["", "middle", ""],
                  ["", "middle", "last"])
        n = length(cells)
        parents = [Symbol(:P, i) for i in 1:n]
        vars = [IRVariable(p; states=["no", "yes"], table=[0.5, 0.5]) for p in parents]
        push!(vars,
              IRVariable(:X; states=["no", "yes"], parents=parents,
                         table=fill(0.5, ntuple(_ -> 2, n + 1)),
                         extras=Dict(:inputs => cells)))
        ir = NetworkIR("unnamed-links", vars)
        back = parse_string(write_string(ir, NeticaDNE()), NeticaDNE())
        @test variable(back, :X).extras[:inputs] == cells
        @test variable(back, :X).parents == parents
        @test variable(back, :X).table == variable(ir, :X).table
    end
end

@testset "renormalization cannot bless nonfinite rows" begin
    for row in
        ([Inf, 1.0], [-Inf, 1.0], [NaN, 1.0], [floatmax(Float64), floatmax(Float64)])
        ir = NetworkIR("nonfinite", [IRVariable(:X; states=["a", "b"], table=row)])
        for renormalize in (false, true)
            @test_throws ValidationError validate(ir; renormalize)
        end
        @test isequal(variable(ir, :X).table, row)
    end
    ir = NetworkIR("finite", [IRVariable(:X; states=["a", "b"], table=[2.0, 6.0])])
    @test variable(validate(ir; renormalize=true), :X).table == [0.25, 0.75]
    @test variable(ir, :X).table == [2.0, 6.0]
    for atol in (-1.0, Inf, NaN)
        @test_throws ArgumentError validate(ir; atol, renormalize=true)
    end
end
