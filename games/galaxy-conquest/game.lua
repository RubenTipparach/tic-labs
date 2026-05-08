-- title:  Galaxy Conquest
-- author: tic-labs
-- desc:   Idle galactic conquest. Click systems, dispatch admirals, salvage wrecks.
-- script: lua

-- M1: galaxy + system view shell.
-- M2: per-star combat sim. Fighters, bullets, particles, wrecks.
-- M3: economy. Fighters cost money. Owned planets pay income.
-- M9.early: layered defenses. Multi-turret, rebuild, defending fighters,
--           respawn, planet HP, capture, distance-scaled difficulty.

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
local FIGHTER  = {hp = 4, speed = 1.0, fire_cd = 26, range = 44, dmg = 1, color = 11}
local DEFENDER = {hp = 3, speed = 0.9, fire_cd = 32, range = 40, dmg = 1, color = 2}
local TURRET   = {fire_cd = 38, range = 64, dmg = 2}
local BULLET_SPEED = 2.6
local DOCK_X, DOCK_Y = 14, MAP_CY

-- economy
local FIGHTER_COST = 10
local INCOME_PERIOD = 60
local STARTING_MONEY = 100

-- defense baselines, scaled by per-star difficulty
local TURRET_HP_BASE      = 8
local PLANET_HP_BASE      = 18
local DEF_SPAWN_CD_BASE   = 700
local TURRET_REBUILD_BASE = 600

local view = "galaxy"
local mx, my, ml, mm, mr = 0, 0, false, false, false
local ml_prev, mr_prev = false, false
local stars = {}
local sel_idx, hov_idx = nil, nil
local money, rp = STARTING_MONEY, 0
local money_tick = 0
local seed = 1
local frame = 0
local capture_flash = 0
local capture_msg = ""

local particles = {}

local TAB_GX0, TAB_GX1 = 80, 130
local TAB_SX0, TAB_SX1 = 132, 182
local SPAWN_BX0, SPAWN_BY0 = 4, MAP_Y0 + 4
local SPAWN_BW, SPAWN_BH = 56, 11

local function d2(x1, y1, x2, y2)
  local dx, dy = x1 - x2, y1 - y2
  return dx * dx + dy * dy
end

local function dist(x1, y1, x2, y2)
  return math.sqrt(d2(x1, y1, x2, y2))
end

local function in_rect(px, py, x0, y0, x1, y1)
  return px >= x0 and px < x1 and py >= y0 and py < y1
end

local function in_box(px, py, x, y, w, h)
  return px >= x and px < x + w and py >= y and py < y + h
end

local function planet_radius(s)
  return 8 + s.tier * 2
end

local function turret_pos(s, t)
  local pr = planet_radius(s)
  return MAP_CX + math.cos(t.rel_a) * pr,
         MAP_CY + math.sin(t.rel_a) * pr
end

-- ---- galaxy generation ----

local function tier_count(diff, lo, hi)
  local v = math.floor(diff + 0.0)
  if v < lo then v = lo end
  if v > hi then v = hi end
  return v
end

local function init_defenses(s)
  if s.owner == 1 then return end
  local diff = s.diff or 1.0
  local tcount = tier_count(diff, 1, 3)
  local thp    = math.floor(TURRET_HP_BASE + diff * 5)
  local dcount = tier_count(diff, 1, 3)
  local php    = math.floor(PLANET_HP_BASE + diff * 12)
  local rebuild = math.max(240, math.floor(TURRET_REBUILD_BASE - diff * 80))
  local respawn = math.max(180, math.floor(DEF_SPAWN_CD_BASE - diff * 100))

  s.turrets = {}
  for k = 1, tcount do
    local a = (k - 1) / tcount * 6.2832
    table.insert(s.turrets, {
      rel_a = a,
      hp = thp, max = thp,
      fire_cd = math.random(0, TURRET.fire_cd),
      rebuild_cd = nil,
    })
  end
  s.defenders = {}
  s.max_defenders = dcount
  s.def_spawn_cd = 60 + math.random(0, 120)
  s.def_spawn_cd_max = respawn
  s.turret_rebuild_cd = rebuild
  s.planet_hp = php
  s.planet_max = php
