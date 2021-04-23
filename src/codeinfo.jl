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

mutable struct SlotRecord
    slotnames::Vector{Symbol}
    newslotmap::Dict{Int, Symbol}
    changemap::Dict{Symbol, Int}
    counter::Int
end

function SlotRecord(ci::CodeInfo)
    slotnames = copy(ci.slotnames)
    newslotmap = Dict{Int, Symbol}()
    changemap = Dict{Symbol, Int}()
    SlotRecord(slotnames, newslotmap, changemap, 0)
end

struct NewSlotNumber
    id::Int
end

@active NewSlotNumber(x) begin
    if x isa NewSlotNumber
        Some(x.id)
    else
        nothing
    end
end

function Base.setindex!(rc::SlotRecord, slot::Symbol, v::Int)
    rc.slotnames[v] = slot
    return SlotNumber(v)
end

function Base.insert!(rc::SlotRecord, v::Int, slot::Symbol)
    insert!(rc.slotnames, v, slot)
    for k in v+1:length(rc.slotnames)
        name = rc.slotnames[k]
        rc.changemap[name] = get(rc.changemap, name, 0) + 1
    end

    id = rc.counter += 1
    rc.newslotmap[id] = slot
    return NewSlotNumber(id)
end

# let's not support this since it requires
# us to check if the slot number is used or not
Base.delete!(::SlotRecord, ::Int) = error("delete slot is not supported")


mutable struct StmtRecord
    counter::Int
    newssa::Dict{Int, Vector{NewSSAValue}}
    data::Dict{Int, Vector{Operation}}
end

StmtRecord() = StmtRecord(0, Dict{Int, Vector{NewSSAValue}}(), Dict{Int, Vector{Operation}}())

Base.getindex(rc::StmtRecord, v) = rc.data[v]
Base.haskey(rc::StmtRecord, v) = haskey(rc.data, v)
Base.iterate(rc::StmtRecord) = iterate(rc.data)
Base.iterate(rc::StmtRecord, st) = iterate(rc.data, st)

function Base.setindex!(rc::StmtRecord, stmt, v)
    push!(
        get!(rc.data, v, Operation[]),
        Operation(Setindex, stmt)
    )
    return stmt
end

function insert_before!(rc::StmtRecord, v, stmt)
    pushfirst!(
        get!(rc.data, v, Operation[]),
        Operation(Insert, stmt)
    )

    rc.counter += 1
    var = NewSSAValue(rc.counter) # length(code) + 1
    pushfirst!(get!(rc.newssa, v, NewSSAValue[]), var)
    return var
end

function insert_after!(rc::StmtRecord, v, stmt)
    push!(
        get!(rc.data, v, Operation[]),
        Operation(Insert, stmt)
    )

    rc.counter += 1
    var = NewSSAValue(rc.counter) # length(code) + 1
    push!(get!(rc.newssa, v, NewSSAValue[]), var)
    return var
end

function Base.delete!(rc::StmtRecord, v)
    push!(
        get!(rc.data, v, Operation[]),
        Operation(Delete, nothing)
    )
    return rc
end

mutable struct NewCodeInfo
    src::CodeInfo
    pc::Int # current SSAValue
    slots::SlotRecord
    stmts::StmtRecord
end

function NewCodeInfo(ci::CodeInfo)
    NewCodeInfo(ci, 1, SlotRecord(ci), StmtRecord())
end

Base.length(ci::NewCodeInfo) = length(ci.src.code)
Base.getindex(ci::NewCodeInfo, idx::Int) = ci.src.code[idx]
Base.eltype(::NewCodeInfo) = Tuple{Int, Any}

function Base.iterate(ci::NewCodeInfo, st::Int=1)
    if st > length(ci)
        ci.pc = 1
        return
    end

    ci.pc = st
    return (st, ci[st]), st + 1
end

function Base.setindex!(ci::NewCodeInfo, stmt, v::Int)
    ci.stmts[v] = stmt
    return stmt
end

