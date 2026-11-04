-- The keybind spec runs under MoonSharp without UE4SS globals, so it checks only the pure helpers and validate.
local Keybind = require("ModMenu.widgets.keybind")

assert_eq(
    "keybind parse splits a modifier from the key",
    Keybind._parse("LeftControl+F7"),
    { mods = { "LeftControl" }, key = "F7" }
)
assert_eq("keybind parse reads a bare key", Keybind._parse("F7"), { mods = {}, key = "F7" })
assert_eq("keybind parse of an empty string is nil", Keybind._parse(""), nil)
assert_eq("keybind parse of a non-string is nil", Keybind._parse(7), nil)
assert_eq("keybind parse of a trailing plus is nil", Keybind._parse("LeftControl+"), nil)
assert_eq("keybind parse of an unknown modifier is nil", Keybind._parse("Hyper+F7"), nil)
assert_eq("keybind parse of a modifier alone is nil", Keybind._parse("LeftShift"), nil)

-- Two sections in the registry's shape, with a keybind nested in a fold to show that the walk reaches children.
local sections = {
    {
        id = "Sec",
        items = {
            { type = "keybind", id = "jump", label = "Jump" },
            { type = "keybind", id = "dash", label = "Dash" },
            { type = "textinput", id = "name", label = "Name" },
        },
    },
    {
        id = "Other",
        items = {
            { type = "fold", id = "more", label = "More", items = {
                { type = "keybind", id = "fly", label = "Fly" },
            } },
        },
    },
}
local values = {
    ["Sec.jump"] = "F7",
    ["Sec.dash"] = "",
    ["Sec.name"] = "F8",
    ["Other.fly"] = "LeftControl+F9",
}

assert_eq("keybind conflict finds a sibling holding F7", Keybind._conflict(values, "Sec", "dash", "F7", sections), "jump")
assert_eq("keybind conflict ignores the item itself", Keybind._conflict(values, "Sec", "jump", "F7", sections), nil)
assert_eq("keybind conflict ignores a textinput holding the same text", Keybind._conflict(values, "Sec", "dash", "F8", sections), nil)
assert_eq(
    "keybind conflict finds a keybind inside a fold of another section",
    Keybind._conflict(values, "Sec", "dash", "LeftControl+F9", sections),
    "fly"
)
assert_eq("keybind conflict treats a different modifier as a different binding", Keybind._conflict(values, "Sec", "dash", "F9", sections), nil)
assert_eq("keybind conflict never reports an empty binding", Keybind._conflict(values, "Sec", "jump", "", sections), nil)

local function errorOf(item)
    local ok, err = pcall(Keybind.validate, item, "Sec", 1)
    if ok then
        return nil
    end
    return tostring(err)
end

local base = { type = "keybind", id = "k", label = "K" }
assert_true("keybind validate accepts a plain item", errorOf(base) == nil)
assert_true(
    "keybind validate accepts a modifier default",
    errorOf({ type = "keybind", id = "k", label = "K", default = "LeftAlt+G", allowModifiers = true }) == nil
)
local nonString = errorOf({ type = "keybind", id = "k", label = "K", default = 7 })
assert_true(
    "keybind validate errors on a non-string default",
    nonString ~= nil and string.find(nonString, "default must be", 1, true) ~= nil
)
local badName = errorOf({ type = "keybind", id = "k", label = "K", default = "Hyper+F7" })
assert_true(
    "keybind validate errors on a default that is not a key name",
    badName ~= nil and string.find(badName, "default must be", 1, true) ~= nil
)
local badConflict = errorOf({ type = "keybind", id = "k", label = "K", onConflict = true })
assert_true(
    "keybind validate errors on an onConflict that is not a function",
    badConflict ~= nil and string.find(badConflict, "onConflict must be a function", 1, true) ~= nil
)
local badMods = errorOf({ type = "keybind", id = "k", label = "K", allowModifiers = "yes" })
assert_true(
    "keybind validate errors on an allowModifiers that is not a boolean",
    badMods ~= nil and string.find(badMods, "allowModifiers must be a boolean", 1, true) ~= nil
)

local seeded = {}
Keybind.seed("Sec", { type = "keybind", id = "a", label = "A", default = "F2" }, seeded)
Keybind.seed("Sec", { type = "keybind", id = "b", label = "B" }, seeded)
assert_eq("keybind seed stores the default", seeded["Sec.a"], "F2")
assert_eq("keybind seed stores an empty binding without a default", seeded["Sec.b"], "")

-- core/input.lua exports the key helpers that the widget reads keys with.
-- Input requires UEHelpers at load, so an empty stub stands in when no earlier spec loaded it.
local stubbedForInput = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedForInput then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local Input = require("ModMenu.core.input")
if stubbedForInput then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
assert_true("core input exports MakeFKey", type(Input.MakeFKey) == "function")
assert_true("core input exports IsKeyDown", type(Input.IsKeyDown) == "function")
if type(Input.IsKeyDown) == "function" then
    local heldPc = {
        IsValid = function()
            return true
        end,
        IsInputKeyDown = function(_, fkey)
            return fkey.KeyName == "F7"
        end,
    }
    assert_eq("core input IsKeyDown reads a held key", Input.IsKeyDown(heldPc, { KeyName = "F7" }), true)
    assert_eq("core input IsKeyDown reads a key that is up", Input.IsKeyDown(heldPc, { KeyName = "F8" }), false)
