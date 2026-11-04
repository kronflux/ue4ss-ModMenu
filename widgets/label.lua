--[[
  ModMenu widget: label

  Presentation: align (left, center, right), wrap (default true) and style (normal, muted, heading,
  warning). The style picks the font size and colour from the theme.
]]

local Label = {}
Label.type = "label"

local Theme = require("ModMenu.core.theme")

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
    local look = Label._style(item, ctx.config, Theme.Of(ctx.config))
    umg.StyleText(label, look.size, look.color)
    umg.SetLabelText(label, item.label)
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
        ctx.umg.SetLabelText(ctrl.widget, s)
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
