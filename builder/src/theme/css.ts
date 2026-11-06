import type { ThemeName } from "../schema";
import { legacyColors, type ResolvedEntry, type ResolvedStyle } from "./resolve";
import {
  BUTTON_STATE_VARIANTS,
  PANEL_PAD,
  PREVIEW_FONTS,
  THEME_KEYS,
  buttonStates,
  preset,
  type Color,
  type PanelPad,
  type ThemeColors,
} from "./tokens";

export function colorCss(c: Color): string {
  const r = Math.round(c.R * 255);
  const g = Math.round(c.G * 255);
  const b = Math.round(c.B * 255);
  if (c.A >= 1) {
    return `rgb(${r}, ${g}, ${b})`;
  }
  return `rgba(${r}, ${g}, ${b}, ${c.A})`;
}

/** One linear channel, 0 to 1, as the sRGB value CSS expects; the inverse of the hex to linear curve in resolve.ts. */
export function linearToSrgb(v: number): number {
  const c = Math.min(1, Math.max(0, v));
  if (c <= 0.0031308) {
    return c * 12.92;
  }
  return 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}

/** A linear colour as an sRGB colour; alpha is not a light value, so it passes through. */
export function srgbColor(c: Color): Color {
  return { R: linearToSrgb(c.R), G: linearToSrgb(c.G), B: linearToSrgb(c.B), A: c.A };
}

/** True for the two presets whose colours are the library's old 0-1 values, not converted hex colours. */
export function isLegacyTheme(resolved: Pick<ResolvedStyle, "id">): boolean {
  return resolved.id === "light" || resolved.id === "dark";
}

/**
 * The CSS colour function for a resolved style. Resolved colours are linear, so they are converted
 * to sRGB for CSS. The one exception is light and dark: the old preview painted their 0-1 values
 * directly, and the preview of those two themes must not change, so they keep colorCss as it was.
 * A hex colour put over light or dark through style.palette is therefore shown unconverted, darker
 * than in game; the preview accepts that so the two shipped themes stay exactly as before.
 */
export function cssColorFor(resolved: Pick<ResolvedStyle, "id">): (c: Color) => string {
  if (isLegacyTheme(resolved)) {
    return colorCss;
  }
  return (c) => colorCss(srgbColor(c));
}

export type Bevel = { light?: Color; dark?: Color; innerLight?: Color; innerDark?: Color; width?: number };

/**
 * Stops as a CSS gradient, top to bottom or left to right. Stops are linear colours, so they are
 * converted to sRGB unless the caller passes the colour function of a legacy theme. The library draws
 * evenly spaced strips, which is what a gradient with no stop positions gives.
 */
export function stopsToCss(stops: Color[], horizontal: boolean, css: (c: Color) => string = (c) => colorCss(srgbColor(c))): string {
  return `linear-gradient(${horizontal ? "90deg" : "180deg"}, ${stops.map((c) => css(c)).join(", ")})`;
}

/**
 * A bevel as an inset box-shadow, as Paint.BevelPlan draws it: light along the top and left, dark along
 * the bottom and right, swapped when sunken, then a second ring one width further in when the bevel has
 * both inner colours. The first shadow paints on top, so the outer ring comes first. A bevel without
 * light or dark draws nothing.
 */
export function bevelToCss(
  bevel: Bevel | undefined,
  sunken: boolean,
  css: (c: Color) => string = (c) => colorCss(srgbColor(c)),
): string {
  if (!bevel || !bevel.light || !bevel.dark) {
    return "none";
  }
  const w = typeof bevel.width === "number" && Number.isFinite(bevel.width) ? bevel.width : 1;
  const ring = (light: Color, dark: Color, depth: number): string[] => {
    const [a, b] = sunken ? [dark, light] : [light, dark];
    return [`inset ${depth}px ${depth}px 0 0 ${css(a)}`, `inset ${-depth}px ${-depth}px 0 0 ${css(b)}`];
  };
  const shadows = ring(bevel.light, bevel.dark, w);
  if (bevel.innerLight && bevel.innerDark) {
    shadows.push(...ring(bevel.innerLight, bevel.innerDark, w * 2));
  }
  return shadows.join(", ");
}

function kebab(key: string): string {
  return key.replace(/[A-Z]/g, (ch) => `-${ch.toLowerCase()}`);
}

