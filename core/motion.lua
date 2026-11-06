--[[
  ModMenu.core.motion — the menu's animation: the open stagger, click pop and shake, the title
  pulse, the cursor blink, the sweep and noise bands, the glints and the glitch of the CRT looks.

  Motion writes render transforms and render opacity only. It never changes layout, and it never
  hides a parent of a clickable widget (the ghosts, the tear and the cursor are overlays with no
  clickable child). The maths are pure functions, so MoonSharp specs check them without UE4SS.
  Tick animates the widgets that shell/effects.lua and shell/build.lua recorded in S.fx. Pop and
  Shake only record a start time, and Tick animates from it.

  Tick writes a transform only while something moves, plus one final write that settles the widget
  back to rest, so a menu with every motion off makes no widget calls per tick.
]]

local Paint = require("ModMenu.core.paint")

local M = {}

local OPEN_STAGGER = 0.06
local OPEN_DURATION = 0.32
local SHAKE_DURATION = 0.4
local POP_DURATION = 0.25
local OPEN_RISE = 24

-- The bands travel the same 1200 units the effects are built for (field note 27). StyleLab moved
-- them 620 units, so the speeds are scaled by the ratio to look the same.
local TRAVEL = 1200
local SPEED_SCALE = 620 / TRAVEL

local EMPTY = {}

--- A small repeatable random number generator, the same recipe as StyleLab's. g holds the seed.
---@param g table
---@return number
local function Rand(g)
    g.seed = (g.seed * 1103515245 + 12345) % 2147483648
    return g.seed / 2147483648
end

--- The opacity and vertical offset of an opening element. Index 1 starts at once, and each later
--- index starts one stagger step after the one before. Past its end it is exactly at rest.
---@param t number seconds since the menu opened
---@param index number 1 for the panel root, 2 for the first section, and so on
---@return number opacity
---@return number y
function M.OpenState(t, index)
    local k = (t - (index - 1) * OPEN_STAGGER) / OPEN_DURATION
    if k >= 1 then
        return 1, 0
    end
    if k < 0 then
        k = 0
    end
    local e = 1 - (1 - k) ^ 3
    return e, (1 - e) * OPEN_RISE
end

--- The horizontal offset of a shake t seconds after it started: a decaying sine, zero at the end.
---@param t number
---@return number
function M.ShakeX(t)
    if t < 0 or t >= SHAKE_DURATION then
        return 0
    end
    return math.sin(t * 60) * 7 * (1 - t / SHAKE_DURATION)
end

--- The scale of a pop t seconds after it started: one swell of 1.5 percent, then exactly 1.
---@param t number
---@return number
function M.PopScale(t)
    if t < 0 or t >= POP_DURATION then
        return 1
    end
    return 1 + 0.015 * math.sin(math.pi * t / POP_DURATION)
end

--- A glitch generator. Its timing follows the seed, so the caller seeds it from the clock and the
--- glitches differ on every run.
---@param seed number
---@return table
function M.NewGlitch(seed)
    seed = math.floor(math.abs(seed)) % 2147483648
    return { seed = seed, nextAt = nil, untilAt = 0, fx = {} }
end

