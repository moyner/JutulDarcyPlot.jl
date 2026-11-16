const RESERVOIR_COLORMAPS = ("viridis", "plasma", "inferno", "magma", "cividis", "turbo", "balance", "coolwarm")

function summary_dashboards(summary, layout)
    sources = summary_sources(summary)
    field = get(summary["VALUES"], "FIELD", Dict())
    presets = [("Current case layout", layout)]
    for (label, keys) in (("Field overview", ("FPR", "FOPR", "FWPR", "FGPR", "FWIR", "FGIR")),
            ("Production rates", ("FOPR", "FWPR", "FGPR", "FLPR", "FWCT", "FGOR")),
            ("Cumulative production", ("FOPT", "FWPT", "FGPT", "FLPT")),
            ("Injection", ("FWIR", "FGIR", "FOIR", "FWIT", "FGIT", "FOIT")))
        plots = ["FIELD:$key" for key in keys if haskey(field, key)]
        isempty(plots) && continue
        cols = min(2, length(plots))
        push!(presets, (label, (; plots, rows = cld(length(plots), cols), cols)))
    end
    well = findfirst(source -> startswith(source[2], "Well "), sources)
    if !isnothing(well)
        name, _, curves = sources[well]
        plots = ["$name:$key" for key in ("WBHP", "WOPR", "WWPR", "WGPR", "WWIR", "WGIR") if haskey(curves, key)]
        if !isempty(plots)
            cols = min(2, length(plots))
            push!(presets, ("Well performance", (; plots, rows = cld(length(plots), cols), cols)))
        end
    end
    return presets
end

function reservoir_field_options(reservoir)
    (; model, states) = reservoir
    domain = model isa Jutul.DataDomain ? model : JutulDarcy.reservoir_domain(model)
    nc = Jutul.number_of_cells(domain)
    # Keep the menu cheap for big cases. The explorer validates the chosen field across reports.
    fields = Dict{String, Bool}()
    function add_field(key, values, static)
        values isa AbstractVecOrMat{<:Real} && size(values, ndims(values)) == nc || return
        # Convert one cell so decomposed fields use the same names as the explorer.
        sample = selectdim(values, ndims(values), 1:min(nc, 1))
        for (key, sample) in JutulDarcy.convert_for_plotting(Dict(key => sample); append_unit = false)
            labels = sample isa AbstractMatrix ? ["$key row $i" for i in axes(sample, 1)] : [string(key)]
            for label in labels
                fields[label] = static || get(fields, label, false)
            end
        end
    end
    for (key, (values, entity)) in pairs(domain)
        entity == Jutul.Cells() && add_field(key, values, true)
    end
    if !ismissing(states) && !isempty(states)
        for (key, values) in pairs(first(states))
            add_field(key, values, false)
        end
    end
    return sort!(collect(fields); by = pair -> lowercase(first(pair)))
end

