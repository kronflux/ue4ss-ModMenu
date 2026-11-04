--[[
  ModMenu widget: label
]]

local Label = {}
Label.type = "label"

function Label.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.label == nil then
        error(prefix .. " label requires .label")
    end
end

function Label.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local label = umg.Construct("/Script/UMG.TextBlock", ctx.contentBox, ctx.namePrefix)
    umg.StyleText(label, ctx.config.fontHint)
    umg.SetLabelText(label, item.label)
    if ctx.layout ~= "horizontal" then
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
