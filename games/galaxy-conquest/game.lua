-- title:  Galaxy Conquest
-- author: tic-labs
-- desc:   Idle galactic conquest. Click systems, dispatch admirals, salvage wrecks.
-- script: lua

-- M1: galaxy map + system view shell.
-- M2: combat sim. Fighters, bullets, planet turret, wrecks, particles.
-- M2.1: per-star simulation. Combat continues on every star, every frame,
--       even when the player is on the galaxy map. Ship counts shown on map.
-- Later milestones add economy, salvage, admirals, research, empires, save/load.

local SW, SH = 240, 136
local TOPBAR_H, BOTBAR_H = 10, 10
local MAP_Y0 = TOPBAR_H
local MAP_Y1 = SH - BOTBAR_H
local MAP_CX = SW / 2
local MAP_CY = (MAP_Y0 + MAP_Y1) / 2

-- empires: 0 neutral, 1 player, 2 pirates, 3 hegemony, 4 kingdom, 5 hivemind
local EMP_COLOR = {[0]=14, [1]=6,  [2]=8,  [3]=11, [4]=9,  [5]=2}
local EMP_NAME  = {[0]="neutral", [1]="you", [2]="pirates",
                   [3]="hegemony", [4]="star kingdom", [5]="ai hivemind"}
local EMP_PREFIX = {[1]="sol", [2]="pi", [3]="he", [4]="sk", [5]="hi"}

-- combat constants
local FIGHTER = {hp = 4, speed = 1.0, fire_cd = 26, range = 44, dmg = 1, r = 2, color = 11}
local TURRET  = {hp = 14,             fire_cd = 38, range = 64, dmg = 2, r = 3, color = 2}
local BULLET_SPEED = 2.6
local DOCK_X, DOCK_Y = 14, MAP_CY

local view = "galaxy"
local mx, my, ml, mm, mr = 0, 0, false, false, false
local ml_prev, mr_prev = false, false
local stars = {}
local sel_idx, hov_idx = nil, nil
local money, rp = 50, 0
local seed = 1
local frame = 0

-- particles are cosmetic only; spawned only for the viewed system
local particles = {}

local TAB_GX0, TAB_GX1 = 80, 130
local TAB_SX0, TAB_SX1 = 132, 182
local SPAWN_BX0, SPAWN_BY0 = 4, MAP_Y0 + 4
local SPAWN_BW, SPAWN_BH = 56, 11

local function d2(x1, y1, x2, y2)
  local dx, dy = x1 - x2, y1 - y2
  return dx * dx + dy * dy
end

local function in_rect(px, py, x0, y0, x1, y1)
  return px >= x0 and px < x1 and py >= y0 and py < y1
end

local function in_box(px, py, x, y, w, h)
  return px >= x and px < x + w and py >= y and py < y + h
end

-- ---- galaxy generation ----

local function gen_galaxy()
  math.randomseed(seed)
  stars = {}
  local minD2 = 14 * 14
  local target = 40
  local tries = 0
  while #stars < target and tries < target * 80 do
    tries = tries + 1
    local x = math.random(8, SW - 8)
    local y = math.random(MAP_Y0 + 6, MAP_Y1 - 6)
    local ok = true
    for i = 1, #stars do
      if d2(x, y, stars[i].x, stars[i].y) < minD2 then ok = false break end
    end
    if ok then
      local emp
      if x < MAP_CX and y < MAP_CY then emp = 2
      elseif x >= MAP_CX and y < MAP_CY then emp = 3
      elseif x < MAP_CX then emp = 4
      else emp = 5 end
      table.insert(stars, {
        x = x, y = y,
        empire = emp, owner = emp,
        capital = false,
        tier = math.random(1, 3),
        name = "",
        ships = {},
        bullets = {},
        wrecks = {},
        turret_hp = nil,
        turret_cd = 0,
      })
    end
  end

  local best, bd = 1, 1e9
  for i, s in ipairs(stars) do
    local d = d2(s.x, s.y, MAP_CX, MAP_CY)
    if d < bd then best, bd = i, d end
  end
  stars[best].owner = 1
  stars[best].empire = 1
  stars[best].tier = 1
  stars[best].name = "sol"
  sel_idx = best

  for emp = 2, 5 do
    local cap, cd = nil, -1
    for i, s in ipairs(stars) do
      if s.empire == emp then
        local d = d2(s.x, s.y, MAP_CX, MAP_CY)
        if d > cd then cap, cd = i, d end
      end
    end
    if cap then
      stars[cap].capital = true
      stars[cap].tier = 4
    end
  end

  for i, s in ipairs(stars) do
    if s.name == "" then
      s.name = string.format("%s%02d", EMP_PREFIX[s.empire] or "n", i)
    end
    if s.owner ~= 1 then
      local mult = s.capital and 2.5 or (s.tier * 0.7 + 0.6)
      s.turret_hp = math.floor(TURRET.hp * mult)
      s.turret_max = s.turret_hp
    end
  end
