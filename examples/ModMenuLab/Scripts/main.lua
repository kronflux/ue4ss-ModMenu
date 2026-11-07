--[[
  ModMenuLab: a test-only menu with no game function.

  Every control type is registered once, every callback writes what it received, and the
  "Probe widgets" button reads the live UMG buttons back (hover flag, background colour, style
  brush tints) so a colour the engine ignored can be told from a paint that never ran. Lines go
  to UE4SS.log and to ModMenuLab-session.log beside this mod, which survives relaunches.
  The test steps are in the README next to this file.
]]

local okReq, ModMenu = pcall(require, "ModMenu.ModMenu")

local function ModRoot()
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", ""):gsub("\\", "/")
    return src:match("^(.*)/Scripts/") or "."
end

local LOG_PATH = ModRoot() .. "/ModMenuLab-session.log"
local runId = os.date("%Y-%m-%d %H:%M:%S")

local function say(msg)
    local line = "[ModMenuLab] " .. tostring(msg)
    print(line .. "\n")
    local f = io.open(LOG_PATH, "a")
    if f then
        f:write(tostring(os.date("%H:%M:%S")), " ", line, "\n")
        f:close()
    end
end

say("run " .. runId .. " started; log at " .. LOG_PATH)
if not okReq then
    say("ModMenu library not found: " .. tostring(ModMenu))
    return
end

local function fmtColor(c)
    if type(c) ~= "table" and type(c) ~= "userdata" then
        return tostring(c)
    end
    local ok, s = pcall(function()
        return string.format("%.2f,%.2f,%.2f,%.2f", c.R, c.G, c.B, c.A)
    end)
    return ok and s or "unreadable"
end

