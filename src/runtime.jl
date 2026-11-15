using Dates: now
using PrecompileTools: @setup_workload, @compile_workload
import GeoEnergyIO, JLD2, Jutul, JutulDarcy, Makie
using JutulDarcyPlot: EclipseSource, JutulSource, parse_commandline, plot_options, resolve_input

include("eclipse_wells.jl")
include("results.jl")
include("plots.jl")
include("precompile.jl")
