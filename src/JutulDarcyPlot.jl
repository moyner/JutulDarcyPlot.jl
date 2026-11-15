module JutulDarcyPlot

using ArgParse
using Dates: now
using PrecompileTools: @setup_workload, @compile_workload
import GeoEnergyIO, JLD2, Jutul, JutulDarcy, Makie

include("inputs.jl")
include("eclipse_wells.jl")
include("results.jl")
include("plots.jl")
include("desktop.jl")
include("web.jl")
include("cli.jl")
include("precompile.jl")

function (@main)(args)
    return run_cli(args; web = false)
end

module Web
using ..JutulDarcyPlot: run_cli

function (@main)(args)
    return run_cli(args; web = true)
end
end

end
