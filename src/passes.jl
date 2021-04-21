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

function permute_stmts!(stmt::InstructionStream, perm::Vector{Int})
    inst = []

    for v in perm
        e = stmt.inst[v]

        if e isa Expr
            ex = replace_from_perm(e, perm)
            push!(inst, ex)
        elseif e isa Core.GotoIfNot
            if e.cond isa Core.SSAValue
                cond = Core.SSAValue(findfirst(isequal(e.cond.id), perm))
            else
                # TODO: figure out which case is this
                # and maybe apply permute to this
                cond = e.cond
            end

            dest = findfirst(isequal(e.dest), perm)
            push!(inst, Core.GotoIfNot(cond, dest))
        elseif e isa Core.GotoNode
            push!(inst, Core.GotoNode(findfirst(isequal(e.label), perm)))
        elseif e isa Core.ReturnNode
            if isdefined(e, :val) && e.val isa Core.SSAValue
                push!(inst, Core.ReturnNode(Core.SSAValue(findfirst(isequal(e.val.id), perm))))
            else
                push!(inst, e)
            end
        else
            # RL: I think
            # other nodes won't contain SSAValue
            # let's just ignore them, but if we
            # find any we can add them here
            push!(inst, e)
            # if e isa Core.SlotNumber
            #     push!(inst, e)
            # elseif e isa Core.NewvarNode
            #     push!(inst, e)
            # else
            # end
            # error("unrecognized statement $e :: ($(typeof(e)))")
        end
    end

    copyto!(stmt.inst, inst)
    permute!(stmt.flag, perm)
    permute!(stmt.line, perm)
    permute!(stmt.type, perm)
    permute!(stmt.flag, perm)
    return stmt
end

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
