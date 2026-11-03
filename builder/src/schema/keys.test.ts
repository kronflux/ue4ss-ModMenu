import { describe, expect, it } from "vitest";
import { DEFAULT_KEY, KEYBIND_CAPTURE_KEYS, TOGGLE_KEYS, isToggleKey, parseKeybind } from "./keys";

// These cases are the ones tooling/lua/widgets_keybind_spec.lua runs against Keybind._parse.
describe("keybind values", () => {
  it("splits modifiers from the key", () => {
    expect(parseKeybind("LeftControl+F7")).toEqual({ mods: ["LeftControl"], key: "F7" });
    expect(parseKeybind("F7")).toEqual({ mods: [], key: "F7" });
  });

  it("rejects an empty part, an unknown or repeated modifier, and a trailing modifier", () => {
    expect(parseKeybind("")).toBeNull();
    expect(parseKeybind("LeftControl++F7")).toBeNull();
    expect(parseKeybind("Hyper+F7")).toBeNull();
    expect(parseKeybind("LeftAlt+LeftAlt+F7")).toBeNull();
    expect(parseKeybind("F7+LeftShift")).toBeNull();
  });

  it("scans the same FKey names as the Lua widget", () => {
    expect(KEYBIND_CAPTURE_KEYS).toHaveLength(26 + 10 + 12 + 4 + 6);
    expect(KEYBIND_CAPTURE_KEYS).toContain("One");
    expect(KEYBIND_CAPTURE_KEYS).toContain("RightShift");
  });
});

describe("toggle keys", () => {
  it("defaults to F6 and lists UE4SS function keys", () => {
    expect(DEFAULT_KEY).toBe("F6");
    expect(isToggleKey("F6")).toBe(true);
    expect(isToggleKey("F8")).toBe(true);
    expect(TOGGLE_KEYS).toContain("F12");
    expect(isToggleKey("LEFT_MOUSE_BUTTON")).toBe(false);
  });
});
