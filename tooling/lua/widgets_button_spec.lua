-- The button widget is tested through Button.poll and Button.pollClick with a fake pointer, because
-- building the UMG widgets needs the engine, which MoonSharp does not have. A mouse click fires when
-- the pointer is released over the button, and a touch tap fires on the press edge.
local okButton, Button = pcall(require, "ModMenu.widgets.button")
assert_true("widgets.button loads under MoonSharp", okButton)
if not okButton then
    return
end

-- FireClick schedules a delayed re-claim of the menu input; the spec has no game thread to run it.
ExecuteInGameThreadWithDelay = function() end

-- Input requires UEHelpers at load, so an empty stub stands in when no earlier spec loaded it.
local stubbedHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local okInput, Input = pcall(require, "ModMenu.core.input")
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
assert_true("core.input loads under MoonSharp", okInput)
if not okInput then
    return
end

--- A pointer the spec drives by setting fields; the fake widget reports them to the real Input.
local function newPointer(touch)
    return { down = false, hovered = true, touch = touch == true }
end

local function newWidget(pointer)
    local widget = {}
    function widget:IsPressed()
        return pointer.down
    end
    function widget:HasMouseCapture()
        return pointer.down
    end
    function widget:IsHovered()
        return pointer.hovered
    end
    return widget
end

local function newContext()
    return {
        Input = Input,
        umg = { TrackPointer = function() end },
        SafeCall = function(fn)
            fn()
        end,
        ReclaimMenuInput = function() end,
    }
end

local function newControl(pointer, clicks)
    return {
        kind = "button",
        widget = newWidget(pointer),
        item = {
            id = "b",
            variant = "default",
            onClick = function()
                clicks.count = clicks.count + 1
            end,
        },
    }
end
local function setup(touch)
    local clicks = { count = 0 }
    local pointer = newPointer(touch)
    Input.SetPointerMode(touch and "touch" or "mouse")
    return newControl(pointer, clicks), newContext(), pointer, clicks
end

-- A press then a release over the button is one click, and it lands on the release tick.
do
    local ctrl, ctx, pointer, clicks = setup(false)
    pointer.down = true
    Button.poll(ctrl, ctx)
    assert_eq("a held mouse button fires no click while it is down", clicks.count, 0)
    pointer.down = false
    Button.poll(ctrl, ctx)
    assert_eq("a release over the button fires one click", clicks.count, 1)
    Button.poll(ctrl, ctx)
    assert_eq("the next idle poll fires no second click", clicks.count, 1)
end

-- A release after the pointer left the button cancels the click.
do
    local ctrl, ctx, pointer, clicks = setup(false)
    pointer.down = true
    Button.poll(ctrl, ctx)
    pointer.hovered = false
    pointer.down = false
    Button.poll(ctrl, ctx)
    assert_eq("a release off the button fires no click", clicks.count, 0)
end

-- A press that never ends has not clicked yet.
do
    local ctrl, ctx, pointer, clicks = setup(false)
    pointer.down = true
    Button.poll(ctrl, ctx)
    Button.poll(ctrl, ctx)
    Button.poll(ctrl, ctx)
    assert_eq("a press with no release fires no click", clicks.count, 0)
end

-- A touch tap has no held phase, so it fires on the press edge.
do
    local ctrl, ctx, pointer, clicks = setup(true)
    pointer.down = true
    Button.poll(ctrl, ctx)
    assert_eq("a touch press fires one click on the down edge", clicks.count, 1)
    Button.poll(ctrl, ctx)
    assert_eq("a held touch fires no second click", clicks.count, 1)
end

-- The mouse-down latch claims the press without firing, and a latch that never shows as held expires.
do
    local ctrl, ctx, pointer, clicks = setup(false)
    assert_true("the latch on a hovered mouse button consumes the click", Button.pollClick(ctrl, ctx) == true)
    assert_eq("the latch alone fires no click", clicks.count, 0)
    assert_true("the latch leaves the button armed", ctrl.armed == true)
    for _ = 1, 5 do
        Button.poll(ctrl, ctx)
    end
    assert_true("an armed latch survives five polls", ctrl.armed == true)
    Button.poll(ctrl, ctx)
    assert_true("an armed latch that never shows as held expires on the sixth poll", ctrl.armed == false)
    assert_eq("an expired latch fires no click", clicks.count, 0)
    pointer.hovered = false
    assert_true("the latch off the button is not consumed", Button.pollClick(ctrl, ctx) == false)
