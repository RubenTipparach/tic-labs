# BSP and Portal Rendering on TIC-80

Companion to `software-rendering-tic-80.md`. This document covers two classic
visibility and scene-traversal techniques — **BSP trees** (as used by Doom
and Quake) and **portal rendering** (as used by the Build engine in Duke
Nukem 3D, Shadow Warrior, and Blood) — with notes on how you'd actually
implement them in TIC-80 Lua on top of `ttri`.

Sections:

1. Why BSP and portals exist
2. BSP trees: theory
3. Building a BSP tree offline
4. BSP traversal (front-to-back, back-to-front)
5. BSP on TIC-80: implementation sketch
6. Portal rendering: theory
7. Portal flood fill with recursive view frustums
8. Portals on TIC-80: implementation sketch
9. Quake: BSP + PVS + portals together
10. Which one to pick for your cart
11. Further reading

---

## 1. Why BSP and portals exist

The baseline software rasterizer from the sibling doc has a problem:
**every triangle in the world costs you CPU**, even the ones you can't see.
Even with AABB frustum culling you still pay per-object. On a Pentium 60 in
1993 — and on TIC-80 Lua in 2026 — that's a dealbreaker the moment your
level gets bigger than a single room.

Both BSP and portal rendering attack the same problem from different angles:

- **BSP trees** precompute a data structure that gives you a correct
  front-to-back (or back-to-front) traversal order for *any* camera
  position, in `O(log n)` per query. This lets you render the world
  without a depth buffer and stop as soon as the screen is full.
- **Portal rendering** exploits the fact that most indoor scenes are made
  of convex rooms connected by small openings (doors, windows). If you
  can only see room B through a narrow hole in room A's wall, then you
  only need to render the part of room B visible through that hole.

Both techniques are well suited to TIC-80 specifically because `ttri` gives
you a fast pixel filler, but the Lua side is slow — so anything that
reduces the number of triangles you have to think about per frame is a win.

---

## 2. BSP trees: theory

A **Binary Space Partitioning tree** recursively divides space into two
half-spaces using a splitting plane (3D) or line (2D). Each internal node
stores a plane; each leaf stores the geometry that lives inside that
half-space.

Invariant: **for any point in space, you can answer "is this geometry in
front of or behind the camera?" in O(log n)** by walking the tree from the
root and choosing one side at each plane.

```
            [plane P0]
           /          \
      front            back
     /     \          /     \
 [plane P1] leaf A  leaf B  [plane P2]
   /    \                    /    \
 leaf C  leaf D            leaf E  leaf F
```

Doom used 2D BSP trees over the map's line segments. Quake used full 3D
BSP trees over the level's polygons. The theory is the same.

### Why the order is correct

If the camera is in front of plane `P`, then *every* point behind `P` is
further from the camera than *every* point in front of `P`, in the half-space
sense. That's not the same as "every back-side triangle has larger z than
every front-side triangle" — the half-spaces can be at weird angles — but
for the purpose of painter's algorithm or occlusion testing, the ordering is
globally consistent with no cyclic overlaps. That's the property that makes
BSP magic.

---

## 3. Building a BSP tree offline

You **do not** build a BSP tree at runtime on TIC-80. You build it in a
Python/Node script as part of your asset pipeline and bake it into the
cart as a flat array of nodes.

Pseudocode for a 2D BSP build (Doom-style, over line segments):

```python
def build_bsp(segs):
    if not segs:
        return None
    # pick a splitter — ideally one that minimises splits and
    # keeps the tree balanced
    splitter = choose_splitter(segs)
    front, back = [], []
    for s in segs:
        if s is splitter:
            continue
        side = classify(s, splitter)
        if side == FRONT:
            front.append(s)
        elif side == BACK:
            back.append(s)
        elif side == SPANNING:
            f, b = split_seg(s, splitter)
            front.append(f)
            back.append(b)
        else:  # COINCIDENT
            front.append(s)  # convention
    return Node(
        plane = splitter.line,
        front = build_bsp(front),
        back  = build_bsp(back),
        segs  = [splitter],
    )
```

### Choosing a good splitter

