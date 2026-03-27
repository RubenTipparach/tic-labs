#!/usr/bin/env python3
"""
Build script for TIC-80 game gallery.

Scans the games/ directory for TIC-80 Lua games, uses the TIC-80 CLI to
export each game as a playable HTML bundle (with WASM runtime), and
generates a gallery index page.

Requires: TIC-80 CLI installed (set TIC80_PATH env var if not on PATH).
          xvfb-run for headless environments (CI).

Usage: python3 build/build.py
"""

import json
import os
import shutil
import html
import struct
import subprocess
import tempfile
import zipfile

GAMES_DIR = "games"
OUTPUT_DIR = "docs"

# TIC-80 binary path — override with TIC80_PATH env var
TIC80_BIN = os.environ.get("TIC80_PATH", "tic80")

# .tic file format constants
TIC_CHUNK_CODE = 5
TIC_CHUNK_DEFAULT_PALETTE = 12


def make_tic_cartridge(lua_source):
    """Build a minimal .tic cartridge binary from Lua source code.

    The .tic format uses typed chunks with 4-byte headers:
      byte 0: chunk type
      bytes 1-3: chunk size (24-bit little-endian)
    """
    data = bytearray()

    # Sweetie 16 default palette (16 colors x 3 bytes RGB)
    palette = bytes([
        0x1a, 0x1c, 0x2c, 0x5d, 0x27, 0x5d, 0xb1, 0x3e, 0x53, 0xef, 0x7d, 0x57,
        0xff, 0xcd, 0x75, 0xa7, 0xf0, 0x70, 0x38, 0xb7, 0x64, 0x25, 0x71, 0x79,
        0x29, 0x36, 0x6f, 0x3b, 0x5d, 0xc9, 0x41, 0xa6, 0xf6, 0x73, 0xef, 0xf7,
        0xf4, 0xf4, 0xf4, 0x94, 0xb0, 0xc2, 0x56, 0x6c, 0x86, 0x33, 0x3c, 0x57,
    ])

    # Palette chunk
    pal_size = len(palette)
    data.append(TIC_CHUNK_DEFAULT_PALETTE)
    data += struct.pack("<I", pal_size)[:3]
    data += palette

    # Code chunk
    code_bytes = lua_source.encode("ascii", errors="replace")
    code_size = len(code_bytes)
    data.append(TIC_CHUNK_CODE)
    data += struct.pack("<I", code_size)[:3]
    data += code_bytes

    return bytes(data)