end

-- ---- combat helpers ----

local function add_particle(x, y, count, color)
  for i = 1, count do
    local a = math.random() * 6.2832
    local sp = 0.4 + math.random() * 1.4
    table.insert(particles, {
      x = x, y = y,
      vx = math.cos(a) * sp, vy = math.sin(a) * sp,
      life = 10 + math.random(0, 10),
      color = color,
    })
  end
end

local function fire_bullet(s, x, y, tx, ty, team, dmg)
  local dx, dy = tx - x, ty - y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 0.1 then d = 0.1 end
  table.insert(s.bullets, {
    x = x, y = y,
    vx = dx / d * BULLET_SPEED, vy = dy / d * BULLET_SPEED,
    team = team, dmg = dmg, life = 50,
  })
end

local function spawn_fighter(s)
  table.insert(s.ships, {
    x = DOCK_X, y = DOCK_Y + math.random(-10, 10),
    vx = 0, vy = 0,
    hp = FIGHTER.hp, max_hp = FIGHTER.hp,
    team = 1, kind = "fighter",
    fire_cd = math.random(0, 20),
    orbit_dir = math.random() < 0.5 and 1 or -1,
  })
end

local function planet_radius(s)
  return 8 + s.tier * 2
end

-- ---- view switching ----

local function set_view(v)
  if v == view then return end
  view = v
  particles = {}
end

-- ---- input ----

local function update_mouse()
  ml_prev, mr_prev = ml, mr
  mx, my, ml, mm, mr = mouse()
end

local function mclicked() return ml and not ml_prev end
local function mrclicked() return mr and not mr_prev end

local function pick_star_at(px, py)
  local best, bd = nil, 25
  for i, s in ipairs(stars) do
    local d = d2(s.x, s.y, px, py)
    if d <= bd then best, bd = i, d end
  end
  return best
end

local function update_topbar()
  if mclicked() then
    if in_rect(mx, my, TAB_GX0, 0, TAB_GX1, TOPBAR_H) then set_view("galaxy") end
    if in_rect(mx, my, TAB_SX0, 0, TAB_SX1, TOPBAR_H) then set_view("system") end
  end
end

local function update_galaxy()
  hov_idx = pick_star_at(mx, my)
  if hov_idx and my >= MAP_Y0 and my < MAP_Y1 then
    if mclicked() then sel_idx = hov_idx end
    if mrclicked() then
      sel_idx = hov_idx
      set_view("system")
    end
  end
end

-- ---- per-star combat sim ----

