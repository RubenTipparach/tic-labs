-- title:  DOLM
-- author: tic-labs
-- desc:   Portal-rendered FPS demo with procedural textures
-- script: lua

-- ==================================================================
-- DOLM
--
-- A small Doom-alike exercising the portal rendering technique
-- described in bsp-and-portal-rendering-tic-80.md. Four convex sectors
-- connected by portals, walls drawn with perspective-correct ttri
-- sampling from procedurally-generated textures that are written into
-- TIC-80 tile RAM at boot.
-- ==================================================================

local W, H   = 240, 136
local HW, HH = 120, 68
local FOCAL  = 120
local NEAR   = 0.2

local sin, cos, sqrt  = math.sin, math.cos, math.sqrt
local floor, abs, max = math.floor, math.abs, math.max
local minF, maxF      = math.min, math.max
local rand            = math.random

-- ------------------------------------------------------------------
-- Procedural texture generation
-- ------------------------------------------------------------------
-- TIC-80 tile RAM:
--   bytes  0x04000 .. 0x05FFF   (8192 bytes, 4bpp)
--   layout 16x16 tiles of 8x8 pixels = 128x128 pixel image
--
-- poke4 uses a nibble address: tile ram starts at nibble 0x08000.
-- We pack four 32x32 textures into the top-left 64x64 of the sheet:
--
--   tex 0: brick  at (u=0,v=0)   tex 1: metal at (u=32,v=0)
--   tex 2: stone  at (u=0,v=32)  tex 3: tech  at (u=32,v=32)

local function putPix(px, py, c)
  local tx = px // 8
  local ty = py // 8
  local sx = px & 7
  local sy = py & 7
  local tileIdx = ty * 16 + tx
  -- nibble address = 0x08000 + tile*64 + sy*8 + sx
  poke4(0x08000 + tileIdx * 64 + sy * 8 + sx, c)
end

local function genBrick(ox, oy)
  for py = 0, 31 do
    for px = 0, 31 do
      local row = py // 4
      local offset = (row & 1) * 4
      local bx = (px + offset) & 7
      local by = py & 3
      local c = 2  -- mortar red
      if bx == 0 or by == 0 then
        c = 1  -- grout (dark)
      end
      -- speckles and worn corners
      if rand(0, 22) == 0 then c = 3 end
      if (bx == 7 or bx == 6) and by == 3 then c = 1 end
      putPix(ox + px, oy + py, c)
    end
  end
end

local function genMetal(ox, oy)
  for py = 0, 31 do
    for px = 0, 31 do
      local c = 13                            -- base grey
      if ((px + py) & 1) == 0 then c = 14 end -- subtle checker
      -- panel outline
      if px == 0 or px == 31 or py == 0 or py == 31 then c = 15 end
      -- rivets
      if (px == 3 or px == 28) and (py == 3 or py == 28) then c = 12 end
      -- horizontal highlight
      if py == 16 then c = 14 end
      putPix(ox + px, oy + py, c)
    end
  end
end

local function genStone(ox, oy)
  for py = 0, 31 do
    for px = 0, 31 do
      local n = rand(0, 3)
      local c
      if n == 0 then c = 14
      elseif n == 1 then c = 13
      elseif n == 2 then c = 12
      else c = 13 end
      -- cracks
      if py == 10 and px > 4 and px < 22 then c = 0 end
      if px == 17 and py > 11 and py < 26 then c = 0 end
      if py == 22 and px > 17 and px < 28 then c = 0 end
      putPix(ox + px, oy + py, c)
    end
  end
end

local function genTech(ox, oy)
  for py = 0, 31 do
    for px = 0, 31 do
      local c = 9                        -- dark blue base
      if (px & 7) == 0 or (py & 7) == 0 then c = 10 end  -- grid lines
      if (px & 7) == 4 and (py & 7) == 4 then c = 11 end -- panel lights
      -- diagonal band near the top
      if py < 3 then c = 10 end
      if py == 3 then c = 11 end
      putPix(ox + px, oy + py, c)
    end
  end
