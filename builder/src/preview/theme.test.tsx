import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import type { StyleOverrides } from "../schema";
import { fullDocument } from "../schema/fullFixture";
import { colorCss, fontFamily, linearToSrgb, styleVars, themeVars } from "../theme/css";
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

describe("MenuPreview", () => {
  const doc = fullDocument();

  it("draws light without any themed part", () => {
    const html = renderToStaticMarkup(<MenuPreview document={doc} theme="light" />);
    expect(html).toContain("mm-header-stock");
    expect(html).not.toContain("mm-panel-themed");
    expect(html).not.toContain("mm-btn-shaped");
    expect(html).toContain("mm-variant-toggle-stock");
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
