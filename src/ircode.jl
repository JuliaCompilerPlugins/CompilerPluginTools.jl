# copied & modified from brutus

"""
    code_ircode_by_signature([pass, ]sig; world=get_world_counter(), interp=NativeInterpreter(world))

Get `IRCode` by given signature, one can use the first argument to transform the `IRCode` during interpretation.
"""
function code_ircode_by_signature(pass, @nospecialize(sig); world=get_world_counter(), interp=NativeInterpreter(world))
    return map(Base._methods_by_ftype(sig, -1, world)) do data
        mi = ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance}, (Any, Any, Any), data[3], data[1], data[2])
        code_ircode_by_mi(pass, mi; world, interp)
    end
end

function code_ircode_by_signature(@nospecialize(sig); world=get_world_counter(), interp=NativeInterpreter(world))
    return code_ircode_by_signature(default_julia_pass, sig; world, interp)
end

"""
    code_ircode([pass, ]f, types; world=get_world_counter(), interp=NativeInterpreter(world))

Get `IRCode` by given function `f` and its argument types `types`. An option argument `pass`
can be specified as a transform function on IRCode during type inference.
"""
function code_ircode(@nospecialize(f), @nospecialize(types); world=get_world_counter(), interp=NativeInterpreter(world))
    return code_ircode(default_julia_pass, f, types; world, interp)
end

function code_ircode(@nospecialize(pass), @nospecialize(f), @nospecialize(types); world=get_world_counter(), interp=NativeInterpreter(world))
    return [code_ircode_by_mi(pass, mi; world, interp) for mi in method_instances(f, types, world)]
end

"""
    code_ircode_by_mi(f, mi::MethodInstance; world=get_world_counter(), interp=NativeInterpreter(world))

Return the `IRCode` object along with inferred return type.

# Arguments

- `f(ir::IRCode, sv::OptimizationState) -> IRCode`: optimization passes to run.
- `mi::MethodInstance`: method instance.

# Kwargs

- `world::Int`: world number, default is calling `Core.Compiler.get_world_counter`.
- `interp::AbstractInterpreter`: the interpreter to use for inference.
"""
function code_ircode_by_mi(f, mi::MethodInstance; world=get_world_counter(), interp=NativeInterpreter(world))
    return typeinf_lock() do
        result = Core.Compiler.InferenceResult(mi)
        @static if VERSION < v"1.8-"
            frame = Core.Compiler.InferenceState(result, false, interp)
        else
            frame = Core.Compiler.InferenceState(result, :local, interp)
        end
        frame === nothing && return nothing

        if typeinf(interp, frame)
            opt_params = OptimizationParams(interp)
            sv = OptimizationState(frame, opt_params, interp)
            preserve_coverage = coverage_enabled(sv.mod)
            @static if VERSION < v"1.8-"
                ci = sv.src; nargs = sv.nargs - 1;
                ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, sv)
                ir = slot2reg(ir, ci, nargs, sv)
            else
                ci = sv.src
                ir = convert_to_ircode(ci, sv)
                ir = slot2reg(ir, ci, sv)
            end
            # passes
            ir = f(ir, sv)
            sv.src.inferred = true
        end

        frame.inferred || return nothing
        @static if VERSION < v"1.8-"
            resize!(ir.argtypes, sv.nargs)
        else
            svdef = sv.linfo.def
            nargs = isa(svdef, Method) ? Int(svdef.nargs) : 0
            resize!(ir.argtypes, nargs)
        end
        return ir => widenconst(result.result)
    end
end

"""
    code_ircode_by_mi(mi::MethodInstance; world=get_world_counter(), interp=NativeInterpreter(world))

The default `code_ircode_by_mi` that uses the default Julia compiler optimization passes.
See also [`code_ircode_by_mi`](@ref).
"""
function code_ircode_by_mi(mi::MethodInstance; world=get_world_counter(), interp=NativeInterpreter(world))
    return code_ircode_by_mi(default_julia_pass, mi; world, interp)
end
