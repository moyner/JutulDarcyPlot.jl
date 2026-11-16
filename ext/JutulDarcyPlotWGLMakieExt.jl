module JutulDarcyPlotWGLMakieExt

import WGLMakie
import Bonito, JutulDarcyPlot, Makie
using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    examples = JutulDarcyPlot.plot_workload_data()
    args = JutulDarcyPlot.parse_commandline(["Example"]; web = true)
    @compile_workload begin
        WGLMakie.activate!()
        try
            for mode in ("case", "companion", "eclipse-deck")
                JutulDarcyPlot.case_browser_listing(@__DIR__, mode)
            end
            for (; data, static) in examples
                for (results, view) in ((data, :combined), (data, :auto), (data, :wells), (static, :reservoir))
                    app = JutulDarcyPlot.web_app("Example", results, view, args;
                        bonito = Bonito, backend = WGLMakie, allow_case_load = true)
                    session = Bonito.Session(Bonito.NoConnection(); asset_server = Bonito.NoServer())
                    try
                        show(IOBuffer(), Bonito.session_dom(session, app))
                        if view == :combined
                            content = JutulDarcyPlot.statistics_content(Bonito, session, results)
                            show(IOBuffer(), Bonito.jsrender(session, content))
                            workspace = JutulDarcyPlot.web_case("Example", results, view, args)
                            summary_config = Dict("plots" => "FIELD:FPR", "rows" => "1", "cols" => "1")
                            reservoir_config = Dict("colormap" => "plasma", "edges" => "true", "step" => "2")
                            for (kind, config) in ((:summary, summary_config), (:reservoir, reservoir_config))
                                plot = JutulDarcyPlot.web_window(workspace, kind; backend = WGLMakie, bonito = Bonito, config)
                                show(IOBuffer(), Bonito.jsrender(session, plot))
                            end
                        end
                        if hasproperty(session, :init_error) && !isnothing(session.init_error[])
                            throw(session.init_error[])
                        end
                    finally
                        close(session)
                    end
                end
            end
            precompile(WGLMakie.serialize_scene, (Makie.Scene,))
        finally
            isdefined(Bonito, :cleanup_globals) && Bonito.cleanup_globals()
            Makie.cleanup_globals()
        end
    end
end

end
