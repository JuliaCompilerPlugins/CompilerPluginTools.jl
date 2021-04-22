using Test
using CompilerPluginTools

module TestIntrinsic
using CompilerPluginTools

@intrinsic_stub device main(gate)
@intrinsic_stub device gate(gate, loc::Int)
@intrinsic_stub device ctrl(gate, loc::Int, ctrl::Int)
end

@test TestIntrinsic.isintrinsic(:main)
@test TestIntrinsic.isintrinsic(:ctrl)
@test TestIntrinsic.isintrinsic(:gate)

@test_throws IntrinsicError TestIntrinsic.main(:gate)
@test_throws IntrinsicError TestIntrinsic.gate(:gate, 1)
@test_throws IntrinsicError TestIntrinsic.ctrl(:gate, 1, 2)
