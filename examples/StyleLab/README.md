# StyleLab

StyleLab draws sample menus on seven pages, each in a different visual style, so you can choose what ModMenu's themes should look like. It has no game function, and it does not use the ModMenu library. Every widget is built in `Scripts/main.lua`, so each styling technique can be tried on its own.

Each card is drawn from a style table with one entry per object type: panel, header, tabs, section, button, toggle, slider, progress bar, choice, text field, list, icons and motion. A theme sets only the entries it changes. A mixed theme takes entries from other themes and keeps its own colours. So the gallery is also a working model of the per-object-type styling the library will offer.

## Install

1. Copy this folder to `<game>/Binaries/Win64/ue4ss/Mods/StyleLab`.
2. Create an empty `enabled.txt` in that folder.
3. Launch the game and load into a level.

## Use

- **F6 to F12** each open one page. F12 is also Steam's screenshot key, so pressing it may also save a screenshot.
  - If another page is showing, the key switches to its page.
  - If its own page is already showing, the key closes the gallery.
  - The **Close** button in the banner and the `stylelab` console command also close it.
- Each click, toggle and choice writes a line to the log.
- Apply, Reset and Close make the card pulse, and the storm-clearing buttons shake it.

## Pages

**F6 to F8, favourites as full menus.** Each card is a complete menu:
- a header with a close button, and a tab bar
- **Movement:** two toggles, a disabled toggle, a slider and a key binding
- **Storms:** an animated intensity bar, a choice, a stepper and a danger button
- **Items:** a text field, a dropdown and a list with a locked row
- an action bar with a status line, Reset and Apply

| Page | Cards |
|---|---|
| F6 | Slate, Glass, Storm, Neon |
| F7 | Doppler, Tornado Warning, Night Drive, Loadout |
| F8 | Cozy, Carbon, Blueprint, and Mixed: Slate's panel and colours with Glass's title, Neon's buttons, Cozy's toggles and choices, and Doppler's bar |

**F9, reworked.** Compact cards, with the same controls on every card:

| Card | What changed |
|---|---|
| Terminal | An inverted header bar with a blinking cursor, a soft phosphor glow, a block gauge, On and Off chips, and fine scanlines of varied shade. |
| Paper, cool blue | The Paper layout in cool white and ink blue. |
| Field Kit | Graphite and high-visibility yellow, a thin hazard strip, silver lines and smaller corners. |
| Hologram | Scanlines are now drawn as fine lines of varied shade, every 2.5 units. Glitches at random intervals, sometimes in bursts. Each mixes jitter, a colour split of the title, flicker, a tear line and a vertical roll. The scanlines waver, and a sweep and an interference band drift at changing speeds. |
| Ink | Black and white with pill buttons and switches. |
| Frost | Frosted ice-blue glass with a white rim and glints, now near-opaque with dark navy text for reading. |

**F10, new options**, in a narrower four-column layout: Aurora, Midnight, Storm Front, Sakura, Ocean, Steel, and Paper in sage.

**F11, popular palettes**, with each palette's published colours:

| Card | Palette |
|---|---|
| Dracula | Dracula's background and comment blue-grey, purple accent, pink, cyan and green. |
| Catppuccin Mocha | Mocha's base and surfaces, mauve accent, blue to pink pastels. |
| Catppuccin Latte | Catppuccin's light flavour, for comparison with Mocha. |
| Material | Material Design dark: purple primary, teal secondary, capital button labels, tabs. |
| Monokai | Olive-black with Monokai's green, blue, yellow and pink. |
| Nord | Polar night greys, snow storm text, frost blues, aurora red. |

**F12, operating systems.** Light styles on the top row and dark below. Each imitates the look with the engine's fonts and simple shapes. Gradients are faked from stacked strips of colour, and hover and press looks are drawn by polling the widget. Windows 11 uses the colours you gave: accent `#0070D5`, background `#F0F3F9`, buttons `#FEFEFE`. The other values come from public recreations and recall, not from the operating systems' own files.

| Card | What it tries |
|---|---|
| Windows 11, light and dark | A 32-high title bar flush with the window's top edge. Its 46 by 32 caption buttons fill the bar's height, and Close turns red with a white cross, its hover following the window's corner. Monochrome icons, outline off-switches, a short pill under the selected tab. |
| macOS, light and dark | Traffic lights that show their symbols when any of them is hovered, gradient rounded-square icon tiles, a white-on-grey segmented control, a more visible slider. |
| Windows XP | Refined from reference screenshots: a glossy title bar, bubble caption buttons (white outline, gradient, top-left shine, thick white symbols, red Close), 3D push buttons with an orange hover glow and a blue ring on the default button, green blocks in a rounded trough, radio buttons, a status bar. |
| Windows XP, Royale Noir | From a Royale Noir screenshot: neutral black glossy chrome, black bubble caption buttons with white outlines, a light body, near-black button edges, green checks and blocks. |
| Windows 98 | Two-ring bevels in the Classic order that turn sunken while pressed, a navy-to-blue horizontal title bar gradient, radio buttons, a sunken trough of navy blocks. |
## Verdicts so far

