#!/usr/bin/env python3
"""
Build script for the presentation slide decks.

Copies the standalone HTML decks under presentation/ (plus their image and
media assets, e.g. influences/) into docs/presentation/ so they ship with
the GitHub Pages gallery. The main deck is also published as
docs/presentation/index.html, so the folder URL opens straight into the
slides.

This runs as part of build/build.py (which generates the rest of docs/),
but it is also runnable on its own:

    python3 presentation/build.py

It only writes inside docs/presentation/, so it is safe to run after the
game gallery build without clobbering it.
"""

import os
import shutil

# Folder this script lives in (presentation/) and the repo root above it.
HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)

SRC_DIR = HERE
OUTPUT_DIR = os.path.join(REPO_ROOT, "docs", "presentation")

# The deck published at docs/presentation/index.html. Falls back to the
# first deck alphabetically if this file is ever renamed.
MAIN_DECK = "how-to-make-video-games.html"

# Asset file extensions copied alongside the HTML decks (images, media,
# and any external css/js a deck might reference).
ASSET_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".svg",
    ".mp4", ".webm", ".ogg", ".mp3", ".wav",
    ".css", ".js",
}


def _iter_assets(src):
    """Yield (abs_path, rel_path) for every asset under src, recursively,
    skipping hidden dirs. HTML decks are handled separately."""
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for name in files:
            ext = os.path.splitext(name)[1].lower()
            if ext in ASSET_EXTS:
                abs_path = os.path.join(root, name)
                rel_path = os.path.relpath(abs_path, src)
                yield abs_path, rel_path


def build():
    decks = sorted(
        name for name in os.listdir(SRC_DIR)
        if name.endswith(".html")
        and os.path.isfile(os.path.join(SRC_DIR, name))
    )
    if not decks:
        print("No .html presentations found in presentation/.")
        return

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # Copy each slide deck by its own filename.
    for name in decks:
        shutil.copyfile(os.path.join(SRC_DIR, name),
                        os.path.join(OUTPUT_DIR, name))
        print(f"  Copied deck: {name}")

    # Copy image / media assets (e.g. influences/), preserving subfolders.
    asset_count = 0
    for abs_path, rel_path in _iter_assets(SRC_DIR):
        dest = os.path.join(OUTPUT_DIR, rel_path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copyfile(abs_path, dest)
        asset_count += 1
    print(f"  Copied {asset_count} asset(s)")

    # Publish the main deck at docs/presentation/index.html.
    main = MAIN_DECK if MAIN_DECK in decks else decks[0]
    shutil.copyfile(os.path.join(SRC_DIR, main),
                    os.path.join(OUTPUT_DIR, "index.html"))
    print(f"  index.html -> {main}")

    print(f"\nPresentation build complete! {len(decks)} deck(s) "
          f"-> docs/presentation/")


if __name__ == "__main__":
    build()
