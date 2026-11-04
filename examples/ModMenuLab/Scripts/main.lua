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

local okInit, initErr = pcall(ModMenu.Init, {
    title = "ModMenuLab",
    instanceId = "ModMenuLab",
    key = Key.F7,
    keyHint = "F7",
    dock = "right",
    theme = "dark",
    tabs = { "Buttons", "Inputs", "Widgets", "Layout" },
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

local function report(id)
    return function(v)
        say(id .. " -> " .. tostring(v))
    end
end

local function reg(section)
    local ok, err = pcall(ModMenu.Register, section)
    say(string.format("Register %s: %s", section.id, ok and "ok" or ("raised " .. tostring(err))))
end

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

pcall(RegisterConsoleCommandHandler, "labprobe", function()
    ProbeButtons()
    return true
end)
say("ready; `labprobe` reads the live buttons back")
