-- title:  Void Runner
-- author: tic-labs
-- desc:   Flat-shaded 3D space sim (software rasterizer test)
-- script: lua

-- ==================================================================
-- Void Runner
--
-- A tiny flat-shaded 3D space sim used as a test bed for the general
-- rasterizer notes in software-rendering-tic-80.md. No textures: every
-- polygon is a solid TIC-80 tri() call shaded against a fixed light
-- direction, with brightness quantized into 4-step palette ramps so
-- shadows get the banded / dithered retro look.
-- ==================================================================

local W, H     = 240, 136
local HW, HH   = 120, 68
local FOCAL    = 110        -- focal length in pixels
local NEAR     = 1.0

-- Localize hot math for speed
local sin, cos, sqrt = math.sin, math.cos, math.sqrt
local floor, abs     = math.floor, math.abs
local rand           = math.random

-- ------------------------------------------------------------------
-- Palette ramps
-- ------------------------------------------------------------------
-- Each ramp is dark -> light. Quantized flat shading picks one of
-- four indices per triangle, giving the characteristic "dithered
-- shadow" look without actually stippling pixels.
local HULL_RAMP = { 1, 2, 3, 15 }   -- crimson -> white
local ROCK_RAMP = { 0, 14, 13, 12 } -- black -> light grey
local GOLD_RAMP = { 2, 3, 4, 15 }   -- red -> yellow -> white
local LIME_RAMP = { 7, 6, 5, 15 }   -- dk green -> lime -> white

-- Light direction in world space (points toward surfaces)
local LX, LY, LZ = -0.5, -0.7, -0.5
do
  local l = sqrt(LX*LX + LY*LY + LZ*LZ)
  LX, LY, LZ = LX/l, LY/l, LZ/l
end

-- ------------------------------------------------------------------
-- Meshes
-- ------------------------------------------------------------------
-- Each mesh is { verts = {{x,y,z}, ...}, faces = {{i,j,k, ramp}, ...} }
-- Winding is CCW when viewed from outside (right-handed, -z forward).

local function makeOcta(r, ramp)
  -- 8-face octahedron used as "asteroid"
  return {
    verts = {
      { r*1.0, 0,      0},
      {-r*0.9, 0,      0},
      { 0,  r*1.1,     0},
      { 0, -r*0.95,    0},
      { 0,  0,     r*1.2},
      { 0,  0,    -r*0.9},
    },
    faces = {
      {1,3,5,ramp},{3,2,5,ramp},{2,4,5,ramp},{4,1,5,ramp},
      {3,1,6,ramp},{2,3,6,ramp},{4,2,6,ramp},{1,4,6,ramp},
    },
  }
end

-- Elongated box (mothership)
--
-- Faces wound CCW when viewed from outside the box so that the cross
-- product (v2-v1) × (v3-v1) gives the OUTWARD normal. With this
-- convention, front-facing triangles project to positive signed area
-- in screen space, which is what the backface cull in renderEntity
-- tests for.
local MOTHER
do
  local hx, hy, hz = 10, 3, 24
  -- vertex indices
  -- 1=(-,-,-)  2=(+,-,-)  3=(+,+,-)  4=(-,+,-)
  -- 5=(-,-,+)  6=(+,-,+)  7=(+,+,+)  8=(-,+,+)
  MOTHER = {
    verts = {
      {-hx,-hy,-hz},{ hx,-hy,-hz},{ hx, hy,-hz},{-hx, hy,-hz},
      {-hx,-hy, hz},{ hx,-hy, hz},{ hx, hy, hz},{-hx, hy, hz},
    },
    faces = {
      -- front  (-z)
      {1,3,2,HULL_RAMP},{1,4,3,HULL_RAMP},
      -- back   (+z)
      {6,7,8,HULL_RAMP},{6,8,5,HULL_RAMP},
      -- left   (-x)
      {1,5,8,HULL_RAMP},{1,8,4,HULL_RAMP},
      -- right  (+x)
      {2,7,6,HULL_RAMP},{2,3,7,HULL_RAMP},
      -- top    (+y)
      {4,7,3,HULL_RAMP},{4,8,7,HULL_RAMP},
      -- bottom (-y)
      {1,2,6,HULL_RAMP},{1,6,5,HULL_RAMP},
    },
  }
