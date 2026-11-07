-- Specs for the XP tab strip: the selected tab's top line and extra height, the line a hovered tab
-- shows, and that every other tabs variant keeps the tree it has today. The strip is built on fake
-- widgets that record their calls, so no engine is needed.
local stubbedUEHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local Tabs = require("ModMenu.shell.tabs")
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end

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
local function NewSlot()
    return setmetatable({ calls = {}, children = {}, slots = {} }, fakeMeta)
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
        if key == "IsHovered" then
            return w.hovered == true
        end
        if key:match("^AddChildTo") or key == "SetContent" then
            local slot = NewSlot()
            w.children[#w.children + 1] = args[1]
            w.slots[#w.slots + 1] = slot
            return slot
        end
        return nil
    end
end
local realConstruct, realFName, realFindObject = StaticConstructObject, FName, StaticFindObject
local realFText = FText
StaticFindObject = function(path)
    return { path = path, IsValid = function() return true end }
end
FName = function(n)
    return n
end
FText = function(s)
    return s
end
StaticConstructObject = function(cls, outer, name)
    local w = setmetatable({ class = cls.path, name = name, calls = {}, children = {}, slots = {} }, fakeMeta)
    created[#created + 1] = w
    return w
end

local function Color(r, g, b)
    return { R = r, G = g, B = b, A = 1 }
end

local function Strip(variant, active)
    created = {}
    local look = { variant = variant, radius = 3, markFill = Color(1, 1, 1), edge = Color(0, 0, 0.5),
        faceStops = { Color(1, 1, 1), Color(0.9, 0.9, 0.8) }, markLine = Color(1, 0.7, 0.2),
        markLineStops = { Color(1, 0.8, 0.3), Color(0.9, 0.6, 0.1) } }
    local S = {
        config = {
            tabs = { "General", "Display", "Advanced" },
            pointerMode = "desktop",
            spacing = { tabHeight = 56, tabGap = 4, tabGapTouch = 8, tabPad = 8, tabPadTouch = 12 },
            fontItem = 14,
            resolved = {
                palette = { text = Color(0, 0, 0), muted = Color(0.4, 0.4, 0.4), accent = Color(0, 0, 1),
                    surface = Color(0.9, 0.9, 0.9), line = Color(0.5, 0.5, 0.5), accentText = Color(1, 1, 1) },
                body = {},
                tabs = look,
            },
        },
        activeTab = active,
        liveControls = {},
    }
    local contentBox = StaticConstructObject({ path = "/Script/UMG.VerticalBox" }, nil, "Content")
    Tabs.BuildStrip(S, contentBox, "t")
    return S, contentBox
end

local function Find(suffix)
    local out = {}
    for _, w in ipairs(created) do
        if w.name:sub(-#suffix) == suffix then
            out[#out + 1] = w
        end
    end
    return out
end

local function CallArg(widget, key)
    for _, call in ipairs(widget.calls) do
        if call[1] == key then
            return call[2][1]
        end
    end
    return nil
end

-- The height a tab's stack adds up to: fixed SizeBox heights plus the padding of the other slots.
local function TabHeight(tabIndex)
    local stack = Find("ModMenu_Tab" .. tabIndex .. "_t_Stack")[1]
    local total = 0
    for i, child in ipairs(stack.children) do
        local fixed = CallArg(child, "SetHeightOverride")
        local pad = CallArg(stack.slots[i], "SetPadding")
        if fixed ~= nil then
            total = total + fixed
        elseif pad ~= nil then
            total = total + (pad.Top or 0) + (pad.Bottom or 0)
        end
    end
    return total
end

local S = Strip("xp", "Display")
local lines = Find("_XpLine")
assert_eq("xp: one top line per tab", #lines, 3)
assert_eq("xp: the selected tab's line is shown, hit-test invisible", lines[2].visibility, 3)
assert_eq("xp: an unselected tab's line is hidden", lines[1].visibility, 2)
assert_eq("xp: the last tab's line is hidden", lines[3].visibility, 2)
assert_eq("xp: the line is 3 units tall", CallArg(lines[2], "SetHeightOverride"), 3)
assert_eq("xp: the selected tab is 2 units taller", TabHeight(2) - TabHeight(1), 2)
assert_eq("xp: the unselected tabs share one height", TabHeight(1), TabHeight(3))
assert_eq("xp: three live tab controls", #S.liveControls, 3)
assert_eq("xp: the selected tab covers its bottom edge", #Find("ModMenu_Tab2_t_XpJoin"), 1)
assert_eq("xp: an unselected tab has no cover", #Find("ModMenu_Tab1_t_XpJoin"), 0)

-- A hover on tab 3 shows its line, and leaving hides it. The selected tab keeps its line.
local third = S.liveControls[3]
third.widget.hovered = true
Tabs.Poll(S, third)
assert_eq("xp hover: the hovered tab shows its line", lines[3].visibility, 3)
third.widget.hovered = false
Tabs.Poll(S, third)
assert_eq("xp hover: leaving hides the line again", lines[3].visibility, 2)
Tabs.Poll(S, S.liveControls[2])
assert_eq("xp hover: the selected tab keeps its line at rest", lines[2].visibility, 3)

-- Every tab is shapes shown and hidden, so nothing rounded or outlined is recoloured.
assert_true("xp: tabs are shape buttons", S.liveControls[1].flat == false and S.liveControls[2].flat == false)
local recoloured = false
for _, w in ipairs(created) do
    if w.class:find("Border", 1, true) and (w.name:match("_normal$") or w.name:match("_hover$")
        or w.name:match("_pressed$") or w.name:match("_edge$")) then
        for _, call in ipairs(w.calls) do
            if call[1] == "SetBrushColor" then
                recoloured = true
            end
        end
    end
end
assert_eq("xp: no tab shape is recoloured", recoloured, false)

-- Any other variant builds the tree it builds today.
Strip("tabs", "Display")
assert_eq("tabs variant: no XP line widget", #Find("_XpLine"), 0)
assert_eq("tabs variant: no XP join cover", #Find("_XpJoin"), 0)
Strip("joined", "Display")
assert_eq("joined variant: no XP line widget", #Find("_XpLine"), 0)
assert_eq("joined variant: no XP pane edge", #Find("_XpPaneEdge"), 0)

-- XP tabs fit their caption and sit left-aligned with no gap; every other strip keeps fill slots.
do
    Strip("xp", "Display")
    local row = Find("ModMenu_Tabs_t")[1]
    assert_eq("xp slots: three tab slots", #row.slots, 3)
    for i, slot in ipairs(row.slots) do
        assert_eq("xp slots: tab " .. i .. " is auto sized", CallArg(slot, "SetSize").SizeRule, 0)
        assert_eq("xp slots: tab " .. i .. " is left-aligned", CallArg(slot, "SetHorizontalAlignment"), 1)
        assert_eq("xp slots: tab " .. i .. " has no gap", CallArg(slot, "SetPadding").Left, 0)
    end
    local label = Find("ModMenu_Tab1_t_Stack")[1].slots[2]
    local pad = CallArg(label, "SetPadding")
    assert_eq("xp slots: the caption has 6 units each side", { pad.Left, pad.Right }, { 6, 6 })
    Strip("tabs", "Display")
    row = Find("ModMenu_Tabs_t")[1]
    for i, slot in ipairs(row.slots) do
        assert_eq("tabs slots: tab " .. i .. " keeps a fill slot", CallArg(slot, "SetSize").SizeRule, 1)
    end
    assert_eq("tabs slots: the gap is kept", CallArg(row.slots[2], "SetPadding").Left, 4)
end

-- BuildContent adds the strip and then asks for the pane, and nothing sits between them.
do
    local xpS, xpBox = Strip("xp", "Display")
    local inner = Tabs.BuildPane(xpS, xpBox, "t")
    assert_eq("xp order: the strip and the pane are the only children", #xpBox.children, 2)
    assert_true("xp order: the strip comes first", xpBox.children[1].name:match("^ModMenu_TabsXp_") ~= nil)
    assert_true("xp order: the pane follows it", xpBox.children[2].name:match("_XpPane$") ~= nil)
    assert_eq("xp order: no tab pad spacer in the content box", #Find("ModMenu_TabPad_t"), 0)
    assert_eq("xp order: the gap is inside the pane", #Find("_XpPane_TopPad"), 1)
    assert_eq("xp order: the pane edge is hit-test invisible", Find("_XpPaneEdge")[1].visibility, 3)
    local _, plainBox = Strip("tabs", "Display")
    assert_eq("tabs order: strip and tab pad spacer are kept", #plainBox.children, 2)
    assert_eq("tabs order: the spacer is still there", #Find("ModMenu_TabPad_t"), 1)
end

-- In touch mode every tab has a minimum height, and the selected XP tab is 2 above it.
do
    local xpS = Strip("xp", "Display")
    xpS.config.pointerMode = "touch"
    created = {}
    local box = StaticConstructObject({ path = "/Script/UMG.VerticalBox" }, nil, "Content")
    Tabs.BuildStrip(xpS, box, "t")
    local heights = {}
    for i = 1, 3 do
        heights[i] = CallArg(Find("ModMenu_TabSize" .. i .. "_t")[1], "SetMinDesiredHeight")
    end
    assert_eq("xp touch: unselected tabs keep the minimum height", heights[1], 56)
    assert_eq("xp touch: the selected tab is 2 taller", heights[2], 58)
    assert_eq("xp touch: the last tab keeps the minimum height", heights[3], 56)
end

-- The pane under an XP strip is outlined on its left, right and bottom, shown so clicks pass through.
do
    local xpS, xpBox = Strip("xp", "Display")
    local inner = Tabs.BuildPane(xpS, xpBox, "t")
    local pane = Find("_XpPane")[1]
    assert_true("xp pane: an outlined pane widget is built", pane ~= nil)
    assert_true("xp pane: the content goes into the pane's box", inner ~= xpBox and inner.name:match("_XpPane_Content$") ~= nil)
    for _, edge in ipairs({ "Left", "Right", "Bottom" }) do
        local w = Find("_XpPane_" .. edge)[1]
        assert_true("xp pane: " .. edge:lower() .. " edge exists", w ~= nil)
        assert_eq("xp pane: " .. edge:lower() .. " edge is hit-test invisible", w and w.visibility, 3)
    end
    assert_eq("xp pane: no top edge of its own", #Find("_XpPane_Top"), 0)
    for _, variant in ipairs({ "tabs", "joined", "chips" }) do
        local otherS, otherBox = Strip(variant, "Display")
        local before = #created
        assert_true(variant .. " pane: contentBox comes back unchanged", Tabs.BuildPane(otherS, otherBox, "t") == otherBox)
        assert_eq(variant .. " pane: builds no widget", #created, before)
        assert_eq(variant .. " pane: no pane widget", #Find("_XpPane"), 0)
    end
end

StaticConstructObject, FName, StaticFindObject, FText = realConstruct, realFName, realFindObject, realFText
