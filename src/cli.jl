function parse_commandline(argv; web)
    settings = ArgParseSettings(
        prog = web ? "jdplot-web" : "jdplot",
        description = web ? "Explore Eclipse or Jutul results in your browser." :
            "Plot Eclipse or Jutul summary, well, or reservoir data.",
        version = string(pkgversion(@__MODULE__)),
        add_version = true,
        autofix_names = true,
    )
    @add_arg_table! settings begin
        "input"
            help = "Eclipse case prefix, file or directory, Jutul .jld2 results, or a .jl/.AFI case"
            required = true
        "--plot"
            help = web ? "View to serve (auto, summary, wells, reservoir). Auto serves all available views." :
                "View to plot (auto, summary, wells, reservoir). Auto uses summary when available."
            default = "auto"
        "--case"
            help = "Companion Jutul case for native reports (.jl, .DATA, .AFI, or .jld2)"
        "--static"
            help = "Plot reservoir grid properties without loading dynamic states"
            action = :store_true
        "--verbose"
            help = "Show Julia stack traces for invalid input"
            action = :store_true
    end
    if web
        @add_arg_table! settings begin
            "--host"
                help = "Address to listen on"
                default = "127.0.0.1"
            "--port"
                help = "Port to listen on"
                default = 9384
                arg_type = Int
                range_tester = p -> 1 <= p <= 65535
        end
    else
        @add_arg_table! settings begin
            "--backend"
                help = "Rendering backend (cairo or gl)"
                default = "cairo"
            "--output", "-o"
                help = "Output PNG path (defaults to <case>-<plot>.png in the current directory)"
            "--entity"
                help = "Field, well, group, or other summary entity to show initially"
            "--series"
                help = "Summary keyword to plot, for example FPR, WOPR, or WBHP"
            "--field"
                help = "Reservoir property to show initially, for example PRESSURE or porosity"
            "--step"
                help = "One-based position in the saved reservoir reports (default 1)"
                arg_type = Int
                range_tester = n -> n > 0
            "--row"
                help = "Component of a matrix-valued reservoir property for PNG output (default 1)"
                arg_type = Int
                range_tester = n -> n > 0
        end
    end
    return parse_args(argv, settings; as_symbols = true)
end

function select_backend(name)
    backend = lowercase(name)
    if backend in ("cairo", "cairomakie")
        renderer = @eval begin
            import CairoMakie
            CairoMakie
        end
        return renderer, false
    elseif backend in ("gl", "glmakie")
        renderer = @eval begin
            import GLMakie
            GLMakie
        end
        return renderer, true
    end
    throw(ArgumentError("Unknown backend $name. Use cairo or gl."))
end

function present_plot(backend, name, results, view, args; interactive)
    backend.activate!()
    if view == :auto
        view = isnothing(results.summary) ? :reservoir : :summary
    end
    fig = if view == :reservoir
        isnothing(results.reservoir) && throw(ArgumentError("No reservoir geometry found for $name."))
        reservoir_figure(results.reservoir, name; interactive, field = args[:field],
            step = something(args[:step], 1), row = something(args[:row], 1))
    else
        entities = curve_catalog(results.summary, view)
        curve_figure(results.summary, entities, name, view; interactive, entity = args[:entity], series = args[:series])
    end
    if interactive
        screen = display(backend.Screen(; title = "jdplot · $name"), fig)
        wait(screen)
    else
        path = abspath(something(args[:output], "$name-$view.png"))
        lowercase(splitext(path)[2]) == ".png" || throw(ArgumentError("Cairo output must have a .png extension."))
        mkpath(dirname(path))
        Makie.save(path, fig; backend)
        println("Wrote $path")
    end
    return nothing
end

function run_cli(argv; web)
    args = parse_commandline(argv; web)
    command = web ? "jdplot-web" : "jdplot"
    try
        view = Symbol(lowercase(args[:plot]))
        view == :plot_reservoir && (view = :reservoir)
        view in (:auto, :summary, :wells, :reservoir) ||
            throw(ArgumentError("Unknown plot $(args[:plot]). Use auto, summary, wells, or reservoir."))
        static = args[:static]
        if web
            static && view in (:summary, :wells) && throw(ArgumentError("--static applies to reservoir plots."))
        else
            reservoir_options = static || any(k -> !isnothing(args[k]), (:field, :step, :row))
            curve_options = any(k -> !isnothing(args[k]), (:entity, :series))
            if reservoir_options && (view in (:summary, :wells) || curve_options)
                throw(ArgumentError("--static, --field, --step, and --row apply to reservoir plots."))
            elseif curve_options && view == :reservoir
                throw(ArgumentError("--entity and --series apply to summary and well plots."))
            end
            if view == :auto
                reservoir_options && (view = :reservoir)
                curve_options && (view = :summary)
            end
            if lowercase(args[:backend]) in ("gl", "glmakie") && any(k -> !isnothing(args[k]), (:output, :row))
                throw(ArgumentError("--output and --row require the Cairo backend."))
            end
        end
        source = resolve_input(args[:input]; companion = args[:case])
        results = load_results(source, view; web, static)
        name = case_name(source)
        if web
            @eval import Bonito, WGLMakie
            Base.invokelatest(serve_web, name, results, view; host = args[:host], port = args[:port])
        else
            backend, interactive = select_backend(args[:backend])
            Base.invokelatest(present_plot, backend, name, results, view, args; interactive)
        end
    catch err
        if err isa ArgumentError && !args[:verbose]
            println(stderr, "$command: $(err.msg)")
            return 1
        end
        rethrow()
    end
    return 0
end
