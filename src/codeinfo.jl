
# """
#     obtain_const_or_stmt(@nospecialize(x), ci::CodeInfo) -> (value/stmt, type)

# Return the value or the statement of given object. If it's `SSAValue`
# return the corresponding value or statement and its type. If the `CodeInfo`
# is not inferred yet, type will be nothing.
# """
# function obtain_const_or_stmt(@nospecialize(x), ci::CodeInfo)
#     if x isa SSAValue
#         return obtain_ssa(x, ci)
#     elseif x isa QuoteNode
#         return x.value, typeof(x.value)
#     elseif x isa Const
#         return x.val, typeof(x.val)
#     elseif x isa GlobalRef
#         if isdefined(x.mod, x.name) && isconst(x.mod, x.name)
#             val = getfield(x.mod, x.name)
#         else
#             # TODO: move this to parsing time
#             throw(UndefVarError(x.name))
#         end

#         return val, typeof(val)
#     else
#         # special value
#         return x, typeof(x)
#     end
# end

# function obtain_ssa(x::SSAValue, ci::CodeInfo)
#     stmt = ci.code[x.id]
#     if ci.ssavaluetypes isa Int
#         # CI is not inferenced yet
#         return stmt, nothing
#     else
#         typ = ci.ssavaluetypes[x.id]
#     end

#     if typ isa Const
#         return typ.val, typeof(typ.val)
#     else
#         return stmt, widenconst(typ)
#     end
# end

# """
#     obtain_const(x, ci::CodeInfo)

# Return the corresponding constant value of `x`, when `x` is
# a `SSAValue`, return the corresponding value of `x`. User should
# make sure `x` is actually a constant, or the return value can be
# a statement.
# """
# obtain_const(@nospecialize(x), ci::CodeInfo) = obtain_const_or_stmt(x, ci)[1]

@enum OperationType begin
    Insert
    Setindex
    Push
    Delete
end

struct Operation
    type::OperationType
    stmt
end

struct Record
    operations::Dict{Int, Vector{Operation}} # Insert/Setindex
end

Record() = Record(Dict{Int, Vector{Operation}}())

Base.getindex(rc::Record, v) = rc.operations[v]
Base.haskey(rc::Record, v) = haskey(rc.operations, v)

function Base.setindex!(rc::Record, stmt, v)
    push!(
        get!(rc.operations, v, Operation[]),
        Operation(Setindex, stmt)
    )
    return stmt
end

function Base.insert!(rc::Record, v, stmt)
    push!(
        get!(rc.operations, v, Operation[]),
        Operation(Insert, stmt)
    )
    return rc
end

function Base.delete!(rc::Record, v)
    push!(
        get!(rc.operations, v, Operation[]),
        Operation(Delete, nothing)
    )
    return rc
end

mutable struct NewCodeInfo
    src::CodeInfo
    pc::Int # current SSAValue
    slots::Record
    stmts::Record
end

function NewCodeInfo(ci::CodeInfo)
    NewCodeInfo(ci, 0, Record(), Record())
end

Base.length(ci::NewCodeInfo) = length(ci.src.code)
Base.getindex(ci::NewCodeInfo, idx::Int) = ci.src.code[idx]
Base.eltype(::NewCodeInfo) = Tuple{Int, Any}

function Base.iterate(ci::NewCodeInfo, st::Int=1)
    st > length(ci) && return
    ci.pc += 1
    return (st, ci[st]), st + 1
end

function Base.setindex!(ci::NewCodeInfo, stmt, v::Int)
    ci.stmts[v] = stmt
    return stmt
end

function Base.insert!(ci::NewCodeInfo, v::Int, stmt)
    insert!(ci.stmts, v, stmt)
    ci.pc += 1
    return NewSSAValue(ci.pc-1) # length(code) + 1
end

function Base.delete!(ci::NewCodeInfo, v::Int)
    ci.pc -= 1
    delete!(ci.stmts, v)
    return ci
end

