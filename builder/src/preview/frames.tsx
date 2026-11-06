// The window frames, status bar and still effects of the stage 2 themes, drawn from the resolved style.
// Each part follows shell/chrome.lua or shell/effects.lua, named beside it. Nothing here moves: the
// effects are drawn in one resting state, as the builder preview does for every look.
import type { CSSProperties } from "react";
import { bandFillCss, scanStrength } from "../theme/css";
import type { Color } from "../theme/tokens";
import { usePreviewStyle, type PreviewStyle, type VarStyle } from "./look";

// Chrome.Controls: the caption buttons of each control style in drawing order. A click on minimise or
// close closes the menu and maximise does nothing, which the preview has no menu to show.
const CAPTION_KINDS = ["min", "max", "close"] as const;
type CaptionKind = (typeof CAPTION_KINDS)[number];

function captionKinds(captions: unknown): CaptionKind[] {
  return captions === "close" ? ["close"] : [...CAPTION_KINDS];
}

const CAPTION_LABEL: Record<CaptionKind, string> = { min: "Minimise", max: "Maximise", close: "Close" };

// Every cross is two bars at 45 and -45 degrees, as Paint.Cross draws it; no game texture is used.
function Cross() {
  return (
    <i className="mm-cross" aria-hidden="true">
      <b />
      <b />
    </i>
  );
}

function CaptionGlyph({ kind }: { kind: CaptionKind }) {
  if (kind === "close") {
    return <Cross />;
  }
  return <i className={kind === "min" ? "mm-g-min" : "mm-g-max"} aria-hidden="true" />;
}

function CaptionButtons({ variant, captions }: { variant: string; captions: unknown }) {
  return (
    <span className="mm-caps">
      {captionKinds(captions).map((kind) => (
        <button key={kind} type="button" className={`mm-cap mm-cap-${kind}`} aria-label={CAPTION_LABEL[kind]}>
          {variant === "xpbar" && <i className="mm-cap-shine" aria-hidden="true" />}
          <CaptionGlyph kind={kind} />
        </button>
      ))}
    </span>
  );
}

/**
 * The title bar for the window, xpbar and classic headers (Chrome.TopBand and Chrome.BandRow): the
 * title, then the caption buttons flush with the right edge. XP's bar is a gradient from top to bottom
 * and Classic's runs from left to right.
 */
export function WindowBand({ title, variant }: { title: string; variant: string }) {
  const ps = usePreviewStyle();
  const fill = bandFillCss(ps.resolved, ps.css);
  const style: CSSProperties | undefined = fill !== undefined ? { background: fill } : undefined;
  return (
    <div className={`mm-band-window mm-band-${variant}`} style={style}>
      <h2 className="mm-title mm-band-title">{title}</h2>
      <CaptionButtons variant={variant} captions={ps.resolved.header.captions} />
    </div>
  );
}

// Chrome.TrafficLights: the three lights in order close, minimise, maximise. Hovering one shows the
// symbols on all three.
const LIGHTS = ["close", "min", "max"] as const;

export function MacHeader({ title }: { title: string }) {
  return (
    <div className="mm-mac-bar">
      <span className="mm-lights">
        {LIGHTS.map((kind) => (
          <button key={kind} type="button" className={`mm-light mm-light-${kind}`} aria-label={CAPTION_LABEL[kind]}>
            {kind === "close" ? <Cross /> : <i className={kind === "min" ? "mm-g-min" : "mm-g-plus"} aria-hidden="true" />}
          </button>
        ))}
      </span>
      <h2 className="mm-title mm-mac-title">{title}</h2>
    </div>
  );
}

/** The status bar along the bottom edge of the panel (Chrome.StatusBar): a dividing line and a message. */
export function StatusBar({ ps }: { ps: PreviewStyle }) {
  const bar = ps.resolved.panel.statusBar as { text?: unknown } | undefined;
  if (typeof bar !== "object" || bar === null) {
    return null;
  }
  return (
    <div className="mm-status">
      <span>{typeof bar.text === "string" ? bar.text : "Ready"}</span>
    </div>
  );
}

// Effects.SparkleSpots: the six glints of the frost look, placed by their distance from two edges.
const SPARKLES: { size: number; top?: number; right?: number; bottom?: number; left?: number }[] = [
  { size: 4, top: 12, right: 28 },
  { size: 3, top: 26, right: 46 },
  { size: 2, top: 8, right: 64 },
  { size: 3, left: 22, bottom: 18 },
  { size: 2, left: 40, bottom: 30 },
  { size: 3, right: 30, bottom: 24 },
];

function alpha(c: Color, a: number): Color {
  return { R: c.R, G: c.G, B: c.B, A: a };
}

/**
 * The drawn effects over the panel (Effects.Build), shown at rest and clicks pass through: scanlines as a
 * repeating gradient, the sweep and the noise band as one still band each, and the glints as dots.
 * Nothing when the theme draws none, so a plain theme's markup has no layer.
 */
export function EffectsLayer() {
  const ps = usePreviewStyle();
  const { panel, palette, motion } = ps.resolved;
  const strength = scanStrength(panel);
  const sweep = panel.sweep === true;
  const sparkle = motion?.sparkle === true;
  if (strength <= 0 && !sweep && !sparkle) {
    return null;
  }
  const period = typeof panel.scanPeriod === "number" && panel.scanPeriod > 1 ? panel.scanPeriod : 2.5;
  const black: Color = { R: 0, G: 0, B: 0, A: 1 };
  const scan: VarStyle = {
    // One 1-unit dark line per period, at the mean of the library's seeded alphas, which is the strength.
    background: `repeating-linear-gradient(180deg, transparent 0 0.5px, ${ps.css(alpha(black, strength))} 0.5px 1.5px, transparent 1.5px ${period}px)`,
  };
  return (
    <div className="mm-fx" aria-hidden="true">
      {sweep && (
        <>
          <div className="mm-fx-sweep">
            <span style={{ height: 24, background: ps.css(alpha(palette.accent, 0.03)) }} />
            <span style={{ height: 10, background: ps.css(alpha(palette.accent, 0.08)) }} />
            <span style={{ height: 24, background: ps.css(alpha(palette.accent, 0.03)) }} />
          </div>
          <div className="mm-fx-noise" style={{ background: ps.css(alpha(black, 0.22)) }} />
        </>
      )}
      {sparkle &&
        SPARKLES.map((spot, i) => (
          <span
            key={i}
            className="mm-fx-sparkle"
            style={{ width: spot.size, height: spot.size, top: spot.top, right: spot.right, bottom: spot.bottom, left: spot.left }}
          />
        ))}
      {strength > 0 && <div className="mm-fx-scan" style={scan} />}
    </div>
  );
}
