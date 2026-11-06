# ModMenu

[![CI](https://github.com/mattdavida/ue4ss-ModMenu/actions/workflows/ci.yml/badge.svg)](https://github.com/mattdavida/ue4ss-ModMenu/actions/workflows/ci.yml)

**Builder:** [https://mattdavida.github.io/ue4ss-ModMenu/](https://mattdavida.github.io/ue4ss-ModMenu/) — compose a menu in the browser and export a host zip (no Lua required). Extract the zip into `ue4ss/Mods/`.

ModMenu is a lightweight UI framework for UE4SS Lua mods that lets feature modules register reusable in-game settings panels without each mod reimplementing its own ImGui or UMG shell.

![ModMenu Host (F8, left, Cheats tab) and Mortal Shell 2 (F6, right) — two independent shells](GithubAssets/ModMenuHero.png)

*Mortal Shell 2: `ModMenuHost` (F8, left) and `MortalShell2Mod` (F6, right). Dummy Cheats tab (widgets, button variants) beside a real Give list — two shells, two keys, one session.*

Each **enabled Lua mod** that calls `Init` gets its own panel + hotkey. Feature modules **register sections** into that mod’s shell.

UObject names are unique across mods via `ModRef` shared vars (see `instanceId`), so two mods can both ship a ModMenu without stealing `ModMenu_Root_1`.

![ModMenu Host Give tab (left) and Mortal Shell 2 Unlocks (right)](GithubAssets/ModMenuHero2.png)

*Same session, different pages: Host on **Give** (search, amount row, warning action) while the cheat menu has **Unlocks** open. Tabs and collapse are per-shell.*

Showcase dummy: `examples/ModMenuHost.lua` (copy into `ue4ss/Mods/YourMod/Scripts/main.lua`). Game-side example: `MortalShell2Mod` (not in this repo).

---

## Install (players / Nexus)

Official `ModMenu.zip` is on [GitHub Releases](https://github.com/mattdavida/ue4ss-ModMenu/releases). Extract it into `ue4ss/Mods/`. No rename — the zip already contains the correct path:

```
ue4ss/Mods/
  shared/
    ModMenu/
      ModMenu.lua           ← bundled runtime (from ModMenu.zip)
    UEHelpers/              ← already part of normal UE4SS layouts
  YourHostMod/
    enabled.txt
    Scripts/
      main.lua              ← Init + Register feature modules
      myfeature.lua         ← optional: section logic
```

Require path (same style as UEHelpers):

```lua
local ModMenu = require("ModMenu.ModMenu")
```

The host mod must be enabled (`enabled.txt` / `mods.txt`). ModMenu is loaded via `require` from `shared/`; it is not a separate enabled mod.

Build a local zip (iteration only — do not upload it as the public release):

```bash
npm run deploy
```

Also produced for tooling: `dist/ModMenu.bundle.lua` and `dist/release/shared/ModMenu/ModMenu.lua`.  
`UEHelpers` is **not** bundled — leave the stock UE4SS copy under `Mods/shared/`.  
Omit this repo’s `README.md` / `GithubAssets/` from player zips (use Nexus gallery images instead).

### Source layout (contributors)

Development uses the multi-file tree (what you edit in this repo):

```
ModMenu.lua                 ← public API facade
ConfigManager.lua           ← shim: require("ModMenu.ConfigManager") → store/init.lua
store/                      ← host JSON store (init, json, paths)
core/                       ← util, theme, umg, shared, config (Init options), instance, input, …
shell/                      ← session, dock, collapse, tabs, build, lifecycle, registry
widgets/                    ← one module per item type + registry
tools/                      ← node: bundle.mjs, deploy.mjs
tooling/                    ← C# CLI, Studio, tests (not in ModMenu.zip)
```

`store/*.lua` and `widgets/*.lua` are auto-bundled. New `core/` or `shell/` files still need a `MODULES` row in `tools/bundle.mjs`.

UX / north star: `vision.md` (shipped; leftovers are optional).

---

## Recommended pattern

**Within one mod:** that mod owns one shell; feature scripts only call `Register` / `Get` / `Set` / etc.  
**Across mods:** each enabled Lua mod may `Init` its own independent shell (separate hotkey / dock / `instanceId`).

### Host — `Scripts/main.lua`

```lua
local ModMenu = require("ModMenu.ModMenu")
local MyFeature = require("myfeature")

ModMenu.Init({
    title = "My Mod Menu",
    instanceId = "YourHostMod", -- unique FName tag (Live View: ModMenu_Root_YourHostMod_1)
    key = Key.F6,
    keyHint = "F6",
    dock = "left", -- "left" | "right" | "top" | "bottom" (starting edge; user can change)
    -- theme = "dark", -- charcoal panel; omit for the current ("light") look
    -- tabs = { "Cheats", "Give", "Keybinds" }, -- omit = single scroll
    -- debug = true, -- verbose [ModMenu] traces (open/close, collapse, register, click path)
    -- pointerMode = "touch", -- Ally: checkbox as tap buttons; ignore late LMB latch
    -- showClose = false, -- hide the title-row Close button (on by default)
    -- inputBackend = "engine", -- opt-in when RegisterKeyBind does not fire
    -- consoleCommand = "modmenu",
    -- cursorMode = "modmenu", -- overlay pointer when the game hides the engine cursor
    -- cursorScale = 1, -- overlay pointer size (1 = native ~28x46; 2 = larger)
    -- fontScale = 1.25, -- multiply default font sizes (per-game). fontTitle / fontItem / … still override.
})

MyFeature.RegisterMenu(ModMenu)

print("[YourHostMod] Loaded — F6 opens menu")
```

Use a **different toggle key** per mod if several menus may run together (e.g. F6 + F7).

On bind, ModMenu claims `ModMenu.KeyClaim.<keyHint>` via `ModRef`. If another instance already claimed that hint, it logs **KEY CONFLICT** (still binds — warn only). UE4SS may invoke every binder on that key, so same-key menus can open together (handy for same-author left/right docks; risky for unrelated mods).

### Feature — `Scripts/myfeature.lua`

```lua
local M = {}

---@param ModMenu table
function M.RegisterMenu(ModMenu)
    ModMenu.Register({
        id = "MyFeature",           -- stable unique id (re-Register replaces)
        title = "My Feature",       -- section header
        items = {
            {
                type = "label",
                label = "Short hint for players.",
            },
            { type = "separator" },
            {
                type = "button",
                id = "doThing",
                label = "Do thing",
                onClick = function()
                    -- your game logic
                end,
            },
            {
                type = "checkbox",
                id = "enabled",
                label = "Enabled",
                default = false,
                onChange = function(on)
                    print("enabled = " .. tostring(on))
                end,
            },
            {
                type = "dropdown",
                id = "mode",
                label = "Mode",
                options = {
                    "Simple",
                    { label = "Advanced", value = "adv" },
                },
                default = "Simple",
                onChange = function(value)
                    print("mode = " .. tostring(value))
                end,
            },
        },
    })
end

return M
```

### Why this shape?

| Role | Responsibility |
|------|----------------|
| Host | `Init` once (title, key, dock), wire features |
| Feature module | Own section `id`, items, callbacks, game calls |
| ModMenu | Draw panel, input, values store, dock |

Shipping extra cheats later = add another `*.lua` + one `RegisterMenu` call in the host.

**Multi-mod:** any number of mods may `Init` their own shell. Each gets a process-wide instance serial (`ModMenu.NextInstanceId` shared var) and optional `instanceId` tag so Live View shows distinct roots (`ModMenu_Root_DevTools_1`, `ModMenu_Root_TestMod_1`). Closing one menu will not force GameOnly input while another ModMenu is still open.

---

## API

### `ModMenu.Init(opts?)`

Configure and bind this mod’s shell. Safe to call more than once (updates config).

| Option | Default | Notes |
|--------|---------|--------|
| `title` | `"Mod Menu"` | Header title |
| `instanceId` | `"iN"` | FName tag; set once before first shell create (e.g. `"TestMod"`) |
| `key` | `Key.F6` | Toggle key for the `ue4ss` backend (use a unique key per mod) |
| `keyHint` | `"F6"` | Shown in the header hint |
| `keyName` | from `keyHint` | Unreal `FKey` name for the `engine` backend (e.g. `"F7"`). Required when `keyHint` is not a plain name. |
| `inputBackend` | `"ue4ss"` | `"ue4ss"` (RegisterKeyBind) or `"engine"` (poll `IsInputKeyDown`). Opt-in — no auto-detect. Same backend for toggle **and** LMB. |
| `consoleCommand` | `nil` | Optional. Registers `name [toggle/open/close]`. Do not also register the same command in the host. |
| `dock` | `"right"` | `"left"` \| `"right"` \| `"top"` \| `"bottom"`. Author default. Header dropdown offers all four. Same panel footprint, rotated 90° for top/bottom (`widthFrac` is thickness). |
| `widthFrac` | `0.32` | Panel thickness as % of viewport (width on left/right; height on top/bottom) |
| `topFrac` / `bottomFrac` | `0.05` | Long-axis margins (vertical on left/right; horizontal on top/bottom) |
| `rightFrac` | `0.01` | Thickness-edge gap (all four docks) |
| `fontScale` | `1` | Multiplies the default font sizes (same idea as UE4SS `GuiConsoleFontScaling`). Prefer this for per-game **desktop** tuning. Explicit `fontTitle` / … still win and are not scaled by this. |
| `fontTitle` / `fontHint` / `fontItem` / `fontSection` / `fontDropdown` | 22 / 14 / 16 / 18 / 15 | Optional absolute sizes. Omit and use `fontScale` unless one role needs a one-off size. `fontDropdown` is header + option rows. |
| `touchFontScale` | `1.75` | Used only when `pointerMode` is `"touch"`. Multiplies resolved fonts **and** desktop `widthFrac` (0.32 → ~0.56, cap 0.85). Mortal Shell 2 `fontItem = 10` becomes 18. Not stacked across later `Init` calls. |
| `theme` | `"light"` | Author preset: a preset id such as `"slate"`, or a theme definition table. `"light"` is the current look (navy panel, light fields). `"dark"` is charcoal panel, dark fields, teal/gold tokens. An unknown id raises an error that lists every id. Not a player setting. See **Themes and styles**. |
| `style` | `nil` | Optional per-object-type overrides over the theme, plus `palette`. Merged over the `style` of earlier `Init` calls. See **Themes and styles**. |
| `fonts` | `nil` | Optional table of font id to object path, for game fonts such as `kanit`. Merged across `Init` calls. See **Themes and styles**. |
| `colors` | from `theme` | Optional overrides: `{ panelBg = { R, G, B, A }, ... }`. Merged onto the preset. See **Theming**. |
| `tabs` | `nil` | Optional `{ "Cheats", "Give", ... }`. Adds a tab strip; only the active tab's sections are built. Omit = current single-scroll menu. Duplicate / empty names error. |
| `canOpen` | `nil` | Optional `function(): boolean` or `false, "reason"`. Gates **open** (key toggle + `ModMenu.Open`); close is never gated. Pass `false` on a later `Init` to clear. |
| `ignoreLook` | `false` | Opt-in. While open, `SetIgnoreLookInput(true)` so mouse-look games do not spin the camera. Default off — hosts that need a locked camera must pass `true`. |
| `cursorMode` | `"engine"` | `"engine"` (PlayerController / GameAndUI cursor only) or `"modmenu"` (opt-in HitTestInvisible overlay pointer above the shell). Use when the game suppresses the engine cursor. A later `Init` that changes this (or `cursorScale` / `cursorHideClasses`) rebuilds the overlay if it already exists. |
| `cursorScale` | `1` | Overlay pointer multiplier (`1`–`8`). The glyph is the Windows arrow (~28×46) with a 1px outline + drop shadow. `2` if you want it larger. Only used when `cursorMode = "modmenu"`. Live `Init` updates rebuild the overlay. |
| `cursorHideClasses` | `nil` | Optional string array of UUserWidget class short names to collapse while the ModMenu cursor is shown (e.g. `{ "WB_Cursor_C" }`). Host-supplied; empty by default. Class defaults (`Default__…`) are skipped. On close, each widget is restored to the visibility it had before hide — not forced visible. |
| `debug` | `false` | Verbose `[ModMenu]` traces (open/close, collapse, register, click routing). Failures always print. |
| `pointerMode` | `"mouse"` | `"mouse"` (default) or `"touch"` / `"handheld"` (same). Touch: ignore delayed LMB latch; checkbox ON/OFF buttons; fonts + panel width × `touchFontScale`; 28px scrollbar; a tab strip that is `spacing.tabHeight` tall (default 56) with `spacing.dockPadTouch` of space under Dock. Hosts keep `{ type = "checkbox" }` and desktop `font*` / `widthFrac`. |
| `showClose` | `true` | Title-row **Close** button (same path as the toggle key). Default on so you can dismiss with the mouse. Pass `false` to hide. |
| `spacing` | see **Spacing** | Optional table of layout gaps and paddings in pixels. Keys you omit keep their defaults. See **Spacing** below. |
| `tooltipDelayMs` | `400` | How long, in milliseconds, the pointer rests on an item before its `tooltip` shows. A value that is not a finite number of zero or more raises an error. See **Tooltips** under **Item types**. |
| `autosave` | `false` | Opt-in. `true` saves the dock edge, the active tab, the collapse state of sections and folds, and item values in `ModMenu.ConfigManager` under the reserved key `__modmenu`, and restores them on the next launch. A value that is not a boolean raises an error. See **Autosave** under **Persistence**. |

Also installs viewport hooks and the input backend (`core/input.lua`): toggle + LMB click latch. Default `ue4ss` uses `RegisterKeyBind`. Pass `inputBackend = "engine"` on games where those binds never fire (e.g. Code Vein 2); that polls Unreal `IsInputKeyDown` for the toggle key and left mouse.

```lua
-- Games where RegisterKeyBind does not fire:
ModMenu.Init({
    title = "My Cheats",
    key = Key.F7,
    keyHint = "F7",
    keyName = "F7",
    inputBackend = "engine",
    consoleCommand = "modmenu",
    ignoreLook = true,
})
```

```lua
-- Games that hide / replace the engine cursor (overlay pointer):
ModMenu.Init({
    title = "Give Item Cmd",
    instanceId = "GiveItemCmd",
    key = Key.F6,
    keyHint = "F6",
    ignoreLook = true,
    cursorMode = "modmenu",
    cursorHideClasses = { "WB_Cursor_C", "WB_CursorHidden_C" },
})
-- Wuchang: close the menu before death / area load. ClientRestart with the
-- shell open fatals in that title only; other games restore the menu fine.
```

```lua
-- Keep F7 bound, but only open when another menu allows it:
ModMenu.Init({
    title = "Dev Tools",
    key = Key.F7,
    keyHint = "F7",
    canOpen = function()
        if not cheatMenuOpen then
            return false, "Open the cheat menu first"
        end
        return true
    end,
})

-- Host can still drive the shell explicitly:
--   ModMenu.Open()   -- also respects canOpen
--   ModMenu.Close()  -- always allowed
```

#### Spacing

The shell reads its gaps and paddings from `Init`'s `spacing` table instead of fixed numbers, so a host can tune the layout without editing ModMenu. Every value is in pixels. A key you omit keeps its default, so `Init` without `spacing` leaves the layout exactly as before. An unknown key, or a value that is not a finite number of zero or more, raises an error that names the key. A later `Init` with a `spacing` table is merged over the current spacing, so it keeps the overrides of earlier calls.

| Token | Default | What it controls |
|-------|---------|------------------|
| `gapItem` | `8` | The space between a section's title and its first item. |
| `gapSection` | `18` | The gap between one section and the next. |
| `footerPad` | `8` | The empty space below the last section with a mouse. |
| `footerPadTouch` | `120` | The empty space below the last section when `pointerMode` is `"touch"`, so the last buttons clear the screen edge. |
| `confirmWidth` | `360` | The width of the confirm dialog card. |
| `tabHeight` | `56` | The minimum height of a tab button when `pointerMode` is `"touch"`. With a mouse, tab buttons keep their text height. |
| `tabGap` | `4` | The gap between tab buttons with a mouse. |
| `tabGapTouch` | `8` | The gap between tab buttons, and the horizontal padding inside a tab button, when `pointerMode` is `"touch"`. |
| `tabPad` | `8` | The space below the tab strip with a mouse. |
| `tabPadTouch` | `12` | The space below the tab strip, and the vertical padding inside a tab button, when `pointerMode` is `"touch"`. |
| `dockPad` | `8` | The space below the Dock picker with a mouse. |
| `dockPadTouch` | `24` | The space below the Dock picker when `pointerMode` is `"touch"`. |
| `headPad` | `16` | The space between the panel's header controls and the first section. |
| `confirmGap` | `8` | The gap between the Cancel and Confirm buttons of the confirm dialog. |
| `sectionHeaderPadX` | `10` | The padding at the left and right edges of a collapsible section header. |
| `sectionHeaderPadY` | `4` | The padding above and below the title and mark of a collapsible section header. |
| `sectionHeaderGap` | `12` | The gap between a collapsible section header's title and its plus or minus mark. |
| `tooltipPad` | `6` | The padding on all four sides of the tooltip text. |
| `tooltipGap` | `12` | The distance between the pointer and the tooltip's nearest corner. |
| `tooltipMaxWidth` | `320` | The width at which tooltip text wraps onto a new line. |
| `panelPad` | `nil` | The padding inside the panel on all four sides. When it is not set, the theme's panel padding is used. Once a host sets `panelPad`, a later `Init` cannot unset it, because a key set to `nil` is absent from the table and the merge keeps the earlier value. |

```lua
-- Widen the gap between sections and keep every other gap at its default:
ModMenu.Init({ spacing = { gapSection = 24 } })
```

`ModMenu.GetInstanceId()` / `ModMenu.GetInstanceSerial()` — debug helpers for logs / Live View.

### `ModMenu.Register(section)`

Add or **replace** a section by `section.id`. If the menu is open, content rebuilds.

```lua
{
  id = "UniqueId",       -- required
  title = "Display",     -- optional; defaults to id
  tab = "Cheats",        -- optional; requires Init({ tabs = { ... } }); omit = first tab
  collapsible = false,   -- optional; accordion header (title left, + / - right)
  collapsed = false,     -- optional; start closed (requires collapsible = true)
  -- onToggle = function(collapsed) end,  -- optional
  items = { ... },       -- required array (may include type = "fold")
}
```

A section may also set `description`, one line of muted text under its title, and `prefix`, a short string such as a tag drawn before the title text.

Default is **not** collapsible — existing sections stay always-open. Session remembers open/closed per `id` (re-Register does not reset it; saved to disk only with `Init({ autosave = true })`). Nest groups **inside** a section with `type = "fold"` (see **Item types**).

Omit `Init tabs` and the menu stays a single scroll (Mortal Shell 2 and other hosts unchanged). With tabs, only the **active** tab's sections are built — switching rebuilds content (values from `Get` / `Set` still live for hidden tabs). Last tab is session-only (survives close/open; written to disk only with `Init({ autosave = true })`).

```lua
ModMenu.Init({
    title = "My Cheats",
    tabs = { "Cheats", "Give", "Keybinds" },
})

ModMenu.Register({
    id = "Combat",
    title = "Combat",
    tab = "Cheats",
    items = { ... },
})
```

```lua
ModMenu.Register({
    id = "Keybinds",
    title = "Keybinds",
    collapsible = true,
    collapsed = true, -- start hidden
    items = {
        { type = "label", label = "Set a key per action. Hidden until you open this section." },
    },
})
```

### Values

```lua
ModMenu.Get(sectionId, itemId)           -- checkbox bool / dropdown value
ModMenu.Set(sectionId, itemId, value)    -- sync store + live widget
```

Keys are stored as `"SectionId.itemId"`.

### Labels

```lua
ModMenu.SetLabel(sectionId, itemId, "New text")
```

Label items need an `id` for this to work.

### Buttons

```lua
ModMenu.SetButtonLabel(sectionId, itemId, "Scanning...")
ModMenu.SetEnabled(sectionId, itemId, false)  -- no clicks + themed disabled chrome
ModMenu.SetButtonVariant(sectionId, itemId, "danger")  -- default|primary|secondary|success|danger|warning|info
ModMenu.SetButtonActive(sectionId, itemId, true)     -- selected/on (green)
```

Button items need an `id`. Optional Register fields: `enabled = false`, `variant = "primary"|"danger"|…`, `active = true`. Paint order: disabled, then active, then variant. `accent` is accepted as an alias of `primary`.

### Enabled and visible

Every item accepts `enabled` and `visible`, and both default to true.

```lua
{ type = "slider", id = "speed", label = "Speed", min = 0, max = 10, visible = false }

ModMenu.SetEnabled(sectionId, itemId, false)  -- draws dim, ignores clicks, drags and typing
ModMenu.SetVisible(sectionId, itemId, false)  -- takes no space; the value is kept and autosave still saves it
```

Both return `false` when the section or item is not registered. Neither rebuilds the section. A row or fold passes both flags to its children, so a disabled fold disables everything inside it and a hidden fold hides it. `SetButtonEnabled` stays and does the same as `SetEnabled`.

### Confirm

In-shell modal on the docked panel. Blocks other clicks until Cancel or Confirm. Closing the menu dismisses without running the action.

```lua
-- Declarative (preferred): onClick waits for Confirm
{
  type = "button",
  id = "giveAll",
  label = "Give All Items",
  variant = "danger",
  confirm = {
    title = "Give all items?",
    message = "Adds every pickup. This cannot be undone here.",
    confirmLabel = "Give all", -- optional, default "Confirm"
    cancelLabel = "Cancel",    -- optional
    -- variant = "danger",     -- optional; defaults to the button variant
  },
  onClick = function()
    -- only after Confirm
  end,
}

-- Imperative (dynamic copy)
ModMenu.Confirm({
    title = "Reveal all icons?",
    message = "Paints every map icon and autosaves.",
    confirmLabel = "Reveal all",
    variant = "danger",
    onConfirm = function()
        -- ...
    end,
    -- onCancel = function() end,
})

ModMenu.IsConfirmOpen()
```

### Dropdown options

```lua
-- Replace options; optionally set or clear selection
ModMenu.SetOptions(sectionId, itemId, options, selectedValue)
ModMenu.SetOptions(sectionId, itemId, options, false)  -- clear selection
```

- Searchable dropdowns refresh rows **in place** when the menu is open.
- Non-searchable dropdowns rebuild the panel.

### Lifecycle

```lua
ModMenu.OnOpen(function()
    -- lazy load DBs, refresh status, etc.
end)

ModMenu.Open()
ModMenu.Close()
ModMenu.Toggle()
ModMenu.IsOpen()           -- boolean
ModMenu.ListSections()     -- { "MaxRank", "Items", ... }
ModMenu.SetDock("left")
ModMenu.GetDock()
ModMenu.OnDockChange(function(side)
    -- persist with the host store if you want it next launch
end)
ModMenu.SetTab("Give")     -- requires Init({ tabs = ... })
ModMenu.GetTab()           -- nil when tabs are off
```

`OnOpen` runs each time the menu finishes opening (after the shell is visible). Register as many callbacks as you need (e.g. one per feature).

`OnDockChange` runs after the header picker or `SetDock` applies an edge. Without `Init({ autosave = true })` ModMenu does not write disk, so hosts that want memory across launches save `side` and pass it back on `Init({ dock = ... })`. With autosave on, ModMenu saves the dock itself (see **Autosave**).

### Persistence

Optional JSON store, same singleton either way:

```lua
local ModMenu = require("ModMenu.ModMenu")
local ConfigManager = ModMenu.ConfigManager
-- or: require("ModMenu.ConfigManager")

ConfigManager.Init({
    id = "YourHostMod",
    defaults = { dock = "right", keybinds = {} },
})

local dock = ConfigManager.Get("dock")
ModMenu.Init({ dock = dock })
ModMenu.OnDockChange(function(side)
    ConfigManager.Set("dock", side)
end)
```

`Init` the store **before** `ModMenu.Init` when launch options (dock, toggle key) come from disk. The store's functions are `Init`, `Get`, `Set`, `Save`, `File`, `LoadFailed` and `Overwrite`. Implementation is `store/` (`init`, `json`, `paths`). Path is `Mods/<id>/config.json`. Hosts own what is written. ModMenu writes nothing unless `Init` sets `autosave = true`, and then it writes only its own key.

#### Autosave

`ModMenu.Init({ autosave = true })` saves the menu state in the same store, under the key `__modmenu`. That key is reserved for ModMenu, so a host must not use it for its own data. Every other key in `config.json` stays as the host wrote it, because ModMenu writes only with `ConfigManager.Set("__modmenu", snapshot)`.

```lua
ConfigManager.Init({ id = "YourHostMod" })
ModMenu.Init({ title = "My Mod Menu", autosave = true })
```

The snapshot holds six things.

- The dock edge.
- The active tab, when `Init` sets `tabs`.
- The collapse state of each collapsible section, in `collapsed`.
- The collapse state of each fold, in `folds`.
- The value of each `checkbox`, `dropdown`, `number`, `textinput`, `slider`, `radio`, `keybind`, `stepper`, `multiselect` and `colorpicker` item. A multiselect saves its array of checked values and a colorpicker saves its four numbers `R`, `G`, `B` and `A`, and each is restored only when it is still valid for the item. Buttons, labels, separators and progress bars hold no saved value.
- The key of each `checkbox`, `dropdown`, `radio` and `textinput` value that was cleared with `ModMenu.Set(sectionId, itemId, nil)`, in `cleared`. A cleared value stays cleared after a restart rather than coming back as the default.

```json
{
  "x": "a host key, left as it is",
  "__modmenu": {
    "dock": "left",
    "tab": "Give",
    "collapsed": { "MyMod": false },
    "folds": { "MyMod.advanced": true },
    "values": { "MyMod.enabled": true, "MyMod.count": 3 },
    "cleared": { "MyMod.name": true }
  }
}
```

A key in `collapsed` is the section id, and a key in `folds` is `<sectionId>.<foldId>`. They are kept apart because a section id such as `MyMod.advanced` would otherwise share a key with the fold `advanced` of section `MyMod`. A value key is `<sectionId>.<itemId>`, the same key `ModMenu.Get` uses. The saved state of a section that is not registered in a session is written back unchanged, so a section registered only some of the time keeps its state.

The snapshot is read once, as soon as the store is initialized, and is applied before the menu is first built. A saved value therefore replaces the item's `default`, a saved dock replaces `Init({ dock })`, and a saved tab replaces the first tab. A section gets its saved state on its first `Register`, so a later `Register` of the same section keeps what the player changed. A saved value for an item that no longer exists is ignored, as are a dock that is not one of the four edges and a tab that `Init` does not list. A saved value of the wrong type for its item is ignored too, so a `checkbox` takes only a boolean, a `number` or `slider` only a number, and a `dropdown`, `textinput`, `radio` or `keybind` only a string. A later `Init` call keeps the loaded dock and tab, and the tab is kept only when that `Init` lists it. Numbers, sliders, radios and keybinds pass their saved value through the same checks as a value set before `Register`, so a saved number outside a new range comes back inside it. `onChange` does not run for a restored value, so a host that acts on a value reads it with `ModMenu.Get` after `Register`.

A write happens 300 ms after the last change, so dragging a slider or typing writes once rather than on every step. While the menu is open the poll loop makes the write, and after it closes a delayed call does. Changes made through `ModMenu.Set`, `SetDock` and `SetTab` are saved as well. Nothing is written before the snapshot was read, so an early `Set` cannot replace the saved state with the defaults. If the store's file failed to parse, `Set` writes nothing, as described above, and the state is kept in memory until the host calls `Overwrite`.

`ConfigManager.Init` may run before or after `ModMenu.Init`. When it runs later, the snapshot is read on the next `Register` or `Open`. A host that never initializes the store gets no autosave, and nothing is read or written. A store that raises an error on a write logs `autosave failed` and the menu keeps working. `Init({ autosave = false })` turns autosave off again and drops a write that was still waiting, and an `Init` that omits `autosave` keeps the current setting. When the shell is torn down, as on a client restart, a waiting write is made at once.

The store never opens `config.json` for writing, because opening it would empty it before the new text is on disk. A save writes the whole file to `config.json.tmp` and renames it over `config.json`. Where that rename fails because the file exists, as it can on Windows, the old file is first moved to `config.json.prev` and is removed once the new file is in place. A crash at any point therefore leaves a whole config on disk.

If `config.json` does not parse, `Init` loads the defaults, leaves the file untouched and copies it to `config.json.bad`. If a crash left the old config at `.prev` and the newer one at `.tmp`, `Init` moves `.prev` back, loads that older config and copies the newer one from `.tmp` to `.bad`. When `.bad` already holds a different file, the copy goes to `.bad.2`, `.bad.3` and so on, and a file already copied with the same bytes is not copied again.

`LoadFailed()` returns true after a parse failure, after `.prev` could not be moved back, or while the newer config at `.tmp` could not be copied to `.bad`. While it is true, `Set` keeps the value in memory and returns false, and `Save` writes nothing and returns false, so that the user's file is not replaced by defaults. Otherwise `Set` returns true when the value is unchanged or was stored, and with autosave on it returns the result of `Save`.

The store does not recover on its own. A host checks `LoadFailed()`, decides when the old file may be replaced, for example after telling the user where the `.bad` copy is, and then calls `Overwrite()`. `Overwrite` writes the current in-memory values, including any values set while saves were refused, and returns the result of that save. It refuses and returns false while the unparsed file or the newer config at `.tmp` still has no copy at `.bad`, and it tries that copy again on each call. After a failed restore the older config stays at `.prev` until a later save removes it. A host that never calls `Overwrite` gets false from every `Set` and `Save` until a later launch finds a usable file.

`Get` can return a table whose array holds `require("ModMenu.store.json").null` where the file had `null`. Compare an element with `==` against that value. It is read-only, so writing into it raises `json.null is read-only`; replace the element instead.

### Tests (no game)

CI (`.github/workflows/ci.yml`) runs `dotnet test tooling/ModMenu.sln` on every pull request and push to `main`. Locally:

```bash
npm test
# or: dotnet test tooling/ModMenu.sln
dotnet run --project tooling/CLI -- test
dotnet run --project tooling/CLI -- detect
```

Lua specs live in `tooling/lua/` (store / ConfigManager shims, json, paths, dock math, options). `builder_export_spec.lua` runs the Lua the builder writes, from `tooling/lua/fixtures/`, through `Config.ApplyInit` and `Registry.Register`, so a field the builder writes that the library rejects fails there; `npx vitest run -u` in `builder/` rewrites those two fixture files. Headless Studio window tests lock the picker, remembered last game, Refresh rebind, the **Run Lua tests** log, and the last-run pass/fail banner. In-game **Launch and test** also persists dock through `ModMenu.ConfigManager` on Harness A and B (each writes its own `config.json`).

### Studio

![ModMenu Studio after Launch and test — Mortal Shell II, in-game harness passed (70 checks)](GithubAssets/ModMenuStudio-hero.png)

*ModMenu Studio: pick a UE4SS game, run the no-game Lua suite, or **Launch and test**. The last-run bar stays on screen (here: in-game harness passed, 70 checks).*

```bash
dotnet run --project tooling/Studio
# or: npm run studio
```

In-game **Launch and test** stays local (needs Steam + a UE4SS game). `dotnet run --project tooling/CLI -- test --game "Fatal Claw"` (or Studio **Launch and test**) deploys `examples/ModMenuHarness.lua` (left) and `examples/ModMenuHarnessB.lua` (right) as two enabled mods. After a **30s settle**, A opens and runs the Lua feature suite, then closes. B waits for A's results, opens on the right, and checks that it is a separate `instanceId` / serial / tab session (not dual-open). Polls both `ue4ss/ModMenuHarness-results.json` and `ModMenuHarnessB-results.json` for 120s (240s with `--play-live`), then closes the game (if this run launched it) and removes only the harness mods.

`--play-live` writes `play-live.txt` on the host so the suite steps with `ExecuteInGameThreadWithDelay` (you can watch tabs/dock change). UE4SS must already be installed. FatalClawMod and `config.json` are left alone. `examples/ModMenuHost.lua` stays the human dummy; the harness is the suite.

### Releases

Official downloads are produced by `.github/workflows/ci.yml` on a `v*` tag (`vMAJOR.MINOR.PATCH`, for example `v1.4.0`). Tags `1.0.0`–`1.3.1` predate CI and stay as history.

The player artifact is `ModMenu.zip` (plus `SHA256SUMS.txt`). Studio and the CLI are not attached — run them from the repo (`dotnet run --project tooling/Studio`). `npm run deploy` and `tooling/deploy.ps1` are for local iteration only — do not upload a local publish as the public build.

---

## Extending: widget contract

Item types live under `widgets/`. The shell never hard-codes control UMG — it asks the registry. Do **not** `require` dropdown (or any widget type) from `ModMenu.lua`; the facade stays wire + public API. Host-facing `SetLabel` / `SetButtonLabel` / `SetButtonEnabled` / `SetButtonVariant` / `SetButtonActive` names stay.

### Contract

Each widget module returns a table:

| Hook | When |
|------|------|
| `type` | String id (`"button"`, …) — required |
| `validate(item, sectionId, index)` | `Register` — throw on bad fields |
| `seed(sectionId, item, values)` | `Register` — default into `values` |
| `build(ctx)` | `BuildContent` — construct UMG; append to `ctx.liveControls` |
| `poll(ctrl, ctx)` | every open-menu tick (checkbox, `IsPressed`, search) |
| `pollClick(ctrl, ctx)` | LMB latch rising edge; return `true` if consumed |
| `apply(ctrl, value, ctx)` | `ModMenu.Set` / `SetLabel` / live sync |

Dropdown also exposes helpers used by the registry (`refreshLive`, `collapseAll`, …).

### Build `ctx`

| Field | Purpose |
|-------|---------|
| `values` / `liveControls` | Shared store + control records |
| `config` | Fonts / layout from `Init` |
| `umg` | `ModMenu.core.umg` |
| `Input` | `ModMenu.core.input` |
| `ValueKey` / `SafeCall` / `IsValid` | Helpers |
| `ReclaimMenuInput` / `EnsureMenuVisible` | Shell input helpers |
| `contentBox` | Parent vertical box |
| `section` / `item` | Current section + item |
| `namePrefix` | Unique FName prefix |
| `layout` | `nil`, or `"horizontal"` inside a `row` |

### Adding a new type (PR checklist)

1. Create `widgets/<type>.lua` implementing the contract (copy `button.lua` or `checkbox.lua`).
2. `register(require("ModMenu.widgets.<type>"))` in `widgets/init.lua`.
3. Document fields under **Item types** below.
4. Smoke-test via a host `Register` section, then `npm run deploy`.

`store/*.lua` and `widgets/*.lua` are auto-bundled — do not add a `MODULES` row for a new store helper or widget. New `core/` or `shell/` files still need one.

---

## Item types

Supported: `checkbox` | `button` | `dropdown` | `label` | `separator` | `number` | `textinput` | `slider` | `radio` | `keybind` | `stepper` | `progress` | `multiselect` | `colorpicker` | `row` | `fold`  
(Implemented in `widgets/<type>.lua`.)

### Tooltips

Every item type accepts `tooltip = "text"`. A value that is not a string raises an error from `Register`, and the check also covers the children of a `row` or `fold`.

```lua
{ type = "button", id = "heal", label = "Heal", tooltip = "Restores health to full.", onClick = Heal }
```

When the pointer rests on the item for `tooltipDelayMs` (default 400 ms), one shared tooltip shows the text beside the pointer, and it hides when the pointer leaves. It opens toward the screen centre, away from the docked edge. It never takes the pointer, so it cannot end the hover that shows it. An open confirm dialog or a closed menu hides it. The box uses `confirmCardBg` (or `panelBg`) behind `textPrimary` at `fontHint` size, with the `tooltipPad`, `tooltipGap` and `tooltipMaxWidth` spacing tokens.

A tooltip shows only on an item that builds a live control. A `separator`, a `row` container and a `label` without an `id` build none, so their `tooltip` is validated but never shown. The children of a `row` or `fold` show their own tooltips.

### `separator`

```lua
{ type = "separator" }
```

### `label`

```lua
{ type = "label", label = "Hint text" }
{ type = "label", id = "status", label = "Ready" }  -- id required for SetLabel
-- Empty / whitespace-only labels are collapsed (no leftover gap). SetLabel("") hides the row; SetLabel("text") shows it again.
{ type = "label", label = "Heads up", style = "warning", align = "center", wrap = false }
```

| Field | Default | Meaning |
|---|---|---|
| `style` | `"normal"` | `normal`, `muted` (the muted text colour), `heading` (the section font size in the accent colour) or `warning` (the status colour). |
| `align` | `"left"` | `left`, `center` or `right`. |
| `wrap` | `true` | `false` keeps the text on one line. A label in a row never wraps. |

`Register` rejects any other `style` or `align` and lists the allowed values.

### `button`

```lua
{
  type = "button",
  id = "run",
  label = "Do thing",
  enabled = true,   -- optional; false blocks clicks + disabled chrome
  variant = "default", -- optional: default|primary|secondary|success|danger|warning|info
  active = false,   -- optional; true = selected/on (wins over variant)
  -- confirm = { title = "Are you sure?", message = "Cannot undo.", confirmLabel = "Do it" },
  onClick = function() end,
}
```

`confirm` opens an in-shell modal over the panel. `onClick` runs only after Confirm. Cancel or closing the menu does nothing. One confirm at a time (a new one dismisses the old as Cancel).

Use `SetButtonLabel` / `SetButtonEnabled` / `SetButtonVariant` / `SetButtonActive` for busy and toggle-on states.

| Variant | Use |
|---------|-----|
| `default` | Theme button (navy / charcoal) |
| `primary` | Main action (blue) |
| `secondary` | Muted gray |
| `success` | Positive confirm (green) |
| `danger` | Destructive (red) |
| `warning` | Caution / “Award ALL” (yellow) |
| `info` | Informational (cyan) |

`active = true` is **selected/on**, not a variant. No outline / link variants (UMG fill only).

An enabled button that is not active lightens its fill while the pointer is over it and darkens it while it is pressed. The menu polls `IsHovered` and `IsPressed` on the button and repaints only when that state changes. Disabled and active buttons keep their own fill. The state colours come from the theme; see **Theming & polish**.

A mouse click fires when the button is released over it. The pressed colour stays while the button is held, and releasing after the pointer moved off the button fires nothing. A touch tap fires on press. Tabs, Close, section and fold headers, the confirm buttons, the keybind button and the dropdown header and options follow the same rule and show the same hover and pressed colours.

### `checkbox`

```lua
{
  type = "checkbox",
  id = "enabled",
  label = "Enabled",
  default = false,
  onChange = function(checked) end,
}
```

### `dropdown`

Options may be plain strings or `{ label, value }` tables:

```lua
options = {
  "A",
  { label = "Bee", value = "b" },
}
```

**Simple (short lists):**

```lua
{
  type = "dropdown",
  id = "mode",
  label = "Mode",
  options = { "A", "B" },
  default = "A",
  onChange = function(value) end,
}
```

**Searchable (long lists — filter field + scroll):**

```lua
{
  type = "dropdown",
  id = "item",
  label = "Item",
  searchable = true,
  placeholder = "Select item...",
  maxVisible = 400,      -- cap on built option rows (raise carefully)
  listMaxHeight = 320,   -- scroll area height
  allowEmpty = true,     -- ok with no selection / empty filter results
  options = { { label = "Potion", value = "ITEM_ID" }, ... },
  default = nil,
  onChange = function(value) end,
}
```

| Field | Notes |
|-------|--------|
| `searchable` | Custom picker (not ComboBoxString) |
| `maxVisible` | Max option rows constructed; leftover shows “type to narrow” |
| `listMaxHeight` | ScrollBox height hint |
| `allowEmpty` | Allow cleared / placeholder state |
| `placeholder` | Header text when nothing selected |
| `onExpand` | Optional `function(list)`. Fires when the picker opens. Option rows are built on first expand (not at menu build), so heavy lists can stay cheap until opened. |

### `number`

Labeled numeric field. Value is stored as a Lua number (`Get` / `Set`). Invalid mid-edit text is ignored until a parseable number is typed.

`Set` turns its value into a number in the item's range: a numeric string such as `"5"` is accepted, `integer` items are rounded, and the result is clamped to `min` and `max`. A value that is not numeric is ignored, so the stored value and the field keep what they had. `Set(sectionId, itemId, nil)` resets the item to its `default`, or to `0` when it has none, after the same rounding and clamping. A `Set` made before the section is registered is coerced the same way when `Register` runs, and a value that is not numeric is replaced by the default there. `Set` never fires `onChange`.

```lua
{
  type = "number",
  id = "count",
  label = "Count",
  default = 1,
  min = 1,
  max = 999,
  integer = true,       -- round to nearest int
  placeholder = "1",    -- hint when empty
  fieldWidth = 72,      -- EditableTextBox width
  labelWidth = 156,     -- optional; same width on every row = table-aligned fields
  debounceMs = 250,     -- delay onChange only (default 250; 0 = immediate). Get stays live.
  step = 5,             -- optional; adds minus and plus buttons that move the value by this much
  prefix = "$",         -- optional short text inside the field, before the entry
  suffix = "ms",        -- optional short text inside the field, after the entry
  onChange = function(n) end,
}
```

### `textinput`

Labeled string field.

```lua
{
  type = "textinput",
  id = "name",
  label = "Name",
  default = "",
  placeholder = "Enter name...",
  maxLength = 32,
  fieldWidth = 200,
  labelWidth = 156,     -- optional; align stacked fields
  debounceMs = 250,     -- delay onChange only (default 250; 0 = immediate). Get stays live.
  onChange = function(text) end,
}
```

`Get` / button `onClick` always see the latest parsed value. Only `onChange` waits for typing to pause.

### `slider`

A labelled track with a draggable knob over a numeric range. The current value is printed beside the label. Value is stored as a Lua number (`Get` / `Set`).

```lua
{
  type = "slider",
  id = "volume",
  label = "Volume",
  min = 0,              -- required
  max = 100,            -- required; must be greater than min
  default = 50,         -- optional; min when unset
  step = 5,             -- optional; values snap to min + a whole number of steps
  integer = true,       -- optional; round to the nearest whole number
  format = "%d%%",      -- optional; a string.format pattern, or function(value) returning the text
  live = false,         -- optional; true fires onChange on every step while dragging
  showValue = true,     -- optional; false hides the readout beside the label
  labelWidth = 140,     -- optional; fixes the label column, as number's does
  onChange = function(n) end,
}
```

Press the track and drag to move the knob, or click a point on the track to jump there. The value snaps to `step` while the knob moves. `min` and `max` are always reachable, even when the range is not a whole number of steps. By default `onChange` fires once, on release, and only when the value changed. With `live = true` it fires on every new step during the drag. In a `row`, the track is 160 pixels wide unless the item sets `fill = true`. In touch mode the track and the knob are larger. The track uses `buttonBg`, the part left of the knob uses `buttonBgPrimary`, the knob uses `textPrimary`, and the value text uses `textMuted`.

`Register` raises an error when `min` or `max` is missing or not a number, when `min` is not less than `max`, when `step` is not a positive number, or when `default` is not numeric. `Set` turns its value into a number the same way a drag does: a numeric string is accepted, and the value is snapped, rounded for an `integer` item, and clamped. Once the section is registered, whether or not the menu has built the item, a value that is not numeric is ignored and the stored value is kept. `Set(sectionId, itemId, nil)` resets the item to its `default`. A `Set` made before the section is registered is coerced when `Register` runs. `Set` never fires `onChange`.

### `radio`

A group of buttons with one chosen option. Options take the same shape as a `dropdown`: plain strings or `{ label, value }` tables. The value is the chosen option's value as a string, or `nil` when nothing is chosen.

```lua
{
  type = "radio",
  id = "difficulty",
  label = "Difficulty",
  options = { "Easy", { label = "Normal", value = "normal" }, "Hard" },
  default = "normal",   -- optional; must be one of the option values
  inline = true,        -- optional; true puts the buttons in one row, otherwise they stack
  onChange = function(value) end,
}
```

Each option is a button. The chosen one uses the active button fill (`buttonBgActive`), and the others take the default button fill with the same hover and pressed colours as a plain button. Pressing the chosen option again changes nothing and fires no `onChange`.

`Register` raises an error when `options` is missing or empty, or when `default` is not one of the option values. Without a `default`, the group starts with nothing chosen. `Set` with a value that is not one of the options raises `radio <id>: value must be one of <values>` once the section is registered, and the stored value is kept. `Set(sectionId, itemId, nil)` clears the choice. A `Set` made before the section is registered is checked when `Register` runs, and a value that is not an option is replaced by the default there. `Set` never fires `onChange`.

### `keybind`

A button that shows a key binding and captures a new one when clicked. The value is an Unreal FKey name string (`Get` / `Set`), such as `"F7"`, or `"LeftControl+F7"` when modifiers are held. An empty string means no binding, and the button shows `None`.

```lua
{
  type = "keybind",
  id = "dash",
  label = "Dash",
  default = "F7",          -- optional; "" or unset means no binding
  allowModifiers = true,   -- optional; store held Control, Alt and Shift in front of the key
  onConflict = function(otherId, value, otherSectionId)
    return false           -- true keeps both bindings; false or no onConflict refuses the new one
  end,
  onChange = function(value) end,
}
```

Click the button and it shows `Press a key`. The next letter, digit, function key (`F1` to `F12`) or arrow key that goes down becomes the binding. With `allowModifiers = true`, the held modifiers (`LeftControl`, `RightControl`, `LeftAlt`, `RightAlt`, `LeftShift`, `RightShift`) are written in front of it in that order. A modifier alone is never a binding. Escape or a second click cancels the capture and keeps the old binding. Only one keybind captures at a time. While capturing, the menu reads key state with the player controller's `IsInputKeyDown` every 50 ms, whichever `inputBackend` the host chose. A key already held when the capture starts is not captured.

A binding already held by another `keybind` item in any section registered on the same menu calls `onConflict(otherId, value, otherSectionId)`. Items of another mod's menu never conflict. The new binding is stored only when that call returns `true`, and an item without `onConflict` refuses it. Two bindings with the same key and modifiers conflict whatever order the modifiers are written in.

Capture never binds the menu's toggle key, because that key opens and closes the menu. Closing the menu ends any capture, so the first key pressed after the next `Open` is not taken as a binding.

The menu stores the binding but does not act on it. The host reads it with `Get` and checks the key itself. `Register` raises an error when `default` is not a string or is not a key name with known modifiers, when `allowModifiers` is not a boolean, or when `onConflict` or `onChange` is not a function. `Set` stores its value as given, ends any capture, never checks for a conflict and never fires `onChange`. Once the menu has built the item, `Set(sectionId, itemId, nil)` resets it to its `default`. A `Set` made before the section is registered that is not a key name is replaced by the default when `Register` runs.

### `stepper`

A label with a minus button, a readout and a plus button. The value is a number (`Get` / `Set`).

```lua
{
  type = "stepper",
  id = "count",
  label = "Count",
  min = 0,
  max = 20,
  step = 2,          -- optional; a positive number, default 1
  default = 4,
  integer = true,    -- optional; round to a whole number
  format = "%d",     -- optional; a string.format pattern for the readout
  onChange = function(value) end,
}
```

A click moves the value one step and keeps it between `min` and `max`. Holding a button repeats the step, first after 400 ms and then every 100 ms. `onChange` fires after each step that changed the value, and a click at either end changes nothing. `Set` snaps and clamps its value, ignores a value that is not numeric, resets to `default` for `nil`, and never fires `onChange`. A stepper may sit in a row or a fold. `Register` raises an error naming the field for a `min` or `max` that is not a number, `min` not below `max`, a `step` that is not positive, a `default` that is not numeric, an `integer` that is not a boolean, a `format` that is not a string, or an `onChange` that is not a function.

### `progress`

A label, a bar and a readout. The bar has no input, so the host moves it.

```lua
{
  type = "progress",
  id = "load",
  label = "Loading",
  min = 0,            -- optional, default 0
  max = 1,            -- optional, default 1
  default = 0.25,
  format = "%d%%",    -- optional; a string.format pattern or a function(value) returning text. The default is the percent of the range.
  variant = "success", -- optional; a button variant name for the fill colour
}
```

```lua
ModMenu.SetValue("Main", "load", 0.5)   -- clamps to the range and moves the bar with no rebuild; false for an unknown item
ModMenu.SetLabel("Main", "load", "Done") -- SetLabel also changes a progress item's label
```

The value is not saved, because the host drives it. A progress bar may sit in a row or a fold.

### `multiselect`

A caption and one toggle button per option, laid out in one to four columns. The value is an array of the checked option values, in option order (`Get` / `Set`).

```lua
{
  type = "multiselect",
  id = "tags",
  label = "Tags",
  options = { "Alpha", "Beta", { label = "Gamma", value = "g" } },  -- the dropdown's option shape
  default = { "Beta" },   -- optional; every entry must be an option value
  columns = 2,            -- optional; 1 to 4, default 1
  onChange = function(values) end,
}
```

Each click toggles one option and fires `onChange` with a copy of the new array. `Set` keeps only values that are options, in option order, ignores a value that is not a table, and resets to `default` for `nil`. Autosave saves the array. A multiselect is allowed in a fold only, because its height depends on the option count.

### `colorpicker`

A caption, a swatch filled with the current colour, and one slider per channel. The value is a table `{ R, G, B, A }` with each channel from 0 to 1 (`Get` / `Set`).

```lua
{
  type = "colorpicker",
  id = "tint",
  label = "Tint",
  default = { R = 0.2, G = 0.5, B = 0.8, A = 1 },
  alpha = true,           -- optional; false hides the A slider and keeps A at 1
  onChange = function(color) end,
}
```

The sliders step by 0.01 and the swatch follows them as they move. `onChange` fires once when a drag ends and the colour changed. `Set` clamps each channel and ignores a value that is not a table. Autosave saves the four numbers. A colorpicker is allowed in a fold only.

### `row`

Horizontal group. Children share one line (Unity-style Count + field + button).

Allowed children: `button` | `checkbox` | `label` | `number` | `progress` | `slider` | `stepper` | `textinput`  
(Not: nested `row`, `dropdown`, `multiselect`, `colorpicker`, `separator`, `fold`. Put a `row` *inside* a `fold` instead.)

```lua
{
  type = "row",
  items = {
    {
      type = "number",
      id = "count",
      label = "Count",
      default = 1,
      min = 1,
      integer = true,
    },
    {
      type = "button",
      id = "addSelected",
      label = "Add Selected",
      onClick = function()
        local item = ModMenu.Get("Items", "item")
        local count = ModMenu.Get("Items", "count")
        -- grant / spawn
      end,
    },
  },
}
```

Pair with a searchable `dropdown` above the row for the classic select → count → submit flow.

For stacked amount rows, set the same `labelWidth` + `fieldWidth` on every `number` so the fields line up.

### `fold`

Nested collapsible group **inside** a section (keybind categories, extra tools, …). Same accordion chrome as section collapse (title left, `+` / `-` right). Body is always built; toggle only show/hides it.

Default is **collapsed** (`collapsed` omitted or `true`). Pass `collapsed = false` to start open.

Allowed children: `button` | `checkbox` | `colorpicker` | `dropdown` | `keybind` | `label` | `multiselect` | `number` | `progress` | `radio` | `row` | `separator` | `slider` | `stepper` | `textinput`  
(Not: nested `fold`. Put folds in a collapsible **section** instead.)

`id` is required. `Get` / `Set` / `SetLabel` / `SetButtonLabel` / `SetButtonEnabled` / `SetOptions` resolve fold children, including a control nested in a `row` inside a fold.

Open/closed is session-only per `sectionId.foldId` (same idea as section collapse: survives close/open and `ClientRestart`; written to disk only with `Init({ autosave = true })`). Re-Register keeps the current state.

```lua
ModMenu.Register({
    id = "Keybinds",
    title = "Keybinds",
    collapsible = true,
    collapsed = true,
    items = {
        {
            type = "fold",
            id = "movement",
            label = "Movement",
            collapsed = true,
            items = {
                {
                    type = "dropdown",
                    id = "jump",
                    label = "Jump",
                    options = { "Space", "C", "Unbound" },
                    default = "Space",
                },
            },
        },
        {
            type = "fold",
            id = "combat",
            label = "Combat",
            items = {
                { type = "label", label = "Combat binds…" },
            },
        },
    },
})
```

---

## Dynamic UI patterns

### Update options without rebuilding the whole section

```lua
ModMenu.SetOptions("Items", "item", newOpts, false)
ModMenu.Set("Items", "item", nil)
```

Prefer this for category filters on a searchable list (see DevTools `items.lua`).

### Swap which controls exist

Re-call `Register` with the same `id` and a new `items` array (e.g. show Category only for English). Values for ids that still exist are kept when possible; seed `default` on first register. Rebuilds immediately if the menu is **open**. If the menu is closed after the first open, the next `Open` rebuilds.

### Lazy work on open

```lua
ModMenu.OnOpen(function()
    if alreadyLoaded then return end
    ExecuteInGameThreadWithDelay(50, function()
        -- fetch DB, then SetOptions / SetLabel / Register
    end)
end)
```

Heavy work on the click stack can hitch or crash — delay off the open path when loading large lists.

---

## Behaviour notes (for integrators)

1. **Per-mod shell** — each Lua mod has its own ModMenu state (`require` is not shared across mods). Multiple mods may each `Init` an independent panel. UObject roots are named `ModMenu_Root_<instanceId>_<n>` using a `ModRef` serial (`ModMenu.NextInstanceId`) so they never collide under `GameInstance`.
2. **Toggle keys** — prefer a unique `key` / `keyHint` per mod. Claims are stored as `ModMenu.KeyClaim.<keyHint>`; clashes log **KEY CONFLICT**. On the `ue4ss` backend, UE4SS may fire every binder on that key (both menus toggle — useful for same-author dual docks, confusing for unrelated mods). On `engine`, each shell polls independently.
3. **Input** — while open, uses GameAndUI + mouse cursor. Buttons / dock / dropdowns fire from `UButton:IsPressed()` (rising edge, 16ms poll) plus the LMB latch + `IsHovered()` fallback (touch also keeps the last hovered widget briefly and retries an unclaimed latch). Desktop checkboxes poll persistent `IsChecked()`. `pointerMode = "touch"` renders checkboxes as ON/OFF buttons so a finger tap uses the same press-edge path. The toggle key uses `Init inputBackend`: `ue4ss` (`RegisterKeyBind`) or `engine` (poll `IsInputKeyDown`). PlayerController often does **not** see LMB while Slate owns the mouse, so engine-backend menus must not rely on the LMB latch alone. Closing one menu does not force GameOnly while another ModMenu is still open (`ModMenu.OpenCount`). `ClientRestart` / `DestroyShell` do not touch input unless this instance had the menu open. On close, `GameOnly` is applied only if the game had no cursor when we opened (mouse-look); hub/inventory cursors are left alone. Camera look is **not** locked unless `Init({ ignoreLook = true })`. When the engine cursor is suppressed, opt in with `cursorMode = "modmenu"` for a HitTestInvisible overlay pointer (`core/cursor.lua`); optionally pass `cursorHideClasses` to collapse game cursor widgets while open (class defaults are skipped; prior visibility is restored on close). Overlay mode does not treat a hidden engine cursor as stolen (that would re-apply GameAndUI every tick and break checkboxes / text fields). A later `Init` that changes `cursorMode` / `cursorScale` / `cursorHideClasses` rebuilds the overlay if it already exists.
4. **Dock** — author `Init({ dock })` is the starting edge. Header dropdown offers Left / Right / Top / Bottom (`SetDock` accepts any of the four). Same rectangle rotated 90° (`widthFrac` stays thickness). No free drag. Session only unless `Init({ autosave = true })` is set or the host persists (`OnDockChange` + saved `Init` dock).
5. **Scroll** — the docked panel is a fixed viewport; section content lives in a ScrollBox (mouse wheel). Use `labelWidth` on `number` / `textinput` so amount rows line up like a table.
6. **FNames** — shell names include `instanceId`; content rebuilds bump an internal generation after `ClearChildren`. Collapse / fold expand/collapse show/hide a body and do not rebuild. Prefer `SetOptions` on searchable lists over constant full rebuilds. Menu close/open keeps the UMG tree (no rebuild) so large sections (Give, keybinds) do not respawn on every toggle. `Register` / non-searchable `SetOptions` rebuild **while the menu is open**, and mark the tree dirty if they run while it is closed so the next `Open` rebuilds. `ClientRestart` destroys the shell and restores it if it was open.
7. **Large lists** — keep `maxVisible` bounded; filter narrows the working set. Building thousands of UButtons at once is risky.
8. **Game readiness** — many game objects only exist after a save is loaded; surface that in a status `label` and/or `OnOpen` retry.
9. **Callbacks** — errors inside `onClick` / `onChange` are caught and logged as `[ModMenu] callback error: ...`.
10. **Logging** — quiet by default. Failures still print (`CreateShell failed`, `KEY CONFLICT`, `OPEN blocked`). `Init({ debug = true })` restores open/close, collapse, register, scrollbar, and click-path traces (`press-edge` / `latch-hover` / `latch-miss`). Click traces include `hover` / `pressed` / `capture` / `downVia` / `ptr`. On a handheld, `downVia=capture` is the touch signature — see **Ally / handheld**.
11. **Hot-reload** — `ModRef` shared vars (`NextInstanceId`, key claims, open count) are **not** cleared on Ctrl+R.
12. **Collapse** — opt-in (`collapsible = true`). Accordion header: title on the left, `+` (closed) / `-` (open) on the right. Toggle show/hides the section body (same as dropdowns; no content rebuild). Session-only per section `id` (survives close/open; written to disk only with `Init({ autosave = true })`). Re-Register keeps the current open/closed state. Nested groups use `type = "fold"` inside `items` — same session memory per `sectionId.foldId` (see **Item types**).
13. **Tabs** — opt-in (`Init({ tabs = { ... } })`). Strip under title / dock. Only the active tab's sections are constructed; switching rebuilds that body (not a hidden full tree). `Register({ tab = "Give" })`; omit `tab` = first name. `Get` / `Set` still work for hidden tabs. Session remembers the last tab (not disk). Keyboard Q/E is not in v1. `pointerMode = "touch"` makes the strip `spacing.tabHeight` tall (default 56) with `spacing.dockPadTouch` of space under Dock (desktop unchanged).

### Known limits

- Game-specific **input reclaim** (e.g. Thymesia `NativeUtils`, Wuchang `EnableMouse0`) remains **host responsibility**. `cursorMode = "modmenu"` only draws an overlay glyph; it does not replace per-game input adapters.
- **Wuchang:** close the menu before death or area load. `ClientRestart` with the shell open fatals in that title only (not cursor-related). Other games restore an already-open menu.
- No free-drag, CommonUI, or designer-authored WBP — dock presets + constructed UMG only.
- Camera look is **not** locked unless `Init({ ignoreLook = true })`.

### Ally / handheld

Windows touch is a fake mouse. Hosts that want handheld layout opt in (desktop stays `pointerMode = "mouse"`):

```lua
ModMenu.Init({
    pointerMode = "touch", -- or "handheld"
    -- debug = true, -- optional: click-path traces
})
```

Touch mode: checkboxes are ON/OFF buttons (`press-edge`); delayed LMB latch ignored; fonts and `widthFrac` × `touchFontScale` (default 1.75); ScrollBox thumb is 28px and always shown so it is hittable (content-drag is a later pass — buttons capture the pointer). The title-row **Close** button is on for every pointer mode (`showClose = false` to hide). The tab strip uses buttons that are `spacing.tabHeight` tall (default 56) and `spacing.dockPadTouch` of space under Dock so a finger aiming for Cheats / Give does not hit the Dock button. Desktop tabs stay compact.

---

## Themes and styles

A theme sets the whole look of the menu: colours, corner radius, outlines, fonts and the shape of each control. You choose one preset in `Init`, and you can change any part of it with `style`. Players do not pick a theme; the author sets it.

### Choosing a preset

Pass the preset id as `theme`:

```lua
ModMenu.Init({
    title = "My Cheats",
    theme = "slate",
})
```

`ModMenu.Themes()` returns every preset id in the order below. An unknown id makes `Init` raise an error that lists every id, and the menu keeps its previous theme.

| Id | Name | Look |
|----|------|------|
| `light` | Light | The shipped ModMenu look |
| `dark` | Dark | Charcoal with teal and gold |
| `slate` | Slate | Modern dark |
| `glass` | Glass | Frosted, over the game |
| `storm` | Storm | Amber on slate |
| `neon` | Neon | Synthwave |
| `doppler` | Doppler | Radar scope |
| `tornado-warning` | TORNADO WARNING | Take shelter now |
| `night-drive` | Night Drive | Instrument cluster |
| `loadout` | Loadout | Shooter HUD |
| `cozy` | Cozy | Farm life |
| `carbon` | Carbon | Sim racing |
| `blueprint` | Blueprint | Engineering drawing |
| `paper-blue` | Paper | Cool blue |
| `field-kit` | Field Kit | Rescue gear |
| `ink` | Ink | Black and white |
| `aurora` | Aurora | Night sky |
| `midnight` | Midnight | Calm and low contrast |
| `storm-front` | Storm Front | Lightning on violet |
| `sakura` | Sakura | Soft and light |
| `ocean` | Ocean | Deep water |
| `steel` | Steel | Brushed metal |
| `paper-sage` | Paper | Sage green |
| `dracula` | Dracula | The Dracula palette |
| `catppuccin-mocha` | Catppuccin Mocha | Soothing pastel, dark |
| `catppuccin-latte` | Catppuccin Latte | Soothing pastel, light |
| `material` | Material | Material Design, dark |
| `monokai` | Monokai | The classic editor theme |
| `nord` | Nord | Arctic, north-bluish |
| `terminal` | Terminal | Green phosphor with a blinking cursor |
| `hologram` | Hologram | Projected glass with a sweep, scanlines and glitches |
| `frost` | Frost | Ice with glints |
| `mac-light` | macOS Light | Window with traffic lights |
| `mac-dark` | macOS Dark | Window with traffic lights |

`theme` also takes a theme definition table with the same shape as a preset file, so you can write a custom theme in code. `ModMenu.ResolveStyle(theme, style, colors)` returns the complete style that `Init` would draw, without building any widget, for tests and tools.

### Object types

A theme is split into object types. Each type styles one kind of part, and `style` changes one type at a time.

| Type | Read by |
|------|---------|
| `panel` | The dock panel, its blur, shadow, rim and corner brackets |
| `header` | The title row and the Close button |
| `title`, `body`, `hint`, `data` | Text styles: the title, every label and caption, hints, and value readouts |
| `tabs` | The tab strip |
| `section` | Section headers and fold headers |
| `button` | `button` items, the confirm dialog's buttons and the stepper's buttons |
| `toggle` | `checkbox` items |
| `slider` | `slider` items and the colour picker's channels |
| `progress` | `progress` items |
| `choice` | `radio` and `multiselect` items |
| `field` | `textinput`, `number` and `keybind` items, and the `dropdown` header |
| `list` | The dropdown's option list |
| `stepper` | `stepper` items |
| `tooltip` | The tooltip card |
| `confirm` | The confirm card and the dim overlay behind it |
| `motion` | Animations, listed under **Motion** below |

The field names and kinds of every type are listed once, in `themes/fields.json`. An unknown type or field makes `Init` raise an error that names it.

### Motion

The `motion` type holds the animation switches. Each is a boolean.

| Field | Effect | Default |
|-------|--------|---------|
| `open` | Sections fade in one after another when the menu opens | on for every preset except `light` and `dark` |
| `pop` | A button pops slightly when clicked, and so does the close control | on for every preset except `light` and `dark` |
| `shake` | The menu shakes when a `danger` button is clicked, including the confirm dialog's | on for every preset except `light` and `dark` |
| `pulse` | The title pulses | set per preset; on in `neon` |
| `cursor` | A cursor in the header blinks once a second | set per preset; on in `terminal` |
| `glitch` | Interference bands and glitches appear at irregular times | set per preset; on in `hologram` |
| `sparkle` | Glints come and go | set per preset; on in `frost` |

Turn the default motion off with one table:

```lua
ModMenu.Init({
    theme = "slate",
    style = { motion = { open = false, pop = false, shake = false } },
})
```

### Window frames and caption buttons

`header.variant` picks the title bar. `window` draws a window title bar with caption buttons, `mac` draws traffic lights, `xpbar` draws the XP gradient bar, and `classic` draws the Windows 98 bar.

The caption buttons do not move or resize the menu. Minimise and close both close it. Maximise shows its hover and pressed looks and makes the menu pop, without closing it. On `mac`, the red and yellow lights close the menu, the green light behaves like maximise, and all three show their symbols while the pointer is over any of them.

Set `header.captions = "close"` to draw only the close button. The default is `"all"`.

```lua
ModMenu.Init({
    theme = "slate",
    style = { header = { variant = "window", captions = "close" } },
})
```

### Fields for window frames, gradients and bevels

These field kinds are new. Each is listed in `themes/fields.json`.

- `stops`: a list of at least two colours, drawn as a gradient.
- `bevel`: raised or sunken light and dark edge lines, with an optional inner ring.
- `faces`: a fill and text colour for each button role.
- `xpface`: an XP button's `edge`, `glow` and `defaultRing` colours, plus its `face` and `pressedFace` gradients.
- `frame`: an outlined or bevelled box around a trough, with padding.
- `statusbar`: a status strip with its fill, line and text.

An override of a `bevel`, `frame`, `statusbar`, `xpface` or `faces` field merges key by key, so you change one key and keep the rest. An override of a `stops` field replaces the whole list.

The `button` type has two new variants: `xp` and `classic`. Set `button.variant` in a theme to use one. `header.variant` takes `window`, `mac`, `xpbar` or `classic`, as above.

### Borrowing an object type from another preset

Set a type to a preset id to take its shape from that preset. The borrowed type drops the other preset's colours and takes the colours of your theme's palette, so it fits in.

```lua
ModMenu.Init({
    theme = "slate",
    style = { button = "neon" },
})
```

Add `from` to borrow a type and change some of its fields in the same table:

```lua
ModMenu.Init({
    theme = "slate",
    style = { button = { from = "neon", radius = 4 } },
})
```

This mix borrows five types from four presets over Slate:

```lua
ModMenu.Init({
    theme = "slate",
    style = {
        title = "glass",
        button = "neon",
        toggle = "cozy",
        choice = "cozy",
        progress = "doppler",
    },
})
```

### Changing fields

Set a type to a table to change some of its fields and keep the rest:

```lua
ModMenu.Init({
    theme = "storm",
    style = { toggle = { trackOn = "#22F1FF" } },
})
```

A colour is a hex string in sRGB, `"#RRGGBB"` or `"#RRGGBBAA"`, or a table `{ R, G, B, A }` in linear values as before.

### Changing the palette

`style.palette` replaces colours in the theme's palette before anything else is worked out from it. Every part that takes its colour from the palette follows.

```lua
ModMenu.Init({
    theme = "slate",
    style = { palette = { accent = "#FF7A1A", accentText = "#1A1A1A" } },
})
```

The palette keys are `bg`, `text`, `muted`, `accent`, `accentText`, `danger`, `dangerText`, `surface`, `line`, `track`, `secondaryText`, `success`, `warning` and `info`.

### Styling one item

Give an item a `look` table to change its object type's fields for that item only. An unknown field makes `Register` raise an error that names the section, the item's position and the field, such as `Register(Cheats) items[2].look: button.glow is not a known field`.

```lua
{ type = "button", id = "heal", label = "Heal", look = { radius = 0 } }
```

A `label` item reads the `body` type, a `checkbox` reads `toggle`, and every other item reads the type in the table above. `row`, `fold` and `separator` items take no `look`.

`pill` wins over `radius`. On a theme whose buttons are pills, such as `neon`, a square button needs both fields:

```lua
{ type = "button", id = "heal", label = "Heal", look = { radius = 0, pill = false } }
```

### Game fonts

Some presets name game fonts by id, such as `kanit`, `vcr`, `inconsolata` and `lekton`. The library knows only `roboto` and `mono` by itself, so you pass the object path of each game font in `fonts`:

```lua
local FONT_DIR = "/Game/StormEscape/UI/Foundation/Fonts/"

ModMenu.Init({
    theme = "loadout",
    fonts = {
        kanit = FONT_DIR .. "Kanit/Kanit.Kanit",
        vcr = FONT_DIR .. "vcr_osd_mono.vcr_osd_mono",
        inconsolata = FONT_DIR .. "Inconsolata.Inconsolata",
        lekton = FONT_DIR .. "Lekton.Lekton",
    },
})
```

These paths are Funnel Runners assets. A font that does not load is skipped for the next font in the chain, and every chain ends in Roboto, so text always draws. The library logs each missing path once per session. When a preset names a font id that has no path in `fonts`, the library logs `font id <id> has no path; add it to Init's fonts option` once and uses the next font in the chain. A text style's `font` field takes one id or a list of ids, such as `style = { title = { font = { "kanit", "roboto" } } }`.

### Light, dark and colors

`light` and `dark` draw the same widgets in the same colours as before, and `colors` works as before. A `colors` token is applied after the theme and `style`, with any theme, so `colors = { panelBg = ... }` still sets the panel fill. The token list is under **Theming & polish** below.

### Changing the theme later

A later `Init` merges its `style` over the earlier `style`, and its `fonts` over the earlier `fonts`. When a later `Init` changes `theme`, `style`, `colors` or `fonts`, the library tears the menu down and builds it again in the new look. If the menu is open, it reopens at once; if it is closed, the new look shows on the next open. An `Init` that changes none of these keeps the menu as it is. After each build the log has one line like this, with the counts and the build time in milliseconds:

```text
[ModMenu] built theme=slate items=62 widgets=840 ms=120
```

### Adding or editing a preset

Each preset is a JSON file in `themes/presets/<id>.json`. The library and the builder read generated copies, so after you change a file, run the generator:

```sh
node tools/gen-themes.mjs
```

It writes `core/presets.lua`, `core/stylefields.lua` and the builder's generated theme files. `node tools/gen-themes.mjs --check` writes nothing; it exits 1 and names each generated file that no longer matches the JSON.

---

## Theming & polish

Author-facing (set once in `Init`). Players do not pick a theme.

```lua
ModMenu.Init({
    title = "My Cheats",
    theme = "dark", -- or "light" (default — current look)
    -- colors = {
    --     textAccent = { R = 0.12, G = 0.72, B = 0.70, A = 1.0 },
    -- },
})
```

| Preset | Look |
|--------|------|
| `light` | Current ModMenu: navy panel, mid-blue buttons, light editable fields |
| `dark` | Charcoal panel, thin edge, dark fields, teal (`textAccent`) + gold (`textStatus`) |

`textAccent` / `textStatus` remain for tabs/status. Button variants use their own `buttonBg*` / `buttonText*` tokens (Bootstrap-like primary/danger/warning). Confirm uses `overlayDim` + `confirmCardBg` + `confirmDivider`. The card is content-sized (not panel-tall).

Button hover and pressed fills are optional tokens that no preset sets. When a token is not set, the hover fill is the variant's fill moved 12% toward white and the pressed fill is the same fill moved 12% toward black. Set a token in `colors` to choose the colour yourself.

| Variant | Fill | Hover token | Pressed token |
|---------|------|-------------|---------------|
| `default` | `buttonBg` | `buttonHover` | `buttonPressed` |
| `primary` | `buttonBgPrimary` | `buttonPrimaryHover` | `buttonPrimaryPressed` |
| `secondary` | `buttonBgSecondary` | `buttonSecondaryHover` | `buttonSecondaryPressed` |
| `success` | `buttonBgSuccess` | `buttonSuccessHover` | `buttonSuccessPressed` |
| `danger` | `buttonBgDanger` | `buttonDangerHover` | `buttonDangerPressed` |
| `warning` | `buttonBgWarning` | `buttonWarningHover` | `buttonWarningPressed` |
| `info` | `buttonBgInfo` | `buttonInfoHover` | `buttonInfoPressed` |

```lua
ModMenu.Init({
    theme = "dark",
    colors = {
        buttonPrimaryHover = { R = 0.20, G = 0.48, B = 0.92, A = 1.0 },
    },
})
```

North-star look is the README hero shots (`ModMenuHero.png` / `ModMenuHero2.png`). `light` and `dark` draw flat colours; the other presets add rounded corners, outlines, blur, gradients, bevels and window frames (see **Themes and styles**). 2-column grids and hover glow are optional leftovers in `vision.md`.

Collapsible sections: `Register({ collapsible = true, collapsed = true })`. Nested groups: `{ type = "fold", id, label, items = { ... } }`. Tabs: `Init({ tabs = { "Cheats", "Give" } })` + `Register({ tab = "Cheats", ... })`.

---

## Minimal standalone host

If you only need one section and no feature files:

```lua
-- Mods/MyCheatMenu/Scripts/main.lua
local ModMenu = require("ModMenu.ModMenu")

ModMenu.Init({
    title = "My Cheats",
    instanceId = "MyCheatMenu",
    key = Key.F7,
    keyHint = "F7",
    dock = "right",
})

ModMenu.Register({
    id = "Cheats",
    title = "Cheats",
    items = {
        {
            type = "button",
            id = "heal",
            label = "Heal",
            onClick = function()
                -- ...
            end,
        },
    },
})
```

Ship `MyCheatMenu/` plus ModMenu from `npm run deploy` (`dist/ModMenu.zip` → extract into `ue4ss/Mods/`). See **Install** above.

A fuller dummy (tabs, every widget, log-only clicks) is `examples/ModMenuHost.lua`. Copy it to `ue4ss/Mods/YourMod/Scripts/main.lua` with an empty `enabled.txt`. Use a different toggle key than any other menu in the same session.

---

## See also

- Install / Nexus zip: [GitHub Releases](https://github.com/mattdavida/ue4ss-ModMenu/releases) (`ModMenu.zip`); local: `npm run deploy`
- CI: `.github/workflows/ci.yml`
- UX / north star: `vision.md`
- Widget registry: `widgets/init.lua`
- Public API facade: `ModMenu.lua`
- Example game host (external): `MortalShell2Mod` (F6, Mortal Shell 2)
- Showcase dummy: `examples/ModMenuHost.lua` (F8 — tabs, widgets, console logs)
