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
local FIGHTER  = {hp = 4,  speed = 1.0, fire_cd = 26, range = 44, dmg = 1, color = 11}
local FLAGSHIP = {hp = 30, speed = 0.8, fire_cd = 18, range = 52, dmg = 3, color = 12}
local DEFENDER = {hp = 3,  speed = 0.9, fire_cd = 32, range = 40, dmg = 1, color = 2}
local SALVAGE  = {hp = 3,  speed = 0.8, color = 10,   value = 6,  rp = 1}
local TURRET   = {fire_cd = 38, range = 64, dmg = 2}
local BULLET_SPEED = 2.6
local DOCK_X, DOCK_Y = 14, MAP_CY

-- economy
local FIGHTER_COST = 10
local SALVAGE_COST = 8
local INCOME_PERIOD = 60
local STARTING_MONEY = 100
local HIRE_MONEY_COST = 50
local HIRE_RP_COST    = 10

local MAX_ADMIRAL_SLOTS = 4
local PROMOTION_THRESHOLD = 20
local TRAITS = {"Gunner", "Veteran", "Logistician", "Salvager"}

local NAMES = {"kira", "reyes", "vega", "okwu", "shen",
               "amara", "tariq", "ito",  "vance", "lior"}

local NODES = {
  o = {
    {name = "hard hulls",   cost = 8,  effect = "+1 fighter hp"},
    {name = "upgrade guns", cost = 15, effect = "+1 fighter dmg"},
    {name = "flag battery", cost = 25, effect = "+1 flag dmg"},
  },
  d = {
    {name = "thick steel",  cost = 10, effect = "+2 fighter hp"},
    {name = "salv plating", cost = 10, effect = "+2 salv hp"},
    {name = "flag plating", cost = 25, effect = "+30 flag hp"},
  },
  e = {
    {name = "trade routes", cost = 15, effect = "+50% income"},
    {name = "cheap yards",  cost = 12, effect = "-2 fighter $"},
    {name = "salv proto",   cost = 20, effect = "+50% scoop"},
  },
  l = {
    {name = "officer corp", cost = 20, effect = "+1 adm slot"},
    {name = "comms net",    cost = 15, effect = "fast dispatch"},
    {name = "navl academy", cost = 30, effect = "+1 adm slot"},
  },
}
local COL_KEYS = {"o", "d", "e", "l"}
local COL_TITLES = {"offense", "defense", "economy", "logist"}

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
local victory = false
local victory_frame = 0

local particles = {}

local admirals = {}
local sel_admiral = 1
local officer_xp = 0
local fleet_mode = "panel"
local roster = nil
local research = {o = 0, d = 0, e = 0, l = 0}

local R = {
  -- top bar tabs (x, y, w, h)
  tab_g = {80,  0, 38, 10},
  tab_s = {120, 0, 38, 10},
  tab_f = {160, 0, 38, 10},
  tab_r = {200, 0, 38, 10},
  -- system view spawn buttons
  spawn = {4, MAP_Y0 + 4,  56, 11},
  salv  = {4, MAP_Y0 + 17, 56, 11},
  -- fleet panel buttons
  f_set   = {110, 46, 60,  10},
  f_dep   = {4,   58, 152, 10},
  f_bf    = {4,   72, 100, 11},
  f_bs    = {110, 72, 100, 11},
  f_rec   = {4,   88, 152, 11},
  f_hire  = {30,  56, 180, 14},
  f_prev  = {2,   12, 8,   10},
  f_next  = {154, 12, 8,   10},
  f_fire  = {196, 12, 40,  10},
  f_promo = {162, 88, 74,  11},
  -- promotion roster
  r_card1 = {4,   22, 75, 70},
  r_card2 = {82,  22, 75, 70},
  r_card3 = {160, 22, 75, 70},
  r_skip  = {90, 100, 60, 12},
}

-- research view layout
local RES_COL_X = {4, 64, 124, 184}
local RES_NODE_W, RES_NODE_H = 56, 28
local RES_NODE_Y0, RES_ROW_DY = 30, 30

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

