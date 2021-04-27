struct IntrinsicError <: Exception
    msg::String
end

macro intrinsic_stub(ctxname::Symbol, ex::Expr)
    esc(intrinsic_stub_m(__module__, ctxname, ex))
end

function intrinsic_stub_m(mod::Module, ctxname::Symbol, ex::Expr)
    @match ex begin
        Expr(:call, ::Symbol, Expr(:parameters, _...), _...) => error("syntax: stub cannot have kwargs")
        Expr(:call, ::Symbol, args...) => nothing
        _ => error("syntax: expect function call")
    end

    msg = "$(ex.args[1]) must be executed inside @$ctxname"
    jlfn = JLFunction(;
        name=ex.args[1],
        args=ex.args[2:end],
        body=quote
            throw($CompilerPluginTools.IntrinsicError($msg))
        end
    )

    isintrinsic_def = if isdefined(mod, :__INTRINSICS__)
        nothing
    else
        quote
            const __INTRINSICS__ = Set{Any}()
            isintrinsic(x) = x in __INTRINSICS__
        end
    end

    quote
        $isintrinsic_def
        @noinline $(codegen_ast(jlfn))
        push!(__INTRINSICS__, $(jlfn.name))
    end
end