def tic80_export_html(tic_path, out_dir):
    """Use TIC-80 CLI to export a .tic cartridge to HTML.

    Returns True on success, False on failure.
    The export produces: index.html, tic80.js, tic80.wasm, cart.tic
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        zip_path = os.path.join(tmpdir, "export.zip")
        cmd = f'load {tic_path} & export html {zip_path} & exit'

        # Try with xvfb-run first (needed in headless CI), fall back to direct
        for prefix in [["xvfb-run", "-a"], []]:
            try:
                result = subprocess.run(
                    prefix + [TIC80_BIN, "--cli", "--cmd", cmd],
                    capture_output=True, text=True, timeout=30,
                )
                if os.path.exists(zip_path):
                    break
            except FileNotFoundError:
                continue
            except subprocess.TimeoutExpired:
                print(f"    WARNING: TIC-80 export timed out")
                continue

        if not os.path.exists(zip_path):
            return False

        # Extract the zip into the output directory
        with zipfile.ZipFile(zip_path, 'r') as zf:
            zf.extractall(out_dir)

        return True


def has_tic80():
    """Check if TIC-80 CLI is available."""
    for prefix in [[], ["xvfb-run", "-a"]]:
        try:
            result = subprocess.run(
                prefix + [TIC80_BIN, "--cli", "--cmd", "exit"],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode == 0:
                return True
        except (FileNotFoundError, subprocess.TimeoutExpired):
            continue
    return False


# ── HTML Templates ──────────────────────────────────────────────────────

# Wrapper page that embeds the TIC-80 exported game in an iframe
# with gallery navigation chrome around it
GAME_PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title} - TIC-Labs</title>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    html, body {{ height: 100%; overflow: hidden; }}
    body {{
      background: #1a1c2c;
      color: #e0e0e0;
      font-family: 'Courier New', monospace;
      display: flex;
      flex-direction: column;
    }}
    .top-bar {{
      padding: 6px 16px;
      background: #0f0f1a;
      display: flex;
      align-items: center;
      gap: 12px;
      flex-shrink: 0;
    }}
    .top-bar a {{
      color: #7b8cff;
      text-decoration: none;
      font-size: 13px;
    }}
    .top-bar a:hover {{ text-decoration: underline; }}
    .top-bar h1 {{
      font-size: 15px;
      color: #fff;
      font-weight: normal;
    }}
    .game-frame {{
      flex: 1;
      border: none;
      width: 100%;
    }}
    .info-bar {{
      padding: 4px 16px;
      background: #0f0f1a;
      font-size: 11px;
      color: #566c86;
      flex-shrink: 0;
      display: flex;
      gap: 16px;
    }}
    .info-bar .ctrl {{ color: #7b8cff; }}
  </style>
</head>
<body>
  <div class="top-bar">
    <a href="../">&larr; Gallery</a>
    <h1>{title}</h1>
  </div>
  <iframe class="game-frame" src="play/index.html" allowfullscreen></iframe>
  <div class="info-bar">
    <span class="ctrl">{controls}</span>
    <span>{description}</span>
    <span>by {author}</span>
  </div>
</body>
</html>
"""

