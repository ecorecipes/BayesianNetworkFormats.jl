@testset "io" begin
    @testset "detect_format" begin
        @test detect_format("x.dne") isa NeticaDNE
        @test detect_format("x.XDSL") isa GeNIeXDSL
        @test detect_format("x.net") isa HuginNET
        @test detect_format("x.bif") isa BIF
        @test detect_format("x.dsc") isa DSC
        @test detect_format("x.uai") isa UAI
        @test detect_format("x.bnir.json") isa IRJSON
        @test_throws FormatDetectionError detect_format("x.bif.gz")
        @test_throws FormatDetectionError detect_format("x.neta")
        @test_throws FormatDetectionError detect_format("does_not_exist.txt")
        mktempdir() do dir
            for (src, fmt) in (("dne/habitat_reference.dne", NeticaDNE),
                               ("xdsl/habitat_reference.xdsl", GeNIeXDSL),
                               ("net/asia.net", HuginNET), ("bif/asia.bif", BIF), ("dsc/asia.dsc", DSC),
                               ("uai/asia.uai", UAI), ("golden/bif_asia.bnir.json", IRJSON))
                p = joinpath(dir, replace(basename(src), r"\..*$" => "") * ".txt")
                cp(fix(src), p; force=true)
                @test detect_format(p) isa fmt
            end
            p = joinpath(dir, "junk.txt")
            write(p, "nothing to see here")
            @test_throws FormatDetectionError detect_format(p)
            gz = joinpath(dir, "asia.txt")
            write(gz, "\x1f\x8b\x08rest")
            @test_throws FormatDetectionError detect_format(gz)
            e = try
                detect_format(gz)
                nothing
            catch err
                err
            end
            @test occursin("gunzip", sprint(showerror, e))
        end
    end

    @testset "read_network / write_network / fixture_path" begin
        @test format_name(NeticaDNE()) == :dne
        @test format_name(IRJSON()) == :bnir
        p = fixture_path("dne/habitat_reference.dne")
        @test isabspath(p) && isfile(p)
        @test_throws SystemError fixture_path("dne/nope.dne")
        @test_throws SystemError read_network("no_such_file.bif")
        ir = read_network(p; format=NeticaDNE())
        @test ir.source == p
        mktempdir() do dir
            out = joinpath(dir, "h.xdsl")
            @test write_network(out, ir) == out
            @test isequivalent(read_network(out), ir; extras=false)
            u = joinpath(dir, "h.uai")
            write_network(u, ir)
            @test isfile(u * ".names")
            @test isequivalent(read_network(u), ir; titles=false, positions=false,
                               comments=false, extras=false)
            # explicit format overrides the extension
            write_network(joinpath(dir, "h.txt"), ir; format=BIF())
            @test read_network(joinpath(dir, "h.txt"); format=BIF()).format == :bif
        end
    end

    @testset "a failed write leaves the file as it was" begin
        # `write_network` opened the file for writing before the writer validated the IR, so
        # a rejected write left an empty file in place of the old one.
        mktempdir() do dir
            asia = read_network(fix("bif/asia.bif"))
            bif = joinpath(dir, "keep.bif")
            write(bif, "ORIGINAL")
            decision = NetworkIR("d",
                                 [IRVariable(:D; kind=DecisionNode, states=["a", "b"])])
            @test_throws UnsupportedNodeError write_network(bif, decision)
            @test read(bif, String) == "ORIGINAL"
            # a failure part-way through serialising: extras that JSON cannot hold
            json = joinpath(dir, "keep.bnir.json")
            write(json, "ORIGINAL")
            odd = NetworkIR("x",
                            [IRVariable(:A; states=["a"], table=[1.0],
                                        extras=Dict{Symbol,Any}(:f => sin))])
            @test_throws ArgumentError write_network(json, odd)
            @test_throws ArgumentError write_ir_json(json, odd)
            @test read(json, String) == "ORIGINAL"
            # a UAI file and its sidecar are both left alone when the names are rejected
            uai = joinpath(dir, "keep.uai")
            write(uai, "ORIGINAL")
            write(uai * ".names", "ORIGINAL NAMES")
            hash = NetworkIR("h",
                             [IRVariable(Symbol("#x"); states=["a", "b"], table=[0.5, 0.5])])
            @test_throws ValidationError write_network(uai, hash)
            @test read(uai, String) == "ORIGINAL"
            @test read(uai * ".names", String) == "ORIGINAL NAMES"
            # an evidence file is checked sample by sample before it is replaced
            evid = joinpath(dir, "keep.uai.evid")
            write(evid, "ORIGINAL")
            @test_throws ValidationError write_uai_evidence(evid,
                                                            [Dict(:asia => "yes"),
                                                             Dict(:nope => "yes")]; ir=asia)
            @test read(evid, String) == "ORIGINAL"
            # and no temporary file is left behind
            @test sort(readdir(dir)) ==
                  ["keep.bif", "keep.bnir.json", "keep.uai", "keep.uai.evid",
                   "keep.uai.names"]
            # a missing directory is still a `SystemError` that names the file asked for
            nowhere = joinpath(dir, "missing", "x.bif")
            e = try
                write_network(nowhere, asia)
                nothing
            catch err
                err
            end
            @test e isa SystemError
            @test occursin("x.bif", sprint(showerror, e)) &&
                  !occursin(".tmp", sprint(showerror, e))
            # A write that succeeds replaces the file whole, keeps its permission bits and
            # writes through a symbolic link, as writing in place did.
            @test write_network(bif, asia) == bif
            @test isequivalent(read_network(bif), asia)
            if !Sys.iswindows()
                chmod(bif, 0o640)
                write_network(bif, asia)
                @test filemode(bif) & 0o777 == 0o640
                link = joinpath(dir, "link.bif")
                symlink(bif, link)
                small = NetworkIR("s",
                                  [IRVariable(:A; states=["a", "b"], table=[0.5, 0.5])])
                write_network(link, small)
                @test islink(link)
                @test [v.id for v in read_network(bif).variables] == [:A]
            end
        end
    end

    @testset "the UAI names sidecar through read_network" begin
        mktempdir() do dir
            model = joinpath(dir, "m.uai")
            cp(fix("uai/asia.uai"), model)
            side = joinpath(dir, "custom.names")
            cp(fix("uai/asia.uai.names"), side)
            # without a sidecar next to the file the names are synthesised
            plain = read_network(model)
            @test [v.id for v in plain.variables] == [Symbol("X$(i)") for i in 0:7]
            # `names` is forwarded to read_uai from both read_network methods
            named = read_network(model; names=side)
            @test [v.id for v in named.variables] ==
                  [v.id for v in read_network(fix("uai/asia.uai")).variables]
            @test variable(named, :dysp).parents == [:bronc, :either]
            io_named = open(io -> read_network(io, UAI(); names=side), model)
            @test isequivalent(io_named, named; source=false)
            @test_throws ArgumentError read_network(fix("bif/asia.bif"); names=side)
            e = try
                read_network(fix("bif/asia.bif"); names=side)
                nothing
            catch err
                err
            end
            @test occursin("only supported by the UAI format", sprint(showerror, e))
        end
    end
end
