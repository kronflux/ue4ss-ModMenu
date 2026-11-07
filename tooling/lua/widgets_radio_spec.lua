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

-- The choice variant: stock for light and dark, the resolved choice variant otherwise.
local Style = require("ModMenu.core.style")
local slate = Style.Resolve("slate")
assert_eq("light's radio variant is stock", Radio.Variant(Style.Resolve("light")), "stock")
assert_eq("dark's radio variant is stock", Radio.Variant(Style.Resolve("dark")), "stock")
assert_eq("slate's radio variant is its resolved choice variant", Radio.Variant(slate), slate.choice.variant)
assert_eq("no resolved theme is stock", Radio.Variant(nil), "stock")
assert_eq("an item look overrides the variant", Radio.Variant(slate, { variant = "chips" }), "chips")
assert_eq("the theme stays as resolved after an item look", Radio.Variant(slate), slate.choice.variant)

-- Caption colours per variant and state.
local cs, p = slate.choice, slate.palette
assert_eq("a chosen joined option uses the mark text", Radio._choiceTextColor(cs, p, "joined", true), cs.markText)
assert_eq("an unchosen joined option uses the text colour", Radio._choiceTextColor(cs, p, "joined", false), p.text)
assert_eq("an unchosen tab is muted", Radio._choiceTextColor(cs, p, "tabs", false), p.muted)
assert_eq("a chosen tab uses the mark fill when no tab text is set", Radio._choiceTextColor(cs, p, "tabs", true), cs.tabText or cs.markFill)
assert_eq("a radio option keeps the text colour when chosen", Radio._choiceTextColor(cs, p, "radio", true), p.text)
assert_eq("chips stand apart", Radio._choiceGap("chips"), 6)
assert_eq("joined options nearly touch", Radio._choiceGap("joined"), 2)

-- A themed group shows exactly one mark: the chosen option's.
local function fakeWidget()
    local w = { vis = nil }
    function w:SetVisibility(v)
        self.vis = v
    end
    function w:SetColorAndOpacity(c)
        self.color = c.SpecifiedColor
    end
    return w
end
local theme = { cs = cs, p = p, variant = "joined" }
local themedCtrl = { kind = "radio", item = item(), optionCtrls = {}, valueKey = "s.mode" }
for _, value in ipairs({ "a", "b", "c" }) do
    themedCtrl.optionCtrls[#themedCtrl.optionCtrls + 1] = {
        value = value,
        paint = {},
        marksOn = { fakeWidget() },
        marksOff = {},
        text = fakeWidget(),
        theme = theme,
        item = {},
    }
end
Radio.apply(themedCtrl, "b", {})
local opts = themedCtrl.optionCtrls
assert_eq("the chosen option's mark is shown", opts[2].marksOn[1].vis, 3)
assert_eq("an unchosen option's mark is hidden, keeping its layout", opts[1].marksOn[1].vis, 2)
assert_eq("the other unchosen mark is hidden", opts[3].marksOn[1].vis, 2)
assert_eq("the chosen caption takes the mark text", opts[2].text.color, cs.markText)
Radio.apply(themedCtrl, "c", {})
assert_eq("choosing another option hides the old mark", opts[2].marksOn[1].vis, 2)
assert_eq("and shows the new one", opts[3].marksOn[1].vis, 3)

