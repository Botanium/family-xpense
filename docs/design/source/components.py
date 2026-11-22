"""HTML versions of the app/lib/core/ui components, drawn with tokens.py.

Each function mirrors one widget's layout (padding, gaps, minimum sizes,
text styles and colour slots) closely enough that a 1x capture of the built
screen can be overlaid on the artboard. `t` is a theme from tokens.THEMES.
"""

import html

from tokens import (
    AVATAR, AVATAR_OVERLAP, AVATAR_RING, BOTTOM_OFFSET, BUTTON_HEIGHT, CHIP_HEIGHT,
    CHIP_PADDING, CHART_BAR_GAP, DOCK_PADDING, DOCK_RECORD_BUTTON, DOCK_SIDE_BUTTON,
    DOT_LEDGER, DOT_NUDGE, DOT_UNREAD, FLOATING_MARGIN, GLYPHS, GOAL_BAR, GRABBER_H,
    GRABBER_W, HAIR, HAIR2, ICON_ASK, ICON_PILL, ICON_ROW, ICON_TAB, ICON_TOP,
    LEDGER_ROW, LIST_ROW, MINI_BARS_HEIGHT, MIN_TARGET, MONO, PILL_HEIGHT, PILL_PADDING,
    PROGRESS_RING, PROGRESS_RING_STROKE, QUOTE_MAX_WIDTH, R_DOCK, R_SHEET, R_SLIP,
    R_WELL, RECORD_HALO, S2, S4, S6, S8, S12, S16, S20, S24, SANS, SCREEN_MARGIN,
    SHEET_MARGIN, SLIP_PADDING, STEP_BAR, SWITCH_H, SWITCH_KNOB, SWITCH_W,
    TAB_BAR_HEIGHT, TAB_BAR_INSET, TAB_ITEM_WELL, THIN_BAR, TOP_BUTTON, TOP_ROW, TYPE,
    WAVE_BAR, WAVE_BAR_MINI, WAVE_HEIGHT, WAVE_HEIGHT_MINI, ASK_BUTTON,
)


def esc(s):
    """Escapes text content (apostrophes stay readable)."""
    return html.escape(s, quote=False)


def attr(s):
    """Escapes an attribute value."""
    return html.escape(s, quote=True)


def ts(t, name, color=None, weight=None, extra=""):
    """CSS for one XpType style in colour slot `color` (default ink)."""
    family, size, line, w, tracking = TYPE[name]
    ff = MONO if family == "mono" else SANS
    css = (
        f"font-family: {ff}; font-size: {size}px; line-height: {line}px; "
        f"font-weight: {weight or w}; letter-spacing: {tracking:g}px; color: {color or t['ink']}"
    )
    if family == "mono":
        css += "; font-variant-numeric: tabular-nums"
    if extra:
        css += "; " + extra
    return css


def text(t, style, content, color=None, weight=None, tag="div", extra=""):
    return f'<{tag} style="{ts(t, style, color, weight, extra)}">{esc(content)}</{tag}>'


def gap(n):
    return f'<div style="height: {n}px; flex: none"></div>'


def icon(name, size, color):
    stroke_width, body = GLYPHS[name]
    if name == "stop":
        paint = f'fill="{color}" stroke="none"'
    else:
        paint = f'fill="none" stroke="{color}" stroke-width="{stroke_width:g}" stroke-linecap="round" stroke-linejoin="round"'
    return (
        f'<svg aria-hidden="true" width="{size}" height="{size}" viewBox="0 0 24 24" {paint} '
        f'style="display: block; flex: none">{body}</svg>'
    )


def glass_css(t, variant, over_media=False):
    """GlassSurface at the blur tier: tint, backdrop blur and saturation, a
    one-point rim, a one-point top highlight and the recipe's shadow."""
    g = t["glass"][variant]
    shadow = t["glass"]["sheetOverMediaShadow"] if (variant == "sheet" and over_media) else g["shadow"]
    shadows = f"inset 0 1px 0 {g['hl']}" + (f", {shadow}" if shadow else "")
    return (
        f"background: {g['tint']}; backdrop-filter: blur({g['blur']}px) saturate(1.6); "
        f"-webkit-backdrop-filter: blur({g['blur']}px) saturate(1.6); border: 1px solid {g['border']}; "
        f"box-shadow: {shadows}; box-sizing: border-box"
    )


def content_color(t, variant):
    return t["glass"][variant]["content"]


def hairline(t, soft=False):
    return f'<div style="flex: none; height: 0; border-top: {HAIR} solid {t["hairSoft"] if soft else t["hair"]}"></div>'


def dot(color, size=DOT_LEDGER):
    return f'<span aria-hidden="true" style="flex: none; width: {size}px; height: {size}px; border-radius: {size / 2:g}px; background: {color}"></span>'


