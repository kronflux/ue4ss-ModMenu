import { useState, type ReactNode } from "react";
import type {
  ButtonItem,
  CheckboxItem,
  ColorpickerItem,
  DropdownItem,
  FoldItem,
  Item,
  KeybindItem,
  MultiselectItem,
  NumberItem,
  ProgressItem,
  RadioItem,
  RowItem,
  SliderItem,
  StepperItem,
  TextInputItem,
} from "../schema";
import { buttonChrome } from "./chrome";
import {
  buttonLook,
  choiceLook,
  fieldVariant,
  lookVars,
  progressLook,
  segmentsLit,
  sliderVariant,
  stepperButtonLook,
  textLookStyle,
  toggleVariant,
  usePreviewStyle,
  variantClass,
  type ChoiceLook,
} from "./look";
import { normalizeOptions, optionLabel } from "./options";
import { sliderText, sliderValue } from "./slider";

export type PreviewActions = {
  openDropdown: string | null;
  setOpenDropdown: (key: string | null) => void;
  foldCollapsed: Record<string, boolean>;
  toggleFold: (key: string) => void;
  checks: Record<string, boolean>;
  toggleCheck: (key: string) => void;
  onConfirm: (item: ButtonItem) => void;
};

function itemKey(sectionId: string, id: string | undefined, fallback: string): string {
  return `${sectionId}.${id ?? fallback}`;
}

function MmButton({
  item,
  fill,
  onClick,
}: {
  item: ButtonItem;
  fill?: boolean;
  onClick?: () => void;
}) {
  const look = buttonLook(usePreviewStyle(), item);
  return (
    <button
      type="button"
      className={`mm-btn${fill === false ? " mm-btn-inline" : ""} ${look.className}`}
      style={look.style}
      disabled={item.enabled === false}
      onClick={onClick}
    >
      {item.label}
    </button>
  );
}

// The themed toggle shapes, as widgets/checkbox.lua builds them: a switch or square track with a knob,
// a check box with a mark, or an On and Off chip.
function ToggleControl({ variant, on }: { variant: string; on: boolean }) {
  if (variant === "check") {
    return <span className={`mm-tg-check${on ? " is-on" : ""}`}>{on ? "✓" : ""}</span>;
  }
  if (variant === "text") {
    return <span className={`mm-tg-text${on ? " is-on" : ""}`}>{on ? "On" : "Off"}</span>;
  }
  return (
    <span className={`mm-tg-switch${on ? " is-on" : ""}`}>
      <span className="mm-tg-knob" />
    </span>
  );
}

function MmCheckbox({
  item,
  valueKey,
  actions,
}: {
  item: CheckboxItem;
  valueKey: string;
  actions: PreviewActions;
}) {
  const ps = usePreviewStyle();
  const on = actions.checks[valueKey] ?? item.default === true;
  const variant = toggleVariant(ps, item.look);
  if (variant !== "stock") {
    // The control shows the state, so the caption is the label alone, without ": ON" or ": OFF".
    return (
      <button
        type="button"
        role="switch"
        aria-checked={on}
        className={`mm-toggle ${variantClass("toggle", variant)}`}
        style={lookVars(ps, "toggle", item.look)}
        onClick={() => {
          actions.toggleCheck(valueKey);
        }}
      >
        <span className="mm-toggle-label">{item.label}</span>
        <ToggleControl variant={variant} on={on} />
      </button>
    );
  }
  return (
    <label className={`mm-check ${variantClass("toggle", "stock")}`}>
      <input
        type="checkbox"
        checked={on}
        onChange={() => {
          actions.toggleCheck(valueKey);
        }}
      />
      <span>{item.showState === false ? item.label : `${item.label}: ${on ? "ON" : "OFF"}`}</span>
    </label>
  );
}

function MmField({
  label,
  labelWidth,
  fieldWidth,
  fill,
  look,
  children,
}: {
  label: string;
  labelWidth?: number;
  fieldWidth?: number;
  fill?: boolean;
  look?: Record<string, unknown>;
  children: ReactNode;
}) {
  const ps = usePreviewStyle();
  return (
    <div
      className={`mm-field${fill ? " mm-field-fill" : ""} ${variantClass("field", fieldVariant(ps, look))}`}
      style={lookVars(ps, "field", look)}
    >
      <span className="mm-field-label" style={labelWidth ? { width: labelWidth, flex: "0 0 auto" } : undefined}>
        {label}
      </span>
      <span className="mm-field-box" style={fieldWidth ? { width: fieldWidth, flex: "0 0 auto" } : undefined}>
        {children}
      </span>
    </div>
  );
}

