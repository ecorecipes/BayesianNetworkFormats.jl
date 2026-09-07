ENV["GKSwstype"] = get(ENV, "GKSwstype", "100")

using Documenter
using DocumenterCitations
using BayesianNetworkFormats

DocMeta.setdocmeta!(BayesianNetworkFormats, :DocTestSetup, :(using BayesianNetworkFormats);
                    recursive=true)

# Tutorials are rendered quarto vignettes copied into docs/src/tutorials by
# scripts/sync_vignettes.jl. The page list is built from the files on disk so
# it never has to be maintained by hand.
function tutorial_pages()
    dir = joinpath(@__DIR__, "src", "tutorials")
    isdir(dir) || return Pair{String,String}[]
    files = sort(filter(f -> endswith(f, ".md"), readdir(dir)))
    map(files) do f
        title = f
        for line in eachline(joinpath(dir, f))
            m = match(r"^#\s+(.*)", line)
            if m !== nothing
                title = String(strip(m.captures[1]))
                break
            end
        end
        return title => "tutorials/" * f
    end
end

pages = Any["Home" => "index.md", "File formats" => "formats.md",
            "API Reference" => "api.md", "References" => "references.md"]
tutorials = tutorial_pages()
isempty(tutorials) || push!(pages, "Tutorials" => tutorials)

# `[Key](@cite)` in docstrings and pages resolves against docs/src/references.bib,
# a copy of the ecosystem-wide docs/references.bib kept in sync by
# scripts/sync_references.jl.
bib = CitationBibliography(joinpath(@__DIR__, "src", "references.bib"); style=:authoryear)

# Source links need a commit to point at. A checkout without commits (a fresh
# scaffold, a tarball) builds without them instead of failing.
has_commit = success(pipeline(`git -C $(@__DIR__) rev-parse HEAD`; stderr=devnull))
remote_kw = has_commit ?
            (; repo=Remotes.GitHub("ecorecipes", "BayesianNetworkFormats.jl")) :
            (; remotes=nothing)

makedocs(;
         remote_kw...,
         modules=[BayesianNetworkFormats],
         sitename="BayesianNetworkFormats.jl",
         authors="Simon Frost",
         warnonly=[:missing_docs, :cross_references],
         format=Documenter.HTML(;
                                prettyurls=get(ENV, "CI", "false") == "true",
                                canonical="https://ecorecipes.github.io/BayesianNetworkFormats.jl",
                                repolink="https://github.com/ecorecipes/BayesianNetworkFormats.jl",
                                edit_link="main"),
         plugins=[bib],
         pages=pages,)

deploydocs(;
           repo="github.com/ecorecipes/BayesianNetworkFormats.jl.git",
           devbranch="main",)