def pressable(inner, label=None, href=None, extra=""):
    """XpPressable: a 44 x 44 minimum hit area with the child centred."""
    aria = f' aria-label="{attr(label)}"' if label else ""
    base = f"min-width: {MIN_TARGET}px; min-height: {MIN_TARGET}px; display: inline-flex; align-items: center; justify-content: center; flex: none"
    if extra:
        base += "; " + extra
    if href:
        return f'<a href="{href}"{aria} style="{base}">{inner}</a>'
    return f'<button type="button"{aria} style="{base}">{inner}</button>'


# Glass controls ------------------------------------------------------------

def glass_icon_button(t, glyph, label, unread=False, over_media=False, href=None):
    variant = "overMedia" if over_media else "button"
    fg = content_color(t, variant)
    # The dot sits 12 pt from the top and end edges of the 44 pt button; the
    # 1 pt rim is inside the box, so the CSS offsets are 11.
    unread_dot = (
        f'<span aria-hidden="true" style="position: absolute; top: 11px; right: 11px; width: {DOT_UNREAD}px; '
        f'height: {DOT_UNREAD}px; border-radius: 3px; background: {t["accent"]}"></span>'
        if unread else ""
    )
    style = (
        f"position: relative; width: {TOP_BUTTON}px; height: {TOP_BUTTON}px; border-radius: {TOP_BUTTON // 2}px; "
        f"{glass_css(t, variant)}; color: {fg}; display: flex; align-items: center; justify-content: center; flex: none"
    )
    inner = icon(glyph, ICON_TOP, fg) + unread_dot
    if href:
        return f'<a href="{href}" aria-label="{attr(label)}" style="{style}">{inner}</a>'
    return f'<button type="button" aria-label="{attr(label)}" style="{style}">{inner}</button>'


def glass_pill(t, label, glyph=None, color=None, mono=False, over_media=False):
    variant = "overMedia" if over_media else "button"
    fg = color or content_color(t, variant)
    glyph_html = (icon(glyph, ICON_PILL, fg) + f'<span style="width: {S6}px; flex: none"></span>') if glyph else ""
    label_css = ts(t, "monoLabel", fg) if mono else ts(t, "meta", fg, 500)
    return (
        f'<span style="display: inline-flex; align-items: center; min-height: {PILL_HEIGHT}px; '
        f'padding: {S6 - 1}px {PILL_PADDING - 1}px; border-radius: 999px; {glass_css(t, variant)}; flex: none">'
        f'{glyph_html}<span style="{label_css}">{esc(label)}</span></span>'
    )


def mode_chip_on_device(t):
    return glass_pill(t, "On-device", glyph="lock", color=t["income"])


def top_bar(t, title, leading="", trailing=""):
    """XpTopBar: 44 high, floating margin 16, mono title centred."""
    empty = f'<span style="width: {MIN_TARGET}px; flex: none"></span>'
    return (
        f'<header style="position: absolute; left: {FLOATING_MARGIN}px; right: {FLOATING_MARGIN}px; top: {TOP_ROW}px; '
        f'height: {MIN_TARGET}px; display: flex; align-items: center; justify-content: space-between; z-index: 3">'
        f'{leading or empty}'
        f'<h1 style="position: absolute; left: 0; right: 0; margin: 0; text-align: center; pointer-events: none; '
        f'{ts(t, "screenTitle")}">{esc(title.upper())}</h1>'
        f'{trailing or empty}</header>'
    )


TABS = [("home", "Home", "06"), ("activity", "Activity", "16"), ("goals", "Goals", "12"), ("accounts", "Accounts", "10")]


def tab_bar(t, active, link):
    """XpTabBarWithAsk: glass tab bar plus the orange Ask button."""
    items = []
    for glyph, label, num in TABS:
        on = glyph == active
        color = t["ink"] if on else t["tabInactive"]
        style_name = "tabLabelActive" if on else "tabLabelInactive"
        well = f"background: {t['tabWell']}; " if on else ""
        current = ' aria-current="page"' if on else ""
        items.append(
            f'<a href="{link(num)}"{current} style="height: {TAB_ITEM_WELL}px; border-radius: {TAB_ITEM_WELL // 2}px; {well}'
            f'display: flex; flex-direction: column; align-items: center; justify-content: center; gap: {S2}px">'
            f'{icon(glyph, ICON_TAB, color)}<span style="{ts(t, style_name, color)}">{label}</span></a>'
        )
    right = FLOATING_MARGIN + ASK_BUTTON + S8
    nav = (
        f'<nav aria-label="Main" style="position: absolute; left: {FLOATING_MARGIN}px; right: {right}px; bottom: {BOTTOM_OFFSET}px; '
        f'height: {TAB_BAR_HEIGHT}px; border-radius: {TAB_BAR_HEIGHT // 2}px; {glass_css(t, "control")}; '
        f'display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); align-items: center; padding: 0 {TAB_BAR_INSET - 1}px; z-index: 4">'
        + "".join(items) + "</nav>"
    )
    ask = (
        f'<a href="{link("07")}" aria-label="Ask: talk, type or scan" style="position: absolute; right: {FLOATING_MARGIN}px; '
        f'bottom: {BOTTOM_OFFSET}px; width: {ASK_BUTTON}px; height: {ASK_BUTTON}px; border-radius: {ASK_BUTTON // 2}px; '
        f'{glass_css(t, "accent")}; display: flex; align-items: center; justify-content: center; z-index: 4">'
        f'{icon("sparkle", ICON_ASK, content_color(t, "accent"))}</a>'
    )
    return nav + ask