end

-- ------------------------------------------------------------------
-- Scene
-- ------------------------------------------------------------------
local cam = {
  x=0, y=0, z=-40, yaw=0, pitch=0,
  vx=0, vy=0, vz=0,
}

math.randomseed(1337)

local entities = {}
-- Mothership at origin
entities[#entities+1] = {
  mesh = MOTHER, x=0, y=-6, z=40,
  ry=0, spin=0.004,
}
-- Asteroid field
for i = 1, 18 do
  local r = 2 + rand() * 3
  local ring = 60 + rand() * 120
  local ang  = rand() * 6.2832
  entities[#entities+1] = {
    mesh = makeOcta(r, ROCK_RAMP),
    x = cos(ang) * ring + (rand()-0.5) * 30,
    y = (rand()-0.5) * 40,
    z = sin(ang) * ring + 60,
    ry = rand() * 6.2832,
    spin = (rand()-0.5) * 0.03,
  }
end

-- Bullets
local bullets = {}

-- Starfield (screen-space, parallax by camera yaw)
local stars = {}
for i = 1, 80 do
  stars[i] = { u = rand() * 6.2832, v = rand() * 6.2832, b = 12 + rand(0,3) }
end

-- Scratch buffers (reused each frame to avoid GC churn)
local camV    = {}
local scrV    = {}
local triQ    = {}  -- painter's-sort queue: {avgZ, x1,y1,x2,y2,x3,y3, color}
local triQLen = 0

-- ==================================================================
-- 3D math
-- ==================================================================

-- Camera-space transform: translate then yaw (Y) then pitch (X)
local function toCamera(wx, wy, wz)
  local dx = wx - cam.x
  local dy = wy - cam.y
  local dz = wz - cam.z
  local cy, sy = cos(-cam.yaw),   sin(-cam.yaw)
  local cp, sp = cos(-cam.pitch), sin(-cam.pitch)
  local x1 =  cy*dx - sy*dz
  local z1 =  sy*dx + cy*dz
  local y2 =  cp*dy - sp*z1
  local z2 =  sp*dy + cp*z1
  return x1, y2, z2
end

-- Model transform: yaw-only per entity, then translate
local function toWorld(vx, vy, vz, e)
  local cy, sy = cos(e.ry), sin(e.ry)
  return cy*vx + sy*vz + e.x, vy + e.y, -sy*vx + cy*vz + e.z
end

-- Perspective project. Returns sx, sy, 1/z or nil if behind near plane.
local function project(cx, cy, cz)
  if cz < NEAR then return nil end
  local iz = 1 / cz
  return HW + cx * FOCAL * iz, HH - cy * FOCAL * iz, iz
end

-- ==================================================================
-- Per-entity rendering
-- ==================================================================

