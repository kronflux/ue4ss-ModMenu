import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { StyleOverrides } from "../schema";
import { fullDocument } from "../schema/fullFixture";
import { bevelToCss, colorCss, fontFamily, linearToSrgb, stopsToCss, styleVars, themeVars } from "../theme/css";
import { PRESET_ORDER } from "../theme/presets.generated";
import { hex, resolve } from "../theme/resolve";
import {
  buttonLook,
  choiceLook,
  fieldVariant,
  panelClasses,
  previewStyle,
  progressVariant,
  segmentsLit,
  sliderVariant,
  StyleContext,
  toggleVariant,
} from "./look";
import { ConfirmCard, MenuPreview } from "./MenuPreview";

describe("styleVars", () => {
  it("gives slate's panel radius", () => {
    expect(styleVars(resolve("slate"))["--mm-panel-radius"]).toBe("14px");
  });

  it.each(["light", "dark"])("keeps every value themeVars(%s) gave", (name) => {
    const before = themeVars(name);
    const after = styleVars(resolve(name));
    for (const [key, value] of Object.entries(before)) {
      expect([key, after[key]]).toEqual([key, value]);
    }
  });

  it.each(["light", "dark"])("gives %s's title the stock text colour", (name) => {
    const vars = styleVars(resolve(name));
    expect(vars["--mm-title-color"]).toBe(vars["--mm-text-primary"]);
  });

  it("makes a borrowed neon button a pill", () => {
    expect(styleVars(resolve("slate", { button: "neon" }))["--mm-button-radius"]).toBe("999px");
  });
});

describe("colours and fonts", () => {
  it("converts linear 0.2140 to about 0.5 sRGB", () => {
    expect(linearToSrgb(0.214)).toBeCloseTo(0.5, 3);
  });

  it("round-trips a hex channel through linear and back", () => {
    expect(linearToSrgb(hex("#808080").R) * 255).toBeCloseTo(128, 6);
    expect(linearToSrgb(hex("#4C8DFF").G) * 255).toBeCloseTo(0x8d, 6);
  });

  it("names a font chain by family with a fallback", () => {
    expect(fontFamily(["kanit", "roboto"])).toBe('Kanit, Roboto, system-ui, "Segoe UI", sans-serif');
    expect(fontFamily(["inconsolata", "mono", "roboto"])).toBe(
      'Inconsolata, "Droid Sans Mono", Roboto, ui-monospace, Consolas, monospace',
    );
    expect(fontFamily(undefined)).toBeUndefined();
  });
});

describe("item variants", () => {
  it("gives a slate button the fill variant", () => {
    expect(buttonLook(previewStyle(resolve("slate")), {}).className).toContain("mm-variant-button-fill");
  });

  it("gives a borrowed neon button the ghost variant with a pill radius", () => {
    const look = buttonLook(previewStyle(resolve("slate", { button: "neon" })), {});
    expect(look.className).toContain("mm-variant-button-ghost");
    expect(look.style.borderRadius).toBe("999px");
    // The default role's tone is its fill, slate's surface #2A2F39, clear until hovered (Button.States).
    expect(look.style.background).toBe("rgba(42, 47, 57, 0)");
  });

  it("keeps light's buttons on the legacy colour variables", () => {
    const look = buttonLook(previewStyle(resolve("light")), { variant: "primary" });
    expect(look.shaped).toBe(false);
    expect(look.style).toEqual({ background: "var(--mm-button-bg-primary)", color: "var(--mm-button-text-primary)" });
  });

  it("applies an item look over the type", () => {
    const look = buttonLook(previewStyle(resolve("slate")), { look: { variant: "soft" } });
    expect(look.className).toContain("mm-variant-button-soft");
  });

  it.each(["light", "dark"])("draws every %s part stock", (name) => {
    const ps = previewStyle(resolve(name));
    expect(toggleVariant(ps, undefined)).toBe("stock");
    expect(sliderVariant(ps, undefined)).toBe("stock");
    expect(progressVariant(ps, undefined)).toBe("stock");
    expect(choiceLook(ps, "choice", undefined).variant).toBe("stock");
    expect(choiceLook(ps, "tabs", undefined).variant).toBe("stock");
    expect(fieldVariant(ps, undefined)).toBe("stock");
    expect(panelClasses(ps.resolved)).toBe("mm-panel mm-header-stock mm-section-stock");
  });

  it("gives slate a switch and a badge header on a themed panel", () => {
    const ps = previewStyle(resolve("slate"));
    expect(toggleVariant(ps, undefined)).toBe("switch");
    expect(panelClasses(ps.resolved)).toContain("mm-header-badge");
    expect(panelClasses(ps.resolved)).toContain("mm-panel-themed");
  });

  it("counts lit segments as Progress.SegmentsLit does", () => {
    expect(segmentsLit(50, 0, 100, 12)).toBe(6);
    expect(segmentsLit(0, 0, 100, 12)).toBe(0);
    expect(segmentsLit(100, 0, 100, 12)).toBe(12);
    expect(segmentsLit(99.9, 0, 100, 12)).toBe(11);
  });
});