end

local function genTextures()
  math.randomseed(7)
  genBrick(0, 0)
  genMetal(32, 0)
  genStone(0, 32)
  genTech(32, 32)
end

-- Texture descriptors: base UV and size in tile-space pixels.
local TEX = {
  brick = { u=0,  v=0,  w=32, h=32 },
  metal = { u=32, v=0,  w=32, h=32 },
  stone = { u=0,  v=32, w=32, h=32 },
  tech  = { u=32, v=32, w=32, h=32 },
}

-- ------------------------------------------------------------------
-- Level: four convex sectors joined by portals
-- ------------------------------------------------------------------
--
-- Top-down layout, axis-aligned rectangles aligned along +Z so that
-- the player walks forward through a chain of rooms separated by
-- portal doorways. All sectors share floor (y=0) and ceiling (y=8)
-- heights — mismatched heights would require Doom-style per-column
-- top/bottom occlusion arrays, outside the scope of this demo.
--
--     Z=52  +-----------+  sector 4 (wide hall)
--           |           |
--     Z=32  +---+  *  +-+--+
--               |  s3 |   <- corridor
--     Z=20  +---+-----+---+
--           |   |  *  |
--           | sector 2|    <- main hall
--     Z= 8  +---+  *  +--+
--               |  s1 |    <- start closet
--     Z= 0  +---+-----+
--               0     4
--
-- Walls are listed CCW when viewed from above (interior on the left
-- of each wall direction). Walls with a `portal` field are two-way
-- connections to that sector; each portal appears as a reversed-
-- winding pair in the two sectors it connects.
local sectors = {
  -- sector 1: start closet  [0..4] x [0..8]
  {
    id = 1,
    floorH = 0, ceilH = 8,
    floorTex = "stone", ceilTex = "metal",
    walls = {
      { x1=0, z1=0, x2=4, z2=0, tex="brick" },  -- south (behind player)
      { x1=4, z1=0, x2=4, z2=8, tex="brick" },  -- east
      { x1=4, z1=8, x2=0, z2=8, tex="brick", portal=2 },  -- north PORTAL
      { x1=0, z1=8, x2=0, z2=0, tex="brick" },  -- west
    },
  },
  -- sector 2: main hall  [-4..8] x [8..20]
  {
    id = 2,
    floorH = 0, ceilH = 8,
    floorTex = "metal", ceilTex = "stone",
    walls = {
      { x1=-4, z1=8,  x2=0,  z2=8,  tex="stone" },  -- south-west
      { x1=0,  z1=8,  x2=4,  z2=8,  tex="stone", portal=1 },  -- PORTAL s1
      { x1=4,  z1=8,  x2=8,  z2=8,  tex="stone" },  -- south-east
      { x1=8,  z1=8,  x2=8,  z2=20, tex="stone" },  -- east
      { x1=8,  z1=20, x2=4,  z2=20, tex="stone" },  -- north-east
      { x1=4,  z1=20, x2=0,  z2=20, tex="stone", portal=3 },  -- PORTAL s3
      { x1=0,  z1=20, x2=-4, z2=20, tex="stone" },  -- north-west
      { x1=-4, z1=20, x2=-4, z2=8,  tex="stone" },  -- west
    },
  },
  -- sector 3: corridor  [0..4] x [20..32]
  {
    id = 3,
    floorH = 0, ceilH = 8,
    floorTex = "tech", ceilTex = "tech",
    walls = {
      { x1=0, z1=20, x2=4, z2=20, tex="tech", portal=2 },  -- PORTAL s2
      { x1=4, z1=20, x2=4, z2=32, tex="tech" },  -- east
      { x1=4, z1=32, x2=0, z2=32, tex="tech", portal=4 },  -- PORTAL s4
      { x1=0, z1=32, x2=0, z2=20, tex="tech" },  -- west
    },
  },
  -- sector 4: big end hall  [-8..12] x [32..52]
  {
    id = 4,
    floorH = 0, ceilH = 8,
    floorTex = "metal", ceilTex = "stone",
    walls = {
      { x1=-8, z1=32, x2=0,  z2=32, tex="stone" },  -- south-west
      { x1=0,  z1=32, x2=4,  z2=32, tex="stone", portal=3 },  -- PORTAL s3
      { x1=4,  z1=32, x2=12, z2=32, tex="stone" },  -- south-east
      { x1=12, z1=32, x2=12, z2=52, tex="stone" },  -- east
      { x1=12, z1=52, x2=-8, z2=52, tex="stone" },  -- north
      { x1=-8, z1=52, x2=-8, z2=32, tex="stone" },  -- west
    },
  },
}

