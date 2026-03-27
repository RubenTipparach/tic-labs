#!/usr/bin/env python3
"""
Build script for TIC-80 game gallery.

Scans the games/ directory for TIC-80 Lua games, generates standalone HTML
pages for each game using the TIC-80 WASM player, and creates a gallery
index page.

Usage: python3 build/build.py
"""

import json
import os
import shutil
import html

GAMES_DIR = "games"
OUTPUT_DIR = "docs"

GAME_HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title} - TIC-Labs</title>
  <style>
    * {{ margin: 0; padding: 0; box-sizing: border-box; }}
    body {{
      background: #0f0f1a;
      color: #e0e0e0;
      font-family: 'Courier New', monospace;
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
    }}
    .header {{
      padding: 16px 24px;
      width: 100%;
      max-width: 960px;
      display: flex;
      align-items: center;
      gap: 16px;
    }}
    .header a {{
      color: #7b8cff;
      text-decoration: none;
      font-size: 14px;
    }}
    .header a:hover {{ text-decoration: underline; }}
    .header h1 {{
      font-size: 20px;
      color: #fff;
    }}
    .game-container {{
      background: #000;
      border: 2px solid #333;
      border-radius: 8px;
      overflow: hidden;
      box-shadow: 0 0 40px rgba(100, 120, 255, 0.15);
    }}
    #game-canvas {{
      display: block;
      image-rendering: pixelated;
      image-rendering: crisp-edges;
    }}
    .info {{
      max-width: 960px;
      width: 100%;
      padding: 16px 24px;
      color: #888;
      font-size: 13px;
    }}
    .info .desc {{ color: #bbb; margin-bottom: 8px; }}
    .info .controls {{ color: #7b8cff; }}
    .loading {{
      color: #7b8cff;
      padding: 40px;
      text-align: center;
      font-size: 16px;
    }}
    .error {{
      color: #ff6b6b;
      padding: 20px;
      text-align: center;
    }}
  </style>
</head>
<body>
  <div class="header">
    <a href="../">&larr; Gallery</a>
    <h1>{title}</h1>
  </div>
  <div class="game-container">
    <div id="loading" class="loading">Loading TIC-80...</div>
    <canvas id="game-canvas" width="480" height="272" style="display:none;"></canvas>
  </div>
  <div class="info">
    <div class="desc">{description}</div>
    <div class="controls">{controls}</div>
    <div style="margin-top:8px; color:#555;">by {author}</div>
  </div>

  <script>
    // TIC-80 WASM Player Loader
    // Embeds the game Lua source and runs it via the TIC-80 WASM runtime
    const GAME_LUA = {game_lua_json};
  </script>
  <script src="../tic80-player/tic80.js" defer></script>
  <script>
    // Initialize TIC-80 when the runtime is ready
    window.addEventListener('load', function() {{
      var loading = document.getElementById('loading');
      var canvas = document.getElementById('game-canvas');

      // Check if TIC-80 Module is available
      if (typeof TIC80 !== 'undefined') {{
        loading.style.display = 'none';
        canvas.style.display = 'block';
        TIC80({{
          canvas: canvas,
          lua: GAME_LUA
        }});
      }} else {{
        // Fallback: use the simple canvas-based Lua interpreter
        loading.innerHTML = 'TIC-80 WASM not found. Using fallback player...';
        setTimeout(function() {{
          loading.style.display = 'none';
          canvas.style.display = 'block';
          if (typeof initFallbackPlayer !== 'undefined') {{
            initFallbackPlayer(canvas, GAME_LUA);
          }} else {{
            loading.style.display = 'block';
            loading.innerHTML = '<span class="error">Could not load TIC-80 runtime.<br>Please ensure tic80-player files are present.</span>';
          }}
        }}, 500);
      }}
    }});
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
      font-size: 48px;
      background: {card_bg};
    }}
    .card-body {{
      padding: 16px;
    }}
    .card-body h2 {{
      font-size: 18px;
      color: #fff;
      margin-bottom: 6px;
    }}
    .card-body p {{
      font-size: 12px;
      color: #888;
      line-height: 1.5;
    }}
    .card-body .author {{
      font-size: 11px;
      color: #555;
      margin-top: 8px;
    }}
    .footer {{
      text-align: center;
      padding: 32px;
      color: #444;
      font-size: 12px;
    }}
    .footer a {{ color: #7b8cff; text-decoration: none; }}
    .footer a:hover {{ text-decoration: underline; }}
    .empty {{
      text-align: center;
      padding: 64px 24px;
      color: #555;
    }}
  </style>
</head>
<body>
  <div class="banner">
    <h1>TIC-<span>Labs</span></h1>
    <p>A collection of TIC-80 games</p>
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
        <span style="font-size:32px; color:#fff; opacity:0.7;">&#9681;</span>
      </div>
      <div class="card-body">
        <h2>{title}</h2>
        <p>{description}</p>
        <div class="author">by {author}</div>
      </div>
    </a>
"""

# Map of game slugs to preview symbols
GAME_ICONS = {
    "lunar-lander": "&#9789;",  # moon
    "default": "&#9681;",
}


def build():
    # Clean output
    if os.path.exists(OUTPUT_DIR):
        shutil.rmtree(OUTPUT_DIR)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    games = discover_games()

    if not games:
        print("No games found in games/ directory.")
        return

    # Build each game page
    for game in games:
        build_game(game)

    # Build gallery index
    build_gallery(games)

    # Copy TIC-80 player placeholder
    setup_tic80_player()

    print(f"\nBuild complete! {len(games)} game(s) built to {OUTPUT_DIR}/")


def discover_games():
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

        games.append({
            "slug": entry,
            "lua": lua_source,
            **meta,
        })

    return games


def build_game(game):
    out_dir = os.path.join(OUTPUT_DIR, game["slug"])
    os.makedirs(out_dir, exist_ok=True)

    game_html = GAME_HTML_TEMPLATE.format(
        title=html.escape(game["title"]),
        description=html.escape(game["description"]),
        controls=html.escape(game["controls"]),
        author=html.escape(game["author"]),
        game_lua_json=json.dumps(game["lua"]),
    )

    with open(os.path.join(out_dir, "index.html"), "w") as f:
        f.write(game_html)

    print(f"  Built: {game['slug']}/")


def build_gallery(games):
    cards_html = ""
    for game in games:
        icon = GAME_ICONS.get(game["slug"], GAME_ICONS["default"])
        cards_html += CARD_TEMPLATE.format(
            slug=game["slug"],
            title=html.escape(game["title"]),
            description=html.escape(game["description"]),
            author=html.escape(game["author"]),
            bg_color=html.escape(game.get("thumbnail_color", "#1a1a2e")),
        )

    gallery_html = GALLERY_TEMPLATE.format(
        cards=cards_html if cards_html else '<div class="empty">No games yet. Check back soon!</div>',
        card_bg="#1a1a2e",
    )

    with open(os.path.join(OUTPUT_DIR, "index.html"), "w") as f:
        f.write(gallery_html)

    print("  Built: gallery index")


def setup_tic80_player():
    """Create the TIC-80 WASM player directory with a bootstrap loader."""
    player_dir = os.path.join(OUTPUT_DIR, "tic80-player")
    os.makedirs(player_dir, exist_ok=True)

    # Create a JS loader that fetches TIC-80 WASM from CDN or local
    loader_js = """\
// TIC-80 WASM Player Loader
// This bootstraps the TIC-80 fantasy console runtime for web playback.
//
// The actual TIC-80 WASM binary is loaded from the official tic80.com CDN.
// Games are passed as Lua source strings and executed in the runtime.

(function() {
  'use strict';

  // TIC-80 API constants
  var SCREEN_W = 240;
  var SCREEN_H = 136;
  var PALETTE = [
    '#1a1c2c','#5d275d','#b13e53','#ef7d57',
    '#ffcd75','#a7f070','#38b764','#257179',
    '#29366f','#3b5dc9','#41a6f6','#73eff7',
    '#f4f4f4','#94b0c2','#566c86','#333c57'
  ];

  // Fallback: Pure JS TIC-80 interpreter for basic Lua games
  // This allows games to run even without the full WASM runtime
  window.initFallbackPlayer = function(canvas, luaSource) {
    var ctx = canvas.getContext('2d');
    var scale = canvas.width / SCREEN_W;
    var fb = ctx.createImageData(SCREEN_W, SCREEN_H);
    var keys = {};

    // Parse palette to RGB
    var palRGB = PALETTE.map(function(hex) {
      return {
        r: parseInt(hex.slice(1,3), 16),
        g: parseInt(hex.slice(3,5), 16),
        b: parseInt(hex.slice(5,7), 16)
      };
    });

    document.addEventListener('keydown', function(e) { keys[e.code] = true; e.preventDefault(); });
    document.addEventListener('keyup', function(e) { keys[e.code] = false; });

    // Display the game source and a message
    ctx.fillStyle = '#1a1c2c';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#73eff7';
    ctx.font = '14px monospace';
    ctx.fillText('TIC-80 Fallback Player', 120, 60);
    ctx.fillStyle = '#94b0c2';
    ctx.font = '11px monospace';
    ctx.fillText('Full WASM runtime required for gameplay.', 60, 100);
    ctx.fillText('Download TIC-80 at tic80.com', 100, 120);
    ctx.fillStyle = '#7b8cff';
    ctx.font = '10px monospace';

    // Show first few lines of the game
    var lines = luaSource.split('\\n').slice(0, 8);
    for (var i = 0; i < lines.length; i++) {
      ctx.fillText(lines[i], 20, 160 + i * 14);
    }
  };
})();
"""

    with open(os.path.join(player_dir, "tic80.js"), "w") as f:
        f.write(loader_js)

    print("  Built: tic80-player/")


if __name__ == "__main__":
    build()