--- Step the generator to time now and return what the glitch does this tick. A glitch starts at a
--- random moment, lasts 0.05 to 0.25 seconds, and mixes at least one of five effects. Glitches
--- sometimes come in bursts. The offsets are drawn fresh on every tick of a glitch.
---@param g table
---@param now number
---@return table fx glitching, jitter, split, flicker, tear, roll, dx, dy, opacity, ghostA, ghostB, tearPos, scan
function M.StepGlitch(g, now)
    if g.nextAt == nil then
        -- The first glitch comes after half a second to two seconds, so two seeds start apart.
        g.nextAt = now + 0.5 + 1.5 * Rand(g)
    end
    if now >= g.nextAt then
        g.untilAt = now + 0.05 + 0.2 * Rand(g)
        g.fx = {
            jitter = Rand(g) < 0.7,
            split = Rand(g) < 0.6,
            flicker = Rand(g) < 0.5,
            tear = Rand(g) < 0.5,
            roll = Rand(g) < 0.3,
        }
        if not (g.fx.jitter or g.fx.split or g.fx.flicker or g.fx.tear or g.fx.roll) then
            g.fx.jitter = true
        end
        g.tearY = 20 + Rand(g) * 380
        g.rollY = (Rand(g) * 2 - 1) * 6
        local gap = Rand(g) < 0.3 and (0.08 + 0.25 * Rand(g)) or (0.7 + 3.0 * Rand(g))
        g.nextAt = g.untilAt + gap
    end

    local glitching = now < g.untilAt
    local f = glitching and g.fx or EMPTY
    local out = {
        glitching = glitching,
        jitter = f.jitter == true,
        split = f.split == true,
        flicker = f.flicker == true,
        tear = f.tear == true,
        roll = f.roll == true,
        dx = 0,
        dy = 0,
        opacity = 1,
    }
    if out.jitter then
        out.dx = (Rand(g) * 2 - 1) * 8
    end
    if out.roll then
        out.dy = g.rollY
    end
    if out.flicker then
        out.opacity = 0.4 + 0.45 * Rand(g)
    end
    if out.split then
        local d = 2 + Rand(g) * 5
        out.ghostA = { x = d, y = (Rand(g) - 0.5) * 2 }
        out.ghostB = { x = -d, y = (Rand(g) - 0.5) * 2 }
    end
    if out.tear then
        out.tearPos = { x = (Rand(g) * 2 - 1) * 10, y = g.tearY }
    end
    -- The scanlines never sit quite still: a small jump now and then, and a wavering strength.
    if Rand(g) < (glitching and 0.6 or 0.12) then
        out.scan = { y = math.floor(Rand(g) * 3), opacity = 0.7 + 0.6 * Rand(g) }
    end
    return out
end

-- The clock the start times come from. The spec host has no os.clock, so a spec replaces this, and
-- Now falls back to 0 where the clock gives no number.
M._clock = os.clock

local function Now()
    local v = M._clock ~= nil and M._clock() or nil
    return type(v) == "number" and v or 0
end

-- A seed from the clock, so the timing differs between runs.
local function ClockSeed()
    return math.floor((Now() * 1000003) % 2147483647) + 1
end

local function MotionOf(S)
    local resolved = S.config and S.config.resolved
    return resolved and resolved.motion or EMPTY, resolved and resolved.panel or EMPTY
end

--- Record the start time of a click pop. Tick animates it, only when motion.pop is on.
---@param S table
function M.Pop(S)
    if MotionOf(S).pop then
        S.popAt = Now()
    end
end

--- Record the start time of a shake, only when motion.shake is on.
---@param S table
function M.Shake(S)
    if MotionOf(S).shake then
        S.shakeAt = Now()
    end
end

-- The widgets that Put writes to may be gone after a rebuild, and one stale handle must not stop
-- the rest, so each write is guarded and the first failure is raised at the end of the tick.
local function Put(st, fn)
    local ok, err = pcall(fn)
    if not ok and st.firstError == nil then
        st.firstError = err
    end
end

local function WriteTransform(widget, x, y, scale, opacity)
    widget:SetRenderOpacity(opacity)
    widget:SetRenderTranslation({ X = x, Y = y })
    if scale ~= nil then
        widget:SetRenderScale({ X = scale, Y = scale })
    end
end

local function NewState(now)
    return {
        wasMoving = false,
        sectionsActive = false,
        sweepPos = 0,
        noisePos = 0.5,
        sweepSpeed = 0.3,
        noiseSpeed = 0.12,
        lastTick = now,
    }
end

local function WriteSections(st, sections, t)
    for i, group in ipairs(sections) do
        local opacity, y = M.OpenState(t, i + 1)
        for _, widget in ipairs(group) do
            Put(st, function()
                WriteTransform(widget, 0, y, nil, opacity)
            end)
        end
    end
end

