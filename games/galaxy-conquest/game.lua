-- title:  Galaxy Conquest
-- author: tic-labs
-- desc:   Idle galactic conquest. Click systems, dispatch admirals, salvage wrecks.
-- script: lua

-- M1 shell: galaxy map plus zoomable system view.
-- Combat, economy, admirals, research, save/load all land in later milestones.

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

local view = "galaxy"
local mx, my, ml, mm, mr = 0, 0, false, false, false
local ml_prev, mr_prev = false, false
local stars = {}
local sel_idx, hov_idx = nil, nil
local money, rp = 50, 0
local seed = 1
local frame = 0

local TAB_GX0, TAB_GX1 = 80, 130
local TAB_SX0, TAB_SX1 = 132, 182

local function d2(x1, y1, x2, y2)
  local dx, dy = x1 - x2, y1 - y2
  return dx * dx + dy * dy
end

local function in_rect(px, py, x0, y0, x1, y1)
  return px >= x0 and px < x1 and py >= y0 and py < y1
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
      })
    end
  end

  -- player home is the star closest to galactic center
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

  -- one capital per empire, picked as the farthest star from galactic center
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
  end
end

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
    if in_rect(mx, my, TAB_GX0, 0, TAB_GX1, TOPBAR_H) then view = "galaxy" end
    if in_rect(mx, my, TAB_SX0, 0, TAB_SX1, TOPBAR_H) then view = "system" end
  end
end

local function update_galaxy()
  hov_idx = pick_star_at(mx, my)
  if hov_idx and my >= MAP_Y0 and my < MAP_Y1 then
    if mclicked() then sel_idx = hov_idx end
    if mrclicked() then sel_idx = hov_idx; view = "system" end
  end
end

local function update_system()
  -- placeholder: combat sim, defenses, ships land in M2
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
    local cap = s.capital and " (capital)" or ""
    print(string.format("%s  t%d  %s%s",
            s.name, s.tier, EMP_NAME[s.owner], cap),
          2, SH - BOTBAR_H + 3, EMP_COLOR[s.owner], false, 1, true)
  end
  if view == "galaxy" then
    print("rclick:enter", SW - 56, SH - BOTBAR_H + 3, 14, false, 1, true)
  else
    print("tab back via top bar", SW - 88, SH - BOTBAR_H + 3, 14, false, 1, true)
  end
end

local function draw_galaxy_bg()
  cls(0)
  for i = 0, 80 do
    local x = (i * 37 + 11) % SW
    local y = MAP_Y0 + (i * 19 + 7) % (MAP_Y1 - MAP_Y0)
    pix(x, y, 13)
  end
  -- empire region dividers
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
  if hov_idx then
    local s = stars[hov_idx]
    circb(s.x, s.y, 6, 15)
  end
  if sel_idx and sel_idx ~= hov_idx then
    local s = stars[sel_idx]
    circb(s.x, s.y, 5, 12)
  end
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
  local pr = 10 + s.tier * 3
  circ(cx, cy, pr, EMP_COLOR[s.owner])
  circb(cx, cy, pr, 0)
  for k = 1, s.tier do
    circb(cx, cy, pr + 4 + k * 4, 5)
  end
  print(s.name, cx - #s.name * 2, cy - pr - 9,
        EMP_COLOR[s.owner], false, 1, true)
  print(EMP_NAME[s.owner], cx - #EMP_NAME[s.owner] * 2, cy + pr + 4,
        EMP_COLOR[s.owner], false, 1, true)
  if s.capital then
    print("capital world", cx - 26, cy + pr + 12, 9, false, 1, true)
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
  if view == "galaxy" then draw_galaxy() else draw_system() end
  draw_topbar()
  draw_botbar()
  draw_cursor()
end
