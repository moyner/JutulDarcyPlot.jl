# JutulDarcyPlot.jl

Plot Eclipse and native Jutul reservoir simulations from the terminal with Julia 1.12 or later.

## Install

From a local checkout, install both launchers with Julia's app manager.

```sh
julia -e 'using Pkg; Pkg.Apps.develop(path=ARGS[1])' /path/to/JutulDarcyPlot.jl
```

Add the `bin` subdirectory of your first Julia depot to `PATH`. With the default depot, this is `~/.julia/bin` on Linux and macOS or `%USERPROFILE%\.julia\bin` on Windows. To run directly from the checkout, run `julia --project=. -e 'using Pkg; Pkg.instantiate()'` once. Then use `julia --project=. --compiled-modules=existing -O0 -m JutulDarcyPlot` for the desktop or `julia --project=. -m JutulDarcyPlot.Web` for the browser, followed by the same arguments.

## Plot from the terminal

```text
jdplot MODEL.SMSPEC --rows 1 --columns 2 --plots FPR --plots "FOPR,FWPR"
jdplot MODEL_jutul_output --plots FOPR -o oil-rate.png
jdplot MODEL.SMSPEC --plot wells --entity PROD --series WBHP -o producer.png
jdplot MODEL.UNRST --field PRESSURE --step 3 -o pressure.png
jdplot MODEL.EGRID
jdplot MODEL.EGRID --static
jdplot MODEL_jutul_output --plot reservoir --case MODEL.DATA
```

GLMakie is the default backend. It opens an interactive window and keeps the command running until the window closes. It requires a working OpenGL display. Use `--backend cairo` for PNG output. CairoMakie writes `<case>-<plot>.png` in the current directory by default. `--output` and `--row` select CairoMakie when no backend is given.

By default, `.SMSPEC`, `.UNSMRY`, and `.Snnnn` open the summary. `.EGRID`, `.INIT`, `.UNRST`, `.RSSPEC`, `.Xnnnn`, `.DATA`, `.GRDECL`, `.AFI`, `.jl`, and native `jutul_N.jld2` reports open the reservoir. A case prefix, directory, or JLD2 bundle opens the summary when available and otherwise opens the reservoir. Use `--plot` to choose the view explicitly.