-- ------------------------------------------------------------------
-- Player / camera
-- ------------------------------------------------------------------
local cam = {
  x      = 2,
  z      = 3,
  y      = 3.2,    -- eye height above floor (floors at y=0, ceilings at y=8)
  yaw    = 0,
  sector = 1,
}

-- cheap test whether (x,z) lies inside a convex sector polygon
local function pointInSector(sid, px, pz)
  local S = sectors[sid]
  for _, w in ipairs(S.walls) do
    local dx = w.x2 - w.x1
    local dz = w.z2 - w.z1
    local rx = px  - w.x1
    local rz = pz  - w.z1
    -- CCW interior test: interior is to the LEFT of wall direction
    if dx * rz - dz * rx < 0 then return false end
  end
  return true
end

local function findContainingSector(px, pz, hint)
  if pointInSector(hint, px, pz) then return hint end
  for i = 1, #sectors do
    if pointInSector(i, px, pz) then return i end
  end
  return hint
end

-- ==================================================================
-- Portal-recursive renderer
-- ==================================================================
--
-- The algorithm is the one from §7 of bsp-and-portal-rendering-tic-80.md:
-- start from the player's sector, walk its walls. A wall that's a
-- portal becomes a recursive call with a tightened screen-column
-- frustum [xMin, xMax]. A non-portal wall is drawn as a textured quad.
--
-- Floors and ceilings are deliberately simple: for every visible
-- sector we draw a single triangle-fan of its outline as flat-shaded
-- untextured tris (no near-plane clip; triangles with any vertex
-- behind the near plane are skipped — this causes cheap pop-in at
-- close range, which is fine for a demo).

local visitFrame = {}
local frame      = 0

local function rotToCam(wx, wz)
  local dx = wx - cam.x
  local dz = wz - cam.z
  local c  = cos(cam.yaw)
  local s  = sin(cam.yaw)
  -- right-handed: camera +Z points forward (into the screen)
  return c*dx - s*dz, s*dx + c*dz
end

local function projX(cx, cz)
  return HW + cx * FOCAL / cz
end

local function projY(wy, cz)
  return HH - (wy - cam.y) * FOCAL / cz
end

-- Clip a 2D camera-space wall (endpoints a, b) to cz >= NEAR.
-- Returns (ax, az, bx, bz) or nil if wholly behind the near plane.
local function clipWallNear(ax, az, bx, bz)
  if az >= NEAR and bz >= NEAR then return ax, az, bx, bz end
  if az <  NEAR and bz <  NEAR then return nil end
  if az < NEAR then
    local t = (NEAR - az) / (bz - az)
    ax = ax + t * (bx - ax)
    az = NEAR
  else
    local t = (NEAR - bz) / (az - bz)
    bx = bx + t * (ax - bx)
    bz = NEAR
  end
  return ax, az, bx, bz
end