end

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
        turrets = {}, defenders = {},
        planet_hp = nil, planet_max = nil,
        diff = 1.0,
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
  local sol = stars[best]

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

  local max_d = 1
  for _, s in ipairs(stars) do
    local d = dist(s.x, s.y, sol.x, sol.y)
    if d > max_d then max_d = d end
  end
  for _, s in ipairs(stars) do
    if s.name == "" then
      s.name = string.format("%s%02d", EMP_PREFIX[s.empire] or "n", _)
    end
    local d = dist(s.x, s.y, sol.x, sol.y)
    local norm = d / max_d
    s.diff = 1.0 + norm * 2.0 + (s.capital and 1.0 or 0)
    init_defenses(s)
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
  local dlen = math.sqrt(dx * dx + dy * dy)
  if dlen < 0.1 then dlen = 0.1 end
  table.insert(s.bullets, {
    x = x, y = y,
    vx = dx / dlen * BULLET_SPEED, vy = dy / dlen * BULLET_SPEED,
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

local function spawn_defender(s)
  local a = math.random() * 6.2832
  local pr = planet_radius(s)
  local x = MAP_CX + math.cos(a) * (pr + 6)
  local y = MAP_CY + math.sin(a) * (pr + 6)
  table.insert(s.defenders, {
    x = x, y = y,
    vx = 0, vy = 0,
    hp = DEFENDER.hp, max_hp = DEFENDER.hp,
    team = 2, kind = "defender",
    fire_cd = math.random(0, 30),
    orbit_dir = math.random() < 0.5 and 1 or -1,
  })
end

local function defenses_alive(s)
  if #s.defenders > 0 then return true end
  for _, t in ipairs(s.turrets) do
    if t.hp > 0 then return true end
  end
  return false
end

local function capture_planet(s)
  s.owner = 1
  s.empire = 1
  s.planet_hp = s.planet_max
  s.turrets = {}
  s.defenders = {}
  s.max_defenders = 0
  capture_flash = 60
  capture_msg = string.format("%s captured!", s.name)
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

local function clamp_in_play(o)
  if o.x < 2 then o.x = 2 end
  if o.x > SW - 2 then o.x = SW - 2 end
  if o.y < MAP_Y0 + 2 then o.y = MAP_Y0 + 2 end
  if o.y > MAP_Y1 - 2 then o.y = MAP_Y1 - 2 end
end

local function tick_player_ships(s, viewed)
  local px, py = MAP_CX, MAP_CY
  local pr = planet_radius(s)
  local enemy = s.owner ~= 1
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
    clamp_in_play(sh)

    sh.fire_cd = sh.fire_cd - 1
    if enemy and sh.fire_cd <= 0 and d < FIGHTER.range then
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

local function tick_defenders(s, viewed)
  if s.owner == 1 then return end
  local px, py = MAP_CX, MAP_CY
  local pr = planet_radius(s)
  local i = 1
  while i <= #s.defenders do
    local df = s.defenders[i]
    local target, td = nil, 1e9
    for _, sh in ipairs(s.ships) do
      if sh.team == 1 then
        local dd = d2(df.x, df.y, sh.x, sh.y)
        if dd < td then target, td = sh, dd end
      end
    end
    if target then
      local dx, dy = target.x - df.x, target.y - df.y
      local dlen = math.sqrt(dx * dx + dy * dy)
      if dlen < 0.1 then dlen = 0.1 end
      if dlen > 16 then
        df.vx = dx / dlen * DEFENDER.speed
        df.vy = dy / dlen * DEFENDER.speed
      else
        df.vx = (-dy / dlen) * DEFENDER.speed * df.orbit_dir
        df.vy = ( dx / dlen) * DEFENDER.speed * df.orbit_dir
      end
      df.fire_cd = df.fire_cd - 1
      if df.fire_cd <= 0 and dlen <= DEFENDER.range then
        fire_bullet(s, df.x, df.y, target.x, target.y, 2, DEFENDER.dmg)
        df.fire_cd = DEFENDER.fire_cd
      end
    else
      local dx, dy = px - df.x, py - df.y
      local dlen = math.sqrt(dx * dx + dy * dy)
      if dlen < 0.1 then dlen = 0.1 end
      local orbit_r = pr + 14
      if dlen > orbit_r + 2 then
        df.vx = dx / dlen * DEFENDER.speed
        df.vy = dy / dlen * DEFENDER.speed
      else
        df.vx = (-dy / dlen) * DEFENDER.speed * df.orbit_dir
        df.vy = ( dx / dlen) * DEFENDER.speed * df.orbit_dir
      end
    end
    df.x = df.x + df.vx
    df.y = df.y + df.vy
    clamp_in_play(df)
    if df.hp <= 0 then
      if viewed then
        add_particle(df.x, df.y, 8, 8)
      end
      table.insert(s.wrecks, {x = df.x, y = df.y})
      table.remove(s.defenders, i)
    else
      i = i + 1
    end
  end

  s.def_spawn_cd = s.def_spawn_cd - 1
  if s.def_spawn_cd <= 0 and #s.defenders < s.max_defenders then
    spawn_defender(s)
    s.def_spawn_cd = s.def_spawn_cd_max
  end
end

local function tick_turrets(s)
  if s.owner == 1 then return end
  for _, t in ipairs(s.turrets) do
    if t.hp > 0 then
      t.fire_cd = t.fire_cd - 1
      if t.fire_cd <= 0 then
        local tx, ty = turret_pos(s, t)
        local target, td = nil, 1e9
        for _, sh in ipairs(s.ships) do
          if sh.team == 1 then
            local dd = d2(tx, ty, sh.x, sh.y)
            if dd < td then target, td = sh, dd end
          end
        end
        if target and math.sqrt(td) <= TURRET.range then
          fire_bullet(s, tx, ty, target.x, target.y, 2, TURRET.dmg)
          t.fire_cd = TURRET.fire_cd
        end
      end
    elseif t.rebuild_cd then
      t.rebuild_cd = t.rebuild_cd - 1
      if t.rebuild_cd <= 0 then
        t.hp = t.max
        t.rebuild_cd = nil
      end
    end
  end
end

local function tick_bullets(s, viewed)
  local pr = planet_radius(s)
  local pr2 = pr * pr
  local def_alive = defenses_alive(s)
  local i = 1
  while i <= #s.bullets do
    local b = s.bullets[i]
    b.x = b.x + b.vx
    b.y = b.y + b.vy
    b.life = b.life - 1
    local hit = false
    if b.team == 1 then
      for _, df in ipairs(s.defenders) do
        if d2(b.x, b.y, df.x, df.y) <= 9 then
          df.hp = df.hp - b.dmg
          if viewed then add_particle(b.x, b.y, 3, 9) end
          hit = true
          break
        end
      end
      if not hit then
        for _, t in ipairs(s.turrets) do
          if t.hp > 0 then
            local tx, ty = turret_pos(s, t)
            if d2(b.x, b.y, tx, ty) <= 9 then
              t.hp = t.hp - b.dmg
              if viewed then add_particle(b.x, b.y, 3, 9) end
              if t.hp <= 0 then
                t.hp = 0
                t.rebuild_cd = s.turret_rebuild_cd
                if viewed then add_particle(tx, ty, 8, 8) end
              end
              hit = true
              break
            end
          end
        end
      end
      if not hit and not def_alive
         and s.owner ~= 1 and s.planet_hp and s.planet_hp > 0
         and d2(b.x, b.y, MAP_CX, MAP_CY) <= pr2 then
        s.planet_hp = s.planet_hp - b.dmg
        if viewed then add_particle(b.x, b.y, 4, 8) end
        hit = true
        if s.planet_hp <= 0 then
          if viewed then add_particle(MAP_CX, MAP_CY, 30, 8) end
          capture_planet(s)
        end
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

local function tick_money()
  money_tick = money_tick + 1
  if money_tick >= INCOME_PERIOD then
    money_tick = 0
    for _, s in ipairs(stars) do
      if s.owner == 1 then
        money = money + 1 + s.tier
      end
    end
  end
end

local function tick_world()
  for i, s in ipairs(stars) do
    local viewed = (i == sel_idx and view == "system")
    local active = #s.ships > 0 or #s.bullets > 0 or #s.defenders > 0 or viewed
    if active then
      tick_player_ships(s, viewed)
      tick_defenders(s, viewed)
      tick_turrets(s)
      tick_bullets(s, viewed)
    elseif s.owner ~= 1 then
      -- still tick respawn timers slowly when off screen and idle
      tick_defenders(s, false)
      tick_turrets(s)
    end
  end
  tick_particles()
  tick_money()
  if capture_flash > 0 then capture_flash = capture_flash - 1 end
end

local function update_system()
  if mclicked() and in_box(mx, my, SPAWN_BX0, SPAWN_BY0, SPAWN_BW, SPAWN_BH) then
    if money >= FIGHTER_COST then
      local s = stars[sel_idx]
      if s then
        spawn_fighter(s)
        money = money - FIGHTER_COST
      end
    end
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
    local diff_str = string.format(" d%.1f", s.diff or 1.0)
    print(string.format("%s  t%d  %s%s%s",
            s.name, s.tier, EMP_NAME[s.owner], cap, diff_str),
          2, SH - BOTBAR_H + 3, EMP_COLOR[s.owner], false, 1, true)
  end
  if view == "galaxy" then
    print(string.format("active fighters:%d", total_player_ships()),
          SW - 96, SH - BOTBAR_H + 3, 11, false, 1, true)
  else
    local d = s and #s.defenders or 0
    local t_alive = 0
    if s then for _, t in ipairs(s.turrets) do if t.hp > 0 then t_alive = t_alive + 1 end end end
    print(string.format("def:%d  tur:%d  ship:%d", d, t_alive, s and #s.ships or 0),
          SW - 100, SH - BOTBAR_H + 3, 14, false, 1, true)
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
  for _, s in ipairs(stars) do
    local r = 1
    if s.tier >= 3 then r = 2 end
    if s.capital then r = 3 end
    circ(s.x, s.y, r, EMP_COLOR[s.owner])
    if s.capital then circb(s.x, s.y, r + 2, EMP_COLOR[s.owner]) end
  end
  for _, s in ipairs(stars) do
    if #s.ships > 0 then
      local rr = 5 + math.floor(frame / 8) % 3
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

local function draw_ship(sh, body_color)
  local hp_frac = sh.hp / sh.max_hp
  local body = body_color
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

local function draw_turrets(s)
  for _, t in ipairs(s.turrets) do
    local tx, ty = turret_pos(s, t)
    if t.hp > 0 then
      rect(tx - 1, ty - 1, 3, 3, 2)
      pix(tx, ty, 9)
    else
      pix(tx, ty, 5)
      if t.rebuild_cd then
        local total = s.turret_rebuild_cd
        local frac = 1 - (t.rebuild_cd / total)
        if frac < 0 then frac = 0 end
        if frac > 1 then frac = 1 end
        circb(tx, ty, 2, frac > 0.5 and 9 or 5)
      end
    end
  end
end

local function draw_spawn_button()
  local can_afford = money >= FIGHTER_COST
  local hot = in_box(mx, my, SPAWN_BX0, SPAWN_BY0, SPAWN_BW, SPAWN_BH)
  local edge
  if not can_afford then edge = 8
  elseif hot then edge = 11
  else edge = 14 end
  rect(SPAWN_BX0, SPAWN_BY0, SPAWN_BW, SPAWN_BH, 1)
  rectb(SPAWN_BX0, SPAWN_BY0, SPAWN_BW, SPAWN_BH, edge)
  print(string.format("fighter $%d", FIGHTER_COST),
        SPAWN_BX0 + 4, SPAWN_BY0 + 3, edge, false, 1, true)
end

local function draw_planet_hp(s)
  if s.owner == 1 or not s.planet_max then return end
  local tw = 60
  local tx = SW - tw - 4
  local ty = MAP_Y0 + 4
  rect(tx, ty, tw, 7, 1)
  local frac = s.planet_hp / s.planet_max
  if frac < 0 then frac = 0 end
  local barc = defenses_alive(s) and 14 or 8
  rect(tx + 1, ty + 1, math.floor((tw - 2) * frac), 5, barc)
  rectb(tx, ty, tw, 7, 14)
  print("planet", tx + 4, ty + 1, 14, false, 1, true)
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
  draw_turrets(s)
  draw_wrecks(s)
  draw_bullets(s)
  for _, df in ipairs(s.defenders) do draw_ship(df, DEFENDER.color) end
  for _, sh in ipairs(s.ships) do draw_ship(sh, FIGHTER.color) end
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
  draw_planet_hp(s)

  if capture_flash > 0 and capture_msg ~= "" then
    local cw = #capture_msg * 4 + 6
    local cx2 = (SW - cw) / 2
    rect(cx2, MAP_Y0 + 16, cw, 9, 0)
    rectb(cx2, MAP_Y0 + 16, cw, 9, 6)
    print(capture_msg, cx2 + 3, MAP_Y0 + 18, 6, false, 1, true)
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
