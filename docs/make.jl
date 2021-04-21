using CompilerPluginTools
using Documenter

DocMeta.setdocmeta!(CompilerPluginTools, :DocTestSetup, :(using CompilerPluginTools); recursive=true)

makedocs(;
    modules=[CompilerPluginTools],
    authors="Roger-luo <rogerluo.rl18@gmail.com> and contributors",
    repo="https://github.com/JuliaCompilerPlugins/CompilerPluginTools.jl/blob/{commit}{path}#{line}",
    sitename="CompilerPluginTools.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaCompilerPlugins.github.io/CompilerPluginTools.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaCompilerPlugins/CompilerPluginTools.jl",
)
