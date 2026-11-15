module JutulDarcyPlotCairoMakieExt

import CairoMakie

include("../src/runtime.jl")
include("../src/desktop.jl")

@setup_workload begin
    examples = plot_workload_data()
    @compile_workload begin
        CairoMakie.activate!(visible = false)
        try
            precompile_plot_figures(examples; interactive = false) do figure
                show(IOBuffer(), MIME"image/png"(), figure)
            end
        finally
            Makie.cleanup_globals()
        end
    end
end

end
