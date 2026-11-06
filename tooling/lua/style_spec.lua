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
        local ok, resolved = pcall(Style.Resolve, input.theme, input.style, input.colors)
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
        local entry = resolved[typeName]
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
            local v = resolved[typeName][field]
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

-- Stage 1 ships light, dark and the 27 StyleLab presets; the loop above resolves each of them.
local ids = Style.Ids()
assert_eq("Ids holds the 29 stage 1 presets", #ids, 29)
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