end

-- The fill helpers repaint the Border behind a transparent Button. A fake Border records the colour it
-- was given, and a fake Button reports the pointer state, so no engine is needed.
local okUmg, Umg = pcall(require, "ModMenu.core.umg")
assert_true("core.umg loads under MoonSharp", okUmg)
if okUmg then
    local function newFill()
        local fill = { color = nil }
        function fill:SetBrushColor(color)
            self.color = color
        end
        return fill
    end
    local function newButton()
        local button = { hovered = false, pressed = false, background = nil }
        function button:IsHovered()
            return self.hovered
        end
        function button:IsPressed()
            return self.pressed
        end
        function button:SetBackgroundColor(color)
            self.background = color
        end
        return button
    end
    local normal = { R = 0.4, G = 0.4, B = 0.4, A = 1 }
    local hover = { R = 0.6, G = 0.6, B = 0.6, A = 1 }
    local pressed = { R = 0.2, G = 0.2, B = 0.2, A = 1 }

    local ctrl = { widget = newButton(), fill = newFill() }
    Umg.SetFillColors(ctrl, normal, hover, pressed)
    assert_eq("SetFillColors paints the resting colour on the fill", ctrl.fill.color, normal)
    assert_eq("SetFillColors makes the button transparent", ctrl.widget.background.A, 0)

    ctrl.widget.hovered = true
    Umg.TrackPointer(ctrl)
    assert_eq("TrackPointer paints the hover colour", ctrl.fill.color, hover)
    ctrl.widget.pressed = true
    Umg.TrackPointer(ctrl)
    assert_eq("TrackPointer paints the pressed colour", ctrl.fill.color, pressed)
    ctrl.widget.hovered = false
    ctrl.widget.pressed = false
    Umg.TrackPointer(ctrl)
    assert_eq("TrackPointer returns to the resting colour", ctrl.fill.color, normal)

    local bare = { widget = newButton() }
    bare.widget.hovered = true
    Umg.TrackPointer(bare)
    assert_eq("TrackPointer leaves a control with no fill alone", bare.lastState, nil)

    local derived = { widget = newButton(), fill = newFill() }
    Umg.SetFill(derived, normal)
    derived.widget.hovered = true
    Umg.TrackPointer(derived)
    assert_true("SetFill derives a lighter hover colour", derived.fill.color.R > normal.R)
end

