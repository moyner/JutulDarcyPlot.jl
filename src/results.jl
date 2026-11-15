function load_results(source::EclipseSource, view; web, static)
    use_curves = view in (:summary, :wells, :combined) || (view == :auto && source.has_summary)
    has_grid = !isnothing(source.grid) || !isnothing(source.deck)
    use_grid = view in (:reservoir, :combined) || (view == :auto && (web || !use_curves) && has_grid)

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

function eclipse_cell_fields(data, cells, nactive, active_positions, nfull, full_ordered, active_ordered)
    header = get(data, "INTEHEAD", Int[])
    unit_system = get(header, 3, 0)
    fields = Dict{Symbol, Any}()
    for (key, values) in pairs(data)
        key in ECLIPSE_METADATA && continue
        values isa AbstractArray{<:Real} && !(values isa AbstractArray{Bool}) || continue
        label = Symbol(eclipse_field_label(key, unit_system))
        if length(values) == nfull
            fields[label] = full_ordered ? vec(values) : vec(values)[cells]
        elseif length(values) == nactive && !isnothing(active_positions)
            fields[label] = active_ordered ? vec(values) : vec(values)[active_positions]
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
    deck = nothing
    has_deck = !isnothing(source.deck) && uppercase(splitext(source.deck)[2]) == ".DATA"
    if !isnothing(source.grid)
        grid = GeoEnergyIO.read_egrid(source.grid)
        from_binary = true
    elseif !isnothing(source.deck)
        if lowercase(splitext(source.deck)[2]) == ".grdecl"
            grid = GeoEnergyIO.parse_grdecl_file(source.deck; verbose = false)
        else
            deck = GeoEnergyIO.parse_data_file(source.deck; verbose = false)
            grid = deck["GRID"]
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
    full_ordered = length(mesh.cell_map) == length(active) && issorted(mesh.cell_map)
    active_ordered = mesh.cell_map == active_cells
    cell_fields(data) = eclipse_cell_fields(data, mesh.cell_map, length(active_cells), active_positions,
        length(active), full_ordered, active_ordered)
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
    logical_cells = LinearIndices(Tuple(grid["cartDims"]))
    cell_map = zeros(Int, length(logical_cells))
    cell_map[mesh.cell_map] .= eachindex(mesh.cell_map)
    completions = Dict{String, Vector{Int}}()
    if static && has_deck
        isnothing(deck) && (deck = GeoEnergyIO.parse_data_file(source.deck; verbose = false))
        add_deck_completions!(completions, deck, logical_cells, cell_map)
    end
    if !isnothing(source.restart) && (!static || isempty(completions))
        restart = GeoEnergyIO.read_restart(source.restart)
        for report in restart
            add_restart_completions!(completions, report, logical_cells, cell_map)
        end
        if !static
            fields = cell_fields.(restart)
            if !isempty(fields) && any(!isempty, fields)
                states = fields
                steps = [step["report_step"] for step in restart]
            end
        end
    end
    if !static && isempty(completions) && has_deck
        isnothing(deck) && (deck = GeoEnergyIO.parse_data_file(source.deck; verbose = false))
        add_deck_completions!(completions, deck, logical_cells, cell_map)
    end
    wells = [JutulDarcy.SimpleWell(unique(cells); name = Symbol(name)) for (name, cells) in sort!(collect(completions); by = first)]
    return (model = domain, states = states, steps = steps, wells = wells)
end

function load_case(path)
    path = abspath(path)
    isfile(path) || throw(ArgumentError("Case file does not exist: $path"))
    ext = lowercase(splitext(path)[2])
    if ext == ".jl"
        # Use a fresh module so an unrelated global named `case` cannot be reused.
        scope = Module(gensym(:JDPlotCase))
        Core.eval(scope, :(const include = Base.Fix1(Base.include, $scope)))
        Base.include(scope, path)
        case = Base.invokelatest() do
            isdefined(scope, :case) ? getfield(scope, :case) : nothing
        end
    elseif ext == ".data"
        case = JutulDarcy.setup_case_from_data_file(path; verbose = false, parse_arg = (; verbose = false))
    elseif ext == ".afi"
        case = JutulDarcy.setup_case_from_afi(path; verbose = false)
    elseif ext == ".jld2"
        case = JLD2.jldopen(path, "r") do file
            get(file, "case", nothing)
        end
    else
        throw(ArgumentError("Expected a .jl, .DATA, .AFI, or .jld2 case file, got $path"))
    end
    case isa Jutul.JutulCase || throw(ArgumentError("$path must define or store a JutulCase named case"))
    return case
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
    use_curves = view in (:summary, :wells, :combined) || (view == :auto && has_curves)
    use_grid = view in (:reservoir, :combined) || (view == :auto && (web || !use_curves) && !isnothing(case))
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
        steps = isempty_states ? Int[] : steps, wells = missing) : nothing
    return (; summary, reservoir)
end
