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
  | "row"
  | "fold";

export type ConfirmSpec = {
  title?: string;
  message?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: ButtonVariant;
};

// The registry checks tooltip on every item type, so every item shape carries it.
// The runtime shows the text 400 ms after the pointer starts hovering the item.
type WithTooltip = { tooltip?: string };

export type SeparatorItem = WithTooltip & { type: "separator" };

export type LabelItem = WithTooltip & { type: "label"; id?: string; label: string };

export type ButtonItem = WithTooltip & {
  type: "button";
  id: string;
  label: string;
  variant?: ButtonVariant;
  enabled?: boolean;
  active?: boolean;
  confirm?: ConfirmSpec;
};

export type CheckboxItem = WithTooltip & {
  type: "checkbox";
  id: string;
  label: string;
  default?: boolean;
};

export type DropdownItem = WithTooltip & {
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

export type NumberItem = WithTooltip & {
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
};

export type TextInputItem = WithTooltip & {
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
export type SliderItem = WithTooltip & {
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
};

// Radio options use the dropdown's option shape, and default must be one of the option values.
export type RadioItem = WithTooltip & {
  type: "radio";
  id: string;
  label: string;
  options: DropdownOption[];
  default?: string;
  inline?: boolean;
};

// A keybind value is an FKey name such as "F7" or "LeftControl+F7", and "" means no binding.
export type KeybindItem = WithTooltip & {
  type: "keybind";
  id: string;
  label: string;
  default?: string;
  allowModifiers?: boolean;
};

export type RowChild = ButtonItem | CheckboxItem | LabelItem | NumberItem | SliderItem | TextInputItem;

export type RowItem = WithTooltip & { type: "row"; items: RowChild[] };

export type FoldChild =
  | ButtonItem
  | CheckboxItem
  | DropdownItem
  | KeybindItem
  | LabelItem
  | NumberItem
  | RadioItem
  | RowItem
  | SeparatorItem
  | SliderItem
  | TextInputItem;

export type FoldItem = WithTooltip & {
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
  | RowItem
  | FoldItem;

export type Section = {
  id: string;
  title?: string;
  tab?: string;
  collapsible?: boolean;
  collapsed?: boolean;
  items: Item[];
};

export type InitSpec = {
  title: string;
  instanceId: string;
  keyHint: string;
  dock: DockSide;
  theme: ThemeName;
  tabs?: string[];
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
  "slider",
  "textinput",
]);

// These two lists match ALLOWED in widgets/row.lua and widgets/fold.lua.
export const FOLD_CHILD_TYPES: ReadonlySet<ItemType> = new Set([
  "button",
  "checkbox",
  "dropdown",
  "keybind",
  "label",
  "number",
  "radio",
  "row",
  "separator",
  "slider",
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
  "row",
  "fold",
]);
