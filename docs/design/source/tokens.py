"""Signal tokens for the WP-D1 reference artboards, copied from the merged
code in app/lib/core/theme (primitives.dart, xp_colors.dart, xp_type.dart,
xp_space.dart, xp_glass.dart, xp_elevation.dart).

Every colour, size, radius and glass recipe the artboards use comes from this
file. If a token changes in app/lib/core/theme, change it here and run
build.py again.
"""

# Frame: an iPhone of 390 x 844 points (iPhone 12 to 14 class), with its
# safe areas. The app's own rules then place everything inside them.
FRAME_W = 390
FRAME_H = 844
SAFE_TOP = 47
SAFE_BOTTOM = 34

# XpSpace (xp_space.dart).
S2, S4, S6, S8, S12, S16, S20, S24, S32, S40 = 2, 4, 6, 8, 12, 16, 20, 24, 32, 40
SCREEN_MARGIN = 24
FLOATING_MARGIN = 16
SHEET_MARGIN = 8
LEDGER_ROW = 36
RECEIPT_GROUP_ROW = 44
LIST_ROW = 54
MIN_TARGET = 44
TAB_BAR_HEIGHT = 62
TAB_ITEM_WELL = 50
TAB_BAR_INSET = 6
ASK_BUTTON = 62
DOCK_PADDING = 14
DOCK_SIDE_BUTTON = 48
DOCK_RECORD_BUTTON = 56
RECORD_HALO = 6
TOP_BUTTON = 44
PILL_HEIGHT = 32
PILL_PADDING = 12
BUTTON_HEIGHT = 52
CHIP_HEIGHT = 38
CHIP_PADDING = 14
SLIP_PADDING = 18
GRABBER_W, GRABBER_H = 38, 5
CHART_BAR_GAP = 5
MINI_BARS_HEIGHT = 64
DOT_LEDGER, DOT_UNREAD, DOT_NUDGE = 7, 6, 18
AVATAR, AVATAR_OVERLAP, AVATAR_RING = 34, 10, 2
THIN_BAR, GOAL_BAR = 2, 4
SWITCH_W, SWITCH_H, SWITCH_KNOB = 52, 32, 26
STEP_BAR = 3
SCAN_BRACKET, SCAN_STROKE = 26, 2.5
WAVE_BAR, WAVE_BAR_MINI = 3, 2
WAVE_HEIGHT, WAVE_HEIGHT_MINI = 40, 14
ICON_TOP, ICON_TAB, ICON_ASK, ICON_PILL, ICON_ROW = 20, 21, 24, 12, 17
QUOTE_MAX_WIDTH = 270
CAMERA_SCRIM = 120
PROGRESS_RING, PROGRESS_RING_STROKE = 44, 3

# XpRadius.
R_SLIP, R_CHART_BAR, R_SHEET, R_DOCK, R_PAPER, R_WELL = 6, 2, 38, 34, 3, 24

# Derived placements (xp_space.dart bottomControlOffset and
# contentBottomPadding; the top row sits one s8 below the safe area).
BOTTOM_OFFSET = max(SAFE_BOTTOM, S8) + S8  # 42
CONTENT_BOTTOM_PADDING = TAB_BAR_HEIGHT + BOTTOM_OFFSET + S16  # 120
TOP_ROW = SAFE_TOP + S8  # 55

# One physical pixel on a 3x iPhone, and two (XpSpace.hairline, x2).
HAIR = "0.33px"
HAIR2 = "0.67px"

SANS = "'Geist', system-ui, sans-serif"
MONO = "'Geist Mono', ui-monospace, monospace"

# XpType (xp_type.dart): family, size, line height, weight, tracking.
TYPE = {
    "figureHero": ("mono", 50, 56, 300, -2.5),
    "figureLarge": ("mono", 38, 42, 300, -1.6),
    "figureMedium": ("mono", 28, 32, 300, -1.2),
    "figureBody": ("mono", 14, 20, 400, 0),
    "figureSmall": ("mono", 12, 16, 400, 0),
    "figureMarkHero": ("mono", 22, 28, 300, 0),
    "figureMarkLarge": ("mono", 17, 22, 300, 0),
    "monoLabel": ("mono", 11, 14, 400, 1.2),
    "screenTitle": ("mono", 12, 16, 400, 1.4),
    "quote": ("sans", 20, 27, 500, -0.3),
    "title": ("sans", 16, 22, 600, 0),
    "body": ("sans", 15, 22, 400, 0),
    "bodyStrong": ("sans", 15, 22, 500, 0),
    "subhead": ("sans", 14, 20, 500, 0),
    "caption": ("sans", 13, 18, 400, 0),
    "meta": ("sans", 12, 16, 400, 0),
    "button": ("sans", 15, 20, 600, 0),
    "chip": ("sans", 13, 18, 500, 0),
    "tabLabelActive": ("sans", 11, 13, 600, 0),
    "tabLabelInactive": ("sans", 11, 13, 500, 0),
}


