import { describe, expect, it } from "vitest";
import type { SliderItem } from "../schema";
import { sliderText, sliderValue } from "./slider";

function slider(fields: Partial<SliderItem>): SliderItem {
  return { type: "slider", id: "s", label: "S", min: 0, max: 10, ...fields };
}

// These cases follow Snap and CoerceDefault in widgets/slider.lua, which the runtime applies when it seeds a slider.
describe("sliderValue", () => {
  it("snaps the default to the step counted from min", () => {
    expect(sliderValue(slider({ min: 1, max: 9, step: 2, default: 2.2 }))).toBe(3);
  });

  it("keeps max when the range is not a whole number of steps", () => {
    expect(sliderValue(slider({ min: 0, max: 10, step: 3, default: 10 }))).toBe(10);
  });

  it("snaps a tenth step without float residue", () => {
    expect(sliderValue(slider({ min: 0, max: 1, step: 0.1, default: 0.3 }))).toBe(0.3);
  });

  it("rounds an integer item half away from zero", () => {
    expect(sliderValue(slider({ min: -10, max: 10, integer: true, default: -2.5 }))).toBe(-3);
    expect(sliderValue(slider({ min: -10, max: 10, integer: true, default: 2.5 }))).toBe(3);
  });

  it("clamps the default and falls back to min without one", () => {
    expect(sliderValue(slider({ min: 0, max: 10, default: 12 }))).toBe(10);
    expect(sliderValue(slider({ min: 2, max: 10 }))).toBe(2);
  });
});

describe("sliderText", () => {
  it("applies a %.Nf format", () => {
    expect(sliderText(3, slider({ format: "%.2f x" }))).toBe("3.00 x");
  });

  // Lua's string.format rejects a precision of three digits, so the runtime shows the default text too.
  it("shows the default text for a precision that string.format rejects", () => {
    expect(sliderText(3, slider({ format: "%.101f" }))).toBe("3");
    expect(sliderText(3, slider({ format: "%.100f" }))).toBe("3");
    expect(sliderText(3, slider({ format: "%.099f" }))).toBe("3");
  });

  it("applies a two digit precision", () => {
    expect(sliderText(3, slider({ format: "%.12f" }))).toBe("3.000000000000");
  });
});
