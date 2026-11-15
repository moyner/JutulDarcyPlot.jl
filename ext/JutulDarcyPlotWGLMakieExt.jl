module JutulDarcyPlotWGLMakieExt

import WGLMakie
import Bonito

include("../src/runtime.jl")
include("../src/web.jl")

@setup_workload begin
    examples = plot_workload_data()
    @compile_workload begin
        WGLMakie.activate!()
        try
            for (; data, static) in examples
                for (results, view) in ((data, :auto), (data, :combined), (static, :reservoir))
                    app = web_app("Example", results, view; bonito = Bonito, backend = WGLMakie)
                    session = Bonito.Session(Bonito.NoConnection(); asset_server = Bonito.NoServer())
                    try
                        show(IOBuffer(), Bonito.session_dom(session, app))
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
