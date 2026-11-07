local Umg = require("ModMenu.core.umg")

-- A fake ScrollBox: setters record the thickness, WidgetBarStyle is a table of plain brush tables.
local function Fake()
    local function brush()
        return {
            TintColor = { SpecifiedColor = nil, ColorUseRule = 9 },
            ImageSize = { X = 0, Y = 0 },
            DrawAs = 0,
            OutlineSettings = { CornerRadii = nil, Color = { SpecifiedColor = nil, ColorUseRule = 9 }, Width = 0, RoundingType = 0 },
        }
    end
    local scroll = {
        thickness = nil,
        WidgetBarStyle = {
            NormalThumbImage = brush(),
            HoveredThumbImage = brush(),
            DraggedThumbImage = brush(),
            VerticalBackgroundImage = brush(),
            HorizontalBackgroundImage = brush(),
        },
    }
    function scroll:SetScrollbarThickness(v)
        self.thickness = v.X
    end
    return scroll
end

local red = { R = 1, G = 0, B = 0, A = 1 }
local blue = { R = 0, G = 0, B = 1, A = 1 }
local green = { R = 0, G = 1, B = 0, A = 1 }
local grey = { R = 0.5, G = 0.5, B = 0.5, A = 1 }

local themed = Fake()
Umg.StyleScrollBox(themed, { resolved = { scroll = { thumb = red, thumbHover = blue, track = green, thumbEdge = grey, thumbRadius = 4, width = 17 } } })
local style = themed.WidgetBarStyle
assert_eq("scroll: the thumb tint is red", style.NormalThumbImage.TintColor.SpecifiedColor, red)
assert_eq("scroll: the thumb is a rounded box", style.NormalThumbImage.DrawAs, 4)
assert_eq("scroll: the hovered thumb takes thumbHover", style.HoveredThumbImage.TintColor.SpecifiedColor, blue)
assert_eq("scroll: the dragged thumb takes thumbHover", style.DraggedThumbImage.TintColor.SpecifiedColor, blue)
assert_eq("scroll: the track takes track", style.VerticalBackgroundImage.TintColor.SpecifiedColor, green)
assert_eq("scroll: the thumb carries the edge colour", style.NormalThumbImage.OutlineSettings.Color.SpecifiedColor, grey)
local radii = style.NormalThumbImage.OutlineSettings.CornerRadii or {}
assert_eq("scroll: the thumb carries the radius", radii["X"], 4)
assert_eq("scroll: width sets the thickness", themed.thickness, 17)
assert_eq("scroll: the thumb edge is 1 wide", style.NormalThumbImage.OutlineSettings.Width, 1)
assert_eq("scroll: the track has no edge", style.VerticalBackgroundImage.OutlineSettings.Width, 0)

for _, w in ipairs({ 0, 0.5, -3 }) do
    local small = Fake()
    Umg.StyleScrollBox(small, { resolved = { scroll = { thumb = red, width = w } } })
    assert_eq("scroll: width " .. w .. " keeps 8", small.thickness, 8)
end

local fallback = Fake()
Umg.StyleScrollBox(fallback, { resolved = { scroll = { thumb = red } } })
assert_eq("scroll: hover falls back to thumb", fallback.WidgetBarStyle.HoveredThumbImage.TintColor.SpecifiedColor, red)
assert_eq("scroll: no width keeps 8", fallback.thickness, 8)

local touch = Fake()
Umg.StyleScrollBox(touch, { pointerMode = "touch", resolved = { scroll = { thumb = red, width = 17 } } })
assert_eq("scroll: touch keeps 28", touch.thickness, 28)

local plain = Fake()
Umg.StyleScrollBox(plain, { resolved = {} })
assert_eq("scroll: unset keeps thickness 8", plain.thickness, 8)
assert_eq("scroll: unset leaves the thumb draw type", plain.WidgetBarStyle.NormalThumbImage.DrawAs, 0)
assert_eq("scroll: unset leaves the thumb tint", plain.WidgetBarStyle.NormalThumbImage.TintColor.SpecifiedColor, nil)
assert_eq("scroll: unset only resizes the brush", plain.WidgetBarStyle.NormalThumbImage.ImageSize.X, 8)
