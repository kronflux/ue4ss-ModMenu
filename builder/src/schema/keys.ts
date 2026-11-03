/** UE4SS `Key` names (docs.ue4ss.com). Toggle picker omits mouse / IME. Default is F6. */
export const DEFAULT_KEY = "F6";

export type KeyGroup = { label: string; keys: string[] };

export const KEY_GROUPS: KeyGroup[] = [
  {
    label: "Function",
    keys: ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"],
  },
  {
    label: "Letters",
    keys: "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split(""),
  },
  {
    label: "Number row",
    keys: ["ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE"],
  },
  {
    label: "Numpad",
    keys: [
      "NUM_ZERO",
      "NUM_ONE",
      "NUM_TWO",
      "NUM_THREE",
      "NUM_FOUR",
      "NUM_FIVE",
      "NUM_SIX",
      "NUM_SEVEN",
      "NUM_EIGHT",
      "NUM_NINE",
      "MULTIPLY",
      "ADD",
      "SUBTRACT",
      "DECIMAL",
      "DIVIDE",
      "NUM_LOCK",
    ],
  },
  {
    label: "Navigation",
    keys: [
      "ESCAPE",
      "TAB",
      "RETURN",
      "SPACE",
      "BACKSPACE",
      "INS",
      "DEL",
      "HOME",
      "END",
      "PAGE_UP",
      "PAGE_DOWN",
      "LEFT_ARROW",
      "UP_ARROW",
      "RIGHT_ARROW",
      "DOWN_ARROW",
    ],
  },
  {
    label: "Other",
    keys: [
      "PAUSE",
      "CAPS_LOCK",
      "SCROLL_LOCK",
      "PRINT_SCREEN",
      "LEFT_WIN",
      "RIGHT_WIN",
      "APPS",
      "OEM_PLUS",
      "OEM_MINUS",
      "OEM_COMMA",
      "OEM_PERIOD",
    ],
  },
];

export const TOGGLE_KEYS: string[] = KEY_GROUPS.flatMap((group) => group.keys);

export function isToggleKey(name: string): boolean {
  return TOGGLE_KEYS.includes(name);
}

// A keybind item stores Unreal FKey names, which differ from the UE4SS Key names above.
// The FKey for the 1 key is "One", and the arrows are "Up", "Down", "Left" and "Right".
// These lists and parseKeybind match Keybind.MODIFIERS, Keybind.CAPTURE_KEYS and
// Keybind._parse in widgets/keybind.lua.
export const KEYBIND_MODIFIERS: readonly string[] = [
  "LeftControl",
  "RightControl",
  "LeftAlt",
  "RightAlt",
  "LeftShift",
  "RightShift",
];

export const KEYBIND_CAPTURE_KEYS: readonly string[] = [
  ..."ABCDEFGHIJKLMNOPQRSTUVWXYZ".split(""),
  "Zero",
  "One",
  "Two",
  "Three",
  "Four",
  "Five",
  "Six",
  "Seven",
  "Eight",
  "Nine",
  ...Array.from({ length: 12 }, (_, i) => `F${i + 1}`),
  "Up",
  "Down",
  "Left",
  "Right",
  ...KEYBIND_MODIFIERS,
];

export type KeybindParts = { mods: string[]; key: string };

/**
 * Split a binding such as "LeftControl+F7" into its modifiers and its key.
 * Returns null for an empty value, an empty part, a modifier that is not in KEYBIND_MODIFIERS,
 * a repeated modifier, or a binding that ends in a modifier. The key itself is not checked
 * against KEYBIND_CAPTURE_KEYS, because the Lua widget accepts any FKey name a host sets.
 */
export function parseKeybind(value: string): KeybindParts | null {
  if (value === "") {
    return null;
  }
  const parts = value.split("+");
  if (parts.some((part) => part === "")) {
    return null;
  }
  const key = parts.pop() as string;
  if (KEYBIND_MODIFIERS.includes(key)) {
    return null;
  }
  const seen = new Set<string>();
  for (const mod of parts) {
    if (!KEYBIND_MODIFIERS.includes(mod) || seen.has(mod)) {
      return null;
    }
    seen.add(mod);
  }
  return { mods: parts, key };
}
