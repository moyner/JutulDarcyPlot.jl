function widget_observable(widget)
    widget isa Makie.Menu && return widget.i_selected
    widget isa Makie.Toggle && return widget.active
    widget isa Makie.Checkbox && return widget.checked
    widget isa Makie.Slider && return widget.value
    widget isa Makie.IntervalSlider && return widget.interval
    widget isa Makie.Axis && return widget.targetlimits
    return nothing
end

widget_value(value::Tuple) = join(value, ',')
widget_value(value::Makie.Rect2d) = widget_value((minimum(value)..., Makie.widths(value)...))
widget_value(value) = string(value)

function restore_widget!(widget, value)
    if widget isa Makie.Menu
        index = parse(Int, value)
        0 <= index <= length(widget.options[]) && (widget.i_selected[] = index)
    elseif widget isa Makie.Slider
        Makie.set_close_to!(widget, parse(Float64, value))
    elseif widget isa Makie.IntervalSlider
        ends = parse.(Float64, split(value, ','))
        length(ends) == 2 && Makie.set_close_to!(widget, ends...)
    elseif widget isa Makie.Axis
        bounds = parse.(Float64, split(value, ','))
        if length(bounds) == 4 && all(isfinite, bounds) && bounds[3] > 0 && bounds[4] > 0
            widget.targetlimits[] = Makie.Rect2d(bounds...)
        end
    else
        widget_observable(widget)[] = parse(Bool, value)
    end
end

function mount_plot_state(bonito, session, node, figure, camera_scene)
    plot_widgets() = filter(figure.content) do widget
        # The reservoir histogram follows the controls that generated it.
        !(widget isa Makie.Axis && !isnothing(camera_scene)) && !isnothing(widget_observable(widget))
    end
    camera = isnothing(camera_scene) ? nothing : Makie.cameracontrols(camera_scene)
    # WGLMakie sends its UI changes back to these same Julia observables.
    changes = Makie.Observable(String[])
    restore = Makie.Observable(String[])
    restoring = Ref(false)
    listeners = IdDict{Any, Any}()
    function watch_widgets!()
        widgets = plot_widgets()
        for widget in collect(keys(listeners))
            if !any(w -> w === widget, widgets)
                Makie.off(pop!(listeners, widget))
            end
        end
        for widget in widgets
            haskey(listeners, widget) && continue
            listeners[widget] = bonito.on(session, widget_observable(widget)) do _
                # Changing summary rows or columns replaces its per-panel menus.
                current = watch_widgets!()
                if !restoring[]
                    changes[] = ["widgets"; [widget_value(widget_observable(w)[]) for w in current]]
                end
            end
        end
        return widgets
    end
    watch_widgets!()
    has_camera = !isnothing(camera) && all(k -> hasproperty(camera, k), (:eyeposition, :lookat, :upvector))
    if has_camera
        # Projection updates follow each camera interaction and include the full pose.
        bonito.on(session, Makie.camera(camera_scene).projectionview) do _
            restoring[] || (changes[] = ["camera", join((camera.eyeposition[]..., camera.lookat[]..., camera.upvector[]...), ',')])
        end
    end
    bonito.on(session, restore) do entries
        restoring[] = true
        try
            values = web_plot_settings(entries)
            indices = sort!(filter(!isnothing, tryparse.(Int, collect(keys(values)))))
            for index in indices
                widgets = plot_widgets()
                if checkbounds(Bool, widgets, index)
                    restore_widget!(widgets[index], values[string(index)])
                end
            end
            if has_camera && haskey(values, "camera")
                pose = parse.(Float64, split(values["camera"], ','))
                if length(pose) == 9 && all(isfinite, pose)
                    Makie.update_cam!(camera_scene, camera, Makie.Vec3d(pose[1:3]...),
                        Makie.Vec3d(pose[4:6]...), Makie.Vec3d(pose[7:9]...))
                end
            end
        catch err
            err isa InterruptException && rethrow()
            @debug "Could not restore a saved plot control" exception = err
        finally
            restoring[] = false
        end
    end
    code = bonito.JSCode([bonito.JSString("node => { const changes = "), changes,
        bonito.JSString("; const restore = "), restore, bonito.JSString(""";
            changes.on(value => node.dispatchEvent(new CustomEvent("jdplot:control", {bubbles: true, detail: value})));
            node.addEventListener("jdplot:restore", event => restore.notify(event.detail));
            node.dataset.controlsReady = "true";
            node.dispatchEvent(new CustomEvent("jdplot:controls-ready", {bubbles: true}));
        }""")])
    bonito.onload(session, node, code)
    return nothing
end
