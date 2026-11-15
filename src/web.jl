const VIEW_TITLES = Dict(:summary => "Summary", :wells => "Wells", :reservoir => "Reservoir")
const WORKSPACE_ASSET = joinpath(@__DIR__, "web_workspace.js")
const CASE_BROWSER_ASSET = joinpath(@__DIR__, "web_case_browser.js")
include_dependency(WORKSPACE_ASSET)
include_dependency(CASE_BROWSER_ASSET)
const WORKSPACE_JS = read(WORKSPACE_ASSET, String)
const CASE_BROWSER_JS = read(CASE_BROWSER_ASSET, String)
include("web_case_browser.jl")
include("web_statistics.jl")

const WEB_STYLE = """
    * { box-sizing: border-box; }
    body { margin: 0; background: #edf2f6; color: #173044; font: 15px Inter, system-ui, sans-serif; }
    .jdplot { margin: auto; padding: 14px 16px 20px; color-scheme: light;
              --bonito-widget-bg: #fff; --bonito-widget-fg: #173044;
              --bonito-widget-muted-bg: #edf5f8; --bonito-widget-hover-bg: #edf5f8; }
    .jdplot header { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap;
                     gap: 12px; padding: 12px 16px; margin-bottom: 12px; color: #f6fbfd; border-radius: 10px;
                     background: linear-gradient(108deg, #132c40, #1b4155); }
    .jdplot h1, .jdplot h2 { margin: 0; }
    .jdplot h1 { font-size: clamp(20px, 2.4vw, 28px); font-weight: 650; overflow-wrap: anywhere; }
    .jdplot h2 { font-size: 16px; }
    .jdplot button, .jdplot select, .jdplot input { font: inherit; color: inherit; }
    .jdplot button, .jdplot select { border: 1px solid #c8d5de; background: #fff; border-radius: 6px;
                                    padding: 7px 11px; cursor: pointer; }
    .jdplot button:hover { background: #e7eff4; }
    .jdplot :focus-visible { outline: 2px solid #08798a; outline-offset: 2px; }
    .jdplot button:disabled { opacity: .55; cursor: default; }
    .jdplot header :focus-visible { outline-color: #8fe8ee; }
    .jdplot header button, .jdplot header select { color: #173044; border-color: transparent; }
    .jdplot .controls { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
    .jdplot .plot-controls { display: flex; gap: 0; }
    .jdplot .plot-choice { border-top-right-radius: 0; border-bottom-right-radius: 0; }
    .jdplot .plot-controls .actions-add { border-top-left-radius: 0; border-bottom-left-radius: 0; }
    .jdplot .actions-add { color: #fff; background: #075968; border-color: #075968; }
    .jdplot .actions-add:hover { background: #034755; }
    .jdplot header .actions-add { color: #0c3541; background: #a4e2e1; border-color: #a4e2e1; }
    .jdplot header .actions-add:hover { background: #c7eeee; }
    .jdplot .plot-gallery { max-width: 1400px; margin: auto; }
    .jdplot .plot-gallery section { background: #fff; border: 1px solid #ccd8e0;
                                    border-radius: 10px; margin-bottom: 20px; overflow: hidden; }
    .jdplot .plot-gallery h2 { padding: 12px 16px; }
    .jdplot .workspace-stage { position: relative; height: max(530px, calc(100dvh - 108px)); overflow: hidden;
                               background: #dfe8ef; border: 1px solid #c6d4df; border-radius: 10px; }
    .jdplot .plot-window { position: absolute; display: flex; flex-direction: column; left: 8px; top: 8px;
                           width: min(860px, 95%); height: min(640px, 95%); background: #fff;
                           border: 1px solid #aabdc9; border-radius: 9px; overflow: hidden;
                           box-shadow: 0 6px 18px #25445c29; }
    .jdplot .window-bar { display: flex; align-items: stretch; background: #f3f7fa; border-bottom: 1px solid #c9d7e0; }
    .jdplot .window-title { flex: 1; display: flex; align-items: center; padding: 9px 12px;
                            touch-action: none; cursor: grab; user-select: none; }
    .jdplot .window-title:active { cursor: grabbing; }
    .jdplot .window-close, .jdplot .window-maximize { border: 0; border-radius: 0; background: transparent;
                            min-width: 38px; padding: 4px 8px; font-size: 19px; line-height: 1; }
    .jdplot .window-close:hover { background: #f9e8e9; color: #8d2330; }
    .jdplot .window-maximized { inset: 0 !important; width: 100% !important; height: 100% !important; }
    .jdplot .window-maximized .window-title { cursor: default; }
    .jdplot .window-maximized .window-resize { display: none; }
    .jdplot .window-resize { position: absolute; bottom: 0; right: 0; width: 19px; height: 19px;
                             border: 0; padding: 0; touch-action: none; cursor: nwse-resize;
                             background: linear-gradient(135deg, transparent 48%, #7897a8 49% 55%, #edf3f7 56%); }
    .jdplot .view-body { display: flex; flex-direction: column; flex: 1; min-height: 0; overflow: hidden; }
    .jdplot .plot-gallery .view-body { height: min(80vh, 800px); min-height: 520px; }
    .jdplot .plot { height: 100%; overflow: auto; }
    .jdplot .plot-frame { height: 100%; min-height: 490px; }
    .jdplot .plot-stack { position: relative; flex: 1; min-height: 0; }
    .jdplot .plot-stack > .plot { position: absolute; inset: 0; }
    /* Retain a usable size for a WGLMakie canvas while its tab is hidden. */
    .jdplot .plot-stack > [hidden] { display: block; visibility: hidden; }
    .jdplot .plot-switcher { display: flex; align-items: center; gap: 4px; padding: 6px 8px; }
    .jdplot .plot-switcher button { border-color: transparent; background: transparent; }
    .jdplot .plot-switcher button[aria-pressed="true"] { background: #dcebf0; color: #004858; }
    .jdplot dialog { max-height: calc(100dvh - 24px); color: inherit; background: #fff; border: 1px solid #9cb2c2;
                     border-radius: 12px; box-shadow: 0 18px 60px #152e4a66; padding: 20px; }
    .jdplot dialog::backdrop { background: #10273f7d; }
    .jdplot dialog h2 { font-size: 20px; }
    .jdplot .case-dialog { width: min(710px, calc(100% - 24px)); }
    .jdplot .case-nav { display: grid; grid-template-columns: auto auto minmax(0, 1fr); gap: 8px; margin-top: 16px; }
    .jdplot .case-filter { min-width: 0; padding: 7px 11px; border: 1px solid #c8d5de; border-radius: 6px; }
    .jdplot .case-directory { margin: 10px 0 6px; color: #496476; font-size: 13px; overflow-wrap: anywhere; }
    .jdplot .case-entries { height: clamp(120px, 32vh, 340px); margin: 0 0 10px; padding: 4px;
                           overflow: auto; list-style: none; background: #f8fafc;
                           border: 1px solid #d3dfe7; border-radius: 7px; }
    .jdplot .case-entries button { display: flex; justify-content: space-between; width: 100%; gap: 8px;
                                 background: transparent; border-color: transparent; text-align: left; padding: 6px 9px; }
    .jdplot .case-entries button:hover { background: #e7eff4; }
    .jdplot .case-entries button[aria-pressed="true"] { background: #e0f1f2; color: #004858; }
    .jdplot .case-entries button span { overflow-wrap: anywhere; }
    .jdplot .case-entries small { flex-shrink: 0; color: #496476; }
    .jdplot .case-empty { color: #496476; padding: 8px; }
    .jdplot .case-selection { display: flex; align-items: center; flex-wrap: wrap; gap: 8px;
                             border-top: 1px solid #dbe5ed; padding: 9px 0; margin-top: 6px; }
    .jdplot .case-selection span { width: 132px; color: #496476; }
    .jdplot .case-selection strong { flex: 1 1 130px; overflow-wrap: anywhere; }
    .jdplot .case-status { margin: 8px 0; overflow-wrap: anywhere; }
    .jdplot .case-status:empty { display: none; }
    .jdplot .dialog-actions { justify-content: flex-end; margin-top: 6px; }
    .jdplot .stats-dialog { width: min(840px, calc(100% - 24px)); }
    .jdplot .stats-dialog[open] { display: flex; flex-direction: column; overflow: hidden; }
    .jdplot .stats-body { min-height: 0; overflow: auto; }
    .jdplot .stats-heading { display: flex; justify-content: space-between; align-items: center;
                            gap: 8px; flex-wrap: wrap; margin-bottom: 8px; }
    .jdplot .stats-heading h3 { margin: 0; font-size: 16px; }
    .jdplot .stats-heading select { max-width: 100%; margin: 0; }
    .jdplot .stats-overview { display: grid; grid-template-columns: repeat(auto-fit, minmax(115px, 1fr));
                             gap: 8px; margin: 14px 0 20px; }
    .jdplot .stats-overview div { background: #edf5f8; padding: 8px 10px; border-radius: 7px; }
    .jdplot .stats-overview dt, .jdplot .stats-note { color: #496476; font-size: 13px; }
    .jdplot .stats-overview dd { margin: 4px 0 0; font-size: 18px; font-weight: 650; }
    .jdplot .stats-note { margin: 0 0 8px; }
    .jdplot .stats-content section + section { margin-top: 20px; }
    .jdplot .stats-table { font: inherit; font-size: 14px; font-variant-numeric: tabular-nums; }
    .jdplot .stats-table .table-header { background: #edf5f8; color: #173044; }
    .jdplot .stats-table :is(.table-header, .table-cell) { border-color: #d9e4ec; white-space: nowrap; }
    @media (max-width: 720px) {
        .jdplot .workspace-stage { height: auto; min-height: 200px; padding: 8px; overflow: visible; }
        .jdplot .plot-window { position: relative; inset: auto !important; width: 100% !important;
                               height: 580px !important; margin-bottom: 8px; }
        .jdplot .window-title { cursor: default; touch-action: auto; }
        .jdplot .window-resize, .jdplot .window-maximize { display: none; }
    }
    @media (max-width: 520px) {
        .jdplot { padding: 8px; }
        .jdplot dialog { padding: 13px; }
        .jdplot .case-nav { grid-template-columns: auto 1fr; }
        .jdplot .case-filter { grid-column: 1 / -1; }
    }
    """