function plot_options_dialog(DOM, data)
    field(label, input) = DOM.label(DOM.span(label), input; class = "plot-field")
    select(name, pairs) = DOM.select([DOM.option(label; value) for (value, label) in pairs]...; name)
    number(name, value, min, max; step = 1) = DOM.input(; type = "number", name, value, min, max, step, required = true)
    checkbox(name, label, checked) = DOM.label(DOM.input(; type = "checkbox", name, checked), label; class = "plot-check")
    groups = []
    if :summary in data.available
        presets = summary_dashboards(data.results.summary, data.layout)
        choices = [DOM.option(label; value = i, var"data-plots" = join(layout.plots, '\n'),
            var"data-rows" = layout.rows, var"data-cols" = layout.cols) for (i, (label, layout)) in enumerate(presets)]
        preset = field("Dashboard preset", DOM.select(choices..., DOM.option("Custom"; value = ""); class = "summary-preset"))
        panels = field("Panels, one per line", DOM.textarea(join(data.layout.plots, '\n'); name = "plots", rows = 5, required = true))
        layout = DOM.div(field("Rows", number("rows", data.layout.rows, 1, max(10, data.layout.rows))),
            field("Columns", number("cols", data.layout.cols, 1, max(10, data.layout.cols))),
            field("Units", select("units", (("Metric", "Metric"), ("Field", "Field"), ("SI", "SI")))); class = "plot-grid")
        push!(groups, DOM.div(preset, panels, layout; class = "plot-settings", var"data-options" = "summary"))
    end
    if :reservoir in data.available
        reservoir = data.results.reservoir
        choices = [DOM.option(key; value = key, var"data-static" = string(static)) for (key, static) in reservoir_field_options(reservoir)]
        property = DOM.select(DOM.option("Automatic"; value = "", var"data-static" = "true"), choices...; name = "field")
        fields = DOM.div(field("Property", property),
            field("Report", select("step", isempty(reservoir.steps) ? [("1", "Static grid")] :
                [(string(i), "Report $step") for (i, step) in enumerate(reservoir.steps)])),
            field("Colormap", select("colormap", [(key, key) for key in RESERVOIR_COLORMAPS])),
            field("Background", select("preset", (("viridis_dark", "Dark"), ("gist_yarg", "Light")))),
            field("Vertical scale", number("zaspect", 1/3, 0.001, 100; step = "any")),
            field("Units", select("unit_system", (("metric", "Metric"), ("field", "Field"), ("si", "SI"))));
            class = "plot-grid")
        visibility = DOM.div(checkbox("static_only", "Static properties only", false),
            checkbox("edges", "Mesh lines", false), checkbox("mesh_enabled", "Mesh cells", true),
            checkbox("show_axis", "Axes", false), checkbox("faults", "Faults", true),
            checkbox("static_color_range_enabled", "Fixed color range across reports", true),
            checkbox("split_filters_enabled", "Split static and dynamic filters", false); class = "plot-grid")
        overlays = DOM.div(field("Fault opacity", number("fault_alpha", 0.5, 0, 1; step = "any")),
            field("Well color", DOM.input(; type = "color", name = "well_color", value = "#8b0000")),
            field("Well line width", number("well_linewidth", 3, 0.1, 30; step = "any")),
            field("Well label size", number("well_fontsize", 18, 6, 72)); class = "plot-grid")
        push!(groups, DOM.div(fields, visibility, DOM.details(DOM.summary("Well and fault styling"), overlays);
            class = "plot-settings", var"data-options" = "reservoir"))
    end
    if :wells in data.available
        wells = data.results.wells.wells
        names = sort!(string.(collect(keys(wells))))
        responses = sort!(unique([string(k) for well in values(wells) for k in keys(well)]))
        push!(groups, DOM.div(field("Well", select("entity", [("", "All wells"); [(name, name) for name in names]])),
            field("Response", select("series", [("", "Automatic"); [(key, key) for key in responses]]));
            class = "plot-settings", var"data-options" = "wells"))
    end
    tabs = DOM.div([DOM.button(VIEW_TITLES[view]; type = "button", var"data-kind" = string(view),
        var"aria-pressed" = "false") for view in data.available]...; class = "plot-kinds", role = "group", var"aria-label" = "Plot type")
    actions = DOM.div(DOM.button("Cancel"; type = "button", class = "plot-cancel"),
        DOM.button("Add plot"; type = "submit", class = "actions-add plot-submit"); class = "controls dialog-actions")
    form = DOM.form(tabs, groups..., DOM.p(; class = "plot-error", role = "status"), actions)
    return DOM.dialog(DOM.h2("Add plot"), form; class = "plot-dialog", var"aria-label" = "Add plot")
end

function web_plot_settings(values)
    config = Dict{String, String}()
    for entry in values
        fields = split(entry, '='; limit = 2)
        length(fields) == 2 && (config[fields[1]] = fields[2])
    end
    return config
end

function web_summary_layout(data, config)
    haskey(config, "plots") || return data.layout
    plots = String.(filter(!isempty, strip.(split(config["plots"], '\n'))))
    isempty(plots) && throw(ArgumentError("Enter at least one summary panel."))
    default = data.layout
    rows = clamp(parse(Int, get(config, "rows", string(default.rows))), 1, max(10, default.rows))
    cols = clamp(parse(Int, get(config, "cols", string(default.cols))), 1, max(10, default.cols))
    cld(length(plots), rows) <= cols || throw(ArgumentError("The selected grid is too small for $(length(plots)) panels."))
    unit_system = get(config, "units", "Metric")
    unit_system in ("Metric", "Field", "SI") || throw(ArgumentError("Unknown summary unit system."))
    return (; plots, rows, cols, unit_system)
end

function web_reservoir_options(config)
    option(key, default, allowed) = begin
        value = get(config, key, default)
        value in allowed || throw(ArgumentError("Invalid value for $key."))
        value
    end
    number(key, default, lo, hi) = clamp(parse(Float64, get(config, key, string(default))), lo, hi)
    flag(key, default) = get(config, key, string(default)) == "true"
    plot_options = (colormap = Symbol(option("colormap", "viridis", RESERVOIR_COLORMAPS)),
        preset = Symbol(option("preset", "viridis_dark", ("viridis_dark", "gist_yarg"))),
        unit_system = option("unit_system", "metric", ("metric", "field", "si")),
        zaspect = number("zaspect", 1/3, 0.001, 100), edges = flag("edges", false), show_axis = flag("show_axis", false),
        mesh_enabled = flag("mesh_enabled", true), faults = flag("faults", true), fault_alpha = number("fault_alpha", 0.5, 0, 1),
        static_color_range_enabled = flag("static_color_range_enabled", true), split_filters_enabled = flag("split_filters_enabled", false),
        well_color = Makie.to_color(get(config, "well_color", "#8b0000")), well_fontsize = number("well_fontsize", 18, 6, 72),
        well_linewidth = number("well_linewidth", 3, 0.1, 30))
    field = get(config, "field", "")
    return (; field = isempty(field) ? nothing : field, step = parse(Int, get(config, "step", "1")),
        static_only = flag("static_only", false), plot_options)
end