These record which styles to carry into the library's presets. The round 3 gallery is kept, unchanged, in `.hyperfocus/stylelab-archive/round-3/` in this repository.

- **Kept:** Slate, Glass, Storm, Neon, Doppler, Tornado Warning, Night Drive, Loadout, Cozy, Carbon, Blueprint, Ink (pill version), Field Kit (rework), Paper (sage, and preferred to Overcast).
- **Dropped:** Overcast (too close to Paper), Survey, Arcade, Brutal, Swiss, Court, Ember, Bakelite, and the first Terminal, Frost and Hologram designs.
- **Still being judged:** the Terminal, Hologram and Frost reworks, the F10 options, and the F11 and F12 pages.
## What the log records

The log is written to `UE4SS.log` and to `StyleLab-session.log` in this folder.
- **Fonts:** one line for each font, with the typeface names it defines.
- **Failures:** the first failure of each technique on each card.
- **Read-back:** one line per card. It shows the brush and font values the widget holds after styling.
- **Build summary:** the number of successes and failures for each technique.
- **Steps:** a `[step]` line before each native call. If the game closes without an error, the last step line names the call that killed it.

## Findings from the first run (Funnel Runners, 2026-11-05)

These come from `StyleLab-session.log` and a 2560x1440 screenshot, read with enlarged crops. The general rules are in the framework's field notes 29 to 33. This section records what each card showed.

**Worked as intended.**
- **Build:** all six cards built. The log printed `built 6 of 6 cards, 49 clickable widgets`, and no technique failed.
- **Brushes and controls:** rounded panels, fill buttons, pill toggles, slider bars and thumbs, and rounded progress bars all drew as specified.
- **Text:** font outlines (the Neon title, the Terminal title glow), text shadows (Glass), letter spacing and the Roboto Light typeface all drew.
- **Icons:** the game's icon textures drew, tinted.
- **Clicks:** a click selected the segment it landed on. The log shows `Slate segment -> Low`, then Medium, High and Medium. No other click was logged, so the other controls' clicks are unchecked.

**Defects in the gallery itself.**
1. **White rims.** Toggle tracks and the segmented pickers show a white or grey rim at their rounded edge. The unselected, transparent segments still draw a white rounded outline. These Borders are painted white and tinted with `SetBrushColor`, which does not tint the edge colour (field note 30). Fill buttons, whose edge and fill are the same colour, show no rim.
2. **Ghost buttons have no outline.** Glass, Terminal and Neon buttons show only their caption. The outline set on a Button's state brush did not draw, while the same kind of outline on a Border did (field note 31).
3. **Glass blur.** The blurred area shows a few pixels outside the panel's rounded frame, and its corners curve differently from the frame (field note 32).
4. **Missing game fonts.** Rye, Arvo and DSEG7 did not load (`asset missing: ...`). So the Paper title is Roboto Bold rather than Rye, the Paper readout is Roboto, and the Terminal readout is VCR OSD Mono rather than DSEG7 (field note 33). The Paper and Terminal footers still name fonts the cards do not use.
5. **Storm is invented.** The Storm card is not the game's look. Its subtitle, "The game's own look", was written from asset folder names in the object dump, not from the game on screen. Its materials drew their default values, as described below (field note 33).
   - The panel is a flat translucent grey wash.
   - The Primary and Danger bracket materials are flat purple and red boxes.
   - The Secondary material draws nothing.
6. **Terminal's on toggle.** The knob and the track are the same green, so the knob is invisible when the toggle is on.
7. **Shadows are not visible.** The three layered shadows at alpha 0.12 do not show against the dark game scene, under Slate or under Paper.
8. **Cut-off cards.** Storm and Paper are taller than their slots. Storm's footer is cut off, and both cards show the ScrollBox's bottom shadow bar. Kanit's taller line height is the likely cause for Storm. That is inferred.
9. **Coarse scanlines.** Terminal's scanlines tile at the texture's native size, which gives a few broad bands rather than fine lines.

**Not checked.**
- How the hovered and pressed brushes look. The screenshot shows only the normal state.
- The open animation, the Neon title pulse, and the Pop and Shake effects on clicks.
