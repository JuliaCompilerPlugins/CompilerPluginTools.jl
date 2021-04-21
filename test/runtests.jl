using CompilerPluginTools
using Test

@testset "patches" begin
    include("patches.jl")    
end

@testset "interpreter" begin
    include("interp.jl")    
end
