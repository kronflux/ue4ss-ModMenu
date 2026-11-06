--[[
  ModMenu.core.style: resolves a theme into one complete style table.

  A theme is a preset id or a definition table. Style.Resolve applies, in this order: the preset or
  definition, its base and parts borrowing, style.palette, the palette defaults and derived fields,
  each style.<type> override, and last the legacy colors table. Every colour in the result is a
  linear { R, G, B, A } table, so widget code never converts a hex string.

  This module touches no UE4SS global, so the spec suite can load it under MoonSharp.
]]

local Fields = require("ModMenu.core.stylefields")
local Presets = require("ModMenu.core.presets")
local Theme = require("ModMenu.core.theme")

local M = {}

local TYPES = Fields.types
local PALETTE = Fields.palette
local TEXT_KINDS = TYPES.title
local ROLE_NAMES = { "default", "primary", "secondary", "success", "danger", "warning", "info", "active", "disabled" }
local ROLE_KINDS = {
    fill = "color",
    text = "color",
    hover = "color",
    pressed = "color",
    edge = "color",
    variant = TYPES.button.variant,
}
local SHADOW_KINDS = { x = "number", y = "number", color = "color" }

-- The stage 2 kinds that are a fixed set of keys. A key may itself hold another stage 2 kind: an xp
-- face holds two stops lists and a frame holds a bevel. Every key is optional, so a borrowed value
-- that kept only a width is still valid.
local FIXED_KINDS = {
    bevel = { light = "color", dark = "color", innerLight = "color", innerDark = "color", width = "number" },
    xpface = { edge = "color", glow = "color", defaultRing = "color", face = "stops", pressedFace = "stops" },
    frame = { edge = "color", fill = "color", radius = "radius", pad = "number", bevel = "bevel" },
    statusbar = { text = "string", fill = "color", line = "color" },
}
-- A faces entry is a map from button role to one of these.
local FACE_KINDS = { fill = "color", text = "color" }
-- Every stage 2 kind. Their validation messages read `<path>: expected <kind>`.
local STAGE2_KINDS = { stops = true, bevel = true, faces = true, xpface = true, frame = true, statusbar = true }

-- Types resolve in this order because some defaults read an earlier type: choice reads button,
-- tabs reads choice, and field, list, stepper and tooltip read button or field.
local TYPE_ORDER = {
    "panel", "header", "title", "body", "hint", "data", "section", "button", "toggle", "slider",
    "progress", "choice", "tabs", "field", "list", "stepper", "tooltip", "confirm", "motion",
}

-- A definition may carry these keys beside its object types.
local DEFINITION_KEYS = {
    id = true, stage = true, name = true, subtitle = true, footer = true, icon = true,
    palette = true, base = true, parts = true,
}

local IsRole = {}
for _, role in ipairs(ROLE_NAMES) do
    IsRole[role] = true
end

local IsPaletteKey = {}
for _, key in ipairs(PALETTE) do
    IsPaletteKey[key] = true
end

------------------------------------------------------------------------------------------
-- Colours
------------------------------------------------------------------------------------------

local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local BLACK = { R = 0, G = 0, B = 0, A = 1 }