-- Button.States decides a button's look from the resolved theme with no engine, so each theme's
-- choice of variant, role, shape and outline is checked here.
local okStyle, Style = pcall(require, "ModMenu.core.style")
local okPaint, Paint = pcall(require, "ModMenu.core.paint")
local okTheme, Theme = pcall(require, "ModMenu.core.theme")
assert_true("core.style, core.paint and core.theme load for Button.States", okStyle and okPaint and okTheme)
assert_true("Button.States exists", type(Button.States) == "function")
if okStyle and okPaint and okTheme and type(Button.States) == "function" then
    local light = Style.Resolve("light")
    local slate = Style.Resolve("slate")
    local legacyLight = Theme.Preset("light")

    local primary = Button.States(light, { variant = "primary" })
    assert_eq("light primary rests on the legacy buttonBgPrimary", primary.normal.fill, legacyLight.buttonBgPrimary)
    assert_eq("light primary captions use the legacy buttonTextPrimary", primary.text, legacyLight.buttonTextPrimary)
    assert_true("light primary is flat in every state", Paint.IsFlat(primary.normal) and Paint.IsFlat(primary.hover)
        and Paint.IsFlat(primary.pressed) and Paint.IsFlat(primary.disabled))
    assert_eq("light primary draws no outline", primary.edge, nil)
    assert_true("light primary keeps the legacy recoloured button", Paint.NeedsShapes(primary) == false)
    local legacyStates = Theme.ButtonStates(legacyLight, "primary")
    assert_eq("light primary hover is today's hover", primary.hover.fill, legacyStates.hover)
    assert_eq("light primary pressed is today's pressed", primary.pressed.fill, legacyStates.pressed)

    local dark = Style.Resolve("dark")
    local darkDefault = Button.States(dark, {})
    local legacyDark = Theme.Preset("dark")
    assert_eq("dark default rests on the legacy buttonBg", darkDefault.normal.fill, legacyDark.buttonBg)
    assert_true("dark default keeps the legacy recoloured button", Paint.NeedsShapes(darkDefault) == false)

    local slateDefault = Button.States(slate, {})
    assert_eq("slate buttons have radius 8", slateDefault.normal.radius, 8)
    assert_true("slate buttons draw their own shapes", Paint.NeedsShapes(slateDefault) == true)

    local ghostTheme = Style.Resolve({ button = { variant = "ghost", pill = true, width = 2 } })
    local ghost = Button.States(ghostTheme, { variant = "primary" })
    assert_eq("a pill ghost theme gives pill shapes", ghost.normal.pill, true)
    assert_eq("a ghost outline takes the button width", ghost.edge and ghost.edge.width, 2)
    assert_eq("a ghost rests clear", ghost.normal.fill.A, 0)
    assert_eq("a ghost caption takes the role colour", ghost.text, ghostTheme.button.roles.primary.fill)

    local disabled = Button.States(slate, { variant = "primary", enabled = false })
    assert_eq("a disabled button does not change on hover", disabled.hover, disabled.normal)
    assert_eq("a disabled button does not change on press", disabled.pressed, disabled.normal)
    assert_eq("a disabled button uses the disabled role", disabled.normal.fill, slate.button.roles.disabled.fill)

    local active = Button.States(slate, { variant = "danger", active = true })
    assert_eq("an active button uses the active role", active.normal.fill, slate.button.roles.active.fill)
    assert_eq("an active button keeps one fill on hover", active.hover, active.normal)

    local looked = Button.States(slate, { look = { radius = 0 } })
    assert_eq("an item look radius 0 overrides slate's radius", looked.normal.radius, 0)

    local soft = Button.States(Style.Resolve({ button = { variant = "soft" } }), { variant = "primary" })
    assert_true("a soft button rests on a faint tint", soft.normal.fill.A > 0 and soft.normal.fill.A < 0.5)

    local underline = Button.States(Style.Resolve({ button = { variant = "underline" } }), {})
    assert_true("an underline button names its bar colour", underline.underline ~= nil)
    assert_eq("an underline button draws no outline", underline.edge, nil)

    local stepperish = Button.States(slate, {}, { radius = 0, pill = false })
    assert_eq("an override table wins over the button radius", stepperish.normal.radius, 0)

    local ghostDisabled = Button.States(ghostTheme, { variant = "primary", enabled = false })
    assert_eq("a disabled ghost outlines in the disabled tone", ghostDisabled.edge and ghostDisabled.edge.outline,
        ghostTheme.button.roles.disabled.text)

    local neonLike = Style.Resolve({ base = "neon" })
    local neonDefault = Button.States(neonLike, {})
    assert_true("a neon-based theme has a clear default fill", neonLike.button.roles.default.fill.A < 0.05)
    assert_eq("a clear default tone gives way to the role text for the ghost edge",
        neonDefault.edge and neonDefault.edge.outline, neonLike.button.roles.default.text)
    assert_eq("a clear default tone gives way to the role text for the caption", neonDefault.text,
        neonLike.button.roles.default.text)

    assert_eq("a themed button relabels in its theme's upper case",
        Button.CaptionText({ themed = true, captionSpec = { upper = true } }, "Go now"), "GO NOW")
    assert_eq("a themed button with no text style relabels as given",
        Button.CaptionText({ themed = true }, "Go now"), "Go now")
    assert_eq("a legacy button relabels as given", Button.CaptionText({ captionSpec = { upper = true } }, "Go now"), "Go now")
end