// The prefix and suffix sit inside the field, as the runtime draws them. The step buttons follow the field.
function MmNumber({ item, fill }: { item: NumberItem; fill?: boolean }) {
  const step = buttonLook(usePreviewStyle(), {});
  const width = item.fieldWidth ?? (fill === false ? 72 : 96);
  return (
    <div className="mm-number">
      <MmField label={item.label} labelWidth={item.labelWidth} fieldWidth={width} fill={fill !== false} look={item.look}>
        {item.prefix && <span className="mm-note">{item.prefix}</span>}
        <input
          className="mm-edit"
          type="text"
          defaultValue={item.default ?? 0}
          placeholder={item.placeholder}
          readOnly
        />
        {item.suffix && <span className="mm-note">{item.suffix}</span>}
      </MmField>
      {item.step !== undefined && (
        <>
          <button type="button" className={`mm-btn mm-btn-inline mm-step ${step.className}`} style={step.style}>
            -
          </button>
          <button type="button" className={`mm-btn mm-btn-inline mm-step ${step.className}`} style={step.style}>
            +
          </button>
        </>
      )}
    </div>
  );
}

function MmText({ item, fill }: { item: TextInputItem; fill?: boolean }) {
  const width = item.fieldWidth ?? (fill === false ? 72 : undefined);
  return (
    <MmField label={item.label} labelWidth={item.labelWidth} fieldWidth={width} fill={fill !== false} look={item.look}>
      <input className="mm-edit" type="text" defaultValue={item.default ?? ""} placeholder={item.placeholder} readOnly />
    </MmField>
  );
}

function MmDropdown({
  item,
  dropKey,
  actions,
}: {
  item: DropdownItem;
  dropKey: string;
  actions: PreviewActions;
}) {
  const ps = usePreviewStyle();
  const [filter, setFilter] = useState("");
  const open = actions.openDropdown === dropKey;
  const list = normalizeOptions(item.options);
  const placeholder = item.placeholder ?? "Select...";
  const selected = optionLabel(item.options, item.default, placeholder);
  const maxVisible = item.maxVisible ?? (item.searchable ? 400 : list.length);
  const matched = list.filter((opt) => opt.label.toLowerCase().includes(filter.toLowerCase()));
  const shown = matched.slice(0, maxVisible);
  const extra = matched.length - shown.length;

  return (
    <div className={`mm-drop ${variantClass("field", fieldVariant(ps, item.look))}`} style={lookVars(ps, "field", item.look)}>
      <button
        type="button"
        className="mm-drop-header"
        onClick={() => {
          actions.setOpenDropdown(open ? null : dropKey);
          setFilter("");
        }}
      >
        <span>{selected}</span>
        <span className="mm-drop-arrow">{open ? "▲" : "▼"}</span>
      </button>
      {open && (
        <div className="mm-drop-list" style={item.listMaxHeight ? { maxHeight: item.listMaxHeight } : undefined}>
          {item.searchable && (
            <input
              className="mm-drop-search"
              type="text"
              value={filter}
              placeholder="Type to filter..."
              onChange={(event) => {
                setFilter(event.target.value);
              }}
            />
          )}
          {shown.map((opt) => (
            <div
              key={opt.value}
              className={`mm-drop-opt${opt.value === item.default ? " is-selected" : ""}`}
            >
              {opt.label}
            </div>
          ))}
          {extra > 0 && <div className="mm-drop-more">…{extra} more — type to narrow</div>}
          {matched.length === 0 && <div className="mm-drop-more">No matches</div>}
        </div>
      )}
    </div>
  );
}

// A themed slider rail, as widgets/slider.lua styles the engine slider: a rounded track of the
// slider's thickness and a round, square or bar thumb at the value. A tint fills the track up to the
// thumb, as the colour picker's channels show their colour.
function SliderRail({ fraction, tint }: { fraction: number; tint?: string }) {
  const at = `${Math.min(1, Math.max(0, fraction)) * 100}%`;
  return (
    <div className="mm-sl-rail">
      <div className="mm-sl-track">
        {tint !== undefined && <span className="mm-sl-tint" style={{ width: at, background: tint }} />}
        <span className="mm-sl-thumb" style={{ left: at }} />
      </div>
    </div>
  );
}