# Fallback: standalone page when TIC-80 CLI is not available
# Uses CDN-hosted WASM runtime
FALLBACK_GAME_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title} - TIC-Labs</title>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    html, body {{ height: 100%; overflow: hidden; background: #1a1c2c; }}
    canvas {{
      image-rendering: pixelated;
      image-rendering: crisp-edges;
      width: 100%;
      height: 100%;
    }}
  </style>
</head>
<body>
  <canvas id="canvas" oncontextmenu="event.preventDefault()" tabindex="0"></canvas>
  <script>
    window.addEventListener("keydown", function(e) {{
      if([32,37,38,39,40].indexOf(e.keyCode)>-1) e.preventDefault();
    }}, false);
    var Module = {{
      canvas: document.getElementById('canvas'),
      arguments: ['cart.tic'],
      locateFile: function(path) {{
        if (path.endsWith('.wasm')) return 'https://tic80.com/js/1.1.2837/' + path;
        return path;
      }}
    }};
  </script>
  <script src="https://tic80.com/js/1.1.2837/tic80.js"></script>
</body>
</html>
"""

GALLERY_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TIC-Labs - Game Gallery</title>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    body {{
      background: #0f0f1a;
      color: #e0e0e0;
      font-family: 'Courier New', monospace;
      min-height: 100vh;
    }}
    .banner {{
      text-align: center;
      padding: 48px 24px 32px;
      background: linear-gradient(180deg, #151530 0%, #0f0f1a 100%);
    }}
    .banner h1 {{
      font-size: 36px;
      color: #fff;
      letter-spacing: 4px;
      margin-bottom: 8px;
    }}
    .banner h1 span {{ color: #7b8cff; }}
    .banner p {{
      color: #888;
      font-size: 14px;
    }}
    .gallery {{
      max-width: 960px;
      margin: 0 auto;
      padding: 32px 24px;
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 24px;
    }}
    .card {{
      background: #1a1a2e;
      border: 1px solid #2a2a4a;
      border-radius: 12px;
      overflow: hidden;
      transition: transform 0.2s, border-color 0.2s, box-shadow 0.2s;
      cursor: pointer;
      text-decoration: none;
      color: inherit;
      display: block;
    }}
    .card:hover {{
      transform: translateY(-4px);
      border-color: #7b8cff;
      box-shadow: 0 8px 32px rgba(100, 120, 255, 0.2);
    }}
    .card-preview {{
      height: 140px;
      display: flex;
      align-items: center;
      justify-content: center;
    }}
    .card-preview svg {{ width: 64px; height: 64px; opacity: 0.6; }}
    .card-body {{ padding: 16px; }}
    .card-body h2 {{ font-size: 18px; color: #fff; margin-bottom: 6px; }}
    .card-body p {{ font-size: 12px; color: #888; line-height: 1.5; }}
    .card-body .meta {{
      font-size: 11px; color: #555; margin-top: 8px;
      display: flex; justify-content: space-between;
    }}
    .footer {{
      text-align: center;
      padding: 32px;
      color: #444;
      font-size: 12px;
    }}
    .footer a {{ color: #7b8cff; text-decoration: none; }}
    .footer a:hover {{ text-decoration: underline; }}
  </style>
</head>
<body>
  <div class="banner">
    <h1>TIC-<span>Labs</span></h1>
    <p>A collection of TIC-80 fantasy console games</p>
  </div>
  <div class="gallery">
    {cards}
  </div>
  <div class="footer">
    Powered by <a href="https://tic80.com">TIC-80</a> |
    Built with TIC-Labs
  </div>
</body>
</html>
"""

CARD_TEMPLATE = """
    <a class="card" href="{slug}/">
      <div class="card-preview" style="background: {bg_color};">
        {icon_svg}
      </div>
      <div class="card-body">
        <h2>{title}</h2>
        <p>{description}</p>
        <div class="meta">
          <span>by {author}</span>
          <span>{controls}</span>
        </div>
      </div>
    </a>
"""

GAME_ICONS = {
    "lunar-lander": '<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M32 8L26 24H38L32 8Z" fill="#73eff7"/><path d="M26 24L22 36H42L38 24H26Z" fill="#41a6f6"/><path d="M22 36L18 40H46L42 36H22Z" fill="#3b5dc9"/><circle cx="32" cy="20" r="2" fill="#ffcd75"/><path d="M28 40L26 48" stroke="#ef7d57" stroke-width="2"/><path d="M36 40L38 48" stroke="#ef7d57" stroke-width="2"/><path d="M4 52C12 48 20 54 28 50C36 46 44 52 60 48" stroke="#566c86" stroke-width="2"/></svg>',
    "default": '<svg viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="16" y="16" width="32" height="32" rx="4" fill="#3b5dc9"/><circle cx="28" cy="32" r="4" fill="#73eff7"/><circle cx="40" cy="28" r="2" fill="#a7f070"/><circle cx="40" cy="36" r="2" fill="#ef7d57"/></svg>',
}


def build():
    """Main build entry point."""
    if os.path.exists(OUTPUT_DIR):
        shutil.rmtree(OUTPUT_DIR)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    games = discover_games()
    if not games:
        print("No games found in games/ directory.")
        return

    use_tic80 = has_tic80()
    if use_tic80:
        print(f"TIC-80 CLI found. Will export native HTML bundles.")
    else:
        print(f"TIC-80 CLI not found. Using CDN fallback for WASM runtime.")

    for game in games:
        build_game(game, use_tic80)

    build_gallery(games)

    with open(os.path.join(OUTPUT_DIR, ".nojekyll"), "w") as f:
        pass

    print(f"\nBuild complete! {len(games)} game(s) -> {OUTPUT_DIR}/")


def discover_games():
    """Scan games/ directory for valid game folders."""
    games = []
    if not os.path.exists(GAMES_DIR):
        return games

    for entry in sorted(os.listdir(GAMES_DIR)):
        game_dir = os.path.join(GAMES_DIR, entry)
        lua_file = os.path.join(game_dir, "game.lua")
        meta_file = os.path.join(game_dir, "meta.json")

        if not os.path.isdir(game_dir) or not os.path.exists(lua_file):
            continue

        meta = {
            "title": entry.replace("-", " ").title(),
            "author": "Unknown",
            "description": "A TIC-80 game.",
            "controls": "",
            "thumbnail_color": "#1a1a2e",
        }

        if os.path.exists(meta_file):
            with open(meta_file, "r") as f:
                meta.update(json.load(f))

        with open(lua_file, "r") as f:
            lua_source = f.read()

        games.append({"slug": entry, "lua": lua_source, **meta})

    return games


def build_game(game, use_tic80):
    """Build a single game page."""
    out_dir = os.path.join(OUTPUT_DIR, game["slug"])
    os.makedirs(out_dir, exist_ok=True)

    # Generate .tic cartridge
    tic_data = make_tic_cartridge(game["lua"])

    if use_tic80:
        # Use TIC-80 CLI to export full HTML bundle
        play_dir = os.path.join(out_dir, "play")
        os.makedirs(play_dir, exist_ok=True)

        # Write .tic to temp location for TIC-80 to load
        with tempfile.NamedTemporaryFile(suffix=".tic", delete=False) as tmp:
            tmp.write(tic_data)
            tmp_tic = tmp.name

        try:
            success = tic80_export_html(tmp_tic, play_dir)
        finally:
            os.unlink(tmp_tic)

        if success:
            # Write wrapper page with gallery nav
            wrapper = GAME_PAGE_TEMPLATE.format(
                title=html.escape(game["title"]),
                description=html.escape(game["description"]),
                controls=html.escape(game["controls"]),
                author=html.escape(game["author"]),
            )
            with open(os.path.join(out_dir, "index.html"), "w") as f:
                f.write(wrapper)
            print(f"  Built: {game['slug']}/ (TIC-80 native export)")
            return
        else:
            print(f"  WARNING: TIC-80 export failed for {game['slug']}, using fallback")

    # Fallback: CDN-based player
    with open(os.path.join(out_dir, "cart.tic"), "wb") as f:
        f.write(tic_data)

    fallback = FALLBACK_GAME_TEMPLATE.format(
        title=html.escape(game["title"]),
    )
    # Write the play page
    play_dir = os.path.join(out_dir, "play")
    os.makedirs(play_dir, exist_ok=True)
    with open(os.path.join(play_dir, "index.html"), "w") as f:
        f.write(fallback)
    # Copy cart.tic into play dir
    with open(os.path.join(play_dir, "cart.tic"), "wb") as f:
        f.write(tic_data)

    # Write wrapper page
    wrapper = GAME_PAGE_TEMPLATE.format(
        title=html.escape(game["title"]),
        description=html.escape(game["description"]),
        controls=html.escape(game["controls"]),
        author=html.escape(game["author"]),
    )
    with open(os.path.join(out_dir, "index.html"), "w") as f:
        f.write(wrapper)

    print(f"  Built: {game['slug']}/ (CDN fallback)")


def build_gallery(games):
    """Build the gallery index page."""
    cards_html = ""
    for game in games:
        icon_svg = GAME_ICONS.get(game["slug"], GAME_ICONS["default"])
        cards_html += CARD_TEMPLATE.format(
            slug=game["slug"],
            title=html.escape(game["title"]),
            description=html.escape(game["description"]),
            author=html.escape(game["author"]),
            controls=html.escape(game.get("controls", "")),
            bg_color=html.escape(game.get("thumbnail_color", "#1a1a2e")),
            icon_svg=icon_svg,
        )

    gallery_html = GALLERY_TEMPLATE.format(cards=cards_html)
    with open(os.path.join(OUTPUT_DIR, "index.html"), "w") as f:
        f.write(gallery_html)

    print("  Built: gallery index")


if __name__ == "__main__":
    build()
