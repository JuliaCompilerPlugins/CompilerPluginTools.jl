using Test
using Yuan

struct TestInterpreter <: JuliaLikeInterpreter
    native_interpreter::NativeInterpreter
end

function Yuan.optimize(interp::TestInterpreter, ir::IRCode)
    @test true
    return ir
end

code_ircode(sin, (Float64, ); interp=TestInterpreter(NativeInterpreter()))
