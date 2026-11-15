# JutulDarcyPlot.jl

Plot Eclipse and native Jutul reservoir simulations from the terminal with Julia 1.12 or later.

## Install

From a local checkout, install both launchers with Julia's app manager.

```sh
julia -e 'using Pkg; Pkg.Apps.develop(path=ARGS[1])' /path/to/JutulDarcyPlot.jl
```

Add the `bin` subdirectory of your first Julia depot to `PATH`. With the default depot, this is `~/.julia/bin` on Linux and macOS or `%USERPROFILE%\.julia\bin` on Windows. To run directly from the checkout, run `julia --project=. -e 'using Pkg; Pkg.instantiate()'` once, then use `julia --project=. -m JutulDarcyPlot` or `julia --project=. -m JutulDarcyPlot.Web` followed by the same arguments.

## Plot from the terminal

```text
jdplot MODEL_jutul_output --plot summary --series FOPR -o oil-rate.png
jdplot MODEL.SMSPEC --plot wells --entity PROD --series WBHP -o producer.png
jdplot MODEL.UNRST --plot reservoir --field PRESSURE --step 3 -o pressure.png
jdplot MODEL.EGRID --plot reservoir --static
jdplot MODEL_jutul_output --plot reservoir --backend gl
```

CairoMakie is the default backend. It writes `<case>-<plot>.png` in the current directory unless `--output` is supplied. GLMakie opens a window with curve selectors or the JutulDarcy reservoir explorer and keeps the command running until the window closes. It requires a working OpenGL display.

`--plot auto` selects the summary when available and otherwise uses the reservoir. `--series` selects a summary keyword. `--entity` can select a field, well, group, or other summary entity. `--field` and `--step` select a reservoir property and its one-based position in the saved reports. CairoMakie also accepts `--row` for matrix-valued properties. Add `--static` to show grid properties even when restart files are present.

## Explore in a browser

```text
jdplot-web MODEL_jutul_output
jdplot-web MODEL.EGRID --plot reservoir --static --port 9000
jdplot-web native-results --case case.jl
```

Open the URL printed by `jdplot-web`. The Bonito server listens on `127.0.0.1:9384` by default and serves all available views with WGLMakie. Use `--plot` for a single view or `--host` and `--port` to change the listen address. The reservoir explorer can switch between static and dynamic properties, step through saved reports, and rotate and zoom the grid. Interactive views show dynamic cell properties available across all reports. To plot an array saved in only some reports, use Cairo with `--field` and `--step`. Each browser session has its own controls. Press Ctrl+C in the terminal to stop the server.

## Input formats

- **Eclipse.** Pass a case prefix, a supported case file, or a directory containing one case, including the default output directory from `jdrun`. Summary and well curves use `.SMSPEC` with `.UNSMRY` or split `.Snnnn` files and display the units declared by the summary. Reservoir plotting uses `.EGRID`, or geometry from `.DATA` or `.GRDECL`, and adds cell arrays from `.INIT` and `.UNRST` or split `.Xnnnn` reports when available. Selecting a specific `.Xnnnn` plots that report. The binary reader loads the main grid.
- **Jutul.** Pass the `output_path` directory from `simulate_reservoir`, or any of its `jutul_N.jld2` files, together with `--case`. The case supplies the mesh, wells, and simulation controls. It may be a Julia script defining `case::JutulCase`, a `.DATA` or `.AFI` input, or a JLD2 file storing `case`. Rebuilding curves from a report directory requires consecutive saved reports with `report_level >= 0`. You can also pass a `.jl`, `.AFI`, or JLD2 case by itself for a static reservoir view.

To store the native case and results together, save the raw `SimResult` from a `ReservoirSimResult` under the `result` key.

```julia
using JLD2, JutulDarcy

# `case` is the JutulCase used to run the simulation.
simulation = simulate_reservoir(case)
jldsave("model.jld2"; case, result = simulation.result)
```

Then run `jdplot model.jld2` or `jdplot-web model.jld2`. The `result` key can also contain a `ReservoirSimResult`, which already contains summary curves.
