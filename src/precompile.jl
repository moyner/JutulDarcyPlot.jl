function write_eclipse_workload(directory; unified = true)
    std = GeoEnergyIO.StandardIO
    base = joinpath(directory, "CASE")
    grid = std.output.rectangular_grid([40.0, 45.0], [30.0, 30.0], [5.0, 6.0])
    dims = Tuple(grid["cartDims"])
    nc = prod(dims)
    egrid = std.write_egrid(grid, base)
    std.write_init(Dict("PORO" => collect(range(0.1f0, 0.2f0; length = nc))), base)
    day = Jutul.si_unit(:day)
    steps = map(1:2) do step
        headers = std.output.standard_headers(dims, nc; elapsed = step * day, report_step = step)
        head = headers[1].data
        head[[17, 18, 25, 28, 33]] .= (2, 2, 5, 1, 4)
        append!(headers, [
            std.BinaryKeyword("IWEL", Int32[1, 1, 1, 2, 2, 2, 2, 1, 1, 1]),
            std.BinaryKeyword("ZWEL", ["INJ", "PROD"]),
            std.BinaryKeyword("ICON", Int32[1, 1, 1, 1, 2, 1, 1, 2, 1, 2, 2, 1, 0, 0, 0, 0]),
        ])
        solution = [std.BinaryKeyword("PRESSURE", Float32.(100 .+ step .* (1:nc)))]
        return std.output.restart_block(headers, solution; report_step = step)
    end
    restart = std.write_restart(steps, base; unified)
    summary = Dict{String, Any}(
        "DIMENS" => dims,
        "UNIT_SYSTEM" => "METRIC",
        "TIME" => (start_date = nothing, seconds = [day, 2day]),
        "VALUES" => Dict("FIELD" => Dict("FPR" => [110.0, 115.0]),
            "WELLS" => Dict("INJ" => Dict("WBHP" => [125.0, 130.0]), "PROD" => Dict("WBHP" => [105.0, 102.0]))),
    )
    summary = std.write_summary(summary, base; unified)
    return (; base, egrid, restart, summary)
end

function write_native_workload(directory)
    case = JutulDarcy.setup_mini_wellcase(:single_phase; nstep = 2, dims = (2, 2, 2), total_time = 120.0)
    for step in eachindex(case.dt)
        report = Dict(:ministeps => [Dict(:success => true, :dt => case.dt[step])])
        Jutul.write_result_jld2(directory, case.state0, report, step)
    end
    companion = joinpath(directory, "case.jld2")
    JLD2.jldsave(companion; case)
    return companion
end

function plot_workload_data()
    return mktempdir() do dir
        files = write_eclipse_workload(mkdir(joinpath(dir, "eclipse")))
        eclipse = resolve_input(files.base)
        native_dir = mkdir(joinpath(dir, "native"))
        native = resolve_input(native_dir; companion = write_native_workload(native_dir))
        return map((eclipse, native)) do source
            data = load_results(source, :auto; web = true, static = false)
            static = load_results(source, :reservoir; web = true, static = true)
            return (; data, static)
        end
    end
end

function precompile_plot_figures(render, examples; interactive)
    args = parse_commandline(["Example"]; web = false)
    for (; data, static) in examples
        layout = summary_layout(summary_sources(data.summary), args)
        render(summary_figure(data.summary, "Example", layout; interactive))
        render(well_figure(data.wells, data.summary, "Example"))
        render(reservoir_figure(data.reservoir, "Example"; interactive, step = 2))
        render(reservoir_figure(static.reservoir, "Example"; interactive))
    end
    return nothing
end

@setup_workload begin
    directory = mktempdir()
    try
        unified = write_eclipse_workload(mkdir(joinpath(directory, "unified")))
        split = write_eclipse_workload(mkdir(joinpath(directory, "split")); unified = false)
        native = mkdir(joinpath(directory, "native"))
        companion = write_native_workload(native)
        @compile_workload begin
            for (argv, web) in (([unified.egrid], false),
                    ([unified.summary.spec, "--rows", "1", "--cols", "2", "--plots", "FPR", "--plots", "PROD:WBHP"], false),
                    ([split.base], true))
                args = parse_commandline(argv; web)
                (; view, static) = plot_options(args; web)
                load_results(resolve_input(args[:input]), view; web, static)
            end
            load_results(resolve_input(first(split.restart)), :reservoir; web = false, static = false)
            load_results(resolve_input(native; companion), :auto; web = true, static = false)
        end
    finally
        rm(directory; recursive = true)
    end
end