function web_case(name, results, requested, args)
    summary = summary_sources(results.summary)
    available = Symbol[]
    isempty(summary) || push!(available, :summary)
    has_well_results(results.wells) && push!(available, :wells)
    isnothing(results.reservoir) || push!(available, :reservoir)
    if requested in (:combined, :auto)
        views = filter(view -> view != :wells || !(:summary in available), available)
    else
        requested in available || throw(ArgumentError("No $(lowercase(VIEW_TITLES[requested])) data available for $name."))
        views = [requested]
    end
    isempty(views) && throw(ArgumentError("No plottable summary, well, or reservoir data available for $name."))
    layout = :summary in views || has_summary_options(args) ? summary_layout(summary, args) : nothing
    return (; name, results, available, views, layout)
end

function web_plot(DOM, backend, figure, view; min_width, hidden = false)
    plot = backend.WithConfig(figure; resize_to = :parent)
    frame = DOM.div(plot; class = "plot-frame", style = "min-width: $(min_width)px")
    return DOM.div(frame; class = "plot", var"data-plot" = string(view), hidden)
end

function web_view(data, view; backend, bonito)
    DOM = bonito.DOM
    (; results, layout, name) = data
    if view == :summary
        summary = summary_figure(results.summary, name, layout; interactive = true)
        plot = web_plot(DOM, backend, summary, :summary; min_width = max(820, 415 * layout.cols))
        if :wells in data.available
            buttons = [DOM.button(VIEW_TITLES[v]; type = "button", var"data-tab" = string(v),
                var"aria-pressed" = string(v == :summary)) for v in (:summary, :wells)]
            toggle = DOM.div(buttons...; class = "plot-switcher", role = "group", var"aria-label" = "Curve view")
            wells = well_figure(results.wells, results.summary, name)
            stack = DOM.div(plot, web_plot(DOM, backend, wells, :wells; min_width = 880, hidden = true);
                class = "plot-stack")
            return DOM.div(toggle, stack; class = "view-body")
        end
    elseif view == :reservoir
        figure = reservoir_figure(results.reservoir, name; interactive = true)
        plot = web_plot(DOM, backend, figure, view; min_width = 960)
    else
        figure = well_figure(results.wells, results.summary, name)
        plot = web_plot(DOM, backend, figure, view; min_width = 880)
    end
    return DOM.div(plot; class = "view-body")
