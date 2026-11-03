import type { SliderItem } from "../schema";

// This rounds half away from zero, as RoundInteger in widgets/slider.lua does, where Math.round would round -2.5 to -2.
function roundInteger(n: number): number {
  return n >= 0 ? Math.floor(n + 0.5) : Math.ceil(n - 0.5);
}

function clamp(n: number, item: SliderItem): number {
  return Math.min(item.max, Math.max(item.min, n));
}

// This follows Snap in widgets/slider.lua: clamp, snap to the step counted from min unless the value
// sits on an end of the range, round an integer item, and clamp again. The twelve significant digits
// match the runtime's "%.12g", so a 0.1 step does not leave 0.30000000000000004.
function snap(n: number, item: SliderItem): number {
  let value = clamp(n, item);
  if (item.step !== undefined && value !== item.min && value !== item.max) {
    value = item.min + roundInteger((value - item.min) / item.step) * item.step;
    value = Number(value.toPrecision(12));
  }
  if (item.integer) {
    value = roundInteger(value);
  }
  return clamp(value, item);
}

// This returns the value the runtime seeds a slider with, as CoerceDefault in widgets/slider.lua does: the default or else min, snapped.
export function sliderValue(item: SliderItem): number {
  return snap(typeof item.default === "number" ? item.default : item.min, item);
}

// Lua's string.format accepts a precision of at most two digits, so a longer one fails there and the runtime shows the default text.
const MAX_PRECISION_DIGITS = 2;

// This mirrors Format in widgets/slider.lua for the formats a document can hold. A format string
// with one %d, %i, %f, %.Nf or %s is applied; any other format shows the default text, because the
// preview cannot run Lua's string.format.
export function sliderText(value: number, item: SliderItem): string {
  if (item.format !== undefined) {
    const match = /%(\.(\d+))?([dfis])/.exec(item.format);
    const precision: string | undefined = match ? match[2] : undefined;
    const precisionOk = precision === undefined || precision.length <= MAX_PRECISION_DIGITS;
    if (match && precisionOk && item.format.replace(/%%/g, "").split("%").length === 2) {
      const [whole, , digits, kind] = match;
      let text: string;
      if (kind === "f") {
        text = value.toFixed(digits !== undefined ? Number(digits) : 6);
      } else if (kind === "s") {
        text = String(value);
      } else {
        text = String(Math.trunc(value));
      }
      return item.format.replace(whole, text).replace(/%%/g, "%");
    }
  }
  if (item.integer) {
    return String(Math.round(value));
  }
  return value.toFixed(6).replace(/\.?0+$/, "");
}