local function renderEntity(e)
  local m = e.mesh
  local verts, faces = m.verts, m.faces
  local nv = #verts

  -- transform vertices
  for i = 1, nv do
    local v = verts[i]
    local wx, wy, wz = toWorld(v[1], v[2], v[3], e)
    local cx, cy, cz = toCamera(wx, wy, wz)
    local cvi = camV[i]
    if not cvi then cvi = {}; camV[i] = cvi end
    cvi[1], cvi[2], cvi[3] = cx, cy, cz

    local svi = scrV[i]
    if not svi then svi = {}; scrV[i] = svi end
    local sx, sy, iz = project(cx, cy, cz)
    if sx then
      svi[1], svi[2], svi[3], svi[4] = sx, sy, iz, true
    else
      svi[4] = false
    end
  end

  -- rasterize faces
  for fi = 1, #faces do
    local f = faces[fi]
    local a, b, c, ramp = f[1], f[2], f[3], f[4]
    local sa, sb, sc = scrV[a], scrV[b], scrV[c]
    if sa[4] and sb[4] and sc[4] then
      -- screen-space signed area: backface cull.
      -- With CCW-from-outside mesh winding and the projection
      -- HW + cx*FOCAL/cz, HH - cy*FOCAL/cz, front-facing triangles
      -- give positive signed area.
      local area = (sb[1]-sa[1]) * (sc[2]-sa[2])
                 - (sb[2]-sa[2]) * (sc[1]-sa[1])
      if area > 0 then
        -- flat shade using camera-space face normal
        local ca, cb, cc = camV[a], camV[b], camV[c]
        local ex, ey, ez = cb[1]-ca[1], cb[2]-ca[2], cb[3]-ca[3]
        local fx, fy, fz = cc[1]-ca[1], cc[2]-ca[2], cc[3]-ca[3]
        local nx = ey*fz - ez*fy
        local ny = ez*fx - ex*fz
        local nz = ex*fy - ey*fx
        local ln = sqrt(nx*nx + ny*ny + nz*nz)
        if ln > 0 then
          local inv = 1 / ln
          nx, ny, nz = nx*inv, ny*inv, nz*inv
          -- Light is in world space but camera only rotates; for a
          -- demo this cheat (use world L in camera frame) is fine.
          local ndotl = -(nx*LX + ny*LY + nz*LZ)
          if ndotl < 0 then ndotl = 0 end
          local si = 1 + floor(ndotl * 3.999)
          if si > 4 then si = 4 end
          local color = ramp[si]
          local avgZ = (ca[3] + cb[3] + cc[3]) * 0.3333
          triQLen = triQLen + 1
          local t = triQ[triQLen]
          if not t then t = {}; triQ[triQLen] = t end
          t[1] = avgZ
          t[2], t[3] = sa[1], sa[2]
          t[4], t[5] = sb[1], sb[2]
          t[6], t[7] = sc[1], sc[2]
          t[8] = color
        end
      end
    end
  end
end

-- ==================================================================
-- Starfield
-- ==================================================================

local function drawStars()
  -- Parallax: rotate each star's angular position by camera yaw/pitch
  local yaw, pitch = cam.yaw, cam.pitch
  for i = 1, #stars do
    local s = stars[i]
    local u = (s.u - yaw) % 6.2832
    local v = (s.v - pitch) % 6.2832
    -- map [0, 2pi) to screen with a narrow band around center
    if u > 3.1416 then u = u - 6.2832 end
    if v > 3.1416 then v = v - 6.2832 end
    if u > -1.2 and u < 1.2 and v > -0.8 and v < 0.8 then
      local sx = HW + u * 100
      local sy = HH + v * 100
      pix(sx, sy, s.b)
    end
  end
end

-- ==================================================================
-- Game state
-- ==================================================================

local score    = 0
local gameTick = 0
local fireCD   = 0

-- spawn a bullet forward from the camera
local function fire()
  if fireCD > 0 then return end
  fireCD = 8
  local fx = sin(cam.yaw) * cos(cam.pitch)
  local fy = -sin(cam.pitch)
  local fz = cos(cam.yaw) * cos(cam.pitch)
  bullets[#bullets+1] = {
    x=cam.x + fx*2, y=cam.y + fy*2, z=cam.z + fz*2,
    vx=fx*3, vy=fy*3, vz=fz*3,
    life=80,
  }
  sfx(0, 48, 8, 0, 10)
end

-- Hit test bullet vs entities (asteroids only)
local function tryHit(b)
  for i = #entities, 1, -1 do
    local e = entities[i]
    if e.mesh ~= MOTHER then
      local dx = b.x - e.x
      local dy = b.y - e.y
      local dz = b.z - e.z
      local r  = 4
      if dx*dx + dy*dy + dz*dz < r*r then
        table.remove(entities, i)
        score = score + 10
        sfx(1, 36, 16, 0, 12)
        return true
      end
    end
  end
  return false
end