function MmSlider({ item, fill }: { item: SliderItem; fill?: boolean }) {
  const ps = usePreviewStyle();
  const variant = sliderVariant(ps, item.look);
  const span = item.max - item.min;
  const value = sliderValue(item);
  const fraction = span > 0 ? (value - item.min) / span : 0;
  if (variant !== "stock") {
    return (
      <div
        className={`mm-slider${fill === false ? " mm-slider-inline" : ""} ${variantClass("slider", variant)}`}
        style={lookVars(ps, "slider", item.look)}
      >
        <div className="mm-slider-head">
          <span className="mm-slider-label" style={item.labelWidth ? { width: item.labelWidth, flex: "0 0 auto" } : undefined}>
            {item.label}
          </span>
          {item.showValue !== false && <span className="mm-slider-value">{sliderText(value, item)}</span>}
        </div>
        <SliderRail fraction={fraction} />
      </div>
    );
  }
  return (
    <div className={`mm-slider${fill === false ? " mm-slider-inline" : ""} ${variantClass("slider", "stock")}`}>
      <div className="mm-slider-head">
        <span className="mm-slider-label" style={item.labelWidth ? { width: item.labelWidth, flex: "0 0 auto" } : undefined}>
          {item.label}
        </span>
        {item.showValue !== false && <span className="mm-slider-value">{sliderText(value, item)}</span>}
      </div>
      <div className="mm-slider-track">
        <span className="mm-slider-fill" style={{ flexGrow: fraction }} />
        <span className="mm-slider-knob" />
        <span className="mm-slider-rest" style={{ flexGrow: 1 - fraction }} />
      </div>
    </div>
  );
}

// The readout shows the value the runtime seeds a stepper with: the default or else min or zero, kept inside the range.
// The text goes through the slider's formatter, which handles the same format strings and the same fallback.
function MmStepper({ item }: { item: StepperItem }) {
  const low = item.min ?? Number.NEGATIVE_INFINITY;
  const high = item.max ?? Number.POSITIVE_INFINITY;
  const value = Math.min(high, Math.max(low, item.default ?? item.min ?? 0));
  const shaped = { ...item, min: item.min ?? 0, max: item.max ?? 0 } as unknown as SliderItem;
  // The minus and plus buttons take the stepper's role, radius and pill over the button style, as
  // widgets/stepper.lua does. A flat look keeps today's plain spans.
  const ps = usePreviewStyle();
  const btn = stepperButtonLook(ps, item.look);
  const flat = btn.flat;
  const btnClass = flat ? "mm-stepper-btn" : `mm-stepper-btn ${btn.className}`;
  const btnStyle = flat ? undefined : btn.style;
  return (
    <div className={`mm-stepper${flat ? "" : " mm-stepper-themed"}`}>
      <span className="mm-stepper-label">{item.label}</span>
      <span className={btnClass} style={btnStyle}>
        -
      </span>
      <span className="mm-stepper-readout">{sliderText(value, shaped)}</span>
      <span className={btnClass} style={btnStyle}>
        +
      </span>
    </div>
  );
}

// The bar shows the value the runtime seeds a progress item with: the default or else min, kept inside the range.
// Without a format the readout is the percent of the range. A format goes through the slider's formatter, which
// shows the plain number for a format string it cannot apply, where the runtime would fall back to the percent.
function MmProgress({ item }: { item: ProgressItem }) {
  const low = item.min ?? 0;
  const high = item.max ?? 1;
  const value = Math.min(high, Math.max(low, item.default ?? low));
  const span = high - low;
  const fraction = span > 0 ? (value - low) / span : 0;
  const text =
    item.format !== undefined
      ? sliderText(value, { ...item, min: low, max: high } as unknown as SliderItem)
      : `${Math.round(fraction * 100)}%`;
  const ps = usePreviewStyle();
  const pr = progressLook(ps, item);
  if (pr.variant === "bar" || pr.variant === "segments") {
    const n = pr.segmentColors.length;
    const lit = segmentsLit(value, low, high, n);
    const trough =
      pr.variant === "bar" ? (
        <span className="mm-pr-bar">
          <span className="mm-pr-fill" style={{ width: `${fraction * 100}%`, background: pr.fill }} />
        </span>
      ) : (
        <span className="mm-pr-segments">
          {pr.segmentColors.map((color, i) => (
            <span key={i} className="mm-pr-seg" style={i < lit ? { background: pr.block ?? color } : undefined} />
          ))}
        </span>
      );
    return (
      <div className={`mm-progress ${variantClass("progress", pr.variant)}`} style={lookVars(ps, "progress", item.look)}>
        <span className="mm-progress-label">{item.label}</span>
        {pr.frame ? (
          <span className={`mm-pr-frame mm-pr-frame-${pr.frame.kind}`} style={pr.frame.style}>
            {trough}
          </span>
        ) : (
          trough
        )}
        <span className="mm-progress-readout">{text}</span>
      </div>
    );
  }
  // The default variant and an unset one use the accent, as the runtime does.
  const fill = item.variant && item.variant !== "default" ? buttonChrome({ variant: item.variant }).background : undefined;
  return (
    <div className={`mm-progress ${variantClass("progress", "stock")}`}>
      <span className="mm-progress-label">{item.label}</span>
      <span className="mm-progress-bar">
        <span className="mm-progress-fill" style={{ width: `${fraction * 100}%`, background: fill }} />
      </span>
      <span className="mm-progress-readout">{text}</span>
    </div>
  );
}