end

-- A capture runs through poll with a fake ctx and a fake player controller.
-- Keys in held are down, and each scan clears nextScanAt so the 50 ms scan rate does not skip it.
local held = {}
local fakePc = {
    IsValid = function()
        return true
    end,
}
local function CaptureCtx(extra)
    local ctx = {
        values = { ["Sec.jump"] = "F7", ["Sec.dash"] = "" },
        liveControls = {},
        config = { keyName = "F6" },
        umg = { SetLabelText = function() end, SetFillColors = function() end, TrackPointer = function() end },
        IsValid = function(obj)
            return obj ~= nil
        end,
        SafeCall = function(fn, ...)
            if fn then
                fn(...)
            end
        end,
        Input = {
            ReleaseClick = function()
                return false
            end,
            ArmClick = function()
                return false, false
            end,
            MakeFKey = function(name)
                return { KeyName = name }
            end,
            IsKeyDown = function(_, fkey)
                return held[fkey.KeyName] == true
            end,
        },
    }
    for key, value in pairs(extra or {}) do
        ctx[key] = value
    end
    return ctx
end
local function CaptureCtrl()
    return {
        kind = "keybind",
        sectionId = "Sec",
        item = { type = "keybind", id = "dash", label = "Dash" },
        widget = {},
        valueKey = "Sec.dash",
        capturing = true,
    }
end
local function Press(ctrl, ctx, name)
    held = {}
    ctrl.nextScanAt = nil
    Keybind.poll(ctrl, ctx)
    held = { [name] = true }
    ctrl.nextScanAt = nil
    Keybind.poll(ctrl, ctx)
    held = {}
end

-- The spec host's os.clock gives no number, so a fixed fake clock paces the scan and is restored afterwards.
local clockBefore = Keybind._clock
Keybind._clock = function()
    return 0
end
local savedHelpers = package.loaded["UEHelpers.UEHelpers"]
package.loaded["UEHelpers.UEHelpers"] = {
    GetPlayerController = function()
        return fakePc
    end,
}

local toggleCtx = CaptureCtx({ sections = sections })
local toggleCtrl = CaptureCtrl()
Press(toggleCtrl, toggleCtx, "F6")
assert_eq("keybind capture refuses the menu toggle key", toggleCtx.values["Sec.dash"], "")
assert_true("keybind capture keeps listening after the toggle key", toggleCtrl.capturing == true)
Press(toggleCtrl, toggleCtx, "F8")
assert_eq("keybind capture binds a key after the toggle key was refused", toggleCtx.values["Sec.dash"], "F8")

-- A conflict is checked against the sections the ctx carries, so another shell's keybinds never refuse a binding.
local otherShell = {}
Keybind.seed("Ghost", { type = "keybind", id = "k", label = "K", default = "F5" }, otherShell)
local ownCtx = CaptureCtx({ sections = { sections[1] } })
ownCtx.values["Ghost.k"] = otherShell["Ghost.k"]
local ownCtrl = CaptureCtrl()
Press(ownCtrl, ownCtx, "F5")
assert_eq("keybind conflict ignores a keybind seeded by another shell", ownCtx.values["Sec.dash"], "F5")
local bareCtx = CaptureCtx()
bareCtx.values["Ghost.k"] = otherShell["Ghost.k"]
local bareCtrl = CaptureCtrl()
Press(bareCtrl, bareCtx, "F5")
assert_eq("keybind conflict without ctx sections ignores a keybind seeded by another shell", bareCtx.values["Sec.dash"], "F5")
local refuseCtx = CaptureCtx({ sections = sections })
local refuseCtrl = CaptureCtrl()
Press(refuseCtrl, refuseCtx, "F7")
assert_eq("keybind conflict with ctx sections refuses a binding a sibling holds", refuseCtx.values["Sec.dash"], "")

package.loaded["UEHelpers.UEHelpers"] = savedHelpers
Keybind._clock = clockBefore

-- The shell ends every capture when the menu closes, because poll stops while it is closed.
assert_true("Keybind._stopCapture is a function", type(Keybind._stopCapture) == "function")
if type(Keybind._stopCapture) == "function" then
    local closeCtrl = CaptureCtrl()
    local closeCtx = CaptureCtx({ liveControls = { closeCtrl } })
    closeCtrl.prevDown = { F8 = true }
    Keybind._stopCapture(closeCtx)
    assert_true("Keybind._stopCapture ends a capture", closeCtrl.capturing == false)
    assert_eq("Keybind._stopCapture forgets the held keys", closeCtrl.prevDown, nil)
end

local inList = {}
for _, name in ipairs(Keybind.CAPTURE_KEYS) do
    inList[name] = true
end
assert_true(
    "keybind capture keys hold letters, digits, function keys, arrows and modifiers",
    inList.A and inList.Z and inList.Zero and inList.Nine and inList.F1 and inList.F12
        and inList.Up and inList.Left and inList.LeftControl and inList.RightAlt and inList.RightShift
)
