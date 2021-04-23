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

    @test test_ci.code[1] == :(overdub($(GlobalRef(Main, :>)), $(SlotNumber(2)), 0))
    @test test_ci.code[2] isa GotoIfNot
    @test test_ci.code[3] == :(overdub($(GlobalRef(Main, :*)), 2, $(SlotNumber(2))))
    @test test_ci.code[4] == ReturnNode(SSAValue(3))
    @test test_ci.code[5] == :(overdub($(GlobalRef(Main, :*)), 3, $(SlotNumber(2))))
    @test test_ci.code[6] == ReturnNode(SSAValue(5))
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

    @test test_ci.code[1] == :(1 + 1)
    @test test_ci.code[2] isa GotoIfNot
    @test test_ci.code[3] == "variable: %3"
    @test test_ci.code[4] == :(overdub($(SSAValue(3)), $(GlobalRef(Main, :*)), 2, $(SlotNumber(2))))
    @test test_ci.code[5] == ReturnNode(SSAValue(4))
    @test test_ci.code[6] == "variable: %5"

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
end
