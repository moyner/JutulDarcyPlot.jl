(root, actions) => {
    document.title = "jdplot · " + root.querySelector("h1").textContent;
    const stage = root.querySelector(".workspace-stage");
    const stats = root.querySelector(".stats-dialog");
    root.querySelector(".stats-open").addEventListener("click", () => {
        stats.showModal();
        actions.notify(["stats"]);
    });
    stats.querySelector(".stats-close").addEventListener("click", () => stats.close());

    root.addEventListener("click", event => {
        const tab = event.target.closest("[data-tab]");
        if (!tab) return;
        const body = tab.closest(".view-body");
        for (const choice of body.querySelectorAll("[data-tab]")) {
            choice.setAttribute("aria-pressed", String(choice === tab));
        }
        for (const plot of body.querySelectorAll("[data-plot]")) {
            plot.hidden = plot.dataset.plot !== tab.dataset.tab;
        }
    });
    if (!stage) return;

    const choice = root.querySelector(".plot-choice");
    root.querySelector(".actions-add").addEventListener("click", () => actions.notify(["add", choice.value]));
    const stacked = window.matchMedia("(max-width: 720px)");
    const windows = new Map();
    const snapDistance = 18;
    let layer = 0;
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
        handle.addEventListener("lostpointercapture", () => { drag = null; });
        handle.addEventListener("keydown", event => {
            if (stacked.matches || window.classList.contains("window-maximized")) return;
            const directions = {ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1]};
            const direction = directions[event.key];
            if (!direction) return;
            const [dx, dy] = direction.map(d => 24 * d);
            const box = windows.get(window);
            put(window, resize ? {...box, width: box.width + dx, height: box.height + dy} :
                {...box, left: box.left + dx, top: box.top + dy});
            event.preventDefault();
            event.stopPropagation();
        });
    }

    function mount(window, count) {
        const index = sequence++;
        const view = window.dataset.view;
        put(window, initialBox(index, count, view));
        const front = () => { window.style.zIndex = ++layer; };
        front();
        window.addEventListener("pointerdown", front);
        window.addEventListener("focusin", front);
        windowInteraction(window, window.querySelector(".window-title"), false);
        windowInteraction(window, window.querySelector(".window-resize"), true);
        const maximize = window.querySelector(".window-maximize");
        const title = window.querySelector("h2").textContent;
        maximize.addEventListener("click", () => {
            const expanded = window.classList.toggle("window-maximized");
            const label = (expanded ? "Restore " : "Maximize ") + title + " window";
            maximize.setAttribute("aria-pressed", String(expanded));
            maximize.setAttribute("aria-label", label);
            maximize.title = label;
            maximize.textContent = expanded ? "❐" : "□";
            front();
        });
        window.querySelector(".window-close").addEventListener("click", () => {
            let wrapper = window;
            while (wrapper.parentElement !== stage) wrapper = wrapper.parentElement;
            wrapper.remove();
            windows.delete(window);
            root.querySelector(".actions-add").focus({preventScroll: true});
        });
    }

    const initial = [...stage.querySelectorAll(".plot-window")];
    initial.forEach(window => mount(window, initial.length));
    const observer = new MutationObserver(() => {
        for (const window of stage.querySelectorAll(".plot-window")) {
            if (!windows.has(window)) mount(window, 0);
        }
    });
    observer.observe(stage, {childList: true, subtree: true});
    const resizeObserver = new ResizeObserver(() => {
        if (stacked.matches) return;
        for (const [window, box] of windows) put(window, box);
    });
    resizeObserver.observe(stage);
    const cleanup = new MutationObserver(() => {
        if (root.isConnected) return;
        observer.disconnect();
        resizeObserver.disconnect();
        cleanup.disconnect();
    });
    cleanup.observe(root.closest(".jdplot"), {childList: true, subtree: true});
}