local function updateBullets()
  for i = #bullets, 1, -1 do
    local b = bullets[i]
    b.x = b.x + b.vx
    b.y = b.y + b.vy
    b.z = b.z + b.vz
    b.life = b.life - 1
    if b.life <= 0 or tryHit(b) then
      table.remove(bullets, i)
    end
  end
end

local function renderBullets()
  for i = 1, #bullets do
    local b = bullets[i]
    local cx, cy, cz = toCamera(b.x, b.y, b.z)
    local sx, sy = project(cx, cy, cz)
    if sx then
      circ(sx, sy, 1, 4)
      pix(sx, sy, 15)
    end
  end
end

-- ==================================================================
-- Game loop
-- ==================================================================

function TIC()
  gameTick = gameTick + 1

  -- Input
  if btn(0) then cam.pitch = cam.pitch - 0.03 end
  if btn(1) then cam.pitch = cam.pitch + 0.03 end
  if btn(2) then cam.yaw   = cam.yaw   - 0.03 end
  if btn(3) then cam.yaw   = cam.yaw   + 0.03 end
  if cam.pitch >  1.2 then cam.pitch =  1.2 end
  if cam.pitch < -1.2 then cam.pitch = -1.2 end

  local fwdX =  sin(cam.yaw) * cos(cam.pitch)
  local fwdY = -sin(cam.pitch)
  local fwdZ =  cos(cam.yaw) * cos(cam.pitch)

  if btn(4) then
    cam.vx = cam.vx + fwdX * 0.08
    cam.vy = cam.vy + fwdY * 0.08
    cam.vz = cam.vz + fwdZ * 0.08
  end
  if btn(5) then
    cam.vx = cam.vx * 0.92
    cam.vy = cam.vy * 0.92
    cam.vz = cam.vz * 0.92
  end

  if btnp(6) then fire() end
  if fireCD > 0 then fireCD = fireCD - 1 end

  -- Speed cap
  local speed = sqrt(cam.vx*cam.vx + cam.vy*cam.vy + cam.vz*cam.vz)
  local maxS = 2.5
  if speed > maxS then
    local k = maxS / speed
    cam.vx, cam.vy, cam.vz = cam.vx*k, cam.vy*k, cam.vz*k
  end

  cam.x = cam.x + cam.vx
  cam.y = cam.y + cam.vy
  cam.z = cam.z + cam.vz

  -- Update entities
  for i = 1, #entities do
    local e = entities[i]
    e.ry = e.ry + e.spin
  end

  updateBullets()

  -- Render
  cls(0)
  drawStars()

  triQLen = 0
  for i = 1, #entities do
    renderEntity(entities[i])
  end

  -- Painter's sort back-to-front over the active slice of triQ
  local active = {}
  for i = 1, triQLen do active[i] = triQ[i] end
  table.sort(active, function(a, b) return a[1] > b[1] end)
  for i = 1, #active do
    local t = active[i]
    tri(t[2],t[3], t[4],t[5], t[6],t[7], t[8])
  end

  renderBullets()

  -- HUD
  line(HW-6, HH, HW-2, HH, 15)
  line(HW+2, HH, HW+6, HH, 15)
  line(HW, HH-6, HW, HH-2, 15)
  line(HW, HH+2, HW, HH+6, 15)

  print("SCORE "..score, 4, 4, 15)
  print("TRIS  "..triQLen, 4, 12, 13)
  print("SPD   "..floor(speed*10), 4, 20, 13)

  -- compass bar
  rect(HW-40, H-10, 80, 3, 13)
  local cx = HW + (((cam.yaw * 0.5) % 3.1416) - 1.5708) * 25
  rect(cx, H-12, 2, 7, 15)
end

-- ==================================================================
-- Sound effects (lightweight square-wave blips)
-- ==================================================================
-- TIC-80 carts normally define SFX in the <SFX> chunk; in a code-only
-- cart we don't have that chunk, so the sfx() calls above will just
-- be no-ops. That's fine — the game is visually driven.