def avatar_pair(t, first="Y", second="S", label="You and Sam"):
    def one(initial, fill, fg, shift):
        move = f" transform: translateX(-{AVATAR_OVERLAP}px);" if shift else ""
        return (
            f'<span style="width: {AVATAR}px; height: {AVATAR}px; box-sizing: border-box; border-radius: {AVATAR // 2}px; '
            f'background: {fill}; border: {AVATAR_RING}px solid {t["canvas"]}; display: flex; align-items: center; '
            f'justify-content: center; flex: none;{move} {ts(t, "meta", fg, 600)}">{initial}</span>'
        )
    return (
        f'<span role="img" aria-label="{attr(label)}" style="display: flex; flex: none">'
        f'{one(first, t["ink"], t["canvas"], False)}{one(second, t["surface"], t["ink"], True)}</span>'
    )


# Content -------------------------------------------------------------------

def section_label(t, label, action=None, href=None):
    """SectionLabel: caption in secondary ink, optional link."""
    act = ""
    if action:
        inner = f'<span style="{ts(t, "caption", weight=500)}">{esc(action)}</span>'
        act = pressable(inner, href=href)
    height = MIN_TARGET if action else 18
    return (
        f'<div style="display: flex; align-items: center; min-height: {height}px; flex: none">'
        f'<h2 style="flex: 1; margin: 0; {ts(t, "caption", t["ink2"], extra="font-weight: 400")}">{esc(label)}</h2>{act}</div>'
    )


def ledger_row(t, label, value, dot_color=None, value_color=None):
    """LedgerRow: dot, label, dotted leader, mono value; 36 high."""
    d = (dot(dot_color) + f'<span style="width: {S8}px; flex: none"></span>') if dot_color else ""
    leader = (
        f'<span aria-hidden="true" style="flex: 1; height: 10px; box-sizing: border-box; padding-top: 8.67px">'
        f'<span style="display: block; height: {HAIR2}; background: repeating-linear-gradient(90deg, transparent 0 0.33px, '
        f'{t["leader"]} 0.33px 1px, transparent 1px 4px)"></span></span>'
    )
    return (
        f'<div style="display: flex; align-items: center; min-height: {LEDGER_ROW}px; flex: none">{d}'
        f'<span style="{ts(t, "subhead")}">{esc(label)}</span><span style="width: {S8}px; flex: none"></span>{leader}'
        f'<span style="width: {S8}px; flex: none"></span><span style="{ts(t, "figureBody", value_color)}">{esc(value)}</span></div>'
    )


def list_row(t, title, subtitle=None, leading="", trailing="", divider=True, href=None):
    """XpListRow: min 54 with 8 vertical padding, soft hairline below."""
    sub = f'<div style="{ts(t, "meta", t["ink2"])}">{esc(subtitle)}</div>' if subtitle else ""
    border = f"border-bottom: {HAIR} solid {t['hairSoft']}; " if divider else ""
    lead = leading
    trail = trailing
    tag = "a" if href else "div"
    href_attr = f' href="{href}"' if href else ""
    return (
        f'<{tag}{href_attr} style="display: flex; align-items: center; gap: {S12}px; min-height: {LIST_ROW - 16}px; '
        f'padding: {S8}px 0; {border}flex: none; color: inherit">{lead}'
        f'<div style="flex: 1; min-width: 0"><div style="{ts(t, "bodyStrong")}">{esc(title)}</div>{sub}</div>{trail}</{tag}>'
    )


def amount(t, value, style="figureBody", color=None, converted=None, align="end"):
    conv = f'<div style="{ts(t, "figureSmall", t["ink2"])}; text-align: {align}">{esc(converted)}</div>' if converted else ""
    return (
        f'<div style="flex: none; text-align: {align}"><div style="{ts(t, style, color)}">{esc(value)}</div>{conv}</div>'
    )


def disclosure(t, title, value=None, divider=True, href=None, title_color=None):
    """XpDisclosure: min 54, body title, secondary value, chevron."""
    val = (
        f'<span style="flex: 0 1 auto; min-width: 0; text-align: right; {ts(t, "body", t["ink2"])}">{esc(value)}</span>'
        if value else ""
    )
    border = f"border-bottom: {HAIR} solid {t['hairSoft']}; " if divider else ""
    tag = "a" if href else "button"
    extra = f' href="{href}"' if href else ' type="button"'
    return (
        f'<{tag}{extra} style="display: flex; align-items: center; width: 100%; min-height: {LIST_ROW}px; {border}'
        f'flex: none; text-align: left; color: inherit"><span style="flex: 1; {ts(t, "body", title_color)}">{esc(title)}</span>{val}'
        f'<span style="width: {S8}px; flex: none"></span>{icon("forward", ICON_ROW, t["ink2"])}</{tag}>'
    )