This is the whole game. Bad splits mean an unbalanced tree and lots of
split segments, which bloats memory. The standard heuristic is to score
each candidate with:

```
score = abs(front_count - back_count) + split_weight * splits
```

…and pick the one with the lowest score. You don't have to try every
candidate; sampling ~10% is fine.

### Serialisation format for TIC-80

You want an array-of-structs that's cheap to walk in Lua. Something like:

```lua
bsp = {
  -- node i is at indices i*6 + 1 .. i*6 + 6
  -- plane: (nx, ny, d)
  -- children: front_index, back_index (negative = leaf)
  -- leaf: seg_start, seg_count
  nx1, ny1, d1,  front1, back1, _,
  nx2, ny2, d2,  front2, back2, _,
  ...
}
```

Two tricks:

1. Store nodes in a flat array, not Lua tables of tables. Flat array
   indexing is ~3x faster than `node.front`.
2. Use *negative* indices to mean "this is a leaf, look me up in the leaf
   array". Saves a discriminator byte.

---

## 4. BSP traversal (front-to-back, back-to-front)

Given a camera position, the traversal is a simple recursion:

```lua
local function traverse(nodeIdx, camX, camY, camZ)
  if nodeIdx < 0 then
    -- leaf: render its polygons (or queue them)
    renderLeaf(-nodeIdx)
    return
  end

  local b = nodeIdx * 6
  local nx, ny, d = bsp[b+1], bsp[b+2], bsp[b+3]
  local frontChild, backChild = bsp[b+4], bsp[b+5]

  -- signed distance from camera to plane
  local side = nx*camX + ny*camY + d  -- (+z term if 3D)

  if side >= 0 then
    -- camera is in front of the plane
    traverse(frontChild, camX, camY, camZ)  -- near
    -- splitter polygon goes here (if any)
    traverse(backChild,  camX, camY, camZ)  -- far
  else
    traverse(backChild,  camX, camY, camZ)  -- near
    traverse(frontChild, camX, camY, camZ)  -- far
  end
end
```

That's it. The two possible orderings are:

- **Front-to-back** (near child first, as above): efficient when combined
  with an occlusion structure, because you can stop as soon as the screen
  is fully covered. This is what Doom does.
- **Back-to-front** (far child first): classic painter's algorithm — no
  depth buffer needed, but you overdraw a lot. Simplest to implement on
  top of `ttri`.

For TIC-80, **back-to-front is usually the right call** unless you also
implement an occlusion buffer. `ttri` is fast enough that moderate
overdraw is fine, and you save yourself the bookkeeping.

### Doom's "implicit z-buffer"

Doom didn't have a z-buffer. Instead it kept three 1D arrays:

- `solidsegs` — ranges of screen columns already fully covered by an
  opaque wall.
- `ceilingclip[x]` / `floorclip[x]` — per-column highest drawn ceiling /
  lowest drawn floor.

Walking the BSP front-to-back, each wall clips itself against these
arrays. Once `solidsegs` covers the entire screen width, traversal stops.
This is both the visibility test and the top/bottom clipping.

On TIC-80 the same trick works if you render walls as vertical strips
(one `ttri` per column pair) and maintain 240-entry Lua arrays — but
that's only cheap if you keep the wall/floor geometry Doom-like (flat
floors, no sloped walls, uniform column height).

---

## 5. BSP on TIC-80: implementation sketch

Here's a minimal back-to-front 2D BSP renderer targeting TIC-80. Assume
the asset pipeline has produced `bsp` (node array) and `segs` (wall
segments, each with two endpoints, a texture id, top/bottom heights).

### Data layout

```lua
-- one flat node array; each node occupies 5 entries
-- [nx, ny, d, frontIdx, backIdx]
-- children: positive = internal node, negative = leaf index

local bsp = {
  0, 1, -3,   2,  -1,   -- root: plane y = 3
  1, 0,  4,  -2,  -3,   -- plane x = -4
}

-- leaves reference a contiguous range of segs
local leaves = {
  -- [first, count, floorH, ceilH, floorTex, ceilTex]
  {1, 4, 0, 4, 5, 6},
  {5, 3, 0, 5, 5, 6},
  {8, 2, 0, 4, 5, 6},
}

local segs = {
  -- {x1, z1, x2, z2, texId, uOffset, length}
  ...
}
```