-- The xp and classic variants draw layered looks from the theme's xp and bevel tables, faces replace a
-- role's colours, and height asks for a minimum-height wrapper only when the theme sets it.
if okStyle and okPaint and type(Button.States) == "function" then
    local function hasOutline(look, color)
        for _, layer in ipairs(look.layers or {}) do
            -- ForItem copies tables, so colours are compared by channel, not identity.
            local o = layer.outline
            if o ~= nil and o.R == color.R and o.G == color.G and o.B == color.B and o.A == color.A then
                return true
            end
        end
        return false
    end
    local xpDef = {
        base = "slate",
        button = {
            variant = "xp",
            radius = 3,
            height = 28,
            xp = {
                edge = "#003C74",
                glow = "#F8B33A",
                defaultRing = "#8CB4F0",
                face = { "#FFFFFF", "#F4F3EE" },
                pressedFace = { "#F4F3EE", "#C0C0C0" },
            },
            faces = { secondary = { fill = "#ECE9D8", text = "#112233" } },
        },
    }
    local xp = Style.Resolve(xpDef)
    local x = xp.button.xp
    local primaryXp = Button.States(xp, { variant = "primary" })
    assert_true("an xp button draws its own shapes", Paint.NeedsShapes(primaryXp) == true)
    assert_eq("xp normal starts with the face gradient", primaryXp.normal.layers[1].gradient.stops, x.face)
    assert_eq("xp pressed starts with the pressed face gradient", primaryXp.pressed.layers[1].gradient.stops, x.pressedFace)
    assert_true("xp normal draws the edge ring", hasOutline(primaryXp.normal, x.edge))
    assert_true("xp pressed draws the edge ring", hasOutline(primaryXp.pressed, x.edge))
    assert_true("a primary xp button rests with the default ring", hasOutline(primaryXp.normal, x.defaultRing))
    assert_true("xp hover shows the glow ring", hasOutline(primaryXp.hover, x.glow))
    assert_true("xp hover drops the default ring", not hasOutline(primaryXp.hover, x.defaultRing))
    assert_true("xp pressed shows no glow", not hasOutline(primaryXp.pressed, x.glow))
    assert_true("xp normal shows no glow", not hasOutline(primaryXp.normal, x.glow))
    assert_eq("xp height comes from the theme", primaryXp.height, 28)

    local defaultXp = Button.States(xp, {})
    assert_true("a non-primary xp button has no default ring", not hasOutline(defaultXp.normal, x.defaultRing))

    local secondaryXp = Button.States(xp, { variant = "secondary" })
    assert_eq("faces.secondary sets the secondary text colour", secondaryXp.text, xp.button.faces.secondary.text)
    local flatFace = Style.Resolve({ base = "slate", button = { faces = { secondary = { fill = "#ECE9D8", text = "#112233" } } } })
    local faced = Button.States(flatFace, { variant = "secondary" })
    assert_eq("faces.secondary sets the secondary fill", faced.normal.fill, flatFace.button.faces.secondary.fill)

    local disabledXp = Button.States(xp, { variant = "primary", enabled = false })
    assert_eq("a disabled xp button keeps one look", disabledXp.hover, disabledXp.normal)
    assert_eq("a disabled xp button is a flat disabled fill", disabledXp.normal.fill, xp.button.roles.disabled.fill)

    local noXp = Button.States(Style.Resolve({ base = "slate", button = { variant = "xp" } }), { variant = "primary" })
    assert_true("xp with no xp table falls back to a fill look", noXp.normal.layers == nil and noXp.normal.fill ~= nil)

    local classic = Style.Resolve({
        base = "slate",
        button = {
            variant = "classic",
            radius = 0,
            bevel = { light = "#DFDFDF", dark = "#0A0A0A", innerLight = "#FFFFFF", innerDark = "#808080" },
        },
    })
    local classicStates = Button.States(classic, { variant = "primary" })
    assert_true("a classic button draws its own shapes", Paint.NeedsShapes(classicStates) == true)
    assert_eq("classic pressed shifts the caption one unit down and right", classicStates.pressed.shift, { x = 1, y = 1 })
    assert_eq("classic normal has no shift", classicStates.normal.shift, nil)
    local function bevelLayer(look)
        for _, layer in ipairs(look.layers or {}) do
            if layer.bevel ~= nil then
                return layer
            end
        end
        return nil
    end
    assert_eq("classic pressed holds a sunken bevel", bevelLayer(classicStates.pressed) and bevelLayer(classicStates.pressed).sunken, true)
    assert_true("classic normal holds a raised bevel", bevelLayer(classicStates.normal) ~= nil and not bevelLayer(classicStates.normal).sunken)
    assert_eq("classic normal fills with the role face", classicStates.normal.layers[1].fill, classic.button.roles.primary.fill)
    assert_eq("a theme with no height gives no height", classicStates.height, nil)

    local bare = Button.States(Style.Resolve({ base = "slate", button = { variant = "classic" } }), { variant = "primary" })
    assert_true("classic with no bevel draws a flat role fill", bare.normal.layers == nil and bare.normal.fill ~= nil)

    assert_eq("slate buttons have no height wrapper", Button.States(Style.Resolve("slate"), {}).height, nil)

    local okStepper, Stepper = pcall(require, "ModMenu.widgets.stepper")
    if okStepper and type(Stepper._states) == "function" then
        local stepXp = Stepper._states(xp, {})
        assert_true("stepper buttons follow the xp button looks", stepXp.normal.layers ~= nil and stepXp.normal.layers[1].gradient ~= nil)
    end
