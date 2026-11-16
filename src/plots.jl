function summary_sources(summary)
    sources = Tuple{String, String, AbstractDict}[]
    (isnothing(summary) || isempty(summary["TIME"].seconds)) && return sources
    values = summary["VALUES"]
    field = get(values, "FIELD", Dict())
    isempty(field) || push!(sources, ("FIELD", "Field", field))
    for (scope, label) in (("GROUP", "Group"), ("WELLS", "Well"))
        for (name, data) in sort!(collect(get(values, scope, Dict())); by = first)
            isempty(data) || push!(sources, (name, "$label $name", data))
        end
    end
    return sources
end

function initial_summary_plot(sources; entity, series)
    if !isnothing(entity)
        sources = filter(s -> lowercase(entity) in (lowercase(s[1]), lowercase(s[2])), sources)
        isempty(sources) && throw(ArgumentError("Unknown summary entity $entity."))
        length(sources) == 1 || throw(ArgumentError("Use the full label to disambiguate $entity."))
    end
    if !isnothing(series)
        key = uppercase(series)
        for (name, _, data) in sources
            haskey(data, key) && return "$name:$key"
        end
        throw(ArgumentError("Series $series is unavailable$(isnothing(entity) ? "" : " for $entity")."))
    end
    name, _, data = first(sources)
    for key in ("FPR", "FOPR", "FWPR", "WBHP")
        haskey(data, key) && return "$name:$key"
    end
    return "$name:$(minimum(keys(data)))"
end

function summary_layout(sources, args)
    isempty(sources) && throw(ArgumentError("No field, group, or well summary curves are available."))
    plots = args[:plots]
    if isempty(plots)
        plots = [initial_summary_plot(sources; entity = get(args, :entity, nothing), series = get(args, :series, nothing))]
    end
    rows = args[:rows]
    cols = something(args[:columns], isnothing(rows) ? 1 : cld(length(plots), rows))
    rows = something(rows, cld(length(plots), cols))
    cld(length(plots), rows) <= cols || throw(ArgumentError("$(length(plots)) summary panels do not fit in $rows rows and $cols columns."))
    return (; plots, rows, cols)
end

function summary_figure(summary, name, layout; interactive)
    return JutulDarcy.plot_summary(summary; names = [name], selectors = interactive, layout...)
end

function explorer_states(states, nc)
    ismissing(states) && return missing
    # Jutul's explorer uses one set of field names and color ranges for every
    # report. PNGs can also plot properties present in only one report.
    shared = Set(keys(first(states)))
    for state in Iterators.drop(states, 1)
        intersect!(shared, keys(state))
    end
    filter!(shared) do key
        return all(states) do state
            value = state[key]
            value isa AbstractVecOrMat{<:Real} && size(value, ndims(value)) == nc && all(isfinite, value)
        end
    end
    isempty(shared) && return missing
    return [Dict(key => state[key] for key in shared) for state in states]
end

function reservoir_figure(reservoir, name; interactive, field = nothing, step = 1, row = 1,
        return_explorer = false, static_only = false, plot_options = NamedTuple())
    (; model, states, steps, wells) = reservoir
    if !(1 <= step <= max(length(steps), 1))
        throw(ArgumentError("Step $step is out of range. Available plot steps: 1:$(length(steps))."))
    end
    domain = model isa Jutul.DataDomain ? model : JutulDarcy.reservoir_domain(model)
    nc = Jutul.number_of_cells(domain)
    if static_only
        states = missing
    elseif interactive
        states = explorer_states(states, nc)
    end
    convert_data(x) = JutulDarcy.convert_for_plotting(x; units = get(plot_options, :unit_system, "metric"))
    static = convert_data(domain)
    snapshot = ismissing(states) ? Dict() : convert_data(states[step])
    properties = merge(static, snapshot)
    keys_to_plot = sort!(filter(collect(keys(properties))) do key
        values = properties[key]
        return values isa AbstractVecOrMat{<:Real} && size(values, ndims(values)) == nc && any(isfinite, values)
    end; by = string)
    isempty(keys_to_plot) && throw(ArgumentError("The reservoir has no plottable cell properties."))

    field_label(k) = first(split(string(k), " / "; limit = 2))
    component = interactive && !isnothing(field) ? match(r"^(.*) row ([1-9][0-9]*)$", field) : nothing
    if !isnothing(component)
        field, row = component.captures[1], parse(Int, component.captures[2])
    end
    if isnothing(field)
        preferred = ismissing(states) ? ("poro", "porosity", "volumes") : ("pressure", "swat", "saturations")
        index = nothing
        for candidate in preferred
            index = findfirst(k -> lowercase(field_label(k)) == candidate, keys_to_plot)
            isnothing(index) || break
        end
        key = keys_to_plot[something(index, 1)]
    else
        index = findfirst(k -> lowercase(field) in (lowercase(field_label(k)), lowercase(string(k))), keys_to_plot)
        isnothing(index) && throw(ArgumentError("Unknown cell property $field at step $step. Available: $(join(keys_to_plot, ", "))"))
        key = keys_to_plot[index]
    end
    values = properties[key]
    nrows = values isa AbstractMatrix ? size(values, 1) : 1
    1 <= row <= nrows || throw(ArgumentError("Cell property $key has $nrows components. Requested row $row."))
    if interactive
        explorer_key = values isa AbstractMatrix ? "$key row $row" : key
        explorer = JutulDarcy.plot_reservoir(model, states; step, key = explorer_key, title = name, wells, plot_options...)
        return return_explorer ? explorer : explorer.fig
    end

    fig = JutulDarcy.plot_reservoir(model, states; gui = false, fancy = false, key, step, row,
        resolution = (820, 500), colorbar = :vertical, wells)
    caption = String[name, string(key)]
    nrows > 1 && push!(caption, "Component $row")
    haskey(snapshot, key) && push!(caption, "Report $(steps[step])")
    Makie.Label(fig[0, 1:2], join(caption, " · "); fontsize = 19)
    return fig
end
