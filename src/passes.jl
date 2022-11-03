"""
    anymap(f, xs)

Like `map`, but force to create `Vector{Any}`.
"""
anymap(f, xs) = Any[f(x) for x in xs]

"""
    default_julia_pass(ir::IRCode, sv::OptimizationState)

The default julia optimization pass.
"""
function default_julia_pass(ir::IRCode, sv::OptimizationState)
    ir = compact!(ir)
    if VERSION < v"1.9-"
        ir = ssa_inlining_pass!(ir, ir.linetable, sv.inlining, sv.src.propagate_inbounds)
    else
        ir = ssa_inlining_pass!(ir, sv.inlining, ci.propagate_inbounds)
    end

    ir = compact!(ir)

    @static if VERSION < v"1.8-"
        ir = Core.Compiler.getfield_elim_pass!(ir)
    else
        ir = Core.Compiler.sroa_pass!(ir)
    end

    ir = adce_pass!(ir)
    ir = type_lift_pass!(ir)
    ir = compact!(ir)
    if JLOptions().debug_level == 2
        verify_ir(ir)
        verify_linetable(ir.linetable)
    end
    return ir
end

"""
    no_pass(ir::IRCode, ::OptimizationState)

No pass.
"""
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
            # NOTE:
            # dest in IRCode refers to #BB
            # don't update it
            # dest = findfirst(isequal(dest), perm)
            return GotoIfNot(cond, dest)
        @case GotoNode(label)
            return GotoNode(findfirst(isequal(label), perm))
        @case ReturnNode(val)
            return ReturnNode(permute_stmt(val, perm))
        @case _
            return e
    end
end

"""
    permute_stmts!(ir::IRCode, perm::Vector{Int})

Permute statements according to `perm`.
"""
function permute_stmts!(ir::IRCode, perm::Vector{Int})
    inst = Any[permute_stmt(ir.stmts.inst[v], perm) for v in perm]
    copyto!(ir.stmts.inst, inst)
    permute!(ir.stmts.flag, perm)
    permute!(ir.stmts.line, perm)
    permute!(ir.stmts.type, perm)
    permute!(ir.stmts.flag, perm)
    return ir
end

@static if VERSION < v"1.8-"
    argtypes(sig::Signature) = sig.atypes
else
    argtypes(sig::Signature) = sig.argtypes
end

function is_allconst(sig::Signature)
    allconst = true
    for atype in argtypes(sig)
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
    f, ft, atypes = sig.f, sig.ft, argtypes(sig)
    
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
            @case Expr(:call, f, args...)
                new_stmt = Expr(:call, f, map(eval_global, args)...)
                sig = Core.Compiler.call_sig(ir, new_stmt)
                sig === nothing && continue
                if is_const_call_inlineable(sig)
                    fargs = anymap(x::Const -> x.val, argtypes(sig)[2:end])
                    val = sig.f(fargs...)
                    ir.stmts[i][:inst] = quoted(val)
                    ir.stmts[i][:type] = Const(val)
                else
                    ir.stmts[i][:inst] = new_stmt
                end
            @case Expr(:invoke, mi, f, args...)
                ir.stmts[i][:inst] = Expr(:invoke, mi, f, map(eval_global, args)...)
            @case Expr(:new, t, args...)
                allconst = all(x->is_arg_allconst(ir, x), args)
                allconst && isconcretetype(t) && !ismutabletype(t) || continue
                args = anymap(arg->unwrap_arg(ir, arg), args)
                val = ccall(:jl_new_structv, Any, (Any, Ptr{Cvoid}, UInt32), t, args, length(args))
                ir.stmts[i][:inst] = quoted(val)
                ir.stmts[i][:type] = Const(val)
            @case _
                nothing
        end
    end
    return ir
end

function eval_global(x)
    @switch x begin
        @case GlobalRef(mod, name)
            t = Core.Compiler.abstract_eval_global(mod, name)
            t isa Const || return x
            return quoted(t.val)
        @case _
            return x
    end
end

"""
    const_invoke!(f, ir::IRCode, ref::GlobalRef)

Replace the function invoke `Expr(:invoke, _, ref, args...)` with
`f(args...)` if its arguments `args` are all constant.
"""
function const_invoke!(f, ir::IRCode, ref::GlobalRef)
    for i in 1:length(ir.stmts)
        stmt = ir.stmts[i][:inst]
        
        @switch stmt begin
            @case Expr(:invoke, _, &ref, args...)
                if all(x->is_arg_allconst(ir, x), args)
                    args = anymap(x->unwrap_arg(ir, x), args)
                    val = f(args...)

                    ir.stmts[i][:inst] = quoted(val)
                    ir.stmts[i][:type] = Const(val)
                end
            @case _
                nothing
        end
    end
    return ir
end

function contains_const_invoke(ir::IRCode, ref::GlobalRef)
    for i in 1:length(ir.stmts)
        stmt = ir.stmts[i][:inst]

        @switch stmt begin
            @case Expr(:invoke, _, &ref, args...)
                all(x->is_arg_allconst(ir, x), args) && return true
            @case _
                nothing
        end
    end
    return false
end