-- Draw a textured wall quad using two ttri calls. Pass 1/z in the z
-- slots so ttri does perspective-correct texture interpolation and
-- depth-tests against other wall quads drawn in the same frame.
local function drawWallQuad(lx, lz, rx, rz, floorH, ceilH, texKey)
  local T = TEX[texKey]
  local ilz = 1 / lz
  local irz = 1 / rz
  local sxL = HW + lx * FOCAL * ilz
  local sxR = HW + rx * FOCAL * irz
  local syTL = HH - (ceilH  - cam.y) * FOCAL * ilz
  local syBL = HH - (floorH - cam.y) * FOCAL * ilz
  local syTR = HH - (ceilH  - cam.y) * FOCAL * irz
  local syBR = HH - (floorH - cam.y) * FOCAL * irz

  local u0, u1 = T.u, T.u + T.w
  local v0, v1 = T.v, T.v + T.h

  ttri(sxL,syTL, sxR,syTR, sxR,syBR,
       u0,v0,   u1,v0,   u1,v1,
       0, -1,
       ilz, irz, irz)
  ttri(sxL,syTL, sxR,syBR, sxL,syBL,
       u0,v0,   u1,v1,   u0,v1,
       0, -1,
       ilz, irz, ilz)
end

-- Portal frustum is just a screen-column interval [xMin, xMax].
local function renderSector(sid, xMin, xMax, depth)
  if depth > 12 then return end
  if xMin >= xMax then return end
  if visitFrame[sid] == frame then return end
  visitFrame[sid] = frame

  local S = sectors[sid]
  local fH, cH = S.floorH, S.ceilH

  -- Scissor everything we draw for this sector to the inherited
  -- frustum column range. Portal recursion will narrow it further,
  -- and we re-assert this sector's scissor after each recursive
  -- call returns.
  clip(xMin, 0, xMax - xMin, H)

  -- First pass: floor and ceiling as flat-shaded tri fans over the
  -- raw sector polygon. Drawn BEFORE walls so that wall quads can
  -- overwrite them cleanly at the seams. Since all sectors share the
  -- same floor/ceiling heights, the portal recursion order (deeper
  -- children first, then walls of the current sector on top within
  -- the scissored region) produces correct visuals.
  do
    local n = #S.walls
    local floorCol = ({stone=14, metal=13, tech=9,  brick=1})[S.floorTex] or 13
    local ceilCol  = ({stone=13, metal=14, tech=10, brick=2})[S.ceilTex]  or 13

    local px, pz, ok = {}, {}, {}
    for i = 1, n do
      local cx, cz = rotToCam(S.walls[i].x1, S.walls[i].z1)
      px[i] = cx
      pz[i] = cz
      ok[i] = cz >= NEAR
    end

    for i = 2, n - 1 do
      if ok[1] and ok[i] and ok[i+1] then
        local iz1 = 1 / pz[1]
        local iz2 = 1 / pz[i]
        local iz3 = 1 / pz[i+1]
        local fx1 = HW + px[1]   * FOCAL * iz1
        local fy1 = HH - (fH - cam.y) * FOCAL * iz1
        local fx2 = HW + px[i]   * FOCAL * iz2
        local fy2 = HH - (fH - cam.y) * FOCAL * iz2
        local fx3 = HW + px[i+1] * FOCAL * iz3
        local fy3 = HH - (fH - cam.y) * FOCAL * iz3
        tri(fx1,fy1, fx2,fy2, fx3,fy3, floorCol)

        local cy1 = HH - (cH - cam.y) * FOCAL * iz1
        local cy2 = HH - (cH - cam.y) * FOCAL * iz2
        local cy3 = HH - (cH - cam.y) * FOCAL * iz3
        tri(fx1,cy1, fx3,cy3, fx2,cy2, ceilCol)
      end
    end
  end

  -- Second pass: walls (portals recurse).
  --
  -- Sector data is authored CCW when viewed from above (interior on the
  -- left as you walk along each wall). With camera +Z forward, that CCW
  -- winding projects to screen with the wall's x1 endpoint on the right
  -- when visible — so we read x2/z2 as "a" (left on screen) and x1/z1
  -- as "b" (right on screen), which makes the cull and sxa<sxb checks
  -- agree with the projection.
  for wi = 1, #S.walls do
    local w = S.walls[wi]

    local ax, az = rotToCam(w.x2, w.z2)
    local bx, bz = rotToCam(w.x1, w.z1)

    -- Backface cull: a front-facing wall has sxa < sxb on screen,
    -- which in camera space means ax*bz - az*bx < 0.
    if ax*bz - az*bx <= 0 then
      local cax, caz, cbx, cbz = clipWallNear(ax, az, bx, bz)
      if cax then
        local sxa = HW + cax * FOCAL / caz
        local sxb = HW + cbx * FOCAL / cbz
        if sxa < sxb then
          local cx1 = maxF(sxa, xMin)
          local cx2 = minF(sxb, xMax)
          if cx1 < cx2 then
            if w.portal then
              renderSector(w.portal, cx1, cx2, depth + 1)
              -- restore this sector's scissor after the child clips it
              clip(xMin, 0, xMax - xMin, H)
            else
              drawWallQuad(cax, caz, cbx, cbz, fH, cH, w.tex)
            end
          end
        end
      end
    end
  end
