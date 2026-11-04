export const DOCUMENT_VERSION = 1 as const;

export type ThemeName = "light" | "dark";
export type DockSide = "left" | "right" | "top" | "bottom";

export type ButtonVariant =
  | "default"
  | "primary"
  | "secondary"
  | "success"
  | "danger"
  | "warning"
  | "info"
  | "accent";

export type DropdownOption = string | { label?: string; value?: string };

export type ItemType =
  | "separator"
  | "label"
  | "button"
  | "checkbox"
  | "dropdown"
  | "number"
  | "textinput"
  | "slider"
  | "radio"
  | "keybind"
  | "stepper"
  | "progress"
  | "multiselect"
  | "colorpicker"
  | "row"
  | "fold";

export type ConfirmSpec = {
  title?: string;
  message?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: ButtonVariant;
};

// The registry checks tooltip, enabled and visible on every item type, so every item shape carries them.
// The runtime shows the tooltip 400 ms after the pointer starts hovering the item. A disabled item draws
// dim and ignores input, and a hidden item takes no space but keeps its value.
type ItemCommon = { tooltip?: string; enabled?: boolean; visible?: boolean };

export type LabelAlign = "left" | "center" | "right";
export type LabelStyle = "normal" | "muted" | "heading" | "warning";

export type SeparatorItem = ItemCommon & { type: "separator" };

export type LabelItem = ItemCommon & {
  type: "label";
  id?: string;
  label: string;
  align?: LabelAlign;
  wrap?: boolean;
  style?: LabelStyle;
};

export type ButtonItem = ItemCommon & {
  type: "button";
  id: string;
  label: string;
  variant?: ButtonVariant;
  enabled?: boolean;
  active?: boolean;
  confirm?: ConfirmSpec;
};

export type CheckboxItem = ItemCommon & {
  type: "checkbox";
  id: string;
  label: string;
  default?: boolean;
  showState?: boolean;
};

export type DropdownItem = ItemCommon & {
  type: "dropdown";
  id: string;
  label: string;
  options: DropdownOption[];
  default?: string | null;
  searchable?: boolean;
  placeholder?: string;
  maxVisible?: number;
  listMaxHeight?: number;
  allowEmpty?: boolean;
};

export type NumberItem = ItemCommon & {
  type: "number";
  id: string;
  label: string;
  default?: number;
  min?: number;
  max?: number;
  integer?: boolean;
  placeholder?: string;
  fieldWidth?: number;
  labelWidth?: number;
  debounceMs?: number;
  step?: number;
  prefix?: string;
  suffix?: string;
};

export type TextInputItem = ItemCommon & {
  type: "textinput";
  id: string;
  label: string;
  default?: string;
  placeholder?: string;
  maxLength?: number;
  fieldWidth?: number;
  labelWidth?: number;
  debounceMs?: number;
};

// A slider snaps its value to step counted from min, and rounds it when integer is true.
// The format string goes through Lua's string.format; the document cannot hold a Lua function.
export type SliderItem = ItemCommon & {
  type: "slider";
  id: string;
  label: string;
  min: number;
  max: number;
  default?: number;
  step?: number;
  integer?: boolean;
  format?: string;
  live?: boolean;
  showValue?: boolean;
  labelWidth?: number;
};

// Radio options use the dropdown's option shape, and default must be one of the option values.
export type RadioItem = ItemCommon & {
  type: "radio";
  id: string;
  label: string;
  options: DropdownOption[];
  default?: string;
  inline?: boolean;
};

// A keybind value is an FKey name such as "F7" or "LeftControl+F7", and "" means no binding.
export type KeybindItem = ItemCommon & {
  type: "keybind";
  id: string;
  label: string;
  default?: string;
  allowModifiers?: boolean;
};

// A stepper is a minus button, a readout and a plus button. One click moves the value one step
// (default 1) inside min and max, and holding a button repeats. Without a format the readout uses
// %d for an integer item and %g otherwise. The format goes through Lua's string.format.
export type StepperItem = ItemCommon & {
  type: "stepper";
  id: string;
  label: string;
  min?: number;
  max?: number;
  step?: number;
  default?: number;
  integer?: boolean;
  format?: string;
};

// A progress bar is a label, a bar and a readout. It has no input and no onChange, and the host
// moves it with ModMenu.SetValue, so it is not saved. The range is min 0 to max 1 unless set. Without
// a format the readout shows the percent of the range. The variant picks the fill colour.
export type ProgressItem = ItemCommon & {
  type: "progress";
  id: string;
  label: string;
  min?: number;
  max?: number;
  default?: number;
  format?: string;
  variant?: ButtonVariant;
};

