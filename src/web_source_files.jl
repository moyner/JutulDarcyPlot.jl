const CASE_LOG_EXTENSIONS = (".DBG", ".PRT")
const CASE_TEXT_EXTENSIONS = (".DATA", ".GRDECL", ".AFI", ".JL", CASE_LOG_EXTENSIONS...)

function append_case_text_files!(candidates, directory, name, extensions)
    for entry in readdir(directory)
        stem, ext = splitext(entry)
        same_case = isnothing(name) || (Sys.iswindows() ? lowercase(stem) == lowercase(name) : stem == name)
        if same_case && uppercase(ext) in extensions
            push!(candidates, joinpath(directory, entry))
        end
    end
    return candidates
end

function case_source_files(source::EclipseSource)
    candidates = Union{Nothing, String}[source.deck]
    directory, name = splitdir(source.base)
    append_case_text_files!(candidates, directory, name, (".DATA", ".GRDECL", CASE_LOG_EXTENSIONS...))
    return case_text_paths(candidates)
end

function case_source_files(source::JutulSource)
    candidates = Union{Nothing, String}[source.path, source.case_path]
    if isdir(source.path)
        append_case_text_files!(candidates, source.path, nothing, CASE_LOG_EXTENSIONS)
    else
        directory, name = splitdir(splitext(source.path)[1])
        append_case_text_files!(candidates, directory, name, CASE_LOG_EXTENSIONS)
    end
    return case_text_paths(candidates)
end

case_source_files(::Nothing) = String[]

function case_text_paths(candidates)
    paths = String[]
    for path in candidates
        isnothing(path) && continue
        if uppercase(splitext(path)[2]) in CASE_TEXT_EXTENSIONS && isfile(path)
            push!(paths, abspath(path))
        end
    end
    return unique!(Sys.iswindows() ? lowercase : identity, paths)
end

function web_source_dialog(DOM, files)
    select = DOM.select([DOM.option(basename(path); value = i, title = path) for (i, path) in enumerate(files)]...;
        var"aria-label" = "Case file", class = "source-choice")
    controls = DOM.div(select, DOM.button("Close"; type = "button", class = "source-close"); class = "controls")
    title = DOM.div(DOM.h2("Case files"), controls; class = "stats-heading")
    path = DOM.p(; class = "source-path", role = "status")
    editor = DOM.textarea(; class = "source-editor", readonly = true, wrap = "off", spellcheck = "false",
        var"aria-label" = "Case file contents")
    return DOM.dialog(title, path, editor; class = "source-dialog", var"aria-label" = "Case files")
end

function source_file_preview(path)
    limit = 4 * 1024 * 1024
    bytes = open(io -> read(io, limit + 1), path)
    truncated = length(bytes) > limit
    if truncated
        resize!(bytes, limit)
    end
    # Remove malformed sequences without allowing binary bytes into the editor's text.
    content = String(bytes)
    if !isvalid(content)
        content = join(isvalid(c) ? c : '\ufffd' for c in content)
    end
    return [path, content, truncated ? "Showing the first 4 MiB" : "Read only"]
end

function listen_for_source_file(bonito, session, actions, response, files)
    bonito.on(session, actions) do action
        length(action) == 2 && first(action) == "source" || return
        index = tryparse(Int, action[2])
        isnothing(index) && return
        checkbounds(Bool, files, index) || return
        response[] = try
            source_file_preview(files[index])
        catch err
            err isa InterruptException && rethrow()
            [files[index], "", sprint(showerror, err)]
        end
    end
end
