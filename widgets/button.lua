--[[
  ModMenu widget: button

  Visual layers (disabled wins, then active, then variant):
    enabled = false  → themed disabled chrome + no clicks
    active = true    → "this is on" (green) — not a variant
    variant          → Bootstrap-like intent (primary/danger/warning/…)
    default          → theme buttonBg
    confirm          → optional table; onClick waits for the in-shell modal

  Hover and pressed sit below the disabled and active layers. Each poll reads IsHovered and
  IsPressed and shows the look for the new state only when the state changes.
  A mouse click fires on release over the button; a touch tap fires on press.

  Button.States turns the resolved theme into the looks a button draws: the theme's button
  variant (fill, soft, ghost or underline) in the colours of the item's role. When every look is
  flat, the button is today's recoloured Border, so light and dark keep their widgets and colours.
  Otherwise each look is its own shape, built once and shown or hidden (field note 30).
]]

local Util = require("ModMenu.core.util")
local Theme = require("ModMenu.core.theme")
local Style = require("ModMenu.core.style")
local Paint = require("ModMenu.core.paint")

local Button = {}
Button.type = "button"

local VARIANTS = {
    default = true,
    primary = true,
    secondary = true,
    success = true,
    danger = true,
    warning = true,
    info = true,
}

-- Short-lived names from the first variant pass.
local ALIASES = {
    accent = "primary",
}

local VARIANT_CHROME = {
    primary = { "buttonBgPrimary", "buttonTextPrimary" },
    secondary = { "buttonBgSecondary", "buttonTextSecondary" },
    success = { "buttonBgSuccess", "buttonTextSuccess" },
    danger = { "buttonBgDanger", "buttonTextDanger" },
    warning = { "buttonBgWarning", "buttonTextWarning" },
    info = { "buttonBgInfo", "buttonTextInfo" },
}

local VARIANT_HELP = "default|primary|secondary|success|danger|warning|info"

function Button.NormalizeVariant(value)
    if value == nil or value == "" then
        return "default"
    end
    if type(value) ~= "string" then
        return nil
    end
    value = ALIASES[value] or value
    if VARIANTS[value] then
        return value
    end
    return nil
end

local function ChromeColors(colors, item)
    colors = colors or {}
    local fallbackBg, fallbackFg = colors.buttonBg, colors.buttonText
    if item.enabled == false then
        return colors.buttonBgDisabled or fallbackBg, colors.buttonTextDisabled or fallbackFg
    end
    if item.active == true then
        return colors.buttonBgActive or fallbackBg, colors.buttonTextActive or fallbackFg
    end
    local variant = item.variant or "default"
    local keys = VARIANT_CHROME[variant]
    if keys then
        return colors[keys[1]] or fallbackBg, colors[keys[2]] or fallbackFg
    end
    return fallbackBg, fallbackFg
end

------------------------------------------------------------------------------------------
-- Looks from the resolved theme
------------------------------------------------------------------------------------------

local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local BLACK = { R = 0, G = 0, B = 0, A = 1 }

-- Engine visibility values: shown without taking hits, and hidden while keeping its space.
-- These constants, SetShown and AddToOverlay copy core/paint.lua's, which keeps them local.
local VIS_SHOWN, VIS_HIDDEN = 3, 2
local H_FILL, H_CENTER = 0, 2
local V_FILL, V_CENTER = 0, 2

-- A shaped fill button darkens this far toward black when pressed, as StyleLab draws it.
local PRESS_DARKEN = 0.22

-- Tint alphas for normal, hover and pressed, as StyleLab draws the variants without a solid fill.
local TINTS = {
    soft = { 0.14, 0.24, 0.34 },
    ghost = { 0, 0.16, 0.30 },
    underline = { 0, 0.16, 0.30 },
}

-- Any other variant name draws as fill. xp and classic are in this set but still fall back to
-- fill when the theme lacks the table they draw from (see Look).
local LOOK_VARIANTS = { fill = true, soft = true, ghost = true, underline = true, xp = true, classic = true }

-- The xp rings are 2 wide inside the 1-wide edge, as StyleLab draws them, and the face gradient
-- is built from this many strips.
local XP_RING_WIDTH = 2
local XP_FACE_STEPS = 10