function fontVars(): Record<string, string> {
  return {
    "--mm-font-title": `${PREVIEW_FONTS.title}px`,
    "--mm-font-hint": `${PREVIEW_FONTS.hint}px`,
    "--mm-font-item": `${PREVIEW_FONTS.item}px`,
    "--mm-font-section": `${PREVIEW_FONTS.section}px`,
    "--mm-font-dropdown": `${PREVIEW_FONTS.dropdown}px`,
  };
}

function padVars(pad: PanelPad): Record<string, string> {
  return {
    "--mm-pad-left": `${pad.left}px`,
    "--mm-pad-top": `${pad.top}px`,
    "--mm-pad-right": `${pad.right}px`,
    "--mm-pad-bottom": `${pad.bottom}px`,
  };
}

// The legacy token variables, such as --mm-button-bg-primary, and the derived hover and pressed colours.
function tokenVars(colors: ThemeColors, css: (c: Color) => string): Record<string, string> {
  const vars: Record<string, string> = {};
  for (const key of THEME_KEYS) {
    vars[`--mm-${kebab(key)}`] = css(colors[key]);
  }
  // The derived state colours get the same names as the Lua state keys, such as --mm-button-primary-hover.
  for (const variant of BUTTON_STATE_VARIANTS) {
    const states = buttonStates(colors, variant);
    const prefix = variant === "default" ? "button" : `button-${variant}`;
    vars[`--mm-${prefix}-hover`] = css(states.hover);
    vars[`--mm-${prefix}-pressed`] = css(states.pressed);
  }
  return vars;
}

export function themeVars(name: ThemeName): Record<string, string> {
  return { ...padVars(PANEL_PAD[name]), ...fontVars(), ...tokenVars(preset(name), colorCss) };
}

// ---------------------------------------------------------------------------------------------
// Resolved style to CSS
// ---------------------------------------------------------------------------------------------

// The config's default sizes, which a theme's text size is written over in game. The preview draws
// smaller than the game (PREVIEW_FONTS), so a theme size is scaled by the same ratio as the default.
const CONFIG_FONTS = { title: 22, hint: 14, item: 16, section: 18, dropdown: 15 } as const;

type FontKey = keyof typeof CONFIG_FONTS;

function previewSize(size: unknown, key: FontKey): string | undefined {
  if (typeof size !== "number" || size <= 0) {
    return undefined;
  }
  return `${Math.max(1, Math.round((size * PREVIEW_FONTS[key]) / CONFIG_FONTS[key]))}px`;
}

function isColor(v: unknown): v is Color {
  return typeof v === "object" && v !== null && typeof (v as Color).R === "number";
}

function num(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) ? v : fallback;
}

/** The largest corner of a radius: one number, or 4 numbers. */
export function largestRadius(radius: unknown): number {
  if (Array.isArray(radius)) {
    return radius.reduce((largest: number, r: unknown) => Math.max(largest, num(r, 0)), 0);
  }
  return num(radius, 0);
}

/**
 * A radius as a CSS border-radius. A pill is fully round. Four numbers are top-left, top-right,
 * bottom-right and bottom-left, the order of the brush's CornerRadii and of CSS.
 */
export function radiusCss(radius: unknown, pill?: unknown): string {
  if (pill === true) {
    return "999px";
  }
  if (Array.isArray(radius)) {
    return radius.map((r) => `${num(r, 0)}px`).join(" ");
  }
  return `${num(radius, 0)}px`;
}

// Font ids as CSS family names. The builder bundles no fonts, so a family the machine lacks shows the
// fallback; the export still names the font id (spec A4). An id not listed is used as its own family name.
const FONT_FAMILIES: Record<string, string> = {
  roboto: "Roboto",
  mono: '"Droid Sans Mono"',
  kanit: "Kanit",
  vcr: '"VCR OSD Mono"',
  inconsolata: "Inconsolata",
  lekton: "Lekton",
};

const MONO_IDS = new Set(["mono", "inconsolata", "vcr", "lekton"]);

/** A font id or chain as a CSS font-family list, ending in a generic family. */
export function fontFamily(font: unknown): string | undefined {
  const chain = typeof font === "string" ? [font] : Array.isArray(font) ? font.filter((f) => typeof f === "string") : [];
  if (chain.length === 0) {
    return undefined;
  }
  const names = chain.map((id: string) => FONT_FAMILIES[id] ?? `"${id.replace(/"/g, "")}"`);
  const mono = chain.some((id: string) => MONO_IDS.has(id));
  const fallback = mono ? "ui-monospace, Consolas, monospace" : 'system-ui, "Segoe UI", sans-serif';
  return `${names.join(", ")}, ${fallback}`;
}

