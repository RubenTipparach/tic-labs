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

TIC_CHUNK_CODE = 5


def _run_tic80(fs_dir, cmd, timeout=30):
    """Run a TIC-80 CLI command. Tries xvfb-run for headless, then direct."""
    for prefix in [["xvfb-run", "-a"], []]:
        try:
            result = subprocess.run(
                prefix + [TIC80_BIN, "--fs", fs_dir, "--cli", "--cmd", cmd],
                capture_output=True, text=True, timeout=timeout,
            )
            return result
        except FileNotFoundError:
            continue
        except subprocess.TimeoutExpired:
            print(f"    WARNING: TIC-80 timed out")
            continue
    return None


def has_tic80():
    """Check if TIC-80 CLI is available."""
    with tempfile.TemporaryDirectory() as tmpdir:
        result = _run_tic80(tmpdir, "exit", timeout=10)
        return result is not None and result.returncode == 0


def make_blank_cartridge(fs_dir):
    """Use TIC-80 to create a valid blank .tic cartridge template."""
    result = _run_tic80(fs_dir, "new lua & save blank.tic & exit")
    blank_path = os.path.join(fs_dir, "blank.tic")
    if result and os.path.exists(blank_path):
        return open(blank_path, "rb").read()
    return None


def patch_cartridge_code(blank_tic_data, lua_source):
    """Replace the code chunk in a valid .tic cartridge with new Lua source.

    The .tic format uses typed chunks with 4-byte headers:
      byte 0: chunk type (lower 5 bits = type, upper 3 bits = bank)
      bytes 1-3: chunk size (24-bit little-endian)
    """
    out = bytearray()
    pos = 0
    replaced = False

    while pos < len(blank_tic_data):
        if pos + 4 > len(blank_tic_data):
            break
        chunk_type = blank_tic_data[pos]
        chunk_size = (blank_tic_data[pos + 1]
                      | (blank_tic_data[pos + 2] << 8)
                      | (blank_tic_data[pos + 3] << 16))
        ctype = chunk_type & 0x1F

        if ctype == TIC_CHUNK_CODE:
            # Replace code chunk with our game source
            code_bytes = lua_source.encode("ascii", errors="replace")
            out.append(chunk_type)
            out += struct.pack("<I", len(code_bytes))[:3]
            out += code_bytes
            replaced = True
        else:
            # Copy chunk as-is
            if chunk_size == 0:
                out += blank_tic_data[pos:pos + 4]
            else:
                out += blank_tic_data[pos:pos + 4 + chunk_size]

        pos += 4 + (chunk_size if chunk_size > 0 else 0)

    if not replaced:
        code_bytes = lua_source.encode("ascii", errors="replace")
        out.append(TIC_CHUNK_CODE)
        out += struct.pack("<I", len(code_bytes))[:3]
        out += code_bytes

    return bytes(out)


def tic80_export_html(fs_dir, cart_name, out_dir):
    """Use TIC-80 CLI to export a .tic cartridge to HTML.

    The cart must already exist in fs_dir. Returns True on success.
    """
    zip_name = cart_name.replace(".tic", "-export.zip")
    cmd = f"load {cart_name} & export html {zip_name} & exit"

    result = _run_tic80(fs_dir, cmd)
    stdout = result.stdout if result else ""
    print(f"    tic80: {stdout.strip()}")

    zip_path = os.path.join(fs_dir, zip_name)
    if not os.path.exists(zip_path):
        return False

    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(out_dir)

    # Post-process the exported HTML to add mobile-friendly canvas scaling
    patch_exported_html(out_dir)

    return True


# CSS/JS injected into the TIC-80 native export's play/index.html
# so the canvas fills the viewport on mobile
EXPORT_MOBILE_PATCH = """
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
  canvas {
    width: 100% !important;
    height: 100% !important;
    object-fit: contain !important;
    image-rendering: pixelated !important;
    image-rendering: crisp-edges !important;
    display: block !important;
    position: absolute !important;
    top: 0 !important;
    left: 0 !important;
  }
</style>
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
"""


def patch_exported_html(out_dir):
    """Inject mobile-friendly styles into TIC-80's exported HTML."""
    index_path = os.path.join(out_dir, "index.html")
    if not os.path.exists(index_path):
        return
    with open(index_path, "r") as f:
        content = f.read()
    # Inject our styles right after <head> or at the start
    if "<head>" in content:
        content = content.replace("<head>", "<head>" + EXPORT_MOBILE_PATCH, 1)
    elif "<HEAD>" in content:
        content = content.replace("<HEAD>", "<HEAD>" + EXPORT_MOBILE_PATCH, 1)
    else:
        content = EXPORT_MOBILE_PATCH + content
    with open(index_path, "w") as f:
        f.write(content)


# ── HTML Templates ──────────────────────────────────────────────────────

