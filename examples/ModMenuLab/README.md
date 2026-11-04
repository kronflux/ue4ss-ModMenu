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
| 1 | Launch the game, wait for the main menu | `Init ok`, four `Register ... ok` lines |
| 2 | Press F7 | `[ModMenu] OPEN tag=ModMenuLab`, no crash |
| 3 | Hover the `default` button, then move off | `button b_default pointer state hover`, then `normal`; note whether the fill changed colour or only showed the stock grey |
| 4 | Click `default` | `click path=...`, `b_default -> nil` |
| 5 | Click `Probe widgets` | one `probe ...` line per button with `bg=` and `hoverTint=`; compare `hoverTint` with the theme's hover colour |
| 6 | Hover `with tooltip` and hold still for one second | tooltip visible and readable; note its size |
| 7 | Click `confirm`, then the modal's confirm | `b_confirm -> nil` after the modal |
| 8 | Inputs tab: toggle, change the number, type text, pick `two` | `c_1 -> true`, `n_1 -> ...`, `t_1 -> ...`, `d_1 -> two` |
| 9 | Widgets tab: drag the slider | `s_1 -> ...` values in steps of 5 |
| 10 | Click `Crouch`, then `B` | `r_1 -> Crouch`, `r_2 -> B`, the chosen option painted green |
| 11 | Click the keybind, press Ctrl+G | `k_1 -> Ctrl+G` |
| 12 | Layout tab: use the row's three controls and the fold's two | one `row_...` or `fold_...` line each |
| 13 | Close with F7, relaunch, repeat step 2 | the values from steps 8 to 11 restored (`autosave`) |

## Comparing runs

Each run adds lines under a new `run <date>` header in `ModMenuLab-session.log`. Diff two runs'
sections for the same step. A difference in a `probe` line's `bg` or `hoverTint` between runs
on different library builds is the evidence that a styling change reached the engine.
