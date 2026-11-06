--[[
  ModMenu.core.tooltip - one shared tooltip for every item that sets tooltip = "text".

  The registry validates the field for every item type. After a build, the shell attaches each
  live control whose item has a tooltip, and the poll loop calls Poll every tick. Poll reads
  IsHovered on the attached widgets, shows the text beside the pointer once the hover has lasted
  config.tooltipDelayMs, and hides it when the pointer leaves. The text block and its border are
  created on the first show, under the menu canvas, and reused for every item after that.
  Visibility changes only when the shown state changes, so a steady hover or no hover costs no
  SetVisibility call.

  The card draws from the resolved tooltip style. A flat card is recoloured on every show, as it
  always was. A rounded or outlined card is written into its brush when the widget is built and is
  never recoloured, because a recoloured rounded brush shows a rim (field note 30); the widget is
  built again when the canvas or the resolved style changes.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Paint = require("ModMenu.core.paint")
local Theme = require("ModMenu.core.theme")

local IsValid = Util.IsValid

local Tooltip = {}

local VIS_COLLAPSED = 1
-- The tooltip never takes the pointer, because a tooltip under the pointer would end the hover that shows it.
local VIS_HITTEST_INVISIBLE = 3
-- The tooltip sits above the confirm dialog's dim layer, which uses Z order 20.
local TOOLTIP_Z = 30
local DEFAULT_DELAY_MS = 400

-- Each created tooltip gets a new name, because reusing a name under a rebuilt canvas can resurrect a destroyed widget.
local createGen = 0

--- Raise an error when item.tooltip is set to anything other than a string.
---@param item table
---@param prefix string
function Tooltip.Validate(item, prefix)
    if item.tooltip ~= nil and type(item.tooltip) ~= "string" then
        error(prefix .. " tooltip must be a string")
    end
end

---@class ModMenuTooltipTarget
---@field widget any the attached control's widget, polled with IsHovered
---@field text string the item's tooltip text

---@class ModMenuTooltipState
---@field targets ModMenuTooltipTarget[]
---@field hovered ModMenuTooltipTarget|nil the target under the pointer since hoverSince
---@field hoverSince number|nil
---@field shown boolean
---@field root any|nil the SizeBox that holds the tooltip
---@field border any|nil
---@field text any|nil
---@field slot any|nil
---@field canvas any|nil the menu canvas the widget was built under
---@field shaped boolean|nil true when the card's brush was written as a rounded or outlined shape
---@field resolved table|nil the resolved style the card was built from

---@return ModMenuTooltipState
local function TipState(state)
    local tip = state.tooltip
    if tip == nil then
        ---@type ModMenuTooltipState
        tip = { targets = {}, hovered = nil, hoverSince = nil, shown = false }
        state.tooltip = tip
    end
    return tip
end

--- Record a live control's widget and its item's tooltip text on the shell state.
--- A control without a widget, or whose item has no tooltip, is ignored.
---@param state table the shell state
---@param ctrl table a live control
function Tooltip.Attach(state, ctrl)
    if ctrl == nil or ctrl.widget == nil or ctrl.item == nil then
        return
    end
    local text = ctrl.item.tooltip
    if type(text) ~= "string" or text == "" then
        return
    end
    table.insert(TipState(state).targets, { widget = ctrl.widget, text = text })
end

local function IsTrue(value)
    return value == true or value == 1
end

local function IsHovered(widget)
    local hovered = false
    pcall(function()
        hovered = IsTrue(widget:IsHovered())
    end)
    return hovered
end

-- UE4SS FVector2D fields are often userdata, not Lua numbers (the same reader lives in
-- core/input.lua), so each field goes through tonumber. A reader that accepted only Lua numbers
-- would place the tooltip at the canvas origin on every show.
local function AsNumber(v)
    if v == nil then
        return nil
    end
    if type(v) == "number" then
        return v
    end
    local ok, n = pcall(tonumber, v)
    if ok and type(n) == "number" then
        return n
    end
    ok, n = pcall(function()
        return v + 0
    end)
    if ok and type(n) == "number" then
        return n
    end
    return nil
end

local function ReadVec2(v)
    if v == nil then
        return nil, nil
    end
    if type(v) == "table" then
        return AsNumber(v.X or v.x), AsNumber(v.Y or v.y)
    end
    local okX, x = pcall(function()
        return v.X
    end)
    local okY, y = pcall(function()
        return v.Y
    end)
    if not okX or not okY then
        return nil, nil
    end
    return AsNumber(x), AsNumber(y)
end

--- Read the pointer in viewport space, the same space the menu canvas uses for slot positions.
local function PointerXY()
    local okHelpers, UEHelpers = pcall(require, "UEHelpers.UEHelpers")
    if not okHelpers then
        return nil, nil
    end
    local world = UEHelpers.GetGameInstance()
    if IsValid(world) then
        local ok, lib = pcall(function()
            return StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        end)
        if ok and IsValid(lib) and lib.GetMousePositionOnViewport then
            local okPos, pos = pcall(function()
                return lib:GetMousePositionOnViewport(world)
            end)
            if okPos then
                local x, y = ReadVec2(pos)
                if x and y then
                    return x, y
                end
            end
        end
    end
    local pc = UEHelpers.GetPlayerController()
    if IsValid(pc) and pc.GetMousePosition then
        local ok, a, b = pcall(function()
            return pc:GetMousePosition()
        end)
        a, b = AsNumber(a), AsNumber(b)
        if ok and a ~= nil and b ~= nil then
            return a, b
        end
    end
    return nil, nil
end

local function SetVisibility(widget, vis)
    pcall(function()
        widget:SetVisibility(vis)
    end)
end

--- The resolved tooltip style and the hint text style, or nil when the config has no resolved style.
---@return table|nil look, table|nil hint
local function Looks(config)
    local resolved = config.resolved
    if type(resolved) ~= "table" or type(resolved.tooltip) ~= "table" then
        return nil, nil
    end
    return resolved.tooltip, resolved.hint
end

--- The card's shape from the tooltip style, for Paint.Brush and Paint.IsFlat.
local function CardSpec(look)
    if look == nil then
        return nil
    end
    return { fill = look.fill, radius = look.radius, outline = look.outline, width = look.width }
end

--- The tooltip text size: the hint style's size when the theme sets one, else fontHint.
local function TextSize(config, hint)
    return Paint.TextSize(config, hint and hint.size or nil, "fontHint")
end

--- True when the built widget no longer matches the shell: the canvas was rebuilt, or a rounded
--- card was written for a resolved style that a later Init replaced. A flat card is recoloured on
--- every show, so a new style alone does not rebuild it.
local function IsStale(state, tip)
    if tip.canvas ~= state.menuCanvas then
        return true
    end
    return tip.shaped == true and tip.resolved ~= (state.config or {}).resolved
end

--- Build the shared tooltip under the menu canvas. Returns false when the canvas is gone.
local function EnsureWidget(state, tip)
    if tip.root ~= nil and IsValid(tip.root) and not IsStale(state, tip) then
        return true
    end
    if not IsValid(state.menuCanvas) then
        return false
    end
    if tip.root ~= nil and IsValid(tip.root) then
        local old = tip.root
        pcall(function()
            old:RemoveFromParent()
        end)
    end
    tip.root, tip.border, tip.text, tip.slot = nil, nil, nil, nil
    createGen = createGen + 1
    local suffix = tostring(createGen)
    local canvas = state.menuCanvas
    local config = state.config or {}
    local look, hint = Looks(config)
    local spec = CardSpec(look)
    local ok = pcall(function()
        local size = Umg.Construct("/Script/UMG.SizeBox", canvas, "ModMenu_TooltipSize_" .. suffix)
        local border = Umg.Construct("/Script/UMG.Border", size, "ModMenu_TooltipBorder_" .. suffix)
        -- A rounded or outlined card is written into the Border's own brush now, before it is first
        -- shown, because only then does Slate read it (field note 29).
        tip.shaped = spec ~= nil and not Paint.IsFlat(spec)
        if tip.shaped then
            pcall(function()
                Paint.Brush(border.Background, spec)
            end)
        end
        local text = Umg.Construct("/Script/UMG.TextBlock", border, "ModMenu_TooltipText_" .. suffix)
        -- The font size must be set before the block is slotted, as widgets/label.lua does, because a
        -- Font.Size written after construction is not read by the drawn text, which then keeps the
        -- stock 24 px size whatever the menu's fontScale.
        Umg.StyleText(text, TextSize(config, hint), nil, hint)
        Umg.EnableAutoWrap(text)
        pcall(function()
            border:SetContent(text)
        end)
        pcall(function()
            size:SetContent(border)
        end)
        local slot = canvas:AddChildToCanvas(size)
        pcall(function()
            slot:SetAutoSize(true)
            slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
            slot:SetZOrder(TOOLTIP_Z)
        end)
        SetVisibility(size, VIS_COLLAPSED)
        tip.root = size
        tip.border = border
        tip.text = text
        tip.slot = slot
        tip.canvas = canvas
        tip.resolved = config.resolved
    end)
    return ok and tip.root ~= nil
end

--- Style, fill and place the tooltip, then make it visible. Returns false when the widget could not be built.
--- Colours, padding and width are read on every show, so a later Init applies without a rebuild.
local function Show(state, tip, target)
    if not EnsureWidget(state, tip) then
        return false
    end
    local config = state.config or {}
    local spacing = config.spacing or {}
    local colors = Theme.Of(config)
    local look, hint = Looks(config)
    local pad = spacing.tooltipPad or 6
    local gap = spacing.tooltipGap or 12
    pcall(function()
        tip.root:SetMaxDesiredWidth(spacing.tooltipMaxWidth or 320)
    end)
    pcall(function()
        -- A rounded or outlined card keeps the brush written at build (see EnsureWidget).
        if not tip.shaped then
            tip.border:SetBrushColor((look and look.fill) or colors.tooltipBg or colors.panelBg)
        end
        tip.border:SetPadding({ Left = pad, Top = pad, Right = pad, Bottom = pad })
    end)
    -- The tooltip text once followed textPrimary, so a host's legacy textPrimary override still
    -- colours it; otherwise the tooltip style's text colour applies.
    local overrides = config._colorOverrides
    local textColor = (look and look.text) or colors.textPrimary
    if type(overrides) == "table" and overrides.textPrimary ~= nil then
        textColor = colors.textPrimary
    end
    -- Only the colour applies here; the size was fixed at construction (see EnsureWidget).
    Umg.StyleText(tip.text, TextSize(config, hint), textColor, hint)
    Umg.SetLabelText(tip.text, target.text)

    -- The tooltip opens toward the screen centre, away from the docked edge, so it does not run off screen.
    local px, py = PointerXY()
    if px ~= nil and tip.slot ~= nil then
        local alignX, alignY = 0, 0
        local x, y = px + gap, py + gap
        if config.dock == "right" then
            alignX = 1
            x = px - gap
        end
        if config.dock == "bottom" then
            alignY = 1
            y = py - gap
        end
        pcall(function()
            tip.slot:SetAlignment({ X = alignX, Y = alignY })
            tip.slot:SetPosition({ X = x, Y = y })
        end)
    end
    SetVisibility(tip.root, VIS_HITTEST_INVISIBLE)
    tip.shown = true
    return true
end

local function HideWidget(tip)
    if tip.shown and tip.root ~= nil then
        SetVisibility(tip.root, VIS_COLLAPSED)
    end
    tip.shown = false
end

--- Hide the tooltip and forget the current hover, keeping the attached targets.
--- Close uses this, because the menu keeps its tree and its live controls while closed.
---@param state table the shell state
function Tooltip.Hide(state)
    local tip = state.tooltip
    if tip == nil then
        return
    end
    HideWidget(tip)
    tip.hovered = nil
    tip.hoverSince = nil
end

--- Hide the tooltip and drop every attached target, because the controls they point at are being replaced.
--- The shared widget is kept, since it lives under the canvas and survives a content rebuild.
---@param state table the shell state
function Tooltip.Reset(state)
    local tip = state.tooltip
    if tip == nil then
        return
    end
    Tooltip.Hide(state)
    tip.targets = {}
end

--- Check the hover once. now is a time in milliseconds from any steady clock.
---@param state table the shell state
---@param now number
function Tooltip.Poll(state, now)
    ---@type ModMenuTooltipState|nil
    local tip = state.tooltip
    if tip == nil or #tip.targets == 0 then
        return
    end

    -- The confirm dialog covers the panel, so a hover under it does not count.
    local hovered = nil
    if state.confirm == nil then
        -- The current target is checked first, because a steady hover is the common case.
        if tip.hovered ~= nil and IsHovered(tip.hovered.widget) then
            hovered = tip.hovered
        else
            for _, target in ipairs(tip.targets) do
                if IsHovered(target.widget) then
                    hovered = target
                    break
                end
            end
        end
    end

    if hovered ~= tip.hovered then
        HideWidget(tip)
        tip.hovered = hovered
        tip.hoverSince = hovered and now or nil
        return
    end

    if hovered ~= nil and not tip.shown then
        local delay = (state.config and state.config.tooltipDelayMs) or DEFAULT_DELAY_MS
        if now - tip.hoverSince >= delay and not Show(state, tip, hovered) then
            -- A failed build is not retried on every tick of the same hover. The next hover tries again.
            tip.hoverSince = math.huge
        end
    end
end

return Tooltip
