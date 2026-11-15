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
    """

function web_app(name, results, requested)
    summary = curve_catalog(results.summary, :summary)
    wells = curve_catalog(results.summary, :wells)
    available = Dict(:summary => !isempty(summary), :wells => !isempty(wells),
        :reservoir => !isnothing(results.reservoir))
    views = if requested == :auto
        filter(view -> available[view], [:summary, :wells, :reservoir])
    else
        available[requested] || throw(ArgumentError("No $(lowercase(VIEW_TITLES[requested])) data available for $name."))
        [requested]
    end
    isempty(views) && throw(ArgumentError("No plottable summary, well, or reservoir data available for $name."))
    DOM = Bonito.DOM
    # Build each figure in its own browser session. The loaded results are shared
    # read-only, while menu, slider, and camera state are local to the session.
    return Bonito.App(; title = "jdplot · $name") do
        sections = map(views) do view
            fig = if view == :reservoir
                figure = reservoir_figure(results.reservoir, name; interactive = true)
                Makie.resize!(figure, 1300, 760)
                figure
            else
                entities = view == :wells ? wells : summary
                curve_figure(results.summary, entities, name, view; interactive = true)
            end
            plot = WGLMakie.WithConfig(fig; resize_to = (:parent, nothing))
            min_width = view == :reservoir ? 1000 : 580
            frame = DOM.div(plot; style = "min-width: $(min_width)px")
            DOM.section(DOM.h2(VIEW_TITLES[view]), DOM.div(frame; class = "plot"); id = string(view))
        end
        header = if length(views) > 1
            links = [DOM.a(VIEW_TITLES[view]; href = "#$view") for view in views]
            DOM.header(DOM.h1(name), DOM.nav(links...))
        else
            DOM.header(DOM.h1(name))
        end
        return DOM.main(DOM.style(WEB_STYLE), header, sections...; class = "jdplot")
    end
end

function serve_web(name, results, view; host, port)
    WGLMakie.activate!()
    app = web_app(name, results, view)
    server = Bonito.Server(app, host, port)
    println("jdplot-web is serving $name at $(Bonito.online_url(server, "/"))")
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
