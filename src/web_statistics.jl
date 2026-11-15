function finite_stats(values)
    count = 0
    first_value = min_value = Inf
    last_value = max_value = -Inf
    total = 0.0
    for value in values
        isfinite(value) || continue
        iszero(count) && (first_value = value)
        last_value = value
        min_value = min(min_value, value)
        max_value = max(max_value, value)
        total += value
        count += 1
    end
    iszero(count) && return nothing
    return (; first_value, last_value, min_value, max_value, mean_value = total / count, count)
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
        stats = finite_stats(values)
        isnothing(stats) && continue
        unit = get(units, key, "")
        unit isa AbstractDict && (unit = get(unit, name, ""))
        push!(rows, (; Series = key, Unit = isempty(unit) ? "—" : unit,
            var"First finite" = stats.first_value, var"Latest finite" = stats.last_value,
            Min = stats.min_value, Max = stats.max_value))
    end
    return rows
end

function statistics_cell_rows(model, state)
    domain = model isa Jutul.DataDomain ? model : JutulDarcy.reservoir_domain(model)
    nc = Jutul.number_of_cells(domain)
    fields = JutulDarcy.convert_for_plotting(isnothing(state) ? domain : state)
    rows = NamedTuple[]
    for key in sort!(collect(keys(fields)); by = string)
        values = fields[key]
        values isa AbstractVecOrMat{<:Real} && size(values, ndims(values)) == nc || continue
        components = values isa AbstractVector ? (values,) : eachrow(values)
        for (i, component) in enumerate(components)
            stats = finite_stats(component)
            isnothing(stats) && continue
            label = values isa AbstractVector ? string(key) : "$key [$i]"
            push!(rows, (; Property = label, Min = stats.min_value, Mean = stats.mean_value,
                Max = stats.max_value, var"Finite cells" = stats.count))
        end
    end
    return rows
end

function statistics_table(bonito, rows)
    isempty(rows) && return bonito.DOM.p("No finite values are available."; class = "stats-note")
    return bonito.Table(rows; class = "stats-table", row_renderer = stat_label, allow_row_sorting = false)
end

function statistics_content(bonito, session, results)
    DOM = bonito.DOM
    (; summary, reservoir, wells) = results
    metrics = []
    section = []
    if !isnothing(reservoir)
        (; model, states, steps) = reservoir
        domain = model isa Jutul.DataDomain ? model : JutulDarcy.reservoir_domain(model)
        push!(metrics, "Active cells" => Jutul.number_of_cells(domain))
        push!(metrics, "Reservoir reports" => length(steps))
        selection = bonito.Dropdown(0:length(steps); index = length(steps) + 1,
            option_to_string = i -> iszero(i) ? "Static properties" : "Report $(steps[i])",
            var"aria-label" = "Reservoir snapshot", class = "stats-report")
        table = map(session, selection.value) do i
            snapshot = iszero(i) ? nothing : states[i]
            statistics_table(bonito, statistics_cell_rows(model, snapshot))
        end
        push!(section, DOM.section(DOM.div(DOM.h3("Reservoir properties"), selection; class = "stats-heading"), table))
    end
    if has_well_results(wells)
        push!(metrics, "Wells with curves" => length(wells.wells))
    end
    sources = summary_sources(summary)
    if !isempty(sources)
        time = summary["TIME"].seconds
        push!(metrics, "Summary samples" => length(time), "Elapsed days" => last(time) / Jutul.si_unit(:day))
        choices = bonito.Dropdown(eachindex(sources); option_to_string = i -> sources[i][2],
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
        action == ["stats"] && !ready[] || return
        try
            content[] = statistics_content(bonito, session, results)
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
