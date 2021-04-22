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

    intrinsic_stub = if isdefined(mod, :INTRINSIC_STUB)
        nothing
    else
        quote
            const INTRINSIC_STUB = Symbol[]
            isintrinsic(name) = name in INTRINSIC_STUB
        end
    end

    quote
        $intrinsic_stub
        push!(INTRINSIC_STUB, $(QuoteNode(jlfn.name)))
        @noinline $(codegen_ast(jlfn))
    end
end