--- Animate everything for time now. The first failure of the tick is raised after every part ran,
--- so the caller logs it once and the other motions still play.
---@param S table
---@param now number os.clock seconds
function M.Tick(S, now)
    local motion, panel = MotionOf(S)
    local st = S.motionState
    if st == nil then
        st = NewState(now)
        S.motionState = st
    end
    st.firstError = nil
    local fx = S.fx or EMPTY
    local root = S.panelRoot or fx.root

    -- A new root means the shell was rebuilt, and the new widget starts at rest.
    if root ~= st.root then
        st.root = root
        st.wasMoving = false
    end

    local x, y, scale, opacity = 0, 0, 1, 1

    local t = S.openedAt ~= nil and now - S.openedAt or nil
    local sections = fx.sections or EMPTY
    local rootOpening = false
    local sectionsOpening = false
    if motion.open and t ~= nil then
        rootOpening = t < OPEN_DURATION
        sectionsOpening = t < #sections * OPEN_STAGGER + OPEN_DURATION
        if rootOpening then
            opacity, y = M.OpenState(t, 1)
        end
    end

    local shaking = false
    if S.shakeAt ~= nil then
        local st2 = now - S.shakeAt
        if motion.shake and st2 < SHAKE_DURATION then
            shaking = true
            x = x + M.ShakeX(st2)
        else
            S.shakeAt = nil
        end
    end

    local popping = false
    if S.popAt ~= nil then
        local pt = now - S.popAt
        if motion.pop and pt < POP_DURATION then
            popping = true
            scale = M.PopScale(pt)
        else
            S.popAt = nil
        end
    end

    local glitch = nil
    local glitching = false
    if motion.glitch then
        if st.glitch == nil then
            st.glitch = M.NewGlitch(ClockSeed())
        end
        glitch = M.StepGlitch(st.glitch, now)
        glitching = glitch.glitching
        x = x + glitch.dx
        y = y + glitch.dy
        opacity = opacity * glitch.opacity
    end

    -- One final write after the last moving tick settles the root at exactly rest.
    local moving = rootOpening or shaking or popping or glitching
    if root ~= nil and (moving or st.wasMoving) then
        Put(st, function()
            WriteTransform(root, x, y, scale, opacity)
        end)
    end
    st.wasMoving = moving

    if sectionsOpening or st.sectionsActive then
        WriteSections(st, sections, t or math.huge)
    end
    st.sectionsActive = sectionsOpening

    if glitch ~= nil then
        local ghosts = fx.ghosts or EMPTY
        if st.ghostsRef ~= ghosts then
            st.ghostsRef = ghosts
            st.wasSplit = false
        end
        if ghosts[1] ~= nil and ghosts[2] ~= nil then
            Put(st, function()
                if glitch.split ~= st.wasSplit then
                    st.wasSplit = glitch.split
                    Paint.SetShown(ghosts[1], glitch.split)
                    Paint.SetShown(ghosts[2], glitch.split)
                end
                if glitch.split then
                    ghosts[1]:SetRenderTranslation({ X = glitch.ghostA.x, Y = glitch.ghostA.y })
                    ghosts[2]:SetRenderTranslation({ X = glitch.ghostB.x, Y = glitch.ghostB.y })
                end
            end)
        end

        local tear = fx.tear
        if st.tearRef ~= tear then
            st.tearRef = tear
            st.wasTear = false
        end
        if tear ~= nil then
            Put(st, function()
                if glitch.tear ~= st.wasTear then
                    st.wasTear = glitch.tear
                    Paint.SetShown(tear, glitch.tear)
                end
                if glitch.tear then
                    tear:SetRenderTranslation({ X = glitch.tearPos.x, Y = glitch.tearPos.y })
                end
            end)
        end

        if fx.scanlines ~= nil and glitch.scan ~= nil then
            Put(st, function()
                fx.scanlines:SetRenderTranslation({ X = 0, Y = glitch.scan.y })
                fx.scanlines:SetRenderOpacity(glitch.scan.opacity)
            end)
        end
    end

    if motion.pulse and fx.title ~= nil then
        Put(st, function()
            fx.title:SetRenderOpacity(0.8 + 0.2 * (0.5 + 0.5 * math.sin(now * 3)))
        end)
    end

    if motion.cursor and fx.cursor ~= nil then
        if st.cursorRef ~= fx.cursor then
            st.cursorRef = fx.cursor
            st.cursorOn = nil
        end
        local on = (now * 2) % 2 < 1
        if on ~= st.cursorOn then
            st.cursorOn = on
            Put(st, function()
                Paint.SetShown(fx.cursor, on)
            end)
        end
    end

    local dt = math.min(0.1, now - st.lastTick)
    st.lastTick = now
    if panel.sweep and fx.sweep ~= nil then
        -- The sweep and the noise band each pick a new speed every time they wrap around.
        if st.rng == nil then
            st.rng = { seed = ClockSeed() }
        end
        st.sweepPos = st.sweepPos + dt * st.sweepSpeed
        st.noisePos = st.noisePos + dt * st.noiseSpeed
        if st.sweepPos > 1 then
            st.sweepPos = 0
            st.sweepSpeed = (0.18 + 0.35 * Rand(st.rng)) * SPEED_SCALE
        end
        if st.noisePos > 1 then
            st.noisePos = 0
            st.noiseSpeed = (0.06 + 0.2 * Rand(st.rng)) * SPEED_SCALE
        end
        Put(st, function()
            fx.sweep:SetRenderTranslation({ X = 0, Y = st.sweepPos * TRAVEL - 60 })
            if fx.noise ~= nil then
                fx.noise:SetRenderTranslation({ X = 0, Y = st.noisePos * TRAVEL - 40 })
            end
        end)
    end

    if motion.sparkle and fx.sparkles ~= nil then
        for i, dot in ipairs(fx.sparkles) do
            local v = math.max(0, math.sin(now * 1.1 + i * 1.9))
            Put(st, function()
                dot:SetRenderOpacity(0.15 + 0.85 * v ^ 6)
            end)
        end
    end

    if st.firstError ~= nil then
        error(st.firstError, 0)
    end