end

function web_window(data, view; backend, bonito)
    DOM = bonito.DOM
    title = VIEW_TITLES[view]
    body = web_view(data, view; backend, bonito)
    return bonito.App(; loading_page = nothing) do
        bar = DOM.div(DOM.div(DOM.h2(title); class = "window-title", tabindex = "0",
                var"aria-label" = "Move $title window"),
            DOM.button("□"; class = "window-maximize", type = "button", title = "Maximize $title window",
                var"aria-label" = "Maximize $title window", var"aria-pressed" = "false"),
            DOM.button("×"; class = "window-close", type = "button", var"aria-label" = "Close $title window");
            class = "window-bar")
        resize = DOM.button(; class = "window-resize", type = "button", var"aria-label" = "Resize $title window")
        DOM.section(bar, body, resize; class = "plot-window",
            var"data-view" = string(view), var"aria-label" = title)
    end
end

function web_case_app(data, requested, switch_case, input; backend, bonito, allow_case_load)
    DOM = bonito.DOM
    combined = requested == :combined
    # Build the initial figures before installing a replacement case in the tab.
    plots = if combined
        DOM.div([web_window(data, view; backend, bonito) for view in data.views]...;
            class = "workspace-stage", var"aria-label" = "Plot workspace")
    else
        DOM.div([DOM.section(DOM.h2(VIEW_TITLES[view]),
                web_view(data, view; backend, bonito); var"data-view" = string(view)) for view in data.views]...;
            class = "plot-gallery")
    end
    return bonito.App(; loading_page = nothing) do session
        actions = Makie.Observable(String[])
        controls = []
        if combined
            choices = [DOM.option(VIEW_TITLES[view]; value = string(view)) for view in data.available]
            push!(controls, DOM.div(DOM.select(choices...; class = "plot-choice", var"aria-label" = "Plot type"),
                DOM.button("Add plot"; class = "actions-add", type = "button"); class = "plot-controls"))
        end
        push!(controls, DOM.button("Statistics"; class = "stats-open", type = "button"))
        if allow_case_load
            push!(controls, DOM.button("Load case"; class = "case-open", type = "button"))
        end
        header = DOM.header(DOM.h1(data.name), DOM.div(controls...; class = "controls"))
        stats = web_statistics_dialog(bonito, session, data.results, actions)
        browser = allow_case_load ? web_case_dialog(DOM, input) : nothing
        root = DOM.div(header, plots, stats, browser)
        bonito.on(session, actions) do action
            if combined && length(action) == 2 && first(action) == "add"
                view = findfirst(v -> string(v) == action[2], data.available)
                isnothing(view) && return
                bonito.append_child(session, plots, web_window(data, data.available[view]; backend, bonito))
            end
        end
        bonito.onload(session, root, web_initializer(bonito, "root", WORKSPACE_JS, actions))
        if allow_case_load
            mount_case_browser!(bonito, session, browser, actions, switch_case)
        end
        return root
    end
