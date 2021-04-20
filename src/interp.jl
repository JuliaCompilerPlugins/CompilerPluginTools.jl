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
Core.Compiler.add_remark!(interp::JuliaLikeInterpreter, st::Core.Compiler.InferenceState, msg::String) =
    nothing # println(msg)