end

--- Begin the open animation: record the start time, forget the old state and draw the first frame
--- at once, so the panel never shows one full frame before it fades in.
---@param S table
---@param now number
function M.Start(S, now)
    S.openedAt = now
    S.popAt = nil
    S.shakeAt = nil
    S.motionState = nil
    M.Tick(S, now)
end

--- End the animation when the menu closes: put a half-finished panel back at rest, hide the glitch
--- overlays, and clear the start times so nothing is left for the next open.
---@param S table
function M.Stop(S)
    local st = S.motionState
    local fx = S.fx or EMPTY
    local root = S.panelRoot or fx.root
    S.openedAt = nil
    S.popAt = nil
    S.shakeAt = nil
    S.motionState = nil
    if st == nil then
        return
    end
    st.firstError = nil
    if st.wasMoving and root ~= nil then
        Put(st, function()
            WriteTransform(root, 0, 0, 1, 1)
        end)
    end
    if st.sectionsActive then
        WriteSections(st, fx.sections or EMPTY, math.huge)
    end
    if st.wasSplit and fx.ghosts ~= nil then
        Put(st, function()
            Paint.SetShown(fx.ghosts[1], false)
            Paint.SetShown(fx.ghosts[2], false)
        end)
    end
    if st.wasTear and fx.tear ~= nil then
        Put(st, function()
            Paint.SetShown(fx.tear, false)
        end)
    end
    if st.firstError ~= nil then
        error(st.firstError, 0)
    end
end

--- Read the children a vertical box gained since from, as a list of widgets, for the open stagger.
--- A box that does not answer yields an empty list, so the stagger skips that section.
---@param box any
---@param from number|nil the child count before the section was built
---@return table widgets
function M.ChildrenSince(box, from)
    local list = {}
    if from == nil then
        return list
    end
    pcall(function()
        for i = from, box:GetChildrenCount() - 1 do
            list[#list + 1] = box:GetChildAt(i)
        end
    end)
    return list
end

--- The child count of a panel widget, or nil when it cannot be read.
---@param box any
---@return number|nil
function M.ChildCount(box)
    local ok, n = pcall(function()
        return box:GetChildrenCount()
    end)
    if ok and type(n) == "number" then
        return n
    end
    return nil
end

return M