end

function web_initializer(bonito, node, javascript, observables...)
    code = Any[bonito.JSString("$node => ($javascript)($node")]
    for observable in observables
        append!(code, (bonito.JSString(", "), observable))
    end
    push!(code, bonito.JSString(")"))
    return bonito.JSCode(code)
end

function web_app(name, results, requested, args; backend, bonito, allow_case_load = false)
    initial = web_case(name, results, requested, args)
    return bonito.App(; title = "jdplot · $name") do
        display = Makie.Observable{Any}(nothing)
        function switch_case(path, companion)
            isempty(path) && throw(ArgumentError("Select a case file or folder."))
            companion = isempty(companion) ? nothing : companion
            next_args = copy(args)
            next_args[:input] = path
            next_args[:case] = companion
            next_args[:plots] = String[]
            next_args[:rows] = next_args[:columns] = nothing
            (; view, static) = plot_options(next_args; web = true)
            source = resolve_input(path; companion)
            data = load_results(source, view; web = true, static)
            next_case = Base.invokelatest(web_case, case_name(source), data, view, next_args)
            display[] = Base.invokelatest(web_case_app, next_case, view, switch_case, path;
                backend, bonito, allow_case_load)
            return nothing
        end
        display[] = web_case_app(initial, requested, switch_case, args[:input]; backend, bonito, allow_case_load)
        return bonito.DOM.main(bonito.DOM.style(WEB_STYLE), display; class = "jdplot")
    end
end

function serve_web(name, results, view, args; host, port, backend, bonito)
    backend.activate!()
    # Loading a path can execute a Julia case script. Restrict this action to a local server.
    allow_case_load = lowercase(host) in ("127.0.0.1", "::1", "localhost")
    app = web_app(name, results, view, args; backend, bonito, allow_case_load)
    server = bonito.Server(app, host, port)
    println("jdplot-web is serving $name at $(bonito.online_url(server, "/"))")
    flush(stdout)
    try
        wait(server)
    catch err
        err isa InterruptException || rethrow()
    finally
        close(server)
    end
    return nothing
end