local function tick_ships(s, viewed)
  local px, py = MAP_CX, MAP_CY
  local pr = planet_radius(s)
  local enemy_alive = s.owner ~= 1 and (s.turret_hp or 0) > 0
  local i = 1
  while i <= #s.ships do
    local sh = s.ships[i]
    local dx, dy = px - sh.x, py - sh.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.1 then d = 0.1 end
    local approach = pr + 22
    if d > approach then
      sh.vx = dx / d * FIGHTER.speed
      sh.vy = dy / d * FIGHTER.speed
    else
      sh.vx = (-dy / d) * FIGHTER.speed * sh.orbit_dir
      sh.vy = ( dx / d) * FIGHTER.speed * sh.orbit_dir
    end
    sh.x = sh.x + sh.vx
    sh.y = sh.y + sh.vy
    if sh.x < 2 then sh.x = 2 end
    if sh.x > SW - 2 then sh.x = SW - 2 end
    if sh.y < MAP_Y0 + 2 then sh.y = MAP_Y0 + 2 end
    if sh.y > MAP_Y1 - 2 then sh.y = MAP_Y1 - 2 end

    sh.fire_cd = sh.fire_cd - 1
    if enemy_alive and sh.fire_cd <= 0 and d < FIGHTER.range then
      fire_bullet(s, sh.x, sh.y, px, py, 1, FIGHTER.dmg)
      sh.fire_cd = FIGHTER.fire_cd
    end

    if sh.hp <= 0 then
      if viewed then
        add_particle(sh.x, sh.y, 10, 8)
        add_particle(sh.x, sh.y, 4, 9)
      end
      table.insert(s.wrecks, {x = sh.x, y = sh.y})
      table.remove(s.ships, i)
    else
      i = i + 1
    end
  end
end

local function tick_turret(s)
  if s.owner == 1 or not s.turret_hp or s.turret_hp <= 0 then return end
  s.turret_cd = (s.turret_cd or 0) - 1
  if s.turret_cd > 0 then return end
  local best, bd = nil, 1e9
  for _, sh in ipairs(s.ships) do
    if sh.team == 1 then
      local d = d2(MAP_CX, MAP_CY, sh.x, sh.y)
      if d < bd then best, bd = sh, d end
    end
  end
  if best and math.sqrt(bd) <= TURRET.range then
    fire_bullet(s, MAP_CX, MAP_CY, best.x, best.y, 2, TURRET.dmg)
    s.turret_cd = TURRET.fire_cd
  end
end

local function tick_bullets(s, viewed)
  local pr2 = planet_radius(s) * planet_radius(s)
  local i = 1
  while i <= #s.bullets do
    local b = s.bullets[i]
    b.x = b.x + b.vx
    b.y = b.y + b.vy
    b.life = b.life - 1
    local hit = false
    if b.team == 1 then
      if s.owner ~= 1 and s.turret_hp and s.turret_hp > 0
         and d2(b.x, b.y, MAP_CX, MAP_CY) <= pr2 then
        s.turret_hp = s.turret_hp - b.dmg
        if viewed then add_particle(b.x, b.y, 4, 9) end
        hit = true
      end
    else
      for _, sh in ipairs(s.ships) do
        if sh.team == 1 and d2(b.x, b.y, sh.x, sh.y) <= 9 then
          sh.hp = sh.hp - b.dmg
          if viewed then add_particle(b.x, b.y, 3, 9) end
          hit = true
          break
        end
      end
    end
    if hit or b.life <= 0
       or b.x < 0 or b.x > SW
       or b.y < MAP_Y0 or b.y > MAP_Y1 then
      table.remove(s.bullets, i)
    else
      i = i + 1
    end
  end
end

