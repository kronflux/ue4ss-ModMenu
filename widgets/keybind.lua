--[[
  ModMenu widget: keybind

  The value is an FKey name string such as "F7", or "LeftControl+F7" when modifiers are held.
  An empty string means the item has no binding.

  A button shows the binding. A click starts capture and the button shows "Press a key".
  While capturing, poll reads every name in Keybind.CAPTURE_KEYS with IsInputKeyDown every
  SCAN_MS, the same 50 ms rate the engine input backend uses, because a one-frame
  WasInputKeyJustPressed is missed at that rate and a rising edge of the held state is not.
  The first scan only records which keys are already held, so a key held before the click is
  not captured. The first non-modifier key that goes down is stored, with the held modifiers
  in front of it when allowModifiers is true. Escape or a second click cancels the capture.

  A binding already held by another keybind item in the same menu calls
  item.onConflict(otherId, value, otherSectionId). The new binding is refused unless that
  call returns true, and an item without onConflict always refuses it.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local PaintLib = require("ModMenu.core.paint")
local Button = require("ModMenu.widgets.button")

local Keybind = {}
Keybind.type = "keybind"

local SCAN_MS = 50
local CANCEL_KEY = "Escape"
local CAPTURE_PROMPT = "Press a key"
local UNBOUND_TEXT = "None"

--- The clock in seconds that paces the capture scan. This is a module field so that a spec can replace it with a fake clock.
Keybind._clock = os.clock

--- Modifier names in the order they are written in front of a key, so one chord always
--- produces the same string and two items holding it compare equal.
Keybind.MODIFIERS = { "LeftControl", "RightControl", "LeftAlt", "RightAlt", "LeftShift", "RightShift" }

local MODIFIER_RANK = {}
for i, name in ipairs(Keybind.MODIFIERS) do
    MODIFIER_RANK[name] = i
end

--- The key names scanned during capture, as Unreal FKey names.
--- Digits use the engine's word names, because the FKey for the 1 key is "One", not "1".
Keybind.CAPTURE_KEYS = {}
for code = string.byte("A"), string.byte("Z") do
    table.insert(Keybind.CAPTURE_KEYS, string.char(code))
end
for _, name in ipairs({ "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }) do
    table.insert(Keybind.CAPTURE_KEYS, name)
end
for n = 1, 12 do
    table.insert(Keybind.CAPTURE_KEYS, "F" .. n)
end
for _, name in ipairs({ "Up", "Down", "Left", "Right" }) do
    table.insert(Keybind.CAPTURE_KEYS, name)
end
for _, name in ipairs(Keybind.MODIFIERS) do
    table.insert(Keybind.CAPTURE_KEYS, name)
end

local DEFAULT_HELP = 'an FKey name string such as "F7" or "LeftControl+F7"'

--- Split a binding into its modifiers and its key.
--- Returns nil for a value that is not a non-empty string, has an empty part, names a modifier
--- that is not in Keybind.MODIFIERS, repeats a modifier, or ends in a modifier.
---@param value any
---@return { mods: string[], key: string }|nil
function Keybind._parse(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    local parts = {}
    for part in string.gmatch(value .. "+", "([^+]*)%+") do
        if part == "" then
            return nil
        end
        table.insert(parts, part)
    end
    local key = table.remove(parts)
    if key == nil or MODIFIER_RANK[key] ~= nil then
        return nil
    end
    local seen = {}
    for _, mod in ipairs(parts) do
        if MODIFIER_RANK[mod] == nil or seen[mod] then
            return nil
        end
        seen[mod] = true
    end
    return { mods = parts, key = key }
end

--- The binding with its modifiers in Keybind.MODIFIERS order, or nil when it does not parse.
--- Two bindings that differ only in modifier order are the same chord.
local function Canonical(value)
    local parsed = Keybind._parse(value)
    if parsed == nil then
        return nil
    end
    local mods = {}
    for i, mod in ipairs(parsed.mods) do
        mods[i] = mod
    end
    table.sort(mods, function(a, b)
        return MODIFIER_RANK[a] < MODIFIER_RANK[b]
    end)
    table.insert(mods, parsed.key)
    return table.concat(mods, "+")
end

local function FindHolder(items, sectionId, itemId, values, want, ownSectionId)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            if item.type == "keybind" and item.id ~= nil
                and not (sectionId == ownSectionId and item.id == itemId)
            then
                if Canonical(values[Util.ValueKey(sectionId, item.id)]) == want then
                    return item.id
                end
            end
            if (item.type == "row" or item.type == "fold") and type(item.items) == "table" then
                local found = FindHolder(item.items, sectionId, itemId, values, want, ownSectionId)
                if found ~= nil then
                    return found
                end
            end
        end
    end
    return nil
end

--- Find another keybind item that already holds this binding.
--- sections has the registry's shape, a list of { id, items }, and rows and folds are searched
--- at any depth. The item itself is skipped, and an empty or unparsable binding never conflicts.
---@return string|nil otherItemId
---@return string|nil otherSectionId
function Keybind._conflict(values, sectionId, itemId, value, sections)
    local want = Canonical(value)
    if want == nil then
        return nil
    end
    for _, section in ipairs(sections or {}) do
        local found = FindHolder(section.items, section.id, itemId, values, want, sectionId)
        if found ~= nil then
            return found, section.id
        end
    end
    return nil
end

--- The registered sections of this shell, which the widget ctx carries.
--- A conflict is checked against these, including sections on a tab that is not built, and never
--- against another shell's sections.
local function SectionsFor(ctx)
    if ctx ~= nil and type(ctx.sections) == "table" then
        return ctx.sections
    end
    return {}
end

function Keybind.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.default ~= nil and (type(item.default) ~= "string"
        or (item.default ~= "" and Keybind._parse(item.default) == nil))
    then
        error(prefix .. " default must be " .. DEFAULT_HELP)
    end
    if item.allowModifiers ~= nil and type(item.allowModifiers) ~= "boolean" then
        error(prefix .. " allowModifiers must be a boolean")
    end
    if item.onConflict ~= nil and type(item.onConflict) ~= "function" then
        error(prefix .. " onConflict must be a function")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
end

local function DefaultValue(item)
    return item.default or ""
end

--- A value set before Register that is not a binding is replaced by the default here,
--- as the number widget does, so the store only ever holds a binding or "".
function Keybind.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = Util.ValueKey(sectionId, item.id)
    local current = values[vkey]
    if current == nil or (current ~= "" and Keybind._parse(current) == nil) then
        values[vkey] = DefaultValue(item)
    end
end

local function Caption(item, value, capturing)
    local shown
    if capturing then
        shown = CAPTURE_PROMPT
    elseif type(value) == "string" and value ~= "" then
        shown = value
    else
        shown = UNBOUND_TEXT
    end
    return string.format("%s: %s", tostring(item.label), shown)
end

--- The text colour of a themed keybind: the accent while it captures, the field text otherwise.
---@param themed table { field, accent }
---@param capturing boolean
---@return table
function Keybind._textColor(themed, capturing)
    if capturing then
        return themed.accent
    end
    return themed.field.text
end

--- Paint the button as active while it captures, so the player sees which item is listening.
local function Paint(ctrl, ctx)
    local caption = Caption(ctrl.item, ctx.values[ctrl.valueKey], ctrl.capturing)
    local themed = ctrl.themed
    if themed ~= nil then
        -- A themed keybind shows capture by its caption and text colour alone, so no shape is
        -- recoloured at run time (field note 30).
        ctx.umg.SetLabelText(ctrl.labelWidget, PaintLib.Caption(caption, themed.textSpec))
        local color = Keybind._textColor(themed, ctrl.capturing == true)
        pcall(function()
            ctrl.labelWidget:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
        end)
        return
    end
    ctx.umg.SetLabelText(ctrl.labelWidget, caption)
    -- The paint table is kept, because it holds the fill colours the pointer poll repaints from.
    ctrl.paint = ctrl.paint or {
        kind = "keybind",
        widget = ctrl.widget,
        fill = ctrl.fill,
        labelWidget = ctrl.labelWidget,
    }
    ctrl.paint.item = { active = ctrl.capturing == true, enabled = true, variant = "default" }
    Button.applyChrome(ctrl.paint, ctx)
end

function Keybind.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    if ctx.values[vkey] == nil then
        ctx.values[vkey] = DefaultValue(item)
    end
    local field, textSpec, fontSize = Umg.FieldLook(ctx.config, item.look)
    local fill, button, label, root
    local themed = nil
    if field ~= nil then
        -- The binding sits in a field frame; the edge is its own Border because a Button's state
        -- brush did not draw an outline (field note 31).
        local paint = PaintLib.StateButton(ctx.contentBox, ctx.namePrefix, {
            normal = { fill = field.fill, radius = field.radius, pill = field.pill },
            edge = { outline = field.outline, width = field.width },
        }, Caption(item, ctx.values[vkey], false), {
            color = field.text,
            size = fontSize,
            textSpec = textSpec,
            pad = { 10, 4, 10, 4 },
        })
        root, button, label = paint.root, paint.widget, paint.label
        -- The bevel goes around the whole field frame and takes no clicks itself.
        root = PaintLib.Bevelled(ctx.contentBox, ctx.namePrefix .. "_FieldBevel", root, field.bevel, true)
        themed = { paint = paint, field = field, textSpec = textSpec, accent = ctx.config.resolved.palette.accent }
    else
        fill, button, label = umg.CreateFilledButton(
            ctx.contentBox,
            ctx.namePrefix,
            Caption(item, ctx.values[vkey], false)
        )
        root = fill
    end
    umg.AddToContent(ctx, root)
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
    local ctrl = {
        kind = "keybind",
        sectionId = ctx.section.id,
        item = item,
        widget = button,
        fill = fill,
        labelWidget = label,
        valueKey = vkey,
        wasPressed = false,
        capturing = false,
        themed = themed,
        -- Keyboard and gamepad focus is not built yet; the stubs keep the control contract.
        focus = {
            enter = function() end,
            leave = function() end,
            activate = function() end,
        },
    }
    Paint(ctrl, ctx)
    table.insert(ctx.liveControls, ctrl)
end

-- Start and stop are logged under debug, so the log can tell a capture that ended at once from
-- one that never read a key.
local function StopCapture(ctrl, ctx)
    if ctrl.capturing then
        Util.Debug(string.format("keybind %s capture stop", tostring(ctrl.item and ctrl.item.id)))
    end
    ctrl.capturing = false
    ctrl.prevDown = nil
    Paint(ctrl, ctx)
end

local function StartCapture(ctrl, ctx)
    -- Only one item listens at a time, so a key press cannot bind two items at once.
    for _, other in ipairs(ctx.liveControls) do
        if other ~= ctrl and other.kind == "keybind" and other.capturing then
            StopCapture(other, ctx)
        end
    end
    ctrl.capturing = true
    ctrl.prevDown = nil
    ctrl.nextScanAt = nil
    Util.Debug(string.format("keybind %s capture start", tostring(ctrl.item and ctrl.item.id)))
    Paint(ctrl, ctx)
end

--- A click toggles capture. Shared by the IsPressed poll and the LMB-latch pollClick.
local function FireClick(ctrl, ctx, path)
    ctx.Input.DebugClick(path, ctrl, ctrl.widget)
    ctx.Input.SuppressPressEdge(ctrl)
    if ctrl.capturing then
        StopCapture(ctrl, ctx)
    else
        StartCapture(ctrl, ctx)
    end
    ctx.ReclaimMenuInput()
    ctx.Input.IgnoreClicks(2)
    return true
end

-- Key lookup uses ctx.Input.MakeFKey and ctx.Input.IsKeyDown from core/input.lua, so the widget
-- reads keys the same way as the engine toggle backend. Each FKey is made once and cached.
local fkeyCache = {} ---@type table<string, table|false>

local function LoadHelpers()
    local ok, helpers = pcall(require, "UEHelpers.UEHelpers")
    if ok then
        return helpers
    end
    return nil
end

local function MakeFKey(ctx, name)
    local cached = fkeyCache[name]
    if cached ~= nil then
        return cached or nil
    end
    local ok, fkey = pcall(ctx.Input.MakeFKey, name)
    if not ok then
        fkey = nil
    end
    fkeyCache[name] = fkey or false
    return fkey
end

--- The menu's toggle key as an FKey name, which capture never binds, because pressing it closes the menu.
local function ToggleKeyName(ctx)
    local config = ctx.config
    if type(config) == "table" and type(config.keyName) == "string" then
        return config.keyName
    end
    return nil
end

--- Store a captured binding unless another item holds it and onConflict does not return true.
local function Commit(ctrl, ctx, value)
    local item = ctrl.item
    if value ~= ctx.values[ctrl.valueKey] then
        local otherId, otherSectionId = Keybind._conflict(
            ctx.values,
            ctrl.sectionId,
            item.id,
            value,
            SectionsFor(ctx)
        )
        if otherId ~= nil then
            local allowed = false
            if type(item.onConflict) == "function" then
                local ok, result = pcall(item.onConflict, otherId, value, otherSectionId)
                if not ok then
                    Util.Log("callback error: " .. tostring(result))
                end
                allowed = ok and result == true
            end
            if not allowed then
                Util.Debug(string.format(
                    "keybind %s.%s refused %s, held by %s.%s",
                    tostring(ctrl.sectionId),
                    tostring(item.id),
                    value,
                    tostring(otherSectionId),
                    tostring(otherId)
                ))
                StopCapture(ctrl, ctx)
                return
            end
        end
        ctx.values[ctrl.valueKey] = value
        StopCapture(ctrl, ctx)
        ctx.SafeCall(item.onChange, value)
        return
    end
    StopCapture(ctrl, ctx)
end

--- One capture scan. Records each key's held state and acts on the keys that went down since
--- the last scan; the first scan after the click only records.
local function Scan(ctrl, ctx)
    local now = Keybind._clock() * 1000
    if ctrl.nextScanAt ~= nil and now < ctrl.nextScanAt then
        return
    end
    ctrl.nextScanAt = now + SCAN_MS

    local helpers = LoadHelpers()
    local pc = nil
    if helpers ~= nil then
        pcall(function()
            pc = helpers.GetPlayerController()
        end)
    end
    if not ctx.IsValid(pc) then
        if ctrl.prevDown == nil then
            Util.Debug("keybind scan: no player controller, keys cannot be read")
        end
        return
    end

    local first = ctrl.prevDown == nil
    local prev = ctrl.prevDown or {}
    local down = {}
    local function Read(name)
        local fkey = MakeFKey(ctx, name)
        down[name] = fkey ~= nil and ctx.Input.IsKeyDown(pc, fkey) == true
        return down[name] and not prev[name]
    end

    local cancel = Read(CANCEL_KEY)
    local toggleKey = ToggleKeyName(ctx)
    local pressed = nil
    for _, name in ipairs(Keybind.CAPTURE_KEYS) do
        if Read(name) and pressed == nil and MODIFIER_RANK[name] == nil and name ~= toggleKey then
            pressed = name
        end
    end
    ctrl.prevDown = down
    if first then
        return
    end
    if cancel then
        StopCapture(ctrl, ctx)
        return
    end
    if pressed == nil then
        return
    end
    local parts = {}
    if ctrl.item.allowModifiers == true then
        for _, mod in ipairs(Keybind.MODIFIERS) do
            if down[mod] then
                table.insert(parts, mod)
            end
        end
    end
    table.insert(parts, pressed)
    Commit(ctrl, ctx, table.concat(parts, "+"))
end

function Keybind.poll(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    if ctrl.themed ~= nil then
        PaintLib.TrackPointer(ctrl.themed.paint)
    elseif ctrl.paint ~= nil then
        ctx.umg.TrackPointer(ctrl.paint)
    end
    if ctx.Input.ReleaseClick(ctrl, ctrl.widget) then
        FireClick(ctrl, ctx, "release")
        return
    end
    if ctrl.capturing then
        Scan(ctrl, ctx)
    end
end

--- @return boolean true if click consumed
function Keybind.pollClick(ctrl, ctx)
    local consumed, fireNow = ctx.Input.ArmClick(ctrl, ctrl.widget)
    if fireNow then
        return FireClick(ctrl, ctx, "latch-hover")
    end
    return consumed
end

--- End the capture of every keybind control in ctx.liveControls.
--- The shell calls this when the menu closes, because poll stops then and a capture left on would
--- take the first key pressed after the menu opens again.
function Keybind._stopCapture(ctx)
    for _, ctrl in ipairs(ctx.liveControls or {}) do
        if ctrl.kind == "keybind" and ctrl.capturing then
            ctrl.capturing = false
            ctrl.prevDown = nil
            if ctx.IsValid(ctrl.widget) then
                Paint(ctrl, ctx)
            end
        end
    end
end

--- Set from the host stores the value as given and ends any capture. It never fires onChange
--- and never checks for a conflict, because the host chose the binding.
function Keybind.apply(ctrl, value, ctx)
    if value == nil then
        value = DefaultValue(ctrl.item)
    end
    ctx.values[ctrl.valueKey] = tostring(value)
    ctrl.capturing = false
    ctrl.prevDown = nil
    if ctx.IsValid(ctrl.widget) then
        Paint(ctrl, ctx)
    end
end

return Keybind
