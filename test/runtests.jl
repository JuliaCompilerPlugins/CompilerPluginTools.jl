using CompilerPluginTools
using Test

@testset "patches" begin
    include("patches.jl")    
end

@testset "interpreter" begin
    include("interp.jl")    
end

@testset "codeinfo" begin
    include("codeinfo.jl")
end

@testset "passes" begin
    include("passes.jl")
end