local function tick_particles()
  local i = 1
  while i <= #particles do
    local p = particles[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vx = p.vx * 0.9
    p.vy = p.vy * 0.9
    p.life = p.life - 1
    if p.life <= 0 then
      table.remove(particles, i)
    else
      i = i + 1
    end
  end
end

local function tick_world()
  for i, s in ipairs(stars) do
    local viewed = (i == sel_idx and view == "system")
    if #s.ships > 0 or #s.bullets > 0 or viewed then
      tick_ships(s, viewed)
      tick_turret(s)
      tick_bullets(s, viewed)
    end
  end
  tick_particles()
end

local function update_system()
  if mclicked() and in_box(mx, my, SPAWN_BX0, SPAWN_BY0, SPAWN_BW, SPAWN_BH) then
    local s = stars[sel_idx]
    if s then spawn_fighter(s) end
  end
end

-- ---- drawing ----

local function total_player_ships()
  local n = 0
  for _, s in ipairs(stars) do
    for _, sh in ipairs(s.ships) do
      if sh.team == 1 then n = n + 1 end
    end
  end
  return n
end

local function draw_topbar()
  rect(0, 0, SW, TOPBAR_H, 0)
  print(string.format("$%d  rp:%d", money, rp), 2, 3, 9, false, 1, true)
  local g_col = view == "galaxy" and 11 or 14
  local s_col = view == "system" and 11 or 14
  rectb(TAB_GX0, 1, TAB_GX1 - TAB_GX0, TOPBAR_H - 2, g_col)
  rectb(TAB_SX0, 1, TAB_SX1 - TAB_SX0, TOPBAR_H - 2, s_col)
  print("galaxy", TAB_GX0 + 14, 3, g_col, false, 1, true)
  print("system", TAB_SX0 + 14, 3, s_col, false, 1, true)
end

local function draw_botbar()
  rect(0, SH - BOTBAR_H, SW, BOTBAR_H, 0)
  local s = stars[sel_idx]
  if s then
    local cap = s.capital and " (cap)" or ""
    print(string.format("%s  t%d  %s%s",
            s.name, s.tier, EMP_NAME[s.owner], cap),
          2, SH - BOTBAR_H + 3, EMP_COLOR[s.owner], false, 1, true)
  end
  if view == "galaxy" then
    print(string.format("active fighters: %d", total_player_ships()),
          SW - 100, SH - BOTBAR_H + 3, 11, false, 1, true)
  else
    print(string.format("ships:%d wrecks:%d", s and #s.ships or 0, s and #s.wrecks or 0),
          SW - 86, SH - BOTBAR_H + 3, 14, false, 1, true)
  end
end

local function draw_galaxy_bg()
  cls(0)
  for i = 0, 80 do
    local x = (i * 37 + 11) % SW
    local y = MAP_Y0 + (i * 19 + 7) % (MAP_Y1 - MAP_Y0)
    pix(x, y, 13)
  end
  line(MAP_CX, MAP_Y0, MAP_CX, MAP_Y1 - 1, 13)
  line(0, MAP_CY, SW - 1, MAP_CY, 13)
end

local function draw_galaxy()
  draw_galaxy_bg()
  for i, s in ipairs(stars) do
    local r = 1
    if s.tier >= 3 then r = 2 end
    if s.capital then r = 3 end
    circ(s.x, s.y, r, EMP_COLOR[s.owner])
    if s.capital then circb(s.x, s.y, r + 2, EMP_COLOR[s.owner]) end
  end
  -- combat indicators on top
  for _, s in ipairs(stars) do
    if #s.ships > 0 then
      -- pulse a ring
      local rr = 5 + (frame // 8) % 3
      circb(s.x, s.y, rr, 11)
      print("x" .. #s.ships, s.x + 4, s.y - 6, 11, false, 1, true)
    end
  end
  if hov_idx then
    local s = stars[hov_idx]
    circb(s.x, s.y, 6, 15)
  end
  if sel_idx and sel_idx ~= hov_idx then
    local s = stars[sel_idx]
    circb(s.x, s.y, 5, 12)
  end
end

local function draw_ship(sh)
  local hp_frac = sh.hp / sh.max_hp
  local body = FIGHTER.color
  if hp_frac < 0.4 then body = 8 end
  pix(sh.x, sh.y, body)
  pix(sh.x - 1, sh.y, body)
  pix(sh.x + 1, sh.y, body)
  pix(sh.x, sh.y - 1, body)
  pix(sh.x, sh.y + 1, body)
end

local function draw_bullets(s)
  for _, b in ipairs(s.bullets) do
    local c = b.team == 1 and 10 or 9
    pix(b.x, b.y, c)
    pix(b.x - b.vx * 0.5, b.y - b.vy * 0.5, c == 10 and 9 or 8)
  end
end

local function draw_particles()
  for _, p in ipairs(particles) do
    pix(p.x, p.y, p.color)
  end
end

local function draw_wrecks(s)
  for _, w in ipairs(s.wrecks) do
    pix(w.x, w.y, 14)
    pix(w.x + 1, w.y, 5)
    pix(w.x, w.y + 1, 5)
  end
end

local function draw_spawn_button()
  local hot = in_box(mx, my, SPAWN_BX0, SPAWN_BY0, SPAWN_BW, SPAWN_BH)
  local edge = hot and 11 or 14
  rect(SPAWN_BX0, SPAWN_BY0, SPAWN_BW, SPAWN_BH, 1)
  rectb(SPAWN_BX0, SPAWN_BY0, SPAWN_BW, SPAWN_BH, edge)
  print("spawn fighter", SPAWN_BX0 + 4, SPAWN_BY0 + 3, edge, false, 1, true)
end

local function draw_system()
  cls(1)
  local sid = sel_idx or 1
  for i = 0, 100 do
    local x = (i * 53 + sid * 11) % SW
    local y = MAP_Y0 + (i * 31 + sid * 7) % (MAP_Y1 - MAP_Y0)
    pix(x, y, 13)
  end
  local s = stars[sel_idx]
  if not s then return end
  local cx, cy = MAP_CX, MAP_CY
  local pr = planet_radius(s)
  circ(cx, cy, pr, EMP_COLOR[s.owner])
  circb(cx, cy, pr, 0)
  if s.owner ~= 1 and s.turret_hp and s.turret_hp > 0 then
    pix(cx, cy, 2)
    pix(cx + 1, cy, 2)
    pix(cx - 1, cy, 2)
    pix(cx, cy + 1, 2)
    pix(cx, cy - 1, 2)
  end

  draw_wrecks(s)
  draw_bullets(s)
  for _, sh in ipairs(s.ships) do draw_ship(sh) end
  draw_particles()

  rect(DOCK_X - 3, DOCK_Y - 4, 6, 8, 13)
  rectb(DOCK_X - 3, DOCK_Y - 4, 6, 8, 6)
  pix(DOCK_X, DOCK_Y, 6)

  print(s.name, cx - #s.name * 2, cy - pr - 9,
        EMP_COLOR[s.owner], false, 1, true)
  print(EMP_NAME[s.owner], cx - #EMP_NAME[s.owner] * 2, cy + pr + 4,
        EMP_COLOR[s.owner], false, 1, true)
  if s.capital then
    print("capital world", cx - 26, cy + pr + 12, 9, false, 1, true)
  end

  draw_spawn_button()

  if s.owner ~= 1 and s.turret_max then
    local tw = 40
    local tx = SW - tw - 4
    local ty = MAP_Y0 + 4
    rect(tx, ty, tw, 7, 1)
    local frac = s.turret_hp / s.turret_max
    if frac < 0 then frac = 0 end
    rect(tx + 1, ty + 1, math.floor((tw - 2) * frac), 5, 2)
    rectb(tx, ty, tw, 7, 14)
    print("turret", tx + 4, ty + 1, 14, false, 1, true)
  end
end

local function draw_cursor()
  for i = 0, 5 do
    pix(mx, my + i, 15)
    pix(mx + i, my, 15)
  end
  pix(mx + 1, my + 1, 15)
  pix(mx + 2, my + 2, 15)
  pix(mx + 3, my + 3, 15)
end

gen_galaxy()

function TIC()
  frame = frame + 1
  update_mouse()
  update_topbar()
  if view == "galaxy" then update_galaxy() else update_system() end
  tick_world()
  if view == "galaxy" then draw_galaxy() else draw_system() end
  draw_topbar()
  draw_botbar()
  draw_cursor()
end
