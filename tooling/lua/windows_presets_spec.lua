-- AC-2: every sample point of every Windows preset in tooling/lua/fixtures/windows-reference.json
-- must equal the resolved style value it names, within 3 per channel (0 to 255).
-- tools/sample-reference.ps1 writes the fixture from the user's screenshots.
local okStyle, Style = pcall(require, "ModMenu.core.style")
assert_true("core.style loads under MoonSharp", okStyle)
if not okStyle then
    return
end
local Json = require("ModMenu.store.json")

local TOLERANCE = 3

local function ReadFixture()
    local f = io.open(_REPO .. "/tooling/lua/fixtures/windows-reference.json", "r")
    if f == nil then
        return nil
    end
    local text = f:read("*a")
    f:close()
    return Json.Decode(text)
end

-- The inverse of the sRGB to linear curve that Style.Hex applies.
local function ToByte(linear)
    local c = linear
    if c <= 0.0031308 then
        c = c * 12.92
    else
        c = 1.055 * (c ^ (1 / 2.4)) - 0.055
    end
    return math.floor(c * 255 + 0.5)
end

local function ParseHex(hex)
    local r, g, b = tostring(hex):match("^#(%x%x)(%x%x)(%x%x)$")
    if r == nil then
        return nil
    end
    return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

local function Hex(bytes)
    return string.format("#%02X%02X%02X", bytes[1], bytes[2], bytes[3])
end

-- A path such as "header.barStops[2]" or "button.xp.edge": dotted keys, with [n] a 1-based index.
local function GetPath(root, path)
    local node = root
    for segment in path:gmatch("[^%.]+") do
        local key, index = segment:match("^([%w_]+)%[(%d+)%]$")
        if type(node) ~= "table" then
            return nil
        end
        if key ~= nil then
            node = node[key]
            if type(node) ~= "table" then
                return nil
            end
            node = node[tonumber(index)]
        else
            node = node[segment]
        end
    end
    return node
end

local fixture = ReadFixture()
assert_true("windows-reference.json is readable", fixture ~= nil)
if fixture == nil then
    return
end

local ids = {}
for id in pairs(fixture) do
    ids[#ids + 1] = id
end
table.sort(ids)

for _, id in ipairs(ids) do
    local ok, resolved = pcall(Style.Resolve, id)
    assert_true(id .. " resolves", ok)
    if ok then
        for _, point in ipairs(fixture[id]) do
            local label = string.format("%s %s (%s) %s", id, point.name, point.field, point.color)
            local want = ParseHex(point.color)
            local value = GetPath(resolved, point.field)
            if type(value) ~= "table" or value.R == nil then
                assert_eq(label, point.field .. " is " .. type(value), "a colour")
            else
                local got = { ToByte(value.R), ToByte(value.G), ToByte(value.B) }
                local worst = 0
                for i = 1, 3 do
                    worst = math.max(worst, math.abs(got[i] - want[i]))
                end
                if worst <= TOLERANCE then
                    assert_true(label, true)
                else
                    assert_eq(label, Hex(got), Hex(want))
                end
            end
        end
    end
end

-- Each of the eight Windows presets has a table in the fixture, with at least 12 points.
local WINDOWS_IDS = {
    "xp-luna", "xp-luna-silver", "xp-luna-olive", "xp-embedded", "xp-royale", "xp-royale-noir", "xp-zune",
    "windows-classic",
}
for _, id in ipairs(WINDOWS_IDS) do
    assert_true(id .. " has at least 12 sample points", type(fixture[id]) == "table" and #fixture[id] >= 12)
end
