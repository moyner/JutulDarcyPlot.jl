module JutulDarcyPlotGLMakieExt

import GLMakie

include("../src/runtime.jl")
include("../src/desktop.jl")

@setup_workload begin
    examples = plot_workload_data()
    args = parse_commandline(["Example"]; web = false)
    @compile_workload begin
        try
            for (; data, static) in examples
                curves = (summary = data.summary, reservoir = nothing)
                grid = (summary = nothing, reservoir = data.reservoir)
                for (results, view) in ((curves, :summary), (curves, :wells), (grid, :reservoir), (static, :reservoir))
                    screen = render_plot(GLMakie, "Example", results, view, args;
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
            precompile_plot_figures(identity, examples; interactive = true)
        finally
            GLMakie.closeall()
            Makie.cleanup_globals()
        end
    end
end

end
