const VIEW_TITLES = Dict(:summary => "Summary", :wells => "Wells", :reservoir => "Reservoir")

const WEB_STYLE = """
    body { margin: 0; background: #f3f6fa; color: #142b3a; font: 16px Inter, system-ui, sans-serif; }
    .jdplot { max-width: 1400px; margin: auto; padding: 24px clamp(12px, 4vw, 48px) 48px; }
    .jdplot header { display: flex; align-items: baseline; justify-content: space-between;
                     flex-wrap: wrap; gap: 12px; padding: 8px 0 20px; }
    .jdplot h1, .jdplot h2 { margin: 0; }
    .jdplot h1 { font-size: clamp(22px, 4vw, 32px); overflow-wrap: anywhere; }
    .jdplot h2 { font-size: 18px; padding: 16px 20px 12px; }
    .jdplot nav { display: flex; gap: 16px; }
    .jdplot a { color: #00586a; text-underline-offset: 4px; }
    .jdplot section { background: white; border: 1px solid #d3dfe7; border-radius: 12px;
                      margin-bottom: 20px; overflow: hidden; }
    .jdplot .plot { overflow-x: auto; }
    .jdplot.wide { max-width: 1800px; padding-inline: clamp(12px, 1.4vw, 24px); }
    .jdplot .combined { display: grid; grid-template-columns: minmax(320px, 1fr) minmax(960px, 2.5fr); gap: 16px; }
    @media (max-width: 1350px) {
        .jdplot .combined { grid-template-columns: minmax(0, 1fr); gap: 0; }
    }
    """

function web_app(name, results, requested; bonito, backend)
    summary = curve_catalog(results.summary, :summary)
    wells = curve_catalog(results.summary, :wells)
    available = Dict(:summary => !isempty(summary), :wells => !isempty(wells),
        :reservoir => !isnothing(results.reservoir))
    combined = requested == :combined
    views = if requested == :auto
        filter(view -> available[view], [:summary, :wells, :reservoir])
    else
        required = combined ? [:summary, :reservoir] : [requested]
        for view in required
            available[view] || throw(ArgumentError("No $(lowercase(VIEW_TITLES[view])) data available for $name."))
        end
        required
    end
    isempty(views) && throw(ArgumentError("No plottable summary, well, or reservoir data available for $name."))
    DOM = bonito.DOM
    # Build each figure in its own browser session. The loaded results are shared
    # read-only, while menu, slider, and camera state are local to the session.
    return bonito.App(; title = "jdplot · $name") do
        sections = map(views) do view
            fig = if view == :reservoir
                figure = reservoir_figure(results.reservoir, name; interactive = true)
                combined ? Makie.resize!(figure, 1040, 720) : Makie.resize!(figure, 1300, 760)
                figure
            else
                entities = view == :wells ? wells : summary
                curve_figure(results.summary, entities, name, view; interactive = true, compact = combined)
            end
            plot = backend.WithConfig(fig; resize_to = (:parent, nothing))
            min_width = if view == :reservoir
                combined ? 960 : 1000
            else
                combined ? 320 : 580
            end
            frame = DOM.div(plot; style = "min-width: $(min_width)px")
            DOM.section(DOM.h2(VIEW_TITLES[view]), DOM.div(frame; class = "plot"); id = string(view))
        end
        header = if length(views) > 1 && !combined
            links = [DOM.a(VIEW_TITLES[view]; href = "#$view") for view in views]
            DOM.header(DOM.h1(name), DOM.nav(links...))
        else
            DOM.header(DOM.h1(name))
        end
        plots = DOM.div(sections...; class = combined ? "combined" : "views")
        return DOM.main(DOM.style(WEB_STYLE), header, plots; class = combined ? "jdplot wide" : "jdplot")
    end
end

function serve_web(name, results, view; host, port, backend, bonito)
    backend.activate!()
    app = web_app(name, results, view; backend, bonito)
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