--- Read every live ModMenu button back from the object array and log its state.
local function ProbeButtons()
    local ok, err = pcall(function()
        local all = FindAllOf("Button") or {}
        local seen = 0
        for _, b in ipairs(all) do
            local name = b:GetFullName()
            if name:find("ModMenu_", 1, true) then
                seen = seen + 1
                local hovered, pressed, bg, tint, drawAs, vis = "?", "?", "?", "?", "?", "?"
                pcall(function() hovered = tostring(b:IsHovered()) end)
                pcall(function() pressed = tostring(b:IsPressed()) end)
                pcall(function() bg = fmtColor(b.BackgroundColor) end)
                pcall(function()
                    local brush = b.WidgetStyle.Hovered
                    tint = fmtColor(brush.TintColor.SpecifiedColor)
                    drawAs = tostring(brush.DrawAs)
                end)
                pcall(function() vis = tostring(b:GetVisibility()) end)
                say(string.format("probe %s hovered=%s pressed=%s bg=%s hoverTint=%s drawAs=%s vis=%s",
                    name:match("([^%.]+)$") or name, hovered, pressed, bg, tint, drawAs, vis))
            end
        end
        say("probe done: " .. seen .. " ModMenu buttons of " .. #all)
    end)
    if not ok then
        say("probe raised: " .. tostring(err))
    end
end

-- Autosave writes through the store, and the store writes Mods/ModMenuLab/config.json once it is initialised.
pcall(ModMenu.ConfigManager.Init, { id = "ModMenuLab" })

-- The lab starts in this theme, and the Theme test section switches from it.
local START_THEME = "dark"

-- These are Funnel Runners font assets, which some presets name as kanit, vcr, inconsolata and lekton.
-- In another game the paths do not exist, so the library draws those presets in Roboto and logs each missing path once.
local FONT_DIR = "/Game/StormEscape/UI/Foundation/Fonts/"
local FONTS = {
    kanit = FONT_DIR .. "Kanit/Kanit.Kanit",
    vcr = FONT_DIR .. "vcr_osd_mono.vcr_osd_mono",
    inconsolata = FONT_DIR .. "Inconsolata.Inconsolata",
    lekton = FONT_DIR .. "Lekton.Lekton",
}

local okInit, initErr = pcall(ModMenu.Init, {
    title = "ModMenuLab",
    instanceId = "ModMenuLab",
    key = Key.F7,
    keyHint = "F7",
    dock = "right",
    theme = START_THEME,
    -- Fonts are merged across Init calls, so the theme switches below do not pass them again.
    fonts = FONTS,
    tabs = { "Theme", "Buttons", "Inputs", "Widgets", "Layout", "Controls", "Multi", "Windows" },
    consoleCommand = "modmenulab",
    ignoreLook = true,
    autosave = true,
    debug = true,
})
if not okInit then
    say("Init raised: " .. tostring(initErr))
    return
end
say("Init ok; F7 or `modmenulab` opens the lab")

-- A table value, such as a multiselect array or a colour, is written out so the log shows what it holds.
local function describe(v)
    if type(v) ~= "table" then
        return tostring(v)
    end
    local parts = {}
    for key, value in pairs(v) do
        parts[#parts + 1] = tostring(key) .. "=" .. describe(value)
    end
    table.sort(parts)
    return "{" .. table.concat(parts, ",") .. "}"
end

local function report(id)
    return function(v)
        say(id .. " -> " .. describe(v))
    end
end

local function reg(section)
    local ok, err = pcall(ModMenu.Register, section)
    say(string.format("Register %s: %s", section.id, ok and "ok" or ("raised " .. tostring(err))))
end

-- Theme test: every switch calls Init with the new theme, and the library tears the shell down and builds it again.
-- The menu stays open through the rebuild, so Next theme can be clicked through every preset.
local themeIds = ModMenu.Themes()
local themeIndex = 1
for i, id in ipairs(themeIds) do
    if id == START_THEME then
        themeIndex = i
    end
end

-- The theme Init runs on the next game-thread tick, so the shell is not torn down inside the click handler that
-- asked for it. The menu is still open when Init runs, so the rebuild-while-open path (AC-9) is still exercised.
-- One function held by this file-level local is reused for every switch, because UE4SS keeps only a registry
-- reference to a delayed callback and a collected closure breaks the Lua tick hook.
local pendingThemeId = nil
local function runPendingTheme()
    local id = pendingThemeId
    pendingThemeId = nil
    if id == nil then
        return
    end
    local ok, err = pcall(ModMenu.Init, { theme = id })
    if not ok then
        say("theme " .. id .. " Init raised: " .. tostring(err))
    end
end

local function applyTheme(index)
    -- Lua's % is floored, so index 0 wraps to the last preset and index count + 1 wraps to the first.
    themeIndex = ((index - 1) % #themeIds) + 1
    local id = themeIds[themeIndex]
    -- The dropdown's value is stored before the rebuild, so the new shell shows the theme it is drawn in.
    pcall(ModMenu.Set, "LabTheme", "theme_pick", id)
    say("theme -> " .. id)
    -- Two clicks within one tick queue one Init, for the later theme.
    local queued = pendingThemeId ~= nil
    pendingThemeId = id
    if not queued then
        local ok, err = pcall(ExecuteInGameThreadWithDelay, 1, runPendingTheme)
        if not ok then
            pendingThemeId = nil
            say("theme " .. id .. " could not be queued: " .. tostring(err))
        end
    end
end

local function pickTheme(id)
    -- The dropdown has stored the value before this runs, so the local index is the record of the theme on screen.
    if id == themeIds[themeIndex] then
        return
    end
    for i, known in ipairs(themeIds) do
        if known == id then
            applyTheme(i)
            return
        end
    end
    say("theme pick ignored: unknown id " .. tostring(id))
end

reg({
    id = "LabTheme", title = "Theme test", tab = "Theme",
    description = "Each choice rebuilds the menu in that preset. Watch the log for a built theme line per switch.",
    items = {
        { type = "dropdown", id = "theme_pick", label = "Theme", options = themeIds, default = START_THEME,
          onChange = pickTheme },
        { type = "row", items = {
            { type = "button", id = "theme_prev", label = "Previous theme", onClick = function()
                applyTheme(themeIndex - 1)
            end },
            { type = "button", id = "theme_next", label = "Next theme", variant = "primary", onClick = function()
                applyTheme(themeIndex + 1)
            end },
        } },
        -- A danger button shows the danger-click shake. It logs one line and changes nothing else.
        { type = "button", id = "theme_shake", label = "Shake test", variant = "danger", onClick = function()
            say("shake test")
        end },
    },
})
-- Autosave restores the dropdown's last value, but Init above drew START_THEME, so the dropdown is set back to match.
pcall(ModMenu.Set, "LabTheme", "theme_pick", START_THEME)

reg({
    id = "LabButtons", title = "Button variants", tab = "Buttons",
    items = {
        { type = "button", id = "b_default", label = "default", onClick = report("b_default") },
        { type = "button", id = "b_primary", label = "primary", variant = "primary", onClick = report("b_primary") },
        { type = "button", id = "b_secondary", label = "secondary", variant = "secondary", onClick = report("b_secondary") },
        { type = "button", id = "b_success", label = "success", variant = "success", onClick = report("b_success") },
        { type = "button", id = "b_danger", label = "danger", variant = "danger", onClick = report("b_danger") },
        { type = "button", id = "b_warning", label = "warning", variant = "warning", onClick = report("b_warning") },
        { type = "button", id = "b_info", label = "info", variant = "info", onClick = report("b_info") },
        { type = "button", id = "b_active", label = "active", active = true, onClick = report("b_active") },
        { type = "button", id = "b_disabled", label = "disabled", enabled = false, onClick = report("b_disabled") },
        { type = "button", id = "b_confirm", label = "confirm", variant = "danger",
          confirm = { title = "Lab", message = "Confirm fires onClick?" }, onClick = report("b_confirm") },
        { type = "button", id = "b_tip", label = "with tooltip", tooltip = "Tooltip text. Should be readable and near the pointer.", onClick = report("b_tip") },
        { type = "separator" },
        { type = "button", id = "b_probe", label = "Probe widgets", variant = "info", onClick = ProbeButtons },
    },
})

reg({
    id = "LabInputs", title = "Inputs", tab = "Inputs",
    items = {
        { type = "label", id = "l_1", label = "A label. Below: checkbox, number, text, dropdown." },
        { type = "checkbox", id = "c_1", label = "Checkbox", default = false, onChange = report("c_1") },
        { type = "number", id = "n_1", label = "Number", default = 10, min = 0, max = 100, step = 1, onChange = report("n_1") },
        { type = "textinput", id = "t_1", label = "Text", default = "hello", onChange = report("t_1") },
        { type = "dropdown", id = "d_1", label = "Dropdown", options = { "one", "two", "three" }, default = "one", onChange = report("d_1") },
    },
})

reg({
    id = "LabWidgets", title = "Milestone B widgets", tab = "Widgets",
    items = {
        { type = "slider", id = "s_1", label = "Slider", tooltip = "Steps of 5.",
          min = 0, max = 200, step = 5, default = 100, integer = true, format = "%d%%", onChange = report("s_1") },
        { type = "radio", id = "r_1", label = "Radio inline", options = { "Stand", "Crouch", "Prone" }, default = "Stand", inline = true, onChange = report("r_1") },
        { type = "radio", id = "r_2", label = "Radio stacked", options = { "A", "B" }, default = "A", onChange = report("r_2") },
        { type = "keybind", id = "k_1", label = "Keybind", default = "F5", allowModifiers = true, onChange = report("k_1") },
    },
})

reg({
    id = "LabLayout", title = "Row and fold", tab = "Layout", collapsible = true,
    items = {
        { type = "row", id = "row_1", items = {
            { type = "button", id = "row_btn", label = "row button", onClick = report("row_btn") },
            { type = "checkbox", id = "row_chk", label = "row check", default = true, onChange = report("row_chk") },
            { type = "slider", id = "row_sl", label = "row slider", min = 0, max = 10, step = 1, default = 5, onChange = report("row_sl") },
        } },
        { type = "fold", id = "fold_1", label = "Fold", items = {
            { type = "radio", id = "fold_r", label = "fold radio", options = { "x", "y" }, default = "x", onChange = report("fold_r") },
            { type = "keybind", id = "fold_k", label = "fold key", default = "F9", onChange = report("fold_k") },
        } },
    },
})

reg({
    id = "LabStyle", title = "Presentation", prefix = "[C]", tab = "Inputs",
    description = "This line is the section description, under a title that starts with a prefix.",
    items = {
        { type = "label", label = "Heading style", style = "heading" },
        { type = "label", label = "Muted style, in the muted text colour.", style = "muted" },
        { type = "label", label = "Warning style, in the status colour.", style = "warning" },
        { type = "label", label = "Centred label", align = "center" },
        { type = "label", label = "Right-aligned label", align = "right" },
        { type = "label", label = "A long label with wrap off stays on one line and runs past the panel edge when it is long enough", wrap = false },
        { type = "number", id = "n_step", label = "Stepper", default = 20, min = 0, max = 100, step = 5, integer = true,
          prefix = "$", suffix = "ms", onChange = report("n_step") },
        { type = "slider", id = "s_noval", label = "No readout", min = 0, max = 10, step = 1, default = 4, integer = true,
          showValue = false, onChange = report("s_noval") },
        { type = "slider", id = "s_wide", label = "Label column 220 wide", min = 0, max = 10, step = 1, default = 6, integer = true,
          labelWidth = 220, onChange = report("s_wide") },
    },
})

-- The Controls tab holds the stepper, the progress bar and the colour picker. The multiselect has its own
-- tab, so a failure when it is built cannot hide the rest: open the Multi tab last.
local function bump(delta)
    return function()
        local now = tonumber(ModMenu.Get("LabControls", "pr_1")) or 0
        local found = ModMenu.SetValue("LabControls", "pr_1", now + delta)
        say(string.format("pr_1 SetValue %+.2f -> %s found=%s", delta, tostring(ModMenu.Get("LabControls", "pr_1")), tostring(found)))
    end
end

reg({
    id = "LabControls", title = "Stepper, progress and colour", tab = "Controls",
    items = {
        { type = "stepper", id = "st_1", label = "Stepper 0 to 20 by 2", min = 0, max = 20, step = 2, default = 4,
          integer = true, onChange = report("st_1") },
        { type = "stepper", id = "st_2", label = "Stepper 0 to 1 by 0.1", min = 0, max = 1, step = 0.1, default = 0.5,
          format = "%.1f", onChange = report("st_2") },
        { type = "row", items = {
            { type = "stepper", id = "st_row", label = "In a row", min = 0, max = 5, default = 2, onChange = report("st_row") },
            { type = "button", id = "st_btn", label = "row button", onClick = report("st_btn") },
        } },
        { type = "separator" },
        { type = "progress", id = "pr_1", label = "Progress", default = 0.25, variant = "success" },
        { type = "progress", id = "pr_2", label = "Custom readout", min = 0, max = 200, default = 50, variant = "danger",
          format = function(v) return string.format("%d of 200", v) end },
        { type = "button", id = "pr_up", label = "Progress +0.1", variant = "info", onClick = bump(0.1) },
        { type = "button", id = "pr_down", label = "Progress -0.1", variant = "info", onClick = bump(-0.1) },
        { type = "button", id = "pr_label", label = "Rename progress label", variant = "info", onClick = function()
            local found = ModMenu.SetLabel("LabControls", "pr_1", "Renamed " .. os.date("%H:%M:%S"))
            say("pr_1 SetLabel found=" .. tostring(found))
        end },
        { type = "fold", id = "col_fold", label = "Colour pickers", collapsed = false, items = {
            { type = "colorpicker", id = "cp_1", label = "Colour with alpha", default = { R = 0.2, G = 0.5, B = 0.8, A = 1 },
              onChange = report("cp_1") },
            { type = "colorpicker", id = "cp_2", label = "Colour without alpha", alpha = false,
              default = { R = 0.9, G = 0.4, B = 0.1, A = 1 }, onChange = report("cp_2") },
        } },
    },
})

reg({
    id = "LabMulti", title = "Multiselect (open this tab last)", tab = "Multi",
    items = {
        { type = "fold", id = "ms_fold", label = "Two columns", collapsed = false, items = {
            { type = "multiselect", id = "ms_1", label = "Tags", columns = 2,
              options = { "Alpha", "Beta", "Gamma", "Delta", { label = "Epsilon", value = "e" } },
              default = { "Beta" }, onChange = report("ms_1") },
            { type = "multiselect", id = "ms_2", label = "One column", options = { "Red", "Green", "Blue" },
              onChange = report("ms_2") },
        } },
    },
})

-- The Windows tab holds one of each control the Windows presets restyle, then a list long enough
-- that the panel scrollbar shows. The tab strip itself shows the tab look.
local windowsItems = {
    { type = "checkbox", id = "w_chk_off", label = "Check box, off", default = false, onChange = report("w_chk_off") },
    { type = "checkbox", id = "w_chk_on", label = "Check box, on", default = true, onChange = report("w_chk_on") },
    { type = "radio", id = "w_radio", label = "Radio buttons", options = { "First", "Second", "Third" },
      default = "First", onChange = report("w_radio") },
    { type = "slider", id = "w_slider", label = "Slider with ticks", min = 0, max = 100, step = 10, default = 50,
      integer = true, onChange = report("w_slider") },
    { type = "dropdown", id = "w_drop", label = "Dropdown", options = { "Alpha", "Beta", "Gamma", "Delta" },
      default = "Alpha", onChange = report("w_drop") },
    { type = "number", id = "w_num", label = "Number with step 5", default = 20, min = 0, max = 100, step = 5,
      integer = true, onChange = report("w_num") },
    { type = "stepper", id = "w_step", label = "Stepper", min = 0, max = 10, step = 1, default = 3,
      integer = true, onChange = report("w_step") },
    { type = "progress", id = "w_prog", label = "Progress", default = 0.6 },
    { type = "separator" },
}
for i = 1, 30 do
    windowsItems[#windowsItems + 1] = { type = "label", label = string.format("Scroll filler line %02d", i) }
end
windowsItems[#windowsItems + 1] = { type = "button", id = "w_last", label = "Last item", onClick = report("w_last") }

reg({
    id = "LabWindows", title = "Windows controls", tab = "Windows",
    description = "One of each control the Windows presets restyle, then a list long enough to show the scrollbar.",
    items = windowsItems,
})

-- enabled and visible: each toggle button flips one flag and logs the new value.
local labState = { targetEnabled = true, sliderVisible = false, foldEnabled = true, foldVisible = true }
local function toggle(key, apply, sectionId, itemId)
    return function()
        labState[key] = not labState[key]
        local found = apply(sectionId, itemId, labState[key])
        say(string.format("%s -> %s found=%s", key, tostring(labState[key]), tostring(found)))
    end
end

reg({
    id = "LabState", title = "Enabled and visible", tab = "Layout",
    items = {
        { type = "button", id = "t_target", label = "Target button", onClick = report("t_target") },
        { type = "button", id = "t_toggleEnabled", label = "Toggle target enabled", variant = "info",
          onClick = toggle("targetEnabled", ModMenu.SetEnabled, "LabState", "t_target") },
        { type = "slider", id = "t_slider", label = "Hidden slider", min = 0, max = 10, step = 1, default = 3,
          integer = true, visible = false, onChange = report("t_slider") },
        { type = "button", id = "t_toggleVisible", label = "Toggle slider visible", variant = "info",
          onClick = toggle("sliderVisible", ModMenu.SetVisible, "LabState", "t_slider") },
        { type = "fold", id = "t_fold", label = "State fold", collapsed = false, items = {
            { type = "button", id = "t_inner", label = "Inner button", onClick = report("t_inner") },
            { type = "slider", id = "t_innerSlider", label = "Inner slider", min = 0, max = 10, step = 1, default = 5,
              integer = true, onChange = report("t_innerSlider") },
        } },
        { type = "button", id = "t_toggleFoldEnabled", label = "Toggle fold enabled", variant = "info",
          onClick = toggle("foldEnabled", ModMenu.SetEnabled, "LabState", "t_fold") },
        { type = "button", id = "t_toggleFoldVisible", label = "Toggle fold visible", variant = "info",
          onClick = toggle("foldVisible", ModMenu.SetVisible, "LabState", "t_fold") },
    },
})

pcall(RegisterConsoleCommandHandler, "labprobe", function()
    ProbeButtons()
    return true
end)
say("ready; `labprobe` reads the live buttons back")
