@testset "IR JSON" begin
    for ir in
        (habitat_reference_ir(), grazing_reference_ir(), umbrella_ir(), sprinkler_ir(),
         read_network(fix("dne/levels_continuous.dne")),
         read_network(fix("xdsl/equation_node.xdsl"); strict=false))
        io = IOBuffer()
        write_ir_json(io, ir)
        text = String(take!(io))
        back = read_ir_json(IOBuffer(text))
        @test back == ir                      # full structural equality, extras included
        @test isequivalent(back, ir; format=true, source=true)
        io2 = IOBuffer()
        write_ir_json(io2, back)
        @test String(take!(io2)) == text      # deterministic
    end
    lv = read_network(fix("dne/levels_continuous.dne"))
    text = write_string(lv, IRJSON())
    @test occursin("\"levels\": [-Infinity, 10.0, 20.0, Infinity]", text)
    @test occursin("\"kind\": \"chance\"", text)
    # key order is fixed: format, version, name, ...
    @test findfirst("\"format\"", text) < findfirst("\"version\"", text) <
          findfirst("\"name\"", text)
    rt = roundtrip(grazing_reference_ir(), IRJSON())
    @test rt == BayesianNetworkFormats._with(grazing_reference_ir(); format=:ir, source="")
    @test rt.mau == grazing_reference_ir().mau
    @test_throws ParseError read_ir_json(IOBuffer("{\"format\": \"other\"}"))
    @test_throws ParseError read_ir_json(IOBuffer("not json"))
    @test_throws ParseError read_ir_json(IOBuffer("{\"format\":\"bnir\",\"variables\":[{\"id\":\"A\",\"kind\":\"weird\",\"states\":[],\"parents\":[]}]}"))
    bad = NetworkIR("x",
                    [IRVariable(:A; states=["a"], table=[1.0],
                                extras=Dict{Symbol,Any}(:f => sin))])
    @test_throws ArgumentError write_ir_json(IOBuffer(), bad)
end
