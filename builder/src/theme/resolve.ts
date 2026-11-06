// Theme resolution for the builder, ported from core/style.lua so the preview and the library agree.
//
// A theme is a preset id or a definition. resolve() applies, in this order: the preset or definition,
// its base and parts borrowing, style.palette, the palette defaults and derived fields, each
// style.<type> override, and last the legacy colors table. Every colour in the result is a linear
// { R, G, B, A } object. The shared fixtures in tooling/lua/fixtures/style/ hold both resolvers equal,
// so a rule changed here must change in core/style.lua too.
import type { StyleColor, StyleOverrides } from "../schema/types";
import { FIELDS } from "./fields.generated";
import { PRESETS, PRESET_ORDER } from "./presets.generated";
import { LIGHT, type Color } from "./tokens";

// The resolved style is a dynamic table read by field name, as the Lua widgets read it.
// oxlint-disable-next-line typescript/no-explicit-any
type Field = any;

/** One object type's resolved fields, every colour linear. */
export type ResolvedEntry = Record<string, Field>;

/** Object types in resolution order: choice reads button, tabs reads choice, and field, list, stepper and tooltip read button or field. */
export const OBJECT_TYPES = [
  "panel",
  "header",
  "title",
  "body",
  "hint",
  "data",
  "section",
  "button",
  "toggle",
  "slider",
  "progress",
  "choice",
  "tabs",
  "field",
  "list",
  "stepper",
  "tooltip",
  "confirm",
  "motion",
] as const;

export type ObjectType = (typeof OBJECT_TYPES)[number];

export type ResolvedStyle = {
  id: string;
  name?: string;
  subtitle?: string;
  footer?: string;
  palette: Record<string, Color>;
} & Record<ObjectType, ResolvedEntry>;

/** A theme definition in the shape of a preset file: palette, object types, and optional base and parts borrowing. */
export type ThemeDefinition = {
  name?: string;
  subtitle?: string;
  footer?: string;
  palette?: Record<string, StyleColor>;
  base?: string;
  parts?: Record<string, string>;
  [key: string]: unknown;
};

/** A problem in a style table, theme definition or item look: where it is and what is wrong. */
export type StyleIssue = { path: string; message: string };

type Dict = Record<string, Field>;

const TYPES = FIELDS.types;
const PALETTE = FIELDS.palette;
const TEXT_KINDS = TYPES.title;
const ROLE_NAMES = ["default", "primary", "secondary", "success", "danger", "warning", "info", "active", "disabled"];
const ROLE_KINDS: Record<string, string> = {
  fill: "color",
  text: "color",
  hover: "color",
  pressed: "color",
  edge: "color",
  variant: TYPES.button.variant,
};
const SHADOW_KINDS: Record<string, string> = { x: "number", y: "number", color: "color" };

// A definition may carry these keys beside its object types.
const DEFINITION_KEYS = new Set(["id", "stage", "name", "subtitle", "footer", "icon", "palette", "base", "parts"]);

