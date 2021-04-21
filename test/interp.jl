using Test
using CompilerPluginTools

struct TestInterpreter <: JuliaLikeInterpreter
    native_interpreter::NativeInterpreter
end

function CompilerPluginTools.optimize(interp::TestInterpreter, ir::IRCode)
    @test true
    return ir
end

code_ircode(sin, (Float64, ); interp=TestInterpreter(NativeInterpreter()))
