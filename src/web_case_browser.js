(dialog, request, response, actions, status) => {
    const open = dialog.parentElement.querySelector(".case-open");
    const title = dialog.querySelector(".case-title");
    const up = dialog.querySelector(".case-up");
    const locations = dialog.querySelector(".case-locations");
    const filter = dialog.querySelector(".case-filter");
    const directory = dialog.querySelector(".case-directory");
    const entries = dialog.querySelector(".case-entries");
    const folder = dialog.querySelector(".case-folder");
    const path = dialog.querySelector(".case-path");
    const companionPath = dialog.querySelector(".case-companion-path");
    const companionButton = dialog.querySelector(".case-companion");
    const clear = dialog.querySelector(".case-clear");
    const cancel = dialog.querySelector(".case-cancel");
    const load = dialog.querySelector(".case-load");
    const message = dialog.querySelector(".case-status");
    let mode = "case";
    let caseDirectory = dialog.dataset.directory;
    let listing = null;
    let selected = null;
    let companion = null;
    let browsing = false;
    let loading = false;

    function controls() {
        entries.inert = browsing || loading;
        up.disabled = browsing || loading || !listing?.parent;
        locations.disabled = browsing || loading;
        folder.disabled = browsing || loading;
        folder.hidden = mode !== "case" || !listing?.folderCase;
        path.textContent = selected?.name ?? "Choose a file or results folder";
        path.title = selected?.path ?? "";
        companionPath.textContent = companion?.name ?? (selected?.needsModel ? "Required for Jutul reports" : "Automatic");
        companionPath.title = companion?.path ?? "";
        companionButton.disabled = browsing || loading || !selected || mode !== "case";
        clear.hidden = !companion || mode !== "case";
        clear.disabled = loading;
        cancel.disabled = browsing || loading;
        load.hidden = mode !== "case";
        load.disabled = browsing || loading || !selected || (selected.needsModel && !companion);
    }

    function browse(target, nextMode = mode) {
        if (!target || browsing || loading) return;
        if (mode !== nextMode) {
            listing = null;
            directory.textContent = "";
            entries.replaceChildren();
        }
        mode = nextMode;
        browsing = true;
        const heading = mode === "case" ? "Load case" : mode === "eclipse-deck" ? "Choose Eclipse deck" : "Choose companion model";
        title.textContent = heading;
        dialog.setAttribute("aria-label", heading);
        cancel.textContent = mode === "case" ? "Cancel" : "Back to case";
        message.textContent = "Reading server folder…";
        controls();
        request.notify([target, mode]);
    }

    function select(name, fullPath, kind) {
        if (mode !== "case") {
            companion = {name, path: fullPath};
            browse(caseDirectory, "case");
        } else {
            if (selected?.path !== fullPath) companion = null;
            selected = {name, path: fullPath, directory: listing.directory,
                needsModel: kind === "Jutul report", companionMode: kind === "Eclipse" ? "eclipse-deck" : "companion"};
            message.textContent = "";
            for (const button of entries.querySelectorAll("button[aria-pressed]")) {
                button.setAttribute("aria-pressed", String(button.value === fullPath));
            }
            controls();
        }
    }

    function renderEntries() {
        const search = filter.value.trim().toLocaleLowerCase();
        const fragment = document.createDocumentFragment();
        for (const [name, fullPath, kind] of listing?.entries ?? []) {
            if (!name.toLocaleLowerCase().includes(search)) continue;
            const item = document.createElement("li");
            const button = document.createElement("button");
            button.type = "button";
            button.value = fullPath;
            button.dataset.kind = kind;
            const label = document.createElement("span");
            label.textContent = name;
            const badge = document.createElement("small");
            badge.textContent = kind === "Folder" ? "Folder ›" : kind;
            button.append(label, badge);
            if (kind === "Folder") {
                button.addEventListener("click", () => browse(fullPath));
            } else {
                const current = mode === "case" ? selected : companion;
                button.setAttribute("aria-pressed", String(current?.path === fullPath));
                button.addEventListener("click", () => select(name, fullPath, kind));
            }
            item.append(button);
            fragment.append(item);
        }
        if (!fragment.childElementCount) {
            const empty = document.createElement("li");
            empty.className = "case-empty";
            empty.textContent = search ? "No matching files or folders." : "No supported files or folders here.";
            fragment.append(empty);
        }
        entries.replaceChildren(fragment);
    }

    response.on(value => {
        browsing = false;
        if (value.error) {
            message.textContent = value.error;
            controls();
            return;
        }
        listing = value;
        if (mode === "case") caseDirectory = listing.directory;
        directory.textContent = listing.directory;
        locations.replaceChildren(new Option("Server locations", "", true, true),
            ...listing.locations.map(([label, value]) => new Option(label, value)));
        filter.value = "";
        renderEntries();
        message.textContent = "";
        controls();
        filter.focus();
    });
    status.on(error => {
        loading = false;
        message.textContent = error;
        controls();
    });

    open.addEventListener("click", () => {
        dialog.showModal();
        browse(caseDirectory, "case");
    });
    filter.addEventListener("input", renderEntries);
    locations.addEventListener("change", () => browse(locations.value));
    up.addEventListener("click", () => browse(listing?.parent));
    folder.addEventListener("click", () => select(listing.directory, listing.directory, listing.nativeReports ? "Jutul report" : "Folder"));
    companionButton.addEventListener("click", () => browse(selected.directory, selected.companionMode));
    clear.addEventListener("click", () => { companion = null; controls(); });
    cancel.addEventListener("click", () => {
        if (mode !== "case") browse(caseDirectory, "case");
        else dialog.close();
    });
    dialog.addEventListener("cancel", event => {
        if (loading || browsing || mode !== "case") {
            event.preventDefault();
            if (mode !== "case") browse(caseDirectory, "case");
        }
    });
    load.addEventListener("click", () => {
        loading = true;
        message.textContent = "Loading case…";
        controls();
        actions.notify(["load", selected.path, companion?.path ?? ""]);
    });
}
