import type {
  ButtonItem,
  ColorpickerItem,
  ConfirmSpec,
  DropdownItem,
  DropdownOption,
  FoldItem,
  Item,
  KeybindItem,
  MenuDocument,
  MultiselectItem,
  NumberItem,
  RadioItem,
  Section,
  SliderItem,
  ProgressItem,
  StepperItem,
  TextInputItem,
} from "../schema";
import { SPACING_KEYS } from "../schema";
import { ensureIds } from "../editor/model";

function luaString(value: string): string {
  return `"${value.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\r/g, "\\r").replace(/\n/g, "\\n")}"`;
}

function luaStringArray(values: string[]): string {
  return values.length === 0 ? "{}" : `{ ${values.map((value) => luaString(String(value))).join(", ")} }`;
}

function indent(level: number): string {
  return "    ".repeat(level);
}

function keyExpr(hint: string): string | null {
  if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(hint)) {
    return `Key.${hint}`;
  }
  return null;
}

// A JSON document can hold a number where the schema names a string, such as { label: "One", value: 1 }.
// Options.NormalizeOptions in core/options.lua turns such a field into a string with tostring, and
// validation compares String(value), so the export writes the same string.
function plainString(value: unknown): string | undefined {
  return value === undefined || value === null ? undefined : String(value);
}

function emitOptions(options: DropdownOption[], level: number): string {
  const pad = indent(level);
  const inner = indent(level + 1);
  const rows = options.map((opt) => {
    if (typeof opt === "string") {
      return `${inner}${luaString(opt)},`;
    }
    const label = plainString(opt.label);
    const value = plainString(opt.value);
    if (label !== undefined && value !== undefined && label !== value) {
      return `${inner}{ label = ${luaString(label)}, value = ${luaString(value)} },`;
    }
    return `${inner}${luaString(label ?? value ?? "")},`;
  });
  return `{\n${rows.join("\n")}\n${pad}}`;
}

function emitConfirm(confirm: ConfirmSpec, level: number): string {
  const pad = indent(level);
  const inner = indent(level + 1);
  const lines = [`${pad}confirm = {`];
  if (confirm.title !== undefined) {
    lines.push(`${inner}title = ${luaString(confirm.title)},`);
  }
  if (confirm.message !== undefined) {
    lines.push(`${inner}message = ${luaString(confirm.message)},`);
  }
  if (confirm.confirmLabel !== undefined) {
    lines.push(`${inner}confirmLabel = ${luaString(confirm.confirmLabel)},`);
  }
  if (confirm.cancelLabel !== undefined) {
    lines.push(`${inner}cancelLabel = ${luaString(confirm.cancelLabel)},`);
  }
  if (confirm.variant !== undefined) {
    lines.push(`${inner}variant = ${luaString(confirm.variant)},`);
  }
  lines.push(`${pad}},`);
  return lines.join("\n");
}

function stubOnChange(sectionId: string, itemId: string, arg: string): string[] {
  return [
    `onChange = function(${arg})`,
    `    -- TODO: game call`,
    `    -- local value = ModMenu.Get(${luaString(sectionId)}, ${luaString(itemId)})`,
    `end,`,
  ];
}

function stubOnClick(sectionId: string, itemId: string): string[] {
  return [
    `onClick = function()`,
    `    -- TODO: game call`,
    `    -- ModMenu.Get(${luaString(sectionId)}, ${luaString(itemId)})`,
    `end,`,
  ];
}

function emitFieldLines(lines: string[], pad: string, fields: Array<[string, string | undefined]>) {
  for (const [key, value] of fields) {
    if (value !== undefined) {
      lines.push(`${pad}${key} = ${value},`);
    }
  }
}

// enabled and visible are common to every item. A true value is the library's default, so only false is written.
function stateFields(item: Item): Array<[string, string | undefined]> {
  return [
    ["enabled", item.enabled === false ? "false" : undefined],
    ["visible", item.visible === false ? "false" : undefined],
  ];
}

// An imported document can hold text where the schema names a number, and the export writes the
// value into the Lua as code. Only a finite number is written, so text never becomes Lua.
function numberField(value: unknown): string | undefined {
  return typeof value === "number" && Number.isFinite(value) ? String(value) : undefined;
}