export type ChoiceOption = { key: string; label: string; on: boolean; onClick?: () => void };

/**
 * A themed choice strip: radio and multiselect options in the choice style, and the shell's tabs in
 * the tabs style. Joined options sit in one frame, chips are outlined shapes, tabs underline the
 * chosen option, and radio draws a ring with a dot. columns lays the options out in a grid.
 */
export function ChoiceStrip({
  look,
  options,
  columns,
  stacked,
}: {
  look: ChoiceLook;
  options: ChoiceOption[];
  columns?: number;
  stacked?: boolean;
}) {
  const layout = columns !== undefined && columns > 1 ? { gridTemplateColumns: `repeat(${columns}, 1fr)` } : undefined;
  return (
    <div
      className={`mm-choice mm-choice-${look.variant}${stacked ? " mm-choice-stacked" : ""}${layout ? " mm-choice-grid" : ""}`}
      style={{ ...look.style, ...layout }}
    >
      {options.map((opt) => (
        <button
          key={opt.key}
          type="button"
          className={`mm-choice-opt${opt.on ? " is-on" : ""}`}
          style={{ color: opt.on ? look.textOn : look.textOff }}
          aria-pressed={opt.on}
          onClick={opt.onClick}
        >
          {look.variant === "radio" && <span className="mm-choice-ring" />}
          <span className="mm-choice-text">{opt.label}</span>
        </button>
      ))}
    </div>
  );
}

