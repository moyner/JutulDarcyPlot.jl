module JutulDarcyPlotCairoMakieExt

import CairoMakie, JutulDarcyPlot, Makie
using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    examples = JutulDarcyPlot.plot_workload_data()
    @compile_workload begin
        CairoMakie.activate!(visible = false)
        try
            JutulDarcyPlot.precompile_plot_figures(examples; interactive = false) do figure
                show(IOBuffer(), MIME"image/png"(), figure)
            end
        finally
            Makie.cleanup_globals()
        end
    end
end

end