-- The same sRGB to linear curve as StyleLab, so a ported preset keeps its colours.
local function Linear(byte)
    local c = byte / 255
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function ParseHex(s)
    if type(s) ~= "string" then
        return nil
    end
    local digits = s:match("^#(%x+)$")
    if digits == nil or (#digits ~= 6 and #digits ~= 8) then
        return nil
    end
    local function Byte(i)
        return tonumber(digits:sub(i, i + 1), 16)
    end
    local alpha = 1
    if #digits == 8 then
        alpha = Byte(7) / 255
    end
    return { R = Linear(Byte(1)), G = Linear(Byte(3)), B = Linear(Byte(5)), A = alpha }
end

--- Convert an sRGB hex string, "#RRGGBB" or "#RRGGBBAA", to a linear colour table.
---@param s string
---@return table
function M.Hex(s)
    local c = ParseHex(s)
    if c == nil then
        error('ModMenu style: malformed colour "' .. tostring(s) .. '"; write "#RRGGBB" or "#RRGGBBAA"', 0)
    end
    return c
end

--- Return a new linear colour from a hex string or a { R, G, B, A } table.
--- A table is copied the way core/theme.lua copies legacy colours, so a missing alpha is 1.
---@param v string|table
---@return table
function M.Color(v)
    if type(v) == "string" then
        return M.Hex(v)
    end
    if type(v) ~= "table" then
        error("ModMenu style: a colour must be a hex string or an { R, G, B, A } table, got " .. type(v), 0)
    end
    return {
        R = tonumber(v.R) or 0,
        G = tonumber(v.G) or 0,
        B = tonumber(v.B) or 0,
        A = tonumber(v.A) or 1,
    }
end

local Color = M.Color

local function Alpha(c, a)
    return { R = c.R, G = c.G, B = c.B, A = a }
end

local function Mix(a, b, t)
    return {
        R = a.R + (b.R - a.R) * t,
        G = a.G + (b.G - a.G) * t,
        B = a.B + (b.B - a.B) * t,
        A = a.A + (b.A - a.A) * t,
    }
end

local function IsColorValue(v)
    if type(v) == "string" then
        return ParseHex(v) ~= nil
    end
    return type(v) == "table" and type(v.R) == "number" and type(v.G) == "number" and type(v.B) == "number"
        and (v.A == nil or type(v.A) == "number")
end

------------------------------------------------------------------------------------------
-- Copying by kind
------------------------------------------------------------------------------------------

local function DeepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local out = {}
    for k, inner in pairs(v) do
        out[k] = DeepCopy(inner)
    end
    return out
end

-- Free-form tables, such as a progress ramp, hold colours that both resolvers must convert, so
-- any hex string or colour table inside one becomes a linear copy.
local function ConvertDeep(v)
    if type(v) == "string" and ParseHex(v) ~= nil then
        return ParseHex(v)
    end
    if type(v) ~= "table" then
        return v
    end
    if type(v.R) == "number" then
        return Color(v)
    end
    local out = {}
    for k, inner in pairs(v) do
        out[k] = ConvertDeep(inner)
    end
    return out
end

local CopyByKind

local function CopyTable(kinds, t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = CopyByKind(kinds[k], v)
    end
    return out
end

-- Return a new value of the given kind with every colour linear. An unknown kind is copied as is.
CopyByKind = function(kind, v)
    if v == nil then
        return nil
    end
    if kind == "color" then
        return Color(v)
    end
    if kind == "text" and type(v) == "table" then
        return CopyTable(TEXT_KINDS, v)
    end
    if kind == "shadow" and type(v) == "table" then
        return CopyTable(SHADOW_KINDS, v)
    end
    if kind == "roles" and type(v) == "table" then
        local out = {}
        for role, entry in pairs(v) do
            out[role] = type(entry) == "table" and CopyTable(ROLE_KINDS, entry) or entry
        end
        return out
    end
    if kind == "stops" and type(v) == "table" then
        local out = {}
        for i = 1, #v do
            out[i] = Color(v[i])
        end
        return out
    end
    if FIXED_KINDS[kind] ~= nil and type(v) == "table" then
        return CopyTable(FIXED_KINDS[kind], v)
    end
    if kind == "faces" and type(v) == "table" then
        local out = {}
        for role, entry in pairs(v) do
            out[role] = type(entry) == "table" and CopyTable(FACE_KINDS, entry) or entry
        end
        return out
    end
    if kind == "table" then
        return ConvertDeep(v)
    end
    return DeepCopy(v)
end

--- A new entry for an object type, with every colour converted and every table copied.
local function Normalize(typeName, entry)
    local kinds = TYPES[typeName] or {}
    local out = {}
    for f, v in pairs(entry or {}) do
        out[f] = CopyByKind(kinds[f], v)
    end
    return out
end

-- A shallow merge of two tables: the keys of base, then the keys of over. Defined here because
-- MergeType and the resolvers below both use it.
local function Merge(base, over)
    local out = {}
    for k, v in pairs(base or {}) do
        out[k] = v
    end
    for k, v in pairs(over or {}) do
        out[k] = v
    end
    return out
end

-- Merge two tables of one fixed-key kind key by key, and a nested fixed-key kind the same way. A
-- stops list replaces whole, because half a gradient has no meaning.
local function MergeFixed(kind, base, over)
    local kinds = FIXED_KINDS[kind]
    local out = {}
    for k, v in pairs(base) do
        out[k] = v
    end
    for k, v in pairs(over) do
        local sub = kinds[k]
        if FIXED_KINDS[sub] ~= nil and type(v) == "table" and type(out[k]) == "table" then
            out[k] = MergeFixed(sub, out[k], v)
        else
            out[k] = v
        end
    end
    return out
end

-- Merge two entries of one type. Roles merge per role and per colour, text tables per key, and the
-- stage 2 kinds per key, because an override names only the parts it changes.
local function MergeType(typeName, base, over)
    local kinds = TYPES[typeName] or {}
    local out = {}
    for f, v in pairs(base or {}) do
        out[f] = v
    end
    for f, v in pairs(over or {}) do
        local kind = kinds[f]
        if kind == "roles" and type(v) == "table" and type(out[f]) == "table" then
            local roles = {}
            for role, entry in pairs(out[f]) do
                roles[role] = entry
            end
            for role, entry in pairs(v) do
                if type(entry) == "table" and type(roles[role]) == "table" then
                    local merged = {}
                    for k, inner in pairs(roles[role]) do
                        merged[k] = inner
                    end
                    for k, inner in pairs(entry) do
                        merged[k] = inner
                    end
                    roles[role] = merged
                else
                    roles[role] = entry
                end
            end
            out[f] = roles
        elseif FIXED_KINDS[kind] ~= nil and type(v) == "table" and type(out[f]) == "table" then
            out[f] = MergeFixed(kind, out[f], v)
        elseif kind == "faces" and type(v) == "table" and type(out[f]) == "table" then
            local faces = {}
            for role, entry in pairs(out[f]) do
                faces[role] = entry
            end
            for role, entry in pairs(v) do
                if type(entry) == "table" and type(faces[role]) == "table" then
                    faces[role] = Merge(faces[role], entry)
                else
                    faces[role] = entry
                end
            end
            out[f] = faces
        elseif kind == "text" and type(v) == "table" and type(out[f]) == "table" then
            local text = {}
            for k, inner in pairs(out[f]) do
                text[k] = inner
            end
            for k, inner in pairs(v) do
                text[k] = inner
            end
            out[f] = text
        else
            out[f] = v
        end
    end
    return out
end

local function WithoutKeys(t, colorKinds)
    local out = {}
    for k, v in pairs(t) do
        if colorKinds[k] ~= "color" then
            out[k] = v
        end
    end
    return out
end

-- The part of a stage 2 value that a borrow keeps, which is only what is not a colour: a bevel keeps
-- its width, a frame its radius, pad and bevel width, and a status bar its text. Stops, faces and
-- xp faces hold nothing else, so nothing is kept. An empty result means the field is dropped.
local function StripKind(kind, v)
    if kind == "bevel" then
        if v.width ~= nil then
            return { width = v.width }
        end
    elseif kind == "statusbar" then
        if v.text ~= nil then
            return { text = v.text }
        end
    elseif kind == "frame" then
        local out = {}
        if v.radius ~= nil then
            out.radius = DeepCopy(v.radius)
        end
        if v.pad ~= nil then
            out.pad = v.pad
        end
        if type(v.bevel) == "table" then
            local bevel = StripKind("bevel", v.bevel)
            if next(bevel) ~= nil then
                out.bevel = bevel
            end
        end
        return out
    end
    return {}
end

--- An entry without its colours, so a borrowed type takes its shape from one preset and its
--- colours from the current palette. Free-form lists such as a ramp or shadow layers are kept,
--- as StyleLab's StripColors keeps them.
local function StripColors(typeName, entry)
    local kinds = TYPES[typeName] or {}
    local out = {}
    for f, v in pairs(entry or {}) do
        local kind = kinds[f]
        if kind == "color" then
            -- A colour field is dropped; the resolver derives it from the palette.
        elseif kind == "roles" and type(v) == "table" then
            local roles = {}
            for role, roleEntry in pairs(v) do
                if type(roleEntry) == "table" then
                    roles[role] = WithoutKeys(roleEntry, ROLE_KINDS)
                end
            end
            out[f] = roles
        elseif kind == "text" and type(v) == "table" then
            out[f] = WithoutKeys(v, TEXT_KINDS)
            if type(v.shadow) == "table" then
                out[f].shadow = WithoutKeys(v.shadow, SHADOW_KINDS)
            end
        elseif kind == "shadow" and type(v) == "table" then
            out[f] = WithoutKeys(v, SHADOW_KINDS)
        elseif STAGE2_KINDS[kind] and type(v) == "table" then
            local kept = StripKind(kind, v)
            if next(kept) ~= nil then
                out[f] = kept
            end
        else
            out[f] = v
        end
    end
    return out
end

------------------------------------------------------------------------------------------
-- Validation
------------------------------------------------------------------------------------------

local function Fail(message)
    error(message, 0)
end

local function EnumAllows(kind, v)
    if type(v) ~= "string" then
        return false
    end
    for option in kind:sub(6):gmatch("[^|]+") do
        if option == v then
            return true
        end
    end
    return false
end

local function IsRadius(v)
    if type(v) == "number" then
        return true
    end
    if type(v) ~= "table" or #v ~= 4 then
        return false
    end
    for i = 1, 4 do
        if type(v[i]) ~= "number" then
            return false
        end
    end
    return true
end

local function IsFont(v)
    if type(v) == "string" then
        return true
    end
    if type(v) ~= "table" or #v == 0 then
        return false
    end
    for i = 1, #v do
        if type(v[i]) ~= "string" then
            return false
        end
    end
    return true
end

local CheckValue

-- `inside` marks a table that is part of a stage 2 value, whose entries report `expected <kind>`.
local function CheckTable(where, path, kinds, t, inside)
    for k, v in pairs(t) do
        local kind = kinds[k]
        if kind == nil then
            Fail(where .. ": " .. path .. "." .. tostring(k) .. " is not a known field")
        end
        CheckValue(where, path .. "." .. tostring(k), kind, v, inside)
    end
end

CheckValue = function(where, path, kind, v, inside)
    local function Bad()
        if inside or STAGE2_KINDS[kind] then
            Fail(where .. ": " .. path .. ": expected " .. kind)
        end
        Fail(where .. ": " .. path .. " must be " .. kind)
    end
    if kind == "color" then
        if not IsColorValue(v) then
            Bad()
        end
    elseif kind == "number" then
        if type(v) ~= "number" then
            Bad()
        end
    elseif kind == "boolean" then
        if type(v) ~= "boolean" then
            Bad()
        end
    elseif kind == "string" then
        if type(v) ~= "string" then
            Bad()
        end
    elseif kind:sub(1, 5) == "enum:" then
        if not EnumAllows(kind, v) then
            Bad()
        end
    elseif kind == "radius" then
        if not IsRadius(v) then
            Bad()
        end
    elseif kind == "font" then
        if not IsFont(v) then
            Bad()
        end
    elseif kind == "text" then
        if type(v) ~= "table" then
            Bad()
        end
        CheckTable(where, path, TEXT_KINDS, v)
    elseif kind == "shadow" then
        -- False turns a text shadow off, as StyleLab's shadow = false does.
        if v == false then
            return
        end
        if type(v) ~= "table" then
            Bad()
        end
        CheckTable(where, path, SHADOW_KINDS, v)
    elseif kind == "roles" then
        if type(v) ~= "table" then
            Bad()
        end
        for role, entry in pairs(v) do
            local rolePath = path .. "." .. tostring(role)
            if not IsRole[role] then
                Fail(where .. ": " .. rolePath .. " is not a known field")
            end
            if type(entry) ~= "table" then
                Fail(where .. ": " .. rolePath .. " must be a table of " .. kind)
            end
            CheckTable(where, rolePath, ROLE_KINDS, entry)
        end
    elseif kind == "stops" then
        if type(v) ~= "table" then
            Bad()
        end
        if #v < 2 then
            Fail(where .. ": " .. path .. ": expected at least 2 colours")
        end
        for i = 1, #v do
            if not IsColorValue(v[i]) then
                Fail(where .. ": " .. path .. "[" .. i .. "]: expected color")
            end
        end
    elseif FIXED_KINDS[kind] ~= nil then
        -- A table of keys. An empty list is an empty table, but a list with entries is not.
        if type(v) ~= "table" or #v > 0 then
            Bad()
        end
        CheckTable(where, path, FIXED_KINDS[kind], v, true)
    elseif kind == "faces" then
        if type(v) ~= "table" or #v > 0 then
            Bad()
        end
        for role, entry in pairs(v) do
            local rolePath = path .. "." .. tostring(role)
            if not IsRole[role] then
                Fail(where .. ": " .. rolePath .. " is not a known field")
            end
            if type(entry) ~= "table" or #entry > 0 then
                Fail(where .. ": " .. rolePath .. ": expected table")
            end
            CheckTable(where, rolePath, FACE_KINDS, entry, true)
        end
    elseif kind == "table" then
        if type(v) ~= "table" then
            Bad()
        end
    end
end

-- The message starts with `where` when the caller gave one, so an Init or Register error names the call that failed.
local function UnknownPreset(id, where)
    Fail((where or "ModMenu style") .. ': unknown theme "' .. tostring(id) .. '"; choose one of: '
        .. table.concat(Presets.order, ", "))
end

local function CheckPresetId(id, where)
    if type(id) ~= "string" or Presets.presets[id] == nil then
        UnknownPreset(id, where)
    end
end

local function CheckEntry(where, typeName, entry, allowFrom)
    local kinds = TYPES[typeName]
    for f, v in pairs(entry) do
        if allowFrom and f == "from" then
            CheckPresetId(v, where .. ": " .. typeName .. ".from")
        else
            local kind = kinds[f]
            if kind == nil then
                Fail(where .. ": " .. typeName .. "." .. tostring(f) .. " is not a known field")
            end
            CheckValue(where, typeName .. "." .. tostring(f), kind, v)
        end
    end
end

local function CheckPalette(where, palette)
    if type(palette) ~= "table" then
        Fail(where .. ": palette must be a table")
    end
    for k, v in pairs(palette) do
        if not IsPaletteKey[k] then
            Fail(where .. ": palette." .. tostring(k) .. " is not a known field")
        end
        CheckValue(where, "palette." .. tostring(k), "color", v)
    end
end

--- Check a style override table against the field list.
--- Each object type takes a preset id, a field table, or a field table with `from = "<preset id>"`;
--- `palette` takes palette colours. The first problem raises an error that starts with `where`.
--- opts.noFrom rejects `from` as an unknown field, because an item look merges over the theme's
--- type and has no preset to borrow from, so a `from` there would be ignored silently.
---@param style table|nil
---@param where string
---@param opts table|nil { noFrom? }
function M.Validate(style, where, opts)
    local allowFrom = not (type(opts) == "table" and opts.noFrom == true)
    if style == nil then
        return
    end
    if type(style) ~= "table" then
        Fail(where .. ": style must be a table")
    end
    for typeName, value in pairs(style) do
        if typeName == "palette" then
            CheckPalette(where, value)
        elseif TYPES[typeName] == nil then
            Fail(where .. ": unknown object type " .. tostring(typeName))
        elseif type(value) == "string" then
            CheckPresetId(value, where .. ": " .. typeName)
        elseif type(value) == "table" then
            CheckEntry(where, typeName, value, allowFrom)
        else
            Fail(where .. ": " .. typeName .. " must be a preset id or a table of fields")
        end
    end
end

-- A definition is checked like a style table, except that base and parts name presets and a type
-- entry cannot borrow with `from`.
local function ValidateDefinition(def, where)
    for key, value in pairs(def) do
        if key == "palette" then
            CheckPalette(where, value)
        elseif key == "base" then
            CheckPresetId(value, where .. ": base")
        elseif key == "parts" then
            if type(value) ~= "table" then
                Fail(where .. ": parts must be a table of object type to preset id")
            end
            for typeName, id in pairs(value) do
                if TYPES[typeName] == nil then
                    Fail(where .. ": unknown object type " .. tostring(typeName))
                end
                CheckPresetId(id, where .. ": parts." .. typeName)
            end
        elseif DEFINITION_KEYS[key] then
            -- Names and descriptions are free text.
        elseif TYPES[key] == nil then
            Fail(where .. ": unknown object type " .. tostring(key))
        elseif type(value) ~= "table" then
            Fail(where .. ": " .. key .. " must be a table of fields")
        else
            CheckEntry(where, key, value, false)
        end
    end
end

------------------------------------------------------------------------------------------
-- Flattening: a definition and its borrowing become one raw table
------------------------------------------------------------------------------------------

local Flatten

local function PresetRaw(id, seen)
    CheckPresetId(id)
    return Flatten(Presets.presets[id], seen)
end

--- Apply a definition's base and parts, and convert its colours, without filling defaults.
--- The base supplies the palette and every type; the definition's own entries merge over it; each
--- part replaces its type with the named preset's entry stripped of colours, and the definition's
--- own fields for that type still merge over the part.
Flatten = function(def, seen)
    seen = seen or {}
    if seen[def] then
        Fail("ModMenu style: a theme borrows from itself through base or parts")
    end
    seen[def] = true
    local raw = { palette = {} }
    if def.base ~= nil then
        raw = PresetRaw(def.base, seen)
    end
    for k, v in pairs(def.palette or {}) do
        raw.palette[k] = Color(v)
    end
    for _, typeName in ipairs(TYPE_ORDER) do
        if def[typeName] ~= nil then
            raw[typeName] = MergeType(typeName, raw[typeName], Normalize(typeName, def[typeName]))
        end
    end
    for typeName, id in pairs(def.parts or {}) do
        local source = PresetRaw(id, seen)
        raw[typeName] = MergeType(typeName, StripColors(typeName, source[typeName]), Normalize(typeName, def[typeName]))
    end
    seen[def] = nil
    return raw
end

------------------------------------------------------------------------------------------
-- Defaults and derived fields, per object type
------------------------------------------------------------------------------------------

local LEGACY_LIGHT = Theme.Preset("light")

-- The legacy light button colours, for the roles and palette entries StyleLab never defined.
local LEGACY_ROLE = {
    success = { fill = LEGACY_LIGHT.buttonBgSuccess, text = LEGACY_LIGHT.buttonTextSuccess },
    warning = { fill = LEGACY_LIGHT.buttonBgWarning, text = LEGACY_LIGHT.buttonTextWarning },
    info = { fill = LEGACY_LIGHT.buttonBgInfo, text = LEGACY_LIGHT.buttonTextInfo },
}

local function ResolvePalette(raw)
    local p = {}
    for _, key in ipairs(PALETTE) do
        if raw[key] ~= nil then
            p[key] = Color(raw[key])
        end
    end
    -- A custom definition may name only some colours, so the core ones fall back to the light
    -- preset's palette rather than leaving a widget with nil.
    local light = Presets.presets.light.palette
    for _, key in ipairs({ "bg", "text", "muted", "accent", "accentText", "danger", "surface", "line" }) do
        if p[key] == nil then
            p[key] = Color(light[key])
        end
    end
    p.dangerText = p.dangerText or Color(WHITE)
    p.secondaryText = p.secondaryText or Color(p.text)
    p.track = p.track or Mix(p.bg, p.text, 0.15)
    p.success = p.success or Color(LEGACY_ROLE.success.fill)
    p.warning = p.warning or Color(LEGACY_ROLE.warning.fill)
    p.info = p.info or Color(LEGACY_ROLE.info.fill)
    return p
end

local function LargestRadius(radius)
    if type(radius) == "table" then
        local largest = 0
        for i = 1, #radius do
            if radius[i] > largest then
                largest = radius[i]
            end
        end
        return largest
    end
    return radius or 0
end

-- A bevel with no width is one unit wide, as the field list says. Only a bevel that exists gets one,
-- so a borrow that dropped its bevel does not bring it back.
local function WithBevelWidth(bevel)
    if type(bevel) ~= "table" then
        return bevel
    end
    return Merge({ width = 1 }, bevel)
end

-- The bevel and status bar defaults of each object type, filled for a resolved entry and for an item
-- look merged over it.
local function FillDefaults(typeName, s)
    if typeName == "panel" then
        s.bevel = WithBevelWidth(s.bevel)
        -- The status bar says "Ready" unless the theme gives it other text.
        if type(s.statusBar) == "table" then
            s.statusBar = Merge({ text = "Ready" }, s.statusBar)
        end
    elseif typeName == "button" or typeName == "field" then
        s.bevel = WithBevelWidth(s.bevel)
    elseif typeName == "toggle" then
        s.checkBevel = WithBevelWidth(s.checkBevel)
    elseif typeName == "progress" then
        if type(s.frame) == "table" and s.frame.bevel ~= nil then
            s.frame = Merge(s.frame, { bevel = WithBevelWidth(s.frame.bevel) })
        end
    end
    return s
end

local function ResolveText(t, color)
    local out = Merge({ color = color }, t)
    if type(out.shadow) == "table" and out.shadow.color == nil then
        out.shadow = Merge(out.shadow, { color = Alpha(BLACK, 0.5) })
    end
    return out
end

local function DefaultRoles(p)
    return {
        default = { fill = p.surface, text = p.text },
        primary = { fill = p.accent, text = p.accentText },
        secondary = { fill = p.surface, text = p.secondaryText },
        success = { fill = p.success, text = LEGACY_ROLE.success.text },
        danger = { fill = p.danger, text = p.dangerText },
        warning = { fill = p.warning, text = LEGACY_ROLE.warning.text },
        info = { fill = p.info, text = LEGACY_ROLE.info.text },
        active = { fill = p.accent, text = p.accentText },
        disabled = { fill = Mix(p.bg, p.text, 0.08), text = p.muted },
    }
end

-- Text sizes, fonts and typefaces are left nil unless a theme sets them, because nil means the
-- library's own font and the config's size after font scaling.
local RESOLVERS = {}

function RESOLVERS.panel(t, p)
    local s = Merge({ radius = 12, width = 1, outline = p.line, fill = p.bg, pad = 18, blur = 0,
        shadowColor = BLACK, hardShadow = 0, hardShadowColor = BLACK, rim = false,
        rimLight = Alpha(WHITE, 0.7), rimDark = Alpha(BLACK, 0.25), corners = false }, t)
    -- The blur sits at half the panel's radius (field note 32), so it follows a changed radius.
    s.blurRadius = s.blurRadius or LargestRadius(s.radius) * 0.5
    s.blurInset = s.blurInset or 2
    return FillDefaults("panel", s)
end

function RESOLVERS.header(t, p)
    return Merge({ variant = "badge", fill = Alpha(p.bg, 0), text = p.text, line = p.line,
        badgeFill = Mix(p.bg, p.accent, 0.16), controlGlyph = p.text, captions = "all" }, t)
end

function RESOLVERS.title(t, p)
    return ResolveText(t, p.text)
end

function RESOLVERS.body(t, p)
    return ResolveText(t, p.text)
end

function RESOLVERS.hint(t, p)
    return ResolveText(t, p.muted)
end

function RESOLVERS.data(t, p)
    local s = ResolveText(t, p.accent)
    s.statusColor = s.statusColor or p.warning
    return s
end

function RESOLVERS.section(t, p)
    local s = Merge({ variant = "label", color = p.muted, fill = Mix(p.bg, p.text, 0.06), mark = p.muted,
        line = p.line }, t)
    s.text = ResolveText(s.text, s.color)
    return s
end

function RESOLVERS.button(t, p)
    local s = Merge({ variant = "fill", radius = 8, width = 1, hoverToward = WHITE, hoverAmount = 0.14 }, t)
    -- Every role is filled, so a widget never meets a nil fill or text colour.
    local roles = DefaultRoles(p)
    for role, entry in pairs(s.roles or {}) do
        roles[role] = Merge(roles[role], entry)
    end
    s.roles = roles
    return FillDefaults("button", s)
end

function RESOLVERS.toggle(t, p)
    local s = Merge({ variant = "switch", trackOn = p.accent, trackOff = Mix(p.bg, p.text, 0.22), knobOn = WHITE,
        knobOff = WHITE, w = 36, h = 20, checkOff = Alpha(p.text, 0), checkOn = p.accent, checkEdge = p.text,
        checkEdgeOn = p.accent, checkMark = p.accentText, checkEdgeWidth = 1 }, t)
    s.radius = s.radius or s.h / 2
    return FillDefaults("toggle", s)
end

function RESOLVERS.slider(t, p)
    return Merge({ variant = "round", thickness = 4, size = 16, track = p.track, thumbFill = WHITE,
        thumbEdge = p.accent, thumbHover = p.accent }, t)
end

function RESOLVERS.progress(t, p)
    local s = Merge({ variant = "bar", height = 8, radius = 4, segments = 12, gap = 3, track = p.track,
        fill = p.accent }, t)
    return FillDefaults("progress", s)
end

function RESOLVERS.choice(t, p, s)
    return Merge({ variant = "joined", radius = s.button.radius, pill = s.button.pill, markFill = p.accent,
        markText = p.accentText, radioEdge = p.text, radioFill = p.accent }, t)
end

-- The tab strip follows the choice variant, as StyleLab's does; radio has no tab form.
local TAB_VARIANT = { stock = "stock", joined = "joined", chips = "chips", tabs = "tabs", radio = "joined" }

function RESOLVERS.tabs(t, _, s)
    local c = s.choice
    return Merge({ variant = TAB_VARIANT[c.variant], radius = c.radius, pill = c.pill, markFill = c.markFill,
        markText = c.markText, markEdge = c.markEdge, trackFill = c.trackFill, edge = c.edge, tabText = c.tabText }, t)
end

function RESOLVERS.field(t, p, s)
    local f = Merge({ variant = "frame", fill = Mix(p.bg, p.text, 0.07), outline = p.line, width = 1,
        radius = s.button.radius, pill = s.button.pill, text = p.text, hint = p.muted }, t)
    f.headerFill = f.headerFill or Mix(p.bg, p.text, 0.12)
    f.headerText = f.headerText or f.text
    return FillDefaults("field", f)
end

function RESOLVERS.list(t, p, s)
    local f = s.field
    return Merge({ fill = f.fill, text = f.text, hover = Mix(f.fill, p.accent, 0.2), more = p.muted,
        radius = f.radius }, t)
end

function RESOLVERS.stepper(t, _, s)
    return Merge({ role = "default", height = s.button.height, radius = s.button.radius, pill = s.button.pill }, t)
end

function RESOLVERS.tooltip(t, p, s)
    return Merge({ fill = p.surface, text = p.text, radius = s.button.radius, outline = p.line,
        width = s.button.width }, t)
end

function RESOLVERS.confirm(t, p, s)
    return Merge({ fill = p.surface, dim = Alpha(BLACK, 0.6), divider = p.line, radius = s.panel.radius }, t)
end

function RESOLVERS.motion(t)
    return Merge({ pulse = false, cursor = false, glitch = false, sparkle = false, open = true, pop = true,
        shake = true }, t)
end

--- Resolve one type from its raw entry. The result is normalized, so no table in it is shared
--- with the palette, another type or a preset.
local function ResolveType(typeName, raw, p, s)
    local resolver = RESOLVERS[typeName]
    local entry = raw or {}
    if resolver ~= nil then
        entry = resolver(entry, p, s)
    end
    return Normalize(typeName, entry)
end

------------------------------------------------------------------------------------------
-- Legacy colour tokens
------------------------------------------------------------------------------------------

-- Each legacy token and the resolved path it maps to, from the spec's mapping table.
local LEGACY = {
    { "panelBg", { "panel", "fill" } },
    { "panelBorder", { "panel", "outline" } },
    { "textPrimary", { "body", "color" }, { "title", "color" } },
    { "textMuted", { "palette", "muted" } },
    { "textAccent", { "palette", "accent" } },
    { "textStatus", { "data", "statusColor" } },
    { "sectionHeaderBg", { "section", "fill" } },
    { "sectionMark", { "section", "mark" } },
    { "fieldBg", { "field", "fill" } },
    { "fieldText", { "field", "text" } },
    { "fieldHint", { "field", "hint" } },
    { "dropdownHeaderBg", { "field", "headerFill" } },
    { "dropdownHeaderText", { "field", "headerText" } },
    { "dropdownOptionBg", { "list", "fill" } },
    { "dropdownOptionText", { "list", "text" } },
    { "dropdownMore", { "list", "more" } },
    { "overlayDim", { "confirm", "dim" } },
    { "confirmCardBg", { "confirm", "fill" } },
    { "confirmDivider", { "confirm", "divider" } },
    { "tooltipBg", { "tooltip", "fill" } },
}

-- Button tokens: the role, its fill and text keys, and its hover and pressed keys when it has them.
local LEGACY_BUTTONS = {
    { "default", "buttonBg", "buttonText", "buttonHover", "buttonPressed" },
    { "primary", "buttonBgPrimary", "buttonTextPrimary", "buttonPrimaryHover", "buttonPrimaryPressed" },
    { "secondary", "buttonBgSecondary", "buttonTextSecondary", "buttonSecondaryHover", "buttonSecondaryPressed" },
    { "success", "buttonBgSuccess", "buttonTextSuccess", "buttonSuccessHover", "buttonSuccessPressed" },
    { "danger", "buttonBgDanger", "buttonTextDanger", "buttonDangerHover", "buttonDangerPressed" },
    { "warning", "buttonBgWarning", "buttonTextWarning", "buttonWarningHover", "buttonWarningPressed" },
    { "info", "buttonBgInfo", "buttonTextInfo", "buttonInfoHover", "buttonInfoPressed" },
    { "active", "buttonBgActive", "buttonTextActive" },
    { "disabled", "buttonBgDisabled", "buttonTextDisabled" },
}

for _, row in ipairs(LEGACY_BUTTONS) do
    local role = row[1]
    LEGACY[#LEGACY + 1] = { row[2], { "button", "roles", role, "fill" } }
    LEGACY[#LEGACY + 1] = { row[3], { "button", "roles", role, "text" } }
    if row[4] ~= nil then
        LEGACY[#LEGACY + 1] = { row[4], { "button", "roles", role, "hover" } }
        LEGACY[#LEGACY + 1] = { row[5], { "button", "roles", role, "pressed" } }
    end
end

local function SetPath(t, path, value)
    for i = 1, #path - 1 do
        t = t[path[i]]
    end
    t[path[#path]] = value
end

local function GetPath(t, path)
    for i = 1, #path do
        if type(t) ~= "table" then
            return nil
        end
        t = t[path[i]]
    end
    return t
end

local function ApplyLegacy(resolved, colors)
    for _, row in ipairs(LEGACY) do
        local value = colors[row[1]]
        -- Theme.Merge skipped any value that was not a table, so a string that is not valid hex is
        -- skipped too, and a mod that passed a stray value keeps working.
        if type(value) == "table" or ParseHex(value) ~= nil then
            for i = 2, #row do
                SetPath(resolved, row[i], Color(value))
            end
        end
    end
end

--- Read the legacy colour tokens back out of a resolved style, for code that still reads
--- config.colors. A token whose field is nil, such as an underived hover colour, is left out.
---@param resolved table
---@return table
function M.LegacyColors(resolved)
    local out = {}
    for _, row in ipairs(LEGACY) do
        local value = GetPath(resolved, row[2])
        if value ~= nil then
            out[row[1]] = Color(value)
        end
    end
    return out
end

------------------------------------------------------------------------------------------
-- Public functions
------------------------------------------------------------------------------------------

--- The preset ids, in the order of core/presets.lua.
---@return string[]
function M.Ids()
    local out = {}
    for i, id in ipairs(Presets.order) do
        out[i] = id
    end
    return out
end

local function Borrowed(typeName, id)
    return StripColors(typeName, PresetRaw(id)[typeName])
end

--- Resolve a theme, a style override table and legacy colours into one complete style table.
---@param theme string|table|nil a preset id, a definition table, or nil for "light"
---@param style table|nil
---@param colors table|nil
---@return table
function M.Resolve(theme, style, colors)
    if theme == nil then
        theme = "light"
    end
    if type(theme) ~= "string" and type(theme) ~= "table" then
        Fail("ModMenu style: theme must be a preset id or a definition table")
    end
    if type(theme) == "table" then
        ValidateDefinition(theme, "theme")
    end
    local id = type(theme) == "string" and theme or "custom"
    local raw = type(theme) == "string" and PresetRaw(theme) or Flatten(theme)
    M.Validate(style, "style")
    style = style or {}

    for k, v in pairs(style.palette or {}) do
        raw.palette[k] = Color(v)
    end
    local p = ResolvePalette(raw.palette)
    local definition = type(theme) == "table" and theme or Presets.presets[theme]
    local resolved = {
        id = id,
        name = definition.name,
        subtitle = definition.subtitle,
        footer = definition.footer,
        palette = p,
    }
    for _, typeName in ipairs(TYPE_ORDER) do
        resolved[typeName] = ResolveType(typeName, raw[typeName], p, resolved)
    end

    -- A type override runs after every default, so it changes only its own type; derived fields
    -- inside that type, such as the panel's blur radius, are derived again from the override.
    for _, typeName in ipairs(TYPE_ORDER) do
        local value = style[typeName]
        -- Under MoonSharp a bare `local entry` inside this loop held a stale value, so it starts at nil explicitly.
        local entry = nil
        if type(value) == "string" then
            entry = Borrowed(typeName, value)
        elseif type(value) == "table" then
            local fields = {}
            for f, v in pairs(value) do
                if f ~= "from" then
                    fields[f] = v
                end
            end
            local start = value.from ~= nil and Borrowed(typeName, value.from) or raw[typeName]
            entry = MergeType(typeName, start, Normalize(typeName, fields))
        end
        if entry ~= nil then
            resolved[typeName] = ResolveType(typeName, entry, p, resolved)
        end
    end

    if type(colors) == "table" then
        ApplyLegacy(resolved, colors)
    end
    return resolved
end

--- Return an object type's resolved table with an item's look merged over it.
--- The result is a new table; `resolved` is not changed.
---@param resolved table
---@param objectType string
---@param look table|nil
---@return table
function M.ForItem(resolved, objectType, look)
    if TYPES[objectType] == nil then
        Fail("ModMenu style: unknown object type " .. tostring(objectType))
    end
    local base = Normalize(objectType, resolved[objectType])
    if look == nil then
        return base
    end
    return FillDefaults(objectType, MergeType(objectType, base, Normalize(objectType, look)))
end

return M
