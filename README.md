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
jdplot MODEL_jutul_output --series FOPR -o oil-rate.png
jdplot MODEL.SMSPEC --plot wells --entity PROD --series WBHP -o producer.png
jdplot MODEL.UNRST --field PRESSURE --step 3 -o pressure.png
jdplot MODEL.EGRID
jdplot MODEL.EGRID --static
jdplot MODEL_jutul_output --plot reservoir --case MODEL.DATA
```

GLMakie is the default backend. It opens an interactive window and keeps the command running until the window closes. It requires a working OpenGL display. Use `--backend cairo` for PNG output. CairoMakie writes `<case>-<plot>.png` in the current directory by default. `--output` and `--row` select CairoMakie when no backend is given.

By default, `.SMSPEC`, `.UNSMRY`, and `.Snnnn` open the summary. `.EGRID`, `.INIT`, `.UNRST`, `.RSSPEC`, `.Xnnnn`, `.DATA`, `.GRDECL`, `.AFI`, `.jl`, and native `jutul_N.jld2` reports open the reservoir. A case prefix, directory, or JLD2 bundle opens the summary when available and otherwise opens the reservoir. Use `--plot` to choose the view explicitly.

`--series` selects a summary keyword. `--entity` can select a field, well, group, or other summary entity. `--field` and `--step` select a reservoir property and its one-based position in the saved reports. CairoMakie accepts `--row` for matrix-valued properties. Add `--static` to show grid properties and well locations without displaying dynamic cell results.

## Explore in a browser

```text
jdplot-web MODEL_jutul_output
jdplot-web MODEL_jutul_output --plot combined
jdplot-web MODEL.EGRID --static --port 9000
jdplot-web native-results --case case.jl
```

Open the URL printed by `jdplot-web`. The Bonito server listens on `127.0.0.1:9384` by default. A case prefix, directory, or JLD2 bundle serves all available views. An explicit file selects the view by extension, just as it does for `jdplot`. Use `--plot` to choose a view or `--host` and `--port` to change the listen address. The reservoir explorer can switch between static and dynamic properties, step through saved reports, and rotate and zoom the grid. Interactive views show dynamic cell properties available across all reports. To plot an array saved in only some reports, use Cairo with `--field` and `--step`. Each browser session has its own controls. Press Ctrl+C in the terminal to stop the server.

`--plot combined` puts the summary controls and reservoir explorer side by side and stacks them on narrower screens. The summary selector also includes well curves. Either panel stays interactive while you use the other.

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

## Eclipse well locations

`.EGRID` describes the grid. Eclipse restart files store well names in `ZWEL`, well records and connection counts in `IWEL`, and the completion cell indices in `ICON`. `jdplot` uses those completion cells to draw an approximate well path on the main grid. The overlay includes completions from the reports read for the plot. [OPM Flow Reference Manual](https://opm-project.org/wp-content/uploads/2023/06/OPM_Flow_Reference_Manual_2023-04_Rev-0_Reduced.pdf)

The current `jdrun` exporter writes the well summary curves and reservoir solution arrays. For a well overlay on that output, `jdplot` reads `WELSPECS` and `COMPDAT` from the same-named `.DATA` deck, or from the deck supplied with `--case MODEL.DATA`.

## Precompilation

Installation precompiles the Eclipse unified and split readers, native Jutul reports, and summary, well, static reservoir, and dynamic reservoir figures for CairoMakie, GLMakie, and WGLMakie/Bonito. `jdplot` loads the selected backend before loading the simulation and plotting code so Makie can reuse its compiled methods. The GL workload exercises the launcher's window setup and first frame offscreen when an OpenGL context is available. The web workload includes the combined layout and does not start a server or open a browser.