def nudge_row(t, message, action, href=None):
    """NudgeRow: orange 18 pt dot, one line, text action, between hairlines."""
    act = pressable(f'<span style="{ts(t, "caption", weight=600)}">{esc(action)}</span>', href=href)
    return (
        f'<div style="display: flex; flex-direction: column; flex: none">{hairline(t)}'
        f'<div style="display: flex; align-items: center; padding: {S2}px 0">{dot(t["accent"], DOT_NUDGE)}'
        f'<span style="width: {S12}px; flex: none"></span><span style="flex: 1; {ts(t, "caption")}">{esc(message)}</span>'
        f'<span style="width: {S8}px; flex: none"></span>{act}</div>{hairline(t)}</div>'
    )


def rate_prompt(t, rate="1,705", link_change=None):
    """RatePrompt, home placement: the daily dollar-rate question."""
    line = (
        f'<span style="flex: 1; {ts(t, "caption")}">Today\'s dollar rate? '
        f'<span style="{ts(t, "figureBody")}">{esc(rate)}</span></span>'
    )
    change = pressable(f'<span style="{ts(t, "caption", t["ink2"])}">Change</span>', href=link_change)
    same = pressable(f'<span style="{ts(t, "caption", weight=600)}">Same</span>')
    return (
        f'<div aria-label="Today\'s dollar rate? Yesterday it was {rate} dinars" role="group" style="display: flex; flex-direction: column; flex: none">{hairline(t)}'
        f'<div style="display: flex; align-items: center; padding: {S2}px 0">{dot(t["accent"], DOT_NUDGE)}'
        f'<span style="width: {S12}px; flex: none"></span>{line}<span style="width: {S8}px; flex: none"></span>'
        f'<span style="display: flex; align-items: center; gap: {S16}px">{change}{same}</span></div>{hairline(t)}</div>'
    )


def button(t, kind, label, glyph=None, expand=True, href=None, extra=""):
    """XpButton: primary ink, secondary outline, text, destructive."""
    is_text = kind in ("text", "destructive")
    if kind == "primary":
        fill, fg, border, weight = t["primary"], t["onPrimary"], "none", 600
    elif kind == "secondary":
        fill, fg, border, weight = "transparent", t["ink"], f"{HAIR2} solid {t['ink']}", 500
    elif kind == "destructive":
        fill, fg, border, weight = "transparent", t["danger"], "none", 600
    else:
        fill, fg, border, weight = "transparent", t["ink"], "none", 600
    min_h = MIN_TARGET if is_text else BUTTON_HEIGHT
    pad_h = S4 if is_text else S24
    width = "width: 100%; " if expand else ""
    g = (icon(glyph, ICON_TOP, fg) + f'<span style="width: {S8}px; flex: none"></span>') if glyph else ""
    style = (
        f"{width}min-height: {min_h}px; box-sizing: border-box; padding: {S12}px {pad_h}px; border-radius: 999px; "
        f"background: {fill}; border: {border}; display: flex; align-items: center; justify-content: center; flex: none; "
        f"{ts(t, 'button', fg, weight)}"
    )
    if extra:
        style += "; " + extra
    inner = f"{g}<span>{esc(label)}</span>"
    if href:
        return f'<a href="{href}" style="{style}">{inner}</a>'
    return f'<button type="button" style="{style}">{inner}</button>'


def chip(t, label, selected=False):
    """XpChip: 38 visual, 44 hit area, outline; selected is ink fill."""
    fill = t["sel"] if selected else "transparent"
    fg = t["onSel"] if selected else t["ink"]
    return (
        f'<span style="display: inline-flex; align-items: center; min-height: {MIN_TARGET}px; flex: none">'
        f'<button type="button" aria-pressed="{"true" if selected else "false"}" style="min-height: {CHIP_HEIGHT}px; '
        f'box-sizing: border-box; padding: {S8}px {CHIP_PADDING}px; border-radius: 999px; border: {HAIR2} solid {t["ink"]}; '
        f'background: {fill}; {ts(t, "chip", fg)}">{esc(label)}</button></span>'
    )


def chips(t, labels, selected=None):
    """ChoiceChips: a Wrap with 8 between chips and no extra run spacing."""
    return (
        f'<div style="display: flex; flex-wrap: wrap; column-gap: {S8}px; row-gap: 0; flex: none">'
        + "".join(chip(t, label, label == selected) for label in labels) + "</div>"
    )


def filter_bar(t, labels, selected):
    """XpFilterBar: text tabs with a 2 pt ink underline, 20 apart."""
    items = []
    for label in labels:
        on = label == selected
        color = t["ink"] if on else t["ink2"]
        bar = t["ink"] if on else "transparent"
        items.append(
            f'<button type="button" aria-pressed="{"true" if on else "false"}" style="min-height: {MIN_TARGET}px; '
            f'margin-right: {S20}px; display: inline-flex; flex-direction: column; justify-content: center; flex: none">'
            f'<span style="{ts(t, "subhead", color, 600 if on else 500)}; text-align: center">{esc(label)}</span>'
            f'<span style="height: {S6}px"></span><span style="height: {THIN_BAR}px; background: {bar}"></span></button>'
        )
    return f'<div role="tablist" style="display: flex; overflow: hidden; flex: none">{"".join(items)}</div>'