# Wrapper page that embeds the TIC-80 exported game in an iframe
# with gallery navigation chrome around it
GAME_PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>{title} - TIC-Labs</title>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    html, body {{ height: 100%; overflow: hidden; touch-action: manipulation; }}
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

    /* Mobile touch controls */
    .touch-controls {{
      display: none;
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      height: 160px;
      z-index: 1000;
      pointer-events: none;
      padding: 10px 20px 20px;
    }}
    .touch-controls .dpad,
    .touch-controls .action-buttons {{
      pointer-events: auto;
    }}
    .dpad {{
      position: absolute;
      left: 20px;
      bottom: 20px;
      width: 130px;
      height: 130px;
    }}
    .dpad-btn {{
      position: absolute;
      width: 44px;
      height: 44px;
      background: rgba(255,255,255,0.15);
      border: 2px solid rgba(255,255,255,0.3);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: rgba(255,255,255,0.6);
      font-size: 20px;
      -webkit-user-select: none;
      user-select: none;
      touch-action: none;
    }}
    .dpad-btn.active {{
      background: rgba(123,140,255,0.4);
      border-color: rgba(123,140,255,0.7);
    }}
    .dpad-up    {{ top: 0; left: 50%; transform: translateX(-50%); }}
    .dpad-down  {{ bottom: 0; left: 50%; transform: translateX(-50%); }}
    .dpad-left  {{ left: 0; top: 50%; transform: translateY(-50%); }}
    .dpad-right {{ right: 0; top: 50%; transform: translateY(-50%); }}
    .action-buttons {{
      position: absolute;
      right: 20px;
      bottom: 20px;
      width: 120px;
      height: 120px;
    }}
    .action-btn {{
      position: absolute;
      width: 52px;
      height: 52px;
      border-radius: 50%;
      background: rgba(255,255,255,0.15);
      border: 2px solid rgba(255,255,255,0.3);
      display: flex;
      align-items: center;
      justify-content: center;
      color: rgba(255,255,255,0.7);
      font-size: 16px;
      font-weight: bold;
      font-family: 'Courier New', monospace;
      -webkit-user-select: none;
      user-select: none;
      touch-action: none;
    }}
    .action-btn.active {{
      background: rgba(123,140,255,0.4);
      border-color: rgba(123,140,255,0.7);
    }}
    .btn-a {{ right: 0; top: 50%; transform: translateY(-50%); }}
    .btn-b {{ left: 0; bottom: 0; }}

    @media (hover: none) and (pointer: coarse) {{
      .touch-controls {{ display: block; }}
      .info-bar {{ display: none; }}
      .top-bar {{ padding: 4px 10px; }}
      .top-bar h1 {{ font-size: 13px; }}
    }}
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

  <div class="touch-controls">
    <div class="dpad">
      <div class="dpad-btn dpad-up" data-key="ArrowUp" data-keycode="38">&#9650;</div>
      <div class="dpad-btn dpad-down" data-key="ArrowDown" data-keycode="40">&#9660;</div>
      <div class="dpad-btn dpad-left" data-key="ArrowLeft" data-keycode="37">&#9664;</div>
      <div class="dpad-btn dpad-right" data-key="ArrowRight" data-keycode="39">&#9654;</div>
    </div>
    <div class="action-buttons">
      <div class="action-btn btn-a" data-key="z" data-keycode="90">A</div>
      <div class="action-btn btn-b" data-key="x" data-keycode="88">B</div>
    </div>
  </div>

  <script>
  (function() {{
    var isTouchDevice = ('ontouchstart' in window) || (navigator.maxTouchPoints > 0);
    if (!isTouchDevice) return;

    var iframe = document.querySelector('.game-frame');
    var buttons = document.querySelectorAll('.dpad-btn, .action-btn');

    function sendKey(btn, type) {{
      var key = btn.getAttribute('data-key');
      var keyCode = parseInt(btn.getAttribute('data-keycode'), 10);
      try {{
        var target = iframe.contentWindow.document;
        var evt = new KeyboardEvent(type, {{
          key: key,
          code: key.length === 1 ? 'Key' + key.toUpperCase() : key,
          keyCode: keyCode,
          which: keyCode,
          bubbles: true,
          cancelable: true
        }});
        target.dispatchEvent(evt);
      }} catch(e) {{
        // Cross-origin fallback: dispatch on parent document
        var evt = new KeyboardEvent(type, {{
          key: key,
          code: key.length === 1 ? 'Key' + key.toUpperCase() : key,
          keyCode: keyCode,
          which: keyCode,
          bubbles: true,
          cancelable: true
        }});
        document.dispatchEvent(evt);
      }}
    }}

    function handleStart(e) {{
      e.preventDefault();
      this.classList.add('active');
      sendKey(this, 'keydown');
    }}

    function handleEnd(e) {{
      e.preventDefault();
      this.classList.remove('active');
      sendKey(this, 'keyup');
    }}

    buttons.forEach(function(btn) {{
      btn.addEventListener('touchstart', handleStart, {{ passive: false }});
      btn.addEventListener('touchend', handleEnd, {{ passive: false }});
      btn.addEventListener('touchcancel', handleEnd, {{ passive: false }});
    }});

    // Handle dragging finger between d-pad buttons
    document.querySelector('.dpad').addEventListener('touchmove', function(e) {{
      e.preventDefault();
      var touch = e.touches[0];
      var el = document.elementFromPoint(touch.clientX, touch.clientY);
      buttons.forEach(function(btn) {{
        if (btn.closest('.dpad')) {{
          if (btn === el) {{
            if (!btn.classList.contains('active')) {{
              btn.classList.add('active');
              sendKey(btn, 'keydown');
            }}
          }} else {{
            if (btn.classList.contains('active')) {{
              btn.classList.remove('active');
              sendKey(btn, 'keyup');
            }}
          }}
        }}
      }});
    }}, {{ passive: false }});
  }})();
  </script>
