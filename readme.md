# TIC-Labs

A collection of [TIC-80](https://tic80.com) games, automatically built and deployed as a playable web gallery via GitHub Pages.

## Project Structure

```
games/
  lunar-lander/      # Each game gets its own directory
    game.lua         # TIC-80 Lua source
    meta.json        # Title, description, author, controls
build/
  build.py           # Compiles games into HTML gallery
docs/                # Generated output (deployed to GitHub Pages)
```

## Adding a New Game

1. Create a folder under `games/` with your game slug (e.g. `games/my-game/`)
2. Add a `game.lua` with your TIC-80 Lua source code
3. Add a `meta.json`:
   ```json
   {
     "title": "My Game",
     "author": "Your Name",
     "description": "A short description of the game.",
     "controls": "Arrow keys to move, Z to shoot",
     "thumbnail_color": "#1a1a2e"
   }
   ```
4. Commit and push to `main` — the gallery rebuilds automatically.

## Local Build

```bash
python3 build/build.py
# Open docs/index.html in a browser
```

## Deployment

The GitHub Actions workflow (`.github/workflows/deploy.yml`) automatically:
- Detects changes to `games/` or `build/`
- Runs the build script
- Deploys the `docs/` output to GitHub Pages