def switch(t, on, label):
    track = t["sel"] if on else t["perf"]
    knob = t["onSel"] if on else t["knobOff"]
    side = "flex-end" if on else "flex-start"
    inset = (SWITCH_H - SWITCH_KNOB) // 2
    return (
        f'<button type="button" role="switch" aria-checked="{"true" if on else "false"}" aria-label="{attr(label)}" '
        f'style="min-height: {MIN_TARGET}px; display: flex; align-items: center; flex: none">'
        f'<span style="width: {SWITCH_W}px; height: {SWITCH_H}px; box-sizing: border-box; padding: {inset}px; border-radius: {SWITCH_H // 2}px; '
        f'background: {track}; display: flex; justify-content: {side}">'
        f'<span style="width: {SWITCH_KNOB}px; height: {SWITCH_KNOB}px; border-radius: {SWITCH_KNOB // 2}px; background: {knob}; '
        f'box-shadow: {t["knobShadow"]}"></span></span></button>'
    )


def search_field(t, hint, field_id):
    return (
        f'<div style="display: flex; align-items: center; background: {t["sunken"]}; border-radius: {R_WELL}px; flex: none">'
        f'<span style="width: {S16}px; flex: none"></span>{icon("search", ICON_ROW, t["ink2"])}'
        f'<label for="{field_id}" class="sr">{esc(hint)}</label>'
        f'<input id="{field_id}" type="search" placeholder="{attr(hint)}" class="ph" style="flex: 1; min-width: 0; '
        f'border: 0; outline: none; background: none; padding: {S12}px {S8}px; margin: 0; {ts(t, "body")}"></div>'
    )


def text_field(t, label, field_id, value="", hint=""):
    """XpTextField: caption label, body text with 12 vertical padding, hairline."""
    return (
        f'<div style="display: flex; flex-direction: column; flex: none">'
        f'<label for="{field_id}" style="{ts(t, "caption", t["ink2"])}">{esc(label)}</label>'
        f'<input id="{field_id}" type="text" value="{attr(value)}" placeholder="{attr(hint)}" class="ph" '
        f'style="border: 0; outline: none; background: none; padding: {S12}px 0; margin: 0; {ts(t, "body")}">'
        f'{hairline(t)}</div>'
    )


def amount_field(t, currency, value, field_id, label="Amount", chevron=True):
    """AmountField: currency mark (22 mono) with chevron, large mono figure, hairline."""
    chev = icon("chevronDown", ICON_PILL, t["ink2"]) if chevron else ""
    cur = pressable(
        f'<span style="display: flex; align-items: center"><span style="{ts(t, "figureMarkHero")}">{esc(currency)}</span>{chev}</span>',
        label=f"Currency, {currency}",
    )
    return (
        f'<div style="display: flex; flex-direction: column; flex: none"><div style="display: flex; align-items: center">{cur}'
        f'<span style="width: {S8}px; flex: none"></span><label for="{field_id}" class="sr">{esc(label)}</label>'
        f'<input id="{field_id}" type="text" inputmode="decimal" value="{attr(value)}" style="flex: 1; min-width: 0; border: 0; '
        f'outline: none; background: none; padding: {S8}px 0; margin: 0; {ts(t, "figureLarge")}"></div>{hairline(t)}</div>'
    )


def slip(t, inner, label=None):
    aria = f' aria-label="{attr(label)}"' if label else ""
    return (
        f'<article{aria} style="background: {t["surface"]}; border-radius: {R_SLIP}px; box-shadow: {t["slipShadow"]}; '
        f'padding: {SLIP_PADDING}px {SLIP_PADDING}px {S16}px; display: flex; flex-direction: column; gap: {S12}px; flex: none">'
        f'{inner}</article>'
    )


def dashed_rule(t):
    return (
        f'<div aria-hidden="true" style="height: {HAIR2}; flex: none; background: repeating-linear-gradient(90deg, '
        f'{t["perf"]} 0 4px, transparent 4px 8px)"></div>'
    )


def guessed_badge(t, label="Guessed"):
    return (
        f'<span style="flex: none; padding: {S2}px {S6}px; border-radius: 999px; border: {HAIR2} solid {t["perf"]}; '
        f'{ts(t, "monoLabel", t["ink2"])}">{esc(label.upper())}</span>'
    )


def slip_field(t, label, value, guessed=False):
    badge = guessed_badge(t) if guessed else ""
    return (
        f'<div style="display: flex; align-items: center; gap: {S8}px"><span style="{ts(t, "caption", t["ink2"])}">{esc(label)}</span>'
        f'{badge}<span style="flex: 1; text-align: right; {ts(t, "figureSmall")}">{esc(value.upper())}</span></div>'
    )


