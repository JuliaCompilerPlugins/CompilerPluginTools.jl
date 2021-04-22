using Test
using CompilerPluginTools

const GLOBAL_CONST = 2.0

struct Foo
    x::Int
end

@testset "inline_const" begin
    ir = @ircode begin
        Expr(:call, Core.Intrinsics.abs_float, 1.0)::Float64
        GlobalRef(Main, :GLOBAL_CONST)::Float64
        ReturnNode(SSAValue(1))::Float64
    end
    
    ir = inline_const!(ir)
    @test ir.stmts[1][:inst] == 1.0
    @test ir.stmts[1][:type] == Const(1.0)
    @test ir.stmts[2][:inst] == 2.0
    @test ir.stmts[2][:type] == Const(2.0)

    ir = @ircode begin
        Expr(:call, Core.Intrinsics.abs_float, 1.0)::Float64
        Expr(:new, Foo, 2)::Foo
        ReturnNode(SSAValue(1))::Float64
    end
    
    ir = inline_const!(ir)

    @test ir.stmts[2][:inst] == QuoteNode(Foo(2))
    @test ir.stmts[2][:type] == Const(Foo(2))

    ir = @ircode begin
        QuoteNode(1)::Int
        Expr(:new, Foo, SSAValue(1))::Foo
        ReturnNode(SSAValue(1))::Int
    end
    ir = inline_const!(ir)
    @test ir.stmts[2][:inst] == QuoteNode(Foo(1))
    @test ir.stmts[2][:type] == Const(Foo(1))

    ir = @ircode begin
        Expr(:call, Core.tuple, 1, 2, 3)::Tuple{Int, Int, Int}
        ReturnNode(SSAValue(1))::Tuple{Int, Int, Int}
    end
    ir = inline_const!(ir)
    @test ir.stmts[1][:inst] == (1, 2, 3)
    @test ir.stmts[1][:type] == Const((1, 2, 3))
end

@testset "permute_stmts!" begin
    ir = @ircode begin
        QuoteNode(1.0)::Const(1.0)
        Expr(:call, sin, SSAValue(1))::Float64
        QuoteNode(2.0)::Const(2.0)
        Expr(:call, sin, SSAValue(3))::Float64
        Expr(:call, <, SSAValue(4), QuoteNode(1.0))::Bool
        GotoIfNot(SSAValue(5), 7)
        Expr(:call, +, SSAValue(2), SSAValue(4))::Float64
        ReturnNode(SSAValue(6))::Float64
    end
    
    ir = permute_stmts!(ir, [1, 3, 2, 4, 5, 6, 7, 8])
    @test ir.stmts[1][:inst] == QuoteNode(1.0)
    @test ir.stmts[2][:inst] == QuoteNode(2.0)
    @test ir.stmts[3][:inst] == Expr(:call, sin, SSAValue(1))
    @test ir.stmts[4][:inst] == Expr(:call, sin, SSAValue(2))
    @test ir.stmts[5][:inst] == Expr(:call, <, SSAValue(4), QuoteNode(1.0))
    @test ir.stmts[6][:inst] == GotoIfNot(SSAValue(5), 2)
    @test ir.stmts[7][:inst] == Expr(:call, +, SSAValue(3), SSAValue(4))
    @test ir.stmts[8][:inst] == ReturnNode(SSAValue(6))
end

function foo(x)
    2x
end

@testset "const_invoke!" begin
    mi = method_instances(foo, (Float64, ))[1]

    ir = @ircode begin
        Expr(:invoke, mi, GlobalRef(Main, :foo), 2.2)::Float64
        Expr(:invoke, mi, GlobalRef(Main, :foo), Argument(2))::Float64
        ReturnNode(SSAValue(1))::Float64
    end
    
    ir = const_invoke!(ir, GlobalRef(Main, :foo)) do x
        3x
    end
    
    @test ir.stmts[1][:inst] ≈ 3 * 2.2
    @test ir.stmts[2][:inst] == Expr(:invoke, mi, GlobalRef(Main, :foo), Argument(2))
end
