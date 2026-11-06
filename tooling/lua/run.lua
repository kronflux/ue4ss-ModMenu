--[[
  No-game Lua suite. C# injects _REPO (ModMenu repo root) and a require searcher.
  Prints one JSON object to stdout.
]]

local passed = 0
local failed = 0
local failures = {}
local tests = {}

-- JSON gives these characters a short escape; every other control byte below 0x20 uses \u00XX.
local namedEscapes = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\n"] = "\\n",
    ["\t"] = "\\t",
    ["\r"] = "\\r",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
}

-- The C# host parses the summary as JSON, so strings are quoted by JSON rules rather than with
-- Lua's %q, which writes a newline as a backslash followed by a raw newline.
local function escapeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local named = namedEscapes[c]
        if named then
            return named
        end
        local byte = c:byte()
        if byte < 0x20 then
            return string.format("\\u%04x", byte)
        end
        return c
    end) .. '"'
end

local function encode(value)
    local t = type(value)
    if value == nil then
        return "null"
    end
    if t == "boolean" then
        return value and "true" or "false"
    end
    if t == "number" then
        return tostring(value)
    end
    if t == "string" then
        return escapeString(value)
    end
    if t ~= "table" then
        return escapeString(tostring(value))
    end
    local max = 0
    local asObject = false
    for k in pairs(value) do
        if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
            asObject = true
            break
        end
        if k > max then
            max = k
        end
    end
    if not asObject then
        local parts = {}
        for i = 1, max do
            parts[i] = encode(value[i])
        end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(value) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        parts[#parts + 1] = encode(tostring(k)) .. ":" .. encode(value[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function deep_eq(a, b)
    if a == b then
        return true
    end
    if type(a) ~= type(b) then
        return false
    end
    if type(a) == "number" then
        local d = a - b
        if d < 0 then
            d = -d
        end
        return d < 1e-9
    end
    if type(a) ~= "table" then
        return false
    end
    for k, v in pairs(a) do
        if not deep_eq(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function record(name, ok, detail)
    tests[#tests + 1] = {
        name = name,
        ok = ok == true,
        detail = detail,
    }
    if ok then
        passed = passed + 1
        return
    end
    failed = failed + 1
    failures[#failures + 1] = name .. (detail and (": " .. detail) or "")
end

local function check(name, cond, detail)
    record(name, cond, detail)
end

function assert_true(name, cond)
    check(name, cond == true, cond == true and nil or "expected true")
end

function assert_eq(name, got, want)
    if deep_eq(got, want) then
        record(name, true)
        return
    end
    record(name, false, "got " .. encode(got) .. " want " .. encode(want))
end

local specs = {
    "store_spec.lua",
    "store_json_spec.lua",
    "store_paths_spec.lua",
    "dock_spec.lua",
    "options_spec.lua",
    "config_spec.lua",
    "run_json_spec.lua",
    "widgets_number_spec.lua",
    "theme_spec.lua",
    "style_spec.lua",
    "paint_spec.lua",
    "widgets_spec.lua",
    "widgets_slider_spec.lua",
    "widgets_stepper_spec.lua",
    "widgets_progress_spec.lua",
    "widgets_multiselect_spec.lua",
    "widgets_colorpicker_spec.lua",
    "widgets_radio_spec.lua",
    "widgets_button_spec.lua",
    "input_click_spec.lua",
    "itemstate_spec.lua",
    "widgets_label_spec.lua",
    "builder_export_spec.lua",
    "widgets_keybind_spec.lua",
    "persist_spec.lua",
    "persist_shell_spec.lua",
}

-- Specs reach the encoder through this global so they can check its JSON output directly.
_RUNNER = { encode = encode }

local here = _REPO .. "/tooling/lua/"
for i = 1, #specs do
    local path = here .. specs[i]
    local chunk, err = loadfile(path)
    if not chunk then
        check("load " .. specs[i], false, tostring(err))
    else
        local ok, runErr = pcall(chunk)
        if not ok then
            check("run " .. specs[i], false, tostring(runErr))
        end
    end
end

print(encode({
    ok = failed == 0,
    passed = passed,
    failed = failed,
    failures = failures,
    tests = tests,
}))

return failed == 0