def _rgba(hex_color, alpha):
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r},{g},{b},{alpha:g})"


def _white(alpha):
    return _rgba("#FFFFFF", alpha)


# XpColors.light and XpColors.dark (xp_colors.dart), plus XpOpacity uses.
LIGHT = {
    "name": "light",
    "canvas": "#ECEBE7",
    "surface": "#FAF9F6",
    "sunken": "#E6E4DF",
    "ink": "#0B0B0C",
    "ink2": "#67665F",
    "ink3": "#7A7871",
    "inkOnAccent": "#0B0B0C",
    "hair": "#D8D6D0",
    "hairSoft": "#DEDCD6",
    "leader": "#A9A7A0",
    "perf": "#BDBAB2",
    "accent": "#FF5B1A",
    "halo": _rgba("#FF5B1A", 0.16),
    "income": "#127047",
    "saved": "#2B59FF",
    "loan": "#A15C00",
    "danger": "#B3261E",
    "primary": "#0B0B0C",
    "onPrimary": "#FAF9F6",
    "sel": "#0B0B0C",
    "onSel": "#FAF9F6",
    "tabWell": _rgba("#0B0B0C", 0.07),
    "tabInactive": "#3F3E3A",
    "controlWell": _rgba("#0B0B0C", 0.06),
    "scan": "#1C1C1E",
    "onMedia": "#FAF9F6",
    "paper": "#F4F2EC",
    "receiptInk": "#0B0B0C",
    "knobOff": "#FAF9F6",
    "cats": ["#127047", "#2B59FF", "#A15C00", "#8A3FFC", "#C2255C", "#0E7490", "#5F6B00", "#6B5B4B"],
    "chartBar": _rgba("#0B0B0C", 0.82),
    "grabber": _rgba("#0B0B0C", 0.2),
    "barrier": _rgba("#0B0B0C", 0.24),
    "lockCanvas": _rgba("#ECEBE7", 0.72),
    # XpElevation.light.
    "slipShadow": "0 1px 2px rgba(11,11,12,0.05), 0 16px 34px rgba(11,11,12,0.07)",
    "knobShadow": "0 2px 6px rgba(0,0,0,0.18)",
}

DARK = {
    "name": "dark",
    "canvas": "#161617",
    "surface": "#1F1F21",
    "sunken": "#101011",
    "ink": "#F2F1ED",
    "ink2": "#A3A199",
    "ink3": "#77756E",
    "inkOnAccent": "#0B0B0C",
    "hair": "#2C2C2F",
    "hairSoft": "#252527",
    "leader": "#4A4A4E",
    "perf": "#3A3A3D",
    "accent": "#FF5B1A",
    "halo": _rgba("#FF5B1A", 0.22),
    "income": "#4CC38A",
    "saved": "#7C9BFF",
    "loan": "#E0A04A",
    "danger": "#FF8A80",
    "primary": "#F2F1ED",
    "onPrimary": "#0B0B0C",
    "sel": "#F2F1ED",
    "onSel": "#0B0B0C",
    "tabWell": _white(0.10),
    "tabInactive": "#B4B2AA",
    "controlWell": _white(0.08),
    "scan": "#000000",
    "onMedia": "#FAF9F6",
    "paper": "#F4F2EC",
    "receiptInk": "#0B0B0C",
    "knobOff": "#F2F1ED",
    "cats": ["#4CC38A", "#7C9BFF", "#E0A04A", "#B392FF", "#F27DA6", "#4FB8D0", "#A8B83A", "#B8A593"],
    "chartBar": _rgba("#F2F1ED", 0.82),
    "grabber": _rgba("#F2F1ED", 0.2),
    "barrier": _rgba("#F2F1ED", 0.24),
    "lockCanvas": _rgba("#161617", 0.72),
    # XpElevation.dark.
    "slipShadow": "0 1px 2px rgba(0,0,0,0.4), 0 16px 34px rgba(0,0,0,0.35)",
    "knobShadow": "0 2px 6px rgba(0,0,0,0.4)",
}

# XpElevation.paper: under the receipt on the camera screen.
PAPER_SHADOW = "0 24px 50px rgba(0,0,0,0.55)"


def _recipe(tint, blur, border, hl, shadow, content):
    return {"tint": tint, "blur": blur, "border": border, "hl": hl, "shadow": shadow, "content": content}


_OVER_MEDIA = _recipe(_rgba("#FAF9F6", 0.18), 20, _white(0.22), _white(0.25), "", "#FAF9F6")

