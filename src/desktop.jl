function render_plot(backend, name, results, view, args; interactive, visible = interactive)
    backend.activate!(; visible)
    if view == :auto
        view = isnothing(results.summary) ? :reservoir : :summary
    end
    fig = if view == :reservoir
        isnothing(results.reservoir) && throw(ArgumentError("No reservoir geometry found for $name."))
        reservoir_figure(results.reservoir, name; interactive, field = args[:field],
            step = something(args[:step], 1), row = something(args[:row], 1))
    elseif view == :summary
        layout = summary_layout(summary_sources(results.summary), args)
        summary_figure(results.summary, name, layout; interactive)
    else
        well_figure(results.summary, well_catalog(results.summary), name;
            interactive, entity = args[:entity], series = args[:series])
    end
    if interactive
        return display(backend.Screen(; title = "jdplot · $name", visible), fig)
    end
    path = abspath(something(args[:output], "$name-$view.png"))
    lowercase(splitext(path)[2]) == ".png" || throw(ArgumentError("Cairo output must have a .png extension."))
    mkpath(dirname(path))
    Makie.save(path, fig; backend)
    println("Wrote $path")
    return nothing
end

function present_plot(backend, name, results, view, args; interactive)
    screen = render_plot(backend, name, results, view, args; interactive)
    isnothing(screen) || wait(screen)
    return nothing
end
