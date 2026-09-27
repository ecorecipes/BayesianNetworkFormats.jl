# The exception hierarchy of ADR 0013: every exception type this package defines, exported
# or not, subtypes the root `BayesianNetworkFormatsError`, and the types keep their module
# and their names. The conformance inspect adapter loads this package with `import` and
# serialises `string(typeof(e))`, so a type must print qualified from a module that only
# imports the package and bare where it is `using`-visible.
function owned_exception_types(M)
    types = Type[]
    for n in names(M; all=true)
        isdefined(M, n) || continue
        T = getglobal(M, n)
        T isa Type && T <: Exception && parentmodule(T) === M && push!(types, T)
    end
    return types
end

@testset "errors" begin
    owned = owned_exception_types(BayesianNetworkFormats)

    @testset "hierarchy" begin
        @test isabstracttype(BayesianNetworkFormatsError)
        @test BayesianNetworkFormatsError <: Exception
        # The search is not vacuous: it finds the root and the seven concrete types.
        @test issubset([BayesianNetworkFormatsError, ParseError, UnsupportedNodeError,
                        NotNormalizedError, ValidationError, FormatDetectionError,
                        IdentifierCollisionError, IdentifierLengthError], owned)
        # A module that binds only the package name, as `import BayesianNetworkFormats`
        # does in the inspect adapter.
        imported_only = Module(:FmtImportedOnly)
        name_only = :(using BayesianNetworkFormats: BayesianNetworkFormats)
        Core.eval(imported_only, name_only)
        for T in owned
            @test T <: BayesianNetworkFormatsError
            @test parentmodule(T) === BayesianNetworkFormats
            @test string(T) == string(nameof(T))
            @test sprint(show, T; context=:module => imported_only) ==
                  "BayesianNetworkFormats." * string(nameof(T))
        end
    end

    @testset "reader and writer errors are caught by the root" begin
        @test_throws BayesianNetworkFormatsError parse_string("network {", BIF())
        @test_throws BayesianNetworkFormatsError parse_string("MARKOV\n1\n2\n1\n1 0\n2\n0.5 0.5\n",
                                                              UAI())
        @test_throws BayesianNetworkFormatsError parse_string("network x { }\n" *
                                                              "variable A { type discrete [ 2 ] { a, b }; }\n" *
                                                              "probability ( A ) { table 0.5, 0.4; }\n",
                                                              BIF())
        cyclic = NetworkIR("c",
                           [IRVariable(:A; parents=[:B], states=["a", "b"],
                                       table=fill(0.5, 2, 2)),
                            IRVariable(:B; parents=[:A], states=["a", "b"],
                                       table=fill(0.5, 2, 2))])
        @test_throws BayesianNetworkFormatsError validate(cyclic)
        @test_throws BayesianNetworkFormatsError detect_format("x.neta")
        collision = NetworkIR("c",
                              [IRVariable(:A; states=["a b", "a_b"], table=[0.5, 0.5])])
        @test_throws BayesianNetworkFormatsError write_string(collision, NeticaDNE())
        long = NetworkIR("l",
                         [IRVariable(Symbol("A"^31); states=["x", "y"], table=[0.5, 0.5])])
        @test_throws BayesianNetworkFormatsError write_string(long, NeticaDNE())
    end

    @testset "invalid arguments and lookups stay outside the root" begin
        ir = parse_string("network x { }\nvariable A { type discrete [ 2 ] { a, b }; }\n" *
                          "probability ( A ) { table 0.5, 0.5; }\n", BIF())
        for (f, E) in ((() -> validate(ir; atol=-1.0), ArgumentError),
                       (() -> variable(ir, :Z), KeyError),
                       (() -> read_network(joinpath(mktempdir(), "missing.bif")),
                        SystemError))
            err = try
                f()
                nothing
            catch e
                e
            end
            @test err isa E
            @test !(err isa BayesianNetworkFormatsError)
        end
    end
end