/** A typeface name such as "Bold Italic" or "Inconsolata SemiBold" as a CSS weight and style. */
export function typefaceCss(typeface: unknown): { weight?: string; style?: string } {
  if (typeof typeface !== "string" || typeface === "" || typeface === "Default") {
    return {};
  }
  const t = typeface.toLowerCase().replace(/[\s_-]/g, "");
  let weight = "400";
  if (t.includes("black") || t.includes("heavy")) weight = "900";
  else if (t.includes("extrabold")) weight = "800";
  else if (t.includes("semibold")) weight = "600";
  else if (t.includes("bold")) weight = "700";
  else if (t.includes("medium")) weight = "500";
  else if (t.includes("extralight")) weight = "200";
  else if (t.includes("light")) weight = "300";
  else if (t.includes("thin")) weight = "100";
  return { weight, style: t.includes("italic") ? "italic" : undefined };
}

/**
 * A text style table as CSS variables named --mm-<prefix>-*: colour, font, weight, style, size,
 * letter spacing (UMG spacing is in thousandths of an em), case, shadow, outline and skew.
 * A field the theme does not set gives no variable, so the CSS falls back to the stock look.
 */
export function textVars(
  prefix: string,
  t: ResolvedEntry | undefined,
  key: FontKey,
  css: (c: Color) => string,
): Record<string, string> {
  const vars: Record<string, string> = {};
  if (t === undefined) {
    return vars;
  }
  if (isColor(t.color)) vars[`--mm-${prefix}-color`] = css(t.color);
  const family = fontFamily(t.font);
  if (family) vars[`--mm-${prefix}-font`] = family;
  const face = typefaceCss(t.typeface);
  if (face.weight) vars[`--mm-${prefix}-weight`] = face.weight;
  if (face.style) vars[`--mm-${prefix}-style`] = face.style;
  const size = previewSize(t.size, key);
  if (size) vars[`--mm-${prefix}-size`] = size;
  if (typeof t.spacing === "number") vars[`--mm-${prefix}-spacing`] = `${t.spacing / 1000}em`;
  if (t.upper === true) vars[`--mm-${prefix}-transform`] = "uppercase";
  if (t.shadow === false) {
    vars[`--mm-${prefix}-shadow`] = "none";
  } else if (typeof t.shadow === "object" && t.shadow !== null && isColor(t.shadow.color)) {
    vars[`--mm-${prefix}-shadow`] = `${num(t.shadow.x, 1)}px ${num(t.shadow.y, 1)}px 0 ${css(t.shadow.color)}`;
  }
  if (typeof t.outline === "number" && t.outline > 0) {
    vars[`--mm-${prefix}-stroke`] = `${t.outline}px ${isColor(t.outlineColor) ? css(t.outlineColor) : "black"}`;
  }
  if (typeof t.skew === "number" && t.skew !== 0) {
    // The font's skew amount shears the glyphs to the right, as an italic does.
    vars[`--mm-${prefix}-skew`] = `skewX(${-Math.atan(t.skew)}rad)`;
  }
  return vars;
}

function put(vars: Record<string, string>, name: string, value: unknown, css: (c: Color) => string) {
  if (isColor(value)) {
    vars[name] = css(value);
  }
}

function alpha(c: Color, a: number): Color {
  return { R: c.R, G: c.G, B: c.B, A: a };
}

// The panel's box-shadow: a hard shadow wins, else one hard-edged offset copy per layer, each moved
// right by half its depth and down by its depth, as Paint.Shadow lays out its shade boxes.
function panelShadow(panel: ResolvedEntry, css: (c: Color) => string): string {
  // A raised bevel is drawn over the panel shape, so its inset lines come first and the outer shadow after.
  const bevel = asBevel(panel.bevel) ? bevelToCss(asBevel(panel.bevel), false, css) : "none";
  const outer = panelOuterShadow(panel, css);
  const parts = [bevel, outer].filter((s) => s !== "none");
  return parts.length > 0 ? parts.join(", ") : "none";
}

