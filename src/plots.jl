struct Curve
    keyword::String
    description::String
    unit::String
    values::AbstractVector{<:Real}
end

struct CurveEntity
    name::String
    label::String
    curves::Vector{Curve}
end

function curve_catalog(summary, view)
    isnothing(summary) && return CurveEntity[]
    time = summary["TIME"].seconds
    isempty(time) && return CurveEntity[]
    values = summary["VALUES"]
    units = get(summary, "UNITS", nothing)
    system = lowercase(get(summary, "UNIT_SYSTEM", "si"))
    lookup = JutulDarcy.summary_key_lookup()
    entities = CurveEntity[]

    function add_entity(name, label, data; identity = nothing)
        curves = Curve[]
        for key in sort!(collect(keys(data)))
            samples = data[key]
            samples isa AbstractVector{<:Real} && length(samples) == length(time) || continue
            info = get(lookup, key, nothing)
            description = isnothing(info) ? key : "$key · $(uppercasefirst(info.legend))"
            unit = if !isnothing(units)
                entry = get(units, key, "")
                entry isa AbstractDict ? get(entry, identity, "") : entry
            elseif !isnothing(info) && system == "si"
                _, label = JutulDarcy.unit_system_unit_conversion(system, "", info.unit_type)
                info.is_rate && !isempty(label) ? "$label/s" : label
            else
                ""
            end
            push!(curves, Curve(key, description, strip(unit), samples))
        end
        isempty(curves) || push!(entities, CurveEntity(name, label, curves))
    end

    if view == :wells
        for (name, data) in sort!(collect(get(values, "WELLS", Dict())); by = first)
            add_entity(name, name, data; identity = name)
        end
    else
        add_entity("FIELD", "Field", get(values, "FIELD", Dict()))
        # The structured Eclipse format can also contain region, block, and
        # completion vectors. Group these by their declared summary identity.
        for (scope, prefix) in (("GROUP", "Group"), ("REGIONS", "Region"), ("BLOCKS", "Block"),
                ("COMPLETIONS", "Completion"), ("SEGMENTS", "Segment"), ("AQUIFERS", "Aquifer"), ("MISC", "Other"))
            unqualified = Dict{String, Any}()
            for (name, data) in sort!(collect(get(values, scope, Dict())); by = first)
                if data isa AbstractDict
                    add_entity(name, "$prefix $name", data; identity = name)
                else
                    unqualified[name] = data
                end
            end
            add_entity(prefix, prefix, unqualified)
        end
        # This also keeps well-only SMSPEC files usable in the summary view.
        for (name, data) in sort!(collect(get(values, "WELLS", Dict())); by = first)
            add_entity(name, "Well $name", data; identity = name)
        end
    end
    return entities
end

function initial_curve(entities; entity, series, view)
    isempty(entities) && throw(ArgumentError("No $(view == :wells ? "well curves" : "summary curves") are available."))
    entity_options = if isnothing(entity)
        eachindex(entities)
    else
        match = findall(e -> lowercase(entity) in (lowercase(e.name), lowercase(e.label)), entities)
        isempty(match) && throw(ArgumentError("Unknown entity $entity. Available: $(join(getfield.(entities, :label), ", "))"))
        length(match) == 1 || throw(ArgumentError("Use the full label to disambiguate $entity."))
        match
    end
    if !isnothing(series)
        for i in entity_options
            index = findfirst(c -> uppercase(series) == c.keyword, entities[i].curves)
            isnothing(index) || return i, index
        end
        throw(ArgumentError("Series $series is unavailable$(isnothing(entity) ? "" : " for $entity")."))
    end
    i = first(entity_options)
    preferred = view == :wells ? ("WBHP", "WOPR", "WWPR") : ("FPR", "FOPR", "FWPR", "WBHP")
    return i, preferred_index(entities[i].curves, preferred)
end

function preferred_index(curves, preferred)
    for key in preferred
        index = findfirst(c -> c.keyword == key, curves)
        isnothing(index) || return index
    end
    return 1
end