-- The caption padding inside a shaped button, because the shape button clears the Button's own padding.
local LABEL_PAD = { 10, 4, 10, 4 }
local UNDERLINE_PAD = { 12, 4, 12, 4 }
local UNDERLINE_HEIGHT = 2
local UNDERLINE_GAP = 3

local function Alpha(c, a)
    return { R = c.R, G = c.G, B = c.B, A = a }
end

local function Mix(a, b, t)
    return {
        R = a.R + (b.R - a.R) * t,
        G = a.G + (b.G - a.G) * t,
        B = a.B + (b.B - a.B) * t,
        A = a.A + (b.A - a.A) * t,
    }
end

local function LargestRadius(radius)
    if type(radius) == "table" then
        local largest = 0
        for i = 1, #radius do
            largest = math.max(largest, tonumber(radius[i]) or 0)
        end
        return largest
    end
    return tonumber(radius) or 0
end

-- A tone more transparent than this draws nothing visible, so the caption and outline would vanish.
local MIN_TONE_ALPHA = 0.05

--- The colour soft and ghost buttons draw in. A clear tone, such as a theme whose surface has
--- alpha 0, gives way to the role's text colour, so the caption and outline stay visible.
---@param tone table
---@param text table|nil
---@return table
function Button.VisibleTone(tone, text)
    if (tonumber(tone.A) or 1) < MIN_TONE_ALPHA and text ~= nil then
        return text
    end
    return tone
end

-- Disabled wins, then active, then the item's variant, as ChromeColors chooses today.
local function RoleName(item)
    if item.enabled == false then
        return "disabled"
    end
    if item.active == true then
        return "active"
    end
    return Button.NormalizeVariant(item.variant) or "default"
end