end

-- Confirm buttons take their looks from Button.States, so a ghost theme outlines them as it
-- outlines button items, and light keeps today's flat dialog buttons.
local confirmStub = package.loaded["UEHelpers.UEHelpers"] == nil
if confirmStub then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local okConfirm, Confirm = pcall(require, "ModMenu.shell.confirm")
if confirmStub then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
assert_true("shell.confirm loads under MoonSharp", okConfirm)
if okConfirm and okStyle and okPaint and okTheme then
    assert_true("Confirm.ButtonLook exists", type(Confirm.ButtonLook) == "function")
    local neonConfig = { resolved = Style.Resolve({ base = "neon" }), colors = Theme.Preset("dark") }
    local neonStates, neonCaption = Confirm.ButtonLook(neonConfig, "danger")
    assert_true("a neon confirm button is outlined", neonStates.edge ~= nil and (neonStates.edge.width or 0) > 0)
    assert_eq("a neon confirm button rests clear", neonStates.normal.fill.A, 0)
    assert_eq("a neon confirm caption is the outline colour", neonCaption.color, neonStates.edge and neonStates.edge.outline)
    local neonCancel = Confirm.ButtonLook(neonConfig, "secondary")
    assert_true("a neon cancel button is outlined", neonCancel.edge ~= nil)

    local lightColors = Theme.Preset("light")
    local lightConfig = { resolved = Style.Resolve("light"), colors = lightColors, fontItem = 16 }
    local lightStates, lightCaption = Confirm.ButtonLook(lightConfig, "danger")
    local legacy = Theme.ButtonStates(lightColors, "danger")
    assert_true("a light confirm button stays flat", Paint.NeedsShapes(lightStates) == false)
    assert_eq("a light confirm button rests on the legacy danger fill", lightStates.normal.fill, lightColors.buttonBgDanger)
    assert_eq("a light confirm hover is the legacy hover", lightStates.hover.fill, legacy.hover)
    assert_eq("a light confirm pressed is the legacy pressed", lightStates.pressed.fill, legacy.pressed)
    assert_eq("a light confirm caption is the legacy danger text", lightCaption.color, lightColors.buttonTextDanger)
    assert_eq("a light confirm caption keeps the item font size", lightCaption.size, 16)
    assert_eq("a light confirm caption has no text style", lightCaption.textSpec, nil)
    assert_eq("a light confirm caption keeps its padding", lightCaption.pad, { 12, 4, 12, 4 })

    local underConfig = { resolved = Style.Resolve({ base = "slate", button = { variant = "underline" } }), colors = lightColors }
    local underStates = Confirm.ButtonLook(underConfig, "default")
    assert_eq("an underline confirm button draws no bar", underStates.underline, nil)
    assert_true("an underline confirm button is outlined as ghost", underStates.edge ~= nil)
end