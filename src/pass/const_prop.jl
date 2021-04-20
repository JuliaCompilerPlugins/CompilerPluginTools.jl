function inline_const!(ir::IRCode)
    for i in 1:length(ir.stmts)
        stmt = ir.stmts[i][:inst]
        if stmt isa GlobalRef
            t = Core.Compiler.abstract_eval_global(stmt.mod, stmt.name)
            t isa Const || continue
            ir.stmts[i][:inst] = quoted(t.val)
            ir.stmts[i][:type] = t
        elseif stmt isa Expr
            if stmt.head === :call
                sig = Core.Compiler.call_sig(ir, stmt)
                f, ft, atypes = sig.f, sig.ft, sig.atypes
                allconst = true
                for atype in sig.atypes
                    if !isa(atype, Const)
                        allconst = false
                        break
                    end
                end
    
                if allconst &&
                   isa(f, Core.IntrinsicFunction) &&
                   is_pure_intrinsic_infer(f) &&
                   intrinsic_nothrow(f, atypes[2:end])
    
                    fargs = anymap(x::Const -> x.val, atypes[2:end])
                    val = f(fargs...)
                    ir.stmts[i][:inst] = quoted(val)
                    ir.stmts[i][:type] = Const(val)
                elseif allconst && isa(f, Core.Builtin) && 
                       (f === Core.tuple || f === Core.getfield)
                    fargs = anymap(x::Const -> x.val, atypes[2:end])
                    val = f(fargs...)
                    ir.stmts[i][:inst] = quoted(val)
                    ir.stmts[i][:type] = Const(val)
                end
            elseif stmt.head === :new
                exargs = stmt.args[2:end]
                allconst = all(arg->is_arg_allconst(ir, arg), exargs)
                t = stmt.args[1]
                if allconst && isconcretetype(t) && !t.mutable
                    args = anymap(arg->unwrap_arg(ir, arg), exargs)
                    val = ccall(:jl_new_structv, Any, (Any, Ptr{Cvoid}, UInt32), t, args, length(args))
    
                    ir.stmts[i][:inst] = quoted(val)
                    ir.stmts[i][:type] = Const(val)
                end
            end # if stmt.head
        end # if stmt isa X
    end
    return ir
end
