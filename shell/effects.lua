--[[
  ModMenu.shell.effects — the drawn panel effects of the CRT, hologram and frost looks: scanlines, a
  projection sweep, an interference band, a tear, glints, the title ghosts and the cursor block.

  This module only builds the widgets, at rest, and keeps their handles in S.fx. core/motion.lua
  animates them. UMG geometry reads as zero through UE4SS (field note 27), so the bands use a fixed
  1200-unit travel and line count and the panel body clips them to its bounds.
]]

local Umg = require("ModMenu.core.umg")
local Paint = require("ModMenu.core.paint")

local Construct = Umg.Construct

local M = {}

local H_FILL, H_LEFT, H_RIGHT = 0, 1, 3
local V_FILL, V_TOP, V_BOTTOM = 0, 1, 3

-- The height every vertical effect is built for, taller than any panel the library draws.
M.TRAVEL = 1200

-- The seed of the scanline plan, so a look draws the same lines on every build.
local SCAN_SEED = 4242

local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local BLACK = { R = 0, G = 0, B = 0, A = 1 }

local function Alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

--- A small repeatable random number generator, so a look's noise follows its own pattern. g is a
--- table holding the seed, and each call steps it and returns a number from 0 up to but not 1.
---@param g table
---@return number
function M.Rand(g)
    g.seed = (g.seed * 1103515245 + 12345) % 2147483648
    return g.seed / 2147483648
end
local Rand = M.Rand

--- The scanlines for a panel of the given height: one entry per period, each with the alpha of its
--- dark line, or of the faint accent row that now and then replaces it. Pure and seeded.
---@param seed number
---@param strength number
---@param period number
---@param height number
---@return { alpha: number, bright: boolean }[]
function M.ScanlinePlan(seed, strength, period, height)
    local plan = {}
    if period == nil or period <= 0 or height == nil or height <= 0 then
        return plan
    end
    local g = { seed = seed }
    for i = 1, math.floor(height / period) do
        if Rand(g) > 0.93 then
            plan[i] = { alpha = strength * 0.35, bright = true }
        else
            plan[i] = { alpha = strength * (0.55 + 0.9 * Rand(g)), bright = false }
        end
    end
    return plan
end

--- The six glint spots of the frost look: alignment, padding and size, as StyleLab places them.
---@return { h: number, v: number, pad: number[], size: number }[]
function M.SparkleSpots()
    return {
        { h = H_RIGHT, v = V_TOP, pad = { 0, 12, 28, 0 }, size = 4 },
        { h = H_RIGHT, v = V_TOP, pad = { 0, 26, 46, 0 }, size = 3 },
        { h = H_RIGHT, v = V_TOP, pad = { 0, 8, 64, 0 }, size = 2 },
        { h = H_LEFT, v = V_BOTTOM, pad = { 22, 0, 0, 18 }, size = 3 },
        { h = H_LEFT, v = V_BOTTOM, pad = { 40, 0, 0, 30 }, size = 2 },
        { h = H_RIGHT, v = V_BOTTOM, pad = { 0, 0, 30, 24 }, size = 3 },
    }
end

--- Forget every handle. The shell calls it when it builds or tears down a panel.
---@param S table
function M.Reset(S)
    S.fx = { sparkles = {}, ghosts = {} }
end

--- Forget the handles of the title and the cursor, which live in content that every content build
--- replaces, so the motion never moves a destroyed widget.
---@param S table
function M.ResetContent(S)
    if S.fx == nil then
        M.Reset(S)
    end
    S.fx.title = nil
    S.fx.cursor = nil
    S.fx.ghosts = {}
end

local function Sized(outer, name, child, w, h)
    local size = Construct("/Script/UMG.SizeBox", outer, name)
    pcall(function()
        if w ~= nil then
            size:SetWidthOverride(w)
        end
        if h ~= nil then
            size:SetHeightOverride(h)
        end
    end)
    pcall(function()
        size:SetContent(child)
    end)
    return size
end

local function OverlayAdd(overlay, widget, pad, halign, valign)
    return (pcall(function()
        local slot = overlay:AddChildToOverlay(widget)
        slot:SetPadding(Paint.Margin(pad))
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
    end))
