const ECLIPSE_EXTENSIONS = (".DATA", ".GRDECL", ".EGRID", ".INIT", ".UNRST", ".RSSPEC", ".SMSPEC", ".UNSMRY")
const NATIVE_REPORT = r"^jutul_([1-9][0-9]*)\.jld2$"

is_eclipse_extension(ext) = uppercase(ext) in ECLIPSE_EXTENSIONS || occursin(r"^\.[XS][0-9]+$"i, ext)

struct EclipseSource
    base::String
    deck::Union{String, Nothing}
    grid::Union{String, Nothing}
    init::Union{String, Nothing}
    restart::Union{String, Nothing}
    has_summary::Bool
end

struct JutulSource
    path::String
    case_path::Union{String, Nothing}
    reports::Vector{Int}
end

case_name(source::EclipseSource) = basename(source.base)
case_name(source::JutulSource) = isdir(source.path) ? basename(source.path) : splitext(basename(source.path))[1]

function native_reports(directory)
    steps = Int[]
    for path in readdir(directory; join = true)
        report = match(NATIVE_REPORT, basename(path))
        if !isnothing(report) && isfile(path)
            push!(steps, parse(Int, only(report.captures)))
        end
    end
    return sort!(steps)
end

function eclipse_source(path)
    stem, ext = splitext(path)
    base = is_eclipse_extension(ext) ? stem : path
    directory, name = splitdir(base)
    files = Dict{String, String}()
    for file in readdir(directory; join = true)
        sibling, ext = splitext(basename(file))
        same_name = sibling == name || (Sys.iswindows() && lowercase(sibling) == lowercase(name))
        if same_name && is_eclipse_extension(ext) && isfile(file)
            files[uppercase(ext)] = file
        end
    end
    if Sys.iswindows() && !isempty(files)
        # GeoEnergyIO discovers split files by their on-disk case prefix.
        base = splitext(first(values(files)))[1]
    end
    deck = get(files, ".DATA", get(files, ".GRDECL", nothing))
    grid = get(files, ".EGRID", nothing)
    init = get(files, ".INIT", nothing)
    restart = get(files, ".UNRST", nothing)
    if isfile(path) && occursin(r"^\.X[0-9]+$"i, splitext(path)[2])
        restart = path
    elseif isnothing(restart) && any(k -> occursin(r"^\.X[0-9]+$", k), keys(files))
        restart = base
    end
    has_summary = haskey(files, ".SMSPEC") &&
        (haskey(files, ".UNSMRY") || any(k -> occursin(r"^\.S[0-9]+$", k), keys(files)))
    if isnothing(deck) && isnothing(grid) && !has_summary && isnothing(restart)
        throw(ArgumentError("No Eclipse deck, grid, restart, or complete summary found for $base"))
    end
    return EclipseSource(base, deck, grid, init, restart, has_summary)
end

function directory_input(directory; companion)
    reports = native_reports(directory)
    if !isnothing(companion) && !isempty(reports)
        return directory, reports
    end
    candidates = String[]
    if !isempty(reports)
        push!(candidates, directory)
    end
    for file in readdir(directory; join = true)
        isfile(file) || continue
        stem, ext = splitext(file)
        if uppercase(ext) in (".DATA", ".GRDECL", ".EGRID", ".SMSPEC", ".UNSMRY", ".UNRST") ||
                occursin(r"^\.[XS][0-9]+$"i, ext)
            push!(candidates, stem)
        elseif lowercase(ext) == ".jld2" && isnothing(match(NATIVE_REPORT, basename(file)))
            push!(candidates, file)
        end
    end
    unique!(Sys.iswindows() ? lowercase : identity, candidates)
    isempty(candidates) && throw(ArgumentError("No Eclipse case or Jutul results found in $directory"))
    length(candidates) == 1 || throw(ArgumentError("Several cases found in $directory. Pass a case file or prefix: $(join(candidates, ", "))"))
    return only(candidates), reports
end

function resolve_input(input; companion = nothing)
    path = abspath(input)
    reports = Int[]
    if isdir(path)
        path, reports = directory_input(path; companion)
    elseif !isdir(dirname(path))
        throw(ArgumentError("Input directory does not exist: $(dirname(path))"))
    end
    ext = lowercase(splitext(path)[2])
    if isdir(path) || ext in (".jl", ".afi", ".jld2")
        ispath(path) || throw(ArgumentError("Input file does not exist: $path"))
        if isfile(path) && !isnothing(match(NATIVE_REPORT, basename(path)))
            path = dirname(path)
            reports = native_reports(path)
        end
        return JutulSource(path, companion, reports)
    end
    isnothing(companion) || throw(ArgumentError("--case is for Jutul results. Point Eclipse inputs at their case prefix or one of the case files."))
    is_eclipse_extension(ext) && !isfile(path) && throw(ArgumentError("Input file does not exist: $path"))
    return eclipse_source(path)
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