### Per-frame render

```lua
local ttri, sin, cos = ttri, math.sin, math.cos
local camX, camZ, camYaw = 0, 0, 0
local cosY, sinY = 1, 0

-- project a world-space point into camera + screen space
local function project(wx, wz, wy)
  local dx, dz = wx - camX, wz - camZ
  local cx =  cosY*dx - sinY*dz   -- camera-space x
  local cz =  sinY*dx + cosY*dz   -- camera-space z (into the screen)
  if cz < 0.1 then return nil end
  local invZ = 1 / cz
  local sx = 120 + cx * 150 * invZ
  local sy = 68  - wy * 150 * invZ
  return sx, sy, invZ
end

local function drawSeg(seg, floorH, ceilH)
  local x1, z1, x2, z2, tex, uOff, len = unpack(seg)
  local ax, ay, a_iz = project(x1, z1, ceilH)
  local bx, by, b_iz = project(x2, z2, ceilH)
  local cx, cy, c_iz = project(x2, z2, floorH)
  local dx, dy, d_iz = project(x1, z1, floorH)
  if not (ax and bx and cx and dx) then return end -- TODO: near clip

  local u0, u1 = uOff, uOff + len
  local v0, v1 = 0, (ceilH - floorH) * 8

  -- two tris; pass 1/z as the z arg so ttri does perspective-correct UVs
  ttri(ax,ay, bx,by, cx,cy,  u0,v0, u1,v0, u1,v1,  0, -1,  a_iz, b_iz, c_iz)
  ttri(ax,ay, cx,cy, dx,dy,  u0,v0, u1,v1, u0,v1,  0, -1,  a_iz, c_iz, d_iz)
end

local function renderLeaf(leafIdx)
  local L = leaves[leafIdx]
  local first, count, fH, cH = L[1], L[2], L[3], L[4]
  for i = first, first + count - 1 do
    drawSeg(segs[i], fH, cH)
  end
end

local function traverse(nodeIdx)
  if nodeIdx < 0 then renderLeaf(-nodeIdx) return end
  local b = nodeIdx * 5
  local nx, ny, d = bsp[b+1], bsp[b+2], bsp[b+3]
  local front, back = bsp[b+4], bsp[b+5]
  local side = nx*camX + ny*camZ + d
  if side >= 0 then
    traverse(back)    -- far first (back-to-front / painter's)
    traverse(front)
  else
    traverse(front)
    traverse(back)
  end
end

function TIC()
  cls(0)
  cosY, sinY = cos(camYaw), sin(camYaw)
  traverse(0)
end
```

### Notes

- This is back-to-front. If you want front-to-back, swap the `traverse`
  order and add a 240-entry `solidsegs`-style occlusion array.
- Real code needs near-plane clipping; I stubbed it with `return` above.
  See `software-rendering-tic-80.md` §4 for the clip equations.
- Recursion depth of a balanced BSP over a Doom-sized level is under ~16
  — well within Lua's stack, no need to unroll to an explicit stack.
- Keep `bsp` and `segs` as flat numeric arrays. Every `node.front` style
  access is a hash hit.

