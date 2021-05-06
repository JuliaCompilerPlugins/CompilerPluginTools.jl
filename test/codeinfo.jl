using Test
using CompilerPluginTools
using MLStyle
using Expronicon

function foo(x)
    if x > 0
        2x
    else
        3x
    end
end

@testset "map(f, ::CodeInfo)" begin
    ci = code_lowered(foo, (Float64, ))[1]
    test_ci = map(NewCodeInfo(ci)) do stmt
        @match stmt begin
            Expr(:call, f, args...) => Expr(:call, :overdub, f, args...)
            _ => stmt
        end
    end

    @test_codeinfo test_ci begin
        :(overdub($(GlobalRef(Main, :>)), $(SlotNumber(2)), 0))
        ::GotoIfNot
        :(overdub($(GlobalRef(Main, :*)), 2, $(SlotNumber(2))))
        ReturnNode(SSAValue(3))
        :(overdub($(GlobalRef(Main, :*)), 3, $(SlotNumber(2))))
        ReturnNode(SSAValue(5))
    end
end

@testset "NewCodeInfo" begin
    ci = code_lowered(foo, (Float64, ))[1]
    new = NewCodeInfo(ci)
    for (v, stmt) in new
        @switch stmt begin
            @case Expr(:call, GlobalRef(Main, :>), a, b)
                delete!(new, v)
                insert!(new, v, :(1 + 1))
            @case Expr(:call, f, args...)
                x = insert!(new, v, "variable: %$v")
                new[v] = Expr(:call, :overdub, x, f, args...)
            @case _
                nothing
        end
    end
    test_ci = finish(new)

    @test_codeinfo test_ci begin
        :(1 + 1)
        ::GotoIfNot

        "variable: %3"
    
        :(overdub($(SSAValue(3)), $(GlobalRef(Main, :*)), 2, $(SlotNumber(2))))
        ReturnNode(SSAValue(4))
    
        "variable: %5"
    end

    @testset "slot insertion" begin
        ci = code_lowered(foo, (Float64, ))[1]
        new = NewCodeInfo(ci)
        insert!(new.slots, 1, Symbol("#a#"))
        insert!(new.slots, 1, Symbol("#b#"))
        nci = finish(new)
        @test nci.code[1] == Expr(:call, GlobalRef(Main, :>), SlotNumber(4), 0)
        @test nci.code[2] == GotoIfNot(SSAValue(1), 5)
        @test nci.slotnames == [Symbol("#b#"), Symbol("#a#"), Symbol("#self#"), :x]
    end

    @testset "pc=1 multi push" begin
        ci = code_lowered(foo, (Float64, ))[1]
        new = NewCodeInfo(ci)
        push!(new, :(1 + 1))
        push!(new, :(1 + 2))
        push!(new, :(1 + 3))

        for (v, stmt) in new
            if v == 3
                x = insert!(new, v, :(1 + 2))
                new[v] = :(1 + $x)
            end
        end

        test_ci = finish(new)
        @test test_ci.code[1] == :(1 + 1)
        @test test_ci.code[2] == :(1 + 2)
        @test test_ci.code[3] == :(1 + 3)
        @test test_ci.code[4] == Expr(:call, GlobalRef(Main, :>), SlotNumber(2), 0)
        @test test_ci.code[5] == GotoIfNot(SSAValue(4), 9)
        @test test_ci.code[6] == :(1 + 2)
        @test test_ci.code[7] == :(1 + $(SSAValue(6)))
    end

    @testset "multiple insert!(new, 2, ...)" begin
        ci = code_lowered(foo, (Float64, ))[1]
        new = NewCodeInfo(ci)
        insert!(new, 2, :(1 + 1))
        insert!(new, 2, :(1 + 2))
        insert!(new, 2, :(1 + 3))
        test_ci = finish(new)
    
        @test test_ci.code[4] == :(1 + 1)
        @test test_ci.code[3] == :(1 + 2)
        @test test_ci.code[2] == :(1 + 3)
    end

    @testset "multiple push!(new, ...) with setindex" begin
        ci = code_lowered(foo, (Float64, ))[1]
        new = NewCodeInfo(ci)
        push!(new, :(1 + 1))
        push!(new, :(1 + 2))
        push!(new, :(1 + 3))

        for (v, stmt) in new
            if v == 3
                x = push!(new, :(1 + 2))
                x = push!(new, :(1 + 3))
                x = push!(new, :(1 + $x))
                new[v] = :(1 + $x)
            end
        end

        test_ci = finish(new)
        @test test_ci.code[9] == :(1 + $(SSAValue(8)))
    end
end

@testset "rm_code_coverage_effect" begin
    ci = @make_codeinfo begin
        #=%1 =# Expr(:code_coverage_effect)::Nothing
        #=%2 =# QuoteNode(1.0)::Float64
        #=%3 =# Expr(:call, sin, SSAValue(2))::Float64
        #=%4 =# Expr(:code_coverage_effect)::Nothing
        #=%5 =# QuoteNode(2.0)::Float64
        #=%6 =# Expr(:call, sin, SSAValue(5))::Float64
        #=%7 =# Expr(:code_coverage_effect)::Nothing
        #=%8 =# Expr(:call, <, SSAValue(6), QuoteNode(1.0))::Bool
        #=%9 =# GotoIfNot(SSAValue(8), 10)
        #=%10=# Expr(:call, +, SSAValue(3), SSAValue(6))::Float64
        #=%11=# ReturnNode(SSAValue(10))::Float64
    end

    test_ci = CompilerPluginTools.rm_code_coverage_effect(ci)

    @test_codeinfo test_ci begin
        #=%1=# QuoteNode(1.0)::Float64
        #=%2=# Expr(:call, sin, SSAValue(1))::Float64
        #=%3=# QuoteNode(2.0)::Float64
        #=%4=# Expr(:call, sin, SSAValue(3))::Float64
        #=%5=# Expr(:call, <, SSAValue(4), QuoteNode(1.0))::Bool
        #=%6=# GotoIfNot(SSAValue(5), 7)
        #=%7=# Expr(:call, +, SSAValue(2), SSAValue(4))::Float64
        #=%8=# ReturnNode(SSAValue(7))::Float64     
    end
end

@testset "test code_coverage_effect bb start" begin
    ci = @make_codeinfo begin
        Expr(:code_coverage_effect)::Nothing
        Expr(:code_coverage_effect)::Nothing
        Expr(:code_coverage_effect)::Nothing
        Expr(:code_coverage_effect)::Nothing
        Expr(:call, GlobalRef(Main, :foo), 2)::Nothing
        Expr(:call, GlobalRef(Main, :measure), 2)::Int
        Expr(:code_coverage_effect)::Nothing
        Expr(:code_coverage_effect)::Nothing
        Expr(:call, GlobalRef(Main, :measure_cmp), SSAValue(6), 1)::Bool
        GotoIfNot(SSAValue(9), 14)
        Expr(:code_coverage_effect)::Nothing
        Expr(:code_coverage_effect)::Nothing
        Expr(:call, GlobalRef(Main, :foo), 2)::Nothing
        Expr(:code_coverage_effect)::Nothing
        ReturnNode(nothing)::Nothing
    end

    stmt = CompilerPluginTools.rm_code_coverage_effect(ci).code[4]
    @test stmt.cond == SSAValue(3)
    @test stmt.dest == 6
end