end

-- Add a widget to an overlay or raise, so that a part whose add failed is logged once by its guard
-- and never recorded as built.
local function Place(overlay, widget, pad, halign, valign)
    if not OverlayAdd(overlay, widget, pad, halign, valign) then
        error("could not add an effect to the panel body")
    end
end

local function VBoxAdd(box, widget, pad)
    pcall(function()
        local slot = box:AddChildToVerticalBox(widget)
        slot:SetPadding(Paint.Margin(pad))
    end)
end

-- Run one part guarded, as the shell's Decoration does, so a part that fails leaves the rest. The
-- shell hands its own guard in, and the module needs none of its own.
local function Guard(decoration, part, fn)
    if decoration ~= nil then
        return decoration(part, fn)
    end
    return (pcall(fn))
end

--- Build the panel effects into body, an Overlay that already holds the panel shape, and record
--- their handles in S.fx. Each effect is shown hit-test invisible so clicks pass through, and the
--- body clips to its bounds when any effect is present.
---@param S table
---@param body any Overlay
---@param resolved table
---@param suffix string
---@param decoration fun(part: string, fn: function): boolean|nil the shell's guard
function M.Build(S, body, resolved, suffix, decoration)
    local panel = resolved.panel or {}
    local palette = resolved.palette
    local motion = resolved.motion or {}
    local fx = S.fx
    if fx == nil then
        M.Reset(S)
        fx = S.fx
    end
    local clip = false
    local function Name(part)
        return "ModMenu_Fx" .. part .. "_" .. suffix
    end

    if panel.sweep then
        Guard(decoration, "sweep", function()
            -- A soft bright band, three strips deep, with an interference band and a hidden tear.
            local sweep = Construct("/Script/UMG.VerticalBox", body, Name("Sweep"))
            VBoxAdd(sweep, Sized(sweep, Name("SweepA"), Paint.Box(sweep, Name("SweepAFill"),
                { fill = Alpha(palette.accent, 0.03) }, 0), nil, 24))
            VBoxAdd(sweep, Sized(sweep, Name("SweepB"), Paint.Box(sweep, Name("SweepBFill"),
                { fill = Alpha(palette.accent, 0.08) }, 0), nil, 10))
            VBoxAdd(sweep, Sized(sweep, Name("SweepC"), Paint.Box(sweep, Name("SweepCFill"),
                { fill = Alpha(palette.accent, 0.03) }, 0), nil, 24))
            Paint.SetShown(sweep, true)
            Place(body, sweep, 0, H_FILL, V_TOP)
            fx.sweep = sweep
            clip = true

            local noise = Sized(body, Name("Noise"), Paint.Box(body, Name("NoiseFill"),
                { fill = Alpha(BLACK, 0.22) }, 0), nil, 30)
            Paint.SetShown(noise, true)
            Place(body, noise, 0, H_FILL, V_TOP)
            fx.noise = noise

            local tear = Construct("/Script/UMG.VerticalBox", body, Name("Tear"))
            VBoxAdd(tear, Sized(tear, Name("TearA"), Paint.Box(tear, Name("TearAFill"),
                { fill = Alpha(palette.accent, 0.45) }, 0), nil, 2))
            VBoxAdd(tear, Sized(tear, Name("TearB"), Paint.Box(tear, Name("TearBFill"),
                { fill = Alpha(BLACK, 0.45) }, 0), nil, 10))
            Paint.SetShown(tear, false)
            Place(body, tear, 0, H_FILL, V_TOP)
            fx.tear = tear
        end)
    end

    if motion.sparkle then
        for i, spot in ipairs(M.SparkleSpots()) do
            Guard(decoration, "sparkle", function()
                local dot = Sized(body, Name("Sparkle" .. i), Paint.Box(body, Name("SparkleFill" .. i),
                    { fill = WHITE, radius = 1, pill = true }, 0), spot.size, spot.size)
                Paint.SetShown(dot, true)
                Place(body, dot, spot.pad, spot.h, spot.v)
                fx.sparkles[i] = dot
                clip = true
            end)
        end
    end

    -- A scanlines value of true means the default strength, as in StyleLab.
    local strength = panel.scanlines == true and 0.25 or tonumber(panel.scanlines) or 0
    if strength > 0 then
        Guard(decoration, "scanlines", function()
            -- Each line is one Border straight in the VerticalBox, because the hologram look has 480
            -- of them and a wrapper per line would double the build.
            local period = tonumber(panel.scanPeriod) or 2.5
            local stack = Construct("/Script/UMG.VerticalBox", body, Name("Scanlines"))
            for i, line in ipairs(M.ScanlinePlan(SCAN_SEED, strength, period, M.TRAVEL)) do
                local color = line.bright and Alpha(palette.accent, line.alpha) or Alpha(BLACK, line.alpha)
                local row = Paint.Box(stack, Name("Scan" .. i), { fill = color }, { 0, 0.5, 0, 0.5 })
                VBoxAdd(stack, row, { 0, 0, 0, period - 1 })
            end
            Paint.SetShown(stack, true)
            Place(body, stack, (tonumber(panel.width) or 0) + 1, H_FILL, V_TOP)
            fx.scanlines = stack
            clip = true
        end)
    end

    if clip then
        pcall(function()
            body:SetClipping(1)
        end)
    end
