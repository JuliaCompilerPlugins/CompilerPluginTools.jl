"""
    @make_codeinfo begin
        <stmt>::<type>
    end

Create a typed `CodeInfo` object, if field `<type>` is not specified, it will
use `Any`.
"""
macro make_codeinfo(ex)
    esc(make_codeinfo_m(ex))
end

"""
    @make_ircode begin
        <stmt>::<type>
    end

Create a typed `IRCode` object, if field `<type>` is not specified, it will
use `Any`. See also [`make_codeinfo`](@ref).
"""
macro make_ircode(ex)
    quote
        let
            ci = $(make_codeinfo_m(ex))
            Core.Compiler.inflate_ir(ci)
        end
    end |> esc
end

function make_codeinfo_m(ex)
    Meta.isexpr(ex, :block) || error("expect a begin ... end")
    
    code = Expr(:ref, :Any)
    ssavaluetypes = Expr(:ref, :Any)

    for each in ex.args
        @switch each begin
            @case :($stmt::$type)
                push!(code.args, stmt)
                push!(ssavaluetypes.args, type)
            @case ::LineNumberNode
                continue
            @case _
                push!(code.args, each)
                push!(ssavaluetypes.args, :Any)
        end
    end

    @gensym ci nstmts
    quote
        let ci = (Meta.@lower 1 + 1).args[1]
            ci.code = $code
            nstmts = length(ci.code)
            ci.ssavaluetypes = $ssavaluetypes
            ci.codelocs = fill(Int32(1), nstmts)
            ci.ssaflags = fill(Int32(0), nstmts)
            ci
        end
    end
end

