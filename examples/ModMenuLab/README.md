# ModMenuLab

A test-only menu with no game function. It registers every control type once, logs every
callback and every engine read-back, and keeps a log that survives relaunches, so two runs of
the steps below can be compared line by line.

## Install

1. Deploy the library: `npm run deploy`, then copy `dist/release/shared/ModMenu/ModMenu.lua`
   to `<game>/Binaries/Win64/ue4ss/Mods/shared/ModMenu/ModMenu.lua`.
2. Copy `examples/ModMenuLab/Scripts/main.lua` to `<game>/.../ue4ss/Mods/ModMenuLab/Scripts/main.lua`
   and create an empty `<game>/.../ue4ss/Mods/ModMenuLab/enabled.txt`.
3. Disable any other mod that calls `ModMenu.Init`, by setting its line in `mods.txt` to `0`,
   so one shell owns the keys.

The lab opens on F7 or the console command `modmenulab`. Lines go to `UE4SS.log` and to
`ue4ss/Mods/ModMenuLab/ModMenuLab-session.log`, which starts each launch with a `run` line.

## Test steps

Record the result of each step as the log lines it produced. A step with no line is a failure.

| Step | Action | Expected log line |
|---|---|---|
| 1 | Launch the game, wait for the main menu | `Init ok`, nine `Register ... ok` lines, the first for `LabTheme` |
| 2 | Press F7 | `[ModMenu] OPEN tag=ModMenuLab`, no crash |
| 3 | Buttons tab: hover the `default` button, then move off | `button b_default pointer state hover`, then `normal`; note whether the fill changed colour or only showed the stock grey |
| 4 | Buttons tab: click `default` | `click path=...`, `b_default -> nil` |
| 5 | Buttons tab: click `Probe widgets` | one `probe ...` line per button with `bg=` and `hoverTint=`; compare `hoverTint` with the theme's hover colour |
| 6 | Buttons tab: hover `with tooltip` and hold still for one second | tooltip visible and readable; note its size |
| 7 | Buttons tab: click `confirm`, then the modal's confirm | `b_confirm -> nil` after the modal |
| 8 | Inputs tab: toggle, change the number, type text, pick `two` | `c_1 -> true`, `n_1 -> ...`, `t_1 -> ...`, `d_1 -> two` |
| 9 | Widgets tab: drag the slider | `s_1 -> ...` values in steps of 5 |
| 10 | Click `Crouch`, then `B` | `r_1 -> Crouch`, `r_2 -> B`, the chosen option painted green |
| 11 | Click the keybind, press Ctrl+G | `k_1 -> Ctrl+G` |
| 12 | Layout tab: use the row's three controls and the fold's two | one `row_...` or `fold_...` line each |
| 12a | Layout tab: click the `Row and fold` section header | `click path=release kind=collapse`, the body hides, a second click shows it |
| 12b | Press and hold any button, move off it, release | no `click` line and no `->` line for that button |
| 13 | Close with F7, relaunch, repeat step 2 | the values from steps 8 to 11 restored (`autosave`) |
| 14 | Controls tab: click `+` and `-` on the first stepper | `st_1 -> 6`, `st_1 -> 4`; the value stops at 0 and at 20 with no line past an end |
| 15 | Controls tab: press and hold `+` on the first stepper for two seconds | one step at first, then a step about every 100 ms after 400 ms, ending at 20 |
| 16 | Controls tab: click `Progress +0.1` three times, then `Progress -0.1` | `pr_1 SetValue +0.10 -> 0.35 found=true` and so on; the green bar and its percent move with no rebuild |
| 17 | Controls tab: click `Rename progress label` | `pr_1 SetLabel found=true` and the label text changes |
| 18 | Controls tab: drag a colour slider and release | one `cp_1 -> {A=...,B=...,G=...,R=...}` line per drag; the swatch follows the sliders; the second picker has no A slider |
| 19 | Multi tab, last: click two options | `ms_1 -> {Beta,...}` style lines with the checked values in option order; the options sit in two columns |

## Theme test steps

The Theme tab comes first. Its dropdown lists every preset id from `ModMenu.Themes()`, and each
choice calls `ModMenu.Init({ theme = id })`. The library then tears the shell down and builds it
again in that preset, and keeps the menu open. The lab starts in `dark` every launch, and the
first `Init` passes the Funnel Runners paths for the `kanit`, `vcr`, `inconsolata` and `lekton`
fonts. In another game those paths do not exist, so the text falls back to Roboto.

Each switch writes two lines. The lab writes `theme -> <id>`, and the library writes
`[ModMenu] built theme=<id> items=<n> widgets=<n> ms=<n>` once the new shell is built.

| Step | Action | Expected log line |
|---|---|---|
| T1 | Press F7, then click the Theme tab | `[ModMenu] OPEN tag=ModMenuLab`; the dropdown shows `dark` |
| T2 | Click `Next theme` | `theme -> slate`, then `[ModMenu] built theme=slate ...`; the menu stays open in Slate and the dropdown shows `slate` |
| T3 | Click `Next theme` until the dropdown shows `dark` again, taking a screenshot of each preset | one `theme -> <id>` and one `built theme=<id>` line per click, for all 29 ids in order; no crash |
| T4 | Pick `light` in the dropdown first, then click `Previous theme` | `theme -> nord`; the list wraps to the last preset |
| T5 | Pick `glass` in the dropdown | `theme -> glass`, then `built theme=glass ...` |
| T6 | Pick `slate`, then `light`, and compare the two `built` lines | `ms` under 250 for slate; slate's `widgets` at most 3 times light's |
| T7 | In each screenshot, check the buttons, toggles, choices and panel corners | no engine-default grey button, no light rim on a rounded shape, no blur outside the panel's corners |
| T8 | In a preset that names a game font, such as `loadout`, read the log | at most one line per missing path per session, for any of the four paths the lab passes; none in Funnel Runners |

## Comparing runs

Each run adds lines under a new `run <date>` header in `ModMenuLab-session.log`. Diff two runs'
sections for the same step. A difference in a `probe` line's `bg` or `hoverTint` between runs
on different library builds is the evidence that a styling change reached the engine.