function panelOuterShadow(panel: ResolvedEntry, css: (c: Color) => string): string {
  const hard = num(panel.hardShadow, 0);
  if (hard > 0) {
    const c = isColor(panel.hardShadowColor) ? panel.hardShadowColor : { R: 0, G: 0, B: 0, A: 1 };
    return `${hard}px ${hard}px 0 0 ${css(c)}`;
  }
  const layers: unknown = panel.shadowLayers;
  if (!Array.isArray(layers)) {
    return "none";
  }
  const color = isColor(panel.shadowColor) ? panel.shadowColor : { R: 0, G: 0, B: 0, A: 1 };
  const parts: string[] = [];
  for (const layer of layers) {
    if (Array.isArray(layer)) {
      const a = num(layer[0], 0);
      const d = Math.max(0, num(layer[1], 0));
      parts.push(`${Math.floor(d * 0.5 + 0.5)}px ${d}px 0 0 ${css(alpha(color, a))}`);
    }
  }
  return parts.length > 0 ? parts.join(", ") : "none";
}

/**
 * True when the panel draws as the library's original panel: square, no outline width, no blur,
 * shadow, rim or corners, as Build.IsStockPanel decides. Such a panel keeps today's 1 px edge.
 */
export function isStockPanel(panel: ResolvedEntry | undefined, motion?: ResolvedEntry): boolean {
  if (panel === undefined) {
    return true;
  }
  // A bevel is not flat (Paint.IsFlat), a status bar and the drawn effects live in the themed panel's body.
  const flat = largestRadius(panel.radius) <= 0 && panel.pill !== true && num(panel.width, 0) <= 0 && asBevel(panel.bevel) === undefined;
  const shadow = num(panel.hardShadow, 0) > 0 || (Array.isArray(panel.shadowLayers) && panel.shadowLayers.length > 0);
  const effects = scanStrength(panel) > 0 || panel.sweep === true || motion?.sparkle === true;
  return (
    flat &&
    num(panel.blur, 0) <= 0 &&
    !shadow &&
    typeof panel.statusBar !== "object" &&
    !effects &&
    panel.rim !== true &&
    panel.corners !== true
  );
}

/** A bevel that draws something: light and dark are both present. */
export function asBevel(v: unknown): Bevel | undefined {
  if (typeof v !== "object" || v === null) {
    return undefined;
  }
  const b = v as Bevel;
  return isColor(b.light) && isColor(b.dark) ? b : undefined;
}

/** The scanline strength: true is the default 0.25, a number is itself, anything else is none (Effects.Build). */
export function scanStrength(panel: ResolvedEntry): number {
  if (panel.scanlines === true) {
    return 0.25;
  }
  return typeof panel.scanlines === "number" && panel.scanlines > 0 ? panel.scanlines : 0;
}

const HEADER_VARIANTS = new Set(["stock", "badge", "plain", "rule", "bar", "tape", "strip", "window", "mac", "xpbar", "classic"]);

/** The band headers draw in a band across the top of the panel; mac is a row in the content. */
export const BAND_HEADERS = new Set(["bar", "tape", "strip", "window", "xpbar", "classic"]);

/** The header variant the preview draws; a variant this stage does not draw falls back to badge, as in Lua. */
export function headerVariant(resolved: ResolvedStyle): string {
  const v: unknown = resolved.header?.variant;
  if (v === undefined || v === null) {
    return "stock";
  }
  return typeof v === "string" && HEADER_VARIANTS.has(v) ? v : "badge";
}

/** The bar header's text and fill: the header's own when its fill is visible, else accent text on the accent (Build.BarColors). */
export function barColors(resolved: ResolvedStyle): { text: Color; fill: Color } {
  const header = resolved.header ?? {};
  const p = resolved.palette;
  if (isColor(header.fill) && header.fill.A > 0) {
    return { text: isColor(header.text) ? header.text : p.text, fill: header.fill };
  }
  return { text: p.accentText, fill: p.accent };
}

function panelPad(pad: unknown): PanelPad {
  if (Array.isArray(pad)) {
    return { left: num(pad[0], 0), top: num(pad[1], 0), right: num(pad[2], 0), bottom: num(pad[3], 0) };
  }
  const n = num(pad, 0);
  return { left: n, top: n, right: n, bottom: n };
}

/**
 * One object type's own variables, such as --mm-toggle-w or --mm-field-radius. styleVars puts every
 * type's variables on the panel; an item with a look puts its type's variables on itself, so its look
 * wins inside that item only.
 */