Sources:
- [Fabien Sanglard — Doom engine code review](https://fabiensanglard.net/doomIphone/doomClassicRenderer.php)
- [twobithistory — DOOM's BSP trees](https://twobithistory.org/2019/11/06/doom-bsp.html)
- [Introduction to the Doom Repository — BSP traversal](https://bookdown.org/robertness/doom_tour/7_4_rendering_bsp_traversal.html)
- [Michael Abrash — Graphics Programming Black Book, ch. 59](http://www.phatcode.net/res/224/files/html/ch59/59-02.html)

---

## 6. Portal rendering: theory

Portal rendering takes a completely different approach. Instead of
precomputing a tree over the whole world, you model the level as a graph
of **sectors** (convex rooms) connected by **portals** (the shared edges
between rooms).

```
+--------+         +--------+
|  room  |  portal |  room  |
|   A    |==X==Y==>|   B    |
|        |         |        |
+--------+         +--------+
```

### Key insight

If the camera is in room A, you render room A. When you hit a portal
edge, you don't draw a wall — instead you **recurse into room B**, but
with the view frustum clipped down to the shape of the portal as
projected on screen. Anything in room B that falls outside that clipped
frustum is invisible and isn't drawn.

Because the clipped frustum only gets smaller as you recurse deeper, the
algorithm terminates quickly in practice: you bail out of a branch the
moment the clipped frustum is empty.

### Properties vs BSP

| | BSP | Portals |
|--|--|--|
| Precompute | expensive (build tree) | trivial (author sectors) |
| Works with moving geometry | no (static world) | yes (per-sector) |
| Handles non-convex rooms | yes | requires splitting into convex cells |
| Natural for indoor FPS | Doom/Quake | Duke3D / Blood / Shadow Warrior |
| Pairs well with PVS | yes | yes |
| TIC-80 Lua friendliness | good (flat array, simple recursion) | very good (can be 100% 2D math) |

Sources:
- [Fabien Sanglard — Build engine internals](https://fabiensanglard.net/duke3d/build_engine_internals.php)
- [Build (game engine) — Wikipedia](https://en.wikipedia.org/wiki/Build_(game_engine))

---

## 7. Portal flood fill with recursive view frustums

The core algorithm is dead simple:

```text
render(currentSector, frustum):
    for each wall in currentSector:
        wall_screen = project(wall)
        wall_screen = clip(wall_screen, frustum)
        if wall_screen is empty: continue
        if wall is a portal:
            newFrustum = frustum ∩ wall_screen
            render(wall.nextSector, newFrustum)
        else:
            drawWall(wall_screen)
    drawFloor(currentSector, frustum)
    drawCeiling(currentSector, frustum)
    drawSprites(currentSector, frustum)
```

### Representing the frustum

For a Doom/Build-style engine with only yaw rotation and vertical walls,
the frustum is really just a **2D angular wedge** — two rays from the
camera position spreading out to the left and right of the view. You can
represent it as two screen-X bounds `[xMin, xMax]` plus two world-space
rays `(leftAngle, rightAngle)`, or equivalently just `[xMin, xMax]` if
you do all clipping in screen space after the perspective divide.

Recursing into a portal becomes:

```lua
local function recurse(sector, xMin, xMax)
  if xMin >= xMax then return end
  for _, wall in ipairs(sector.walls) do
    local sx1, sx2 = projectWall(wall)       -- screen-x of both endpoints
    if sx1 < sx2 then  -- wall facing us (CCW convention)
      local cx1 = max(sx1, xMin)
      local cx2 = min(sx2, xMax)
      if cx1 < cx2 then
        if wall.portal then
          recurse(wall.portal, cx1, cx2)      -- shrink frustum to portal
        else
          drawWallCols(wall, cx1, cx2)
        end
      end
    end
  end
end
```

### Infinite-loop protection

If two rooms see each other through mirrored portals, a naive recursion
will loop forever. Standard fixes:

- **Visited set per frame**: tag each sector with a frame counter; skip
  already-visited sectors.
- **Max recursion depth**: hard cap of ~16 is plenty for any reasonable
  level.
- **Empty-frustum early out**: the natural base case. The recursion
  terminates automatically when the clipped frustum collapses.

In practice you want both the visited-set and depth cap for safety.

### Why this is fast

Every recursion step monotonically shrinks `[xMin, xMax]` inside its
subtree. After a few portal hops the range is tiny, so very few walls
pass the clip test. On a Build-era PC this achieved visibility in O(what
you can actually see), not O(world size) — and the same asymptotic win
applies to TIC-80.

---

## 8. Portals on TIC-80: implementation sketch

A minimal sector/portal renderer using `ttri`. This deliberately mirrors
the Build engine's shape: convex sectors with flat floors/ceilings, walls
that are quads, portals that are walls marked with a `nextSector`.

### Data model

```lua
-- Each sector is a convex polygon with a floor/ceiling height
-- and an ordered list of walls (CCW).
local sectors = {
  -- sector 1
  {
    floorH = 0, ceilH = 4,
    floorTex = 5, ceilTex = 6,
    walls = {
      { x1=-4, z1=-4, x2= 4, z2=-4, tex=1 },
      { x1= 4, z1=-4, x2= 4, z2= 4, tex=1, portal=2 },  -- portal to sector 2
      { x1= 4, z1= 4, x2=-4, z2= 4, tex=1 },
      { x1=-4, z1= 4, x2=-4, z2=-4, tex=1 },
    },
  },
  -- sector 2
  { floorH = -1, ceilH = 5, floorTex = 7, ceilTex = 6, walls = { ... } },
}
```

### Main loop

```lua
local cam = { x = 0, z = 0, y = 1.6, yaw = 0, sector = 1 }
local visitFrame = {}  -- sector -> last frame visited
local frame = 0

local sin, cos, ttri = math.sin, math.cos, ttri

local function rotToCam(wx, wz)
  local dx, dz = wx - cam.x, wz - cam.z
  local c, s = cos(cam.yaw), sin(cam.yaw)
  return c*dx - s*dz, s*dx + c*dz  -- (camX, camZ), camZ points forward
end

-- Project a world point onto the screen. Returns sx, sy, invZ or nil.
local function project(wx, wz, wy)
  local cx, cz = rotToCam(wx, wz)
  if cz < 0.1 then return nil end       -- behind near plane
  local invZ = 1 / cz
  local sx = 120 + cx * 150 * invZ
  local sy = 68 -  (wy - cam.y) * 150 * invZ
  return sx, sy, invZ
end

local function clipWallToNear(a, b)
  -- a, b are {x, z} in camera space. Clip so that cz >= 0.1.
  local near = 0.1
  if a.z >= near and b.z >= near then return a, b end
  if a.z <  near and b.z <  near then return nil end
  local t = (near - a.z) / (b.z - a.z)
  local nx = a.x + t * (b.x - a.x)
  local new = { x = nx, z = near }
  if a.z < near then return new, b else return a, new end
end

local function renderSector(sectorId, xMin, xMax, depth)
  if depth > 16 then return end
  if xMin >= xMax then return end
  if visitFrame[sectorId] == frame then return end
  visitFrame[sectorId] = frame

  local S = sectors[sectorId]
  local fH, cH = S.floorH, S.ceilH

  for _, w in ipairs(S.walls) do
    -- transform wall endpoints into camera space
    local a = { x = 0, z = 0 }
    local b = { x = 0, z = 0 }
    a.x, a.z = rotToCam(w.x1, w.z1)
    b.x, b.z = rotToCam(w.x2, w.z2)

    -- backface: skip walls whose CCW order faces away
    if a.x*b.z - a.z*b.x > 0 then goto continue end

    -- near-plane clip
    local ca, cb = clipWallToNear(a, b)
    if not ca then goto continue end

    -- project to screen
    local invZa = 1 / ca.z
    local invZb = 1 / cb.z
    local sxa = 120 + ca.x * 150 * invZa
    local sxb = 120 + cb.x * 150 * invZb
    if sxa >= sxb then goto continue end

    -- clip against our inherited frustum column range
    local cx1 = math.max(sxa, xMin)
    local cx2 = math.min(sxb, xMax)
    if cx1 >= cx2 then goto continue end

    if w.portal then
      -- recurse with the shrunken frustum
      renderSector(w.portal, cx1, cx2, depth + 1)
    else
      -- opaque wall: compute top/bottom screen y at both ends
      local syTopA = 68 - (cH - cam.y) * 150 * invZa
      local syBotA = 68 - (fH - cam.y) * 150 * invZa
      local syTopB = 68 - (cH - cam.y) * 150 * invZb
      local syBotB = 68 - (fH - cam.y) * 150 * invZb
      local u0, u1 = 0, 32
      local v0, v1 = 0, 32
      ttri(sxa,syTopA, sxb,syTopB, sxb,syBotB,
           u0,v0, u1,v0, u1,v1,
           0, -1, invZa, invZb, invZb)
      ttri(sxa,syTopA, sxb,syBotB, sxa,syBotA,
           u0,v0, u1,v1, u0,v1,
           0, -1, invZa, invZb, invZa)
    end
    ::continue::
  end

  -- TODO: floors and ceilings. The standard trick is to flood-fill each
  -- remaining column of the frustum with a horizontal span at the right
  -- depth. For a very simple renderer, just draw a big ttri per sector
  -- along the floor/ceiling plane and rely on ttri's clipping.
end

function TIC()
  frame = frame + 1
  cls(0)
  renderSector(cam.sector, 0, 240, 0)
end
```

### Design notes

- **`xMin, xMax` is the "clipped frustum".** Because portals only restrict
  horizontal visibility in a Build-style engine (no slopes, no vertical
  portals), the frustum reduces to a screen-column interval. For full 3D
  portals you'd pass a 4D polygon instead — much more code.
- **The player's current sector** is tracked explicitly. When the player
  walks through a portal, update `cam.sector`. Detecting portal crossings
  is cheap: each frame, test the player's 2D position against each wall
  of the current sector and flip sector when it crosses a portal.
- **Floors and ceilings** are the tricky part of a real portal engine.
  The Build engine uses per-column `umost`/`dmost` arrays (see §4). A
  much simpler TIC-80 approach is to draw the floor and ceiling as a
  single big `ttri` covering the sector's 2D bounds — overdraw is fine at
  240x136, and the per-column bookkeeping in Lua would eat the savings.
- **Keep sectors convex.** If an author draws a concave room, split it
  into convex pieces at asset-bake time with shared portals on the split
  line. This is what Build's editor does.
- **Avoid tables per wall per frame.** The `a = { x=..., z=... }` in the
  sketch above is bait. In real code, use two pre-allocated scratch
  tables or four locals.

Sources:
- [Fabien Sanglard — Build engine internals](https://fabiensanglard.net/duke3d/build_engine_internals.php)
- [Creating Portals from BSP Trees](https://violentcat.github.io/cplusplus/rendering/2020/06/17/portal-render.html)
- [LearnWebGL — hidden surface removal](http://learnwebgl.brown37.net/11_advanced_rendering/hidden_surface_removal.html)

---

## 9. Quake: BSP + PVS + portals together

Quake famously combined all three ideas. It's worth understanding because
it's the "canonical" take and because you can cherry-pick pieces for
TIC-80.

### The pipeline

1. **Offline: build a 3D BSP** over all level brushes. Leaves are convex
   volumes.
2. **Offline: find portals between leaves.** A portal is a polygon on a
   BSP split plane whose two sides belong to different leaves. The tool
   does a flood-fill starting from each leaf through portals.
3. **Offline: compute the PVS (Potentially Visible Set).** For every
   leaf, store a bitmask of which other leaves are potentially visible
   from any point inside it. This is the `LEAF_MARK_VIS` step in qvis,
   and it's the expensive one — it takes hours for large levels because
   it tests every portal-to-portal line of sight.
4. **Runtime: find the leaf containing the camera** by walking the BSP
   (`O(log n)`).
5. **Runtime: union the PVS bits** to get candidate leaves.
6. **Runtime: for each candidate leaf, frustum-cull its bounding box**
   against the camera frustum.
7. **Runtime: render the surviving polygons** sorted front-to-back via
   BSP traversal, with a real z-buffer.

### What you can steal for TIC-80

- **The BSP tree for ordering.** Absolutely worth it — gives you a
  correct draw order with ~16 node comparisons per frame.
- **Portals for sector-to-sector visibility.** Worth it if your levels
  are indoor.
- **The PVS.** Probably *not* worth it — the storage cost (bitmask per
  leaf) is real, and qvis-style flood-fill visibility is expensive to
  precompute and complex to author. Unless you're shipping a single
  Half-Life sized level in a TIC-80 cart, portal recursion at runtime
  will out-compete PVS.

Sources:
- [Michael Abrash — Quake's 3-D Engine: The Big Picture](https://www.bluesnews.com/abrash/chap64.shtml)
- [id Software — Quake source code](https://github.com/id-Software/Quake)
- [qvis / qbsp toolchain](https://ericwa.github.io/ericw-tools/)

---

## 10. Which one to pick for your cart

A decision table based on what you're actually building:

| Scenario | Pick |
|--|--|
| Open outdoor terrain, mostly visible at once | Neither — use section-3 frustum cull + back-to-front sort |
| Single small indoor level, static | Back-to-front BSP over 2D walls |
| Multi-room indoor level with doors/windows | Portals |
| Non-Euclidean or moving geometry (Antichamber-style) | Portals — they handle this naturally |
| Dozens of rooms with long sightlines | BSP + portals (Quake-lite) |
| You want Doom's exact "feel" | BSP with Doom's `solidsegs`/`ceilingclip` trick |
| You want Duke3D's exact feel (room-over-room, slopes) | Portals |

My rough recommendation for a typical TIC-80 3D cart:

1. **Start with back-to-front BSP.** Simplest to get right. You write an
   offline script, bake a flat node array, recurse on traversal. The
   whole renderer is under 100 lines of Lua.
2. **If your levels are indoor and grow beyond ~500 walls**, add portals
   on top of the BSP: leaves become sectors, and wall edges between
   leaves become portals. Use portal recursion for visibility, BSP for
   the static geometry inside each portal-visible sector.
3. **Don't bother with PVS.** Runtime portal flood-fill is fast enough.

### Memory budget reality check

TIC-80 carts have 64 KB of Lua code and up to 256 KB of compressed data.
Rough rules of thumb:

- A 2D BSP node (5 floats) packed into 5 numbers per node: ~200 bytes per
  node at Lua overhead, so ~1000 nodes fits in 200 KB of data. In
  practice you want fewer.
- A sector with ~10 walls costs ~500 bytes of Lua table storage; 100
  sectors is ~50 KB — tight but fine.
- Store geometry as packed number strings and `string.unpack` at startup
  if you need more density.

---

## 11. Further reading

### BSP trees

- [twobithistory — How much of a genius-level move was using BSP in Doom?](https://twobithistory.org/2019/11/06/doom-bsp.html)
- [Fabien Sanglard — Doom Classic Renderer](https://fabiensanglard.net/doomIphone/doomClassicRenderer.php)
- [Michael Abrash — Graphics Programming Black Book, ch. 59 "The Idea of BSP Trees"](http://www.phatcode.net/res/224/files/html/ch59/59-02.html)
- [BSP Tree FAQ (Berkeley)](https://people.eecs.berkeley.edu/~jrs/274s19/bsptreefaq.html)
- [Binary Space Partitioning — Wikipedia](https://en.wikipedia.org/wiki/Binary_space_partitioning)
- [Introduction to the Doom Repository — BSP traversal](https://bookdown.org/robertness/doom_tour/7_4_rendering_bsp_traversal.html)
- [Kinda Technical — Understanding the BSP Tree in DOOM](https://kindatechnical.com/doom-source-code-walkthrough/understanding-the-bsp-tree.html)

### Portals

- [Fabien Sanglard — Build engine internals (Duke Nukem 3D)](https://fabiensanglard.net/duke3d/build_engine_internals.php)
- [Build engine — Wikipedia](https://en.wikipedia.org/wiki/Build_(game_engine))
- [Creating Portals from BSP Trees](https://violentcat.github.io/cplusplus/rendering/2020/06/17/portal-render.html)
- [Game Developer — Occlusion Culling Algorithms](https://www.gamedeveloper.com/programming/occlusion-culling-algorithms)

### Visibility more generally

- [Hidden-surface determination — Wikipedia](https://en.wikipedia.org/wiki/Hidden-surface_determination)
- [LearnWebGL — Hidden surface removal](http://learnwebgl.brown37.net/11_advanced_rendering/hidden_surface_removal.html)
- [GameDev.net — Geometry Culling in 3D Engines](https://www.gamedev.net/tutorials/_technical/graphics-programming-and-theory/geometry-culling-in-3d-engines-r1212/)

### Quake / combined techniques

- [Michael Abrash — Quake's 3-D Engine: The Big Picture (Chapter 64)](https://www.bluesnews.com/abrash/chap64.shtml)
- [id Software — Quake source on GitHub](https://github.com/id-Software/Quake)
- [qvis / qbsp toolchain docs](https://ericwa.github.io/ericw-tools/)

### Companion doc

- `software-rendering-tic-80.md` — the baseline pipeline this document
  assumes: `ttri`, projection, clipping, rasterization, depth.

