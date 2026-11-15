function load_results(source::EclipseSource, view; web, static)
    use_curves = view in (:summary, :wells) || (view == :auto && source.has_summary)
    has_grid = !isnothing(source.grid) || !isnothing(source.deck)
    use_grid = view == :reservoir || (view == :auto && (web || !use_curves) && has_grid)

    summary = if use_curves
        source.has_summary || throw(ArgumentError("No complete Eclipse summary found for $(source.base). Supply SMSPEC and UNSMRY or Snnnn files."))
        GeoEnergyIO.read_summary(source.base; format = :structured)
    end
    reservoir = use_grid ? load_eclipse_reservoir(source; static) : nothing
    return (; summary, reservoir)
end

const DECK_PROPERTIES = ("PORO", "PERMX", "PERMY", "PERMZ", "NTG", "SATNUM", "PVTNUM", "ROCKNUM", "FIPNUM")
const ECLIPSE_METADATA = Set([
    "INTEHEAD", "LOGIHEAD", "DOUBHEAD", "SEQNUM", "STARTSOL", "ENDSOL",
    "IWEL", "SWEL", "XWEL", "ZWEL", "ICON", "SCON", "XCON", "ISEG", "RSEG",
    "ILBS", "ILBR", "IGRP", "SGRP", "XGRP", "ZGRP", "IGRPH", "RGRP", "ZTRACER",
    "TAB", "TABDIMS", "NNCHEAD", "TRANNNC", "LGR", "LGRHEADI", "LGRHEADQ", "LGRHEADD",
])

function eclipse_cell_fields(data, cells, active_cells, active_positions, nfull)
    header = get(data, "INTEHEAD", Int[])
    unit_system = get(header, 3, 0)
    fields = Dict{Symbol, Any}()
    for (key, values) in pairs(data)
        key in ECLIPSE_METADATA && continue
        values isa AbstractArray{<:Real} && !(values isa AbstractArray{Bool}) || continue
        label = Symbol(eclipse_field_label(key, unit_system))
        if length(values) == nfull
            fields[label] = length(cells) == nfull && issorted(cells) ? vec(values) : vec(values)[cells]
        elseif length(values) == length(active_cells) && !isnothing(active_positions)
            fields[label] = cells == active_cells ? vec(values) : vec(values)[active_positions]
        elseif length(values) == length(cells)
            fields[label] = vec(values)
        end
    end
    return fields
end

function eclipse_field_label(key, unit_system)
    # The numeric arrays keep the units declared by the binary Eclipse header.
    if key in ("PRESSURE", "PBUB", "PDEW")
        unit = get(("bar", "psi", "atm", "atm"), unit_system, "")
    elseif key in ("TEMP", "TEMPI") && 1 <= unit_system <= 4
        unit = unit_system == 2 ? "°F" : "°C"
    elseif key in ("PERMX", "PERMY", "PERMZ") && 1 <= unit_system <= 4
        unit = "mD"
    else
        unit = ""
    end
    return isempty(unit) ? key : "$key / $unit"
end

function load_eclipse_reservoir(source; static)
    if !isnothing(source.grid)
        grid = GeoEnergyIO.read_egrid(source.grid)
        from_binary = true
    elseif !isnothing(source.deck)
        if lowercase(splitext(source.deck)[2]) == ".grdecl"
            grid = GeoEnergyIO.parse_grdecl_file(source.deck; verbose = false)
        else
            grid = GeoEnergyIO.parse_data_file(source.deck; verbose = false)["GRID"]
        end
        from_binary = false
    else
        throw(ArgumentError("Reservoir plotting needs an EGRID, DATA, or GRDECL file for $(source.base)."))
    end

    mesh = GeoEnergyIO.mesh_from_grid_section(grid; process_pinch = !from_binary)
    active = get(grid, "ACTNUM", trues(Tuple(grid["cartDims"]))) .!= 0
    active_cells = findall(vec(active))
    positions = zeros(Int, length(active))
    positions[active_cells] .= eachindex(active_cells)
    mesh_positions = positions[mesh.cell_map]
    active_positions = all(>(0), mesh_positions) ? mesh_positions : nothing
    cell_fields(data) = eclipse_cell_fields(data, mesh.cell_map, active_cells, active_positions, length(active))
    domain = Jutul.DataDomain(mesh)
    properties = Dict{String, Any}(k => grid[k] for k in DECK_PROPERTIES if haskey(grid, k))
    if !isnothing(source.init)
        merge!(properties, GeoEnergyIO.read_init(source.init))
    end
    for (key, values) in cell_fields(properties)
        domain[key] = values
    end

    steps = Int[]
    states = missing
    if !static && !isnothing(source.restart)
        restart = GeoEnergyIO.read_restart(source.restart)
        fields = cell_fields.(restart)
        if !isempty(fields) && any(!isempty, fields)
            states = fields
            steps = [step["report_step"] for step in restart]
        end
    end
    return (model = domain, states = states, steps = steps)