function MmRadio({ item, inline }: { item: RadioItem; inline: boolean }) {
  const ps = usePreviewStyle();
  const list = normalizeOptions(item.options);
  const chosen = item.default ?? null;
  const look = choiceLook(ps, "choice", item.look);
  if (look.variant !== "stock") {
    return (
      <div className={`mm-radio ${variantClass("choice", look.variant)}`}>
        <span className="mm-radio-label">{item.label}</span>
        <ChoiceStrip
          look={look}
          stacked={look.variant === "radio" && !inline}
          options={list.map((opt) => ({ key: opt.value, label: opt.label, on: opt.value === chosen }))}
        />
      </div>
    );
  }
  return (
    <div className={`mm-radio ${variantClass("choice", "stock")}`}>
      <span className="mm-radio-label">{item.label}</span>
      <div className={`mm-radio-group${inline ? " mm-radio-inline" : ""}`}>
        {list.map((opt) => (
          <button
            key={opt.value}
            type="button"
            className={`mm-btn${inline ? " mm-btn-inline" : ""}`}
            style={buttonChrome({ active: opt.value === chosen })}
          >
            {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}

// The runtime draws one button per option in a uniform grid, with "[x] " or "[ ] " before the label and
// the checked options painted active, as Multiselect._caption in widgets/multiselect.lua does.
function MmMultiselect({ item }: { item: MultiselectItem }) {
  const ps = usePreviewStyle();
  const list = normalizeOptions(item.options);
  const checked = item.default ?? [];
  const look = choiceLook(ps, "choice", item.look);
  if (look.variant !== "stock") {
    // Several marks can be on at once; the options keep the item's column count.
    return (
      <div className={`mm-multi ${variantClass("choice", look.variant)}`}>
        <span className="mm-multi-label">{item.label}</span>
        <ChoiceStrip
          look={look}
          columns={item.columns ?? 1}
          options={list.map((opt) => ({ key: opt.value, label: opt.label, on: checked.includes(opt.value) }))}
        />
      </div>
    );
  }
  return (
    <div className={`mm-multi ${variantClass("choice", "stock")}`}>
      <span className="mm-multi-label">{item.label}</span>
      <div className="mm-multi-grid" style={{ gridTemplateColumns: `repeat(${item.columns ?? 1}, 1fr)` }}>
        {list.map((opt) => {
          const on = checked.includes(opt.value);
          return (
            <button key={opt.value} type="button" className="mm-btn" style={buttonChrome({ active: on })}>
              {on ? "[x] " : "[ ] "}
              {opt.label}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// The runtime draws a caption, a swatch and one slider per channel, each with its number to two decimals.
// A missing default is opaque white, and alpha false hides the A slider, as widgets/colorpicker.lua does.
const COLOR_TINTS: Record<string, string> = { R: "#e64040", G: "#4dcc4d", B: "#4d80ff" };

function MmColorpicker({ item }: { item: ColorpickerItem }) {
  const ps = usePreviewStyle();
  const variant = sliderVariant(ps, item.look);
  const color = item.default ?? { R: 1, G: 1, B: 1, A: 1 };
  const keys = item.alpha === false ? (["R", "G", "B"] as const) : (["R", "G", "B", "A"] as const);
  const alpha = item.alpha === false ? 1 : color.A;
  const channel = (key: "R" | "G" | "B" | "A") => Math.min(1, Math.max(0, key === "A" ? alpha : color[key]));
  const swatch = `rgba(${Math.round(channel("R") * 255)}, ${Math.round(channel("G") * 255)}, ${Math.round(channel("B") * 255)}, ${channel("A")})`;
  // A themed picker reuses the themed slider for each channel, as widgets/colorpicker.lua does.
  if (variant !== "stock") {
    return (
      <div className={`mm-color ${variantClass("slider", variant)}`} style={lookVars(ps, "slider", item.look)}>
        <span className="mm-color-label">{item.label}</span>
        <div className="mm-color-swatch" style={{ background: swatch }} />
        {keys.map((key) => {
          const value = channel(key);
          return (
            <div key={key} className="mm-color-row">
              <span className="mm-color-key">{key}</span>
              <div className="mm-color-track">
                <SliderRail fraction={value} tint={COLOR_TINTS[key]} />
              </div>
              <span className="mm-color-value">{value.toFixed(2)}</span>
            </div>
          );
        })}
      </div>
    );
  }
  return (
    <div className={`mm-color ${variantClass("slider", "stock")}`}>
      <span className="mm-color-label">{item.label}</span>
      <div className="mm-color-swatch" style={{ background: swatch }} />
      {keys.map((key) => {
        const value = channel(key);
        return (
          <div key={key} className="mm-color-row">
            <span className="mm-color-key">{key}</span>
            <div className="mm-slider-track mm-color-track">
              <span className="mm-slider-fill" style={{ flexGrow: value, background: COLOR_TINTS[key] }} />
              <span className="mm-slider-knob" />
              <span className="mm-slider-rest" style={{ flexGrow: 1 - value }} />
            </div>
            <span className="mm-color-value">{value.toFixed(2)}</span>
          </div>
        );
      })}
    </div>
  );
}

// The runtime button reads "Label: F7", or "Label: None" without a binding, as Caption in widgets/keybind.lua writes it.
function MmKeybind({ item }: { item: KeybindItem }) {
  const ps = usePreviewStyle();
  const bound = item.default !== undefined && item.default !== "";
  const btn = buttonLook(ps, {});
  // The key chip takes the field style when the field variant is frame.
  return (
    <button
      type="button"
      className={`mm-btn mm-keybind ${btn.className} ${variantClass("field", fieldVariant(ps, item.look))}`}
      style={{ ...btn.style, ...lookVars(ps, "field", item.look) }}
    >
      {item.label}: <span className={`mm-key-chip${bound ? "" : " is-unbound"}`}>{bound ? item.default : "None"}</span>
    </button>
  );
}

function MmFold({
  item,
  sectionId,
  actions,
}: {
  item: FoldItem;
  sectionId: string;
  actions: PreviewActions;
}) {
  const key = `${sectionId}.${item.id}`;
  const collapsed = actions.foldCollapsed[key] ?? item.collapsed !== false;
  return (
    <div className="mm-fold">
      <button
        type="button"
        className="mm-accordion"
        onClick={() => {
          actions.toggleFold(key);
        }}
      >
        <span>{item.label}</span>
        <span className="mm-mark">{collapsed ? "+" : "-"}</span>
      </button>
      {!collapsed && (
        <div className="mm-fold-body">
          {item.items.map((child, index) => (
            <PreviewItem
              key={`${child.type}-${"id" in child ? child.id : index}`}
              item={child}
              sectionId={sectionId}
              actions={actions}
              index={index}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function MmRow({
  item,
  sectionId,
  actions,
}: {
  item: RowItem;
  sectionId: string;
  actions: PreviewActions;
}) {
  return (
    <div className="mm-row">
      {item.items.map((child, index) => (
        <PreviewItem
          key={`${child.type}-${"id" in child ? child.id : index}`}
          item={child}
          sectionId={sectionId}
          actions={actions}
          index={index}
          layout="horizontal"
        />
      ))}
    </div>
  );
}

type PreviewItemProps = {
  item: Item;
  sectionId: string;
  actions: PreviewActions;
  index: number;
  layout?: "vertical" | "horizontal";
};

// A tooltip shows as the browser's own title text. The wrapper uses display: contents, so it adds
// no box and the row and fold layouts stay as they are without a tooltip.
// A hidden item draws nothing. A disabled item draws dim and takes no pointer input. The runtime passes both
// flags from a row or fold to its children, and here a hidden parent drops its children and a disabled parent
// dims them through the CSS of its own wrapper.
export function PreviewItem(props: PreviewItemProps) {
  if (props.item.visible === false) {
    return null;
  }
  let body: ReactNode = <PreviewItemBody {...props} />;
  const tooltip = props.item.tooltip;
  if (tooltip !== undefined && tooltip !== "") {
    body = (
      <span className="mm-tip" title={tooltip}>
        {body}
      </span>
    );
  }
  if (props.item.enabled === false) {
    body = <div className="mm-disabled">{body}</div>;
  }
  return body;
}

function PreviewItemBody({ item, sectionId, actions, index, layout = "vertical" }: PreviewItemProps) {
  const ps = usePreviewStyle();
  const horizontal = layout === "horizontal";
  if (item.type === "separator") {
    return <div className="mm-sep" />;
  }
  if (item.type === "label") {
    if (item.label.trim() === "") {
      return null;
    }
    return (
      <p
        className={`mm-label${item.style && item.style !== "normal" ? ` mm-label-${item.style}` : ""}`}
        style={{
          ...textLookStyle(ps, "body", item.look),
          textAlign: item.align,
          whiteSpace: item.wrap === false || horizontal ? "nowrap" : undefined,
        }}
      >
        {item.label}
      </p>
    );
  }
  if (item.type === "button") {
    return (
      <MmButton
        item={item}
        fill={!horizontal}
        onClick={() => {
          if (item.confirm) {
            actions.onConfirm(item);
          }
        }}
      />
    );
  }
  if (item.type === "checkbox") {
    return <MmCheckbox item={item} valueKey={itemKey(sectionId, item.id, String(index))} actions={actions} />;
  }
  if (item.type === "number") {
    return <MmNumber item={item} fill={!horizontal} />;
  }
  if (item.type === "textinput") {
    return <MmText item={item} fill={!horizontal} />;
  }
  if (item.type === "dropdown") {
    return <MmDropdown item={item} dropKey={itemKey(sectionId, item.id, String(index))} actions={actions} />;
  }
  if (item.type === "slider") {
    return <MmSlider item={item} fill={!horizontal} />;
  }
  if (item.type === "stepper") {
    return <MmStepper item={item} />;
  }
  if (item.type === "progress") {
    return <MmProgress item={item} />;
  }
  if (item.type === "radio") {
    return <MmRadio item={item} inline={item.inline === true} />;
  }
  if (item.type === "multiselect") {
    return <MmMultiselect item={item} />;
  }
  if (item.type === "colorpicker") {
    return <MmColorpicker item={item} />;
  }
  if (item.type === "keybind") {
    return <MmKeybind item={item} />;
  }
  if (item.type === "row") {
    return <MmRow item={item} sectionId={sectionId} actions={actions} />;
  }
  if (item.type === "fold") {
    return <MmFold item={item} sectionId={sectionId} actions={actions} />;
  }
  return null;
}
