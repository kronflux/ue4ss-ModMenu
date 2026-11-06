// How the preview draws each item from the resolved theme. Each function follows the Lua widget that
// draws the same item (named beside it), so the preview and the game choose the same variant and colours.
import { createContext, useContext, type CSSProperties } from "react";
import type { ButtonVariant, StyleOverrides, ThemeName } from "../schema";
import {
  asBevel,
  bevelToCss,
  BAND_HEADERS,
  colorStops,
  cssColorFor,
  headerVariant,
  isLegacyTheme,
  isStockPanel,
  largestRadius,
  radiusCss,
  stopsToCss,
  typefaceCss,
  typeVars,
} from "../theme/css";
import { PRESET_ORDER } from "../theme/presets.generated";
import { forItem, legacyColors, resolve, type ResolvedEntry, type ResolvedStyle } from "../theme/resolve";
import { shade, type Color } from "../theme/tokens";
import { buttonChrome, resolveVariant } from "./chrome";

/**
 * What every preview item reads: the resolved style, its CSS colour function, and the document's
 * style override table when the resolver accepted it (some parts switch on an explicit override).
 */
export type PreviewStyle = {
  resolved: ResolvedStyle;
  css: (c: Color) => string;
  legacy: boolean;
  style?: StyleOverrides;
};

export function previewStyle(resolved: ResolvedStyle, style?: StyleOverrides): PreviewStyle {
  return { resolved, css: cssColorFor(resolved), legacy: isLegacyTheme(resolved), style };
}

export const StyleContext = createContext<PreviewStyle>(previewStyle(resolve("light")));

export function usePreviewStyle(): PreviewStyle {
  return useContext(StyleContext);
}

/**
 * The preview's resolved style. An unknown preset id draws as light, as before; a style table the
 * resolver rejects while it is being edited is left out, so the preview keeps drawing the theme.
 */
export function previewResolve(theme: ThemeName, style?: StyleOverrides): ResolvedStyle {
  const id = PRESET_ORDER.includes(theme) ? theme : "light";
  if (style !== undefined) {
    try {
      return resolve(id, style);
    } catch {
      // Fall through to the theme alone.
    }
  }
  return resolve(id);
}

/** The preview style for a theme and a style table; a style table the resolver rejects counts as absent. */
export function previewFor(theme: ThemeName, style?: StyleOverrides): PreviewStyle {
  const id = PRESET_ORDER.includes(theme) ? theme : "light";
  if (style !== undefined && style !== null) {
    try {
      return previewStyle(resolve(id, style), style);
    } catch {
      // Fall through to the theme alone.
    }
  }
  return previewStyle(resolve(id));
}

