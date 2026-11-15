const ECLIPSE_WELL_RESPONSES = Dict(
    "WBHP" => :bhp, "WWCT" => :wcut, "WGOR" => :gor, "WWGR" => :wgr, "WGLR" => :glr,
    "WOPR" => :orat, "WOIR" => :orat, "WWPR" => :wrat, "WWIR" => :wrat,
    "WGPR" => :grat, "WGIR" => :grat, "WLPR" => :lrat, "WLIR" => :lrat,
)

has_well_results(wells) = !isnothing(wells) && !isempty(wells.wells) && !isempty(wells.time)

function eclipse_well_results(summary)
    isnothing(summary) && return nothing
    seconds = summary["TIME"].seconds
    isempty(seconds) && return nothing
    n = length(seconds)
    lookup = JutulDarcy.summary_key_lookup()
    units = GeoEnergyIO.InputParser
    system = lowercase(get(summary, "UNIT_SYSTEM", "si"))
    systems = system in ("si", "metric", "field", "lab") ?
        (from = units.DeckUnitSystem(system), to = units.DeckUnitSystem(:si)) : nothing
    wells = Dict{Symbol, AbstractDict}()
    fields = Set{Symbol}()
    for (name, data) in get(summary["VALUES"], "WELLS", Dict())
        responses = Dict{Symbol, Vector{Float64}}()
        for (key, values) in data
            values isa AbstractVector{<:Real} && length(values) == n || continue
            field = get(ECLIPSE_WELL_RESPONSES, key, Symbol(key))
            samples = Float64.(values)
            if haskey(ECLIPSE_WELL_RESPONSES, key) && !isnothing(systems)
                info = lookup[key]
                units.swap_unit_system!(samples, systems, info.unit_type)
                if info.is_rate
                    sign = endswith(key, "PR") ? -1 : 1
                    samples .*= sign / systems.from.time
                end
            elseif haskey(ECLIPSE_WELL_RESPONSES, key)
                field = Symbol(key)
            end
            series = get!(() -> zeros(n), responses, field)
            series .+= samples
        end
        isempty(responses) && continue
        # The native viewer uses signed surface rate to distinguish well types.
        rate = zeros(n)
        for field in (:orat, :wrat, :grat)
            haskey(responses, field) && (rate .+= responses[field])
        end
        if !any(k -> haskey(responses, k), (:orat, :wrat, :grat))
            rate .= get(responses, :lrat, rate)
        end
        responses[:rate] = rate
        if !haskey(responses, :lrat) && any(k -> haskey(responses, k), (:orat, :wrat))
            responses[:lrat] = get(responses, :orat, zeros(n)) .+ get(responses, :wrat, zeros(n))
        end
        union!(fields, keys(responses))
        wells[Symbol(name)] = responses
    end
    isempty(wells) && return nothing
    # SMSPEC can describe different quantities for different wells.
    for data in values(wells), field in fields
        get!(() -> fill(NaN, n), data, field)
    end
    return JutulDarcy.WellResults(seconds, wells)
end

function well_figure(wells, summary, name; entity = nothing, series = nothing)
    has_well_results(wells) || throw(ArgumentError("No well curves are available."))
    if !isnothing(entity)
        names = filter(key -> lowercase(string(key)) == lowercase(entity), collect(keys(wells.wells)))
        length(names) == 1 || throw(ArgumentError("Expected one well matching $entity."))
        key = only(names)
        wells = JutulDarcy.WellResults(wells.time, Dict(key => wells.wells[key]), wells.start_date)
    end
    responses = wells.wells[minimum(keys(wells.wells))]
    field = if isnothing(series)
        haskey(responses, :bhp) ? :bhp : missing
    else
        key = get(ECLIPSE_WELL_RESPONSES, uppercase(series), Symbol(lowercase(series)))
        if !haskey(responses, key)
            key = Symbol(uppercase(series))
        end
        haskey(responses, key) || throw(ArgumentError("Well response $series is unavailable."))
        key
    end
    system = isnothing(summary) ? "si" : lowercase(get(summary, "UNIT_SYSTEM", "si"))
    unit_sys = system == "field" ? "Field" : "Metric"
    # The upstream cumulative control integrates rates against elapsed days.
    return JutulDarcy.plot_well_results(wells; name, field, unit_sys, start_date = nothing, resolution = (1100, 760))
end