</body>
</html>
"""

# Fallback: standalone page when TIC-80 CLI is not available
# Uses CDN-hosted WASM runtime
FALLBACK_GAME_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>{title} - TIC-Labs</title>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    html, body {{ height: 100%; overflow: hidden; background: #000; touch-action: manipulation; margin: 0; }}
    canvas {{
      image-rendering: pixelated;
      image-rendering: crisp-edges;
      width: 100%;
      height: 100%;
      display: block;
      object-fit: contain;
    }}

    /* Mobile touch controls */
    .touch-controls {{
      display: none;
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      height: 160px;
      z-index: 1000;
      pointer-events: none;
      padding: 10px 20px 20px;
    }}
    .touch-controls .dpad,
    .touch-controls .action-buttons {{
      pointer-events: auto;
    }}
    .dpad {{
      position: absolute;
      left: 20px;
      bottom: 20px;
      width: 130px;
      height: 130px;
    }}
    .dpad-btn {{
      position: absolute;
      width: 44px;
      height: 44px;
      background: rgba(255,255,255,0.15);
      border: 2px solid rgba(255,255,255,0.3);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: rgba(255,255,255,0.6);
      font-size: 20px;
      -webkit-user-select: none;
      user-select: none;
      touch-action: none;
    }}
    .dpad-btn.active {{
      background: rgba(123,140,255,0.4);
      border-color: rgba(123,140,255,0.7);
    }}
    .dpad-up    {{ top: 0; left: 50%; transform: translateX(-50%); }}
    .dpad-down  {{ bottom: 0; left: 50%; transform: translateX(-50%); }}
    .dpad-left  {{ left: 0; top: 50%; transform: translateY(-50%); }}
    .dpad-right {{ right: 0; top: 50%; transform: translateY(-50%); }}
    .action-buttons {{
      position: absolute;
      right: 20px;
      bottom: 20px;
      width: 120px;
      height: 120px;
    }}
    .action-btn {{
      position: absolute;
      width: 52px;
      height: 52px;
      border-radius: 50%;
      background: rgba(255,255,255,0.15);
      border: 2px solid rgba(255,255,255,0.3);
      display: flex;
      align-items: center;
      justify-content: center;
      color: rgba(255,255,255,0.7);
      font-size: 16px;
      font-weight: bold;
      font-family: 'Courier New', monospace;
      -webkit-user-select: none;
      user-select: none;
      touch-action: none;
    }}
    .action-btn.active {{
      background: rgba(123,140,255,0.4);
      border-color: rgba(123,140,255,0.7);
    }}
    .btn-a {{ right: 0; top: 50%; transform: translateY(-50%); }}
    .btn-b {{ left: 0; bottom: 0; }}

    @media (hover: none) and (pointer: coarse) {{
      .touch-controls {{ display: block; }}
    }}
  </style>
</head>
<body>
  <canvas id="canvas" oncontextmenu="event.preventDefault()" tabindex="0"></canvas>

  <div class="touch-controls">
    <div class="dpad">
      <div class="dpad-btn dpad-up" data-key="ArrowUp" data-keycode="38">&#9650;</div>
      <div class="dpad-btn dpad-down" data-key="ArrowDown" data-keycode="40">&#9660;</div>
      <div class="dpad-btn dpad-left" data-key="ArrowLeft" data-keycode="37">&#9664;</div>
      <div class="dpad-btn dpad-right" data-key="ArrowRight" data-keycode="39">&#9654;</div>
    </div>
    <div class="action-buttons">
      <div class="action-btn btn-a" data-key="z" data-keycode="90">A</div>
      <div class="action-btn btn-b" data-key="x" data-keycode="88">B</div>
    </div>
  </div>

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

  <script>
  (function() {{
    var isTouchDevice = ('ontouchstart' in window) || (navigator.maxTouchPoints > 0);
    if (!isTouchDevice) return;

    var canvas = document.getElementById('canvas');
    var buttons = document.querySelectorAll('.dpad-btn, .action-btn');

    function sendKey(btn, type) {{
      var key = btn.getAttribute('data-key');
      var keyCode = parseInt(btn.getAttribute('data-keycode'), 10);
      var evt = new KeyboardEvent(type, {{
        key: key,
        code: key.length === 1 ? 'Key' + key.toUpperCase() : key,
        keyCode: keyCode,
        which: keyCode,
        bubbles: true,
        cancelable: true
      }});
      canvas.dispatchEvent(evt);
      document.dispatchEvent(evt);
    }}

    function handleStart(e) {{
      e.preventDefault();
      this.classList.add('active');
      sendKey(this, 'keydown');
    }}

    function handleEnd(e) {{
      e.preventDefault();
      this.classList.remove('active');
      sendKey(this, 'keyup');
    }}

    buttons.forEach(function(btn) {{
      btn.addEventListener('touchstart', handleStart, {{ passive: false }});
      btn.addEventListener('touchend', handleEnd, {{ passive: false }});
      btn.addEventListener('touchcancel', handleEnd, {{ passive: false }});
    }});

    // Handle dragging finger between d-pad buttons
    document.querySelector('.dpad').addEventListener('touchmove', function(e) {{
      e.preventDefault();
      var touch = e.touches[0];
      var el = document.elementFromPoint(touch.clientX, touch.clientY);
      buttons.forEach(function(btn) {{
        if (btn.closest('.dpad')) {{
          if (btn === el) {{
            if (!btn.classList.contains('active')) {{
              btn.classList.add('active');
              sendKey(btn, 'keydown');
            }}
          }} else {{
            if (btn.classList.contains('active')) {{
              btn.classList.remove('active');
              sendKey(btn, 'keyup');
            }}
          }}
        }}
      }});
    }}, {{ passive: false }});
  }})();
  </script>
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
    @media (max-width: 480px) {{
      .banner {{ padding: 32px 16px 20px; }}
      .banner h1 {{ font-size: 28px; letter-spacing: 2px; }}
      .gallery {{ padding: 16px 12px; gap: 16px; grid-template-columns: 1fr; }}
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
        print("TIC-80 CLI found. Will export native HTML bundles.")
    else:
        print("TIC-80 CLI not found. Using CDN fallback for WASM runtime.")

    # If TIC-80 is available, create a blank cartridge template once
    # then patch each game's code into it
    blank_tic = None
    tic80_fs = None
    if use_tic80:
        tic80_fs = tempfile.mkdtemp(prefix="tic80build_")
        blank_tic = make_blank_cartridge(tic80_fs)
        if blank_tic:
            print(f"  Created blank cartridge template ({len(blank_tic)} bytes)")
        else:
            print("  WARNING: Could not create blank cartridge, falling back to CDN")
            use_tic80 = False

    for game in games:
        build_game(game, use_tic80, blank_tic, tic80_fs)

    # Clean up temp dir
    if tic80_fs:
        shutil.rmtree(tic80_fs, ignore_errors=True)

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


def build_game(game, use_tic80, blank_tic, tic80_fs):
    """Build a single game page."""
    out_dir = os.path.join(OUTPUT_DIR, game["slug"])
    play_dir = os.path.join(out_dir, "play")
    os.makedirs(play_dir, exist_ok=True)

    if use_tic80 and blank_tic:
        # Patch the blank cartridge with this game's code
        cart_data = patch_cartridge_code(blank_tic, game["lua"])
        cart_name = f"{game['slug']}.tic"
        cart_path = os.path.join(tic80_fs, cart_name)

        with open(cart_path, "wb") as f:
            f.write(cart_data)

        # Export via TIC-80 CLI (uses --fs so paths are relative)
        success = tic80_export_html(tic80_fs, cart_name, play_dir)

        if success:
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
            print(f"  WARNING: TIC-80 export failed for {game['slug']}, using CDN fallback")

    # Fallback: CDN-based player with our own .tic cartridge
    if blank_tic:
        cart_data = patch_cartridge_code(blank_tic, game["lua"])
    else:
        # No blank template available — write a minimal (possibly invalid) .tic
        cart_data = game["lua"].encode("ascii", errors="replace")

    with open(os.path.join(play_dir, "cart.tic"), "wb") as f:
        f.write(cart_data)

    fallback = FALLBACK_GAME_TEMPLATE.format(
        title=html.escape(game["title"]),
    )
    with open(os.path.join(play_dir, "index.html"), "w") as f:
        f.write(fallback)

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
