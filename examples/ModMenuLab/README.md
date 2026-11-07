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

Record the result of each step as the log lines it produced. A step with no line is a failure,
except the visual-only steps T7, T11, T15, T16, T17, T19 and T26, whose expected column describes
only what to see. Judge those by sight and record what you saw.

| Step | Action | Expected log line |
|---|---|---|
| 1 | Launch the game, wait for the main menu | `Init ok`, ten `Register ... ok` lines, the first for `LabTheme` |
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
| T3 | Click `Next theme` until the dropdown shows `dark` again, taking a screenshot of each preset | one `theme -> <id>` and one `built theme=<id>` line per click, for every id from `ModMenu.Themes()` in order; no crash |
| T4 | Pick `light` in the dropdown first, then click `Previous theme` | `theme -> windows-classic`; the list wraps to the last preset |
| T5 | Pick `glass` in the dropdown | `theme -> glass`, then `built theme=glass ...` |
| T6 | Pick `slate`, then `light`, and compare the two `built` lines | `ms` under 250 for slate; slate's `widgets` at most 3 times light's |
| T7 | In each screenshot, check the buttons, toggles, choices and panel corners | no engine-default grey button, no light rim on a rounded shape, no blur outside the panel's corners |
| T8 | In a preset that names a game font, such as `loadout`, read the log | at most one line per missing path per session, for any of the four paths the lab passes; none in Funnel Runners |
| T9 | Click `Next theme` through `terminal`, `hologram`, `frost`, `mac-light` and `mac-dark` | one `theme -> <id>` and one `built theme=<id>` line per preset; no crash |
| T10 | On `mac-light`, hover any traffic light, then click red, yellow and green in turn, reopening with F7 | all three show their symbols on hover; red and yellow log `CLOSED tag=ModMenuLab`; green logs nothing, the menu pops and stays open |
| T11 | Watch `hologram` for 30 seconds, then `frost` for 30 seconds | hologram shows a sweep, scanlines and glitches at irregular times, and the menu stays clickable; frost glints come and go |
| T12 | On `terminal`, watch the header cursor. On `neon`, watch the title | the cursor blinks once a second; the title pulses |
| T13 | On a preset with motion, click `Shake test`, then any other button | `[ModMenuLab] shake test` and the menu shakes; any other button makes the menu pop slightly |
| T14 | Switch to `hologram` and read the `built theme=hologram` line | `ms` under 250 |
| T15 | On any preset except `light` and `dark`, open the tab with the most sections | sections fade in one after another with no visible stutter |
| T16 | Check the values that need an in-game look: the macOS title bar's vertical position and `cozy` buttons at least 38 tall | each matches the intended look |
| T17 | On `light` and `dark`, open the menu and click any button | nothing animates: no fade on open and no pop |

## Windows preset steps

The Windows tab holds one of each control the Windows presets restyle: two check boxes, radio
buttons, a slider with ticks, a dropdown, a number field with step 5, a stepper, a progress bar,
and 30 filler lines below them so the panel scrollbar shows. The tab strip is the tab look.

Run steps T18 to T27 once for each of the eight presets, in this order: `xp-luna`,
`xp-luna-silver`, `xp-luna-olive`, `xp-embedded`, `xp-royale`, `xp-royale-noir`, `xp-zune`,
`windows-classic`. Pick the preset in the Theme tab, then open the Windows tab. Compare each
preset with its reference screenshot, which is supplied with this round and kept outside the
repository. The files are in `C:/Users/Richard/Workspace/UE4SS-UI/` and are named
`xp_luna_sample.png`, `xp_luna_silver_sample.png`, `xp_luna_olive_sample.png`,
`xp_embedded_sample.png`, `xp_royale_sample.png`, `xp_royale_noir_sample.png`,
`xp_zune_sample.png` and `9x_classic_sample.png`, in the order of the presets above. The builder
previews are in `.hyperfocus/previews/<id>.png`, with a `<id>-scrolled.png` beside each.

Some shapes are approximations that the menu can draw without textures. The radio's shading is
concentric rings. The slider's pointer thumb is a box with rounded bottom corners. Arrow
triangles are stacked bars. The scrollbar thumb is one colour, with no arrow buttons. The font is
Roboto, not Tahoma. Do not record these as failures.

| Step | Action | Expected log line |
|---|---|---|
| T18 | Pick the preset in the Theme tab | `theme -> <id>`, then `[ModMenu] built theme=<id> ...` with `ms` under 250; no crash |
| T19 | Look at the tab strip, then hover an unselected tab | the selected tab sits higher, is filled like the pane, and has the coloured top line; the hovered tab shows the same line, and it goes when the pointer leaves |
| T20 | Windows tab: hover each check box and click the first | the box has the preset's gradient or flat fill and a hover ring; `w_chk_off -> true`, and the box shows its mark |
| T21 | Windows tab: hover each radio button and click `Second` | rings or bevel show, with a hover ring; `w_radio -> Second` and the dot moves |
| T22 | Windows tab: drag the slider and release | the thumb is a pointer shape with a tick row under the track; `w_slider -> ...` in steps of 10 |
| T23 | Windows tab: click the dropdown's arrow button, then pick `Gamma` | the list opens from the arrow button; `w_drop -> Gamma`; the arrow button shows hover and pressed looks |
| T24 | Windows tab: click the number field's up arrow, then its down arrow | `w_num -> 25`, then `w_num -> 20`; the two arrow buttons are stacked at the right |
| T25 | Windows tab: click the stepper's right arrow, then its left arrow | `w_step -> 4`, then `w_step -> 3`; the buttons are arrows when the preset sets `stepper.arrows` |
| T26 | Windows tab: scroll with the wheel, then drag the scrollbar thumb | the thumb and track show the preset's colours, and the thumb follows the drag; `w_last` becomes visible at the end |
| T27 | Click the caption buttons: minimise, then reopen with F7; maximise; close | minimise and close each log `CLOSED tag=ModMenuLab`; maximise logs nothing, the menu pops and stays open |

If T26 shows today's grey scrollbar in a preset that sets `scroll`, the engine ignored the brush
writes. Record that, because the thickness is then the only change.

## Comparing runs

Each run adds lines under a new `run <date>` header in `ModMenuLab-session.log`. Diff two runs'
sections for the same step. A difference in a `probe` line's `bg` or `hoverTint` between runs
on different library builds is the evidence that a styling change reached the engine.
