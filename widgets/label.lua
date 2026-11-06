--[[
  ModMenu widget: label

  Presentation: align (left, center, right), wrap (default true) and style (normal, muted, heading,
  warning). The style picks the font size and colour from the theme.

  A theme whose section variant is stock, as light and dark are, draws labels as the library always
  has, unless the host overrides body, hint or section in its style. Any other theme draws them from
  its resolved text styles through Label.TextSpec. An item's look and a host's style override take
  effect on every theme, so an explicit choice always shows.
]]

local Label = {}
Label.type = "label"

local Theme = require("ModMenu.core.theme")
local Paint = require("ModMenu.core.paint")
local Style = require("ModMenu.core.style")

-- The font size key and colour key each style reads from the config and the theme.
local STYLES = {
    normal = { size = "fontHint", color = "textPrimary" },
    muted = { size = "fontHint", color = "textMuted" },
    heading = { size = "fontSection", color = "textAccent" },
    warning = { size = "fontHint", color = "textStatus" },
}

-- ETextJustify: Left 0, Center 1, Right 2.
local JUSTIFY = { left = 0, center = 1, right = 2 }

--- The font size and colour for an item's style. Normal is the default.
---@return table size and color
function Label._style(item, config, colors)
    local keys = STYLES[item.style or "normal"] or STYLES.normal
    return { size = config[keys.size], color = colors[keys.color] }
end

-- The config size key each style falls back to when its text style sets no size.
local SIZE_KEYS = { normal = "fontHint", muted = "fontHint", heading = "fontSection", warning = "fontHint" }

local function Copy(t)
    local out = {}
    for k, v in pairs(t or {}) do
        out[k] = v
    end
    return out
end

--- The text style a label style draws with, from a resolved theme: normal is body, muted is body
--- in palette.muted, heading is section.text, and warning is body in palette.warning. The result is
--- a new table, so a caller may change it without touching the resolved theme.
---@param resolved table
---@param styleName string|nil
---@return table
function Label.TextSpec(resolved, styleName)
    local name = styleName or "normal"
    if name == "heading" then
        return Copy(resolved.section and resolved.section.text)
    end
    local spec = Copy(resolved.body)
    if name == "muted" then
        spec.color = resolved.palette.muted
    elseif name == "warning" then
        spec.color = resolved.palette.warning
    end
    return spec
end

-- The style override types that change how labels draw: body for normal, muted and warning,
-- section for headings, and hint, which the ruling counts with them so a host's text overrides
-- move labels and separators off the stock path together.
local TEXT_OVERRIDES = { "body", "hint", "section" }

--- True when the host's style override names a text type labels follow.
---@param style table|nil config.style, the host's merged overrides
---@return boolean
function Label.Overridden(style)
    if type(style) ~= "table" then
        return false
    end
    for _, typeName in ipairs(TEXT_OVERRIDES) do
        if style[typeName] ~= nil then
            return true
        end
    end
    return false
end

-- The field names a host override sets on a label style's text, as a set. A preset id or a
-- `from` replaces the whole type, so every field of the resolved text counts as set. A section
-- override sets heading text through its text table, and through color, which the resolver uses
-- as the text colour when the text table names none.
local function OverriddenFields(override, source, heading)
    local fields = {}
    if type(override) == "string" or (type(override) == "table" and override.from ~= nil) then
        for k in pairs(source) do
            fields[k] = true
        end
        return fields
    end
    if type(override) ~= "table" then
        return fields
    end
    if heading then
        if type(override.text) == "table" then
            for k in pairs(override.text) do
                fields[k] = true
            end
        end
        if override.color ~= nil then
            fields.color = true
        end
        return fields
    end
    for k in pairs(override) do
        fields[k] = true
    end
    return fields
end

--- The text style of a label on a stock theme, as light and dark are. The base is the label's
--- legacy colour and no theme size, so it draws as it always has, and the fields the host's style
--- override sets for this label style are taken from the resolved theme over it. Muted and warning
--- labels keep their legacy colour under a body colour override, because on any theme their colour
--- comes from the palette and not from body.
---@param resolved table
---@param styleName string|nil
---@param style table|nil config.style, the host's merged overrides
---@param stockColor table|nil the legacy colour
---@return table
function Label.StockSpec(resolved, styleName, style, stockColor)
    local name = styleName or "normal"
    local spec = Label.TextSpec(resolved, name)
    spec.color = stockColor
    spec.size = nil
    if type(style) ~= "table" then
        return spec
    end
    local heading = name == "heading"
    local override, source
    if heading then
        override = style.section
        source = (resolved.section and resolved.section.text) or {}
    else
        override = style.body
        source = resolved.body or {}
    end
    local paletteColor = name == "muted" or name == "warning"
    for k in pairs(OverriddenFields(override, source, heading)) do
        if k ~= "from" and not (k == "color" and paletteColor) and source[k] ~= nil then
            spec[k] = source[k]
        end
    end
    return spec
end

