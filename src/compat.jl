@static if VERSION < v"1.7-"
    ismutabletype(::Type{T}) where T = T.mutable
end
