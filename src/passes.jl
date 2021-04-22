anymap(f, xs) = Any[f(x) for x in xs]

function default_julia_pass(ir::IRCode, sv::OptimizationState)
    ir = compact!(ir)
    ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, sv.src.propagate_inbounds)
    ir = compact!(ir)
    ir = getfield_elim_pass!(ir)
    ir = adce_pass!(ir)
    ir = type_lift_pass!(ir)
    ir = compact!(ir)
    if JLOptions().debug_level == 2
        verify_ir(ir)
        verify_linetable(ir.linetable)
    end
    return ir
end

no_pass(ir::IRCode, ::OptimizationState) = ir

function replace_from_perm(stmt, perm)
    @match stmt begin
        SSAValue(id) => SSAValue(findfirst(isequal(id), perm))
        Expr(head, args...) => Expr(head, map(x->replace_from_perm(x, perm), args)...)
        _ => stmt
    end
end

function permute_stmt(e, perm::Vector{Int})
    @switch e begin
        @case SSAValue(id)
            return SSAValue(findfirst(isequal(id), perm))
        @case ::Expr
            return replace_from_perm(e, perm)
        @case GotoIfNot(cond, dest)
            cond = permute_stmt(cond, perm)
            dest = findfirst(isequal(dest), perm)
            return GotoIfNot(cond, dest)
        @case GotoNode(label)
            return GotoNode(SSAValue(findfirst(isequal(label), perm)))
        @case ReturnNode(val)
            return ReturnNode(permute_stmt(val, perm))
        @case _
            return e
    end
end

function permute_stmts!(ir::IRCode, perm::Vector{Int})
    inst = Any[permute_stmt(ir.stmts.inst[v], perm) for v in perm]
    copyto!(ir.stmts.inst, inst)
    permute!(ir.stmts.flag, perm)
    permute!(ir.stmts.line, perm)
    permute!(ir.stmts.type, perm)
    permute!(ir.stmts.flag, perm)
    return ir
end

function is_allconst(sig::Signature)
    allconst = true
    for atype in sig.atypes
        if !isa(atype, Const)
            allconst = false
            break
        end
    end
    return allconst
end

function is_arg_allconst(ir, arg)
    if arg isa Argument
        return false
    elseif arg isa SSAValue
        return is_arg_allconst(ir, ir.stmts[arg.id][:inst])
    elseif !is_inlineable_constant(arg) && !isa(arg, QuoteNode)
        return false
    end
    return true
end

function is_const_call_inlineable(sig::Signature)
    is_allconst(sig) || return false
    f, ft, atypes = sig.f, sig.ft, sig.atypes
    
    if isa(f, IntrinsicFunction) && is_pure_intrinsic_infer(f) && intrinsic_nothrow(f, atypes[2:end])
        return true
    end

    if isa(f, Builtin) && (f === Core.tuple || f === Core.getfield)
        return true
    end
    return false
end

function unwrap_arg(ir, arg)
    if arg isa QuoteNode
        return arg.value
    elseif arg isa SSAValue
        return unwrap_arg(ir, ir.stmts[arg.id][:inst])
    else
        return arg
    end
end

"""
    inline_const!(ir::IRCode)

This performs constant propagation on `IRCode` so after the constant propagation
during abstract interpretation, we can force inline constant values in `IRCode`.
"""
function inline_const!(ir::IRCode)
    for i in 1:length(ir.stmts)
        stmt = ir.stmts[i][:inst]
        @switch stmt begin
            @case GlobalRef(mod, name)
                t = Core.Compiler.abstract_eval_global(mod, name)
                t isa Const || continue
                ir.stmts[i][:inst] = quoted(t.val)
                ir.stmts[i][:type] = t
            @case Expr(:call, _...)
                sig = Core.Compiler.call_sig(ir, stmt)
                if is_const_call_inlineable(sig)
                    fargs = anymap(x::Const -> x.val, sig.atypes[2:end])
                    val = sig.f(fargs...)
                    ir.stmts[i][:inst] = quoted(val)
                    ir.stmts[i][:type] = Const(val)
                end
            @case Expr(:new, t, args...)
                allconst = all(x->is_arg_allconst(ir, x), args)
                allconst && isconcretetype(t) && !t.mutable || continue
                args = anymap(arg->unwrap_arg(ir, arg), args)
                @show args
                val = ccall(:jl_new_structv, Any, (Any, Ptr{Cvoid}, UInt32), t, args, length(args))
                ir.stmts[i][:inst] = quoted(val)
                ir.stmts[i][:type] = Const(val)
            @case _
                nothing
        end
    end
    return ir
end