Summary figures use `JutulDarcy.plot_summary` and the dedicated Wells view uses `JutulDarcy.plot_well_results` with elapsed days for rate and cumulative curves. Use `--rows` and `--columns` (or `--cols`) to set the initial summary layout. Repeat `--plots` once per panel. A comma joins curves within a panel, as in `"FOPR,FWPR"`. Prefix well and group keywords with their source name, as in `"PROD:WBHP"` or `"INJECTORS:GWIR"`. On the desktop, `--entity` and `--series` select one summary panel. In the Wells view, `--entity` limits the plot to one well and `--series` selects the initial response. [JutulDarcy plotting documentation](https://sintefmath.github.io/JutulDarcy.jl/stable/man/basics/plotting)

`--field` and `--step` select a reservoir property and its one-based position in the saved reports. CairoMakie accepts `--row` for matrix-valued properties. Add `--static` to show grid properties and well locations without displaying dynamic cell results.

## Explore in a browser

```text
jdplot-web MODEL_jutul_output
jdplot-web MODEL_jutul_output --rows 2 --cols 1 --plots FPR --plots "PROD:WBHP"
jdplot-web MODEL.EGRID --static --port 9000
jdplot-web native-results --case case.jl
```

Open the URL printed by `jdplot-web`. The default combined workspace opens the available summary and reservoir views for the case. Use `--plot auto` to select a view by file extension, or request `--plot summary`, `--plot wells`, or `--plot reservoir` directly. The Bonito server listens on `127.0.0.1:9384` by default. Use `--host` and `--port` to change the listen address. Press Ctrl+C in the terminal to stop the server.

Use **Add plot** to configure a Summary, Wells, or Reservoir window. Summary has case-dependent dashboard presets for field performance, production, injection, and wells. Edit the panel list and set rows, columns, and units to make a custom dashboard. Reservoir windows can use independent fields, report steps, colormaps, cameras, mesh and fault settings, well styling, and vertical scales. Drag a title bar to move a window and snap it to the workspace edges. Drag the lower-right corner to resize it, or use the square button to maximize and restore it. The title bar and resize handle also respond to arrow keys when focused. Windows stack on narrow screens. The Summary window can switch to the native Wells view when well curves are available.

Use **Load case** on localhost to browse files on the machine running Julia. The browser starts beside the active case. Navigate with **Up**, the server locations menu, or a folder in the list. Select an Eclipse file, a Jutul file, or a results directory with **Select this folder**. Use **Browse** beside **Companion model** to pair Jutul reports with their model or add an Eclipse `.DATA` deck. **Data files** opens available case inputs (`.DATA`, `.GRDECL`, `.AFI`, `.jl`) and simulation logs (`.DBG`, `.PRT`) in a read-only editor. Files larger than 4 MiB show a preview of the first 4 MiB.

Refreshing a tab restores its active case, plot windows, positions, configuration, and selections from browser storage. Each tab has its own workspace.

Open **Statistics** for a case overview. The summary table shows first, latest, minimum, mean, median, and maximum for the selected field, group, or well in the summary's stored units. Static reservoir properties have their own table, with total bulk and pore volumes where available. Select a saved report to see statistics for its dynamic cell properties. Column headers sort the tables.

The reservoir explorer switches between static and dynamic properties, steps through saved reports, and rotates and zooms the grid. Interactive views show dynamic cell properties available across all reports. To plot an array saved in only some reports, use Cairo with `--field` and `--step`.

## Input formats

- **Eclipse.** Pass a case prefix, a supported case file, or a directory containing one case, including the default output directory from `jdrun`. Summary and well curves use `.SMSPEC` with `.UNSMRY` or split `.Snnnn` files. Summary figures start in metric units. The dedicated Wells view starts in field units for field-unit decks and metric otherwise. Reservoir plotting uses `.EGRID`, or geometry from `.DATA` or `.GRDECL`, and adds cell arrays from `.INIT` and `.UNRST` or split `.Xnnnn` reports when available. Selecting a specific `.Xnnnn` plots that report. The binary reader loads the main grid.
- **Jutul.** Pass the `output_path` directory from `simulate_reservoir`, or any of its `jutul_N.jld2` files, together with `--case`. The case supplies the mesh, wells, and simulation controls. It may be a Julia script defining `case::JutulCase`, a `.DATA` or `.AFI` input, or a JLD2 file storing `case`. Rebuilding curves from a report directory requires consecutive saved reports with `report_level >= 0`. You can also pass a `.jl`, `.AFI`, or JLD2 case by itself for a static reservoir view.

To store the native case and results together, save the raw `SimResult` from a `ReservoirSimResult` under the `result` key.

```julia
using JLD2, JutulDarcy

# `case` is the JutulCase used to run the simulation.
simulation = simulate_reservoir(case)
jldsave("model.jld2"; case, result = simulation.result)
```

Then run `jdplot model.jld2` or `jdplot-web model.jld2`. The `result` key can also contain a `ReservoirSimResult`, which already contains summary curves.

## Eclipse well locations

`.EGRID` describes the grid. Eclipse restart files store well names in `ZWEL`, well records and connection counts in `IWEL`, and the completion cell indices in `ICON`. `jdplot` uses those completion cells to draw an approximate well path on the main grid. The overlay includes completions from the reports read for the plot. [OPM Flow Reference Manual](https://opm-project.org/wp-content/uploads/2023/06/OPM_Flow_Reference_Manual_2023-04_Rev-0_Reduced.pdf)

The current `jdrun` exporter writes the well summary curves and reservoir solution arrays. For a well overlay on that output, `jdplot` reads `WELSPECS` and `COMPDAT` from the same-named `.DATA` deck, or from the deck supplied with `--case MODEL.DATA`.

## Precompilation

Installation precompiles the Eclipse unified and split readers, native Jutul reports, and summary, well, static reservoir, and dynamic reservoir figures for CairoMakie, GLMakie, and WGLMakie/Bonito. The GL workload exercises the launcher's window setup and first frame offscreen when an OpenGL context is available. The desktop launcher reuses installed package caches and uses `-O0` for Julia methods compiled during the session to reduce time to the first plot. Run the install command again to refresh a previously generated launcher. The web workload includes the combined layout and does not start a server or open a browser.
