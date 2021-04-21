"""
    JuliaLikeInterpreter <: AbstractInterpreter

Abstract type for julia-like interpreter. The subtype of it usually
modifies the native julia interpreter a little bit by overloading
certain abstract interpretation interface, but forward most of the
interfaces to the native interpreter.
"""
abstract type JuliaLikeInterpreter <: AbstractInterpreter end

"""
    parent(interp::JuliaLikeInterpreter)

Return the native interpreter of Julia.
"""
Base.parent(interp::JuliaLikeInterpreter) = interp.native_interpreter

Core.Compiler.InferenceParams(interp::JuliaLikeInterpreter) = InferenceParams(interp.native_interpreter)
Core.Compiler.OptimizationParams(interp::JuliaLikeInterpreter) = OptimizationParams(interp.native_interpreter)
Core.Compiler.get_world_counter(interp::JuliaLikeInterpreter) = get_world_counter(interp.native_interpreter)
Core.Compiler.get_inference_cache(interp::JuliaLikeInterpreter) =
    get_inference_cache(interp.native_interpreter)
Core.Compiler.code_cache(interp::JuliaLikeInterpreter) = Core.Compiler.code_cache(interp.native_interpreter)
Core.Compiler.may_optimize(interp::JuliaLikeInterpreter) =
    Core.Compiler.may_optimize(interp.native_interpreter)
Core.Compiler.may_discard_trees(interp::JuliaLikeInterpreter) =
    Core.Compiler.may_discard_trees(interp.native_interpreter)
Core.Compiler.may_compress(interp::JuliaLikeInterpreter) =
    Core.Compiler.may_compress(interp.native_interpreter)
Core.Compiler.unlock_mi_inference(interp::JuliaLikeInterpreter, mi::Core.MethodInstance) =
    Core.Compiler.unlock_mi_inference(interp.native_interpreter, mi)
Core.Compiler.lock_mi_inference(interp::JuliaLikeInterpreter, mi::Core.MethodInstance) =
    Core.Compiler.lock_mi_inference(interp.native_interpreter, mi)
Core.Compiler.add_remark!(::JuliaLikeInterpreter, ::Core.Compiler.InferenceState, ::String) =
    nothing # println(msg)
@static if VERSION >= v"1.7.0-DEV.577"
    Core.Compiler.verbose_stmt_info(::JuliaLikeInterpreter) = false
end

function Core.Compiler.optimize(interp::JuliaLikeInterpreter, opt::OptimizationState, params::OptimizationParams, @nospecialize(result))
    nargs = Int(opt.nargs) - 1
    ir = Core.Compiler.run_passes(opt.src, nargs, opt)
    ir = optimize(interp, opt, ir)
    if VERSION < v"1.7-DEV"
        Core.Compiler.finish(opt, params, ir, result)
    else
        Core.Compiler.finish(interp, opt, params, ir, result)
    end
end

"""
    optimize(interp::JuliaLikeInterpreter[, state::OptimizationState], ir::IRCode)

This method is for overloading, it will be executed after running Julia optimizers.
If you wish to customize the default Julia optimization passes, consider overloading
`Core.Compiler.optimize(interp, opt, params, result)`.
"""
function optimize end
optimize(interp::JuliaLikeInterpreter, ::OptimizationState, ir::IRCode) = optimize(interp, ir)
optimize(::JuliaLikeInterpreter, ir::IRCode) = ir