function Base.insert!(ci::NewCodeInfo, v::Int, stmt)
    return insert_before!(ci.stmts, v, stmt)
end

function Base.delete!(ci::NewCodeInfo, v::Int)
    delete!(ci.stmts, v)
    return ci
end

function Base.push!(ci::NewCodeInfo, stmt)
    return insert_after!(ci.stmts, ci.pc, stmt)
end

function _emit_code_with_changemap(ci::NewCodeInfo)
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
    return code, codelocs, changemap
end

function emit_code(ci::NewCodeInfo)
    code, codelocs, changemap = _emit_code_with_changemap(ci)
    Core.Compiler.renumber_ir_elements!(code, changemap)
    # NOTE: this must after renumber_ir_elements!
    # since now the changemap is accumulated
    replace_new_ssavalue!(code, ci, changemap)
    return code, codelocs
end

function emit_slot_changemap(ci::NewCodeInfo)
    changemap = fill(0, length(ci.src.slotnames))

    for (old, name) in enumerate(ci.src.slotnames)
        if haskey(ci.slots.changemap, name)
            changemap[old] = ci.slots.changemap[name]
        end
    end

    newslotmap = Dict{Int, Int}()
    for (id, slot) in ci.slots.newslotmap
        newslotmap[id] = findfirst(isequal(slot), ci.slots.slotnames)
    end
    return newslotmap, changemap
end

function finish(ci::NewCodeInfo; inline::Bool=true)
    code, codelocs = emit_code(ci)
    newslotmap, changemap = emit_slot_changemap(ci)
    update_slots!(code, newslotmap, changemap)

    new_ci = copy(ci.src)
    new_ci.code = code
    new_ci.codelocs = codelocs
    new_ci.slotnames = ci.slots.slotnames
    new_ci.slotflags = [0x00 for _ in ci.slots.slotnames]
    new_ci.inferred = false # only supports untyped CodeInfo
    new_ci.inlineable = inline
    new_ci.ssavaluetypes = length(code)
    return new_ci
end

function update_slots!(code::Vector, newslotmap, changemap)
    for (v, stmt) in enumerate(code)
        code[v] = update_slots(stmt, newslotmap, changemap)
    end
    return code
end

function update_slots(e, newslotmap, changemap)
    @match e begin
        SlotNumber(id) => SlotNumber(id + changemap[id])
        NewSlotNumber(id) => SlotNumber(newslotmap[id])
        NewvarNode(SlotNumber(id)) => NewvarNode(SlotNumber(id+slotmap[id]))
        Expr(head, args...) => Expr(head, map(x->update_slots(x, newslotmap, changemap), e.args)...)
        _ => e
    end
end

function replace_new_ssavalue(e, newssamap)
    @match e begin
        NewSSAValue(id) => SSAValue(newssamap[id])
        GotoIfNot(NewSSAValue(id), dest) => GotoIfNot(SSAValue(newssamap[id]), dest)
        ReturnNode(NewSSAValue(id)) => ReturnNode(SSAValue(newssamap[id]))
        Expr(head, args...) => Expr(head, map(x->replace_new_ssavalue(x, newssamap), args)...)
        _ => e
    end
end

function newssamap(ci::NewCodeInfo, changemap::Vector{Int})
    d = Dict{Int, Int}()
    for v in 1:length(ci.src.code)
        ssa = v + changemap[v]
        haskey(ci.stmts.newssa, v) || continue
        newssavalues = ci.stmts.newssa[v]
        for (k, new) in enumerate(newssavalues)
            d[new.id] = ssa - length(newssavalues) + k - 1
        end
    end
    return d
end

function replace_new_ssavalue!(code::Vector, ci::NewCodeInfo, changemap::Vector{Int})
    map = newssamap(ci, changemap)
    for (v, stmt) in enumerate(code)
        code[v] = replace_new_ssavalue(stmt, map)
    end
    return code
end

function Base.map(f, ci::NewCodeInfo)
    for (v, stmt) in ci
        ci[v] = f(stmt)
    end
    return finish(ci)
end