end

function load_results(source::JutulSource, view; web, static)
    case = result = nothing
    if isdir(source.path)
        isempty(source.reports) && throw(ArgumentError("No native report files found in $(source.path)"))
    elseif lowercase(splitext(source.path)[2]) == ".jld2"
        case, result = JLD2.jldopen(source.path, "r") do file
            return get(file, "case", nothing), get(file, "result", nothing)
        end
        isnothing(case) && isnothing(result) &&
            throw(ArgumentError("A Jutul JLD2 file must store case and/or result. Use its directory for jutul_N.jld2 report files."))
        isnothing(case) || case isa Jutul.JutulCase || throw(ArgumentError("JLD2 entry case must be a JutulCase"))
        isnothing(result) || result isa Union{Jutul.SimResult, JutulDarcy.ReservoirSimResult} ||
            throw(ArgumentError("JLD2 entry result must be a SimResult or ReservoirSimResult"))
    else
        case = load_case(source.path)
    end
    if !isnothing(source.case_path)
        case = load_case(source.case_path)
    end
    # A case script may define new Julia methods alongside the case.
    return Base.invokelatest(load_native_results, source, case, result, view; web, static)
end

reservoir_state(state) = get(state, :Reservoir, state)

function load_native_results(source, case, result, view; web, static)
    has_results = !isempty(source.reports) || !isnothing(result)
    has_curves = has_results && (!isnothing(case) || result isa JutulDarcy.ReservoirSimResult)
    use_curves = view in (:summary, :wells) || (view == :auto && has_curves)
    use_grid = view == :reservoir || (view == :auto && (web || !use_curves) && !isnothing(case))
    if (use_grid || (use_curves && has_results && !has_curves) || (!use_grid && !use_curves)) && isnothing(case)
        throw(ArgumentError("Native report files need --case CASE.jl, CASE.DATA, CASE.AFI, or a JLD2 file containing a JutulCase."))
    end
    use_curves && !has_results && throw(ArgumentError("This Jutul case has no simulation results."))
    states = missing
    steps = Int[]
    summary = nothing
    if result isa JutulDarcy.ReservoirSimResult
        summary = use_curves ? result.summary : nothing
        if use_grid && !static
            states = result.states
            steps = collect(eachindex(states))
        end
    elseif use_curves || (use_grid && !static)
        if result isa Jutul.SimResult
            raw_states, reports = result.states, result.reports[eachindex(result.states)]
            steps = collect(eachindex(raw_states))
        elseif !isempty(source.reports)
            steps = source.reports
            saved = [Jutul.read_restart(source.path, step; read_report = use_curves) for step in steps]
            raw_states = first.(saved)
            reports = last.(saved)
        else
            raw_states, reports = [], []
        end
        if use_curves
            problem = if isempty(raw_states)
                "No saved states found in the Jutul results."
            elseif steps != eachindex(steps)
                "Reconstructing native summary curves requires consecutive reports starting at jutul_1.jld2."
            elseif !all(r -> r isa AbstractDict && haskey(r, :ministeps), reports)
                "Reconstructing summary curves requires saved Jutul reports. Save report_level >= 0 or store the ReservoirSimResult instead."
            end
            if isnothing(problem)
                sim = Jutul.SimResult(raw_states, reports, now())
                output = JutulDarcy.ReservoirSimResult(case.model, sim, case.forces; start_date = case.start_date)
                summary = JutulDarcy.summary_result(case, output, :si; start_date = case.start_date)
            elseif view == :auto
                use_grid = true
            else
                throw(ArgumentError(problem))
            end
        end
        if use_grid && !static && !isempty(raw_states)
            states = map(reservoir_state, raw_states)
        end
    end
    isempty_states = ismissing(states) || isempty(states)
    reservoir = use_grid ? (model = case.model, states = isempty_states ? missing : states,
        steps = isempty_states ? Int[] : steps) : nothing
    return (; summary, reservoir)
end