def entry_slip(t, header, confidence, amount_html, fields, question=None, choices="", action="", footer="", label=None):
    mono = ts(t, "monoLabel", t["ink2"], extra="letter-spacing: 1px")
    parts = [
        f'<div style="display: flex; justify-content: space-between; {mono}"><span>{esc(header.upper())}</span>'
        + (f"<span>{esc(confidence)}</span>" if confidence else "") + "</div>",
        amount_html,
    ]
    if fields:
        parts.append(dashed_rule(t))
        parts.extend(slip_field(t, *f) for f in fields)
    if question or choices:
        parts.append(dashed_rule(t))
    if question:
        parts.append(f'<div style="{ts(t, "subhead")}">{esc(question)}</div>')
    for extra in (choices, action, footer):
        if extra:
            parts.append(extra)
    return slip(t, "".join(parts), label)


def thin_bar(t, value, color=None, height=THIN_BAR, label=None):
    aria = f' role="img" aria-label="{attr(label)}"' if label else ' aria-hidden="true"'
    return (
        f'<div{aria} style="height: {height}px; border-radius: 999px; background: {t["hair"]}; overflow: hidden; flex: none">'
        f'<div style="width: {min(value, 1) * 100:.1f}%; height: 100%; border-radius: 999px; background: {color or t["ink"]}"></div></div>'
    )


def goal_bar(t, label, value, pace=None, color=None):
    pace_html = (gap(S6) + f'<div style="{ts(t, "monoLabel", t["ink2"])}">{esc(pace.upper())}</div>') if pace else ""
    return (
        f'<div style="display: flex; flex-direction: column; flex: none"><div style="display: flex; align-items: center">'
        f'<span style="flex: 1; {ts(t, "bodyStrong")}">{esc(label)}</span><span style="{ts(t, "figureBody")}">{round(value * 100)}%</span></div>'
        f'{gap(S6)}{thin_bar(t, value, color or t["saved"], GOAL_BAR)}{pace_html}</div>'
    )


def step_bar(t, current, count=4):
    segs = "".join(
        f'<span style="flex: 1; height: {STEP_BAR}px; border-radius: 999px; background: {t["ink"] if i <= current else t["hair"]}"></span>'
        for i in range(1, count + 1)
    )
    return f'<div role="img" aria-label="Step {current} of {count}" style="display: flex; gap: {S4}px; flex: none">{segs}</div>'


def progress_ring(t, value):
    r = PROGRESS_RING / 2 - PROGRESS_RING_STROKE / 2
    circ = 2 * 3.141592653589793 * r
    c = PROGRESS_RING / 2
    return (
        f'<div role="img" aria-label="{round(value * 100)}% saved" style="position: relative; width: {PROGRESS_RING}px; height: {PROGRESS_RING}px; flex: none">'
        f'<svg aria-hidden="true" width="{PROGRESS_RING}" height="{PROGRESS_RING}" viewBox="0 0 {PROGRESS_RING} {PROGRESS_RING}" style="display: block">'
        f'<circle cx="{c}" cy="{c}" r="{r}" fill="none" stroke="{t["hair"]}" stroke-width="{PROGRESS_RING_STROKE}"></circle>'
        f'<circle cx="{c}" cy="{c}" r="{r}" fill="none" stroke="{t["ink"]}" stroke-width="{PROGRESS_RING_STROKE}" stroke-linecap="round" '
        f'stroke-dasharray="{circ * value:.2f} {circ:.2f}" transform="rotate(-90 {c} {c})"></circle></svg>'
        f'<span style="position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; '
        f'{ts(t, "monoLabel", extra="letter-spacing: 0px")}">{round(value * 100)}%</span></div>'
    )


def history_row(t, title, when, detail=None, restore=None):
    det = f'<div style="{ts(t, "figureSmall")}">{esc(detail)}</div>' if detail else ""
    rest = ""
    if restore:
        rest = pressable(
            f'<span style="display: flex; align-items: center; gap: {S4}px">{icon("restore", ICON_ROW, t["ink"])}'
            f'<span style="{ts(t, "caption", weight=600)}">{esc(restore)}</span></span>'
        )
    return (
        f'<div style="display: flex; align-items: center; padding: {S8}px 0; border-bottom: {HAIR} solid {t["hairSoft"]}; flex: none">'
        f'<div style="flex: 1"><div style="{ts(t, "bodyStrong")}">{esc(title)}</div>{det}'
        f'<div style="{ts(t, "monoLabel", t["ink2"])}">{esc(when.upper())}</div></div>{rest}</div>'
    )


def spinner(t):
    """CupertinoActivityIndicator, radius 10, in secondary ink."""
    ticks = []
    for i in range(8):
        opacity = 1 - i * 0.1
        ticks.append(
            f'<line x1="10" y1="2.5" x2="10" y2="6.5" stroke="{t["ink2"]}" stroke-width="2" stroke-linecap="round" '
            f'opacity="{opacity:.2f}" transform="rotate({-i * 45} 10 10)"></line>'
        )
    return f'<svg aria-hidden="true" width="20" height="20" viewBox="0 0 20 20" style="display: block; flex: none">{"".join(ticks)}</svg>'


