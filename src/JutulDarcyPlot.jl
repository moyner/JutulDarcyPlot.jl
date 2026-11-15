module JutulDarcyPlot

using ArgParse

include("inputs.jl")
include("cli.jl")

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