export function typeVars(type: string, e: ResolvedEntry, css: (c: Color) => string): Record<string, string> {
  const v: Record<string, string> = {};
  if (type === "button") {
    v["--mm-button-radius"] = radiusCss(e.radius, e.pill);
  } else if (type === "toggle") {
    const h = num(e.h, 20);
    v["--mm-toggle-w"] = `${num(e.w, 36)}px`;
    v["--mm-toggle-h"] = `${h}px`;
    put(v, "--mm-toggle-track-on", e.trackOn, css);
    put(v, "--mm-toggle-track-off", e.trackOff, css);
    put(v, "--mm-toggle-knob-on", e.knobOn, css);
    put(v, "--mm-toggle-knob-off", e.knobOff, css);
    if (isColor(e.offEdge)) {
      // An off track with an edge is an outline only, as in Windows 11.
      v["--mm-toggle-track-off"] = "transparent";
      v["--mm-toggle-off-edge"] = `inset 0 0 0 1px ${css(e.offEdge)}`;
    }
    // A check box or text chip is square-cornered at 3 unless the theme gives its own radius;
    // the radius derived from the switch height does not count (Checkbox's BoxRadius).
    const r = e.radius;
    const derived = r === undefined || (typeof r === "number" && r === h / 2);
    v["--mm-toggle-box-radius"] = derived ? "3px" : radiusCss(r);
    put(v, "--mm-toggle-check-off", e.checkOff, css);
    put(v, "--mm-toggle-check-on", e.checkOn, css);
    put(v, "--mm-toggle-check-edge", e.checkEdge, css);
    put(v, "--mm-toggle-check-edge-on", e.checkEdgeOn, css);
    put(v, "--mm-toggle-check-mark", e.checkMark, css);
    v["--mm-toggle-check-edge-width"] = `${num(e.checkEdgeWidth, 1)}px`;
    // A sunken bevel goes over the whole check box, as Windows Classic draws it.
    const checkBevel = asBevel(e.checkBevel);
    if (checkBevel) v["--mm-toggle-check-bevel"] = bevelToCss(checkBevel, true, css);
  } else if (type === "slider") {
    v["--mm-slider-thickness"] = `${num(e.thickness, 4)}px`;
    v["--mm-slider-size"] = `${num(e.size, 16)}px`;
    v["--mm-slider-thumb-width"] = `${num(e.thumbWidth, 2)}px`;
    put(v, "--mm-slider-track", e.track, css);
    put(v, "--mm-slider-thumb-fill", e.thumbFill, css);
    put(v, "--mm-slider-thumb-edge", e.thumbEdge, css);
    put(v, "--mm-slider-thumb-hover", e.thumbHover ?? e.thumbFill, css);
  } else if (type === "progress") {
    v["--mm-progress-height"] = `${num(e.height, 8)}px`;
    v["--mm-progress-radius"] = radiusCss(e.radius);
    v["--mm-progress-gap"] = `${num(e.gap, 3)}px`;
    put(v, "--mm-progress-track", e.track, css);
    put(v, "--mm-progress-fill-color", e.fill, css);
  } else if (type === "field") {
    v["--mm-field-radius"] = radiusCss(e.radius, e.pill);
    v["--mm-field-width"] = `${num(e.width, 1)}px`;
    put(v, "--mm-field-outline", e.outline, css);
    put(v, "--mm-field-bg", e.fill, css);
    put(v, "--mm-field-text", e.text, css);
    put(v, "--mm-field-hint", e.hint, css);
    const fieldBevel = asBevel(e.bevel);
    if (fieldBevel) v["--mm-field-bevel"] = bevelToCss(fieldBevel, true, css);
    put(v, "--mm-dropdown-header-bg", e.headerFill, css);
    put(v, "--mm-dropdown-header-text", e.headerText, css);
  } else if (type === "list") {
    v["--mm-list-radius"] = radiusCss(e.radius);
    put(v, "--mm-list-hover", e.hover, css);
  } else if (type === "section") {
    put(v, "--mm-section-color", e.color, css);
    put(v, "--mm-section-line", e.line, css);
    Object.assign(v, textVars("section-text", e.text, "section", css));
  } else if (type === "confirm") {
    v["--mm-confirm-radius"] = radiusCss(e.radius);
  } else if (type === "body" || type === "title" || type === "hint" || type === "data") {
    const key: FontKey = type === "title" ? "title" : type === "hint" ? "hint" : "item";
    Object.assign(v, textVars(type, e, key, css));
  }
  return v;
}