-- Radio insides, built from a fake UMG: every widget records its class, name, children and calls.
do
    local Umg = require("ModMenu.core.umg")
    local created = {}
    local fakeMeta = {}
    local function Vivify()
        return setmetatable({}, {
            __index = function(t, k)
                local v = Vivify()
                rawset(t, k, v)
                return v
            end,
        })
    end
    fakeMeta.__index = function(self, key)
        if key == "IsValid" then
            return function()
                return true
            end
        end
        local isMethod = key:match("^AddChild") or key:match("^Set") or key:match("^Is") or key:match("^Get")
        if key:match("^%u") and not isMethod then
            local v = Vivify()
            rawset(self, key, v)
            return v
        end
        return function(w, ...)
            local args = { ... }
            w.calls[#w.calls + 1] = { key, args }
            if key == "SetVisibility" then
                w.visibility = args[1]
            end
            if key:match("^AddChildTo") or key == "SetContent" then
                w.children[#w.children + 1] = args[1]
                local slot = setmetatable({ calls = {}, children = {} }, fakeMeta)
                if rawget(w, "slotOf") == nil then
                    rawset(w, "slotOf", {})
                end
                rawget(w, "slotOf")[args[1]] = slot
                return slot
            end
            return nil
        end
    end
    local realConstruct, realFName, realFindObject = StaticConstructObject, FName, StaticFindObject
    StaticFindObject = function(path)
        return { path = path, IsValid = function() return true end }
    end
    FName = function(n)
        return n
    end
    StaticConstructObject = function(cls, _outer, name)
        local w = setmetatable({ class = cls.path, name = name, calls = {}, children = {} }, fakeMeta)
        created[#created + 1] = w
        return w
    end

    local function Named(pattern)
        local out = {}
        for _, w in ipairs(created) do
            if w.name:find(pattern) then
                out[#out + 1] = w
            end
        end
        return out
    end
    local function WidthOf(w)
        for _, call in ipairs(w.calls) do
            if call[1] == "SetWidthOverride" then
                return call[2][1]
            end
        end
        return nil
    end
    local function Hex(c) return Style.Hex(c) end

    local function BuildOption(choice)
        created = {}
        local base = { variant = "radio", markFill = Hex("#2C62F6"), markText = Hex("#FFFFFF") }
        for k, v in pairs(choice) do
            base[k] = v
        end
        local theme = { variant = "radio", cs = base, p = { text = Hex("#000000") }, size = 12, hintSize = 10 }
        local opt = Radio._buildOption(Umg, nil, "R", "Caption", theme, function() end)
        return opt
    end

    local rings = { Hex("#1C5180"), Hex("#E0E0DA"), Hex("#FFFFFF") }
    local opt = BuildOption({ radioRings = rings, radioHoverRing = Hex("#F9A63A") })
    local circles = Named("_Ring%d+$")
    assert_eq("a radio with 3 rings has 3 circle Borders", #circles, 3)
    for _, w in ipairs(circles) do
        assert_eq("a ring is a Border: " .. w.name, w.class, "/Script/UMG.Border")
    end
    local sizes = Named("_Ring%d+_Size$")
    assert_eq("each ring has a size", #sizes, 3)
    local w1, w2, w3 = WidthOf(sizes[1]), WidthOf(sizes[2]), WidthOf(sizes[3])
    assert_true("the rings shrink", w1 ~= nil and w2 ~= nil and w3 ~= nil and w1 > w2 and w2 > w3)
    assert_eq("each ring is inset 2 more units a side than the last", { w1 - w2, w2 - w3 }, { 4, 4 })
    assert_eq("the radio has one hover ring", #Named("_RadioHover$"), 1)
    local ring = Named("_RadioHover$")[1]
    assert_true("the radio has a hover ring to inspect", ring ~= nil)
    if ring ~= nil then
        assert_eq("the radio hover ring is hidden at rest", ring.visibility, 2)
        rawset(opt.widget, "IsHovered", function() return true end)
        local ctx = { Input = { ReleaseClick = function() return false end } }
        Radio._pollOption(opt, ctx)
        assert_eq("the radio hover ring is shown after a hover poll", ring.visibility, 3)
        rawset(opt.widget, "IsHovered", function() return false end)
        Radio._pollOption(opt, ctx)
        assert_eq("the radio hover ring is hidden when the pointer leaves", ring.visibility, 2)
    end

    -- The outermost ring carries the radio edge, and only when the style sets one.
    local edgeColor = Hex("#003C74")
    BuildOption({ radioRings = rings, radioEdge = edgeColor })
    local edgeOutline = Named("_Ring1$")[1].Background.OutlineSettings
    assert_eq("an edged radio's first ring is outlined 1 wide", edgeOutline.Width, 1)
    assert_eq("an edged radio's first ring is outlined in radioEdge", edgeOutline.Color.SpecifiedColor, edgeColor)
    assert_eq("an edged radio's second ring has no outline", Named("_Ring2$")[1].Background.OutlineSettings.Width, 0)
    BuildOption({ radioRings = rings })
    assert_eq("without radioEdge the first ring has no outline", Named("_Ring1$")[1].Background.OutlineSettings.Width, 0)

    BuildOption({ radioBevel = { light = Hex("#FFFFFF"), dark = Hex("#808080"), width = 1 } })
    local dark, light = Named("_RadioBevelDark$"), Named("_RadioBevelLight$")
    assert_true("a radio bevel draws an outer dark circle and an inner light circle", #dark == 1 and #light == 1)
    assert_eq("the dark circle is shown hit-test invisible", dark[1].visibility, 3)
    assert_eq("the light circle is shown hit-test invisible", light[1].visibility, 3)
    local function PadOf(parent, child)
        local slots = rawget(parent, "slotOf")
        local slot = slots and slots[child]
        for _, call in ipairs(slot and slot.calls or {}) do
            if call[1] == "SetPadding" then
                local m = call[2][1]
                return { m.Left, m.Top, m.Right, m.Bottom }
            end
        end
        return nil
    end
    local bevelRing = Named("_Ring$")[1]
    assert_eq("the dark circle fills the ring", PadOf(bevelRing, dark[1]), { 0, 0, 0, 0 })
    assert_eq("the light circle is offset 1 down and right", PadOf(bevelRing, light[1]), { 1, 1, 0, 0 })

    -- With both a bevel and rings, the rings sit inside the bevel and are centred on the light circle.
    BuildOption({ radioBevel = { light = Hex("#FFFFFF"), dark = Hex("#808080"), width = 1 },
        radioRings = { Hex("#FFFFFF"), Hex("#EEEEEE") } })
    local both = Named("_Ring$")[1]
    local bothSizes = Named("_Ring%d+_Size$")
    assert_eq("with a bevel, the first ring is 10 wide", WidthOf(bothSizes[1]), 10)
    assert_eq("with a bevel, the second ring is 6 wide", WidthOf(bothSizes[2]), 6)
    assert_eq("with a bevel, the ring is centred on the light circle", PadOf(both, bothSizes[1]), { 1, 1, 0, 0 })
    assert_eq("with a bevel, the dot is centred on the light circle", PadOf(both, Named("_DotSize$")[1]), { 1, 1, 0, 0 })
    assert_eq("with a bevel, the ring size is shown hit-test invisible", bothSizes[1].visibility, 3)

    -- A disabled radio hides the hover ring and shows its normal look.
    local hoverOpt = BuildOption({ radioRings = rings, radioHoverRing = Hex("#F9A63A") })
    rawset(hoverOpt.widget, "IsHovered", function() return true end)
    local pollCtx = { Input = { ReleaseClick = function() return false end } }
    Radio._pollOption(hoverOpt, pollCtx)
    assert_eq("a hovered option shows its ring", hoverOpt.hoverRing.visibility, 3)
    Radio.onItemState({ optionCtrls = { hoverOpt } }, false, true, {})
    assert_eq("disabling the radio hides the hover ring", hoverOpt.hoverRing.visibility, 2)
    assert_eq("disabling the radio shows the normal state", hoverOpt.paint.lastState, "normal")
    Radio.onItemState({ optionCtrls = { hoverOpt } }, true, true, {})
    assert_eq("enabling the radio leaves the ring to the poll", hoverOpt.hoverRing.visibility, 2)

    BuildOption({})
    assert_eq("without the new fields there are no ring circles", #Named("_Ring%d+$"), 0)
    assert_eq("without the new fields there is no hover ring", #Named("_RadioHover$"), 0)
    assert_eq("without the new fields there is no bevel", #Named("_RadioBevel"), 0)
    assert_eq("without the new fields the off ring is built as today", #Named("_RingOff$"), 1)
    assert_eq("without the new fields the on ring is built as today", #Named("_RingOn$"), 1)

    StaticConstructObject, FName, StaticFindObject = realConstruct, realFName, realFindObject
end
