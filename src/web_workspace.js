(root, actions, plotStatus, sourceText) => {
    document.title = "jdplot · " + root.querySelector("h1").textContent;
    const main = root.closest(".jdplot");
    const stage = root.querySelector(".workspace-stage");
    const message = root.querySelector(".workspace-message");
    const uniqueId = () => globalThis.crypto?.randomUUID?.() ?? Date.now() + "-" + Math.random().toString(36).slice(2);
    let token = history.state?.jdplotWorkspace;
    if (!token) {
        token = uniqueId();
        history.replaceState({...history.state, jdplotWorkspace: token}, "");
    }
    const key = "jdplot.workspace.v1/" + token + "/" + main.dataset.workspace;
    const caseKey = JSON.stringify([root.dataset.input, root.dataset.companion]);
    let workspace = main.jdplotWorkspace;
    if (!workspace) {
        try { workspace = JSON.parse(localStorage.getItem(key)); } catch { /* Storage can be disabled. */ }
        workspace ??= {active: null, cases: {}};
        main.jdplotWorkspace = workspace;
    }
    const savedCase = workspace.cases[caseKey];
    const records = new Map((savedCase?.plots ?? []).map(record => [record.id, record]));
    const statistics = savedCase?.statistics ?? {};
    let resuming = false;
    let timer;
    let restoreWindows = () => {};
    function save() {
        clearTimeout(timer);
        if (resuming || !root.isConnected) return;
        workspace.active = caseKey;
        workspace.cases[caseKey] = {plots: [...records.values()], statistics};
        try { localStorage.setItem(key, JSON.stringify(workspace)); } catch { /* Keep the live workspace. */ }
    }
    function scheduleSave() {
        clearTimeout(timer);
        timer = setTimeout(save, 160);
    }
    const lifecycle = new AbortController();
    window.addEventListener("pagehide", save, {signal: lifecycle.signal});
    const cleanup = new MutationObserver(() => {
        if (root.isConnected) return;
        lifecycle.abort();
        clearTimeout(timer);
        cleanup.disconnect();
    });
    cleanup.observe(main, {childList: true, subtree: true});
    if (!main.dataset.jdplotStarted) {
        main.dataset.jdplotStarted = "true";
        if (workspace.active && workspace.active !== caseKey && root.querySelector(".case-open")) {
            const [input, companion] = JSON.parse(workspace.active);
            resuming = true;
            message.textContent = "Restoring the active case…";
            actions.notify(["load", input, companion]);
        }
    }
    root.addEventListener("jdplot:case-error", event => {
        if (!resuming) return;
        resuming = false;
        message.textContent = "Could not restore the active case. " + event.detail;
        restoreWindows();
        save();
    });

    const stats = root.querySelector(".stats-dialog");
    root.querySelector(".stats-open").addEventListener("click", () => {
        stats.showModal();
        actions.notify(["stats", statistics.summary ?? "", statistics.report ?? ""]);
    });
    stats.addEventListener("change", event => {
        const selector = event.target;
        if (selector.matches(".stats-entity")) statistics.summary = String(selector.selectedIndex + 1);
        else if (selector.matches(".stats-report")) statistics.report = String(selector.selectedIndex + 1);
        else return;
        save();
    });
    stats.querySelector(".stats-close").addEventListener("click", () => stats.close());

    const source = root.querySelector(".source-dialog");
    if (source) {
        const choice = source.querySelector(".source-choice");
        const path = source.querySelector(".source-path");
        const editor = source.querySelector(".source-editor");
        function loadSource() {
            path.textContent = "Reading file…";
            editor.value = "";
            actions.notify(["source", choice.value]);
        }
        root.querySelector(".source-open").addEventListener("click", () => { source.showModal(); loadSource(); });
        source.querySelector(".source-close").addEventListener("click", () => source.close());
        choice.addEventListener("change", loadSource);
        sourceText.on(([filename, content, status]) => {
            path.textContent = filename + " · " + status;
            editor.value = content;
            editor.scrollTop = editor.scrollLeft = 0;
        });
    }

    function selectTab(body, key) {
        for (const choice of body.querySelectorAll("[data-tab]")) {
            choice.setAttribute("aria-pressed", String(choice.dataset.tab === key));
        }
        for (const plot of body.querySelectorAll("[data-plot]")) {
            plot.hidden = plot.dataset.plot !== key;
        }
    }
    root.addEventListener("click", event => {
        const tab = event.target.closest("[data-tab]");
        if (!tab) return;
        selectTab(tab.closest(".view-body"), tab.dataset.tab);
        const record = records.get(tab.closest("[data-window-id]").dataset.windowId);
        if (record) { record.tab = tab.dataset.tab; save(); }
    });
    root.addEventListener("jdplot:control", event => {
        const plot = event.target;
        const owner = plot.closest("[data-window-id]");
        const record = owner && records.get(owner.dataset.windowId);
        if (!record) return;
        const [name, value] = event.detail;
        const controls = record.controls[plot.dataset.plot] ??= {};
        if (name === "widgets") {
            const widgets = Object.fromEntries(event.detail.slice(1).map((value, index) => [index + 1, value]));
            if (controls.camera) widgets.camera = controls.camera;
            record.controls[plot.dataset.plot] = widgets;
            scheduleSave();
            return;
        }
        if (controls[name] === value) return;
        controls[name] = value;
        scheduleSave();
    });
    function wireRecord(node, record) {
        if ([...node.querySelectorAll("[data-tab]")].some(tab => tab.dataset.tab === record.tab)) {
            selectTab(node.querySelector(".view-body"), record.tab);
        }
        for (const plot of node.querySelectorAll("[data-plot]")) {
            const controls = record.controls[plot.dataset.plot];
            if (!controls) continue;
            const entries = Object.entries(controls).map(([name, value]) => name + "=" + value);
            const restore = () => plot.dispatchEvent(new CustomEvent("jdplot:restore", {detail: entries}));
            if (plot.dataset.controlsReady) restore();
            else plot.addEventListener("jdplot:controls-ready", restore, {once: true});
        }
    }
    function defaultRecord(node) {
        return {id: node.dataset.windowId, view: node.dataset.view, options: [], controls: {}};
    }
    if (!stage) {
        for (const node of root.querySelectorAll("[data-window-id]")) {
            const record = records.get(node.dataset.windowId) ?? defaultRecord(node);
            records.set(record.id, record);
            wireRecord(node, record);
        }
        save();
        return;
    }

    const picker = root.querySelector(".plot-dialog");
    const add = root.querySelector(".plot-open");
    const form = picker.querySelector("form");
    const submit = picker.querySelector(".plot-submit");
    const error = picker.querySelector(".plot-error");
    const presets = picker.querySelector(".summary-preset");
    const pending = new Map();
    let kind, adding;
    function pickKind(value) {
        kind = value;
        error.textContent = "";
        for (const tab of picker.querySelectorAll("[data-kind]")) {
            tab.setAttribute("aria-pressed", String(tab.dataset.kind === kind));
        }
        for (const group of picker.querySelectorAll("[data-options]")) {
            group.hidden = group.dataset.options !== kind;
            for (const input of group.querySelectorAll("[name]")) input.disabled = group.hidden;
        }
    }
    picker.querySelector(".plot-kinds").addEventListener("click", event => {
        const tab = event.target.closest("[data-kind]");
        if (tab && !adding) pickKind(tab.dataset.kind);
    });
    const staticOnly = form.elements.static_only;
    staticOnly?.addEventListener("change", () => {
        const field = form.elements.field;
        for (const option of field.options) option.hidden = staticOnly.checked && option.dataset.static !== "true";
        if (field.selectedOptions[0]?.hidden) field.value = "";
    });
    presets?.addEventListener("change", () => {
        const option = presets.selectedOptions[0];
        if (!option.value) return;
        for (const name of ["plots", "rows", "cols"]) form.elements[name].value = option.dataset[name];
    });
    for (const name of ["plots", "rows", "cols"]) {
        form.elements[name]?.addEventListener("input", () => { presets.value = ""; });
    }
    add.addEventListener("click", () => {
        pickKind(kind ?? picker.querySelector("[data-kind]").dataset.kind);
        picker.showModal();
    });
    picker.querySelector(".plot-cancel").addEventListener("click", () => picker.close());
    picker.addEventListener("cancel", event => { if (adding) event.preventDefault(); });
    form.addEventListener("submit", event => {
        event.preventDefault();
        if (adding) return;
        const group = form.querySelector("[data-options]:not([hidden])");
        const options = [...group.querySelectorAll("[name]")].map(input =>
            input.name + "=" + (input.type === "checkbox" ? input.checked : input.value));
        const record = {id: uniqueId(), view: kind, options, controls: {}};
        adding = record.id;
        submit.disabled = picker.querySelector(".plot-cancel").disabled = true;
        error.textContent = "Building plot…";
        pending.set(record.id, record);
        actions.notify(["add", record.id, record.view, ...record.options]);
    });
    function finishAdd() {
        adding = null;
        submit.disabled = picker.querySelector(".plot-cancel").disabled = false;
    }
    plotStatus.on(([id, reason]) => {
        pending.delete(id);
        if (adding === id) {
            finishAdd();
            error.textContent = reason;
        } else if (records.has(id)) {
            message.textContent = "Could not restore a plot. " + reason;
        }
    });

    const stacked = window.matchMedia("(max-width: 720px)");
    const windows = new Map();
    const snapDistance = 18;
    let layer = Math.max(0, ...[...records.values()].map(record => record.layer ?? 0));
    let sequence = 0;

    function put(window, box) {
        const width = Math.min(stage.clientWidth, Math.max(300, box.width));
        const height = Math.min(stage.clientHeight, Math.max(300, box.height));
        const right = Math.max(0, stage.clientWidth - width);
        const bottom = Math.max(0, stage.clientHeight - height);
        function snap(value, edge) {
            if (value < snapDistance) return 0;
            if (value > edge - snapDistance) return edge;
            return value;
        }
        const left = snap(box.left, right);
        const top = snap(box.top, bottom);
        const placed = {left, top, width, height};
        windows.set(window, placed);
        for (const [key, value] of Object.entries(placed)) window.style[key] = value + "px";
    }

    function initialBox(index, count, view) {
        const width = stage.clientWidth;
        const height = stage.clientHeight;
        if (count === 1 && index === 0) {
            return {left: 0, top: 0, width, height};
        }
        if (count > 1 && index < 2) {
            const leftWidth = Math.round((width - 8) * 0.46);
            return index === 0 ? {left: 0, top: 0, width: leftWidth, height} :
                {left: leftWidth + 8, top: 0, width: width - leftWidth - 8, height};
        }
        const offset = 38 + (index % 6) * 28;
        return {left: offset, top: offset,
            width: Math.min(view === "reservoir" ? 1020 : 880, width * 0.82),
            height: Math.min(720, height * 0.88)};
    }

    function windowInteraction(window, handle, resize) {
        let drag = null;
        function commitGeometry() {
            records.get(window.dataset.windowId).box = windows.get(window);
            save();
        }
        handle.addEventListener("pointerdown", event => {
            if (stacked.matches || window.classList.contains("window-maximized") || event.button !== 0 || drag) return;
            drag = {pointer: event.pointerId, x: event.clientX, y: event.clientY, box: windows.get(window)};
            handle.focus({preventScroll: true});
            handle.setPointerCapture(event.pointerId);
            event.preventDefault();
        });
        handle.addEventListener("pointermove", event => {
            if (drag?.pointer !== event.pointerId) return;
            const {box, x, y} = drag;
            const dx = event.clientX - x;
            const dy = event.clientY - y;
            if (resize) {
                put(window, {...box,
                    width: Math.min(stage.clientWidth - box.left, box.width + dx),
                    height: Math.min(stage.clientHeight - box.top, box.height + dy)});
            } else {
                put(window, {...box, left: box.left + dx, top: box.top + dy});
            }
        });
        handle.addEventListener("lostpointercapture", () => {
            if (!drag) return;
            drag = null;
            commitGeometry();
        });
        handle.addEventListener("keydown", event => {
            if (stacked.matches || window.classList.contains("window-maximized")) return;
            const directions = {ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1]};
            const direction = directions[event.key];
            if (!direction) return;
            const [dx, dy] = direction.map(d => 24 * d);
            const box = windows.get(window);
            put(window, resize ? {...box, width: box.width + dx, height: box.height + dy} :
                {...box, left: box.left + dx, top: box.top + dy});
            commitGeometry();
            event.preventDefault();
            event.stopPropagation();
        });
    }

    function removeWindow(window) {
        let wrapper = window;
        while (wrapper.parentElement && wrapper.parentElement !== stage) wrapper = wrapper.parentElement;
        wrapper.remove();
    }

    function mount(window, count) {
        const id = window.dataset.windowId;
        const record = pending.get(id) ?? records.get(id) ?? defaultRecord(window);
        pending.delete(id);
        records.set(id, record);
        const index = sequence++;
        const view = window.dataset.view;
        const box = record.box ?? initialBox(index, count, view);
        put(window, box);
        record.box ??= box;
        record.layer ??= ++layer;
        window.style.zIndex = record.layer;
        const front = () => {
            if (record.layer === layer) return;
            window.style.zIndex = record.layer = ++layer;
            scheduleSave();
        };
        window.addEventListener("pointerdown", front);
        window.addEventListener("focusin", front);
        windowInteraction(window, window.querySelector(".window-title"), false);
        windowInteraction(window, window.querySelector(".window-resize"), true);
        const maximize = window.querySelector(".window-maximize");
        const title = window.querySelector("h2").textContent;
        function setMaximized(expanded) {
            window.classList.toggle("window-maximized", expanded);
            const label = (expanded ? "Restore " : "Maximize ") + title + " window";
            maximize.setAttribute("aria-pressed", String(expanded));
            maximize.setAttribute("aria-label", label);
            maximize.title = label;
            maximize.textContent = expanded ? "❐" : "□";
            record.maximized = expanded;
        }
        setMaximized(Boolean(record.maximized));
        maximize.addEventListener("click", () => {
            setMaximized(!record.maximized);
            front();
            save();
        });
        window.querySelector(".window-close").addEventListener("click", () => {
            removeWindow(window);
            windows.delete(window);
            records.delete(id);
            save();
            add.focus({preventScroll: true});
        });
        wireRecord(window, record);
        if (adding === id) {
            finishAdd();
            picker.close();
        }
    }

    const initial = [...stage.querySelectorAll(".plot-window")];
    const mounted = new Set();
    for (const window of initial) {
        const id = window.dataset.windowId;
        if (savedCase && !records.has(id)) {
            removeWindow(window);
        } else {
            mount(window, initial.length);
            mounted.add(id);
        }
    }
    const observer = new MutationObserver(() => {
        let added = false;
        for (const window of stage.querySelectorAll(".plot-window")) {
            if (!windows.has(window)) { mount(window, 0); added = true; }
        }
        if (added) save();
    });
    observer.observe(stage, {childList: true, subtree: true});
    const resizeObserver = new ResizeObserver(() => {
        if (stacked.matches) return;
        for (const [window, box] of windows) put(window, box);
    });
    resizeObserver.observe(stage);
    lifecycle.signal.addEventListener("abort", () => {
        observer.disconnect();
        resizeObserver.disconnect();
    });
    restoreWindows = () => {
        for (const record of records.values()) {
            if (!mounted.has(record.id)) actions.notify(["add", record.id, record.view, ...record.options]);
        }
    };
    if (!resuming) restoreWindows();
    save();
}