function isDict(v: unknown): v is Dict {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

// A Lua table is an object or an array.
function isTable(v: unknown): v is Dict {
  return typeof v === "object" && v !== null;
}

// Lua has no undefined or null field, so both count as absent.
function present(v: unknown): boolean {
  return v !== undefined && v !== null;
}

// A lookup by own key only, so a name such as "constructor" is never found on Object.prototype.
function own<T>(t: Readonly<Record<string, T>>, key: unknown): T | undefined {
  return typeof key === "string" && Object.hasOwn(t, key) ? t[key] : undefined;
}

function isType(name: unknown): boolean {
  return own(TYPES, name) !== undefined;
}

function isPreset(id: unknown): boolean {
  return own(PRESETS, id) !== undefined;
}

function entries(t: unknown): [string, Field][] {
  if (!isTable(t)) {
    return [];
  }
  return Object.entries(t).filter(([, v]) => present(v));
}

// ---------------------------------------------------------------------------------------------
// Colours
// ---------------------------------------------------------------------------------------------

const WHITE: Color = { R: 1, G: 1, B: 1, A: 1 };
const BLACK: Color = { R: 0, G: 0, B: 0, A: 1 };

// The same sRGB to linear curve as StyleLab and core/style.lua, so a ported preset keeps its colours.
function linear(byte: number): number {
  const c = byte / 255;
  if (c <= 0.04045) {
    return c / 12.92;
  }
  return Math.pow((c + 0.055) / 1.055, 2.4);
}

function parseHex(s: unknown): Color | null {
  if (typeof s !== "string") {
    return null;
  }
  const match = /^#([0-9a-fA-F]+)$/.exec(s);
  if (match === null || (match[1].length !== 6 && match[1].length !== 8)) {
    return null;
  }
  const digits = match[1];
  const byte = (i: number) => parseInt(digits.slice(i, i + 2), 16);
  const alpha = digits.length === 8 ? byte(6) / 255 : 1;
  return { R: linear(byte(0)), G: linear(byte(2)), B: linear(byte(4)), A: alpha };
}

/** Convert an sRGB hex string, "#RRGGBB" or "#RRGGBBAA", to a linear colour. */
export function hex(s: string): Color {
  const c = parseHex(s);
  if (c === null) {
    throw new Error(`ModMenu style: malformed colour "${String(s)}"; write "#RRGGBB" or "#RRGGBBAA"`);
  }
  return c;
}

// Lua's tonumber: a number, or a numeric string, else the fallback.
function toNumber(v: unknown, fallback: number): number {
  if (typeof v === "number") {
    return v;
  }
  // Decimal only, so "Infinity" and "0b11", which Number() accepts and tonumber rejects, fall back.
  if (typeof v === "string" && /^\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\s*$/.test(v)) {
    return Number(v);
  }
  return fallback;
}

/** A new linear colour from a hex string or an { R, G, B, A } object; a missing alpha is 1. */
export function color(v: unknown): Color {
  if (typeof v === "string") {
    return hex(v);
  }
  if (!isTable(v)) {
    throw new Error(`ModMenu style: a colour must be a hex string or an { R, G, B, A } table, got ${typeof v}`);
  }
  return { R: toNumber(v.R, 0), G: toNumber(v.G, 0), B: toNumber(v.B, 0), A: toNumber(v.A, 1) };
}

function alpha(c: Color, a: number): Color {
  return { R: c.R, G: c.G, B: c.B, A: a };
}

function mix(a: Color, b: Color, t: number): Color {
  return {
    R: a.R + (b.R - a.R) * t,
    G: a.G + (b.G - a.G) * t,
    B: a.B + (b.B - a.B) * t,
    A: a.A + (b.A - a.A) * t,
  };
}

function isColorValue(v: unknown): boolean {
  if (typeof v === "string") {
    return parseHex(v) !== null;
  }
  return (
    isTable(v) &&
    typeof v.R === "number" &&
    typeof v.G === "number" &&
    typeof v.B === "number" &&
    (!present(v.A) || typeof v.A === "number")
  );
}

// ---------------------------------------------------------------------------------------------
// Copying by kind
// ---------------------------------------------------------------------------------------------

// An own key even for "__proto__", which plain assignment would turn into the copy's prototype.
function setOwn(out: Dict, key: string, value: Field) {
  Object.defineProperty(out, key, { value, enumerable: true, writable: true, configurable: true });
}

function deepCopy(v: Field): Field {
  if (Array.isArray(v)) {
    return v.map(deepCopy);
  }
  if (!isTable(v)) {
    return v;
  }
  const out: Dict = {};
  for (const [k, inner] of entries(v)) {
    setOwn(out, k, deepCopy(inner));
  }
  return out;
}

// Free-form tables, such as a progress ramp, hold colours that both resolvers convert.
function convertDeep(v: Field): Field {
  if (typeof v === "string" && parseHex(v) !== null) {
    return parseHex(v);
  }
  if (!isTable(v)) {
    return v;
  }
  if (typeof v.R === "number") {
    return color(v);
  }
  if (Array.isArray(v)) {
    return v.map(convertDeep);
  }
  const out: Dict = {};
  for (const [k, inner] of entries(v)) {
    setOwn(out, k, convertDeep(inner));
  }
  return out;
}

function copyTable(kinds: Record<string, string>, t: Dict): Dict {
  const out: Dict = {};
  for (const [k, v] of entries(t)) {
    out[k] = copyByKind(own(kinds, k), v);
  }
  return out;
}

// A new value of the given kind with every colour linear. An unknown kind is copied as is.
function copyByKind(kind: string | undefined, v: Field): Field {
  if (!present(v)) {
    return undefined;
  }
  if (kind === "color") {
    return color(v);
  }
  if (kind === "text" && isTable(v)) {
    return copyTable(TEXT_KINDS, v);
  }
  if (kind === "shadow" && isTable(v)) {
    return copyTable(SHADOW_KINDS, v);
  }
  if (kind === "roles" && isTable(v)) {
    const out: Dict = {};
    for (const [role, entry] of entries(v)) {
      out[role] = isTable(entry) ? copyTable(ROLE_KINDS, entry) : entry;
    }
    return out;
  }
  if (kind === "table") {
    return convertDeep(v);
  }
  return deepCopy(v);
}

function normalize(typeName: string, entry: unknown): Dict {
  const kinds = own(TYPES, typeName) ?? {};
  const out: Dict = {};
  for (const [f, v] of entries(entry)) {
    out[f] = copyByKind(own(kinds, f), v);
  }
  return out;
}

function shallow(t: unknown): Dict {
  const out: Dict = {};
  for (const [k, v] of entries(t)) {
    out[k] = v;
  }
  return out;
}

// Merge two entries of one type. Roles merge per role and per colour, and text tables per key,
// because an override names only the parts it changes.
function mergeType(typeName: string, base: unknown, over: unknown): Dict {
  const kinds = own(TYPES, typeName) ?? {};
  const out = shallow(base);
  for (const [f, v] of entries(over)) {
    const kind = own(kinds, f);
    if (kind === "roles" && isTable(v) && isTable(out[f])) {
      const roles = shallow(out[f]);
      for (const [role, entry] of entries(v)) {
        roles[role] = isTable(entry) && isTable(roles[role]) ? { ...shallow(roles[role]), ...shallow(entry) } : entry;
      }
      out[f] = roles;
    } else if (kind === "text" && isTable(v) && isTable(out[f])) {
      out[f] = { ...shallow(out[f]), ...shallow(v) };
    } else {
      out[f] = v;
    }
  }
  return out;
}

function withoutColors(t: Dict, kinds: Record<string, string>): Dict {
  const out: Dict = {};
  for (const [k, v] of entries(t)) {
    if (own(kinds, k) !== "color") {
      out[k] = v;
    }
  }
  return out;
}

// An entry without its colours, so a borrowed type takes its shape from one preset and its colours
// from the current palette. Free-form lists such as a ramp or shadow layers are kept.
function stripColors(typeName: string, entry: unknown): Dict {
  const kinds = own(TYPES, typeName) ?? {};
  const out: Dict = {};
  for (const [f, v] of entries(entry)) {
    const kind = own(kinds, f);
    if (kind === "color") {
      continue;
    }
    if (kind === "roles" && isTable(v)) {
      const roles: Dict = {};
      for (const [role, roleEntry] of entries(v)) {
        if (isTable(roleEntry)) {
          roles[role] = withoutColors(roleEntry, ROLE_KINDS);
        }
      }
      out[f] = roles;
    } else if (kind === "text" && isTable(v)) {
      out[f] = withoutColors(v, TEXT_KINDS);
      if (isTable(v.shadow)) {
        out[f].shadow = withoutColors(v.shadow, SHADOW_KINDS);
      }
    } else if (kind === "shadow" && isTable(v)) {
      out[f] = withoutColors(v, SHADOW_KINDS);
    } else {
      out[f] = v;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Validation: the rules of Style.Validate, collected as issues instead of raised one at a time
// ---------------------------------------------------------------------------------------------

function enumAllows(kind: string, v: unknown): boolean {
  return typeof v === "string" && kind.slice(5).split("|").includes(v);
}

function isRadius(v: unknown): boolean {
  return typeof v === "number" || (Array.isArray(v) && v.length === 4 && v.every((n) => typeof n === "number"));
}

function isFont(v: unknown): boolean {
  return typeof v === "string" || (Array.isArray(v) && v.length > 0 && v.every((n) => typeof n === "string"));
}

function checkTable(path: string, kinds: Record<string, string>, t: Dict, issues: StyleIssue[]) {
  for (const [k, v] of entries(t)) {
    const kind = own(kinds, k);
    if (kind === undefined) {
      issues.push({ path: `${path}.${k}`, message: "unknown field" });
    } else {
      checkValue(`${path}.${k}`, kind, v, issues);
    }
  }
}

function checkValue(path: string, kind: string, v: unknown, issues: StyleIssue[]) {
  const bad = () => issues.push({ path, message: `must be ${kind}` });
  if (kind === "color") {
    if (!isColorValue(v)) bad();
  } else if (kind === "number") {
    if (typeof v !== "number") bad();
  } else if (kind === "boolean") {
    if (typeof v !== "boolean") bad();
  } else if (kind === "string") {
    if (typeof v !== "string") bad();
  } else if (kind.startsWith("enum:")) {
    if (!enumAllows(kind, v)) bad();
  } else if (kind === "radius") {
    if (!isRadius(v)) bad();
  } else if (kind === "font") {
    if (!isFont(v)) bad();
  } else if (kind === "text") {
    if (!isTable(v)) bad();
    else checkTable(path, TEXT_KINDS, v, issues);
  } else if (kind === "shadow") {
    // False turns a text shadow off, as StyleLab's shadow = false does.
    if (v === false) return;
    if (!isTable(v)) bad();
    else checkTable(path, SHADOW_KINDS, v, issues);
  } else if (kind === "roles") {
    if (!isTable(v)) {
      bad();
      return;
    }
    for (const [role, entry] of entries(v)) {
      const rolePath = `${path}.${role}`;
      if (!ROLE_NAMES.includes(role)) {
        issues.push({ path: rolePath, message: "unknown field" });
      } else if (!isTable(entry)) {
        issues.push({ path: rolePath, message: `must be a table of ${kind}` });
      } else {
        checkTable(rolePath, ROLE_KINDS, entry, issues);
      }
    }
  } else if (kind === "table") {
    if (!isTable(v)) bad();
  }
}

function checkPresetId(path: string, id: unknown, issues: StyleIssue[]) {
  if (typeof id !== "string" || !isPreset(id)) {
    issues.push({ path, message: `unknown preset ${String(id)}` });
  }
}

function checkEntry(path: string, typeName: string, entry: Dict, allowFrom: boolean, issues: StyleIssue[]) {
  const kinds = own(TYPES, typeName) ?? {};
  for (const [f, v] of entries(entry)) {
    const kind = own(kinds, f);
    if (allowFrom && f === "from") {
      checkPresetId(`${path}.from`, v, issues);
    } else if (kind === undefined) {
      issues.push({ path: `${path}.${f}`, message: "unknown field" });
    } else {
      checkValue(`${path}.${f}`, kind, v, issues);
    }
  }
}

function checkPalette(path: string, palette: unknown, issues: StyleIssue[]) {
  if (!isTable(palette)) {
    issues.push({ path, message: "must be a table" });
    return;
  }
  for (const [k, v] of entries(palette)) {
    if (!PALETTE.includes(k)) {
      issues.push({ path: `${path}.${k}`, message: "unknown field" });
    } else {
      checkValue(`${path}.${k}`, "color", v, issues);
    }
  }
}

/**
 * Check a style override table against the field list, as Style.Validate does.
 * Each object type takes a preset id, a field table, or a field table with `from`; `palette` takes palette colours.
 * Paths start with `prefix`, such as "init.style".
 */
export function styleIssues(style: unknown, prefix: string): StyleIssue[] {
  const issues: StyleIssue[] = [];
  if (!present(style)) {
    return issues;
  }
  if (!isTable(style)) {
    return [{ path: prefix, message: "must be a table" }];
  }
  for (const [typeName, value] of entries(style)) {
    const path = `${prefix}.${typeName}`;
    if (typeName === "palette") {
      checkPalette(path, value, issues);
    } else if (!isType(typeName)) {
      issues.push({ path, message: "unknown object type" });
    } else if (typeof value === "string") {
      checkPresetId(path, value, issues);
    } else if (isTable(value)) {
      checkEntry(path, typeName, value, true, issues);
    } else {
      issues.push({ path, message: "must be a preset id or a table of fields" });
    }
  }
  return issues;
}

/**
 * Check an item's look against its object type's fields, as the registry's ValidateLook does through
 * Style.Validate({ [type] = look }). Paths start with `prefix`, such as "Register(Main) items[0].look".
 * A look cannot borrow from a preset, so `from` is an unknown field.
 */
export function lookIssues(objectType: string, look: unknown, prefix: string): StyleIssue[] {
  if (!isDict(look)) {
    return [{ path: prefix, message: `must be a table of ${objectType} fields` }];
  }
  const issues: StyleIssue[] = [];
  checkEntry(prefix, objectType, look, false, issues);
  return issues;
}

/** Check a theme definition: like a style table, except that base and parts name presets and a type cannot borrow with `from`. */
export function definitionIssues(def: unknown, prefix: string): StyleIssue[] {
  if (!isDict(def)) {
    return [{ path: prefix, message: "must be a preset id or a definition table" }];
  }
  const issues: StyleIssue[] = [];
  for (const [key, value] of entries(def)) {
    const path = `${prefix}.${key}`;
    if (key === "palette") {
      checkPalette(path, value, issues);
    } else if (key === "base") {
      checkPresetId(path, value, issues);
    } else if (key === "parts") {
      if (!isTable(value)) {
        issues.push({ path, message: "must be a table of object type to preset id" });
        continue;
      }
      for (const [typeName, id] of entries(value)) {
        if (!isType(typeName)) {
          issues.push({ path: `${path}.${typeName}`, message: "unknown object type" });
        } else {
          checkPresetId(`${path}.${typeName}`, id, issues);
        }
      }
    } else if (DEFINITION_KEYS.has(key)) {
      // Names and descriptions are free text.
    } else if (!isType(key)) {
      issues.push({ path, message: "unknown object type" });
    } else if (!isTable(value)) {
      issues.push({ path, message: "must be a table of fields" });
    } else {
      checkEntry(path, key, value, false, issues);
    }
  }
  return issues;
}

function throwFirst(issues: StyleIssue[]) {
  if (issues.length > 0) {
    throw new Error(`ModMenu style: ${issues[0].path}: ${issues[0].message}`);
  }
}

// ---------------------------------------------------------------------------------------------
// Flattening: a definition and its borrowing become one raw table
// ---------------------------------------------------------------------------------------------

function presetRaw(id: unknown, seen: Set<object>): Dict {
  if (typeof id !== "string" || !isPreset(id)) {
    throw new Error(`ModMenu style: unknown theme "${String(id)}"; choose one of: ${PRESET_ORDER.join(", ")}`);
  }
  return flatten(PRESETS[id] as Dict, seen);
}

// The base supplies the palette and every type; the definition's own entries merge over it; each part
// replaces its type with the named preset's entry stripped of colours, and the definition's own fields
// for that type still merge over the part.
function flatten(def: Dict, seen: Set<object> = new Set()): Dict {
  if (seen.has(def)) {
    throw new Error("ModMenu style: a theme borrows from itself through base or parts");
  }
  seen.add(def);
  let raw: Dict = { palette: {} };
  if (present(def.base)) {
    raw = presetRaw(def.base, seen);
  }
  for (const [k, v] of entries(def.palette)) {
    raw.palette[k] = color(v);
  }
  for (const typeName of OBJECT_TYPES) {
    if (present(def[typeName])) {
      raw[typeName] = mergeType(typeName, raw[typeName], normalize(typeName, def[typeName]));
    }
  }
  for (const [typeName, id] of entries(def.parts)) {
    const source = presetRaw(id, seen);
    raw[typeName] = mergeType(typeName, stripColors(typeName, source[typeName]), normalize(typeName, def[typeName]));
  }
  seen.delete(def);
  return raw;
}

// ---------------------------------------------------------------------------------------------
// Defaults and derived fields, per object type
// ---------------------------------------------------------------------------------------------

// The legacy light button colours, for the roles and palette entries StyleLab never defined. Read at
// call time, because tokens.ts imports this module too.
function legacyRole(role: "success" | "warning" | "info"): { fill: Color; text: Color } {
  if (role === "success") return { fill: LIGHT.buttonBgSuccess, text: LIGHT.buttonTextSuccess };
  if (role === "warning") return { fill: LIGHT.buttonBgWarning, text: LIGHT.buttonTextWarning };
  return { fill: LIGHT.buttonBgInfo, text: LIGHT.buttonTextInfo };
}

function resolvePalette(raw: Dict): Record<string, Color> {
  const p: Record<string, Color> = {};
  for (const key of PALETTE) {
    if (present(raw[key])) {
      p[key] = color(raw[key]);
    }
  }
  // A custom definition may name only some colours, so the core ones fall back to the light preset's palette.
  const light = PRESETS.light.palette as Dict;
  for (const key of ["bg", "text", "muted", "accent", "accentText", "danger", "surface", "line"]) {
    if (p[key] === undefined) {
      p[key] = color(light[key]);
    }
  }
  p.dangerText ??= color(WHITE);
  p.secondaryText ??= color(p.text);
  p.track ??= mix(p.bg, p.text, 0.15);
  p.success ??= color(legacyRole("success").fill);
  p.warning ??= color(legacyRole("warning").fill);
  p.info ??= color(legacyRole("info").fill);
  return p;
}

// Lua's Merge: the defined fields of base, then the defined fields of over.
function merge(base: unknown, over: unknown): Dict {
  return { ...shallow(base), ...shallow(over) };
}

function largestRadius(radius: unknown): number {
  if (Array.isArray(radius)) {
    return radius.reduce((largest: number, r: number) => (r > largest ? r : largest), 0);
  }
  return typeof radius === "number" ? radius : 0;
}

function resolveText(t: unknown, c: Color): Dict {
  const out = merge({ color: c }, t);
  if (isTable(out.shadow) && !present(out.shadow.color)) {
    out.shadow = merge(out.shadow, { color: alpha(BLACK, 0.5) });
  }
  return out;
}

function defaultRoles(p: Record<string, Color>): Dict {
  return {
    default: { fill: p.surface, text: p.text },
    primary: { fill: p.accent, text: p.accentText },
    secondary: { fill: p.surface, text: p.secondaryText },
    success: { fill: p.success, text: legacyRole("success").text },
    danger: { fill: p.danger, text: p.dangerText },
    warning: { fill: p.warning, text: legacyRole("warning").text },
    info: { fill: p.info, text: legacyRole("info").text },
    active: { fill: p.accent, text: p.accentText },
    disabled: { fill: mix(p.bg, p.text, 0.08), text: p.muted },
  };
}

// The tab strip follows the choice variant; radio has no tab form.
const TAB_VARIANT: Record<string, string> = { stock: "stock", joined: "joined", chips: "chips", tabs: "tabs", radio: "joined" };

type Resolver = (t: Dict, p: Record<string, Color>, s: Dict) => Dict;

// Text sizes, fonts and typefaces are left absent unless a theme sets them, because absent means the
// library's own font and the config's size after font scaling.
const RESOLVERS: Record<ObjectType, Resolver> = {
  panel(t, p) {
    const s = merge(
      {
        radius: 12, width: 1, outline: p.line, fill: p.bg, pad: 18, blur: 0, shadowColor: BLACK, hardShadow: 0,
        hardShadowColor: BLACK, rim: false, rimLight: alpha(WHITE, 0.7), rimDark: alpha(BLACK, 0.25), corners: false,
      },
      t,
    );
    // The blur sits at half the panel's radius (field note 32), so it follows a changed radius.
    s.blurRadius ??= largestRadius(s.radius) * 0.5;
    s.blurInset ??= 2;
    return s;
  },
  header(t, p) {
    return merge(
      { variant: "badge", fill: alpha(p.bg, 0), text: p.text, line: p.line, badgeFill: mix(p.bg, p.accent, 0.16), controlGlyph: p.text },
      t,
    );
  },
  title(t, p) {
    return resolveText(t, p.text);
  },
  body(t, p) {
    return resolveText(t, p.text);
  },
  hint(t, p) {
    return resolveText(t, p.muted);
  },
  data(t, p) {
    const s = resolveText(t, p.accent);
    s.statusColor ??= p.warning;
    return s;
  },
  section(t, p) {
    const s = merge({ variant: "label", color: p.muted, fill: mix(p.bg, p.text, 0.06), mark: p.muted, line: p.line }, t);
    s.text = resolveText(s.text, s.color);
    return s;
  },
  button(t, p) {
    const s = merge({ variant: "fill", radius: 8, width: 1, height: 36, hoverToward: WHITE, hoverAmount: 0.14 }, t);
    // Every role is filled, so a widget never meets an absent fill or text colour.
    const roles = defaultRoles(p);
    for (const [role, entry] of entries(s.roles)) {
      roles[role] = merge(roles[role], entry);
    }
    s.roles = roles;
    return s;
  },
  toggle(t, p) {
    const s = merge(
      {
        variant: "switch", trackOn: p.accent, trackOff: mix(p.bg, p.text, 0.22), knobOn: WHITE, knobOff: WHITE, w: 36, h: 20,
        checkOff: alpha(p.text, 0), checkOn: p.accent, checkEdge: p.text, checkEdgeOn: p.accent, checkMark: p.accentText,
        checkEdgeWidth: 1,
      },
      t,
    );
    s.radius ??= s.h / 2;
    return s;
  },
  slider(t, p) {
    return merge(
      { variant: "round", thickness: 4, size: 16, track: p.track, thumbFill: WHITE, thumbEdge: p.accent, thumbHover: p.accent },
      t,
    );
  },
  progress(t, p) {
    return merge({ variant: "bar", height: 8, radius: 4, segments: 12, gap: 3, track: p.track, fill: p.accent }, t);
  },
  choice(t, p, s) {
    return merge(
      {
        variant: "joined", radius: s.button.radius, pill: s.button.pill, markFill: p.accent, markText: p.accentText,
        radioEdge: p.text, radioFill: p.accent,
      },
      t,
    );
  },
  tabs(t, _p, s) {
    const c = s.choice;
    return merge(
      {
        variant: own(TAB_VARIANT, c.variant), radius: c.radius, pill: c.pill, markFill: c.markFill, markText: c.markText,
        markEdge: c.markEdge, trackFill: c.trackFill, edge: c.edge, tabText: c.tabText,
      },
      t,
    );
  },
  field(t, p, s) {
    const f = merge(
      {
        variant: "frame", fill: mix(p.bg, p.text, 0.07), outline: p.line, width: 1, radius: s.button.radius, pill: s.button.pill,
        text: p.text, hint: p.muted,
      },
      t,
    );
    f.headerFill ??= mix(p.bg, p.text, 0.12);
    f.headerText ??= f.text;
    return f;
  },
  list(t, p, s) {
    const f = s.field;
    return merge({ fill: f.fill, text: f.text, hover: mix(f.fill, p.accent, 0.2), more: p.muted, radius: f.radius }, t);
  },
  stepper(t, _p, s) {
    return merge({ role: "default", height: s.button.height, radius: s.button.radius, pill: s.button.pill }, t);
  },
  tooltip(t, p, s) {
    return merge({ fill: p.surface, text: p.text, radius: s.button.radius, outline: p.line, width: s.button.width }, t);
  },
  confirm(t, p, s) {
    return merge({ fill: p.surface, dim: alpha(BLACK, 0.6), divider: p.line, radius: s.panel.radius }, t);
  },
  motion(t) {
    return merge({ pulse: false, cursor: false, glitch: false, sparkle: false }, t);
  },
};

// Resolve one type from its raw entry. The result is normalized, so it shares no object with the
// palette, another type or a preset.
function resolveType(typeName: ObjectType, raw: unknown, p: Record<string, Color>, s: Dict): Dict {
  return normalize(typeName, RESOLVERS[typeName](isTable(raw) ? raw : {}, p, s));
}

// ---------------------------------------------------------------------------------------------
// Legacy colour tokens
// ---------------------------------------------------------------------------------------------

// Each legacy token and the resolved paths it maps to, from the spec's mapping table, in core/style.lua's order.
const LEGACY: [string, ...string[][]][] = [
  ["panelBg", ["panel", "fill"]],
  ["panelBorder", ["panel", "outline"]],
  ["textPrimary", ["body", "color"], ["title", "color"]],
  ["textMuted", ["palette", "muted"]],
  ["textAccent", ["palette", "accent"]],
  ["textStatus", ["data", "statusColor"]],
  ["sectionHeaderBg", ["section", "fill"]],
  ["sectionMark", ["section", "mark"]],
  ["fieldBg", ["field", "fill"]],
  ["fieldText", ["field", "text"]],
  ["fieldHint", ["field", "hint"]],
  ["dropdownHeaderBg", ["field", "headerFill"]],
  ["dropdownHeaderText", ["field", "headerText"]],
  ["dropdownOptionBg", ["list", "fill"]],
  ["dropdownOptionText", ["list", "text"]],
  ["dropdownMore", ["list", "more"]],
  ["overlayDim", ["confirm", "dim"]],
  ["confirmCardBg", ["confirm", "fill"]],
  ["confirmDivider", ["confirm", "divider"]],
  ["tooltipBg", ["tooltip", "fill"]],
];

// Button tokens: the role, its fill and text keys, and its hover and pressed keys when it has them.
const LEGACY_BUTTONS: string[][] = [
  ["default", "buttonBg", "buttonText", "buttonHover", "buttonPressed"],
  ["primary", "buttonBgPrimary", "buttonTextPrimary", "buttonPrimaryHover", "buttonPrimaryPressed"],
  ["secondary", "buttonBgSecondary", "buttonTextSecondary", "buttonSecondaryHover", "buttonSecondaryPressed"],
  ["success", "buttonBgSuccess", "buttonTextSuccess", "buttonSuccessHover", "buttonSuccessPressed"],
  ["danger", "buttonBgDanger", "buttonTextDanger", "buttonDangerHover", "buttonDangerPressed"],
  ["warning", "buttonBgWarning", "buttonTextWarning", "buttonWarningHover", "buttonWarningPressed"],
  ["info", "buttonBgInfo", "buttonTextInfo", "buttonInfoHover", "buttonInfoPressed"],
  ["active", "buttonBgActive", "buttonTextActive"],
  ["disabled", "buttonBgDisabled", "buttonTextDisabled"],
];

for (const [role, fill, text, hover, pressed] of LEGACY_BUTTONS) {
  LEGACY.push([fill, ["button", "roles", role, "fill"]]);
  LEGACY.push([text, ["button", "roles", role, "text"]]);
  if (hover !== undefined) {
    LEGACY.push([hover, ["button", "roles", role, "hover"]]);
    LEGACY.push([pressed, ["button", "roles", role, "pressed"]]);
  }
}

function setPath(t: Dict, path: string[], value: Color) {
  let node = t;
  for (let i = 0; i < path.length - 1; i += 1) {
    node = node[path[i]];
  }
  node[path[path.length - 1]] = value;
}

function getPath(t: unknown, path: string[]): Field {
  let node: Field = t;
  for (const segment of path) {
    if (!isTable(node)) {
      return undefined;
    }
    node = node[segment];
  }
  return node;
}

function applyLegacy(resolved: Dict, colors: Dict) {
  for (const [key, ...paths] of LEGACY) {
    const value = colors[key];
    // Theme.Merge skipped any value that was not a table, so a string that is not valid hex is skipped too.
    if (isTable(value) || parseHex(value) !== null) {
      for (const path of paths) {
        setPath(resolved, path, color(value));
      }
    }
  }
}

/**
 * Read the legacy colour tokens back out of a resolved style, as Style.LegacyColors does.
 * A token whose field is absent, such as an underived hover colour, is left out.
 */
export function legacyColors(resolved: ResolvedStyle): Record<string, Color> {
  const out: Record<string, Color> = {};
  for (const [key, path] of LEGACY) {
    const value = getPath(resolved, path);
    if (present(value)) {
      out[key] = color(value);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------
// Public functions
// ---------------------------------------------------------------------------------------------

function borrowed(typeName: string, id: string): Dict {
  return stripColors(typeName, presetRaw(id, new Set())[typeName]);
}

/**
 * Resolve a theme, a style override table and legacy colours into one complete style, as Style.Resolve does.
 * Throws an Error naming the problem for an unknown preset, an unknown type or field, or a value of the wrong kind.
 */
export function resolve(
  themeOrNull?: string | ThemeDefinition | null,
  style?: StyleOverrides | null,
  colors?: Partial<Record<string, Color | string>> | null,
): ResolvedStyle {
  const theme = themeOrNull ?? "light";
  if (typeof theme !== "string" && !isDict(theme)) {
    throw new Error("ModMenu style: theme must be a preset id or a definition table");
  }
  if (typeof theme !== "string") {
    throwFirst(definitionIssues(theme, "theme"));
  }
  const id = typeof theme === "string" ? theme : "custom";
  const raw = typeof theme === "string" ? presetRaw(theme, new Set()) : flatten(theme as Dict);
  throwFirst(styleIssues(style, "style"));
  const overrides: Dict = isDict(style) ? style : {};

  for (const [k, v] of entries(overrides.palette)) {
    raw.palette[k] = color(v);
  }
  const p = resolvePalette(raw.palette);
  const definition = (typeof theme === "string" ? PRESETS[theme] : theme) as Dict;
  const resolved: Dict = { id, palette: p };
  for (const key of ["name", "subtitle", "footer"]) {
    if (present(definition[key])) {
      resolved[key] = definition[key];
    }
  }
  for (const typeName of OBJECT_TYPES) {
    resolved[typeName] = resolveType(typeName, raw[typeName], p, resolved);
  }

  // A type override runs after every default, so it changes only its own type; derived fields inside
  // that type, such as the panel's blur radius, are derived again from the override.
  for (const typeName of OBJECT_TYPES) {
    const value = overrides[typeName];
    let entry: Dict | undefined;
    if (typeof value === "string") {
      entry = borrowed(typeName, value);
    } else if (isTable(value)) {
      const fields: Dict = {};
      for (const [f, v] of entries(value)) {
        if (f !== "from") {
          fields[f] = v;
        }
      }
      const start = present(value.from) ? borrowed(typeName, value.from) : raw[typeName];
      entry = mergeType(typeName, start, normalize(typeName, fields));
    }
    if (entry !== undefined) {
      resolved[typeName] = resolveType(typeName, entry, p, resolved);
    }
  }

  if (isDict(colors)) {
    applyLegacy(resolved, colors);
  }
  return resolved as ResolvedStyle;
}

/** An object type's resolved fields with an item's look merged over them, as Style.ForItem does. A new object; `resolved` is not changed. */
export function forItem(resolved: ResolvedStyle, objectType: string, look?: Record<string, unknown> | null): ResolvedEntry {
  if (!isType(objectType)) {
    throw new Error(`ModMenu style: unknown object type ${String(objectType)}`);
  }
  const base = normalize(objectType, (resolved as Dict)[objectType]);
  if (!present(look)) {
    return base;
  }
  return mergeType(objectType, base, normalize(objectType, look));
}
