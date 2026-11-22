#!/usr/bin/env python3
"""Renders the preview pages from build.py to PNG at 3x and 1x.

    python3 docs/design/source/render.py --out <build dir> --dest docs/design/png [--only 06-home]

The 3x PNG is a headless Google Chrome screenshot with an isolated profile:
a 390 x 844 window at device scale factor 3 (1170 x 2532, the pixel density
of the household's iPhones), scrollbars hidden, file fonts allowed so the
pages use the app's bundled Geist and Geist Mono. Glass is the CSS
backdrop-filter blur tier.

The 1x PNG is that 3x image downsampled to 390 x 844 with macOS `sips`, so it
matches a 3x simulator capture scaled to 1x (hairlines are one physical
pixel on the device, not one point).
"""

import argparse
import concurrent.futures
import json
import pathlib
import subprocess
import tempfile

CANDIDATES = [
    pathlib.Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
]


def chrome():
    for c in CANDIDATES:
        if c.exists():
            return str(c)
    raise SystemExit("no Chrome found")


def shoot(binary, page, png3, png1, profiles):
    with tempfile.TemporaryDirectory(dir=profiles) as profile:
        subprocess.run(
            [
                binary, "--headless", "--no-first-run", "--no-default-browser-check",
                f"--user-data-dir={profile}", "--hide-scrollbars", "--allow-file-access-from-files",
                "--window-size=390,844", "--force-device-scale-factor=3",
                f"--screenshot={png3}", page.as_uri(),
            ],
            check=True, capture_output=True, timeout=120,
        )
    subprocess.run(
        ["sips", "--resampleHeightWidth", "844", "390", str(png3), "--out", str(png1)],
        check=True, capture_output=True, timeout=60,
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--dest", required=True)
    parser.add_argument("--only", nargs="*")
    args = parser.parse_args()
    # Absolute, because pages are opened as file:// URIs and Chrome and sips
    # get the PNG paths; relative ones fail in Path.as_uri().
    out = pathlib.Path(args.out).resolve()
    dest = pathlib.Path(args.dest).resolve()
    dest.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
    binary = chrome()
    profiles = out / "profiles"
    profiles.mkdir(exist_ok=True)
    jobs = []
    for entry in manifest:
        stem = entry["png"]
        if args.only and not any(stem.startswith(o) for o in args.only):
            continue
        jobs.append((out / "preview" / f"{stem}.html", dest / f"{stem}@3x.png", dest / f"{stem}@1x.png", profiles))
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        list(pool.map(lambda j: shoot(binary, *j), jobs))
    print(f"{len(jobs) * 2} PNGs written to {dest}")


if __name__ == "__main__":
    main()
