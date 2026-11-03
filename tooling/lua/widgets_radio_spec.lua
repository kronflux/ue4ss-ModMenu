-- The radio widget is tested through validate, seed, apply's check and _resolve, because building and
-- painting the option buttons needs UMG, which MoonSharp does not have.
local okRadio, Radio = pcall(require, "ModMenu.widgets.radio")
assert_true("widgets.radio loads under MoonSharp", okRadio)
if not okRadio then
    return
end

local function item(fields)
    local base = { id = "mode", label = "Mode", options = { "a", { label = "Bee", value = "b" }, "c" } }
    for key, value in pairs(fields or {}) do
        base[key] = value
    end
    return base
end

local function errorOf(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then
        return nil
    end
    return tostring(err)
end

local function mentions(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end

assert_true("validate accepts a radio item with options", pcall(Radio.validate, item(), "s", 1))
assert_true("validate accepts a default that is one of the options", pcall(Radio.validate, item({ default = "b" }), "s", 1))

local missing = item()
missing.options = nil
assert_true("validate errors on missing options", mentions(errorOf(Radio.validate, missing, "s", 1), "radio requires an .options array"))
assert_true(
    "validate errors on empty options",
    mentions(errorOf(Radio.validate, item({ options = {} }), "s", 1), "radio requires at least one option")
)
assert_true(
    "validate errors on a default not in the options",
    mentions(errorOf(Radio.validate, item({ default = "z" }), "s", 1), "default must be one of a, b, c")
)
assert_true(
    "validate errors on a non-function onChange",
    mentions(errorOf(Radio.validate, item({ onChange = 1 }), "s", 1), "onChange must be a function")
)
assert_true(
    "validate errors on a non-boolean inline",
    mentions(errorOf(Radio.validate, item({ inline = "yes" }), "s", 1), "inline must be a boolean")
)

assert_eq("_resolve returns the option for a listed value", Radio._resolve("b", item()), { label = "Bee", value = "b" })
assert_eq("_resolve returns nil for a value not in the options", Radio._resolve("z", item()), nil)
assert_eq("_resolve returns nil for nil", Radio._resolve(nil, item()), nil)

local values = {}
Radio.seed("s", item({ default = "c" }), values)
assert_eq("seed stores the default", values["s.mode"], "c")

-- A Set before Register can leave a value the options do not hold, so seed replaces it with the default.
local early = { ["s.mode"] = "z" }
Radio.seed("s", item({ default = "a" }), early)
assert_eq("seed replaces a value set before Register that is not an option", early["s.mode"], "a")

-- apply checks the value before it paints, so the error is reached without UMG.
local ctrl = { kind = "radio", item = item(), optionCtrls = {}, valueKey = "s.mode" }
assert_true(
    "apply errors on a value not in the options",
    mentions(errorOf(Radio.apply, ctrl, "z", {}), "radio mode: value must be one of a, b, c")
)