--- The text style of a label item that sets a look. The look's fields, converted as the body type
--- converts them, are merged over the label style's text style. Only the fields the look names are
--- merged, so a heading keeps its section text colour unless the look sets one. On a stock theme
--- the base is Label.StockSpec, so a look that sets only a font leaves the label's colour and size
--- as they are today, or as the host's style override set them.
---@param resolved table
---@param styleName string|nil
---@param look table
---@param stockColor table|nil the legacy colour, given only on a stock theme
---@param style table|nil config.style, read only on a stock theme
---@return table
function Label.LookSpec(resolved, styleName, look, stockColor, style)
    local spec
    if stockColor ~= nil then
        spec = Label.StockSpec(resolved, styleName, style, stockColor)
    else
        spec = Label.TextSpec(resolved, styleName)
    end
    local merged = Style.ForItem(resolved, "body", look)
    for k in pairs(look) do
        spec[k] = merged[k]
    end
    return spec
end

--- True when the theme's section variant is stock, as light and dark set it. A label heading is a
--- section caption in the same theme, so labels and sections follow one switch. With no resolved
--- theme, as under the spec runner, this is true too.
---@param resolved table|nil
---@return boolean
function Label.StockSection(resolved)
    return resolved == nil or resolved.section == nil or resolved.section.variant == "stock"
end

--- True when labels and separators draw as the library always has: the section variant is stock
--- and the host gave no style override for body, hint or section. An explicit override takes
--- effect on every theme, so it moves light and dark labels onto the themed text path.
---@param resolved table|nil
---@param style table|nil config.style, the host's merged overrides
---@return boolean
function Label.Stock(resolved, style)
    if not Label.StockSection(resolved) then
        return false
    end
    return resolved == nil or not Label.Overridden(style)
end

--- The engine text justification for an item's align. Left is the default.
---@return number
function Label._justify(item)
    return JUSTIFY[item.align or "left"] or JUSTIFY.left
end

function Label.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.label == nil then
        error(prefix .. " label requires .label")
    end
    if item.style ~= nil and STYLES[item.style] == nil then
        error(prefix .. " style must be one of normal, muted, heading, warning")
    end
    if item.align ~= nil and JUSTIFY[item.align] == nil then
        error(prefix .. " align must be one of left, center, right")
    end
    if item.wrap ~= nil and type(item.wrap) ~= "boolean" then
        error(prefix .. " wrap must be a boolean")
    end
end

function Label.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local label = umg.Construct("/Script/UMG.TextBlock", ctx.contentBox, ctx.namePrefix)
    local resolved = ctx.config.resolved
    local style = ctx.config.style
    local textSpec = nil
    local styleName = item.style or "normal"
    if resolved == nil or (item.look == nil and Label.Stock(resolved, style)) then
        local look = Label._style(item, ctx.config, Theme.Of(ctx.config))
        umg.StyleText(label, look.size, look.color)
    else
        -- An explicit look or style override wins on every theme, light and dark included. On a
        -- stock theme the legacy colour stays the base wherever the host set no colour.
        local stockColor = nil
        if Label.StockSection(resolved) then
            stockColor = Label._style(item, ctx.config, Theme.Of(ctx.config)).color
        end
        if item.look ~= nil then
            textSpec = Label.LookSpec(resolved, styleName, item.look, stockColor, style)
        elseif stockColor ~= nil then
            textSpec = Label.StockSpec(resolved, styleName, style, stockColor)
        else
            textSpec = Label.TextSpec(resolved, styleName)
        end
        local size = Paint.TextSize(ctx.config, textSpec.size, SIZE_KEYS[styleName] or "fontHint")
        umg.StyleText(label, size, textSpec.color, textSpec)
    end
    umg.SetLabelText(label, Paint.Caption(item.label, textSpec))
    pcall(function()
        label:SetJustification(Label._justify(item))
    end)
    if ctx.layout ~= "horizontal" and item.wrap ~= false then
        umg.EnableAutoWrap(label)
    end
    umg.AddToContent(ctx, label)
    local pad = umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 6)
    local ctrl = {
        kind = "label",
        sectionId = ctx.section.id,
        item = item,
        widget = label,
        pad = pad,
        textSpec = textSpec,
        valueKey = item.id and ctx.ValueKey(ctx.section.id, item.id) or nil,
    }
    Label.apply(ctrl, item.label, ctx)
    if item.id then
        table.insert(ctx.liveControls, ctrl)
    end
end

function Label.apply(ctrl, text, ctx)
    local VIS_VISIBLE = 0
    local VIS_COLLAPSED = 1
    local s = tostring(text or "")
    if ctrl.widget ~= nil then
        ctx.umg.SetLabelText(ctrl.widget, Paint.Caption(s, ctrl.textSpec))
    end
    local empty = s:match("^%s*$") ~= nil
    -- A hidden label stays collapsed when its text changes; ItemState shows it again.
    local vis = (empty or ctrl.stateHidden) and VIS_COLLAPSED or VIS_VISIBLE
    pcall(function()
        if ctrl.widget ~= nil then
            ctrl.widget:SetVisibility(vis)
        end
        if ctrl.pad ~= nil then
            ctrl.pad:SetVisibility(vis)
        end
    end)
end

--- ItemState calls this after the label's state changed. A shown label with empty text stays collapsed.
function Label.onItemState(ctrl, _enabled, visible, ctx)
    if visible then
        Label.apply(ctrl, ctrl.item.label, ctx)
    end
end

return Label
