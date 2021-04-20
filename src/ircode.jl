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

Base.iterate(p::Core.Compiler.Pair) = Core.Compiler.iterate(p)
Base.iterate(p::Core.Compiler.Pair, st) = Core.Compiler.iterate(p, st)

Base.getindex(m::Core.Compiler.MethodLookupResult, idx::Int) = Core.Compiler.getindex(m, idx)

# copied & modified from brutus
function code_ircode_by_signature(pass, @nospecialize(sig); world=get_world_counter(), interp=NativeInterpreter(world))
    mi = ccall(:jl_specializations_get_linfo, Ref{Core.MethodInstance}, (Any, Any, Any), data[3], data[1], data[2])
    return [code_ircode_by_mi(pass, mi; world, interp) for data in Base._methods_by_ftype(sig, -1, world)]
end

function code_ircode_by_signature(@nospecialize(sig); world=get_world_counter(), interp=NativeInterpreter(world))
    return code_ircode_by_signature(default_julia_pass, sig; world, interp)
end

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
        frame = Core.Compiler.InferenceState(result, false, interp)
        frame === nothing && return nothing

        if typeinf(interp, frame)
            opt_params = OptimizationParams(interp)
            opt = OptimizationState(frame, opt_params, interp)
            preserve_coverage = coverage_enabled(opt.mod)
            ci = opt.src; nargs = opt.nargs - 1;
            ir = convert_to_ircode(ci, copy_exprargs(ci.code), preserve_coverage, nargs, opt)
            ir = slot2reg(ir, ci, nargs, opt)
            # passes
            ir = f(ir, opt)
            opt.src.inferred = true
        end

        frame.inferred || return nothing
        # TODO(yhls): Fix this upstream
        resize!(ir.argtypes, opt.nargs)
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

include("pass/const_prop.jl")