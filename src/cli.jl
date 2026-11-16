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
            help = web ? "View to serve (combined by default, auto, summary, wells, reservoir). Auto follows the file type." :
                "View to plot (auto, summary, wells, reservoir). Auto follows the file type."
            default = web ? "combined" : "auto"
        "--plots", "--summary-plot"
            help = "Initial summary panel, for example FPR, FOPR,FWPR or PROD:WBHP. Repeat for more panels."
            arg_type = String
            action = :append_arg
        "--rows"
            help = "Initial number of summary rows"
            arg_type = Int
            range_tester = n -> n > 0
        "--columns", "--cols"
            help = "Initial number of summary columns"
            arg_type = Int
            range_tester = n -> n > 0
        "--case"
            help = "Companion case for Jutul reports, or original .DATA deck for Eclipse wells or geometry"
        "--static"
            help = "Plot reservoir grid properties without showing dynamic cell results"
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
                help = "Rendering backend (gl by default, cairo for PNG export)"
            "--output", "-o"
                help = "Export to this PNG path (implies cairo unless a backend is given)"
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

function plot_options(args; web)
    view = Symbol(lowercase(args[:plot]))
    view == :plot_reservoir && (view = :reservoir)
    valid_views = web ? (:auto, :summary, :wells, :reservoir, :combined) : (:auto, :summary, :wells, :reservoir)
    view in valid_views || throw(ArgumentError("Unknown plot $(args[:plot]). Use $(join(valid_views, ", "))."))
    static = args[:static]
    reservoir_options = static || (!web && any(k -> !isnothing(args[k]), (:field, :step, :row)))
    curve_options = !web && any(k -> !isnothing(args[k]), (:entity, :series))
    summary_options = has_summary_options(args)
    if summary_options && view in (:reservoir, :wells)
        throw(ArgumentError("--plots, --rows, and --columns apply to summary plots."))
    elseif !isempty(args[:plots]) && curve_options
        throw(ArgumentError("Specify the initial summary panels with --plots or use --entity and --series for a single panel."))
    elseif reservoir_options && (view in (:summary, :wells) || curve_options || (summary_options && !web))
        throw(ArgumentError("--static, --field, --step, and --row apply to reservoir plots."))
    elseif curve_options && view == :reservoir
        throw(ArgumentError("--entity and --series apply to summary and well plots."))
    end
    backend = nothing
    if !web
        png = any(k -> !isnothing(args[k]), (:output, :row))
        backend = something(args[:backend], png ? "cairo" : "gl")
        if png && lowercase(backend) in ("gl", "glmakie")
            throw(ArgumentError("--output and --row require the Cairo backend."))
        end
    end
    if view == :auto
        inferred = default_view(args[:input])
        view = if summary_options && (!web || inferred != :auto)
            static && throw(ArgumentError("Use --plot combined to set summary panels and show a static reservoir."))
            :summary
        elseif reservoir_options && (!web || isfile(args[:input]))
            :reservoir
        elseif curve_options
            :summary
        else
            inferred
        end
    end
    return (; view, static, backend)
end

has_summary_options(args) = !isempty(args[:plots]) || !isnothing(args[:rows]) || !isnothing(args[:columns])

function run_cli(argv; web)
    args = parse_commandline(argv; web)
    command = web ? "jdplot-web" : "jdplot"
    try
        (; view, static, backend) = plot_options(args; web)
        source = resolve_input(args[:input]; companion = args[:case])
        results = load_results(source, view; web, static)
        name = case_name(source)
        if web
            renderer, bonito = @eval begin
                import WGLMakie, Bonito
                WGLMakie, Bonito
            end
            Base.invokelatest(serve_web, name, results, view, args; host = args[:host], port = args[:port],
                backend = renderer, bonito, source)
        else
            renderer, interactive = select_backend(backend)
            Base.invokelatest(present_plot, renderer, name, results, view, args; interactive)
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