def undo_toast(t, message, action):
    fg = content_color(t, "dock")
    return (
        f'<div role="status" style="position: absolute; left: {FLOATING_MARGIN}px; right: {FLOATING_MARGIN}px; '
        f'bottom: {BOTTOM_OFFSET + TAB_BAR_HEIGHT + S12}px; border-radius: 999px; {glass_css(t, "dock")}; '
        f'padding: 0 {S8 - 1}px 0 {S20 - 1}px; display: flex; align-items: center; z-index: 5">'
        f'<span style="flex: 1; {ts(t, "subhead", fg)}">{esc(message)}</span>'
        + pressable(f'<span style="padding: 0 {S12}px; {ts(t, "subhead", weight=600)}">{esc(action)}</span>')
        + "</div>"
    )


def offline_banner(t, message, action=None):
    act = pressable(f'<span style="{ts(t, "meta", weight=600)}">{esc(action)}</span>') if action else ""
    return (
        f'<div role="status" style="display: flex; flex-direction: column; flex: none"><div style="display: flex; align-items: center; '
        f'padding: 0 {SCREEN_MARGIN}px">{icon("offline", ICON_ROW, t["ink2"])}<span style="width: {S8}px; flex: none"></span>'
        f'<span style="flex: 1; padding: {S8}px 0; {ts(t, "meta", t["ink2"])}">{esc(message)}</span>{act}</div>{hairline(t)}</div>'
    )


def mini_bars(t, values, summary):
    top = max(values)
    bars = []
    for i, v in enumerate(values):
        h = max(THIN_BAR, MINI_BARS_HEIGHT * v / top)
        color = t["accent"] if i == len(values) - 1 else t["chartBar"]
        bars.append(f'<span style="flex: 1; height: {h:.2f}px; border-radius: 2px; background: {color}"></span>')
    return (
        f'<div role="img" aria-label="{attr(summary)}" style="height: {MINI_BARS_HEIGHT}px; display: flex; align-items: flex-end; '
        f'gap: {CHART_BAR_GAP}px; flex: none">{"".join(bars)}</div>'
    )


def hero_balance(t, label, mark, whole, fraction, delta=None, secondary=None, delta_positive=True, style="hero"):
    """HeroBalance: caption label, mark + figure with tertiary decimals, delta line."""
    fig, mark_style = ("figureHero", "figureMarkHero") if style == "hero" else ("figureLarge", "figureMarkLarge")
    frac = f'<span style="color: {t["ink3"]}">{esc(fraction)}</span>' if fraction else ""
    delta_html = ""
    if delta:
        sec = f'<span style="color: {t["ink2"]}"> · {esc(secondary)}</span>' if secondary else ""
        color = t["income"] if delta_positive else t["ink"]
        delta_html = gap(S2) + f'<div style="{ts(t, "figureSmall", color)}">{esc(delta.upper())}{sec}</div>'
    return (
        f'<div style="display: flex; flex-direction: column; flex: none">'
        f'<div style="{ts(t, "caption", t["ink2"])}">{esc(label)}</div>{gap(S2)}'
        f'<div style="{ts(t, fig)}; white-space: nowrap"><span style="{ts(t, mark_style)}">{esc(mark)} </span>{esc(whole)}{frac}</div>'
        f'{delta_html}</div>'
    )