// A multiselect is a caption and one toggle button per option, in 1 to 4 columns (default 1). Options use
// the dropdown's option shape, and default is an array of option values. The value is the array of checked
// values in option order. Its height depends on the option count, so it is allowed in a fold but not in a row.
export type MultiselectItem = ItemCommon & {
  type: "multiselect";
  id: string;
  label: string;
  options: DropdownOption[];
  default?: string[];
  columns?: number;
};

// A colour picker is a caption, a swatch and one slider per channel, each from 0 to 1. The default is a
// colour with all four channels, and the value is a table { R, G, B, A }. Alpha is on unless it is false,
// and then the A slider is hidden and A stays 1. It has several rows, so it is allowed in a fold but not in a row.
export type ColorValue = { R: number; G: number; B: number; A: number };

export type ColorpickerItem = ItemCommon & {
  type: "colorpicker";
  id: string;
  label: string;
  default?: ColorValue;
  alpha?: boolean;
};

export type RowChild =
  | ButtonItem
  | CheckboxItem
  | LabelItem
  | NumberItem
  | ProgressItem
  | SliderItem
  | StepperItem
  | TextInputItem;

export type RowItem = ItemCommon & { type: "row"; items: RowChild[] };

export type FoldChild =
  | ButtonItem
  | CheckboxItem
  | ColorpickerItem
  | DropdownItem
  | KeybindItem
  | LabelItem
  | MultiselectItem
  | NumberItem
  | ProgressItem
  | RadioItem
  | RowItem
  | SeparatorItem
  | SliderItem
  | StepperItem
  | TextInputItem;

export type FoldItem = ItemCommon & {
  type: "fold";
  id: string;
  label: string;
  collapsed?: boolean;
  items: FoldChild[];
};

export type Item =
  | SeparatorItem
  | LabelItem
  | ButtonItem
  | CheckboxItem
  | DropdownItem
  | NumberItem
  | TextInputItem
  | SliderItem
  | RadioItem
  | KeybindItem
  | StepperItem
  | ProgressItem
  | MultiselectItem
  | ColorpickerItem
  | RowItem
  | FoldItem;

export type Section = {
  id: string;
  title?: string;
  tab?: string;
  collapsible?: boolean;
  collapsed?: boolean;
  description?: string;
  prefix?: string;
  items: Item[];
};

// The eight layout tokens milestone A moved out of the shell. A value is a number of zero or more pixels.
export const SPACING_KEYS = [
  "gapItem",
  "gapSection",
  "footerPad",
  "confirmWidth",
  "tabHeight",
  "tabPad",
  "dockPad",
  "panelPad",
] as const;
export type SpacingKey = (typeof SPACING_KEYS)[number];

export type InitSpec = {
  title: string;
  instanceId: string;
  keyHint: string;
  dock: DockSide;
  theme: ThemeName;
  tabs?: string[];
  tooltipDelayMs?: number;
  showClose?: boolean;
  cursorScale?: number;
  spacing?: Partial<Record<SpacingKey, number>>;
};

export type MenuDocument = {
  version: typeof DOCUMENT_VERSION;
  init: InitSpec;
  sections: Section[];
};

export type Issue = {
  path: string;
  message: string;
};

export const ROW_CHILD_TYPES: ReadonlySet<ItemType> = new Set([
  "button",
  "checkbox",
  "label",
  "number",
  "progress",
  "slider",
  "stepper",
  "textinput",
]);

// These two lists match ALLOWED in widgets/row.lua and widgets/fold.lua.
export const FOLD_CHILD_TYPES: ReadonlySet<ItemType> = new Set([
  "button",
  "checkbox",
  "colorpicker",
  "dropdown",
  "keybind",
  "label",
  "multiselect",
  "number",
  "progress",
  "radio",
  "row",
  "separator",
  "slider",
  "stepper",
  "textinput",
]);

export const BUTTON_VARIANTS: ReadonlySet<string> = new Set([
  "default",
  "primary",
  "secondary",
  "success",
  "danger",
  "warning",
  "info",
  "accent",
]);

export const DOCK_SIDES: ReadonlySet<string> = new Set(["left", "right", "top", "bottom"]);
export const THEMES: ReadonlySet<string> = new Set(["light", "dark"]);
export const LABEL_ALIGNS: ReadonlySet<string> = new Set(["left", "center", "right"]);
export const LABEL_STYLES: ReadonlySet<string> = new Set(["normal", "muted", "heading", "warning"]);
export const ITEM_TYPES: ReadonlySet<string> = new Set([
  "separator",
  "label",
  "button",
  "checkbox",
  "dropdown",
  "number",
  "textinput",
  "slider",
  "radio",
  "keybind",
  "stepper",
  "progress",
  "multiselect",
  "colorpicker",
  "row",
  "fold",
]);
