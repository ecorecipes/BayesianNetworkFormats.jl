@testset "cross-format equality" begin
    @testset "asia in bif, net, dsc, uai" begin
        irs = Dict(ext => read_network(fix("$(ext)/asia.$(ext)"))
                   for ext in ("bif", "net", "dsc", "uai"))
        for a in keys(irs), b in keys(irs)
            @test isequivalent(irs[a], irs[b]; name=false)
        end
        for (ext, ir) in irs
            @test marginal(ir, :dysp) ≈ [0.4360, 0.5640] atol = 5e-5
        end
        # the exact brute-force value pins the axis convention
        @test marginal(irs["bif"], :dysp)[1] ≈ 0.4359706 atol = 1e-7
        @test marginal(irs["bif"], :xray) ≈ [0.11029, 0.88971] atol = 1e-4
    end

    @testset "habitat reference in all six formats" begin
        ref = habitat_reference_ir()
        files = ["dne/habitat_reference.dne", "dne/habitat_reference_flat.dne",
                 "xdsl/habitat_reference.xdsl",
                 "net/habitat_reference.net", "bif/habitat_reference.bif",
                 "dsc/habitat_reference.dsc",
                 "uai/habitat_reference.uai"]
        irs = [read_network(fix(f)) for f in files]
        for ir in irs
            @test isequivalent(ir, ref; titles=false, positions=false, comments=false,
                               extras=false)
            @test marginal(ir, :Occupancy) ≈ marginal(ref, :Occupancy)
            @test joint_distribution(ir).table ≈ joint_distribution(ref).table
        end
        for a in irs, b in irs
            @test isequivalent(a, b; titles=false, positions=false, comments=false,
                               extras=false)
        end
        # the rich formats also keep titles and positions
        for f in files[1:4]
            @test isequivalent(read_network(fix(f)), ref; extras=false)
        end
        @test isequivalent(read_network(fix("bif/habitat_reference.bif")), ref;
                           titles=false, comments=false, extras=false)
    end

    @testset "grazing reference ID in dne, xdsl, net" begin
        ref = grazing_reference_ir()
        irs = [read_network(fix(f))
               for f in ("dne/grazing_reference_id.dne", "xdsl/grazing_reference_id.xdsl",
                         "net/grazing_reference_id.net")]
        for ir in irs
            @test isequivalent(ir, ref; mau=false, extras=false)
            @test variable(ir, :GrazingManagement).kind == DecisionNode
            @test variable(ir, :GrazingManagement).parents ==
                  [:ClimateForecast, :CurrentVegetation]
            @test variable(ir, :ManagementCost).table == [-40.0, -15.0, 0.0]
            @test variable(ir, :Vegetation).parents ==
                  [:SoilMoisture, :GrazingPressure, :CurrentVegetation]
            @test variable(ir, :Vegetation).table[1, 2, 1, :] == [0.85, 0.12, 0.03]   # lowest score
            @test variable(ir, :Vegetation).table[3, 1, 3, :] == [0.03, 0.12, 0.85]   # highest score
        end
        @test irs[2].mau == ref.mau
        for a in irs, b in irs
            @test isequivalent(a, b; mau=false, extras=false)
        end
    end

    @testset "umbrella in dne, xdsl, net" begin
        ref = umbrella_ir()
        for f in ("dne/umbrella.dne", "xdsl/umbrella.xdsl", "net/umbrella.net")
            @test isequivalent(read_network(fix(f)), ref)
        end
    end
end
