import { describe, expect, it } from "vitest";
import { BUTTON_STATE_KEYS, DARK, LIGHT, THEME_KEYS, buttonStates, shade } from "./tokens";
import { colorCss, themeVars } from "./css";

describe("theme tokens", () => {
  it("light and dark define every Lua key", () => {
    for (const key of THEME_KEYS) {
      expect(LIGHT[key], key).toBeDefined();
      expect(DARK[key], key).toBeDefined();
    }
  });

  // These cases are the ones tooling/lua/theme_spec.lua runs against Theme.Shade and Theme.ButtonStates.
  it("shades toward white and black and clamps", () => {
    const grey = { R: 0.5, G: 0.5, B: 0.5, A: 1 };
    const light = shade(grey, 0.12);
    expect(light.R).toBeCloseTo(0.56);
    expect(light.A).toBe(1);
    expect(shade({ R: 1, G: 1, B: 1, A: 1 }, 0.5).R).toBe(1);
    expect(shade({ R: 0, G: 0, B: 0, A: 1 }, -0.5).R).toBe(0);
  });

  it("derives button states from the fill unless a state colour is set", () => {
    expect(buttonStates(DARK, "primary").hover).toEqual(shade(DARK.buttonBgPrimary, 0.12));
    expect(buttonStates(DARK, "primary").pressed).toEqual(shade(DARK.buttonBgPrimary, -0.12));
    const explicit = { R: 0.1, G: 0.2, B: 0.3, A: 1 };
    expect(buttonStates({ ...DARK, buttonPrimaryHover: explicit }, "primary").hover).toEqual(explicit);
    expect(BUTTON_STATE_KEYS).toHaveLength(14);
    expect(themeVars("dark")["--mm-button-primary-hover"]).toBe(colorCss(shade(DARK.buttonBgPrimary, 0.12)));
    expect(themeVars("light")["--mm-button-pressed"]).toBe(colorCss(shade(LIGHT.buttonBg, -0.12)));
  });

  it("emits CSS vars for each token", () => {
    const vars = themeVars("dark");
    expect(vars["--mm-panel-bg"]).toBe(colorCss(DARK.panelBg));
    expect(vars["--mm-button-bg-danger"]).toBe(colorCss(DARK.buttonBgDanger));
    expect(vars["--mm-pad-left"]).toBe("16px");
  });
});
