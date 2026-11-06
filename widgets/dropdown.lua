--[[
  ModMenu widget: dropdown (plain + searchable).

  A stock field, as light and dark have, draws the library's own header and option rows. A frame
  field draws the header from the field style (headerFill, headerText, outline, width, radius) and
  the option rows from the list style (fill, text, hover, more, radius), each look its own shape.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Theme = require("ModMenu.core.theme")
local Options = require("ModMenu.core.options")
local Input = require("ModMenu.core.input")
local Paint = require("ModMenu.core.paint")
local Style = require("ModMenu.core.style")

local Dropdown = {}
Dropdown.type = "dropdown"

local VIS_VISIBLE = 0
local VIS_COLLAPSED = 1

local DROPDOWN_LIST_MAX_HEIGHT = 320
local DROPDOWN_SEARCHABLE_MAX_ROWS = 400
local THEMED_ROW_CAP = 40

local dropdownRowSerial = 0

--- Show a pointer state on a header or row paint table. A themed one is a Paint state button; a
--- stock one is recoloured as the library always has.
local function Track(paint)
    if paint == nil then
        return
    end
    if paint.flat ~= nil then
        Paint.TrackPointer(paint)
    else
        Umg.TrackPointer(paint)
    end
end

--- The row looks of a themed option list: the list fill with its hover colour, or the active
--- button role for the selected row. Every look shares the list radius.
---@param themed table { list, active }
---@param selected boolean
---@return table states, table textColor
function Dropdown._rowStates(themed, selected)
    local list = themed.list
    if selected then
        return { normal = { fill = themed.active.fill, radius = list.radius } }, themed.active.text
    end
    return {
        normal = { fill = list.fill, radius = list.radius },
        hover = { fill = list.hover, radius = list.radius },
    }, list.text
end

--- The themed looks of a dropdown, or nil for the library's own look. The item's look merges into
--- the field style, which decides stock or frame; the option rows read the list style and the
--- active button role for the selected row.
---@param config table|nil
---@param look table|nil
---@return table|nil { field, list, active, textSpec, hintSpec }
function Dropdown._themed(config, look)
    local resolved = config and config.resolved
    if resolved == nil then
        return nil
    end
    local field = Style.ForItem(resolved, "field", look)
    if Umg.IsStockField(field) then
        return nil
    end
    return {
        field = field,
        list = Style.ForItem(resolved, "list", nil),
        active = resolved.button.roles.active,
        textSpec = resolved.body,
        hintSpec = resolved.hint,
    }
end

local function SyncHeader(ctrl)
    local label = ctrl.selectedLabel
    if ctrl.selectedValue == nil or label == nil or label == "" then
        label = ctrl.placeholder or "Select..."
    end
    Umg.SetLabelText(ctrl.headerLabel, tostring(label))
    Umg.SetLabelText(ctrl.arrowLabel, ctrl.expanded and "▲" or "▼")
end

local function RebuildRows(ctrl)
    if ctrl == nil or ctrl.listBox == nil then
        return
    end
    pcall(function()
        ctrl.listBox:ClearChildren()
    end)
    ctrl.optionRows = {}

    local maxVisible = ctrl.maxVisible or 12
    -- A themed row is a shaped button of several widgets, rebuilt on every expand and search
    -- change, so a searchable list builds at most THEMED_ROW_CAP at once and search reaches the
    -- rest. A list without search keeps every row, because a capped row could never be chosen.
    if ctrl.themed ~= nil and ctrl.searchable and maxVisible > THEMED_ROW_CAP then
        maxVisible = THEMED_ROW_CAP
    end
    local filter = ctrl.searchFilter or ""
    local matched = 0
    local shown = 0
    local fontDropdown = ctrl.fontDropdown or 15
    local optionBg = ctrl.optionBg
    local optionText = ctrl.optionText
    local selectedBg = ctrl.optionSelectedBg or optionBg
    local selectedText = ctrl.optionSelectedText or optionText
    local selectedValue = Util.ToPlainString(ctrl.selectedValue) or ctrl.selectedValue

    for _, opt in ipairs(ctrl.list or {}) do
        if Options.OptionMatchesFilter(opt.label, filter) then
            matched = matched + 1
            if shown < maxVisible then
                shown = shown + 1
                dropdownRowSerial = dropdownRowSerial + 1
                local optValue = Util.ToPlainString(opt.value) or opt.value
                local isSelected = selectedValue ~= nil and optValue == selectedValue
                local themed = ctrl.themed
                if themed ~= nil then
                    -- Each row is built with its look written in place and only then added, so the
                    -- list shows it from the first frame even though it is built on expand.
                    local states, textColor = Dropdown._rowStates(themed, isSelected)
                    local paint = Paint.StateButton(
                        ctrl.listBox,
                        ctrl.namePrefix .. "_Opt" .. tostring(dropdownRowSerial),
                        states,
                        opt.label,
                        { color = textColor, size = fontDropdown, textSpec = themed.textSpec, pad = { 8, 4, 8, 4 } }
                    )
                    ctrl.listBox:AddChildToVerticalBox(paint.root)
                    table.insert(ctrl.optionRows, {
                        button = paint.widget,
                        widget = paint.widget,
                        paint = paint,
                        label = paint.label,
                        optLabel = opt.label,
                        optValue = opt.value,
                        wasPressed = false,
                    })
                else
                    local fill, btn, lbl = Umg.CreateFilledButton(
                        ctrl.listBox,
                        ctrl.namePrefix .. "_Opt" .. tostring(dropdownRowSerial),
                        opt.label,
                        isSelected and selectedText or optionText,
                        fontDropdown
                    )
                    ctrl.listBox:AddChildToVerticalBox(fill)
                    local row = {
                        button = btn,
                        widget = btn,
                        fill = fill,
                        label = lbl,
                        optLabel = opt.label,
                        optValue = opt.value,
                        wasPressed = false,
                    }
                    Umg.SetFill(row, isSelected and selectedBg or optionBg)
                    table.insert(ctrl.optionRows, row)
                end
            end
        end
    end

    if ctrl.scrollBox ~= nil then
        pcall(function()
            ctrl.scrollBox:ScrollToStart()
        end)
    end

    if ctrl.moreLabel ~= nil then
        local extra = matched - shown
        if extra > 0 then
            Umg.SetLabelText(ctrl.moreLabel, string.format("…%d more — type to narrow", extra))
            pcall(function()
                ctrl.moreLabel:SetVisibility(VIS_VISIBLE)
            end)
        elseif matched == 0 then
            Umg.SetLabelText(ctrl.moreLabel, "No matches")
            pcall(function()
                ctrl.moreLabel:SetVisibility(VIS_VISIBLE)
            end)
        else
            pcall(function()
                ctrl.moreLabel:SetVisibility(VIS_COLLAPSED)
            end)
        end
    end
end

local function SetExpanded(ctrl, expanded)
    ctrl.expanded = expanded and true or false
    pcall(function()
        if ctrl.optionsBox ~= nil then
            ctrl.optionsBox:SetVisibility(ctrl.expanded and VIS_VISIBLE or VIS_COLLAPSED)
        end
    end)
    if ctrl.expanded then
        if ctrl.searchable then
            ctrl.searchFilter = ""
            pcall(function()
                if ctrl.searchBox ~= nil then
                    ctrl.searchBox:SetText(FText(""))
                end
            end)
        end
        RebuildRows(ctrl)
    end
    SyncHeader(ctrl)
end

function Dropdown.collapseAll(liveControls, exceptCtrl)
    for _, ctrl in ipairs(liveControls or {}) do
        if ctrl.kind == "dropdown" and ctrl ~= exceptCtrl then
            SetExpanded(ctrl, false)
        end
    end
end

local function CreatePicker(outer, namePrefix, options, selectedValue, dropOpts, config)
    dropOpts = dropOpts or {}
    config = config or {}
    local searchable = dropOpts.searchable == true
    local placeholder = dropOpts.placeholder or "Select..."
    local maxVisible = dropOpts.maxVisible
        or (searchable and DROPDOWN_SEARCHABLE_MAX_ROWS or 9999)
    local listMaxHeight = dropOpts.listMaxHeight or DROPDOWN_LIST_MAX_HEIGHT
    local allowEmpty = dropOpts.allowEmpty == true or searchable or dropOpts.placeholder ~= nil
    local fontDropdown = config.fontDropdown or 15
    local fontHint = config.fontHint or 14
    local colors = Theme.Of(config)
    local themed = Dropdown._themed(config, dropOpts.look)
    if themed ~= nil then
        fontDropdown = Paint.TextSize(config, themed.textSpec and themed.textSpec.size, "fontDropdown")
        fontHint = Paint.TextSize(config, themed.hintSpec and themed.hintSpec.size, "fontHint")
    end

    local list, labelToValue, valueToLabel = Options.NormalizeOptions(options)
    selectedValue = Util.ToPlainString(selectedValue) or selectedValue
    local selectedLabel = selectedValue ~= nil and valueToLabel[selectedValue] or nil
    if selectedLabel == nil and #list > 0 and not allowEmpty then
        selectedLabel = list[1].label
        selectedValue = list[1].value
    end
    if selectedLabel == nil then
        selectedLabel = placeholder
        selectedValue = nil
    end

    local root = Umg.Construct("/Script/UMG.VerticalBox", outer, namePrefix .. "_Root")

    local headerFill, headerBtn, headerRow
    if themed == nil then
        -- The Border is the visible fill, and the Button inside it is transparent (see Umg.SetFillColors).
        headerFill = Umg.Construct("/Script/UMG.Border", root, namePrefix .. "_Header_Fill")
        headerBtn = Umg.Construct("/Script/UMG.Button", headerFill, namePrefix .. "_Header_Btn")
        pcall(function()
            headerFill:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
            headerFill:SetContent(headerBtn)
            if headerBtn.SetClickMethod then
                headerBtn:SetClickMethod(1)
            end
            if headerBtn.SetTouchMethod then
                headerBtn:SetTouchMethod(1)
            end
        end)
        headerRow = Umg.Construct("/Script/UMG.HorizontalBox", headerBtn, namePrefix .. "_HeaderRow")
    else
        -- The themed header is a Paint state button built around this row once the row is filled.
        headerRow = Umg.Construct("/Script/UMG.HorizontalBox", root, namePrefix .. "_HeaderRow")
    end
    local headerText = themed ~= nil and themed.field.headerText or colors.dropdownHeaderText
    local headerSpec = themed ~= nil and themed.textSpec or nil

    local valueLabel = Umg.Construct("/Script/UMG.TextBlock", headerRow, namePrefix .. "_Value")
    Umg.StyleText(valueLabel, fontDropdown, headerText, headerSpec)
    Umg.SetLabelText(valueLabel, tostring(selectedLabel))
    local valueSlot = headerRow:AddChildToHorizontalBox(valueLabel)
    pcall(function()
        valueSlot:SetSize({ SizeRule = 1, Value = 1.0 })
        valueSlot:SetPadding({ Left = 10, Top = 8, Right = 6, Bottom = 8 })
        valueSlot:SetVerticalAlignment(2)
    end)

    local arrowLabel = Umg.Construct("/Script/UMG.TextBlock", headerRow, namePrefix .. "_Arrow")
    Umg.StyleText(arrowLabel, fontDropdown, headerText, headerSpec)
    Umg.SetLabelText(arrowLabel, "▼")
    local arrowSlot = headerRow:AddChildToHorizontalBox(arrowLabel)
    pcall(function()
        arrowSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        arrowSlot:SetPadding({ Left = 4, Top = 8, Right = 10, Bottom = 8 })
        arrowSlot:SetVerticalAlignment(2)
    end)

    local headerPaint
    if themed == nil then
        pcall(function()
            headerBtn:SetContent(headerRow)
        end)
        root:AddChildToVerticalBox(headerFill)
        headerPaint = { widget = headerBtn, fill = headerFill }
        Umg.SetFill(headerPaint, colors.dropdownHeaderBg)
    else
        local f = themed.field
        -- The edge is its own Border, because a Button's state brush did not draw an outline
        -- (field note 31); hover and pressed shapes are derived from the header fill.
        headerPaint = Paint.StateButton(root, namePrefix .. "_Header", {
            normal = { fill = f.headerFill, radius = f.radius, pill = f.pill },
            edge = { outline = f.outline, width = f.width },
        }, headerRow)
        headerBtn, headerFill = headerPaint.widget, headerPaint.fill
        root:AddChildToVerticalBox(Paint.Bevelled(root, namePrefix .. "_HeaderBevel", headerPaint.root, f.bevel, true))
    end

    local optionsBox = Umg.Construct("/Script/UMG.VerticalBox", root, namePrefix .. "_Opts")
    pcall(function()
        optionsBox:SetVisibility(VIS_COLLAPSED)
    end)

    local searchBox = nil
    if searchable then
        local searchBorder
        if themed == nil then
            searchBorder = Umg.Construct("/Script/UMG.Border", optionsBox, namePrefix .. "_SearchBorder")
            pcall(function()
                searchBorder:SetBrushColor(colors.fieldBg)
                searchBorder:SetPadding({ Left = 8, Top = 6, Right = 8, Bottom = 6 })
            end)
        else
            local f = themed.field
            searchBorder = Paint.Box(optionsBox, namePrefix .. "_SearchBorder", {
                fill = f.fill,
                outline = f.outline,
                width = f.width,
                radius = f.radius,
                pill = f.pill,
            }, { 8, 6, 8, 6 })
        end
        searchBox = Umg.Construct("/Script/UMG.EditableTextBox", searchBorder, namePrefix .. "_Search")
        pcall(function()
            searchBox:SetHintText(FText("Type to filter..."))
            searchBox:SetText(FText(""))
        end)
        Umg.StyleEditableTextBox(searchBox, fontDropdown, themed and themed.field, themed and themed.textSpec)
        pcall(function()
            searchBorder:SetContent(searchBox)
        end)
        optionsBox:AddChildToVerticalBox(searchBorder)
        Umg.AddSpacer(optionsBox, namePrefix .. "_SearchPad", 6)
    end

    local sizeBox = Umg.Construct("/Script/UMG.SizeBox", optionsBox, namePrefix .. "_ListSize")
    pcall(function()
        sizeBox:SetMaxDesiredHeight(listMaxHeight)
    end)
    local scrollBox = Umg.Construct("/Script/UMG.ScrollBox", sizeBox, namePrefix .. "_Scroll")
    pcall(function()
        sizeBox:SetContent(scrollBox)
    end)

    local listBox = Umg.Construct("/Script/UMG.VerticalBox", scrollBox, namePrefix .. "_List")
    pcall(function()
        scrollBox:AddChild(listBox)
    end)
    Umg.StyleScrollBox(scrollBox, config)
    optionsBox:AddChildToVerticalBox(sizeBox)

    local moreLabel = nil
    if searchable then
        moreLabel = Umg.Construct("/Script/UMG.TextBlock", optionsBox, namePrefix .. "_More")
        Umg.StyleText(moreLabel, fontHint, themed ~= nil and themed.list.more or colors.dropdownMore,
            themed ~= nil and themed.hintSpec or nil)
        Umg.SetLabelText(moreLabel, "")
        pcall(function()
            moreLabel:SetVisibility(VIS_COLLAPSED)
        end)
        optionsBox:AddChildToVerticalBox(moreLabel)
    end

    root:AddChildToVerticalBox(optionsBox)

    local picker = {
        namePrefix = namePrefix,
        list = list,
        labelToValue = labelToValue,
        valueToLabel = valueToLabel,
        selectedValue = selectedValue,
        selectedLabel = selectedLabel,
        placeholder = placeholder,
        searchable = searchable,
        maxVisible = maxVisible,
        fontDropdown = fontDropdown,
        searchFilter = "",
        searchBox = searchBox,
        scrollBox = scrollBox,
        listBox = listBox,
        moreLabel = moreLabel,
        headerBtn = headerBtn,
        headerFill = headerFill,
        headerPaint = headerPaint,
        headerLabel = valueLabel,
        arrowLabel = arrowLabel,
        optionsBox = optionsBox,
        optionRows = {},
        optionBg = colors.dropdownOptionBg,
        optionText = colors.dropdownOptionText,
        optionSelectedBg = colors.buttonBgActive,
        optionSelectedText = colors.buttonTextActive,
        themed = themed,
        expanded = false,
        headerWasPressed = false,
    }

    -- Option buttons spawn on first expand, not at menu build.
    return root, picker
end

function Dropdown.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    -- An empty array is valid because SetOptions can empty a dropdown, and that list is written into
    -- the caller's item, which the mod may pass to Register again.
    if type(item.options) ~= "table" then
        error(prefix .. " dropdown requires an .options array")
    end
    local ok, err = pcall(Options.NormalizeOptions, item.options)
    if not ok then
        error(prefix .. " " .. tostring(err))
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
    if item.maxVisible ~= nil and (type(item.maxVisible) ~= "number" or item.maxVisible < 1) then
        error(prefix .. " maxVisible must be a positive number")
    end
end

function Dropdown.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    if values[vkey] == nil and item.default ~= nil then
        values[vkey] = item.default
    end
end

function Dropdown.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = ctx.values[vkey]
    if current == nil then
        current = item.default
    end

    local caption = umg.Construct("/Script/UMG.TextBlock", ctx.contentBox, ctx.namePrefix .. "_Cap")
    local themed = Dropdown._themed(ctx.config, item.look)
    if themed ~= nil then
        local spec = themed.textSpec
        umg.StyleText(caption, Paint.TextSize(ctx.config, spec and spec.size, "fontHint"), nil, spec)
        umg.SetLabelText(caption, Paint.Caption(item.label, spec))
    else
        umg.StyleText(caption, ctx.config.fontHint)
        umg.SetLabelText(caption, item.label)
    end
    ctx.contentBox:AddChildToVerticalBox(caption)
    umg.RecordNode(ctx, caption)

    local root, picker = CreatePicker(ctx.contentBox, ctx.namePrefix, item.options, current, {
        searchable = item.searchable == true,
        placeholder = item.placeholder,
        maxVisible = item.maxVisible,
        listMaxHeight = item.listMaxHeight,
        allowEmpty = item.allowEmpty,
        look = item.look,
    }, ctx.config)

    ctx.values[vkey] = picker.selectedValue
    ctx.contentBox:AddChildToVerticalBox(root)
    umg.RecordNode(ctx, root)
    umg.RecordNode(ctx, umg.AddSpacer(ctx.contentBox, ctx.namePrefix .. "_Pad", 8))

    table.insert(ctx.liveControls, Dropdown.liveControl(picker, {
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        valueKey = vkey,
    }))
end

--- Shell chrome (dock picker) and Register dropdowns share this control shape.
function Dropdown.liveControl(picker, extra)
    local ctrl = {
        kind = "dropdown",
        namePrefix = picker.namePrefix,
        list = picker.list,
        labelToValue = picker.labelToValue,
        valueToLabel = picker.valueToLabel,
        selectedLabel = picker.selectedLabel,
        selectedValue = picker.selectedValue,
        placeholder = picker.placeholder,
        searchable = picker.searchable,
        maxVisible = picker.maxVisible,
        fontDropdown = picker.fontDropdown,
        searchFilter = picker.searchFilter,
        searchBox = picker.searchBox,
        scrollBox = picker.scrollBox,
        listBox = picker.listBox,
        moreLabel = picker.moreLabel,
        headerBtn = picker.headerBtn,
        headerFill = picker.headerFill,
        headerPaint = picker.headerPaint,
        headerLabel = picker.headerLabel,
        arrowLabel = picker.arrowLabel,
        optionsBox = picker.optionsBox,
        optionRows = picker.optionRows,
        optionBg = picker.optionBg,
        optionText = picker.optionText,
        optionSelectedBg = picker.optionSelectedBg,
        optionSelectedText = picker.optionSelectedText,
        themed = picker.themed,
        expanded = false,
        headerWasPressed = false,
    }
    if type(extra) == "table" then
        for key, value in pairs(extra) do
            ctrl[key] = value
        end
    end
    return ctrl
end

---@param path string
local function SelectOption(ctrl, ctx, row, path)
    Input.DebugClick(path, ctrl, row.button)
    local value = row.optValue
    ctrl.selectedValue = value
    ctrl.selectedLabel = tostring(row.optLabel or value)
    ctx.values[ctrl.valueKey] = value
    SetExpanded(ctrl, false)
    Input.SuppressPressEdge(row)
    Input.SuppressPressEdge(ctrl, "headerWasPressed")
    Input.IgnoreClicks(2)
    ctx.SafeCall(ctrl.item.onChange, value)
    ctx.ReclaimMenuInput()
    ctx.EnsureMenuVisible()
end

---@param path string
local function ToggleHeader(ctrl, ctx, path)
    if Input.WidgetHovered(ctrl.searchBox) then
        return false
    end
    Input.DebugClick(path, ctrl, ctrl.headerBtn)
    local nextExpanded = not ctrl.expanded
    if nextExpanded then
        Dropdown.collapseAll(ctx.liveControls, ctrl)
    end
    SetExpanded(ctrl, nextExpanded)
    if nextExpanded then
        ctx.SafeCall(ctrl.item.onExpand, ctrl.list)
    end
    Input.SuppressPressEdge(ctrl, "headerWasPressed")
    Input.IgnoreClicks(2)
    return true
end

--- Filter text poll while expanded + native UButton press (no LMB latch).
function Dropdown.poll(ctrl, ctx)
    if ctrl.searchable and ctrl.expanded and ctrl.searchBox ~= nil then
        local text = Options.GetWidgetPlainText(ctrl.searchBox)
        if text ~= ctrl.searchFilter then
            ctrl.searchFilter = text
            RebuildRows(ctrl)
        end
    end

    if ctrl.expanded and ctrl.optionRows then
        for _, row in ipairs(ctrl.optionRows) do
            Track(row.paint or row)
            if Input.ReleaseClick(row, row.button) then
                SelectOption(ctrl, ctx, row, "release")
                return
            end
        end
    end
    Track(ctrl.headerPaint)
    if Input.ReleaseClick(ctrl, ctrl.headerBtn) then
        ToggleHeader(ctrl, ctx, "release")
    end
end

--- Option-row click (priority over header). Returns true if consumed.
function Dropdown.pollOptionClick(ctrl, ctx)
    if not ctrl.expanded or not ctrl.optionRows then
        return false
    end
    for _, row in ipairs(ctrl.optionRows) do
        local consumed, fireNow = Input.ArmClick(row, row.button)
        if consumed then
            if fireNow then
                SelectOption(ctrl, ctx, row, "latch-hover")
            end
            return true
        end
    end
    return false
end

--- Header toggle click. Returns true if consumed.
function Dropdown.pollHeaderClick(ctrl, ctx)
    local consumed, fireNow = Input.ArmClick(ctrl, ctrl.headerBtn)
    if not consumed then
        consumed, fireNow = Input.ArmClick(ctrl, ctrl.headerLabel)
    end
    if not consumed then
        return false
    end
    if fireNow then
        return ToggleHeader(ctrl, ctx, "latch-hover")
    end
    return true
end

--- LMB latch: option rows first, then header.
function Dropdown.pollClick(ctrl, ctx)
    if Dropdown.pollOptionClick(ctrl, ctx) then
        return true
    end
    return Dropdown.pollHeaderClick(ctrl, ctx)
end

function Dropdown.apply(ctrl, value, _ctx)
    if value == nil then
        ctrl.selectedValue = nil
        ctrl.selectedLabel = ctrl.placeholder or "Select..."
    else
        local label = ctrl.valueToLabel and ctrl.valueToLabel[value] or tostring(value)
        ctrl.selectedValue = value
        ctrl.selectedLabel = tostring(label)
    end
    SyncHeader(ctrl)
end

--- In-place searchable list refresh (SetOptions path).
function Dropdown.refreshLive(ctrl, list, selectedValue, values, vkey)
    local normalized, labelToValue, valueToLabel = Options.NormalizeOptions(list)
    ctrl.list = normalized
    ctrl.labelToValue = labelToValue
    ctrl.valueToLabel = valueToLabel
    if selectedValue == false then
        ctrl.selectedValue = nil
        ctrl.selectedLabel = ctrl.placeholder or "Select..."
    elseif selectedValue ~= nil then
        local plain = Util.ToPlainString(selectedValue) or selectedValue
        ctrl.selectedValue = plain
        ctrl.selectedLabel = valueToLabel[plain] or tostring(plain)
    elseif ctrl.selectedValue ~= nil and valueToLabel[ctrl.selectedValue] == nil then
        ctrl.selectedValue = nil
        ctrl.selectedLabel = ctrl.placeholder or "Select..."
        values[vkey] = nil
    elseif ctrl.selectedValue ~= nil then
        ctrl.selectedLabel = valueToLabel[ctrl.selectedValue] or ctrl.selectedLabel
    end
    ctrl.searchFilter = ""
    pcall(function()
        if ctrl.searchBox ~= nil then
            ctrl.searchBox:SetText(FText(""))
        end
    end)
    if ctrl.expanded then
        RebuildRows(ctrl)
    end
    SyncHeader(ctrl)
end

function Dropdown.createPicker(outer, namePrefix, options, selectedValue, dropOpts, config)
    return CreatePicker(outer, namePrefix, options, selectedValue, dropOpts, config)
end

function Dropdown.nextRowSerial()
    dropdownRowSerial = dropdownRowSerial + 1
    return dropdownRowSerial
end

return Dropdown
