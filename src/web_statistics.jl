function sample_statistics(values)
    samples = filter(isfinite, values)
    isempty(samples) && return nothing
    lo, hi = extrema(samples)
    total = sum(Float64, samples)
    first_value, last_value = first(samples), last(samples)
    return (; first_value, last_value, lo, hi, total, mean = total / length(samples), median = median!(samples))
end

stat_label(value::AbstractFloat) = string(round(value; sigdigits = 6))
stat_label(value) = string(value)

function statistics_summary_rows(summary, source)
    name, _, series = source
    units = get(summary, "UNITS", Dict())
    rows = NamedTuple[]
    for key in sort!(collect(keys(series)))
        values = series[key]
        values isa AbstractVector{<:Real} || continue
        stats = sample_statistics(values)
        isnothing(stats) && continue
        unit = get(units, key, "")
        unit isa AbstractDict && (unit = get(unit, name, ""))
        push!(rows, (; Series = key, Unit = isempty(unit) ? "—" : unit,
            First = stats.first_value, Latest = stats.last_value,
            Min = stats.lo, Mean = stats.mean, Median = stats.median, Max = stats.hi))
    end
    return rows
end

function statistics_static_fields(domain)
    fields = JutulDarcy.convert_for_plotting(domain)
    if haskey(domain, :volumes)
        filter!(pair -> first(split(string(first(pair)), " / "; limit = 2)) != "volumes", fields)
        fields[Symbol("Bulk volume / m³")] = domain[:volumes]
    end
    if haskey(fields, :PORV)
        # INIT properties keep the units in which the simulator wrote them.
        fields[Symbol("Pore volume (PORV)")] = pop!(fields, :PORV)
    else
        pv = if haskey(domain, :PORO) && !haskey(domain, :porosity) && haskey(domain, :volumes)
            ntg = haskey(domain, :NTG) ? domain[:NTG] : 1.0
            domain[:volumes] .* domain[:PORO] .* ntg
        elseif haskey(domain, :porosity) || haskey(domain, :pore_volume)
            JutulDarcy.pore_volume(domain; throw = false)
        else
            missing
        end
        ismissing(pv) || (fields[Symbol("Pore volume / m³")] = pv)
        delete!(fields, :pore_volume)
    end
    return fields
end

function statistics_cell_rows(domain, state)
    nc = Jutul.number_of_cells(domain)
    is_static = isnothing(state)
    fields = is_static ? statistics_static_fields(domain) : JutulDarcy.convert_for_plotting(state)
    rows = NamedTuple[]
    for key in sort!(collect(keys(fields)); by = string)
        values = fields[key]
        values isa AbstractVecOrMat{<:Real} && size(values, ndims(values)) == nc || continue
        components = values isa AbstractVector ? (values,) : eachrow(values)
        for (i, component) in enumerate(components)
            stats = sample_statistics(component)
            isnothing(stats) && continue
            label = values isa AbstractVector ? string(key) : "$key [$i]"
            row = (; Property = label, Min = stats.lo, Mean = stats.mean, Median = stats.median, Max = stats.hi)
            if is_static
                total = startswith(label, "Bulk volume") || startswith(label, "Pore volume") ? stats.total : ""
                row = (; row..., Total = total)
            end
            push!(rows, row)
        end
    end
    return rows
end

function statistics_table(bonito, rows)
    isempty(rows) && return bonito.DOM.p("No values are available."; class = "stats-note")
    return bonito.Table(rows; class = "stats-table", row_renderer = stat_label, allow_row_sorting = false)
end

function statistics_content(bonito, session, results; summary_index = nothing, report_index = nothing)
    DOM = bonito.DOM
    (; summary, reservoir, wells) = results
    metrics = []
    section = []
    if !isnothing(reservoir)
        (; model, states, steps) = reservoir
        domain = model isa Jutul.DataDomain ? model : JutulDarcy.reservoir_domain(model)
        push!(metrics, "Active cells" => Jutul.number_of_cells(domain))
        push!(metrics, "Reservoir reports" => length(steps))
        static_table = statistics_table(bonito, statistics_cell_rows(domain, nothing))
        push!(section, DOM.section(DOM.div(DOM.h3("Static reservoir properties"); class = "stats-heading"), static_table))
        if !isempty(steps)
            selection = bonito.Dropdown(eachindex(steps); index = clamp(something(report_index, length(steps)), 1, length(steps)),
                option_to_string = i -> "Report $(steps[i])",
                var"aria-label" = "Reservoir snapshot", class = "stats-report")
            table = map(session, selection.value) do i
                statistics_table(bonito, statistics_cell_rows(domain, states[i]))
            end
            push!(section, DOM.section(DOM.div(DOM.h3("Reservoir report"); class = "stats-heading"), table))
        end
    end
    if has_well_results(wells)
        push!(metrics, "Wells with curves" => length(wells.wells))
    end
    sources = summary_sources(summary)
    if !isempty(sources)
        time = summary["TIME"].seconds
        push!(metrics, "Summary samples" => length(time), "Elapsed days" => last(time) / Jutul.si_unit(:day))
        choices = bonito.Dropdown(eachindex(sources); index = clamp(something(summary_index, 1), 1, length(sources)),
            option_to_string = i -> sources[i][2],
            var"aria-label" = "Summary entity", class = "stats-entity")
        curves = map(session, choices.value) do i
            statistics_table(bonito, statistics_summary_rows(summary, sources[i]))
        end
        unit_system = uppercase(string(get(summary, "UNIT_SYSTEM", "")))
        units = isempty(unit_system) ? nothing : DOM.p("Summary unit system · $unit_system"; class = "stats-note")
        pushfirst!(section, DOM.section(DOM.div(DOM.h3("Summary curves"), choices; class = "stats-heading"), units, curves))
    elseif has_well_results(wells)
        push!(metrics, "Well samples" => length(wells.time), "Elapsed days" => last(wells.time) / Jutul.si_unit(:day))
    end
    overview = DOM.dl([DOM.div(DOM.dt(label), DOM.dd(stat_label(value))) for (label, value) in metrics]...;
        class = "stats-overview")
    return DOM.div(overview, section...; class = "stats-content")
end

function web_statistics_dialog(bonito, session, results, actions)
    DOM = bonito.DOM
    content = Makie.Observable{Any}(DOM.p("Calculating statistics…"; role = "status"))
    ready = Ref(false)
    bonito.on(session, actions) do action
        !isempty(action) && first(action) == "stats" && !ready[] || return
        try
            summary_index = length(action) >= 2 ? tryparse(Int, action[2]) : nothing
            report_index = length(action) >= 3 ? tryparse(Int, action[3]) : nothing
            content[] = statistics_content(bonito, session, results; summary_index, report_index)
            ready[] = true
        catch err
            err isa InterruptException && rethrow()
            content[] = DOM.p(sprint(showerror, err); role = "status")
        end
    end
    title = DOM.div(DOM.h2("Case statistics"), DOM.button("Close"; type = "button", class = "stats-close");
        class = "stats-heading")
    return DOM.dialog(title, DOM.div(content; class = "stats-body");
        class = "stats-dialog", var"aria-label" = "Case statistics")
end