describe("parity with the Lua widgets", () => {
  it("lets an item look pick a toggle variant, even on light and dark", () => {
    expect(toggleVariant(previewStyle(resolve("light")), { variant: "check" })).toBe("check");
    expect(toggleVariant(previewStyle(resolve("dark")), { variant: "text" })).toBe("text");
    expect(toggleVariant(previewStyle(resolve("slate")), { variant: "square" })).toBe("square");
  });

  it("draws a toggle stock when its look is rejected", () => {
    expect(toggleVariant(previewStyle(resolve("slate")), { variant: "check", checkOn: "not a colour" })).toBe("stock");
  });

  it("keeps the ghost frame rule for tabs only", () => {
    const ps = previewStyle(resolve("slate", { button: "neon" }));
    const choice = choiceLook(ps, "choice", undefined).style;
    // Slate's surface #2A2F39, and no edge because the choice style sets none.
    expect(choice["--mm-ch-frame-fill"]).toBe("rgb(42, 47, 57)");
    expect(choice["--mm-ch-frame-edge"]).toBe("none");
    const tabs = choiceLook(ps, "tabs", undefined).style;
    // Slate's accent #4C8DFF, clear, with the edge at 0.6.
    expect(tabs["--mm-ch-frame-fill"]).toBe("rgba(76, 141, 255, 0)");
    expect(tabs["--mm-ch-frame-edge"]).toBe("inset 0 0 0 1px rgba(76, 141, 255, 0.6)");
  });

  it("themes labels unless the section variant is exactly stock", () => {
    const base = resolve("light");
    const absent = { ...base, section: { ...base.section, variant: undefined } };
    expect(panelClasses(absent)).toContain("mm-labels-themed");
    expect(panelClasses(absent)).toContain("mm-section-stock");
    expect(panelClasses(base)).not.toContain("mm-labels-themed");
  });

  it("draws themed labels in every font field of the body text style", () => {
    // The panel carries slate's body font, and the themed label rule reads each body text variable.
    expect(styleVars(resolve("slate"))["--mm-body-font"]).toContain("Roboto");
    const css = readFileSync(new URL("./MenuPreview.css", import.meta.url), "utf8");
    const rule = /\.mm-labels-themed \.mm-label \{([^}]*)\}/.exec(css)?.[1] ?? "";
    for (const field of ["font", "weight", "style", "spacing", "transform", "shadow", "stroke", "skew"]) {
      expect([field, rule.includes(`var(--mm-body-${field}`)]).toEqual([field, true]);
    }
  });

  it("draws a ghost button whose tone is clear in the role's text colour", () => {
    // Neon's default role fill is its surface #22F1FF00, alpha 0, so the tone is the role text #FFFFFF.
    const look = buttonLook(previewStyle(resolve("neon")), {});
    expect(look.className).toContain("mm-variant-button-ghost");
    expect(look.style.color).toBe("rgb(255, 255, 255)");
    expect(look.style.boxShadow).toBe("inset 0 0 0 2px rgb(255, 255, 255)");
    expect(look.style["--mm-btn-hover"]).toBe("rgba(255, 255, 255, 0.16)");
  });
});