end

--- The title text of a header, with the two coloured ghost copies behind it when the look glitches.
--- It records S.fx.title and S.fx.ghosts, which every content build refreshes.
---@param S table
---@param outer any
---@param text string
---@param spec table the title's text style, already tinted for its band
---@param size number
---@param resolved table
---@param suffix string
---@return any widget the TextBlock, or an Overlay holding the ghosts and the TextBlock
function M.Title(S, outer, text, spec, size, resolved, suffix)
    local function Block(name, style)
        local block = Construct("/Script/UMG.TextBlock", outer, name)
        Paint.Text(block, style, size)
        Umg.SetLabelText(block, Paint.Caption(text, style))
        return block
    end
    local title = Block("ModMenu_Title_" .. suffix, spec)
    if S.fx == nil then
        M.Reset(S)
    end
    S.fx.title = title
    S.fx.ghosts = {}
    local motion = resolved.motion or {}
    if not motion.glitch then
        return title
    end

    -- Two copies behind the title, one red and one in the accent, shown for a moment during a glitch.
    local palette = resolved.palette
    local stack = Construct("/Script/UMG.Overlay", outer, "ModMenu_TitleStack_" .. suffix)
    local function Ghost(name, color, pad)
        local style = {}
        for k, v in pairs(spec) do
            style[k] = v
        end
        style.color = Alpha(color, 0.8)
        style.shadow = false
        local ghost = Block(name, style)
        Place(stack, ghost, pad, H_LEFT, V_TOP)
        Paint.SetShown(ghost, false)
        return ghost
    end
    local ok = pcall(function()
        local a = Ghost("ModMenu_TitleGhostA_" .. suffix, palette.danger, { 3, 0, 0, 0 })
        local b = Ghost("ModMenu_TitleGhostB_" .. suffix, palette.accent, { 0, 0, 3, 0 })
        Place(stack, title, 0, H_LEFT, V_TOP)
        S.fx.ghosts = { a, b }
    end)
    if not ok then
        S.fx.ghosts = {}
        pcall(function()
            title:RemoveFromParent()
        end)
        return title
    end
    return stack
end

--- The cursor block of the bar header, 10 by 20 in the accent text colour, or nil when the look has
--- no cursor. It records S.fx.cursor. The caller places it after the titles.
---@param S table
---@param outer any
---@param resolved table
---@param suffix string
---@return any|nil
function M.Cursor(S, outer, resolved, suffix)
    local motion = resolved.motion or {}
    if not motion.cursor then
        return nil
    end
    if S.fx == nil then
        M.Reset(S)
    end
    local box = Paint.Box(outer, "ModMenu_Cursor_" .. suffix, { fill = resolved.palette.accentText }, 0)
    local sized = Sized(outer, "ModMenu_CursorSize_" .. suffix, box, 10, 20)
    Paint.SetShown(sized, true)
    S.fx.cursor = sized
    return sized
end

return M
