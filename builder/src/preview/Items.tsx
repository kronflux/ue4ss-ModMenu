import { useState, type ReactNode } from "react";
import type {
  ButtonItem,
  CheckboxItem,
  DropdownItem,
  FoldItem,
  Item,
  KeybindItem,
  NumberItem,
  ProgressItem,
  RadioItem,
  RowItem,
  SliderItem,
  StepperItem,
  TextInputItem,
} from "../schema";
import { buttonChrome } from "./chrome";
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
  const chrome = buttonChrome(item);
  return (
    <button
      type="button"
      className={`mm-btn${fill === false ? " mm-btn-inline" : ""}`}
      style={chrome}
      disabled={item.enabled === false}
      onClick={onClick}
    >
      {item.label}
    </button>
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
  const on = actions.checks[valueKey] ?? item.default === true;
  return (
    <label className="mm-check">
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
  children,
}: {
  label: string;
  labelWidth?: number;
  fieldWidth?: number;
  fill?: boolean;
  children: ReactNode;
}) {
  return (
    <div className={`mm-field${fill ? " mm-field-fill" : ""}`}>
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
  const width = item.fieldWidth ?? (fill === false ? 72 : 96);
  return (
    <div className="mm-number">
      <MmField label={item.label} labelWidth={item.labelWidth} fieldWidth={width} fill={fill !== false}>
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
          <button type="button" className="mm-btn mm-btn-inline mm-step" style={buttonChrome({})}>
            -
          </button>
          <button type="button" className="mm-btn mm-btn-inline mm-step" style={buttonChrome({})}>
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
    <MmField label={item.label} labelWidth={item.labelWidth} fieldWidth={width} fill={fill !== false}>
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
    <div className="mm-drop">
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

function MmSlider({ item, fill }: { item: SliderItem; fill?: boolean }) {
  const span = item.max - item.min;
  const value = sliderValue(item);
  const fraction = span > 0 ? (value - item.min) / span : 0;
  return (
    <div className={`mm-slider${fill === false ? " mm-slider-inline" : ""}`}>
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
  return (
    <div className="mm-stepper">
      <span className="mm-stepper-label">{item.label}</span>
      <span className="mm-stepper-btn">-</span>
      <span className="mm-stepper-readout">{sliderText(value, shaped)}</span>
      <span className="mm-stepper-btn">+</span>
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
  // The default variant and an unset one use the accent, as the runtime does.
  const fill = item.variant && item.variant !== "default" ? buttonChrome({ variant: item.variant }).background : undefined;
  return (
    <div className="mm-progress">
      <span className="mm-progress-label">{item.label}</span>
      <span className="mm-progress-bar">
        <span className="mm-progress-fill" style={{ width: `${fraction * 100}%`, background: fill }} />
      </span>
      <span className="mm-progress-readout">{text}</span>
    </div>
  );
}

function MmRadio({ item, inline }: { item: RadioItem; inline: boolean }) {
  const list = normalizeOptions(item.options);
  const chosen = item.default ?? null;
  return (
    <div className="mm-radio">
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

// The runtime button reads "Label: F7", or "Label: None" without a binding, as Caption in widgets/keybind.lua writes it.
function MmKeybind({ item }: { item: KeybindItem }) {
  const bound = item.default !== undefined && item.default !== "";
  return (
    <button type="button" className="mm-btn mm-keybind" style={buttonChrome({})}>
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
        style={{ textAlign: item.align, whiteSpace: item.wrap === false || horizontal ? "nowrap" : undefined }}
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
