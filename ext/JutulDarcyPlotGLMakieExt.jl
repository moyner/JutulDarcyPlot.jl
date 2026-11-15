module JutulDarcyPlotGLMakieExt

import GLMakie, JutulDarcyPlot, Makie
using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    examples = JutulDarcyPlot.plot_workload_data()
    args = JutulDarcyPlot.parse_commandline(["Example"]; web = false)
    @compile_workload begin
        try
            for (; data, static) in examples
                curves = (summary = data.summary, reservoir = nothing, wells = data.wells)
                grid = (summary = nothing, reservoir = data.reservoir)
                for (results, view) in ((curves, :summary), (curves, :wells), (grid, :reservoir), (static, :reservoir))
                    screen = JutulDarcyPlot.render_plot(GLMakie, "Example", results, view, args;
                        interactive = true, visible = false)
                    try
                        Makie.colorbuffer(screen)
                    finally
                        close(screen)
                    end
                end
            end
        catch err
            glfw = GLMakie.GLFW
            err isa glfw.GLFWError && err.code in (glfw.NOT_INITIALIZED, glfw.API_UNAVAILABLE,
                glfw.VERSION_UNAVAILABLE, glfw.PLATFORM_ERROR, glfw.FORMAT_UNAVAILABLE) || rethrow()
            # Still compile figure construction when this machine has no OpenGL context.
            JutulDarcyPlot.precompile_plot_figures(identity, examples; interactive = true)
        finally
            GLMakie.closeall()
            Makie.cleanup_globals()
        end
    end
end

end