const WHITE: Color = { R: 1, G: 1, B: 1, A: 1 };
const BLACK: Color = { R: 0, G: 0, B: 0, A: 1 };

function mixColor(a: Color, b: Color, t: number): Color {
  return { R: a.R + (b.R - a.R) * t, G: a.G + (b.G - a.G) * t, B: a.B + (b.B - a.B) * t, A: a.A + (b.A - a.A) * t };
}

/**
 * The title bar's gradient for the xpbar and classic headers: top to bottom for XP, left to right for
 * Classic (Chrome.TopBand). Undefined for any other header or a preset without barStops.
 */
export function bandFillCss(resolved: ResolvedStyle, css: (c: Color) => string): string | undefined {
  const variant = resolved.header.variant;
  const stops = colorStops(resolved.header.barStops);
  if (stops === undefined || (variant !== "xpbar" && variant !== "classic")) {
    return undefined;
  }
  return stopsToCss(stops, variant === "classic", css);
}

/** A stops list that has the two colours a gradient needs, or undefined. */
export function colorStops(v: unknown): Color[] | undefined {
  return Array.isArray(v) && v.length >= 2 && v.every(isColor) ? (v as Color[]) : undefined;
}

function cornerRadii(radius: unknown): [number, number, number, number] {
  if (Array.isArray(radius)) {
    return [num(radius[0], 0), num(radius[1], 0), num(radius[2], 0), num(radius[3], 0)];
  }
  const r = num(radius, 0);
  return [r, r, r, r];
}

// The window frame colours and sizes as variables: the title bar fill, the caption buttons' faces and
// the status bar (shell/chrome.lua). A variable is written only when the preset gives what it draws from,
// so a preset without a window frame gets none of them.
function frameVars(resolved: ResolvedStyle, css: (c: Color) => string): Record<string, string> {
  const vars: Record<string, string> = {};
  const header = resolved.header;
  const panel = resolved.panel;
  const p = resolved.palette;
  const variant = header.variant;
  const barStops = colorStops(header.barStops);
  const [rTopLeft, rTopRight] = cornerRadii(panel.radius);

  if (typeof panel.bandInset === "number") {
    vars["--mm-band-inset"] = `${panel.bandInset}px`;
  }
  const bandFill = bandFillCss(resolved, css);
  if (bandFill !== undefined) {
    vars["--mm-band-fill"] = bandFill;
    const r = Math.max(0, rTopLeft - 3);
    vars["--mm-band-radius"] = variant === "xpbar" ? `${r}px ${r}px 0 0` : "0";
  }
  if (variant === "xpbar") {
    // White on the blue bar with the dark drop shadow of Windows XP.
    vars["--mm-band-title-shadow"] = `1px 1px 0 ${isColor(header.titleShadow) ? css(header.titleShadow) : "rgb(15, 16, 137)"}`;
  }

  if (variant === "window") {
    vars["--mm-cap-hover"] = css(alpha(p.text, 0.06));
    vars["--mm-cap-press"] = css(alpha(p.text, 0.04));
    vars["--mm-cap-close-radius"] = `0 ${rTopRight}px 0 0`;
  }
  if (variant === "xpbar") {
    const controls = colorStops(header.controlStops) ?? barStops;
    const close = colorStops(header.closeStops) ?? barStops;
    const shade = (stops: Color[], toward: Color, amount: number) => stops.map((c) => mixColor(c, toward, amount));
    for (const [name, stops] of [["xp", controls], ["xp-close", close]] as const) {
      if (stops !== undefined) {
        vars[`--mm-cap-${name}`] = stopsToCss(stops, false, css);
        vars[`--mm-cap-${name}-hover`] = stopsToCss(shade(stops, WHITE, 0.25), false, css);
        vars[`--mm-cap-${name}-pressed`] = stopsToCss(shade(stops, BLACK, 0.2), false, css);
      }
    }
  }
  if (variant === "classic") {
    const face = isColor(header.controlFace) ? header.controlFace : { R: 0.527, G: 0.527, B: 0.527, A: 1 };
    // A panel without a usable bevel gets one derived from the face, so the press still shows.
    const bevel = asBevel(panel.bevel) ?? { light: mixColor(face, WHITE, 0.6), dark: mixColor(face, BLACK, 0.55) };
    vars["--mm-cap-face"] = css(face);
    vars["--mm-cap-bevel"] = bevelToCss(bevel, false, css);
    vars["--mm-cap-bevel-pressed"] = bevelToCss(bevel, true, css);
    vars["--mm-cap-ink"] = css(isColor(header.controlGlyph) ? header.controlGlyph : BLACK);
  }

  const status = panel.statusBar as ResolvedEntry | undefined;
  if (typeof status === "object" && status !== null) {
    // Without a fill the bar uses the panel background, and without a line the palette's line colour.
    vars["--mm-status-fill"] = css(isColor(status.fill) ? status.fill : p.bg);
    vars["--mm-status-line"] = css(isColor(status.line) ? status.line : p.line);
  }
  return vars;
}