def waveform(t, levels, spoken=None, color=None, mini=False, max_width=None):
    bar = WAVE_BAR_MINI if mini else WAVE_BAR
    height = WAVE_HEIGHT_MINI if mini else WAVE_HEIGHT
    spacing = S2 if mini else WAVE_BAR
    skip = 0
    if max_width is not None:
        fit = int((max_width + spacing) // (bar + spacing))
        skip = max(0, len(levels) - fit)
    out = []
    for i in range(skip, len(levels)):
        h = min(max(levels[i] * height, bar), height)
        op = 0.3 if spoken is not None and i >= spoken else 1
        out.append(
            f'<span style="width: {bar}px; height: {h:.1f}px; border-radius: 999px; background: {color or t["ink"]}; '
            f'opacity: {op:g}; flex: none"></span>'
        )
    return (
        f'<div aria-hidden="true" style="height: {height}px; display: flex; align-items: center; justify-content: center; '
        f'gap: {spacing}px; flex: none">{"".join(out)}</div>'
    )


def transcript_quote(t, quote, duration, levels):
    wave = waveform(t, levels, color=t["accent"], mini=True)
    return (
        f'<div style="align-self: flex-end; max-width: {QUOTE_MAX_WIDTH}px; display: flex; flex-direction: column; align-items: flex-end; flex: none">'
        f'<div style="display: flex; align-items: center; padding-bottom: {S6}px">{wave}<span style="width: {S6}px"></span>'
        f'<span style="{ts(t, "monoLabel", t["ink2"], extra="letter-spacing: 0px")}">{esc(duration)}</span></div>'
        f'<p style="margin: 0; text-align: right; {ts(t, "quote")}">“{esc(quote)}”</p></div>'
    )


def well_button(t, glyph, label, href=None):
    fg = content_color(t, "dock")
    style = (
        f"width: {DOCK_SIDE_BUTTON}px; height: {DOCK_SIDE_BUTTON}px; border-radius: {DOCK_SIDE_BUTTON // 2}px; "
        f"background: {t['controlWell']}; display: flex; align-items: center; justify-content: center; flex: none"
    )
    if href:
        return f'<a href="{href}" aria-label="{attr(label)}" style="{style}">{icon(glyph, ICON_TOP, fg)}</a>'
    return f'<button type="button" aria-label="{attr(label)}" style="{style}">{icon(glyph, ICON_TOP, fg)}</button>'


def record_button(t, recording, small=False):
    size = DOCK_SIDE_BUTTON if small else DOCK_RECORD_BUTTON
    halo = f" box-shadow: 0 0 0 {RECORD_HALO}px {t['halo']};" if recording else ""
    label = "Stop listening" if recording else "Talk"
    return (
        f'<button type="button" aria-label="{label}" style="width: {size}px; height: {size}px; border-radius: {size // 2}px; '
        f'background: {t["accent"]}; display: flex; align-items: center; justify-content: center; flex: none;{halo}">'
        f'{icon("stop" if recording else "mic", ICON_TOP, t["inkOnAccent"])}</button>'
    )


DOCK_LEVELS = [6, 12, 20, 30, 16, 34, 22, 12, 28, 36, 18, 10, 24, 30, 16, 8, 22, 32, 24, 14, 10, 18, 12, 8, 6, 4]


def capture_dock(t, recording=False, levels=None, spoken=None, scan_href=None, bottom=BOTTOM_OFFSET):
    """CaptureDock in voice mode: type well, waveform, scan well, record."""
    inner_w = 390 - 2 * FLOATING_MARGIN - 2 * DOCK_PADDING
    wave_w = inner_w - DOCK_SIDE_BUTTON * 2 - DOCK_RECORD_BUTTON - S12 * 3
    wave = (
        waveform(t, [v / WAVE_HEIGHT for v in levels], spoken=spoken, max_width=wave_w)
        if levels else f'<div style="height: {WAVE_HEIGHT}px"></div>'
    )
    return (
        f'<div style="position: absolute; left: {FLOATING_MARGIN}px; right: {FLOATING_MARGIN}px; bottom: {bottom}px; '
        f'border-radius: {R_DOCK}px; {glass_css(t, "dock")}; padding: {DOCK_PADDING - 1}px; z-index: 4">'
        f'<div style="display: flex; align-items: center; gap: {S12}px">{well_button(t, "keyboard", "Type instead")}'
        f'<div style="flex: 1; min-width: 0; display: flex; justify-content: center">{wave}</div>'
        f'{well_button(t, "camera", "Scan a receipt", scan_href)}{record_button(t, recording)}</div></div>'
    )


def glass_sheet(t, inner, header=None, over_media=False, top=None, bottom=SHEET_MARGIN):
    """GlassSheet: sheet glass, radius 38, padding 20/8/20/20, grabber."""
    pos = f"top: {top}px; " if top is not None else ""
    head = ""
    if header:
        cancel, title, action = header
        act = button(t, "text", action, expand=False) if action else f'<span style="width: {MIN_TARGET}px"></span>'
        head = (
            f'<div style="display: flex; align-items: center">{button(t, "text", cancel, expand=False)}'
            f'<h2 style="flex: 1; margin: 0; text-align: center; {ts(t, "title")}">{esc(title)}</h2>{act}</div>'
        )
    return (
        f'<section style="position: absolute; left: {SHEET_MARGIN}px; right: {SHEET_MARGIN}px; {pos}bottom: {bottom}px; '
        f'border-radius: {R_SHEET}px; {glass_css(t, "sheet", over_media)}; padding: {S8 - 1}px {S20 - 1}px {S20 - 1}px; '
        f'display: flex; flex-direction: column; z-index: 6">'
        f'<div aria-hidden="true" style="align-self: center; width: {GRABBER_W}px; height: {GRABBER_H}px; border-radius: 999px; '
        f'background: {t["grabber"]}; flex: none"></div>{gap(S8)}{head}{inner}</section>'
    )


def barrier(t):
    return f'<div aria-hidden="true" style="position: absolute; inset: 0; background: {t["barrier"]}; z-index: 5"></div>'


def app_mark(t, size=ASK_BUTTON):
    """The default LockOverlay mark: ink superellipse with the sparkle."""
    return (
        f'<div role="img" aria-label="Family Xpense" style="width: {size}px; height: {size}px; border-radius: {R_DOCK}px; '
        f'background: {t["primary"]}; display: flex; align-items: center; justify-content: center; flex: none">'
        f'{icon("sparkle", ICON_ASK, t["onPrimary"])}</div>'
    )