local function in_b(b)
  return mx >= b[1] and mx < b[1] + b[3]
     and my >= b[2] and my < b[2] + b[4]
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

local function has_trait(a, name)
  if not a or not a.traits then return false end
  for _, t in ipairs(a.traits) do
    if t == name then return true end
  end
  return false
end

local function fighter_hp_bonus()
  local b = 0
  if research.o >= 1 then b = b + 1 end
  if research.d >= 1 then b = b + 2 end
  return b
end
local function fighter_dmg_bonus()
  return research.o >= 2 and 1 or 0
end
local function flagship_dmg_bonus()
  return research.o >= 3 and 1 or 0
end
local function salvage_hp_bonus()
  return research.d >= 2 and 2 or 0
end
local function income_mult()
  return research.e >= 1 and 1.5 or 1.0
end
local function fighter_cost_real()
  return research.e >= 2 and (FIGHTER_COST - 2) or FIGHTER_COST
end
local function global_salvage_mult()
  return research.e >= 3 and 1.5 or 1.0
end
local function admiral_slot_cap()
  local s = MAX_ADMIRAL_SLOTS
  if research.l >= 1 then s = s + 1 end
  if research.l >= 3 then s = s + 1 end
  return s
end
local function dispatch_speedup()
  return research.l >= 2 and 4 or 0
end
local function dispatch_cd_for(a)
  local cd = 24
  if has_trait(a, "Logistician") then cd = cd - 8 end
  cd = cd - dispatch_speedup()
  if cd < 8 then cd = 8 end
  return cd
end

local function spawn_fighter(s, a)
  local hp = FIGHTER.hp + fighter_hp_bonus()
  table.insert(s.ships, {
    x = DOCK_X, y = DOCK_Y + math.random(-10, 10),
    vx = 0, vy = 0,
    hp = hp, max_hp = hp,
    team = 1, kind = "fighter",
    fire_cd = math.random(0, 20),
    orbit_dir = math.random() < 0.5 and 1 or -1,
    admiral = a,
    dmg_bonus = (has_trait(a, "Gunner") and 1 or 0),
  })
end

local function spawn_salvage(s, a)
  local hp = SALVAGE.hp + salvage_hp_bonus()
  table.insert(s.ships, {
    x = DOCK_X, y = DOCK_Y + math.random(-10, 10),
    vx = 0, vy = 0,
    hp = hp, max_hp = hp,
    team = 1, kind = "salvage",
    fire_cd = 0,
    orbit_dir = math.random() < 0.5 and 1 or -1,
    admiral = a,
  })
end

local function spawn_flagship(s, a)
  table.insert(s.ships, {
    x = DOCK_X, y = DOCK_Y,
    vx = 0, vy = 0,
    hp = a.flagship_hp, max_hp = a.flagship_max,
    team = 1, kind = "flagship",
    fire_cd = math.random(0, 12),
    orbit_dir = math.random() < 0.5 and 1 or -1,
    admiral = a,
    dmg_bonus = has_trait(a, "Veteran") and 1 or 0,
  })
end

local function admiral_recall(a)
  for _, s in ipairs(stars) do
    local i = 1
    while i <= #s.ships do
      local sh = s.ships[i]
      if sh.team == 1 and sh.admiral == a then
        if sh.kind == "fighter" then
          a.fleet_fighter = a.fleet_fighter + 1
        elseif sh.kind == "salvage" then
          a.fleet_salvage = a.fleet_salvage + 1
        elseif sh.kind == "flagship" then
          a.flagship_hp = math.max(1, sh.hp)
          a.flagship_deployed = false
        end
        table.remove(s.ships, i)
      else
        i = i + 1
      end
    end
  end
  a.target_idx = nil
  a.dispatch_cd = 0
end

