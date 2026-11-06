--[[
  ModMenu widget: separator

  A stock theme, as light and dark are, keeps the blank gap the library has always drawn. Any other
  theme draws a one-unit line in palette.line, centred in the same 14-unit gap.
]]

local Label = require("ModMenu.widgets.label")
local Paint = require("ModMenu.core.paint")

local Separator = {}
Separator.type = "separator"

local GAP = 14
local LINE = 1

function Separator.validate(_item, _sectionId, _index)
    -- no fields required
end

function Separator.build(ctx)
    local umg = ctx.umg
    local resolved = ctx.config and ctx.config.resolved
    -- Labels and separators share one stock switch, so a theme or a host's text override changes both or neither.
    if Label.Stock(resolved, ctx.config and ctx.config.style) then
        umg.RecordNode(ctx, umg.AddSpacer(ctx.contentBox, ctx.namePrefix .. "_Sep", GAP))
        return
    end
    local size = umg.Construct("/Script/UMG.SizeBox", ctx.contentBox, ctx.namePrefix .. "_Sep")
    -- A flat line, so Paint.Box paints it with the stock brush and no rim can show.
    local line = Paint.Box(size, ctx.namePrefix .. "_SepLine", { fill = resolved.palette.line }, 0)
    pcall(function()
        size:SetHeightOverride(LINE)
        size:SetContent(line)
    end)
    local slot = ctx.contentBox:AddChildToVerticalBox(size)
    local above = math.floor((GAP - LINE) / 2)
    pcall(function()
        slot:SetPadding({ Left = 0, Top = above, Right = 0, Bottom = GAP - LINE - above })
        slot:SetHorizontalAlignment(0)
    end)
    umg.RecordNode(ctx, size)
end

return Separator
