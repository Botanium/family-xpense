#!/usr/bin/env python3
"""Builds the WP-D1 Signal reference artboards.

    python3 docs/design/source/build.py --out <dir> [--canvas-index <canvas.json>]

Writes, for every screen in screens.SCREENS and both themes:
  <out>/canvas/project/V4-<num>-<Name>-<Theme>.dc.html   artboard for the design canvas
  <out>/preview/<num>-<slug>-<theme>.html               the same frame as a plain page,
                                                         with the app's bundled fonts
With --canvas-index, also writes <out>/canvas/project/canvas.json: the given
index plus the page "v4 · Signal, all screens", its frames and titles.
render.py turns the preview pages into the PNGs in docs/design/.
"""

import argparse
import copy
import json
import pathlib
import re

import tokens
from screens import SCREENS

ROOT = pathlib.Path(__file__).resolve().parents[3]
FONTS = ROOT / "app" / "assets" / "fonts"
PAGE_ID = "v4"
PAGE_NAME = "v4 · Signal, all screens"
GROUPS = [
    ("onboarding", "Onboarding · light above, graphite dark below"),
    ("everyday", "Everyday: Home, Ask, capture, Activity · light above, dark below"),
    ("money", "Accounts, goals, loans · light above, dark below"),
    ("more", "Budgets, notifications, settings, lock, report · light above, dark below"),
]
STEP_X = tokens.FRAME_W + 80
DARK_ROW_OFFSET = tokens.FRAME_H + 120
GROUP_STEP_Y = 2400


def slug(stem):
    return re.sub(r"(?<!^)(?=[A-Z])", "-", stem).lower()


def canvas_name(num, stem, theme):
    return f"V4-{num}-{stem}-{theme.capitalize()}.dc.html"


def png_stem(num, stem, theme):
    return f"{num}-{slug(stem)}-{theme}"


def helmet_css(t):
    return (
        "body{margin:0}\n"
        f"a{{color:{t['ink']};text-decoration:none}}a:hover{{color:{t['ink']}}}\n"
        "button{font:inherit;color:inherit;margin:0;padding:0;border:0;background:none;cursor:pointer}\n"
        "input{font:inherit}\n"
        f".ph::placeholder{{color:{t['ink2']};opacity:1}}\n"
        ".sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}\n"
    )


def frame(t, inner):
    return (
        f'<div style="position: relative; width: {tokens.FRAME_W}px; height: {tokens.FRAME_H}px; box-sizing: border-box; '
        f'overflow: hidden; background: {t["canvas"]}; font-family: {tokens.SANS}; color: {t["ink"]}">{inner}</div>'
    )


GOOGLE_FONTS = (
    '<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600'
    '&family=Geist+Mono:wght@300;400;500&display=swap" rel="stylesheet">'
)


def dc_html(title, t, body):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
{GOOGLE_FONTS}
<style>
{helmet_css(t)}</style>
</helmet>
{body}
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{tokens.FRAME_W},"height":{tokens.FRAME_H}}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
"""


def font_faces():
    faces = [
        ("Geist", 400, FONTS / "geist" / "Geist-Regular.ttf"),
        ("Geist", 500, FONTS / "geist" / "Geist-Medium.ttf"),
        ("Geist", 600, FONTS / "geist" / "Geist-SemiBold.ttf"),
        ("Geist Mono", 300, FONTS / "geist_mono" / "GeistMono-Light.ttf"),
        ("Geist Mono", 400, FONTS / "geist_mono" / "GeistMono-Regular.ttf"),
        ("Geist Mono", 500, FONTS / "geist_mono" / "GeistMono-Medium.ttf"),
    ]
    return "".join(
        f"@font-face{{font-family:'{family}';font-weight:{weight};font-style:normal;src:url('{path.as_uri()}') format('truetype')}}\n"
        for family, weight, path in faces
    )


def preview_html(title, t, body):
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<style>
{font_faces()}{helmet_css(t)}</style>
</head>
<body>
{body}
</body>
</html>
"""


def layout_index(index):
    """Adds the v4 page, its frames, titles and notes to a canvas index."""
    out = copy.deepcopy(index)
    pages = out.setdefault("pages", [])
    if not any(p["id"] == PAGE_ID for p in pages):
        pages.insert(0, {"id": PAGE_ID, "name": PAGE_NAME})
    boards = out.setdefault("boards", {})
    order = out.setdefault("order", [])
    notes = out.setdefault("notes", {})
    for g, (group, title) in enumerate(GROUPS):
        members = [s for s in SCREENS if s[5] == group]
        y = g * GROUP_STEP_Y
        notes[f"v4{group.capitalize()}"] = {
            "x": 0, "y": y - 300, "text": title, "kind": "title1",
            "maxW": len(members) * STEP_X - 80, "page": PAGE_ID,
        }
        for k, (num, stem, name, _fn, _comp, _grp) in enumerate(members):
            for row, theme in enumerate(("light", "dark")):
                file = canvas_name(num, stem, theme)
                label = "graphite dark" if theme == "dark" else "light"
                boards[file] = {
                    "x": k * STEP_X, "y": y + row * DARK_ROW_OFFSET, "w": tokens.FRAME_W, "h": tokens.FRAME_H,
                    "title": f"{num} · {name} · {label}", "is_interactive": True, "page": PAGE_ID,
                }
                if file not in order:
                    order.append(file)
    notes["v4About"] = {
        "x": 6 * STEP_X, "y": 0, "w": 420, "page": PAGE_ID, "fill": "gray",
        "text": (
            "WP-D1 reference artboards, drawn only with the merged tokens in app/lib/core/theme. "
            "Frame 390 × 844 with safe areas of 47 (top) and 34 (bottom): top controls at 55, "
            "bottom controls 42 above the edge, content margin 24, floating margin 16. "
            "Glass is drawn at the blur tier. Sheet and dock corners are superellipses in the app "
            "and circular here. PNGs at 1x and 3x with an index are in docs/design/."
        ),
    }
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--canvas-index")
    args = parser.parse_args()
    out = pathlib.Path(args.out)
    project = out / "canvas" / "project"
    preview = out / "preview"
    project.mkdir(parents=True, exist_ok=True)
    preview.mkdir(parents=True, exist_ok=True)
    manifest = []
    for num, stem, name, fn, comps, group in SCREENS:
        for theme in ("light", "dark"):
            t = tokens.THEMES[theme]

            def link(n, theme=theme):
                for s in SCREENS:
                    if s[0] == n:
                        return canvas_name(s[0], s[1], theme)
                raise KeyError(n)

            body = frame(t, fn(t, link))
            title = f"{name}, Signal {theme}"
            (project / canvas_name(num, stem, theme)).write_text(dc_html(title, t, body), encoding="utf-8")
            (preview / f"{png_stem(num, stem, theme)}.html").write_text(preview_html(title, t, body), encoding="utf-8")
            manifest.append({
                "num": num, "name": name, "theme": theme, "group": group, "components": comps,
                "canvas": canvas_name(num, stem, theme), "png": png_stem(num, stem, theme),
            })
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    if args.canvas_index:
        index = json.loads(pathlib.Path(args.canvas_index).read_text(encoding="utf-8"))
        (project / "canvas.json").write_text(
            json.dumps(layout_index(index), indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
    print(f"{len(manifest)} artboards written to {out}")


if __name__ == "__main__":
    main()