end

-- ==================================================================
-- Game state / loop
-- ==================================================================

local booted = false

local function boot()
  genTextures()
  booted = true
end

local function tryMove(dx, dz)
  local nx, nz = cam.x + dx, cam.z + dz
  -- naive: accept move if new position is in any sector
  local newSid = findContainingSector(nx, nz, cam.sector)
  if pointInSector(newSid, nx, nz) then
    cam.x, cam.z = nx, nz
    cam.sector = newSid
  end
end

function TIC()
  if not booted then boot() end
  frame = frame + 1

  -- Input: arrow keys = move/turn, Z = strafe modifier
  local turnSpeed = 0.05
  local moveSpeed = 0.18

  if btn(2) then
    if btn(4) then
      -- strafe left
      tryMove(cos(cam.yaw) * -moveSpeed, sin(cam.yaw) * moveSpeed)
    else
      cam.yaw = cam.yaw - turnSpeed
    end
  end
  if btn(3) then
    if btn(4) then
      tryMove(cos(cam.yaw) * moveSpeed, sin(cam.yaw) * -moveSpeed)
    else
      cam.yaw = cam.yaw + turnSpeed
    end
  end
  if btn(0) then
    tryMove(sin(cam.yaw) * moveSpeed, cos(cam.yaw) * moveSpeed)
  end
  if btn(1) then
    tryMove(sin(cam.yaw) * -moveSpeed, cos(cam.yaw) * -moveSpeed)
  end

  -- cls(0) clears both framebuffer and ttri's depth buffer.
  cls(0)
  clip()  -- reset any scissor left over from the previous frame

  renderSector(cam.sector, 0, W, 0)

  clip()  -- reset before drawing HUD

  -- HUD
  line(HW-4, HH, HW+4, HH, 12)
  line(HW, HH-4, HW, HH+4, 12)
  pix(HW, HH, 15)

  print("SECTOR "..cam.sector, 4, 4, 12)
  print("X "..floor(cam.x).." Z "..floor(cam.z), 4, 12, 13)
  print("YAW "..floor(cam.yaw * 57 % 360), 4, 20, 13)

  -- mini map (top-right corner)
  local mmx, mmy, mms = W - 52, 4, 0.8
  rectb(mmx-1, mmy-1, 50, 50, 13)
  for si = 1, #sectors do
    local S = sectors[si]
    for _, w in ipairs(S.walls) do
      local col = w.portal and 11 or 15
      local ax = mmx + 25 + (w.x1 - cam.x) * mms
      local ay = mmy + 25 + (w.z1 - cam.z) * mms
      local bx = mmx + 25 + (w.x2 - cam.x) * mms
      local by = mmy + 25 + (w.z2 - cam.z) * mms
      line(ax, ay, bx, by, col)
    end
  end
  -- player dot + facing
  local pfx = mmx + 25 + sin(cam.yaw) * 6
  local pfy = mmy + 25 + cos(cam.yaw) * 6
  line(mmx+25, mmy+25, pfx, pfy, 4)
  pix(mmx+25, mmy+25, 4)
end
