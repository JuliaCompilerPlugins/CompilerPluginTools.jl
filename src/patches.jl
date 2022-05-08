# MLStyle patches
@active Argument(x) begin
    if x isa Argument
        Some(x.n)
    else
        nothing
    end
end

@active SSAValue(x) begin
    if x isa SSAValue
        Some(x.id)
    else
        nothing
    end
end

@active SlotNumber(x) begin
    if x isa SlotNumber
        Some(x.id)
    else
        nothing
    end
end

@active NewvarNode(x) begin
    if x isa NewvarNode
        Some(x.slot)
    else
        nothing
    end
end

@active NewSSAValue(x) begin
    if x isa NewSSAValue
        Some(x.id)
    else
        nothing
    end
end

@active ReturnNode(x) begin
    if x isa ReturnNode && isdefined(x, :val)
        Some(x.val)
    else
        nothing
    end
end

@active Const(x) begin
    if x isa Const
        Some(x.val)
    else
        nothing
    end
end

@active GotoNode(x) begin
    if x isa GotoNode
        Some(x.label)
    else
        nothing
    end
end

@active GotoIfNot(x) begin
    if x isa GotoIfNot
        x.cond, x.dest
    else
        nothing
    end
end

@active Signature(x) begin
    if x isa Signature && isdefined(x, :atype)
        x.f, x.ft, x.atypes, x.atype
    elseif x isa Signature
        x.f, x.ft, x.atypes
    else
        nothing
    end
end

# move this to Base?
Base.iterate(ic::Core.Compiler.IncrementalCompact) = Core.Compiler.iterate(ic)
Base.iterate(ic::Core.Compiler.IncrementalCompact, st) = Core.Compiler.iterate(ic, st)
Base.getindex(ic::Core.Compiler.IncrementalCompact, idx) = Core.Compiler.getindex(ic, idx)
Base.setindex!(ic::Core.Compiler.IncrementalCompact, v, idx) = Core.Compiler.setindex!(ic, v, idx)

Base.getindex(ic::Core.Compiler.Instruction, idx) = Core.Compiler.getindex(ic, idx)
Base.setindex!(ic::Core.Compiler.Instruction, v, idx) = Core.Compiler.setindex!(ic, v, idx)

Base.getindex(ir::Core.Compiler.IRCode, idx) = Core.Compiler.getindex(ir, idx)
Base.setindex!(ir::Core.Compiler.IRCode, v, idx) = Core.Compiler.setindex!(ir, v, idx)

Base.getindex(ref::UseRef) = Core.Compiler.getindex(ref)
Base.iterate(uses::UseRefIterator) = Core.Compiler.iterate(uses)
Base.iterate(uses::UseRefIterator, st) = Core.Compiler.iterate(uses, st)

@static if VERSION < v"1.7-"
Base.iterate(p::Core.Compiler.Pair) = Core.Compiler.iterate(p)
Base.iterate(p::Core.Compiler.Pair, st) = Core.Compiler.iterate(p, st)
end

Base.getindex(m::Core.Compiler.MethodLookupResult, idx::Int) = Core.Compiler.getindex(m, idx)

Base.length(x::Core.Compiler.BitSet) = Core.Compiler.length(x)
Base.iterate(x::Core.Compiler.BitSet) = Core.Compiler.iterate(x)
Base.iterate(x::Core.Compiler.BitSet, st) = Core.Compiler.iterate(x, st)