function Base.push!(ci::NewCodeInfo, stmt)
    ci.stmts[ci.pc] = Operation(Push, stmt)
    return ci
end

function emit_slotnames_and_code(ci::NewCodeInfo)
    changemap = fill(0, length(ci))
    code, codelocs = [], Int32[]

    for (v, stmt) in enumerate(ci.src.code)
        loc = ci.src.codelocs[v]

        if !haskey(ci.stmts, v)
            push!(code, stmt)
            push!(codelocs, loc)
            continue
        end

        need_push = true
        for op in ci.stmts[v]
            if op.type == Insert
                push!(code, op.stmt)
                push!(codelocs, loc)
                changemap[v] += 1
            elseif op.type == Setindex # replace the old one
                push!(code, op.stmt)
                push!(codelocs, loc)
                need_push = false
            elseif op.type == Push
                push!(code, op.stmt)
                push!(codelocs, loc)
                need_push = false
            elseif op.type == Delete
                changemap[v] -= 1
                need_push = false
                continue
            else
                error("unknown operation")
            end
        end

        if need_push
            push!(code, stmt)
            push!(codelocs, loc)
        end
    end

    Core.Compiler.renumber_ir_elements!(code, changemap)
    replace_new_ssavalue!(code)
    return code, codelocs
end

function emit_new_slotinfo(ci::NewCodeInfo)
    newslots = Dict{Int,Symbol}()
    slotnames = copy(ci.src.slotnames)
    changemap = fill(0, length(ci))

    for (v, slot) in ci.slots.operations
        if slot.type == Insert
            newslots[v] = slot.stmt
            insert!(slotnames, v, slot)
            prev = length(filter(x -> x < v, keys(newslots)))
            for k in v-prev:length(slotmap)
                slotmap[k] += 1
            end
        elseif slot.type == Push || slot.type == Setindex
            slotnames[v] = slot
        elseif slot.type == Delete
            error("delete is not supported for slot")
        else
            error("unknown operation for slots: $(slot.type)")
        end
    end

    return slotnames, changemap
end

function finish(ci::NewCodeInfo; inline::Bool=true)
    code, codelocs = emit_slotnames_and_code(ci)
    slotnames, slotmap = emit_new_slotinfo(ci)
    update_slots!(code, slotmap)

    new_ci = copy(ci.src)
    new_ci.code = code
    new_ci.codelocs = codelocs
    new_ci.slotnames = slotnames
    new_ci.slotflags = [0x00 for _ in slotnames]
    new_ci.inferred = false # only supports untyped CodeInfo
    new_ci.inlineable = inline
    new_ci.ssavaluetypes = length(code)
    return new_ci
end

function update_slots!(code::Vector, slotmap)
    for (v, stmt) in enumerate(code)
        code[v] = update_slots(stmt, slotmap)
    end
    return code
end

function update_slots(e, slotmap)
    @match e begin
        SlotNumber(id) => SlotNumber(id + slotmap[id])
        NewvarNode(SlotNumber(id)) => NewvarNode(SlotNumber(id+slotmap[id]))
        Expr(head, args...) => Expr(head, map(x->update_slots(x, slotmap), e.args)...)
        _ => e
    end
end

function replace_new_ssavalue(e)
    @match e begin
        NewSSAValue(id) => SSAValue(id)
        GotoIfNot(NewSSAValue(id), dest) => GotoIfNot(SSAValue(id), dest)
        ReturnNode(NewSSAValue(id)) => ReturnNode(SSAValue(id))
        Expr(head, args...) => Expr(head, map(replace_new_ssavalue, args)...)
        _ => e
    end
end

function replace_new_ssavalue!(code::Vector)
    for (v, stmt) in enumerate(code)
        code[v] = replace_new_ssavalue(stmt)
    end
    return code
end

Base.map(f, ci::CodeInfo) = map(f, NewCodeInfo(ci))

function Base.map(f, ci::NewCodeInfo)
    for (v, stmt) in ci
        ci[v] = f(stmt)
    end
    return finish(ci)
end
