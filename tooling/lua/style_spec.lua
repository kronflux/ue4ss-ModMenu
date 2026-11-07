-- These checks cover theme resolution, because every themed widget reads its colours and shapes
-- from the resolved table, and the builder's TypeScript resolver must match it fixture for fixture.
local okStyle, Style = pcall(require, "ModMenu.core.style")
assert_true("core.style loads under MoonSharp", okStyle)
if not okStyle then
    return
end
local Theme = require("ModMenu.core.theme")
local Json = require("ModMenu.store.json")
local Fields = require("ModMenu.core.stylefields")
local Presets = require("ModMenu.core.presets")

local FIXTURES = {
    "slate-plain",
    "borrow-id",
    "borrow-with-fields",
    "borrow-strips-colors",
    "field-table",
    "palette-change",
    "legacy-colors-over-preset",
    "item-look",
    "light",
    "dark",
    "custom-definition",
    "stage2-kinds",
    "stage2-borrow",
    "stage2-merge",
    "stage3-arrow",
    "stage3-arrow-borrow",
}

local function ReadFixture(name)
    local f = io.open(_REPO .. "/tooling/lua/fixtures/style/" .. name .. ".json", "r")
    if f == nil then
        return nil
    end
    local text = f:read("*a")
    f:close()
    return Json.Decode(text)
end

local function GetPath(t, path)
    for segment in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then
            return nil
        end
        t = t[segment]
    end
    return t
end

-- Expected colours are written to 4 decimals, so a value matches within half of the last digit.
local function Near(got, want)
    if type(want) == "number" then
        return type(got) == "number" and math.abs(got - want) <= 0.000051
    end
    if type(want) ~= "table" then
        return got == want
    end
    if type(got) ~= "table" then
        return false
    end
    for k, v in pairs(want) do
        if not Near(got[k], v) then
            return false
        end
    end
    for k in pairs(got) do
        if want[k] == nil then
            return false
        end
    end
    return true
end