function num(v: unknown): number {
  return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

/** The style table's entry for a type, when it overrides that type (a preset id or a field table). */
function overrideOf(style: StyleOverrides | undefined, type: string): unknown {
  if (style === undefined || style === null || typeof style !== "object") {
    return undefined;
  }
  const v: unknown = (style as Record<string, unknown>)[type];
  return v === null ? undefined : v;
}

/**
 * True when a type's override sets its text colour, as Label.StockSpec reads it. A preset id or `from`
 * counts as setting every field of the resolved entry. A section override sets it with text.color or
 * with color, which the resolver uses as the text colour when text names none.
 */
function overrideSetsColor(style: StyleOverrides | undefined, type: string): boolean {
  const entry = overrideOf(style, type);
  if (typeof entry === "string") {
    return true;
  }
  if (typeof entry !== "object" || entry === null) {
    return false;
  }
  const own = entry as Record<string, unknown>;
  if (own.from != null || own.color != null) {
    return true;
  }
  const text = own.text;
  return type === "section" && typeof text === "object" && text !== null && (text as Record<string, unknown>).color != null;
}

/**
 * How labels and separators draw (Label.Stock). stock is the library's original look and needs the
 * section variant to be exactly "stock" with no body, hint or section override. themed draws them in
 * the theme's text styles. legacy is a stock theme with such an override: the themed text style,
 * with each label's legacy colour as the base where the override sets no colour.
 */
export function labelMode(resolved: ResolvedStyle, style?: StyleOverrides): "stock" | "themed" | "legacy" {
  if (resolved.section.variant !== "stock") {
    return "themed";
  }
  const overridden = ["body", "hint", "section"].some((t) => overrideOf(style, t) !== undefined);
  return overridden ? "legacy" : "stock";
}

/** True when the stock header's title takes the title text style: the style table overrides title. */
export function titleThemed(resolved: ResolvedStyle, style?: StyleOverrides): boolean {
  return headerVariant(resolved) === "stock" && overrideOf(style, "title") !== undefined;
}

/**
 * The label colours of the legacy label mode as panel variables, as Label.StockSpec picks them: normal
 * labels take the resolved body colour when the body override sets a colour or borrows, headings the
 * resolved section text colour (or section colour) when the section override does, and each otherwise
 * keeps its legacy colour (textPrimary, textAccent). Muted and warning labels always keep textMuted and
 * textStatus, even when the body override sets a colour.
 * Nothing in the other modes.
 */
export function labelVars(ps: PreviewStyle): VarStyle {
  if (labelMode(ps.resolved, ps.style) !== "legacy") {
    return {};
  }
  const legacy = legacyColors(ps.resolved);
  const body: unknown = ps.resolved.body.color;
  const textColor: unknown = (ps.resolved.section.text as ResolvedEntry | undefined)?.color;
  const heading: unknown = isColor(textColor) ? textColor : ps.resolved.section.color;
  const bodyColor = overrideSetsColor(ps.style, "body") && isColor(body) ? body : undefined;
  const headingColor = overrideSetsColor(ps.style, "section") && isColor(heading) ? heading : undefined;
  return {
    "--mm-label-color": ps.css(bodyColor ?? legacy.textPrimary),
    "--mm-label-muted-color": ps.css(legacy.textMuted),
    "--mm-label-warning-color": ps.css(legacy.textStatus),
    "--mm-label-heading-color": ps.css(headingColor ?? legacy.textAccent),
  };
}

/**
 * The classes on the panel that select its look: header, section, label and decoration variants.
 * `style` is the document's accepted style table, for the parts an explicit override switches on.
 */
export function panelClasses(resolved: ResolvedStyle, style?: StyleOverrides): string {
  const panel = resolved.panel;
  const header = headerVariant(resolved);
  const sectionVariant: unknown = resolved.section.variant;
  // The section header is stock when the variant is absent or stock (Collapse.ThemedSection).
  const section = typeof sectionVariant === "string" ? sectionVariant : "stock";
  const classes = ["mm-panel", `mm-header-${header}`, `mm-section-${section}`];
  // A band header needs the themed panel, as Build.Panel draws it.
  if (!isStockPanel(panel, resolved.motion) || BAND_HEADERS.has(header)) {
    classes.push("mm-panel-themed");
  }
  if (num(panel.blur) > 0) classes.push("mm-blur");
  if (panel.rim === true) classes.push("mm-rim");
  // Labels and separators follow Label.Stock: only the exact value "stock" with no text override is stock.
  const labels = labelMode(resolved, style);
  if (labels !== "stock") classes.push(`mm-labels-${labels}`);
  if (titleThemed(resolved, style)) classes.push("mm-title-themed");
  return classes.join(" ");
}

/** CSS custom properties beside ordinary style keys. */
export type VarStyle = CSSProperties & Record<`--${string}`, string | undefined>;

type Look = Record<string, unknown> | undefined;

/** The class that names an item's variant, such as mm-variant-button-ghost, for CSS to select. */
export function variantClass(type: string, variant: string): string {
  return `mm-variant-${type}-${variant}`;
}

function isColor(v: unknown): v is Color {
  return typeof v === "object" && v !== null && typeof (v as Color).R === "number";
}

function alpha(c: Color, a: number): Color {
  return { R: c.R, G: c.G, B: c.B, A: a };
}

function mix(a: Color, b: Color, t: number): Color {
  return { R: a.R + (b.R - a.R) * t, G: a.G + (b.G - a.G) * t, B: a.B + (b.B - a.B) * t, A: a.A + (b.A - a.A) * t };
}

const WHITE: Color = { R: 1, G: 1, B: 1, A: 1 };
const BLACK: Color = { R: 0, G: 0, B: 0, A: 1 };

/** The item's look merged over its type, or the type alone when the look does not fit the field list. */
function lookOf(ps: PreviewStyle, type: string, look: Look): ResolvedEntry {
  try {
    return forItem(ps.resolved, type, look);
  } catch {
    return forItem(ps.resolved, type, undefined);
  }
}

/** The type's variables for an item with a look, so the look wins inside that item; nothing without one. */
export function lookVars(ps: PreviewStyle, type: string, look: Look): VarStyle | undefined {
  if (look === undefined || look === null) {
    return undefined;
  }
  return typeVars(type, lookOf(ps, type, look), ps.css) as VarStyle;
}

// ---------------------------------------------------------------------------------------------
// Buttons (widgets/button.lua, Button.States)
// ---------------------------------------------------------------------------------------------

const BUTTON_VARIANTS = new Set(["fill", "soft", "ghost", "underline", "xp", "classic"]);
const TINTS: Record<string, [number, number, number]> = {
  soft: [0.14, 0.24, 0.34],
  ghost: [0, 0.16, 0.3],
  underline: [0, 0.16, 0.3],
};
const PRESS_DARKEN = 0.22;
const MIN_TONE_ALPHA = 0.05;
const ROLES = new Set(["default", "primary", "secondary", "success", "danger", "warning", "info"]);

export type ButtonLook = {
  variant: string;
  className: string;
  style: VarStyle;
  /** False for a flat fill button, which draws with today's legacy colour variables. */
  shaped: boolean;
  /** True for a square fill button with no edge, whatever its colours. */
  flat: boolean;
};

type ButtonOpts = { variant?: ButtonVariant | string; enabled?: boolean; active?: boolean; look?: Look };

// Disabled wins, then active, then the item's variant, as ChromeColors chooses.
function roleName(item: ButtonOpts): string {
  if (item.enabled === false) return "disabled";
  if (item.active === true) return "active";
  const v = resolveVariant(item.variant as ButtonVariant | undefined);
  return ROLES.has(v) ? v : "default";
}

// The button's own typeface, spacing and case, which every shaped look shares.
function typography(b: ResolvedEntry, style: VarStyle) {
  const face = typefaceCss(b.typeface);
  if (face.weight) style.fontWeight = face.weight;
  if (face.style) style.fontStyle = face.style;
  if (typeof b.spacing === "number") style.letterSpacing = `${b.spacing / 1000}em`;
  if (b.upper === true) style.textTransform = "uppercase";
}

/**
 * A button's look: its variant class, colours, radius, edge and the hover and pressed colours.
 * `over` is merged over the button style last, as the stepper puts its radius and pill there.
 * A flat fill button with no look or override keeps today's legacy colour variables, so light and
 * dark buttons stay as they were.
 */
export function buttonLook(ps: PreviewStyle, item: ButtonOpts, over?: Record<string, unknown>): ButtonLook {
  const b: ResolvedEntry = { ...lookOf(ps, "button", item.look), ...over };
  const p = ps.resolved.palette;
  const name = roleName(item);
  const roles = (b.roles ?? {}) as Record<string, ResolvedEntry>;
  const role = roles[name] ?? roles.default ?? {};
  let variant = typeof role.variant === "string" ? role.variant : b.variant;
  if (!BUTTON_VARIANTS.has(variant)) {
    variant = "fill";
  }
  // A theme's face for the role replaces its fill and caption colour, but not for disabled or active, which
  // keep their own so they stay distinguishable. xp and classic draw layers only for a role that is neither
  // and only when the theme gives them what they draw from; otherwise they draw as a flat fill (Look).
  const layered = name !== "disabled" && name !== "active";
  const faces = (b.faces ?? {}) as Record<string, ResolvedEntry>;
  const roleFace = layered ? faces[name] : undefined;
  const xp = (b.xp ?? undefined) as ResolvedEntry | undefined;
  const xpFace = colorStops(xp?.face);
  const xpPressed = colorStops(xp?.pressedFace);
  const bevel = asBevel(b.bevel);
  if (variant === "xp" && (!layered || xpFace === undefined || xpPressed === undefined)) variant = "fill";
  else if (variant === "classic" && (!layered || bevel === undefined)) variant = "fill";
  const radius: unknown = b.radius ?? 0;
  const pill = b.pill === true;
  const roleFill: unknown = roleFace !== undefined && isColor(roleFace.fill) ? roleFace.fill : role.fill;
  const roleText: unknown = roleFace !== undefined && isColor(roleFace.text) ? roleFace.text : role.text;
  const base: Color = isColor(roleFill) ? roleFill : WHITE;
  let tone: Color | undefined = isColor(role.edge) ? role.edge : undefined;
  if (tone === undefined && name === "secondary") tone = p.text;
  else if (tone === undefined && name === "disabled" && isColor(role.text)) tone = role.text;
  tone = tone ?? base;
  // A tone too faint to see draws in the role's text colour instead (Button.VisibleTone).
  if (tone.A < MIN_TONE_ALPHA && isColor(roleText)) tone = roleText;

  let outline: unknown;
  if (variant === "ghost") outline = tone;
  else if (variant !== "underline") outline = (name === "secondary" && b.secondaryEdge) || b.edge;
  const width = typeof b.width === "number" ? b.width : 1;
  const edge = isColor(outline) && width > 0 ? { color: outline, width } : undefined;
  const flat = largestRadius(radius) <= 0 && !pill && edge === undefined;
  const className = variantClass("button", variant);

  // A theme that sets a button height gives the button that minimum height (Button.States, height).
  const minHeight = typeof b.height === "number" && b.height > 0 ? `${b.height}px` : undefined;

  if (variant === "fill" && flat && item.look === undefined && over === undefined) {
    const style: VarStyle = buttonChrome({ enabled: item.enabled, active: item.active, variant: item.variant as ButtonVariant });
    if (minHeight !== undefined) style.minHeight = minHeight;
    return { variant, className, style, shaped: false, flat: true };
  }

  if (variant === "xp" || variant === "classic") {
    const text = isColor(roleText) ? roleText : p.text;
    const style: VarStyle = { color: ps.css(text), borderRadius: radiusCss(radius, pill) };
    if (variant === "xp") {
      // A dark rounded edge around a gradient face. The default ring sits inside the edge on a primary
      // button; hover swaps it for the glow, and pressed takes the darker face with no ring.
      const edgeRing = `inset 0 0 0 1px ${ps.css(isColor(xp?.edge) ? xp.edge : BLACK)}`;
      const ring = (c: unknown) => (isColor(c) ? `, inset 0 0 0 2px ${ps.css(c)}` : "");
      const faceCss = stopsToCss(xpFace as Color[], false, ps.css);
      style.background = faceCss;
      style.boxShadow = edgeRing + (name === "primary" ? ring(xp?.defaultRing) : "");
      style["--mm-btn-hover"] = faceCss;
      style["--mm-btn-pressed"] = stopsToCss(xpPressed as Color[], false, ps.css);
      style["--mm-btn-hover-shadow"] = edgeRing + ring(xp?.glow);
      style["--mm-btn-pressed-shadow"] = edgeRing;
    } else {
      // A raised two-ring bevel that turns sunken while pressed; hover looks like rest.
      const raised = bevelToCss(bevel, false, ps.css);
      style.background = ps.css(base);
      style.boxShadow = raised;
      style["--mm-btn-hover"] = ps.css(base);
      style["--mm-btn-pressed"] = ps.css(base);
      style["--mm-btn-hover-shadow"] = raised;
      style["--mm-btn-pressed-shadow"] = bevelToCss(bevel, true, ps.css);
    }
    if (minHeight !== undefined) style.minHeight = minHeight;
    typography(b, style);
    return { variant, className: `${className} mm-btn-shaped mm-btn-layered`, style, shaped: true, flat: false };
  }

  let normal: Color;
  let hover: Color;
  let pressed: Color;
  let text: Color;
  if (variant === "fill") {
    normal = base;
    text = isColor(roleText) ? roleText : p.text;
    if (flat) {
      hover = shade(base, 0.12);
      pressed = shade(base, -0.12);
    } else {
      hover = mix(base, isColor(b.hoverToward) ? b.hoverToward : WHITE, typeof b.hoverAmount === "number" ? b.hoverAmount : 0.14);
      pressed = mix(base, BLACK, PRESS_DARKEN);
    }
  } else {
    const tint = TINTS[variant];
    text = tone;
    normal = alpha(tone, tint[0]);
    hover = alpha(tone, tint[1]);
    pressed = alpha(tone, tint[2]);
  }
  if (isColor(role.hover)) hover = role.hover;
  if (isColor(role.pressed)) pressed = role.pressed;
  if (name === "disabled" || name === "active") {
    hover = normal;
    pressed = normal;
  }

  const style: VarStyle = {
    background: ps.css(normal),
    color: ps.css(text),
    borderRadius: radiusCss(radius, pill),
    "--mm-btn-hover": ps.css(hover),
    "--mm-btn-pressed": ps.css(pressed),
  };
  if (edge !== undefined) {
    // The game draws the outline with a Border inside the button, so it takes no room outside it.
    style.boxShadow = `inset 0 0 0 ${edge.width}px ${ps.css(edge.color)}`;
  }
  if (variant === "underline") {
    style["--mm-btn-underline"] = ps.css(tone);
  }
  if (minHeight !== undefined) style.minHeight = minHeight;
  typography(b, style);
  return { variant, className: `${className} mm-btn-shaped`, style, shaped: true, flat: variant === "fill" && flat };
}

/**
 * The stepper's minus and plus buttons: the stepper's role, with its radius and pill over the button
 * style, as widgets/stepper.lua builds them. An item's look is a stepper look.
 */
export function stepperButtonLook(ps: PreviewStyle, look: Look): ButtonLook {
  const st = lookOf(ps, "stepper", look);
  const over: Record<string, unknown> = {};
  if (st.radius !== undefined) over.radius = st.radius;
  if (st.pill !== undefined) over.pill = st.pill;
  return buttonLook(ps, { variant: typeof st.role === "string" ? st.role : "default" }, over);
}

/**
 * The Close button's look (shell/build.lua, CloseStates). On a coloured header band it is a clear
 * wash of the band's text colour; elsewhere it is the button style's default role.
 */
export function closeLook(ps: PreviewStyle, bandText?: Color): ButtonLook {
  if (bandText === undefined) {
    return buttonLook(ps, {});
  }
  const b = ps.resolved.button;
  return {
    variant: "band",
    className: "mm-btn-shaped",
    shaped: true,
    flat: false,
    style: {
      background: "transparent",
      color: ps.css(bandText),
      borderRadius: radiusCss(b.radius, b.pill),
      "--mm-btn-hover": ps.css(alpha(bandText, 0.14)),
      "--mm-btn-pressed": ps.css(alpha(bandText, 0.24)),
    },
  };
}

// ---------------------------------------------------------------------------------------------
// Toggles, sliders, progress bars, choices and fields
// ---------------------------------------------------------------------------------------------

const TOGGLE_VARIANTS = new Set(["stock", "switch", "square", "check", "text"]);

/**
 * The toggle variant, as Checkbox.build chooses it: the resolved toggle variant (Checkbox.Variant), which
 * light and dark set to stock, so a toggle override shows on every theme; then an item look naming a
 * known variant wins. A look the style module rejects falls back to stock.
 */
export function toggleVariant(ps: PreviewStyle, look: Look): string {
  const own: unknown = ps.resolved.toggle.variant;
  let variant = typeof own === "string" && TOGGLE_VARIANTS.has(own) ? own : "stock";
  const asked: unknown = look?.variant;
  if (typeof asked === "string" && TOGGLE_VARIANTS.has(asked)) {
    variant = asked;
  }
  if (variant !== "stock") {
    try {
      forItem(ps.resolved, "toggle", look);
    } catch {
      return "stock";
    }
  }
  return variant;
}

/** The slider variant (Slider.Variant); light and dark say stock. */
export function sliderVariant(ps: PreviewStyle, look: Look): string {
  const v = lookOf(ps, "slider", look).variant;
  return typeof v === "string" ? v : "stock";
}

/** The progress variant (Progress.Variant); light and dark say stock. */
export function progressVariant(ps: PreviewStyle, look: Look): string {
  const v = lookOf(ps, "progress", look).variant;
  return typeof v === "string" ? v : "stock";
}

/** The field variant: frame draws the field style's fill, outline and radius; stock draws as today. */
export function fieldVariant(ps: PreviewStyle, look: Look): string {
  const v = lookOf(ps, "field", look).variant;
  return typeof v === "string" ? v : "stock";
}

const SEGMENT_EPSILON = 1e-9;

/** How many of n segments are lit (Progress.SegmentsLit): rounded down, 0 at min and n at max. */
export function segmentsLit(value: number, min: number, max: number, n: number): number {
  if (!Number.isFinite(value) || max <= min || n <= 0) {
    return 0;
  }
  const f = (value - min) / (max - min);
  if (f <= 0) return 0;
  if (f >= 1) return n;
  return Math.floor(f * n + SEGMENT_EPSILON);
}

export type ProgressLook = {
  variant: string;
  entry: ResolvedEntry;
  fill: string;
  /** The colour of each segment when lit, for the segments variant. */
  segmentColors: string[];
  /** A lit block's vertical shading, when the theme gives progress.block; it replaces the segment colour. */
  block?: string;
  /** The frame around the trough: kind edge or bevel, drawn as the padded wrapper's style. */
  frame?: { kind: "edge" | "bevel"; style: VarStyle };
};

// A frame with an edge or a usable bevel gets this much room around the trough when it names none
// (Progress.FrameSpec). A bevel wins over an edge in the kind, and both are drawn when both are set.
function progressFrame(ps: PreviewStyle, entry: ResolvedEntry): ProgressLook["frame"] {
  const f = entry.frame as ResolvedEntry | undefined;
  if (typeof f !== "object" || f === null) {
    return undefined;
  }
  const bevel = asBevel(f.bevel);
  const edge = isColor(f.edge) ? f.edge : undefined;
  if (bevel === undefined && edge === undefined) {
    return undefined;
  }
  const shadows: string[] = [];
  if (bevel !== undefined) shadows.push(bevelToCss(bevel, true, ps.css));
  if (edge !== undefined) shadows.push(`inset 0 0 0 1px ${ps.css(edge)}`);
  return {
    kind: bevel !== undefined ? "bevel" : "edge",
    style: {
      padding: `${typeof f.pad === "number" ? f.pad : 2}px`,
      // A frame that names no fill is white, as StyleLab's trough frame is.
      background: ps.css(isColor(f.fill) ? f.fill : WHITE),
      borderRadius: radiusCss(f.radius),
      boxShadow: shadows.join(", "),
    },
  };
}

/**
 * A progress bar's look. An item naming a button role fills with that role's colour, as
 * Progress.ThemedFill does; a ramp colours the segments from first to last, or in turn when it cycles.
 */
export function progressLook(ps: PreviewStyle, item: { variant?: string; look?: Look }): ProgressLook {
  const entry = lookOf(ps, "progress", item.look);
  const variant = typeof entry.variant === "string" ? entry.variant : "stock";
  const roleKey = resolveVariant(item.variant as ButtonVariant | undefined);
  const role = roleKey !== "default" ? (ps.resolved.button.roles?.[roleKey] as ResolvedEntry | undefined) : undefined;
  const fillColor: Color = isColor(role?.fill) ? role.fill : isColor(entry.fill) ? entry.fill : WHITE;
  const n = Math.max(1, Math.floor(typeof entry.segments === "number" ? entry.segments : 12));
  const ramp = Array.isArray(entry.ramp) ? (entry.ramp as unknown[]).filter(isColor) : [];
  const segmentColors: string[] = [];
  for (let i = 0; i < n; i += 1) {
    let c = fillColor;
    if (ramp.length > 0) {
      const index = entry.cycle === true ? i % ramp.length : Math.min(ramp.length - 1, Math.floor((i / n) * ramp.length));
      c = ramp[index];
    }
    segmentColors.push(ps.css(c));
  }
  const block = colorStops(entry.block);
  return {
    variant,
    entry,
    fill: ps.css(fillColor),
    segmentColors,
    block: block !== undefined ? stopsToCss(block, false, ps.css) : undefined,
    frame: variant === "stock" ? undefined : progressFrame(ps, entry),
  };
}

/** A choice strip's drawing settings, from the choice style for radio and multiselect or the tabs style for tabs. */
export type ChoiceLook = { variant: string; style: VarStyle; textOn: string; textOff: string };

/**
 * A choice strip's look (widgets/radio.lua and StyleLab MakeChoice). Joined sits in one frame,
 * chips are separate outlined shapes, tabs underline the chosen option, radio draws a ring and dot.
 */
export function choiceLook(ps: PreviewStyle, type: "choice" | "tabs", look: Look): ChoiceLook {
  const c = lookOf(ps, type, look);
  const p = ps.resolved.palette;
  const variant = typeof c.variant === "string" ? c.variant : "stock";
  const radius = typeof c.radius === "number" ? c.radius : 0;
  // Only the tab strip turns its frame clear with an accent edge when buttons are ghost (shell/tabs.lua);
  // a radio or multiselect frame takes trackFill or the surface and the choice edge (Radio._choiceFrame).
  const ghost = type === "tabs" && ps.resolved.button.variant === "ghost";
  const frameEdge: unknown = c.edge ?? (ghost ? alpha(p.accent, 0.6) : undefined);
  const markFill: Color = isColor(c.markFill) ? c.markFill : p.accent;
  const style: VarStyle = {
    "--mm-ch-radius": radiusCss(c.radius, c.pill),
    // A joined frame is 3 rounder than its marks, so the marks sit evenly inside it.
    "--mm-ch-frame-radius": c.pill === true ? "999px" : radius > 0 ? `${radius + 3}px` : radiusCss(c.radius),
    "--mm-ch-frame-fill": ps.css(isColor(c.trackFill) ? c.trackFill : ghost ? alpha(p.accent, 0) : p.surface),
    "--mm-ch-frame-edge": isColor(frameEdge) ? `inset 0 0 0 1px ${ps.css(frameEdge)}` : "none",
    "--mm-ch-chip-edge": `inset 0 0 0 1px ${ps.css(isColor(c.edge) ? c.edge : p.line)}`,
    "--mm-ch-mark-fill": ps.css(markFill),
    // A shadow that draws nothing rather than none, so a chip can list it beside its own edge.
    "--mm-ch-mark-edge": isColor(c.markEdge) ? `inset 0 0 0 1px ${ps.css(c.markEdge)}` : "inset 0 0 0 0 transparent",
    "--mm-ch-mark-width": typeof c.markWidth === "number" ? `${c.markWidth}px` : "100%",
    "--mm-ch-mark-height": typeof c.markWidth === "number" ? `${typeof c.markHeight === "number" ? c.markHeight : 3}px` : "2px",
    "--mm-ch-mark-radius": typeof c.markWidth === "number" ? "999px" : "0",
    "--mm-ch-radio-fill": ps.css(isColor(c.radioFill) ? c.radioFill : WHITE),
    "--mm-ch-radio-edge": ps.css(isColor(c.radioEdge) ? c.radioEdge : p.text),
    "--mm-ch-wash": ps.css(alpha(p.text, 0.08)),
  };
  let textOn = ps.css(isColor(c.markText) ? c.markText : p.accentText);
  let textOff = ps.css(p.text);
  if (variant === "tabs") {
    textOn = ps.css(isColor(c.tabText) ? c.tabText : markFill);
    textOff = ps.css(p.muted);
  } else if (variant === "radio") {
    textOn = textOff;
  }
  return { variant, style, textOn, textOff };
}

/** A text style as inline CSS, for an item whose look changes its own text (labels). */
export function textLookStyle(ps: PreviewStyle, type: string, look: Look): VarStyle | undefined {
  const vars = lookVars(ps, type, look);
  if (vars === undefined) {
    return undefined;
  }
  return { ...vars, color: vars[`--mm-${type}-color`] };
}