function curve_figure(summary, entities, name, view; interactive, entity = nothing, series = nothing, compact = false)
    i, j = initial_curve(entities; entity, series, view)
    time = summary["TIME"].seconds ./ Jutul.si_unit(:day)
    start_date = summary["TIME"].start_date
    xlabel = isnothing(start_date) || ismissing(start_date) ? "Elapsed time (days)" : "Days since $(first(split(string(start_date), 'T')))"
    fig = Makie.Figure(size = compact ? (420, 720) : (880, 480), backgroundcolor = :white)
    selected_entity = Makie.Observable(entities[i])
    selected_curve = Makie.Observable(entities[i].curves[j])
    title = Makie.lift(selected_entity) do item
        "$name · $(item.label)"
    end
    ylabel = Makie.lift(selected_curve) do curve
        isempty(curve.unit) ? curve.description : "$(curve.description) ($(curve.unit))"
    end
    plot_position = if compact
        fig[interactive ? 3 : 1, 1]
    else
        fig[interactive ? 2 : 1, 1:2]
    end
    ax = Makie.Axis(plot_position; title, xlabel, ylabel, xgridcolor = :gray90, ygridcolor = :gray90)
    samples = Makie.lift(c -> c.values, selected_curve)
    Makie.scatterlines!(ax, time, samples; color = :teal, linewidth = 2.5,
        markersize = length(time) <= 30 ? 7 : 0)

    if interactive
        entity_menu = Makie.Menu(fig[1, 1]; options = getfield.(entities, :label), default = i)
        series_menu = Makie.Menu(compact ? fig[2, 1] : fig[1, 2];
            options = getfield.(entities[i].curves, :description), default = j)
        Makie.on(entity_menu.i_selected) do index
            index == 0 && return
            item = entities[index]
            previous = selected_curve[].keyword
            selected_entity[] = item
            series_menu.options[] = getfield.(item.curves, :description)
            series_menu.i_selected[] = preferred_index(item.curves, (previous, "WBHP", "FPR"))
        end
        Makie.on(series_menu.i_selected) do index
            if index > 0
                selected_curve[] = selected_entity[].curves[index]
                Makie.autolimits!(ax)
            end
        end
    end
    return fig
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

function reservoir_figure(reservoir, name; interactive, field = nothing, step = 1, row = 1)
    (; model, states, steps, wells) = reservoir
    if !(1 <= step <= max(length(steps), 1))
        throw(ArgumentError("Step $step is out of range. Available plot steps: 1:$(length(steps))."))
    end
    domain = model isa Jutul.DataDomain ? model : JutulDarcy.reservoir_domain(model)
    nc = Jutul.number_of_cells(domain)
    if interactive
        states = explorer_states(states, nc)
    end
    static = JutulDarcy.convert_for_plotting(domain)
    snapshot = ismissing(states) ? Dict() : JutulDarcy.convert_for_plotting(states[step])
    properties = merge(static, snapshot)
    keys_to_plot = sort!(filter(collect(keys(properties))) do key
        values = properties[key]
        return values isa AbstractVecOrMat{<:Real} && size(values, ndims(values)) == nc && any(isfinite, values)
    end; by = string)
    isempty(keys_to_plot) && throw(ArgumentError("The reservoir has no plottable cell properties."))

    field_label(k) = first(split(string(k), " / "; limit = 2))
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
    if interactive
        explorer = JutulDarcy.plot_reservoir(model, states; step, key, title = name, wells)
        return explorer.fig
    end

    values = properties[key]
    nrows = values isa AbstractMatrix ? size(values, 1) : 1
    1 <= row <= nrows || throw(ArgumentError("Cell property $key has $nrows components. Requested row $row."))
    fig = JutulDarcy.plot_reservoir(model, states; gui = false, fancy = false, key, step, row,
        resolution = (820, 500), colorbar = :vertical, wells)
    caption = String[name, string(key)]
    nrows > 1 && push!(caption, "Component $row")
    haskey(snapshot, key) && push!(caption, "Report $(steps[step])")
    Makie.Label(fig[0, 1:2], join(caption, " · "); fontsize = 19)
    return fig
end