/**
 * The CSS variables for a resolved style. They hold the legacy token variables the stock preview
 * reads (light and dark give exactly themeVars' values), the panel and header looks, the palette,
 * and each object type's own variables from typeVars.
 */
export function styleVars(resolved: ResolvedStyle): Record<string, string> {
  const css = cssColorFor(resolved);
  const panel = resolved.panel;
  const p = resolved.palette;
  const vars: Record<string, string> = {
    ...padVars(panelPad(panel.pad)),
    ...fontVars(),
    ...tokenVars(legacyColors(resolved) as ThemeColors, css),
  };

  // A theme's text sizes replace the preview sizes, scaled as the config sizes are.
  const sizes: [unknown, FontKey][] = [
    [resolved.title.size, "title"],
    [resolved.hint.size, "hint"],
    [resolved.body.size, "item"],
    [resolved.section.text?.size, "section"],
    [resolved.body.size, "dropdown"],
  ];
  for (const [size, key] of sizes) {
    const px = previewSize(size, key);
    if (px) vars[`--mm-font-${key}`] = px;
  }

  for (const key of ["text", "muted", "accent", "accentText", "surface", "line", "track", "warning"]) {
    put(vars, `--mm-${kebab(key)}`, p[key], css);
  }

  vars["--mm-panel-radius"] = radiusCss(panel.radius);
  vars["--mm-panel-width"] = `${num(panel.width, 0)}px`;
  put(vars, "--mm-panel-fill", panel.fill, css);
  put(vars, "--mm-panel-outline", panel.outline, css);
  vars["--mm-panel-blur"] = num(panel.blur, 0) > 0 ? `blur(${num(panel.blur, 0)}px)` : "none";
  vars["--mm-panel-shadow"] = panelShadow(panel, css);
  put(vars, "--mm-panel-rim-light", panel.rimLight, css);
  put(vars, "--mm-panel-rim-dark", panel.rimDark, css);
  vars["--mm-panel-rim-inset"] = `${Math.max(4, largestRadius(panel.radius))}px`;

  const header = resolved.header;
  put(vars, "--mm-header-line", header.line, css);
  put(vars, "--mm-header-badge-fill", header.badgeFill, css);
  vars["--mm-header-badge-radius"] = `${Math.min(8, largestRadius(panel.radius))}px`;
  vars["--mm-header-tape"] = `${num(header.tape, 8)}px`;
  vars["--mm-header-tape-alt"] = css(isColor(header.tapeAlt) ? header.tapeAlt : { R: 0, G: 0, B: 0, A: 0.85 });
  vars["--mm-header-strip"] = `${num(header.strip, 4)}px`;
  const bar = barColors(resolved);
  vars["--mm-header-bar-fill"] = css(bar.fill);
  vars["--mm-header-bar-text"] = css(bar.text);
  vars["--mm-header-bar-hint"] = css(alpha(bar.text, 0.8 * bar.text.A));
  Object.assign(vars, frameVars(resolved, css));

  for (const type of ["title", "body", "hint", "data", "section", "button", "toggle", "slider", "progress", "field", "list", "confirm"]) {
    Object.assign(vars, typeVars(type, (resolved as Record<string, ResolvedEntry>)[type], css));
  }
  if (resolved.motion?.glitch === true) {
    // The title's two ghost copies, one red and one in the accent, three units to either side (Effects.Title).
    const ghosts = `3px 0 0 ${css(alpha(p.danger, 0.8))}, -3px 0 0 ${css(alpha(p.accent, 0.8))}`;
    const own = vars["--mm-title-shadow"];
    vars["--mm-title-shadow"] = own !== undefined && own !== "none" ? `${own}, ${ghosts}` : ghosts;
  }
  return vars;
}
