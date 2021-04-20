# MLStyle patches
@active Argument(x) begin
    if x isa Argument
        Some(x.n)
    else
        nothing
    end
end

@active SSAValue(x) begin
    if x isa SSAValue
        Some(x.id)
    else
        nothing
    end
end

@active SlotNumber(x) begin
    if x isa SlotNumber
        Some(x.id)
    else
        nothing
    end
end
