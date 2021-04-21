using Test
using CompilerPluginTools

foo(x) = 2x

ci = code_lowered(foo, (Float64, ))[1]
new = NewCodeInfo(ci, 1)
push!(new.code, :(1 + 1))
push!(new.code, :(1 + $(SSAValue(1))))
CompilerPluginTools.finish(new)

ci, typ = code_typed(cos, (Float64, ))[1]
ir, typ = code_ircode(cos, (Float64, ))[1]
ir

stmt, type = obtain_const_or_stmt(SSAValue(50), ci)
@test ci.code[50] == stmt
@test ci.ssavaluetypes[50] == type

ir.stmts[1]

new = NewCodeInfo(ci, 2)
