function case_browser_directory(path)
    absolute = abspath(path)
    return isdir(absolute) ? absolute : dirname(absolute)
end

function case_browser_locations()
    locations = [("Working directory", pwd()), ("Home", homedir())]
    if Sys.iswindows()
        drives = ccall((:GetLogicalDrives, "kernel32"), UInt32, ())
        for (index, letter) in enumerate('A':'Z')
            iszero(drives & (UInt32(1) << (index - 1))) && continue
            push!(locations, ("Drive $letter:", "$letter:\\"))
        end
    end
    return unique!(last, locations)
end

function case_browser_listing(path, mode)
    mode in ("case", "companion", "eclipse-deck") || throw(ArgumentError("Unknown file selection mode."))
    directory = abspath(path)
    folders = Tuple{String, String, String}[]
    files = empty(folders)
    contains_reports = false
    contains_case = false
    for name in sort!(readdir(directory; sort = false); by = lowercase)
        entry = joinpath(directory, name)
        if isdir(entry)
            push!(folders, (name, entry, "Folder"))
        elseif isfile(entry)
            ext = lowercase(splitext(name)[2])
            report = occursin(NATIVE_REPORT, name)
            eclipse = is_eclipse_extension(ext)
            contains_reports |= report
            contains_case |= is_eclipse_directory_candidate(ext) || ext == ".jld2"
            if mode == "eclipse-deck"
                ext == ".data" || continue
            elseif mode == "companion"
                ext in (".jl", ".afi", ".jld2", ".data") && !report || continue
            else
                eclipse || ext in (".jl", ".afi", ".jld2") || continue
            end
            kind = report ? "Jutul report" : eclipse ? "Eclipse" : "Jutul"
            push!(files, (name, entry, kind))
        end
    end
    parent = dirname(directory)
    return Dict{String, Any}("directory" => directory, "parent" => parent == directory ? "" : parent,
        "locations" => case_browser_locations(), "entries" => append!(folders, files),
        "folderCase" => mode == "case" && contains_case, "nativeReports" => contains_reports)
end

function mount_case_browser!(bonito, session, dialog, actions, switch_case)
    request = Makie.Observable(String[])
    response = Makie.Observable(Dict{String, Any}())
    status = Makie.Observable("")
    busy = Ref(false)
    bonito.on(session, request) do request
        length(request) == 2 || return
        response[] = try
            case_browser_listing(request...)
        catch err
            err isa InterruptException && rethrow()
            Dict{String, Any}("error" => sprint(showerror, err))
        end
    end
    bonito.on(session, actions) do action
        length(action) == 3 && first(action) == "load" && !busy[] || return
        busy[] = true
        try
            switch_case(action[2], action[3])
        catch err
            err isa InterruptException && rethrow()
            status[] = sprint(showerror, err)
        finally
            busy[] = false
        end
    end
    bonito.onload(session, dialog, web_initializer(bonito, "dialog", CASE_BROWSER_JS, request, response, actions, status))
    return nothing
end

function web_case_dialog(DOM, input)
    location = DOM.select(; class = "case-locations", var"aria-label" = "Server locations")
    up = DOM.button("↑ Up"; type = "button", class = "case-up", var"aria-label" = "Parent folder")
    filter = DOM.input(; type = "search", class = "case-filter", placeholder = "Filter by name",
        var"aria-label" = "Filter files and folders")
    browser = DOM.div(DOM.div(up, location, filter; class = "case-nav"),
        DOM.p(; class = "case-directory", var"aria-label" = "Current folder"),
        DOM.ul(; class = "case-entries", var"aria-label" = "Server files and folders", tabindex = "0"),
        DOM.button("Select this folder"; type = "button", class = "case-folder", hidden = true))
    path = DOM.div(DOM.span("Selected case"), DOM.strong("Choose a file or results folder"; class = "case-path");
        class = "case-selection")
    companion = DOM.div(DOM.span("Companion model"), DOM.strong("Automatic"; class = "case-companion-path"),
        DOM.button("Browse…"; type = "button", class = "case-companion", disabled = true,
            var"aria-label" = "Browse for a companion model"),
        DOM.button("Clear"; type = "button", class = "case-clear", hidden = true); class = "case-selection")
    buttons = DOM.div(DOM.button("Cancel"; type = "button", class = "case-cancel"),
        DOM.button("Load"; type = "button", class = "actions-add case-load", disabled = true);
        class = "controls dialog-actions")
    status = DOM.p(; class = "case-status", role = "status")
    return DOM.dialog(DOM.h2("Load case"; class = "case-title"), browser, path, companion, status, buttons;
        class = "case-dialog", var"aria-label" = "Load case", var"data-directory" = case_browser_directory(input))
end
