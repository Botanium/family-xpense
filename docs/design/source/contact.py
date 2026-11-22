#!/usr/bin/env python3
"""Makes a contact sheet of the 1x PNGs of one theme (for the PR).

    python3 docs/design/source/contact.py --png docs/design/png --theme light --out sheet.png [--cols 6] [--scale 0.5]

Lays the frames out in a grid with their numbers and names, as an HTML page,
and screenshots it with headless Google Chrome.
"""

import argparse
import json
import pathlib
import subprocess
import tempfile

from screens import SCREENS

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--png", required=True)
    parser.add_argument("--theme", default="light")
    parser.add_argument("--out", required=True)
    parser.add_argument("--cols", type=int, default=6)
    parser.add_argument("--scale", type=float, default=0.5)
    args = parser.parse_args()
    png = pathlib.Path(args.png).resolve()
    import build
    w, h = round(390 * args.scale), round(844 * args.scale)
    bg, fg = ("#F4F3F0", "#0B0B0C") if args.theme == "light" else ("#0E0E0F", "#F2F1ED")
    cells = []
    for num, stem, name, *_ in SCREENS:
        src = png / f"{build.png_stem(num, stem, args.theme)}@1x.png"
        cells.append(
            f'<figure style="margin:0"><img src="{src.as_uri()}" width="{w}" height="{h}" '
            f'style="display:block;border-radius:12px;box-shadow:0 0 0 1px rgba(127,127,127,.25)">'
            f'<figcaption style="font:500 13px/18px Helvetica, sans-serif;color:{fg};margin-top:8px">{num} · {name}</figcaption></figure>'
        )
    cols = args.cols
    rows = -(-len(cells) // cols)
    pad, gap_x, gap_y = 32, 24, 24
    width = pad * 2 + cols * w + (cols - 1) * gap_x
    height = pad * 2 + rows * (h + 26) + (rows - 1) * gap_y
    page = (
        f'<!doctype html><html><body style="margin:0;background:{bg}"><div style="padding:{pad}px;display:grid;'
        f'grid-template-columns:repeat({cols},{w}px);column-gap:{gap_x}px;row-gap:{gap_y}px">{"".join(cells)}</div></body></html>'
    )
    with tempfile.TemporaryDirectory() as tmp:
        page_path = pathlib.Path(tmp) / "sheet.html"
        page_path.write_text(page, encoding="utf-8")
        subprocess.run(
            [CHROME, "--headless", "--no-first-run", f"--user-data-dir={tmp}/profile", "--hide-scrollbars",
             "--allow-file-access-from-files", f"--window-size={width},{height}", "--force-device-scale-factor=2",
             f"--screenshot={pathlib.Path(args.out).resolve()}", page_path.as_uri()],
            check=True, capture_output=True, timeout=120,
        )
    print(f"{args.out}: {width} x {height} at 2x")


if __name__ == "__main__":
    main()
