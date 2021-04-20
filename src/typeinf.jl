"""
    typeinf_lock(f)

Type inference lock. This prevents you from recursing into type inference when you don't want.
equivalent to the following code, which you may see in Julia compiler implementation.

```julia
ccall(:jl_typeinf_begin, Cvoid, ())
ret = f()
ccall(:jl_typeinf_end, Cvoid, ())
return ret
```
"""
function typeinf_lock(f)
    ccall(:jl_typeinf_begin, Cvoid, ())
    ret = f()
    ccall(:jl_typeinf_end, Cvoid, ())
    return ret
end
