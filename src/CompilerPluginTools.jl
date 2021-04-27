module CompilerPluginTools

using MLStyle
using Expronicon

export
    # interp
    NewCodeInfo,
    NewSlotNumber,
    JuliaLikeInterpreter,
    AbstractInterpreter,
    isintrinsic,
    # reexport SSA nodes from Core
    MethodInstance,
    CodeInfo,
    SSAValue,
    Const,
    PartialStruct,
    Slot,
    GotoIfNot,
    GotoNode,
    SlotNumber,
    Argument,
    NewvarNode,
    ReturnNode,
    InferenceState,
    InferenceParams,
    MethodResultPure,
    CallMeta,
    widenconst,
    argtypes_to_type,
    # reexport IRCode types from Core
    NativeInterpreter,
    IRCode,
    IncrementalCompact,
    NewSSAValue,
    obtain_codeinfo,
    obtain_const,
    obtain_const_or_stmt,
    isconstType,
    compact!,
    # reflections
    code_ircode,
    code_ircode_by_mi,
    code_ircode_by_signature,
    method_instances,
    # builtin pass
    default_julia_pass,
    no_pass,
    # extra pass
    inline_const!,
    permute_stmts!,
    const_invoke!,
    finish,
    IntrinsicError,
    # utils
    method_instance,
    @make_codeinfo,
    @make_ircode,
    @test_codeinfo,
    @intrinsic_stub

using Base:
    method_instances

using Base.Meta: ParseError

using Core:
    CodeInfo,
    SSAValue,
    Const,
    PartialStruct,
    Slot,
    GotoIfNot,
    GotoNode,
    SlotNumber,
    Argument,
    NewvarNode,
    ReturnNode,
    IntrinsicFunction,
    Builtin

using Core.Compiler:
    MethodInstance,
    InferenceParams,
    InferenceResult,
    OptimizationParams,
    OptimizationState,
    Bottom,
    AbstractInterpreter,
    NativeInterpreter,
    VarTable,
    InferenceState,
    CFG,
    NewSSAValue,
    Signature,
    IRCode,
    InstructionStream,
    CallMeta,
    IncrementalCompact,
    JLOptions

using Core.Compiler:
    get_world_counter,
    get_inference_cache,
    # typeinf interfaces
    typeinf,
    # optimization interfaces
    run_passes,
    may_optimize,
    isconstType,
    isconcretetype,
    widenconst,
    isdispatchtuple,
    isinlineable,
    is_inlineable_constant,
    copy_exprargs,
    convert_to_ircode,
    coverage_enabled,
    argtypes_to_type,
    userefs,
    UseRefIterator,
    UseRef,
    MethodResultPure,
    is_pure_intrinsic_infer,
    intrinsic_nothrow,
    quoted,
    # Julia passes
    compact!,
    ssa_inlining_pass!,
    getfield_elim_pass!,
    adce_pass!,
    type_lift_pass!,
    verify_linetable,
    verify_ir,
    retrieve_code_info,
    slot2reg

include("utils.jl")
include("patches.jl")
include("codeinfo.jl")
include("interp.jl")
include("typeinf.jl")
include("ircode.jl")
include("passes.jl")
include("intrinsic.jl")

end