# XpGlass.light (xp_glass.dart). The control tint is the 72 % of review item 6.
LIGHT["glass"] = {
    "control": _recipe(_rgba("#FAF9F6", 0.72), 24, _white(0.75), _white(0.95), "0 12px 32px rgba(11,11,12,0.12)", "#0B0B0C"),
    "button": _recipe(_rgba("#FAF9F6", 0.60), 20, _white(0.75), _white(0.90), "0 4px 14px rgba(11,11,12,0.06)", "#0B0B0C"),
    "dock": _recipe(_rgba("#FAF9F6", 0.62), 26, _white(0.80), _white(0.95), "0 16px 40px rgba(11,11,12,0.14)", "#0B0B0C"),
    "sheet": _recipe(_rgba("#ECEBE7", 0.82), 30, _white(0.60), _white(0.90), "0 -10px 40px rgba(11,11,12,0.14)", "#0B0B0C"),
    "accent": _recipe(_rgba("#FF5B1A", 0.94), 24, _white(0.40), _white(0.50), "0 12px 28px rgba(255,91,26,0.35)", "#0B0B0C"),
    "overMedia": _OVER_MEDIA,
    "sheetOverMediaShadow": "0 -10px 40px rgba(0,0,0,0.35)",
}


def _dark_control(blur):
    return _recipe(_rgba("#222224", 0.64), blur, _white(0.10), _white(0.14), "0 12px 32px rgba(0,0,0,0.5)", "#F2F1ED")


# XpGlass.dark.
DARK["glass"] = {
    "control": _dark_control(24),
    "button": _dark_control(20),
    "dock": _dark_control(26),
    "sheet": _recipe(_rgba("#1C1C1E", 0.84), 30, _white(0.08), _white(0.12), "0 -10px 40px rgba(0,0,0,0.55)", "#F2F1ED"),
    "accent": _recipe(_rgba("#FF5B1A", 0.94), 24, _white(0.30), _white(0.40), "0 12px 28px rgba(255,91,26,0.3)", "#0B0B0C"),
    "overMedia": _OVER_MEDIA,
    "sheetOverMediaShadow": "0 -10px 40px rgba(0,0,0,0.55)",
}

THEMES = {"light": LIGHT, "dark": DARK}

# XpGlyph paths (xp_glyphs.dart) on the 24-unit grid: stroke width, markup.
GLYPHS = {
    "home": (1.7, '<path d="M3 10.5L12 3l9 7.5M5 9.5V21h14V9.5"></path>'),
    "activity": (1.7, '<path d="M9 6h12M9 12h12M9 18h12M4 6h.01M4 12h.01M4 18h.01"></path>'),
    "goals": (1.7, '<circle cx="12" cy="12" r="9"></circle><circle cx="12" cy="12" r="5"></circle>'),
    "accounts": (1.7, '<path d="M3 7a2 2 0 0 1 2-2h13v4M3 7v11a2 2 0 0 0 2 2h16V9H5a2 2 0 0 1-2-2z"></path>'),
    "sparkle": (1.8, '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"></path>'),
    "bell": (1.6, '<path d="M6 16v-5a6 6 0 0 1 12 0v5l1.5 2h-15zM10 20.5a2 2 0 0 0 4 0"></path>'),
    "back": (1.8, '<path d="M15 5l-7 7 7 7"></path>'),
    "forward": (1.8, '<path d="M9 5l7 7-7 7"></path>'),
    "chevronDown": (1.8, '<path d="M6 9l6 6 6-6"></path>'),
    "close": (1.9, '<path d="M6 6l12 12M18 6L6 18"></path>'),
    "lock": (2, '<rect x="5" y="11" width="14" height="10" rx="2"></rect><path d="M8 11V7a4 4 0 0 1 8 0v4"></path>'),
    "keyboard": (1.6, '<rect x="3" y="6" width="18" height="12" rx="2"></rect><path d="M7 10h.01M11 10h.01M15 10h.01M7 14h10"></path>'),
    "camera": (1.6, '<path d="M4 8h3l2-3h6l2 3h3v11H4z"></path><circle cx="12" cy="13" r="3.5"></circle>'),
    "mic": (1.8, '<rect x="9" y="3" width="6" height="12" rx="3"></rect><path d="M5 11a7 7 0 0 0 14 0M12 18v3"></path>'),
    "stop": (0, '<rect x="6" y="6" width="12" height="12" rx="3"></rect>'),
    "plus": (1.8, '<path d="M12 5v14M5 12h14"></path>'),
    "check": (1.9, '<path d="M5 12.5l4.5 4.5L19 7"></path>'),
    "search": (1.7, '<circle cx="11" cy="11" r="6.5"></circle><path d="M16 16l4.5 4.5"></path>'),
    "faceId": (1.6, '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2M9 9.5v1M15 9.5v1M12 9.5v4h-1M9 16a4 4 0 0 0 6 0"></path>'),
    "more": (2.6, '<path d="M6 12h.01M12 12h.01M18 12h.01"></path>'),
    "restore": (1.7, '<path d="M4.5 12A7.5 7.5 0 1 0 6.8 6.6M4 4v4h4M12 8v4l3 2"></path>'),
    "offline": (1.6, '<path d="M7 18a4 4 0 0 1-.5-8a5.5 5.5 0 0 1 11 .5a3.8 3.8 0 0 1-.5 7.5zM4 4l16 16"></path>'),
}
