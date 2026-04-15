# Dual Contouring / Marching Cubes App - Implementation Plan

## Context

TIC-Labs is a static gallery of TIC-80 Lua games. The build system (`build/build.py`) scans `games/*/game.lua`, exports them as playable HTML via the TIC-80 WASM runtime, and generates a gallery index deployed to GitHub Pages. There is no Node.js, no frameworks — just Python build + static HTML output.

This new app is **not** a TIC-80 game. It's a standalone WebGL 3D application using Three.js. The build system needs to be extended to support custom HTML apps alongside TIC-80 games.

---

## Architecture Overview

**Two deliverables:**
1. **Build system change** — teach `build.py` to handle game dirs with a custom `index.html` (no `game.lua` required)
2. **The app itself** — a self-contained HTML file with inline JS implementing marching cubes over a user-editable voxel grid

**Tech choices:**
- Three.js (r160+) loaded from CDN (`unpkg.com` or `cdn.jsdelivr.net`) — no bundler needed
- OrbitControls from Three.js addons CDN for camera
- All logic inline in a single HTML file (matches project convention of self-contained games)
- Marching cubes algorithm implemented from scratch in JS (classic Paul Bourke lookup tables)

---

## Step-by-step Plan

### Step 1: Create the feature branch

- Checkout / create branch `claude/dual-contour-marching-cubes-uSUwh`

### Step 2: Extend `build/build.py` to support custom HTML apps

**File:** `build/build.py`

Changes to `discover_games()` (~line 924):
- After checking for `game.lua`, also check for `index.html` in the game dir
- If `index.html` exists (but no `game.lua`), add the game with a `"custom": True` flag
- Still load `meta.json` for title/description/controls

Changes to `build_game()` (~line 958):
- If `game.get("custom")`, copy the game dir contents (index.html + any assets) into `docs/<slug>/play/` and generate the wrapper page — OR just copy directly to `docs/<slug>/` if the custom game provides its own full page
- Skip TIC-80 cartridge patching/export entirely for custom games

Strategy for custom games:
- Copy `index.html` → `docs/<slug>/play/index.html` so the existing wrapper template (with gallery nav bar) still works via iframe embedding
- This gives us the "← Gallery" back button for free

### Step 3: Create `games/dual-contour/meta.json`

```json
{
  "title": "Dual Contour",
  "author": "tic-labs",
  "description": "Interactive marching cubes voxel editor. Click faces to add cubes, right-click to remove. The volume is polygonized into one continuous mesh in real time.",
  "controls": "Left-click face to add, Right-click to remove, Scroll to zoom, Drag to orbit",
  "thumbnail_color": "#0a1a2a"
}
```

### Step 4: Create `games/dual-contour/index.html` — The Marching Cubes App

This is the main deliverable. Single self-contained HTML file with all JS inline.

#### 4a: HTML Shell & Styles
- Dark background matching TIC-Labs aesthetic (`#0f0f1a`)
- Full-viewport `<canvas>` for Three.js
- A minimal HUD overlay showing controls and voxel count
- A small toolbar for toggling wireframe, resetting grid, etc.

#### 4b: Three.js Scene Setup
- Import Three.js + OrbitControls from CDN via ES module import maps
- Create scene, perspective camera, WebGL renderer
- Add ambient + directional lighting
- OrbitControls for camera (drag to rotate, scroll to zoom)
- Grid helper on the ground plane for spatial reference

#### 4c: Voxel Grid Data Structure
- `VoxelGrid` class backed by a `Map` using string keys (`"x,y,z"`)
- Methods: `set(x,y,z)`, `remove(x,y,z)`, `has(x,y,z)`, `getNeighborFaces(x,y,z)`
- Start with a single voxel at origin `(0,0,0)`
- Each voxel is 1 unit cubed

#### 4d: Marching Cubes Implementation
- Classic marching cubes with the 256-entry edge table and triangle table (Paul Bourke)
- `MarchingCubes` class:
  - Takes a scalar field function (1 inside volume, 0 outside)
  - For each cell in the bounding box of the voxel grid (with 1-cell padding):
    - Sample 8 corners of the cell
    - Look up the case in the edge table
    - Interpolate edge vertices (at isolevel 0.5)
    - Emit triangles from the triangle table
  - Returns a Three.js `BufferGeometry` with positions and computed normals
- The scalar field: for each sample point, check if the nearest voxel center is within a threshold — or use a simpler approach: each filled voxel sets its 8 surrounding grid vertices to 1.0
- Smooth normals computed per-vertex by averaging face normals

#### 4e: Interaction — Adding/Removing Voxels
- **Ghost voxels for placement**: Raycaster against the marching cubes mesh to find the hit face
  - From the hit face normal + position, determine which adjacent empty cell the user is pointing at
  - Show a translucent wireframe "ghost cube" at that position as preview
- **Left-click**: Add voxel at ghost position → regenerate mesh
- **Right-click**: Remove the voxel under the cursor → regenerate mesh
- Context menu suppressed on the canvas

#### 4f: Visual Polish
- Material: `MeshStandardMaterial` with a slight metallic/roughness look
- Wireframe overlay toggle (renders mesh edges as `LineSegments`)
- Voxel wireframe mode: optionally show the raw voxel grid as transparent outlines
- Smooth animation: no lag on regeneration (marching cubes over small grids is fast)
- Ground shadow / ambient occlusion if performance allows

#### 4g: HUD & Controls
- Top-left overlay: "Dual Contour - Marching Cubes Editor"
- Bottom bar: control hints ("LMB: Add | RMB: Remove | Scroll: Zoom | Drag: Orbit")
- Buttons: [Reset] [Toggle Wireframe] [Toggle Voxel Grid]

### Step 5: Add a gallery icon for the new app

In `build.py`, add a `GAME_ICONS` entry for `"dual-contour"` — an SVG showing a 3D cube/mesh motif.

### Step 6: Build & Verify

- Run `python3 build/build.py` to ensure the build succeeds
- Verify `docs/dual-contour/` is generated correctly
- Verify the gallery index shows the new card

### Step 7: Commit & Push

- Commit all changes with a descriptive message
- Push to `claude/dual-contour-marching-cubes-uSUwh`

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `build/build.py` | Edit | Add custom HTML game support in discover/build + add icon |
| `games/dual-contour/meta.json` | Create | Metadata for gallery card |
| `games/dual-contour/index.html` | Create | The marching cubes app (~800-1200 lines) |

---

## Key Technical Decisions

1. **Marching Cubes over Dual Contouring**: MC is simpler to implement, produces the continuous mesh the user wants, and works well for axis-aligned voxels. True dual contouring requires hermite data (normals at edge intersections) which adds complexity without clear benefit for cubic voxels.

2. **Scalar field approach**: Each filled voxel sets its 8 corner vertices to 1.0 in the field. The marching cubes isolevel is 0.5. This naturally produces a smooth shell around the volume that bridges between adjacent cubes.

3. **Single HTML file**: Matches the project convention. Three.js from CDN keeps it dependency-free. All marching cubes tables and logic are inline JS.

4. **Iframe embedding**: The custom app goes in `play/index.html` just like TIC-80 exports, so the existing wrapper template (with gallery nav) works unchanged.