for _, name in ipairs(FIXTURES) do
    local fixture = ReadFixture(name)
    if fixture == nil then
        assert_true("style fixture " .. name .. " is readable", false)
    else
        local input = fixture.input
        -- A fixture may name temporary presets, because no shipped preset holds every stage 2 kind.
        -- They are registered for this resolve only and removed straight after it.
        local temporary = {}
        for id, definition in pairs(input.presets or {}) do
            Presets.presets[id] = definition
            temporary[#temporary + 1] = id
        end
        local ok, resolved = pcall(Style.Resolve, input.theme, input.style, input.colors)
        for _, id in ipairs(temporary) do
            Presets.presets[id] = nil
        end
        if not ok then
            assert_eq("style fixture " .. name, tostring(resolved), "no error")
        else
            if input.look ~= nil then
                resolved[input.lookType] = Style.ForItem(resolved, input.lookType, input.look)
            end
            local mismatches = {}
            local paths = {}
            for path in pairs(fixture.expect) do
                paths[#paths + 1] = path
            end
            table.sort(paths)
            for _, path in ipairs(paths) do
                local got = GetPath(resolved, path)
                if not Near(got, fixture.expect[path]) then
                    mismatches[#mismatches + 1] = path .. " = " .. _RUNNER.encode(got)
                end
            end
            -- A path listed under `absent` must resolve to nothing, as a borrowed field with no keys left does.
            for _, path in ipairs(fixture.absent or {}) do
                if GetPath(resolved, path) ~= nil then
                    mismatches[#mismatches + 1] = path .. " should be absent"
                end
            end
            assert_eq("style fixture " .. name, mismatches, {})
        end
    end
end

-- AC-1: light and dark read back the legacy colours exactly, with and without a colors table.
local override = { panelBg = { R = 0.3, G = 0.2, B = 0.1, A = 1 }, buttonTextDanger = { R = 0.5, G = 0.5, B = 0.5 } }
for _, name in ipairs({ "light", "dark" }) do
    local resolved = Style.Resolve(name)
    assert_eq(name .. " maps back to Theme.Resolve", Style.LegacyColors(resolved), Theme.Resolve(name, nil))
    assert_eq(
        name .. " with colors maps back to Theme.Resolve with the same colors",
        Style.LegacyColors(Style.Resolve(name, nil, override)),
        Theme.Resolve(name, override)
    )
    local nonzero = {}
    for typeName in pairs(Fields.types) do
        local entry = resolved[typeName] or {}
        for _, key in ipairs({ "radius", "width" }) do
            if entry[key] ~= nil and entry[key] ~= 0 then
                nonzero[#nonzero + 1] = typeName .. "." .. key
            end
        end
    end
    table.sort(nonzero)
    assert_eq(name .. " has every radius and width at 0", nonzero, {})
    assert_eq(name .. " buttons use the fill variant", resolved.button.variant, "fill")
end

-- Theme.Merge skipped a legacy value that was not a colour table, so a non-hex string is skipped too.
local okStray, stray = pcall(Style.Resolve, "light", nil, { panelBg = "red" })
assert_true("a non-hex legacy colour string resolves without error", okStray)
if okStray then
    assert_eq("a non-hex legacy colour string leaves panel.fill unchanged", stray.panel.fill, Style.Resolve("light").panel.fill)
end

-- AC-2: every preset resolves, and every resolved field has its declared kind and linear colours.
local function LinearColors(resolved)
    for typeName, kinds in pairs(Fields.types) do
        for field, kind in pairs(kinds) do
            local v = (resolved[typeName] or {})[field]
            if kind == "color" and v ~= nil and type(v) ~= "table" then
                return false
            end
        end
    end
    return true
end

for _, id in ipairs(Style.Ids()) do
    local ok, resolved = pcall(Style.Resolve, id)
    local valid = false
    if ok then
        local types = {}
        for typeName in pairs(Fields.types) do
            types[typeName] = resolved[typeName]
        end
        valid = pcall(Style.Validate, types, "resolved " .. id) and pcall(Style.Validate, { palette = resolved.palette }, id)
            and LinearColors(resolved)
        for _, role in ipairs({ "default", "primary", "secondary", "success", "danger", "warning", "info", "active", "disabled" }) do
            local entry = resolved.button.roles[role]
            valid = valid and entry ~= nil and type(entry.fill) == "table" and type(entry.text) == "table"
        end
    end
    assert_true("preset " .. id .. " ok", valid)
end

-- Stages 1 and 2 ship light, dark and 32 StyleLab presets, and stage 3 adds the eight Windows
-- presets; the loop above resolves each of them. The Windows 11 drafts stay outside themes/presets.
local ids = Style.Ids()
assert_eq("Ids holds the 42 presets", #ids, 42)
assert_eq(
    "Ids ends with the five stage 2 presets in the spec's order",
    { table.unpack(ids, 30, 34) },
    { "terminal", "hologram", "frost", "mac-light", "mac-dark" }
)
assert_eq(
    "Ids ends with mac-dark and the eight Windows presets in the spec's order",
    { table.unpack(ids, 34, 42) },
    {
        "mac-dark", "xp-luna", "xp-luna-silver", "xp-luna-olive", "xp-embedded", "xp-royale", "xp-royale-noir",
        "xp-zune", "windows-classic",
    }
)
do
    local classic = Style.Resolve("windows-classic")
    assert_eq("windows-classic resolves the classic button variant", classic.button.variant, "classic")
    assert_true("windows-classic sets the radio bevel", type(classic.choice.radioBevel) == "table")
    assert_true("windows-classic sets the dropdown arrow bevel", type(classic.field.arrow) == "table" and type(classic.field.arrow.bevel) == "table")
    assert_eq("windows-classic resolves the classic header", classic.header.variant, "classic")
    assert_true("windows-classic sets the check box bevel", type(classic.toggle.checkBevel) == "table")
    assert_true("windows-classic sets the field bevel", type(classic.field.bevel) == "table")
end
assert_eq("Ids puts nord before terminal", ids[29], "nord")
do
    assert_eq("mac-light uses the mac header", Style.Resolve("mac-light").header.variant, "mac")
    local xp = Style.Resolve("slate", { header = { variant = "xpbar" }, button = { variant = "xp" }, panel = { radius = { 8, 8, 0, 0 } } })
    assert_eq("an xp override sets the xp button variant", xp.button.variant, "xp")
    assert_eq("an xp override sets the xpbar header", xp.header.variant, "xpbar")
    assert_eq("an xp override keeps the panel corners 8, 8, 0, 0", xp.panel.radius, { 8, 8, 0, 0 })
    assert_eq("a classic override sets the classic button variant", Style.Resolve("slate", { button = { variant = "classic" } }).button.variant, "classic")
    assert_eq("neon pulses", Style.Resolve("neon").motion.pulse, true)
end
assert_eq("Ids starts with light, dark and slate", { ids[1], ids[2], ids[3] }, { "light", "dark", "slate" })
assert_eq("Ids matches the generated order", ids, require("ModMenu.core.presets").order)

local function ErrorOf(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then
        return "no error"
    end
    -- MoonSharp prefixes a position even for error(message, 0); UE4SS's Lua does not, so the
    -- prefix is removed to compare the message itself.
    return (tostring(err):gsub("^[^:]*:%(%d+,[%d%-]+%): ", ""))
end

-- AC-4: bad input names the bad id, type or field.
assert_eq("Validate names an unknown type", ErrorOf(Style.Validate, { wobble = {} }, "here"), "here: unknown object type wobble")
assert_eq(
    "Validate names an unknown field",
    ErrorOf(Style.Validate, { button = { wobble = 1 } }, "here"),
    "here: button.wobble is not a known field"
)
assert_eq(
    "Validate names a field of the wrong kind",
    ErrorOf(Style.Validate, { button = { radius = "big" } }, "here"),
    "here: button.radius must be radius"
)
assert_eq(
    "Validate rejects a malformed hex colour",
    ErrorOf(Style.Validate, { panel = { fill = "#12" } }, "here"),
    "here: panel.fill must be color"
)
assert_eq(
    "Validate names an unknown palette key",
    ErrorOf(Style.Validate, { palette = { glow = "#FFFFFF" } }, "here"),
    "here: palette.glow is not a known field"
)
assert_eq(
    "Validate names an unknown role field",
    ErrorOf(Style.Validate, { button = { roles = { primary = { glow = "#FFFFFF" } } } }, "here"),
    "here: button.roles.primary.glow is not a known field"
)
assert_true("Validate accepts a borrow with fields", ErrorOf(Style.Validate, { panel = { from = "slate", radius = 4 } }, "here") == "no error")
assert_eq(
    "Validate with noFrom rejects a borrow as an unknown field",
    ErrorOf(Style.Validate, { button = { from = "neon" } }, "here", { noFrom = true }),
    "here: button.from is not a known field"
)

local unknown = ErrorOf(Style.Resolve, "nope")
assert_true("an unknown theme names itself", unknown:find('"nope"', 1, true) ~= nil)
assert_true("an unknown theme lists every preset id", unknown:find("light, dark, slate", 1, true) ~= nil)
assert_true("borrowing an unknown preset lists every id", ErrorOf(Style.Resolve, "light", { panel = "nope" }):find("light, dark, slate", 1, true) ~= nil)
assert_true("Hex names a malformed string", ErrorOf(Style.Hex, "#12345"):find('"#12345"', 1, true) ~= nil)
assert_true("Resolve validates style", ErrorOf(Style.Resolve, "slate", { panel = { glow = 1 } }):find("panel.glow is not a known field", 1, true) ~= nil)

-- Colours.
assert_eq("Hex keeps a short form opaque", Style.Hex("#FFFFFF"), { R = 1, G = 1, B = 1, A = 1 })
assert_eq("Hex reads an alpha byte", Style.Hex("#00000080").A, 128 / 255)
local source = { R = 0.1, G = 0.2, B = 0.3 }
local copied = Style.Color(source)
assert_eq("Color copies a table and fills alpha", copied, { R = 0.1, G = 0.2, B = 0.3, A = 1 })
assert_true("Color returns a new table", copied ~= source)

-- ForItem returns a new table and leaves the resolved style alone.
local slate = Style.Resolve("slate")
local before = slate.button.radius
local item = Style.ForItem(slate, "button", { radius = 2 })
assert_eq("ForItem merges the look", item.radius, 2)
assert_eq("ForItem leaves resolved unchanged", slate.button.radius, before)
assert_true("ForItem returns a new table", item ~= slate.button)

-- Light and dark leave text sizes unset, so the menu keeps its configured sizes. The StyleLab
-- presets carry StyleLab's text defaults: title 20, body 14, readout 22.
assert_eq("light sets no title size", Style.Resolve("light").title.size, nil)
assert_eq("slate carries StyleLab's body size", slate.body.size, 14)

-- Stage 2 kinds: a bad entry inside stops, bevel, faces, xpface, frame or statusbar is reported as
-- `<type>.<field>.<key>: expected <kind>`, and an unknown key as an unknown field.
local function Bad(style)
    return ErrorOf(Style.Validate, style, "here")
end
assert_eq("a bevel colour must be a colour", Bad({ panel = { bevel = { light = "#12" } } }), "here: panel.bevel.light: expected color")
assert_eq("a bevel width must be a number", Bad({ panel = { bevel = { width = "wide" } } }), "here: panel.bevel.width: expected number")
assert_eq("a bevel names an unknown key", Bad({ panel = { bevel = { glow = "#FFFFFF" } } }), "here: panel.bevel.glow is not a known field")
assert_eq("a bevel must be a table", Bad({ panel = { bevel = "flat" } }), "here: panel.bevel: expected bevel")
assert_eq("stops need two colours", Bad({ header = { barStops = { "#000000" } } }), "here: header.barStops: expected at least 2 colours")
assert_eq("stops must be a list", Bad({ header = { barStops = "#000000" } }), "here: header.barStops: expected stops")
assert_eq("a stop must be a colour", Bad({ header = { barStops = { "#000000", "#12" } } }), "here: header.barStops[2]: expected color")
assert_eq("faces names an unknown role", Bad({ button = { faces = { wobble = {} } } }), "here: button.faces.wobble is not a known field")
assert_eq("a face colour must be a colour", Bad({ button = { faces = { primary = { fill = "#12" } } } }), "here: button.faces.primary.fill: expected color")
assert_eq("an xp face needs two stops", Bad({ button = { xp = { face = { "#000000" } } } }), "here: button.xp.face: expected at least 2 colours")
assert_eq("an xp colour must be a colour", Bad({ button = { xp = { glow = 5 } } }), "here: button.xp.glow: expected color")
assert_eq("a frame bevel is checked", Bad({ progress = { frame = { bevel = { light = "x" } } } }), "here: progress.frame.bevel.light: expected color")
assert_eq("a frame pad must be a number", Bad({ progress = { frame = { pad = "x" } } }), "here: progress.frame.pad: expected number")
assert_eq("a status bar text must be a string", Bad({ panel = { statusBar = { text = 5 } } }), "here: panel.statusBar.text: expected string")
assert_eq("a header caption mode is an enum", Bad({ header = { captions = "none" } }), "here: header.captions must be enum:all|close")
assert_eq("a header variant gains mac", Bad({ header = { variant = "mac", captions = "close" } }), "no error")
assert_eq("a button variant gains classic", Bad({ button = { variant = "classic" } }), "no error")
assert_eq("a motion field takes a boolean", Bad({ motion = { open = 1 } }), "here: motion.open must be boolean")

-- Defaults: the open, pop and shake motions are on unless a theme turns them off; light and dark do.
assert_eq("light turns open off", Style.Resolve("light").motion.open, false)
assert_eq("dark turns pop off", Style.Resolve("dark").motion.pop, false)
assert_eq("dark turns shake off", Style.Resolve("dark").motion.shake, false)
assert_eq("slate keeps open on", slate.motion.open, true)
assert_eq("slate keeps pop on", slate.motion.pop, true)
assert_eq("slate keeps shake on", slate.motion.shake, true)
assert_eq("slate sets no button height", slate.button.height, nil)
assert_eq("a bevel override fills the default width", Style.Resolve("slate", { panel = { bevel = { light = "#FFFFFF", dark = "#000000" } } }).panel.bevel.width, 1)
assert_eq("every new kind is in the field list", { Fields.types.panel.bevel, Fields.types.panel.statusBar, Fields.types.header.barStops, Fields.types.button.faces, Fields.types.button.xp, Fields.types.progress.frame }, { "bevel", "statusbar", "stops", "faces", "xpface", "frame" })

-- A header shows every caption control unless a theme says only the close control.
assert_eq("slate shows all captions", slate.header.captions, "all")
assert_eq("light shows all captions", Style.Resolve("light").header.captions, "all")

-- A fixed-key kind is a table of keys, so a non-empty array is rejected and an empty table is not.
assert_eq("a bevel list is rejected", Bad({ panel = { bevel = { "#000000" } } }), "here: panel.bevel: expected bevel")
assert_eq("a status bar list is rejected", Bad({ panel = { statusBar = { "x" } } }), "here: panel.statusBar: expected statusbar")
assert_eq("an xp face list is rejected", Bad({ button = { xp = { "x" } } }), "here: button.xp: expected xpface")
assert_eq("a frame list is rejected", Bad({ progress = { frame = { 1 } } }), "here: progress.frame: expected frame")
assert_eq("a faces list is rejected", Bad({ button = { faces = { "x" } } }), "here: button.faces: expected faces")
assert_eq("a face entry list is rejected", Bad({ button = { faces = { primary = { "x" } } } }), "here: button.faces.primary: expected table")
assert_eq("an empty bevel table is accepted", Bad({ panel = { bevel = {} } }), "no error")
assert_eq("an empty faces table is accepted", Bad({ button = { faces = {} } }), "no error")

-- Stage 3: the arrow button kind, the scroll type and the XP control fields.
assert_eq("an arrow face needs two stops", Bad({ field = { arrow = { face = { "#FFFFFF" } } } }), "here: field.arrow.face: expected at least 2 colours")
assert_eq("an arrow names an unknown key", Bad({ field = { arrow = { wobble = 1 } } }), "here: field.arrow.wobble is not a known field")
assert_eq("an arrow glyph must be a colour", Bad({ field = { arrow = { glyph = "#12" } } }), "here: field.arrow.glyph: expected color")
assert_eq("an arrow size must be a number", Bad({ field = { arrow = { size = "big" } } }), "here: field.arrow.size: expected number")
assert_eq("an arrow bevel is checked", Bad({ field = { arrow = { bevel = { light = "#12" } } } }), "here: field.arrow.bevel.light: expected color")
assert_eq("an arrow list is rejected", Bad({ field = { arrow = { "#000000" } } }), "here: field.arrow: expected arrowbutton")
assert_eq("an empty arrow table is accepted", Bad({ field = { arrow = {} } }), "no error")
assert_eq("a scroll colour must be a colour", Bad({ scroll = { thumb = 3 } }), "here: scroll.thumb must be color")
assert_eq("a scroll names an unknown field", Bad({ scroll = { wobble = 1 } }), "here: scroll.wobble is not a known field")
assert_eq("a scroll takes its fields", Bad({ scroll = { thumb = "#FF0000", thumbRadius = { 1, 2, 3, 4 }, width = 17 } }), "no error")
assert_eq("tabs gain the xp variant", Bad({ tabs = { variant = "xp" } }), "no error")
assert_eq("a slider gains the pointer variant", Bad({ slider = { variant = "pointer" } }), "no error")
assert_eq("the stepper takes arrows", Bad({ stepper = { arrows = true } }), "no error")
assert_eq("the stepper arrows field is a boolean", Bad({ stepper = { arrows = 1 } }), "here: stepper.arrows must be boolean")
assert_eq("a radio ring list needs two colours", Bad({ choice = { radioRings = { "#FFFFFF" } } }), "here: choice.radioRings: expected at least 2 colours")
assert_eq("a check face needs two colours", Bad({ toggle = { checkFace = { "#FFFFFF" } } }), "here: toggle.checkFace: expected at least 2 colours")
assert_eq("every new arrow field is in the field list", { Fields.types.field.arrow, Fields.types.scroll.thumbRadius, Fields.types.stepper.arrows }, { "arrowbutton", "radius", "boolean" })
assert_eq("light resolves no scroll type", Style.Resolve("light").scroll, nil)
assert_eq("dark resolves no scroll type", Style.Resolve("dark").scroll, nil)
assert_eq("slate resolves no scroll type", slate.scroll, nil)
assert_eq("a scroll override resolves", Style.Resolve("slate", { scroll = { thumb = "#FF0000" } }).scroll.thumb, { R = 1, G = 0, B = 0, A = 1 })
assert_eq("a scroll look borrow of an unset type is empty", Style.ForItem(slate, "scroll"), {})

-- An override of a fixed-key kind is merged key by key, and a look fills the same defaults as Resolve.
local lookBevel = Style.ForItem(slate, "field", { bevel = { light = "#FFFFFF", dark = "#000000" } })
assert_eq("a look bevel gets the default width", lookBevel.bevel.width, 1)