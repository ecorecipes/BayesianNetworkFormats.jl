using BayesianNetworkFormats: tokenize, DNE_TOKENS, NET_TOKENS, BIF_TOKENS

@testset "tokenizer" begin
    toks = tokenize("a = (1, 0x1f, -2.5e-3, @imposs); // comment\n/* block\n */ b = \"x\\\"y\";",
                    DNE_TOKENS)
    kinds = [t.kind for t in toks]
    @test kinds ==
          [:ident, :punct, :punct, :number, :punct, :number, :punct, :number, :punct,
           :ident,
           :punct, :punct, :ident, :punct, :string, :punct, :eof]
    @test toks[4].value == 1.0
    @test toks[6].value == 31.0
    @test toks[8].value == -0.0025
    @test toks[10].text == "@imposs"
    @test toks[15].text == "x\"y"
    @test toks[13].line == 3 && toks[13].column == 5

    # Netica backslash-newline continuation strips the indentation of the next line
    s = "c = \"first\\n\\\n\t\tsecond\";"
    t = tokenize(s, DNE_TOKENS)
    @test t[3].text == "first\nsecond"
    # -INFINITY is a single identifier
    t = tokenize("levels = (-INFINITY, 3, INFINITY);", DNE_TOKENS)
    @test t[4].kind == :ident && t[4].text == "-INFINITY"
    # HUGIN comments
    t = tokenize("net % comment\n{ }", NET_TOKENS)
    @test [x.text for x in t[1:3]] == ["net", "{", "}"]
    # BIF identifiers may contain '-' and '.'; identifiers may start with a digit
    t = tokenize("(x-1, 2nd, 3.5)", BIF_TOKENS)
    @test [x.kind for x in t[2:6]] == [:ident, :punct, :ident, :punct, :number]
    @test t[2].text == "x-1" && t[4].text == "2nd"

    e = try
        tokenize("a = \"unterminated", DNE_TOKENS; file="f.dne")
        nothing
    catch err
        err
    end
    @test e isa ParseError
    @test e.file == "f.dne" && e.line == 1 && e.column == 5
    @test occursin("f.dne:1:5", sprint(showerror, e))
    @test_throws ParseError tokenize("/* open", DNE_TOKENS)
    @test_throws ParseError tokenize("a = #", DNE_TOKENS)
    # Netica state-index literals (#k, 0-based) are a token kind of their own
    t = tokenize("evidence = #12; probs = (#0);", DNE_TOKENS)
    @test t[3].kind == :stateindex && t[3].text == "#12" && t[3].value == 12.0
    @test t[8].kind == :stateindex && t[8].value == 0.0
    @test t[9].kind == :punct && t[9].text == ")"
    @test_throws ParseError tokenize("a = #x", DNE_TOKENS)
    @test_throws ParseError tokenize("a = #0", BIF_TOKENS)

    # escapes inside strings: \t and \r as well as \n
    t = tokenize("c = \"a\\tb\\rc\\nd\\qe\";", DNE_TOKENS)
    @test t[3].text == "a\tb\rc\nd" * "qe"
    # a CRLF continuation (Windows-written .dne) strips the indentation of the next line
    t = tokenize("c = \"first\\\r\n   second\";", DNE_TOKENS)
    @test t[3].text == "firstsecond"
    @test t[4].line == 2
    # a bare newline inside a string is kept, and the line counter advances
    t = tokenize("c = \"one\ntwo\";\nd = 1;", DNE_TOKENS)
    @test t[3].text == "one\ntwo"
    @test t[5].line == 3
    # HUGIN has no string continuation: a backslash-newline is a newline in the text
    t = tokenize("label = \"one\\\ntwo\";", NET_TOKENS)
    @test t[3].text == "one\ntwo"
    # CRLF between tokens does not upset the line/column tracking
    t = tokenize("net\r\n{\r\n}\r\n", NET_TOKENS)
    @test [x.text for x in t[1:3]] == ["net", "{", "}"]
    @test t[3].line == 3
end