describe("stage 2 looks", () => {
  const doc = fullDocument();
  const html = (theme: string, style?: StyleOverrides) =>
    renderToStaticMarkup(<MenuPreview document={{ ...doc, init: { ...doc.init, theme, style } }} />);
  const count = (text: string, needle: RegExp) => (text.match(needle) ?? []).length;
  // Slate with an XP title bar, XP buttons, a status bar and framed gradient progress blocks.
  const XP_HEADER = {
    variant: "xpbar",
    barStops: ["#5AA6FF", "#0058E6", "#003FB8"],
    controlStops: ["#D8E6FF", "#3C78EA", "#3A72E0"],
    closeStops: ["#F8C8B4", "#E2582E", "#D9542A"],
  };
  const XP_BUTTON = {
    variant: "xp",
    xp: {
      edge: "#003C74",
      glow: "#F8B33A",
      defaultRing: "#8CB4F0",
      face: ["#FFFFFF", "#EEEDE7", "#D6D0C5"],
      pressedFace: ["#CDC9B8", "#EFEEE7"],
    },
  };
  const XP = {
    panel: { statusBar: { text: "Ready", fill: "#ECE9D8", line: "#C5C2B2" } },
    header: XP_HEADER,
    button: XP_BUTTON,
    progress: {
      variant: "segments",
      block: ["#A6F09C", "#37D52C", "#3AC22E"],
      frame: { edge: "#686868", radius: 4, pad: 2, fill: "#FFFFFF" },
    },
  } as StyleOverrides;
  // Slate with Classic two-ring bevels on the panel, buttons, check box, field and progress frame.
  const BEVEL = { light: "#DFDFDF", dark: "#0A0A0A", innerLight: "#FFFFFF", innerDark: "#808080" };
  const CLASSIC = {
    panel: { bevel: BEVEL },
    header: { variant: "classic", barStops: ["#000080", "#1084D0"], controlFace: "#C0C0C0" },
    button: { variant: "classic", height: 30, bevel: BEVEL },
    toggle: { variant: "check", checkBevel: BEVEL },
    field: { bevel: BEVEL },
    progress: { variant: "segments", frame: { fill: "#FFFFFF", pad: 2, bevel: BEVEL } },
  } as StyleOverrides;
  const white = { R: 1, G: 1, B: 1, A: 1 };
  const black = { R: 0, G: 0, B: 0, A: 1 };

  it("turns stops into a vertical or horizontal sRGB gradient", () => {
    expect(stopsToCss([black, white], false)).toBe("linear-gradient(180deg, rgb(0, 0, 0), rgb(255, 255, 255))");
    expect(stopsToCss([black, white], true)).toBe("linear-gradient(90deg, rgb(0, 0, 0), rgb(255, 255, 255))");
    // Linear 0.21586 is sRGB 128 of 255, so a linear colour is converted, not painted as it is.
    expect(stopsToCss([{ R: 0.21586, G: 0.21586, B: 0.21586, A: 1 }, white], false)).toContain("rgb(128, 128, 128)");
  });

  it("draws a raised bevel as light top and left lines and dark bottom and right lines, per ring", () => {
    const bevel = { light: white, dark: black, innerLight: white, innerDark: black, width: 1 };
    const lines = (css: string) => css.split(/, (?=inset)/);
    const raised = bevelToCss(bevel, false);
    expect(count(raised, /inset/g)).toBe(4);
    expect(lines(raised)[0]).toBe("inset 1px 1px 0 0 rgb(255, 255, 255)");
    expect(lines(raised)[1]).toBe("inset -1px -1px 0 0 rgb(0, 0, 0)");
    expect(lines(raised)[2]).toBe("inset 2px 2px 0 0 rgb(255, 255, 255)");
    // Sunken swaps light and dark in both rings.
    expect(lines(bevelToCss(bevel, true))[0]).toBe("inset 1px 1px 0 0 rgb(0, 0, 0)");
    // The inner ring needs both of its colours, and a bevel without light or dark is no bevel.
    expect(count(bevelToCss({ light: white, dark: black, innerLight: white }, false), /inset/g)).toBe(2);
    expect(bevelToCss({ width: 2 }, false)).toBe("none");
  });

  it("draws an xp style with a gradient title bar, 3 caption buttons and a status bar", () => {
    const out = html("slate", XP);
    expect(out).toContain("mm-header-xpbar");
    expect(out).toMatch(/class="mm-band-window mm-band-xpbar" style="background:linear-gradient/);
    expect(count(out, /class="mm-cap /g)).toBe(3);
    expect(out).toContain('class="mm-status"');
    expect(out).toContain("Ready");
  });

  it("draws only the close button when header.captions is close", () => {
    const closeOnly = { ...XP, header: { ...XP_HEADER, captions: "close" } } as StyleOverrides;
    expect(count(html("slate", closeOnly), /class="mm-cap /g)).toBe(1);
  });

  it("gives classic buttons a two-ring bevel and a sunken pressed look", () => {
    const look = buttonLook(previewStyle(resolve("slate", CLASSIC)), { variant: "primary" });
    expect(look.className).toContain("mm-variant-button-classic");
    expect(count(String(look.style.boxShadow), /inset/g)).toBe(4);
    expect(look.style.minHeight).toBe("30px");
    expect(look.style["--mm-btn-pressed-shadow"]).toBeDefined();
    expect(look.style["--mm-btn-pressed-shadow"]).not.toBe(look.style.boxShadow);
    const out = html("slate", CLASSIC);
    expect(out).toContain("mm-header-classic");
    expect(out).toContain("mm-pr-frame");
  });

  it("gives an xp button a face gradient, its edge, and the default ring only on primary", () => {
    const ps = previewStyle(resolve("slate", XP));
    const primary = buttonLook(ps, { variant: "primary" });
    const secondary = buttonLook(ps, { variant: "secondary" });
    expect(String(primary.style.background)).toContain("linear-gradient");
    expect(String(primary.style.boxShadow)).toContain("rgb(140, 180, 240)");
    expect(String(secondary.style.boxShadow)).not.toContain("rgb(140, 180, 240)");
    // Hover drops the default ring and adds the glow, #F8B33A.
    expect(String(primary.style["--mm-btn-hover-shadow"])).toContain("rgb(248, 179, 58)");
    expect(String(primary.style["--mm-btn-hover-shadow"])).not.toContain("rgb(140, 180, 240)");
    expect(String(primary.style["--mm-btn-pressed"])).toContain("linear-gradient");
  });

  it("keeps a pill over a radius and an xp or classic button without its table as a fill", () => {
    const custom = { ...XP, button: { ...XP_BUTTON, radius: 2, pill: true } } as StyleOverrides;
    expect(buttonLook(previewStyle(resolve("slate", custom)), {}).style.borderRadius).toBe("999px");
    const plain = buttonLook(previewStyle(resolve("slate", { button: { variant: "classic" } })), {});
    expect(plain.className).toContain("mm-variant-button-fill");
  });

  it("draws mac-light with 3 traffic lights and no band", () => {
    const out = html("mac-light");
    expect(out).toContain("mm-header-mac");
    expect(count(out, /class="mm-light /g)).toBe(3);
    expect(out).not.toContain("mm-band-window");
  });

  it("draws window captions with a close control", () => {
    const out = html("slate", { header: { variant: "window" } } as StyleOverrides);
    expect(count(out, /class="mm-cap /g)).toBe(3);
    expect(out).toContain("mm-cap-close");
  });

  it("draws the terminal's scanlines, the hologram's sweep and the frost's glints, still", () => {
    expect(html("terminal")).toContain("mm-fx-scan");
    expect(html("terminal")).toContain("mm-cursor");
    const holo = html("hologram");
    expect(holo).toContain("mm-fx-scan");
    expect(holo).toContain("mm-fx-sweep");
    expect(count(html("frost"), /class="mm-fx-sparkle"/g)).toBe(6);
    expect(html("slate")).not.toContain("mm-fx-");
    expect(html("light")).not.toContain("mm-fx-");
  });

  it("draws progress blocks as gradients and frames the trough", () => {
    const out = html("slate", XP);
    expect(out).toMatch(/class="mm-pr-seg"[^>]*linear-gradient/);
    expect(out).toContain("mm-pr-frame");
  });

  it("draws a bevelled check box, field and panel with classic bevels", () => {
    const vars = styleVars(resolve("slate", CLASSIC));
    expect(vars["--mm-toggle-check-bevel"]).toContain("inset");
    expect(vars["--mm-field-bevel"]).toContain("inset");
    expect(vars["--mm-panel-shadow"]).toContain("inset");
  });
});

describe("MenuPreview", () => {
  const doc = fullDocument();

  it("draws light without any themed part", () => {
    const html = renderToStaticMarkup(<MenuPreview document={doc} theme="light" />);
    expect(html).toContain("mm-header-stock");
    expect(html).not.toContain("mm-panel-themed");
    expect(html).not.toContain("mm-btn-shaped");
    expect(html).toContain("mm-variant-toggle-stock");
  });

  it.each(["light", "dark"])("draws %s with the same markup as before stage 2", (id) => {
    // The snapshot was taken before stage 2's preview code, so a change to it shows as a diff here.
    expect(renderToStaticMarkup(<MenuPreview document={doc} theme={id} />)).toMatchSnapshot();
  });

  it.each([...PRESET_ORDER])("draws %s with every item type", (id) => {
    const html = renderToStaticMarkup(<MenuPreview document={doc} theme={id} />);
    expect(html).toContain('aria-label="Menu preview"');
    expect(html).toContain(doc.init.title);
  });

  it("draws the band headers", () => {
    const bar = renderToStaticMarkup(<MenuPreview document={doc} theme="tornado-warning" />);
    expect(bar).toContain("mm-band-bar");
    expect(renderToStaticMarkup(<MenuPreview document={doc} theme="field-kit" />)).toContain("mm-band-tape");
    expect(renderToStaticMarkup(<MenuPreview document={doc} theme="carbon" />)).toContain("mm-band-strip");
  });

  it("lets a toggle style override pick the switch on light", () => {
    const styled = { ...doc, init: { ...doc.init, theme: "light", style: { toggle: "slate" } } };
    const html = renderToStaticMarkup(<MenuPreview document={styled} />);
    expect(html).toContain("mm-variant-toggle-switch");
    expect(html).not.toContain("mm-variant-toggle-stock");
  });

  it("draws light labels red when the body override sets red", () => {
    const styled = { ...doc, init: { ...doc.init, theme: "light", style: { body: { color: "#FF0000" } } } };
    const html = renderToStaticMarkup(<MenuPreview document={styled} />);
    expect(html).toContain("mm-labels-legacy");
    expect(html).toContain("--mm-label-color:rgb(255, 0, 0)");
    // Heading keeps light's legacy textAccent, as the section override sets no colour.
    expect(html).toContain("--mm-label-heading-color:rgb(115, 184, 224)");
    // Muted and warning keep light's textMuted (0.72, 0.76, 0.82) and textStatus (0.83, 0.69, 0.22).
    expect(html).toContain("--mm-label-muted-color:rgb(184, 194, 209)");
    expect(html).toContain("--mm-label-warning-color:rgb(212, 176, 56)");
  });

  it("follows Label.StockSpec for a borrow, a section colour and a hint-only override", () => {
    const html = (style: StyleOverrides) =>
      renderToStaticMarkup(<MenuPreview document={{ ...doc, init: { ...doc.init, theme: "light", style } }} />);
    // A borrow counts as setting every body field: normal labels take the resolved body colour.
    const borrowed = resolve("light", { body: "neon" }).body.color as { R: number; G: number; B: number; A: number };
    const borrowedHtml = html({ body: "neon" });
    expect(borrowedHtml).toContain(`--mm-label-color:${colorCss(borrowed)}`);
    expect(borrowedHtml).toContain("--mm-label-muted-color:rgb(184, 194, 209)");
    // section.color is the heading colour when text names none.
    expect(html({ section: { color: "#00FF00" } })).toContain("--mm-label-heading-color:rgb(0, 255, 0)");
    // A hint-only override moves labels to this path with light's legacy colours (textPrimary 0.95, 0.95, 0.98).
    const hint = html({ hint: { size: 12 } });
    expect(hint).toContain("mm-labels-legacy");
    expect(hint).toContain("--mm-label-color:rgb(242, 242, 250)");
  });

  it("keeps light's labels and title stock without a style", () => {
    const html = renderToStaticMarkup(<MenuPreview document={{ ...doc, init: { ...doc.init, theme: "light", style: undefined } }} />);
    expect(html).not.toContain("mm-labels-legacy");
    expect(html).not.toContain("mm-labels-themed");
    expect(html).not.toContain("mm-title-themed");
    expect(html).not.toContain("--mm-label-color");
  });

  it("themes the stock header's title when the title is overridden", () => {
    const styled = { ...doc, init: { ...doc.init, theme: "dark", style: { title: { color: "#FF0000" } } } };
    const html = renderToStaticMarkup(<MenuPreview document={styled} />);
    expect(html).toContain("mm-header-stock");
    expect(html).toContain("mm-title-themed");
    expect(html).toContain("--mm-title-color:rgb(255, 0, 0)");
  });

  it("outlines a neon confirm card's buttons as ghost buttons", () => {
    const item = { type: "button" as const, id: "wipe", label: "Wipe", confirm: { title: "Sure?" } };
    const html = renderToStaticMarkup(
      <StyleContext.Provider value={previewStyle(resolve("neon"))}>
        <ConfirmCard item={item} onDismiss={() => undefined} />
      </StyleContext.Provider>,
    );
    expect(html).toContain("mm-variant-button-ghost");
    expect(html).toMatch(/box-shadow:inset 0 0 0 \d+px rgb/);
    const light = renderToStaticMarkup(
      <StyleContext.Provider value={previewStyle(resolve("light"))}>
        <ConfirmCard item={item} onDismiss={() => undefined} />
      </StyleContext.Provider>,
    );
    expect(light).not.toContain("box-shadow");
    expect(light).toContain("var(--mm-button-bg-danger)");
  });

  it("reads the document's theme and style when no theme is given", () => {
    const styled = { ...doc, init: { ...doc.init, theme: "slate", style: { toggle: { variant: "check" } } } };
    const html = renderToStaticMarkup(<MenuPreview document={styled} />);
    expect(html).toContain("mm-variant-toggle-check");
  });
});