local function roll_traits(n)
  local picked = {}
  for i = 1, n do
    local cand = TRAITS[math.random(1, #TRAITS)]
    local dup = false
    for _, p in ipairs(picked) do if p == cand then dup = true end end
    if not dup then table.insert(picked, cand) end
  end
  return picked
end

local function init_admiral(name, traits)
  traits = traits or {}
  local fhp = FLAGSHIP.hp
  for _, t in ipairs(traits) do
    if t == "Veteran" then fhp = fhp + 20 end
  end
  return {
    name = name,
    traits = traits,
    fleet_fighter = 0, fleet_salvage = 0,
    target_idx = nil,
    flagship_hp = fhp, flagship_max = fhp,
    flagship_deployed = false,
    deploy_flagship_toggle = false,
    alive = true,
    dispatch_cd = 0,
  }
end

local function roll_candidate()
  return {
    name = NAMES[math.random(1, #NAMES)],
    traits = roll_traits(math.random(1, 2)),
  }
end

local function open_roster()
  roster = {roll_candidate(), roll_candidate(), roll_candidate()}
  fleet_mode = "roster"
end

local function close_roster()
  roster = nil
  fleet_mode = "panel"
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

local function caps_taken()
  local n = 0
  for _, st in ipairs(stars) do
    if st.capital and st.empire ~= 1 and st.owner == 1 then n = n + 1 end
  end
  return n
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
  officer_xp = officer_xp + 10
  if s.capital and not victory and caps_taken() >= 4 then
    victory = true
    victory_frame = frame
    capture_flash = 240
    capture_msg = "galaxy conquered!"
  end
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
    if in_b(R.tab_g) then set_view("galaxy") end
    if in_b(R.tab_s) then set_view("system") end
    if in_b(R.tab_f) then set_view("fleet") end
    if in_b(R.tab_r) then set_view("research") end
  end
end

local function on_research_purchased(col, tier)
  if col == "d" and tier == 3 then
    for _, a in ipairs(admirals) do
      local was_full = a.flagship_hp == a.flagship_max
      a.flagship_max = a.flagship_max + 30
      if was_full then a.flagship_hp = a.flagship_max end
    end
  end
end

local function update_research()
  if not mclicked() then return end
  for ci, col in ipairs(COL_KEYS) do
    for ti = 1, 3 do
      local x = RES_COL_X[ci]
      local y = RES_NODE_Y0 + (ti - 1) * RES_ROW_DY
      if in_box(mx, my, x, y, RES_NODE_W, RES_NODE_H) then
        local node = NODES[col][ti]
        local owned = research[col] >= ti
        local available = research[col] >= (ti - 1) and not owned
        if available and rp >= node.cost then
          rp = rp - node.cost
          research[col] = ti
          on_research_purchased(col, ti)
        end
        return
      end
    end
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
    if sh.kind == "salvage" then
      local target_idx, td = nil, 1e9
      for wi, w in ipairs(s.wrecks) do
        local dd = d2(sh.x, sh.y, w.x, w.y)
        if dd < td then target_idx, td = wi, dd end
      end
      local tx, ty
      if target_idx then
        local w = s.wrecks[target_idx]
        tx, ty = w.x, w.y
      else
        tx, ty = DOCK_X, DOCK_Y
      end
      local dx, dy = tx - sh.x, ty - sh.y
      local dlen = math.sqrt(dx * dx + dy * dy)
      if dlen > 1 then
        if dlen < 0.1 then dlen = 0.1 end
        sh.vx = dx / dlen * SALVAGE.speed
        sh.vy = dy / dlen * SALVAGE.speed
        sh.x = sh.x + sh.vx
        sh.y = sh.y + sh.vy
      end
      if target_idx and dlen <= 2 then
        if viewed then add_particle(sh.x, sh.y, 6, 10) end
        table.remove(s.wrecks, target_idx)
        local mult = (has_trait(sh.admiral, "Salvager") and 1.5 or 1.0)
                     * global_salvage_mult()
        money = money + math.floor(SALVAGE.value * mult)
        rp = rp + SALVAGE.rp
      end
    else
      local stats = sh.kind == "flagship" and FLAGSHIP or FIGHTER
      local dx, dy = px - sh.x, py - sh.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < 0.1 then d = 0.1 end
      local approach = pr + 22
      if d > approach then
        sh.vx = dx / d * stats.speed
        sh.vy = dy / d * stats.speed
      else
        sh.vx = (-dy / d) * stats.speed * sh.orbit_dir
        sh.vy = ( dx / d) * stats.speed * sh.orbit_dir
      end
      sh.x = sh.x + sh.vx
      sh.y = sh.y + sh.vy
      sh.fire_cd = sh.fire_cd - 1
      if enemy and sh.fire_cd <= 0 and d < stats.range then
        local extra = sh.kind == "flagship"
                      and flagship_dmg_bonus() or fighter_dmg_bonus()
        fire_bullet(s, sh.x, sh.y, px, py, 1,
                    stats.dmg + (sh.dmg_bonus or 0) + extra)
        sh.fire_cd = stats.fire_cd
      end
    end
    clamp_in_play(sh)

    if sh.hp <= 0 then
      if viewed then
        add_particle(sh.x, sh.y, sh.kind == "flagship" and 24 or 10, 8)
        add_particle(sh.x, sh.y, 4, 9)
      end
      table.insert(s.wrecks, {x = sh.x, y = sh.y})
      if sh.kind == "flagship" and sh.admiral then
        sh.admiral.alive = false
        sh.admiral.flagship_hp = 0
        sh.admiral.flagship_deployed = false
        sh.admiral.target_idx = nil
        capture_flash = 90
        capture_msg = string.format("admiral %s lost!", sh.admiral.name)
      end
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
      officer_xp = officer_xp + 1
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
                officer_xp = officer_xp + 2
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
        money = money + math.floor((1 + s.tier) * income_mult())
      end
    end
  end
end

local function tick_admirals()
  for _, a in ipairs(admirals) do
    if a.alive and a.target_idx then
      local s = stars[a.target_idx]
      if s and s.owner ~= 1 then
        a.dispatch_cd = a.dispatch_cd - 1
        if a.dispatch_cd <= 0 then
          if a.fleet_fighter > 0 then
            a.fleet_fighter = a.fleet_fighter - 1
            spawn_fighter(s, a)
            a.dispatch_cd = dispatch_cd_for(a)
          elseif a.fleet_salvage > 0 then
            a.fleet_salvage = a.fleet_salvage - 1
            spawn_salvage(s, a)
            a.dispatch_cd = dispatch_cd_for(a)
          else
            a.dispatch_cd = 12
          end
        end
        if a.deploy_flagship_toggle and not a.flagship_deployed
           and a.flagship_hp > 0 then
          spawn_flagship(s, a)
          a.flagship_deployed = true
        end
      else
        a.target_idx = nil
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
  tick_admirals()
  if capture_flash > 0 then capture_flash = capture_flash - 1 end
end

local function update_system()
  if mclicked() then
    local s = stars[sel_idx]
    local a = admirals[sel_admiral]
    if s and in_b(R.spawn) then
      local c = fighter_cost_real()
      if money >= c then
        spawn_fighter(s, a)
        money = money - c
      end
    elseif s and in_b(R.salv) then
      if money >= SALVAGE_COST then
        spawn_salvage(s, a)
        money = money - SALVAGE_COST
      end
    end
  end
end

local function fire_admiral(idx)
  local a = admirals[idx]
  if not a then return end
  if a.alive then admiral_recall(a) end
  table.remove(admirals, idx)
  if sel_admiral > #admirals then sel_admiral = #admirals end
  if sel_admiral < 1 then sel_admiral = 1 end
end

local function pick_candidate(idx)
  if not roster or not roster[idx] then return end
  if #admirals >= admiral_slot_cap() then return end
  if officer_xp < PROMOTION_THRESHOLD then return end
  local cand = roster[idx]
  table.insert(admirals, init_admiral(cand.name, cand.traits))
  sel_admiral = #admirals
  officer_xp = officer_xp - PROMOTION_THRESHOLD
  close_roster()
end

local function update_fleet()
  if fleet_mode == "roster" then
    if not mclicked() then return end
    if in_b(R.r_card1) then pick_candidate(1)
    elseif in_b(R.r_card2) then pick_candidate(2)
    elseif in_b(R.r_card3) then pick_candidate(3)
    elseif in_b(R.r_skip) then close_roster()
    end
    return
  end
  if not mclicked() then return end
  if in_b(R.f_prev) then
    if #admirals > 0 then
      sel_admiral = sel_admiral - 1
      if sel_admiral < 1 then sel_admiral = #admirals end
    end
    return
  elseif in_b(R.f_next) then
    if #admirals > 0 then
      sel_admiral = sel_admiral + 1
      if sel_admiral > #admirals then sel_admiral = 1 end
    end
    return
  elseif in_b(R.f_fire) then
    if #admirals > 1 then fire_admiral(sel_admiral) end
    return
  elseif in_b(R.f_promo) then
    if officer_xp >= PROMOTION_THRESHOLD and #admirals < admiral_slot_cap() then
      open_roster()
    end
    return
  end
  local a = admirals[sel_admiral]
  if not a then return end
  if not a.alive then
    if in_b(R.f_hire) then
      if money >= HIRE_MONEY_COST and rp >= HIRE_RP_COST then
        money = money - HIRE_MONEY_COST
        rp = rp - HIRE_RP_COST
        admirals[sel_admiral] = init_admiral(
          NAMES[math.random(1, #NAMES)], roll_traits(1))
      end
    end
    return
  end
  if in_b(R.f_set) then
    if a.alive and sel_idx and stars[sel_idx] and stars[sel_idx].owner ~= 1 then
      a.target_idx = sel_idx
      a.dispatch_cd = 0
    end
  elseif in_b(R.f_dep) then
    a.deploy_flagship_toggle = not a.deploy_flagship_toggle
  elseif in_b(R.f_bf) then
    local c = fighter_cost_real()
    if a.alive and money >= c then
      money = money - c
      a.fleet_fighter = a.fleet_fighter + 1
    end
  elseif in_b(R.f_bs) then
    if a.alive and money >= SALVAGE_COST then
      money = money - SALVAGE_COST
      a.fleet_salvage = a.fleet_salvage + 1
    end
  elseif in_b(R.f_rec) then
    if a.alive then admiral_recall(a) end
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
  print(string.format("$%d rp:%d cap:%d/4", money, rp, caps_taken()),
        2, 3, 9, false, 1, true)
  local g_col = view == "galaxy"   and 11 or 14
  local s_col = view == "system"   and 11 or 14
  local f_col = view == "fleet"    and 11 or 14
  local r_col = view == "research" and 11 or 14
  rectb(R.tab_g[1], 1, R.tab_g[3], TOPBAR_H - 2, g_col)
  rectb(R.tab_s[1], 1, R.tab_s[3], TOPBAR_H - 2, s_col)
  rectb(R.tab_f[1], 1, R.tab_f[3], TOPBAR_H - 2, f_col)
  rectb(R.tab_r[1], 1, R.tab_r[3], TOPBAR_H - 2, r_col)
  print("galaxy",   R.tab_g[1] + 7, 3, g_col, false, 1, true)
  print("system",   R.tab_s[1] + 7, 3, s_col, false, 1, true)
  print("fleet",    R.tab_f[1] + 9, 3, f_col, false, 1, true)
  print("research", R.tab_r[1] + 3, 3, r_col, false, 1, true)
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
  if sh.kind == "flagship" then
    rect(sh.x - 1, sh.y - 1, 3, 3, body)
    pix(sh.x, sh.y - 2, body)
    pix(sh.x, sh.y + 2, body)
    pix(sh.x - 2, sh.y, body)
    pix(sh.x + 2, sh.y, body)
    pix(sh.x, sh.y, 7)
  else
    pix(sh.x, sh.y, body)
    pix(sh.x - 1, sh.y, body)
    pix(sh.x + 1, sh.y, body)
    pix(sh.x, sh.y - 1, body)
    pix(sh.x, sh.y + 1, body)
  end
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

local function draw_button(x, y, w, h, label, cost)
  local can_afford = money >= cost
  local hot = in_box(mx, my, x, y, w, h)
  local edge
  if not can_afford then edge = 8
  elseif hot then edge = 11
  else edge = 14 end
  rect(x, y, w, h, 1)
  rectb(x, y, w, h, edge)
  print(string.format("%s $%d", label, cost), x + 4, y + 3, edge, false, 1, true)
end

local function draw_spawn_buttons()
  draw_button(R.spawn[1], R.spawn[2], R.spawn[3], R.spawn[4], "fighter", FIGHTER_COST)
  draw_button(R.salv[1], R.salv[2], R.salv[3], R.salv[4],  "salvage", SALVAGE_COST)
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
  for _, sh in ipairs(s.ships) do
    local c = FIGHTER.color
    if sh.kind == "salvage" then c = SALVAGE.color
    elseif sh.kind == "flagship" then c = FLAGSHIP.color end
    draw_ship(sh, c)
  end
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

  draw_spawn_buttons()
  draw_planet_hp(s)

  if capture_flash > 0 and capture_msg ~= "" then
    local cw = #capture_msg * 4 + 6
    local cx2 = (SW - cw) / 2
    rect(cx2, MAP_Y0 + 16, cw, 9, 0)
    rectb(cx2, MAP_Y0 + 16, cw, 9, 6)
    print(capture_msg, cx2 + 3, MAP_Y0 + 18, 6, false, 1, true)
  end
end

local function draw_panel_button(x, y, w, h, label, hot, can, base_color)
  local edge
  if not can then edge = 8
  elseif hot then edge = 11
  else edge = base_color or 14 end
  rect(x, y, w, h, 1)
  rectb(x, y, w, h, edge)
  print(label, x + 4, y + 3, edge, false, 1, true)
end

local function traits_str(traits)
  if not traits or #traits == 0 then return "(no traits)" end
  local out = traits[1]
  for i = 2, #traits do out = out .. "," .. traits[i] end
  return out
end

local function draw_roster()
  cls(0)
  for i = 0, 60 do
    local x = (i * 41 + 13) % SW
    local y = MAP_Y0 + (i * 23 + 9) % (MAP_Y1 - MAP_Y0)
    pix(x, y, 13)
  end
  print("promotion roster: pick one officer",
        4, 12, 11, false, 1, true)
  print(string.format("officer xp: %d  slots %d/%d",
          officer_xp, #admirals, MAX_ADMIRAL_SLOTS),
        4, 124, 14, false, 1, true)
  local positions = {R.r_card1[1], R.r_card2[1], R.r_card3[1]}
  for i = 1, 3 do
    local cx = positions[i]
    local cand = roster and roster[i]
    local hot = in_box(mx, my, cx, R.r_card1[2], R.r_card1[3], R.r_card1[4])
    local edge = hot and 11 or 14
    rect(cx, R.r_card1[2], R.r_card1[3], R.r_card1[4], 1)
    rectb(cx, R.r_card1[2], R.r_card1[3], R.r_card1[4], edge)
    if cand then
      print(cand.name, cx + 4, R.r_card1[2] + 4, 6, false, 1, true)
      print("traits:", cx + 4, R.r_card1[2] + 16, 14, false, 1, true)
      for ti, t in ipairs(cand.traits) do
        print("- " .. t, cx + 4, R.r_card1[2] + 26 + (ti - 1) * 8,
              11, false, 1, true)
      end
      print("[promote]", cx + 4, R.r_card1[2] + R.r_card1[4] - 10,
            edge, false, 1, true)
    end
  end
  local sk_hot = in_b(R.r_skip)
  draw_panel_button(R.r_skip[1], R.r_skip[2], R.r_skip[3], R.r_skip[4],
    "skip", sk_hot, true)
end

local function draw_fleet()
  if fleet_mode == "roster" then draw_roster(); return end
  cls(0)
  for i = 0, 70 do
    local x = (i * 41 + 13) % SW
    local y = MAP_Y0 + (i * 23 + 9) % (MAP_Y1 - MAP_Y0)
    pix(x, y, 13)
  end

  local a = admirals[sel_admiral]
  if not a then
    print("no admirals - hire one via promotion", 4, 60, 8, false, 1, true)
    return
  end

  local hdr_col = a.alive and 6 or 8
  -- prev / next nav
  draw_panel_button(R.f_prev[1], R.f_prev[2], R.f_prev[3], R.f_prev[4], "<",
    in_b(R.f_prev), #admirals > 1)
  draw_panel_button(R.f_next[1], R.f_next[2], R.f_next[3], R.f_next[4], ">",
    in_b(R.f_next), #admirals > 1)
  print(string.format("adm %d/%d: %s", sel_admiral, #admirals, a.name),
        14, 14, hdr_col, false, 1, true)
  print(a.alive and "(active)" or "(lost)",
        100, 14, hdr_col, false, 1, true)
  -- fire button (disabled if last admiral)
  draw_panel_button(R.f_fire[1], R.f_fire[2], R.f_fire[3], R.f_fire[4], "fire",
    in_b(R.f_fire), #admirals > 1)

  if not a.alive then
    print("flagship destroyed. admiral lost.",
          4, 36, 8, false, 1, true)
    local can = money >= HIRE_MONEY_COST and rp >= HIRE_RP_COST
    draw_panel_button(R.f_hire[1], R.f_hire[2], R.f_hire[3], R.f_hire[4],
      string.format("hire new admiral  $%d  rp:%d",
                    HIRE_MONEY_COST, HIRE_RP_COST),
      in_b(R.f_hire), can)
    return
  end

  -- traits line
  print("traits: " .. traits_str(a.traits), 4, 100, 11, false, 1, true)

  -- promotion button
  local promo_can = officer_xp >= PROMOTION_THRESHOLD
                    and #admirals < MAX_ADMIRAL_SLOTS
  draw_panel_button(R.f_promo[1], R.f_promo[2], R.f_promo[3], R.f_promo[4],
    string.format("xp %d/%d roster", officer_xp, PROMOTION_THRESHOLD),
    in_b(R.f_promo), promo_can)

  print("flagship", 4, 24, FLAGSHIP.color, false, 1, true)
  local fbw = 70
  rect(40, 23, fbw, 7, 1)
  local frac = a.flagship_hp / a.flagship_max
  if frac < 0 then frac = 0 end
  rect(41, 24, math.floor((fbw - 2) * frac), 5,
       a.flagship_hp > 0 and FLAGSHIP.color or 8)
  rectb(40, 23, fbw, 7, 14)
  print(string.format("%d/%d", a.flagship_hp, a.flagship_max),
        116, 24, 14, false, 1, true)
  print(a.flagship_deployed and "deployed" or "docked",
        160, 24, a.flagship_deployed and 11 or 14, false, 1, true)

  print(string.format("pool: %d fighters  %d salvage",
          a.fleet_fighter, a.fleet_salvage),
        4, 36, 14, false, 1, true)

  local tname = "none"
  if a.target_idx and stars[a.target_idx] then
    tname = stars[a.target_idx].name
  end
  print(string.format("target: %s", tname), 4, 48, 11, false, 1, true)

  local can_set = a.alive and sel_idx and stars[sel_idx]
                  and stars[sel_idx].owner ~= 1
  local set_label = sel_idx and stars[sel_idx]
                    and ("set: " .. stars[sel_idx].name) or "set: ?"
  draw_panel_button(R.f_set[1], R.f_set[2], R.f_set[3], R.f_set[4], set_label,
    in_b(R.f_set), can_set)

  local mark = a.deploy_flagship_toggle and "[x]" or "[ ]"
  draw_panel_button(R.f_dep[1], R.f_dep[2], R.f_dep[3], R.f_dep[4],
    mark .. " deploy flagship with fleet",
    in_b(R.f_dep), a.alive)

  local fc = fighter_cost_real()
  local can_bf = a.alive and money >= fc
  local can_bs = a.alive and money >= SALVAGE_COST
  draw_panel_button(R.f_bf[1], R.f_bf[2], R.f_bf[3], R.f_bf[4],
    string.format("build fighter $%d", fc),
    in_b(R.f_bf), can_bf)
  draw_panel_button(R.f_bs[1], R.f_bs[2], R.f_bs[3], R.f_bs[4],
    string.format("build salvage $%d", SALVAGE_COST),
    in_b(R.f_bs), can_bs)

  draw_panel_button(R.f_rec[1], R.f_rec[2], R.f_rec[3], R.f_rec[4],
    "recall fleet to home",
    in_b(R.f_rec), a.alive)
end

local function draw_research()
  cls(0)
  for i = 0, 60 do
    local x = (i * 41 + 13) % SW
    local y = MAP_Y0 + (i * 23 + 9) % (MAP_Y1 - MAP_Y0)
    pix(x, y, 13)
  end
  print("research tree", 4, 12, 11, false, 1, true)
  for ci = 1, 4 do
    print(COL_TITLES[ci], RES_COL_X[ci], 22, 14, false, 1, true)
  end
  for ci, col in ipairs(COL_KEYS) do
    for ti = 1, 3 do
      local x = RES_COL_X[ci]
      local y = RES_NODE_Y0 + (ti - 1) * RES_ROW_DY
      local node = NODES[col][ti]
      local owned = research[col] >= ti
      local can_buy = research[col] >= (ti - 1) and not owned and rp >= node.cost
      local hot = in_box(mx, my, x, y, RES_NODE_W, RES_NODE_H)
      local edge
      if owned then edge = 6
      elseif can_buy and hot then edge = 11
      elseif can_buy then edge = 9
      else edge = 14 end
      rect(x, y, RES_NODE_W, RES_NODE_H, 1)
      rectb(x, y, RES_NODE_W, RES_NODE_H, edge)
      print(node.name, x + 2, y + 2, edge, false, 1, true)
      print(node.effect, x + 2, y + 10, edge, false, 1, true)
      if owned then
        print("owned", x + 2, y + 19, 6, false, 1, true)
      else
        print(string.format("%d rp", node.cost), x + 2, y + 19, edge, false, 1, true)
      end
    end
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
table.insert(admirals, init_admiral("kira"))

local function draw_victory()
  if not victory then return end
  local bw, bh = 160, 40
  local bx, by = math.floor((SW - bw) / 2), math.floor((SH - bh) / 2)
  rect(bx, by, bw, bh, 0)
  rectb(bx, by, bw, bh, 9)
  rectb(bx + 1, by + 1, bw - 2, bh - 2, 10)
  print("galaxy conquered", bx + 24, by + 8, 10, false, 1, false)
  print(string.format("4 capitals fallen in %ds",
        math.floor((frame - victory_frame) / 60)),
        bx + 12, by + 22, 6, false, 1, true)
  print("watch the stars burn", bx + 38, by + 30, 14, false, 1, true)
end

function TIC()
  frame = frame + 1
  update_mouse()
  update_topbar()
  if view == "galaxy" then update_galaxy()
  elseif view == "system" then update_system()
  elseif view == "fleet" then update_fleet()
  else update_research() end
  tick_world()
  if view == "galaxy" then draw_galaxy()
  elseif view == "system" then draw_system()
  elseif view == "fleet" then draw_fleet()
  else draw_research() end
  draw_topbar()
  draw_botbar()
  draw_victory()
  draw_cursor()
end