--- The looks of one role: normal, hover and pressed shapes, the edge, the caption colour and,
--- for underline, the bar colour.
local function Look(b, palette, roleName)
    local roles = b.roles or {}
    local role = roles[roleName] or roles.default or {}
    local variant = role.variant or b.variant
    if not LOOK_VARIANTS[variant] then
        variant = "fill"
    end
    -- A theme's face for this role replaces its fill and caption colour, as StyleLab's RoleColors
    -- does. Disabled and active keep their own colours so they stay distinguishable.
    local face = roleName ~= "disabled" and roleName ~= "active" and b.faces and b.faces[roleName] or nil
    if face ~= nil then
        local copy = {}
        for k, v in pairs(role) do
            copy[k] = v
        end
        copy.fill = face.fill or role.fill
        copy.text = face.text or role.text
        role = copy
    end
    -- xp and classic draw layered looks only for a role that is not disabled or active, and only
    -- when the theme gives them what they draw from; otherwise they draw as a flat fill.
    local layered = roleName ~= "disabled" and roleName ~= "active"
    if variant == "xp" and (not layered or type(b.xp) ~= "table" or b.xp.face == nil or b.xp.pressedFace == nil) then
        variant = "fill"
    elseif variant == "classic" and (not layered or type(b.bevel) ~= "table" or b.bevel.light == nil or b.bevel.dark == nil) then
        variant = "fill"
    end
    local radius, pill = b.radius or 0, b.pill == true
    local base = role.fill or WHITE
    -- Tinted variants draw in one colour. Secondary uses the text colour, as StyleLab does, and
    -- disabled uses its text colour, because its fill is close to the panel and would vanish.
    local tone = role.edge
    if tone == nil and roleName == "secondary" then
        tone = palette.text
    elseif tone == nil and roleName == "disabled" then
        tone = role.text
    end
    tone = tone or base
    tone = Button.VisibleTone(tone, role.text)

    local function Shape(fill)
        return { fill = fill, radius = radius, pill = pill }
    end

    local look = { variant = variant }
    local outline = nil
    if variant == "ghost" then
        outline = tone
    elseif variant ~= "underline" and variant ~= "xp" and variant ~= "classic" then
        outline = (roleName == "secondary" and b.secondaryEdge) or b.edge
    end
    local width = tonumber(b.width) or 1
    if outline ~= nil and width > 0 then
        look.edge = { outline = outline, width = width }
    end

    if variant == "xp" then
        -- A dark rounded edge around a gradient face. Hover adds an orange glow inside the edge and
        -- drops the default ring, and pressed swaps to the darker face with no glow.
        local x = b.xp
        local inner = math.max(0, LargestRadius(radius) - 1)
        local function Ring(color)
            return { fill = Alpha(color, 0), outline = color, width = XP_RING_WIDTH, radius = inner }
        end
        local function FaceLook(stops)
            return { gradient = { stops = stops, steps = XP_FACE_STEPS, radius = inner } }
        end
        local edge = { fill = Alpha(x.edge or BLACK, 0), outline = x.edge or BLACK, width = 1, radius = radius }
        local normal = { FaceLook(x.face) }
        if roleName == "primary" and x.defaultRing ~= nil then
            normal[#normal + 1] = Ring(x.defaultRing)
        end
        normal[#normal + 1] = edge
        local hover = { FaceLook(x.face) }
        if x.glow ~= nil then
            hover[#hover + 1] = Ring(x.glow)
        end
        hover[#hover + 1] = edge
        look.text = role.text
        look.normal = { layers = normal }
        look.hover = { layers = hover }
        look.pressed = { layers = { FaceLook(x.pressedFace), edge } }
    elseif variant == "classic" then
        -- A raised two-ring bevel that turns sunken while pressed, with the caption moving one unit
        -- down and right. Hover looks like rest, as in Windows Classic.
        -- A primary button with defaultEdge gets a 1-wide outline over the bevel's outer row, in every
        -- state, as its own hollow shape so no rounded or outlined shape is ever recoloured.
        local function Stack(sunken)
            local layers = { { fill = base }, { bevel = b.bevel, sunken = sunken } }
            if roleName == "primary" and b.defaultEdge ~= nil then
                layers[#layers + 1] = { fill = Alpha(b.defaultEdge, 0), outline = b.defaultEdge, width = 1, radius = 0 }
            end
            return layers
        end
        local raised = { layers = Stack(false) }
        look.text = role.text
        look.normal = raised
        look.hover = raised
        look.pressed = { layers = Stack(true), shift = { x = 1, y = 1 } }
    elseif variant == "fill" then
        look.text = role.text
        local hover, pressed
        if LargestRadius(radius) <= 0 and not pill and look.edge == nil then
            -- A flat fill derives its states as the library always has, so light and dark keep
            -- today's hover and pressed colours.
            hover, pressed = Theme.FillStates(base)
        else
            hover = Mix(base, b.hoverToward or WHITE, tonumber(b.hoverAmount) or 0.14)
            pressed = Mix(base, BLACK, PRESS_DARKEN)
        end
        look.normal = Shape(base)
        look.hover = Shape(role.hover or hover)
        look.pressed = Shape(role.pressed or pressed)
    else
        local tint = TINTS[variant]
        look.text = tone
        look.normal = Shape(Alpha(tone, tint[1]))
        look.hover = Shape(role.hover or Alpha(tone, tint[2]))
        look.pressed = Shape(role.pressed or Alpha(tone, tint[3]))
        if variant == "underline" then
            look.underline = tone
        end
    end
    return look
end

--- The looks a button draws from the resolved theme. item gives variant, active, enabled and look;
--- the item's look merges over the button type. over, when given, is merged last, so the stepper
--- can put its own radius and pill over the button style. A disabled or active button keeps one
--- look in every pointer state.
---@param resolved table config.resolved
---@param item table|nil
---@param over table|nil
---@return table states { normal, hover, pressed, disabled, edge?, text, underline?, variant, style }
function Button.States(resolved, item, over)
    item = item or {}
    local b = {}
    for k, v in pairs(Style.ForItem(resolved, "button", item.look)) do
        b[k] = v
    end
    if type(over) == "table" then
        for k, v in pairs(over) do
            b[k] = v
        end
    end
    local palette = resolved.palette or {}
    local roleName = RoleName(item)
    local look = Look(b, palette, roleName)
    if roleName == "disabled" or roleName == "active" then
        look.hover = look.normal
        look.pressed = look.normal
    end
    if roleName == "disabled" then
        look.disabled = look.normal
    else
        look.disabled = Look(b, palette, "disabled").normal
    end
    look.style = b
    -- nil means the button keeps its natural height; only a theme that sets one gets a wrapper.
    look.height = tonumber(b.height)
    return look
end

--- The caption style for a state button: the body font, with the button's own typeface, spacing,
--- upper and size. The text style is nil when the theme sets none of them, so light and dark
--- style captions exactly as today.
---@param ctx table
---@param states table from Button.States
---@return table { color, size, textSpec }
function Button.CaptionStyle(ctx, states)
    local config = (ctx and ctx.config) or {}
    local resolved = config.resolved or {}
    local b = states.style or {}
    local body = resolved.body or {}
    local typeface = b.typeface or body.typeface
    local textSpec = nil
    if body.font ~= nil or typeface ~= nil or b.spacing ~= nil or b.upper == true then
        textSpec = { font = body.font, typeface = typeface, spacing = b.spacing, upper = b.upper == true }
    end
    return {
        color = states.text,
        size = Paint.TextSize(config, b.size or body.size, "fontItem"),
        textSpec = textSpec,
    }
end

--- A caption as a live button shows it. A themed button applies its theme's text style, such as
--- upper; any other control shows the text as given.
---@param ctrl table|nil
---@param text any
---@return string
function Button.CaptionText(ctrl, text)
    if ctrl ~= nil and ctrl.themed == true then
        return Paint.Caption(text, ctrl.captionSpec)
    end
    return tostring(text)
end

local function SetShown(widget, on)
    if widget == nil then
        return
    end
    pcall(function()
        widget:SetVisibility(on and VIS_SHOWN or VIS_HIDDEN)
    end)
end

local function AddToOverlay(overlay, widget, pad, halign, valign)
    pcall(function()
        local slot = overlay:AddChildToOverlay(widget)
        slot:SetPadding(Paint.Margin(pad))
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
    end)
end

-- Logged once per session, so a host that changes variants often does not flood the log.
local variantChangeLogged = false

--- Show a shaped button's current look. Shapes are never recoloured (field note 30), so the
--- disabled look is a shape the button already has, and the active look is a shape built with it.
--- A variant change would need new shapes, which a shown Overlay cannot take beneath its caption,
--- so the button keeps the variant it was built with until the shell rebuilds.
--- Swap the edge and the underline bar for their disabled copies, built beside them, because a
--- shape is never recoloured (field note 30). A disabled look with no outline has no copy, so its
--- edge is only hidden.
local function ShowDisabledParts(ctrl, enabled)
    SetShown(ctrl.edge, enabled)
    SetShown(ctrl.disabledEdge, not enabled)
    SetShown(ctrl.bar, enabled)
    SetShown(ctrl.disabledBar, not enabled)
end

local function ApplyShapes(ctrl, resolved, enabled)
    local item = ctrl.item
    if ctrl.builtVariant ~= item.variant and not variantChangeLogged then
        variantChangeLogged = true
        Util.Log("button " .. tostring(item.id) .. ": a variant change on a shaped button shows when the menu is rebuilt")
    end
    local states = Button.States(resolved, {
        variant = ctrl.builtVariant,
        active = item.active,
        enabled = enabled,
        look = item.look,
    })
    Paint.SetEnabled(ctrl, enabled)
    ShowDisabledParts(ctrl, enabled)
    SetShown(ctrl.activeShape, enabled and item.active == true)
    if ctrl.labelWidget ~= nil and states.text ~= nil then
        pcall(function()
            ctrl.labelWidget:SetColorAndOpacity({ SpecifiedColor = states.text, ColorUseRule = 0 })
        end)
    end
end

--- Paint a themed button from Button.States: the flat one is recoloured as today, the shaped one
--- shows its looks.
local function ApplyThemed(ctrl, ctx, resolved, enabled)
    if ctrl.flat == false then
        ApplyShapes(ctrl, resolved, enabled)
        return
    end
    local item = ctrl.item
    local states = Button.States(resolved, {
        variant = item.variant,
        active = item.active,
        enabled = enabled,
        look = item.look,
    })
    pcall(function()
        if ctrl.widget ~= nil then
            ctrl.widget:SetIsEnabled(enabled)
        end
    end)
    ShowDisabledParts(ctrl, enabled)
    if ctx.umg ~= nil then
        ctx.umg.SetFillColors(ctrl, states.normal.fill, states.hover.fill, states.pressed.fill)
        if ctrl.labelWidget ~= nil then
            local caption = Button.CaptionStyle(ctx, states)
            ctx.umg.StyleText(ctrl.labelWidget, caption.size, caption.color, caption.textSpec)
        end
    end
end

--- Paint UMG from item.enabled / item.active / item.variant.
function Button.applyChrome(ctrl, ctx)
    if ctrl == nil or ctrl.item == nil then
        return
    end
    local item = ctrl.item
    -- stateDisabled is set by ItemState when this button or a parent row or fold is disabled.
    local enabled = item.enabled ~= false and ctrl.stateDisabled ~= true
    ctrl.enabled = enabled
    -- Only buttons this module built from a theme take the themed path. Checkbox, radio,
    -- multiselect and keybind pass their own controls here and keep the legacy colours.
    local resolved = ctrl.themed == true and ctx ~= nil and ctx.config ~= nil and ctx.config.resolved
    if resolved then
        ApplyThemed(ctrl, ctx, resolved, enabled)
        return
    end
    local colors = Theme.Of(ctx and ctx.config)
    local bg, fg = ChromeColors(colors, item)
    -- Disabled and active buttons keep one fill in every pointer state.
    local hover, pressed = bg, bg
    if enabled and item.active ~= true then
        local states = Theme.ButtonStates(colors, item.variant)
        hover, pressed = states.hover, states.pressed
    end
    pcall(function()
        if ctrl.widget ~= nil then
            ctrl.widget:SetIsEnabled(enabled)
        end
    end)
    if ctx ~= nil and ctx.umg ~= nil then
        ctx.umg.SetFillColors(ctrl, bg, hover, pressed)
    end
    if ctrl.labelWidget ~= nil and ctx ~= nil and ctx.umg ~= nil then
        ctx.umg.StyleText(ctrl.labelWidget, ctx.config.fontItem, fg)
    end
end

--- ItemState calls this when the button's enabled or visible state changed, so the disabled chrome follows.
function Button.onItemState(ctrl, _enabled, _visible, ctx)
    Button.applyChrome(ctrl, ctx)
end

function Button.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.onClick ~= nil and type(item.onClick) ~= "function" then
        error(prefix .. " onClick must be a function")
    end
    if item.enabled ~= nil and type(item.enabled) ~= "boolean" then
        error(prefix .. " enabled must be a boolean")
    end
    if item.active ~= nil and type(item.active) ~= "boolean" then
        error(prefix .. " active must be a boolean")
    end
    if item.variant ~= nil and Button.NormalizeVariant(item.variant) == nil then
        error(prefix .. " variant must be " .. VARIANT_HELP)
    end
    if item.confirm ~= nil then
        if type(item.confirm) ~= "table" then
            error(prefix .. " confirm must be a table")
        end
        for _, key in ipairs({ "title", "message", "confirmLabel", "cancelLabel" }) do
            if item.confirm[key] ~= nil and type(item.confirm[key]) ~= "string" then
                error(prefix .. " confirm." .. key .. " must be a string")
            end
        end
        if item.confirm.variant ~= nil and Button.NormalizeVariant(item.confirm.variant) == nil then
            error(prefix .. " confirm.variant must be " .. VARIANT_HELP)
        end
        if item.onClick == nil then
            error(prefix .. " confirm requires onClick (runs after Confirm)")
        end
    end
end

--- An outline-only Border in a look's edge colours, hidden until it is shown.
local function HiddenEdge(face, name, edge, normal)
    local box = Paint.Box(face, name, {
        fill = Alpha(edge.outline, 0),
        outline = edge.outline,
        width = edge.width,
        radius = normal.radius,
        pill = normal.pill,
    }, 0)
    SetShown(box, false)
    AddToOverlay(face, box, 0)
    return box
end

--- The content of a shaped or underlined button: an Overlay holding the active look and the
--- disabled outline (shaped buttons only, each hidden until needed) and the caption, with the
--- underline bar below it for underline. These sit above the state shapes and Paint's edge, so the
--- active shape carries its own outline and the disabled outline replaces Paint's edge while disabled.
--- Returns face and a parts table { label, activeShape?, disabledEdge?, bar?, disabledBar? }.
local function BuildFace(ctx, resolved, states, caption, shaped)
    local umg = ctx.umg
    local item = ctx.item
    local name = ctx.namePrefix
    local face = umg.Construct("/Script/UMG.Overlay", ctx.contentBox, name .. "_Face")
    local parts = {}
    local disabled = Button.States(resolved, { variant = item.variant, enabled = false, look = item.look })
    if shaped then
        local active = Button.States(resolved, { variant = item.variant, active = true, look = item.look })
        local spec = { fill = active.normal.fill, radius = active.normal.radius, pill = active.normal.pill }
        if active.edge ~= nil then
            spec.outline = active.edge.outline
            spec.width = active.edge.width
        end
        parts.activeShape = Paint.Box(face, name .. "_active", spec, 0)
        SetShown(parts.activeShape, false)
        AddToOverlay(face, parts.activeShape, 0)
        if disabled.edge ~= nil then
            parts.disabledEdge = HiddenEdge(face, name .. "_disabledEdge", disabled.edge, disabled.normal)
        end
    end
    local label = umg.Construct("/Script/UMG.TextBlock", face, name .. "_BtnLabel")
    umg.StyleText(label, caption.size, caption.color, caption.textSpec)
    umg.SetLabelText(label, Paint.Caption(item.label, caption.textSpec))
    parts.label = label
    local content, pad = label, LABEL_PAD
    if states.underline ~= nil then
        local stack = umg.Construct("/Script/UMG.VerticalBox", face, name .. "_Underline")
        local barSize = umg.Construct("/Script/UMG.SizeBox", stack, name .. "_BarSize")
        -- Both bars share one Overlay, so the disabled bar takes the normal bar's place.
        local bars = umg.Construct("/Script/UMG.Overlay", barSize, name .. "_Bars")
        parts.bar = Paint.Box(bars, name .. "_Bar", { fill = states.underline }, 0)
        AddToOverlay(bars, parts.bar, 0)
        if disabled.underline ~= nil then
            parts.disabledBar = Paint.Box(bars, name .. "_disabledBar", { fill = disabled.underline }, 0)
            SetShown(parts.disabledBar, false)
            AddToOverlay(bars, parts.disabledBar, 0)
        end
        pcall(function()
            local labelSlot = stack:AddChildToVerticalBox(label)
            labelSlot:SetHorizontalAlignment(H_CENTER)
            barSize:SetHeightOverride(UNDERLINE_HEIGHT)
            barSize:SetContent(bars)
            local barSlot = stack:AddChildToVerticalBox(barSize)
            barSlot:SetPadding(Paint.Margin({ 0, UNDERLINE_GAP, 0, 0 }))
            barSlot:SetHorizontalAlignment(H_FILL)
        end)
        content, pad = stack, UNDERLINE_PAD
    end
    AddToOverlay(face, content, pad, H_CENTER, V_CENTER)
    return face, parts
end

--- Build a button from the resolved theme through Paint.StateButton. The resting look of the
--- item's variant decides the tree, and applyChrome then shows the item's current state. A flat
--- button with a plain caption is CreateFilledButton's tree, so light and dark keep today's widgets.
local function BuildThemed(ctx, resolved)
    local item = ctx.item
    local states = Button.States(resolved, { variant = item.variant, look = item.look })
    local caption = Button.CaptionStyle(ctx, states)
    local shaped = Paint.NeedsShapes(states)
    local ctrl
    if not shaped and states.underline == nil then
        ctrl = Paint.StateButton(ctx.contentBox, ctx.namePrefix, states, item.label, caption)
        ctrl.labelWidget = ctrl.label
    else
        local face, parts = BuildFace(ctx, resolved, states, caption, shaped)
        ctrl = Paint.StateButton(ctx.contentBox, ctx.namePrefix, states, face, { pad = 0 })
        ctrl.labelWidget = parts.label
        -- A pressed look's shift moves the caption alone, not the active shape or outline beside it.
        ctrl.label = parts.label
        ctrl.activeShape = parts.activeShape
        ctrl.disabledEdge = parts.disabledEdge
        ctrl.bar = parts.bar
        ctrl.disabledBar = parts.disabledBar
    end
    -- SetButtonLabel passes a new caption through Button.CaptionText with this style.
    ctrl.captionSpec = caption.textSpec
    ctrl.themed = true
    ctrl.builtVariant = item.variant
    return ctrl
end

function Button.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    item.variant = Button.NormalizeVariant(item.variant) or "default"
    local resolved = ctx.config and ctx.config.resolved
    local ctrl
    if resolved ~= nil then
        ctrl = BuildThemed(ctx, resolved)
    else
        local fill, button, label = umg.CreateFilledButton(ctx.contentBox, ctx.namePrefix, item.label)
        ctrl = { root = fill, widget = button, fill = fill, labelWidget = label }
    end
    -- A theme that sets a button height gets a SizeBox with that minimum around the button. The
    -- wrapper replaces the root only when it took the button, so a failed write leaves the button usable.
    local height = resolved ~= nil and Button.States(resolved, { variant = item.variant, look = item.look }).height or nil
    if height ~= nil then
        local sized = umg.Construct("/Script/UMG.SizeBox", ctx.contentBox, ctx.namePrefix .. "_Height")
        local ok = pcall(function()
            sized:SetMinDesiredHeight(height)
            sized:SetContent(ctrl.root)
        end)
        if ok then
            ctrl.root = sized
        end
    end
    umg.AddToContent(ctx, ctrl.root)
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
    ctrl.kind = "button"
    ctrl.sectionId = ctx.section.id
    ctrl.item = item
    ctrl.enabled = item.enabled ~= false
    ctrl.wasPressed = false
    Button.applyChrome(ctrl, ctx)
    table.insert(ctx.liveControls, ctrl)
end

--- Fire onClick. Shared by IsPressed poll and LMB-latch pollClick.
---@param path string
local function FireClick(ctrl, ctx, path)
    ctx.Input.DebugClick(path, ctrl, ctrl.widget)
    ctx.Input.SuppressPressEdge(ctrl)
    if ctrl.item.confirm ~= nil and ctx.ShowConfirm ~= nil then
        ctx.ShowConfirm(ctrl.item)
    else
        -- A button that asks to confirm leaves the motion to the dialog's button, so one action never
        -- moves the menu twice. A danger click shakes the menu, and any other click pops it.
        if ctx.motion ~= nil then
            if ctrl.item.variant == "danger" then
                ctx.motion.Shake()
            else
                ctx.motion.Pop()
            end
        end
        ctx.SafeCall(ctrl.item.onClick)
    end
    ctx.ReclaimMenuInput()
    ctx.Input.IgnoreClicks(2)
    -- Reclaim touches PlayerController / SetInputMode — must stay on the game thread.
    ExecuteInGameThreadWithDelay(200, Util.PinFn(function()
        ctx.ReclaimMenuInput()
    end))
    return true
end

--- Continuous press poll. The click rule is Input.ReleaseClick: a mouse click fires when the
--- button is released over it, so the pressed colour stays visible while the button is held.
function Button.poll(ctrl, ctx)
    if ctrl.enabled == false then
        return
    end
    -- An active button keeps its one fill in every pointer state.
    if ctrl.item ~= nil and ctrl.item.active ~= true then
        -- A shaped button swaps shapes; a flat one, including radio and multiselect options that
        -- share this poll, is recoloured.
        if ctrl.flat == false then
            Paint.TrackPointer(ctrl)
        else
            ctx.umg.TrackPointer(ctrl)
        end
    end
    if ctx.Input.ReleaseClick(ctrl, ctrl.widget) then
        FireClick(ctrl, ctx, "release")
    end
end

--- The mouse-down latch claims a press on the hovered button; the release in Button.poll fires it.
--- @return boolean true if click consumed
function Button.pollClick(ctrl, ctx)
    if ctrl.enabled == false then
        return false
    end
    local consumed, fireNow = ctx.Input.ArmClick(ctrl, ctrl.widget)
    if fireNow then
        return FireClick(ctrl, ctx, "latch-hover")
    end
    return consumed
end
return Button