const COLOR_CHANNELS = ["R", "G", "B", "A"] as const;

const LUA_KEYWORDS = new Set([
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
  "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
]);

function luaKey(key: string): string {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(key) && !LUA_KEYWORDS.has(key) ? key : `[${luaString(key)}]`;
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// A colour table keeps the R, G, B, A order the colour picker's default uses.
function colorOrder(keys: string[]): string[] | null {
  const order = COLOR_CHANNELS.filter((key) => keys.includes(key));
  return keys.length >= 3 && order.length === keys.length && keys.includes("R") ? order : null;
}

// A style value written as a one-line Lua constructor: strings quoted, finite numbers, booleans, lists,
// and tables with their keys sorted so the export is stable. A value of any other shape, such as text
// where a number should be or a non-finite number, is left out rather than written as code.
function luaValue(value: unknown): string | undefined {
  if (typeof value === "string") {
    return luaString(value);
  }
  if (typeof value === "number") {
    return numberField(value);
  }
  if (typeof value === "boolean") {
    return value ? "true" : "false";
  }
  if (Array.isArray(value)) {
    const parts = value.map(luaValue);
    if (parts.some((part) => part === undefined)) {
      return undefined;
    }
    return parts.length === 0 ? "{}" : `{ ${parts.join(", ")} }`;
  }
  if (!isPlainObject(value)) {
    return undefined;
  }
  const fields = luaFields(value);
  return fields.length === 0 ? "{}" : `{ ${fields.join(", ")} }`;
}

function luaFields(table: Record<string, unknown>): string[] {
  const keys = Object.keys(table);
  const order = colorOrder(keys) ?? [...keys].sort();
  return order.flatMap((key) => {
    const text = luaValue(table[key]);
    return text === undefined ? [] : [`${luaKey(key)} = ${text}`];
  });
}

// An item's look, written only when it has a field to write.
function lookField(item: Item): string | undefined {
  if (!isPlainObject(item.look)) {
    return undefined;
  }
  const fields = luaFields(item.look);
  return fields.length > 0 ? `{ ${fields.join(", ")} }` : undefined;
}

function emitItem(item: Item, sectionId: string, level: number): string {
  const pad = indent(level);
  const inner = indent(level + 1);
  const tooltip = item.tooltip !== undefined ? luaString(item.tooltip) : undefined;
  if (item.type === "separator") {
    const parts = [`type = "separator"`];
    if (tooltip !== undefined) {
      parts.push(`tooltip = ${tooltip}`);
    }
    for (const [key, value] of stateFields(item)) {
      if (value !== undefined) {
        parts.push(`${key} = ${value}`);
      }
    }
    return `${pad}{ ${parts.join(", ")} },`;
  }
  if (item.type === "row") {
    const children = item.items.map((child) => emitItem(child, sectionId, level + 2)).join("\n");
    const lines = [`${pad}{`, `${inner}type = "row",`];
    emitFieldLines(lines, inner, [["tooltip", tooltip], ...stateFields(item)]);
    lines.push(`${inner}items = {`, children, `${inner}},`, `${pad}},`);
    return lines.join("\n");
  }
  if (item.type === "fold") {
    const fold = item as FoldItem;
    const children = fold.items.map((child) => emitItem(child, sectionId, level + 2)).join("\n");
    const lines = [
      `${pad}{`,
      `${inner}type = "fold",`,
      `${inner}id = ${luaString(fold.id)},`,
      `${inner}label = ${luaString(fold.label)},`,
    ];
    emitFieldLines(lines, inner, [["tooltip", tooltip], ...stateFields(item)]);
    if (fold.collapsed !== undefined) {
      lines.push(`${inner}collapsed = ${fold.collapsed ? "true" : "false"},`);
    }
    lines.push(`${inner}items = {`, children, `${inner}},`, `${pad}},`);
    return lines.join("\n");
  }

  const lines = [`${pad}{`, `${inner}type = ${luaString(item.type)},`];
  if ("id" in item && item.id) {
    lines.push(`${inner}id = ${luaString(item.id)},`);
  }
  if ("label" in item) {
    lines.push(`${inner}label = ${luaString(item.label)},`);
  }
  // A button writes enabled after its variant, where it always did, so a saved document exports the same text.
  const common = item.type === "button" ? stateFields(item).filter(([key]) => key !== "enabled") : stateFields(item);
  emitFieldLines(lines, inner, [["tooltip", tooltip], ...common]);

  if (item.type === "label") {
    emitFieldLines(lines, inner, [
      ["align", item.align !== undefined ? luaString(item.align) : undefined],
      ["wrap", item.wrap === false ? "false" : undefined],
      ["style", item.style !== undefined && item.style !== "normal" ? luaString(item.style) : undefined],
    ]);
  } else if (item.type === "button") {
    const button = item as ButtonItem;
    emitFieldLines(lines, inner, [
      ["variant", button.variant && button.variant !== "default" ? luaString(button.variant) : undefined],
      ["enabled", button.enabled === false ? "false" : undefined],
      ["active", button.active === true ? "true" : undefined],
    ]);
    if (button.confirm) {
      lines.push(emitConfirm(button.confirm, level + 1));
    }
    for (const stub of stubOnClick(sectionId, button.id)) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "checkbox") {
    if (item.default !== undefined) {
      lines.push(`${inner}default = ${item.default ? "true" : "false"},`);
    }
    emitFieldLines(lines, inner, [["showState", item.showState === false ? "false" : undefined]]);
    for (const stub of stubOnChange(sectionId, item.id, "on")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "dropdown") {
    const drop = item as DropdownItem;
    lines.push(`${inner}options = ${emitOptions(drop.options, level + 1)},`);
    if (drop.default !== undefined && drop.default !== null) {
      lines.push(`${inner}default = ${luaString(drop.default)},`);
    }
    emitFieldLines(lines, inner, [
      ["searchable", drop.searchable === true ? "true" : undefined],
      ["placeholder", drop.placeholder ? luaString(drop.placeholder) : undefined],
      ["maxVisible", numberField(drop.maxVisible)],
      ["listMaxHeight", numberField(drop.listMaxHeight)],
      ["allowEmpty", drop.allowEmpty === true ? "true" : undefined],
    ]);
    for (const stub of stubOnChange(sectionId, drop.id, "value")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "number") {
    const num = item as NumberItem;
    emitFieldLines(lines, inner, [
      ["default", numberField(num.default)],
      ["min", numberField(num.min)],
      ["max", numberField(num.max)],
      ["integer", num.integer === true ? "true" : undefined],
      ["placeholder", num.placeholder ? luaString(num.placeholder) : undefined],
      ["fieldWidth", numberField(num.fieldWidth)],
      ["labelWidth", numberField(num.labelWidth)],
      ["debounceMs", numberField(num.debounceMs)],
      ["step", numberField(num.step)],
      ["prefix", num.prefix ? luaString(num.prefix) : undefined],
      ["suffix", num.suffix ? luaString(num.suffix) : undefined],
    ]);
    for (const stub of stubOnChange(sectionId, num.id, "n")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "textinput") {
    const text = item as TextInputItem;
    emitFieldLines(lines, inner, [
      ["default", text.default !== undefined ? luaString(text.default) : undefined],
      ["placeholder", text.placeholder ? luaString(text.placeholder) : undefined],
      ["maxLength", numberField(text.maxLength)],
      ["fieldWidth", numberField(text.fieldWidth)],
      ["labelWidth", numberField(text.labelWidth)],
      ["debounceMs", numberField(text.debounceMs)],
    ]);
    for (const stub of stubOnChange(sectionId, text.id, "text")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "slider") {
    const slider = item as SliderItem;
    emitFieldLines(lines, inner, [
      ["default", numberField(slider.default)],
      ["min", numberField(slider.min)],
      ["max", numberField(slider.max)],
      ["step", numberField(slider.step)],
      ["integer", slider.integer === true ? "true" : undefined],
      ["format", slider.format !== undefined ? luaString(slider.format) : undefined],
      ["live", slider.live === true ? "true" : undefined],
      ["showValue", slider.showValue === false ? "false" : undefined],
      ["labelWidth", numberField(slider.labelWidth)],
    ]);
    for (const stub of stubOnChange(sectionId, slider.id, "value")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "stepper") {
    const stepper = item as StepperItem;
    emitFieldLines(lines, inner, [
      ["default", numberField(stepper.default)],
      ["min", numberField(stepper.min)],
      ["max", numberField(stepper.max)],
      ["step", numberField(stepper.step)],
      ["integer", stepper.integer === true ? "true" : undefined],
      ["format", stepper.format !== undefined ? luaString(stepper.format) : undefined],
    ]);
    for (const stub of stubOnChange(sectionId, stepper.id, "value")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "progress") {
    // A progress bar has no input, so no onChange stub is written. A default variant is left out, as a button's is.
    const progress = item as ProgressItem;
    emitFieldLines(lines, inner, [
      ["default", numberField(progress.default)],
      ["min", numberField(progress.min)],
      ["max", numberField(progress.max)],
      ["format", progress.format !== undefined ? luaString(progress.format) : undefined],
      ["variant", progress.variant && progress.variant !== "default" ? luaString(progress.variant) : undefined],
    ]);
  } else if (item.type === "radio") {
    const radio = item as RadioItem;
    lines.push(`${inner}options = ${emitOptions(radio.options, level + 1)},`);
    emitFieldLines(lines, inner, [
      ["default", radio.default !== undefined && radio.default !== null ? luaString(String(radio.default)) : undefined],
      ["inline", radio.inline === true ? "true" : undefined],
    ]);
    for (const stub of stubOnChange(sectionId, radio.id, "value")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "multiselect") {
    const multi = item as MultiselectItem;
    lines.push(`${inner}options = ${emitOptions(multi.options, level + 1)},`);
    emitFieldLines(lines, inner, [
      ["default", multi.default !== undefined ? luaStringArray(multi.default) : undefined],
      ["columns", numberField(multi.columns)],
    ]);
    for (const stub of stubOnChange(sectionId, multi.id, "values")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "colorpicker") {
    // Alpha is on in the library unless it is false, so only false is written, as showValue is for a slider.
    const picker = item as ColorpickerItem;
    // The default is written only when all four channels are numbers, as numberField writes a number.
    const channels = picker.default !== undefined ? COLOR_CHANNELS.map((key) => numberField(picker.default?.[key])) : [];
    const color = channels.length === 4 && channels.every((value) => value !== undefined) ? channels : undefined;
    emitFieldLines(lines, inner, [
      ["default", color !== undefined ? `{ R = ${color[0]}, G = ${color[1]}, B = ${color[2]}, A = ${color[3]} }` : undefined],
      ["alpha", picker.alpha === false ? "false" : undefined],
    ]);
    for (const stub of stubOnChange(sectionId, picker.id, "color")) {
      lines.push(`${inner}${stub}`);
    }
  } else if (item.type === "keybind") {
    // No onConflict stub is written, because without one the widget refuses a binding another item holds.
    const bind = item as KeybindItem;
    emitFieldLines(lines, inner, [
      ["default", bind.default !== undefined ? luaString(bind.default) : undefined],
      ["allowModifiers", bind.allowModifiers === true ? "true" : undefined],
    ]);
    for (const stub of stubOnChange(sectionId, bind.id, "binding")) {
      lines.push(`${inner}${stub}`);
    }
  }

  // The look comes last, so an item without one exports the same text as before.
  emitFieldLines(lines, inner, [["look", lookField(item)]]);
  lines.push(`${pad}},`);
  return lines.join("\n");
}

function emitSection(section: Section): string {
  const items = section.items.map((item) => emitItem(item, section.id, 2)).join("\n");
  const lines = [
    `ModMenu.Register({`,
    `    id = ${luaString(section.id)},`,
  ];
  if (section.title !== undefined) {
    lines.push(`    title = ${luaString(section.title)},`);
  }
  if (section.tab) {
    lines.push(`    tab = ${luaString(section.tab)},`);
  }
  if (section.collapsible === true) {
    lines.push(`    collapsible = true,`);
  }
  if (section.collapsed === true) {
    lines.push(`    collapsed = true,`);
  }
  if (section.description) {
    lines.push(`    description = ${luaString(section.description)},`);
  }
  if (section.prefix) {
    lines.push(`    prefix = ${luaString(section.prefix)},`);
  }
  lines.push(`    items = {`, items, `    },`, `})`, ``);
  return lines.join("\n");
}

export function hostFolderName(doc: MenuDocument): string {
  const raw = doc.init.instanceId || doc.init.title || "MyMod";
  const cleaned = raw.replace(/[^A-Za-z0-9_-]+/g, "");
  return cleaned || "MyMod";
}

function bannerRow(text: string, width: number): string {
  const inner = width - 4;
  const clipped = text.length > inner ? text.slice(0, inner) : text;
  return `|  ${clipped.padEnd(inner)}|`;
}

function emitLoadBanner(doc: MenuDocument): string[] {
  const init = doc.init;
  const rows = [`${init.title} Loaded`, `${init.keyHint} = toggle menu`];
  if (init.tabs && init.tabs.length > 0) {
    rows.push(`Tabs: ${init.tabs.join(" / ")}`);
  }
  rows.push(`Dock: ${init.dock}`);
  const width = Math.max(32, ...rows.map((row) => row.length + 4));
  const rule = "-".repeat(width);
  return [rule, ...rows.map((row) => bannerRow(row, width)), rule].map((line) => `print(${luaString(line)})`);
}

export function printLua(document: MenuDocument): string {
  const doc = ensureIds(document);
  const init = doc.init;
  const key = keyExpr(init.keyHint);
  const lines = [
    `--[[`,
    `  Generated by ModMenu Builder.`,
    ``,
    `  Extract the zip into ue4ss/Mods/.`,
    `  Creates ${hostFolderName(doc)}/ (this menu) and shared/ModMenu/ (runtime).`,
    `  Extracting again overwrites shared/ModMenu with the runtime this builder shipped.`,
    ``,
    `  Replace TODO stubs with your game calls.`,
    `  Live lists / chrome: README Dynamic UI (SetOptions, OnOpen, SetButton*).`,
    `]]`,
    ``,
    `local ModMenu = require("ModMenu.ModMenu")`,
    ``,
    `ModMenu.Init({`,
    `    title = ${luaString(init.title)},`,
    `    instanceId = ${luaString(init.instanceId)},`,
  ];
  if (key) {
    lines.push(`    key = ${key},`);
  } else {
    lines.push(`    -- TODO: set key / keyName by hand (keyHint is not a plain Key name)`);
  }
  lines.push(`    keyHint = ${luaString(init.keyHint)},`);
  lines.push(`    dock = ${luaString(init.dock)},`);
  lines.push(`    theme = ${luaString(init.theme)},`);
  if (init.tabs && init.tabs.length > 0) {
    const tabs = init.tabs.map((name) => luaString(name)).join(", ");
    lines.push(`    tabs = { ${tabs} },`);
  }
  const tooltipDelayMs = numberField(init.tooltipDelayMs);
  if (tooltipDelayMs !== undefined) {
    lines.push(`    tooltipDelayMs = ${tooltipDelayMs},`);
  }
  if (init.showClose === false) {
    lines.push(`    showClose = false,`);
  }
  const cursorScale = numberField(init.cursorScale);
  if (cursorScale !== undefined) {
    lines.push(`    cursorScale = ${cursorScale},`);
  }
  if (init.spacing !== undefined) {
    const spacing = init.spacing;
    const tokens = SPACING_KEYS.flatMap((key) => {
      const value = numberField(spacing[key]);
      return value !== undefined ? [[key, value] as const] : [];
    });
    if (tokens.length > 0) {
      lines.push(`    spacing = {`);
      for (const [key, value] of tokens) {
        lines.push(`        ${key} = ${value},`);
      }
      lines.push(`    },`);
    }
  }
  // Each object type on its own line, sorted, so a document without style exports the same text as before.
  if (isPlainObject(init.style)) {
    const types = luaFields(init.style);
    if (types.length > 0) {
      lines.push(`    style = {`);
      for (const line of types) {
        lines.push(`        ${line},`);
      }
      lines.push(`    },`);
    }
  }
  lines.push(`})`, ``, ...emitLoadBanner(doc), ``);
  for (const section of doc.sections) {
    lines.push(emitSection(section));
  }
  return lines.join("\n").replace(/\n+$/, "\n");
}
