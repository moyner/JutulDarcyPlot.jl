function add_completion!(wells, name, ijk, logical_cells, cell_map)
    checkbounds(Bool, logical_cells, ijk...) || return
    cell = cell_map[logical_cells[ijk...]]
    cell > 0 || return
    push!(get!(Vector{Int}, wells, name), cell)
    return nothing
end

function add_restart_completions!(wells, report, logical_cells, cell_map)
    header = get(report, "INTEHEAD", Int[])
    # Eclipse's one-based INTEHEAD positions for the counts and record strides.
    nwells, max_completions = get(header, 17, 0), get(header, 18, 0)
    int_stride, name_stride, conn_stride = get(header, 25, 0), get(header, 28, 0), get(header, 33, 0)
    nwells > 0 && max_completions > 0 && int_stride >= 5 && name_stride > 0 && conn_stride >= 4 || return
    iwel = get(report, "IWEL", Int[])
    zwel = get(report, "ZWEL", String[])
    icon = get(report, "ICON", Int[])
    # Empty or truncated well tables should never prevent plotting cell results.
    length(iwel) ÷ int_stride >= nwells && length(zwel) ÷ name_stride >= nwells &&
        length(icon) ÷ conn_stride ÷ max_completions >= nwells || return
    for w in 1:nwells
        name = strip(zwel[(w - 1) * name_stride + 1])
        isempty(name) && continue
        nconnections = clamp(iwel[(w - 1) * int_stride + 5], 0, max_completions)
        for c in 1:nconnections
            offset = ((w - 1) * max_completions + c - 1) * conn_stride
            ijk = (icon[offset + 2], icon[offset + 3], icon[offset + 4])
            add_completion!(wells, name, ijk, logical_cells, cell_map)
        end
    end
    return nothing
end

function add_deck_completions!(wells, deck, logical_cells, cell_map)
    schedule = get(deck, "SCHEDULE", nothing)
    isnothing(schedule) && return
    specs = get(schedule, "WELSPECS", Dict())
    for step in get(schedule, "STEPS", ())
        for (name, i, j, k1, k2) in get(step, "COMPDAT", ())
            if (i < 1 || j < 1) && haskey(specs, name)
                head = specs[name].head
                i = i < 1 ? head[1] : i
                j = j < 1 ? head[2] : j
            end
            for k in max(1, k1):min(size(logical_cells, 3), k2)
                add_completion!(wells, name, (i, j, k), logical_cells, cell_map)
            end
        end
    end
    return nothing
end
