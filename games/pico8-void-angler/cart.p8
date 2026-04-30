pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- void angler
-- by tic-labs
-- stage 2: inventory + shop

bh_x=64
bh_y=96
bh_r=28

ship_x=64
ship_y=18

-- junk catalog (shared by spawn + shop)
junk_types={
 {name="bolt", val=2, col=6,  rate=5.0},
 {name="can",  val=3, col=13, rate=3.0},
 {name="chip", val=5, col=11, rate=1.5},
 {name="gem",  val=9, col=12, rate=0.5},
}

function _init()
 stars={}
 for i=1,40 do
  add(stars,{
   x=rnd(128),
   y=rnd(128),
   c=({1,5,6,7,13})[flr(rnd(5))+1],
   tw=rnd(1)
  })
 end
 credits=0
 inv={}
 for t in all(junk_types) do inv[t.name]=0 end
 mode="fish"
 shop_sel=1
 dock_msg_t=0
 reset_run()
end

function reset_run()
 arm_state="idle"
 arm_len=0
 arm_max=58
 arm_drop_speed=1.4
 arm_reel_speed=1.1
 aim=0
 aim_t=0
 hook={x=ship_x,y=ship_y+8,vx=0,vy=0}
 hooked=nil
 catch_flash=0

 junk={}
 for i=1,7 do spawn_junk() end

 popups={}
end

function spawn_junk()
 local a=rnd(1)
 local r=rnd(bh_r-3)+2
 local jx=bh_x+cos(a)*r
 local jy=bh_y+sin(a)*r
 -- weighted draw using rate field
 local total=0
 for t in all(junk_types) do total+=t.rate end
 local roll=rnd(total)
 local pick=junk_types[1]
 for t in all(junk_types) do
  roll-=t.rate
  if roll<=0 then pick=t break end
 end
 add(junk,{
  x=jx,y=jy,
  ox=jx,oy=jy,
  spin=rnd(1),
  spinv=(rnd(0.02)+0.005)*(rnd(1)<0.5 and -1 or 1),
  orbit=rnd(1),
  orbitv=(rnd(0.004)+0.001)*(rnd(1)<0.5 and -1 or 1),
  jitter=rnd(1.2)+0.4,
  type=pick,
 })
end

function dist(ax,ay,bx,by)
 local dx=ax-bx local dy=ay-by
 return sqrt(dx*dx+dy*dy)
end

function _update60()
 if mode=="fish" then update_fish()
 else update_shop() end
 if dock_msg_t>0 then dock_msg_t-=1 end
 for s in all(stars) do s.tw+=0.01 end
end

function update_fish()
 if arm_state=="idle" then
  if btn(0) then aim_t=max(aim_t-0.02,-0.18) end
  if btn(1) then aim_t=min(aim_t+0.02,0.18) end
  if not btn(0) and not btn(1) then
   aim_t*=0.92
   if abs(aim_t)<0.005 then aim_t=0 end
  end
  aim=aim_t
  if btnp(4) then
   arm_state="dropping"
   sfx(0)
  end
  -- dock by pressing down on idle
  if btnp(3) then
   mode="shop"
   shop_sel=1
   sfx(4)
  end
 end

 for j in all(junk) do
  j.orbit+=j.orbitv
  j.spin+=j.spinv
  local r=dist(j.ox,j.oy,bh_x,bh_y)
  j.x=bh_x+cos(j.orbit)*r+sin(j.spin*2)*j.jitter
  j.y=bh_y+sin(j.orbit)*r+cos(j.spin*2)*j.jitter
 end

 if arm_state=="dropping" then
  arm_len+=arm_drop_speed
  if arm_len>=arm_max then
   arm_len=arm_max
   arm_state="reeling"
  end
  check_catch()
  if btnp(5) then arm_state="reeling" end
 elseif arm_state=="reeling" then
  arm_len-=arm_reel_speed
  if hooked then
   hooked.x=hook.x
   hooked.y=hook.y
  end
  if arm_len<=0 then
   arm_len=0
   if hooked then
    catch_flash=18
    inv[hooked.type.name]=(inv[hooked.type.name] or 0)+1
    add(popups,{x=ship_x,y=ship_y,t=30,
     txt="+1 "..hooked.type.name})
    sfx(2)
    del(junk,hooked)
    spawn_junk()
    hooked=nil
   else
    sfx(3)
   end
   arm_state="idle"
  end
  if not hooked then check_catch() end
 end

 local ang=0.25+aim
 hook.x=ship_x+cos(ang)*arm_len
 hook.y=ship_y+8+sin(ang)*arm_len

 ship_y=18+sin(time()/3)*0.6

 if catch_flash>0 then catch_flash-=1 end
 for p in all(popups) do
  p.y-=0.5
  p.t-=1
  if p.t<=0 then del(popups,p) end
 end
end

function update_shop()
 local n=#junk_types
 if btnp(2) then shop_sel=((shop_sel-2)%n)+1 sfx(5) end
 if btnp(3) then shop_sel=(shop_sel%n)+1 sfx(5) end
 -- z: sell one of selected
 if btnp(4) then
  local t=junk_types[shop_sel]
  if (inv[t.name] or 0)>0 then
   inv[t.name]-=1
   credits+=t.val
   sfx(2)
   add(popups,{x=64,y=70,t=24,txt="+"..t.val.." cr"})
  else
   sfx(3)
  end
 end
 -- left: sell all of selected
 if btnp(0) then
  local t=junk_types[shop_sel]
  local q=inv[t.name] or 0
  if q>0 then
   inv[t.name]=0
   credits+=q*t.val
   sfx(2)
   add(popups,{x=64,y=70,t=30,txt="+"..(q*t.val).." cr"})
  else
   sfx(3)
  end
 end
 -- x: undock
 if btnp(5) then
  mode="fish"
  dock_msg_t=40
  sfx(4)
 end
 for p in all(popups) do
  p.y-=0.5
  p.t-=1
  if p.t<=0 then del(popups,p) end
 end
end

function check_catch()
 if hooked then return end
 for j in all(junk) do
  if dist(j.x,j.y,hook.x,hook.y)<3.5 then
   hooked=j
   sfx(1)
   return
  end
 end
end

function _draw()
 if mode=="fish" then draw_fish()
 else draw_shop() end
end

function draw_fish()
 cls(0)
 for s in all(stars) do
  local f=(sin(s.tw)+1)*0.5
  if f>0.3 then pset(s.x,s.y,s.c) end
 end

 draw_blackhole()
 draw_arm()
 draw_ship()
 for j in all(junk) do draw_junk(j) end

 draw_topbar()
 -- hint when idle
 if arm_state=="idle" then
  print("\139\145 aim  \142 drop  \151 reel",18,118,5)
  print("\131 dock at shop",36,124,6)
 end

 for p in all(popups) do
  print(p.txt,p.x-#p.txt*2,p.y,7)
 end

 if catch_flash>0 then
  for i=0,7 do
   local a=i/8+time()
   local r=10-catch_flash*0.3
   pset(ship_x+cos(a)*r,ship_y+sin(a)*r,10)
  end
 end

 if dock_msg_t>0 then
  local m="undocked"
  print(m,64-#m*2,60,7)
 end
end

function draw_shop()
 cls(1)
 -- starry shop bg
 for s in all(stars) do
  pset(s.x,s.y,s.c==1 and 5 or s.c)
 end
 -- shop window
 rectfill(8,16,119,112,0)
 rect(8,16,119,112,6)
 rect(9,17,118,111,5)
 print("salvage shop",40,20,7)
 line(10,28,117,28,5)

 -- list
 local y=34
 for i=1,#junk_types do
  local t=junk_types[i]
  local q=inv[t.name] or 0
  local row_y=y+(i-1)*12
  if i==shop_sel then
   rectfill(12,row_y-1,115,row_y+8,2)
   print("\135",13,row_y+1,8)
  end
  -- icon
  draw_junk_icon(t,22,row_y+3)
  print(t.name,30,row_y+1,7)
  print("x"..q,60,row_y+1,6)
  print(t.val.."cr",80,row_y+1,11)
  if i==shop_sel then
   print("each",100,row_y+1,5)
  end
 end

 -- footer
 line(10,98,117,98,5)
 print("\142 sell 1   \139 sell all   \151 leave",13,102,6)
 -- credits + total
 local total=0
 for t in all(junk_types) do total+=(inv[t.name] or 0)*t.val end
 print("hold value: "..total.."cr",13,90,12)

 -- topbar
 draw_topbar()

 for p in all(popups) do
  print(p.txt,p.x-#p.txt*2,p.y,11)
 end
end

function draw_topbar()
 rectfill(0,0,127,7,1)
 line(0,7,127,7,0)
 print("void angler",2,1,7)
 -- credits
 print("cr "..credits,86,1,10)
 if mode=="fish" then
  -- arm gauge
  local gx=44 local gy=2
  rect(gx,gy,gx+30,gy+3,5)
  local fill=flr((arm_len/arm_max)*29)
  if fill>0 then rectfill(gx+1,gy+1,gx+fill,gy+2,11) end
 else
  print("shop",54,1,12)
 end
end

function draw_blackhole()
 for i=0,40 do
  local a=i/40+time()*0.05
  local r=bh_r+sin(a*4+time())*1.6
  local x=bh_x+cos(a)*r
  local y=bh_y+sin(a)*r*0.7
  pset(x,y,({2,8,9,10})[flr((a*3)%4)+1])
 end
 circ(bh_x,bh_y,bh_r,2)
 circ(bh_x,bh_y,bh_r-2,1)
 for i=0,30 do
  local a=i/30+time()*0.2
  local r=(bh_r-6)*(0.5+0.5*sin(a*2+time()))
  pset(bh_x+cos(a)*r,bh_y+sin(a)*r*0.7,1)
 end
 circfill(bh_x,bh_y,bh_r-10,0)
end

function draw_ship()
 local sx=ship_x local sy=ship_y
 rectfill(sx-7,sy-3,sx+7,sy+3,6)
 rectfill(sx-9,sy-1,sx+9,sy+1,6)
 line(sx-9,sy-1,sx+9,sy-1,7)
 rectfill(sx-2,sy-2,sx+2,sy,12)
 pset(sx-1,sy-2,7)
 pset(sx-8,sy+2,8)
 pset(sx+8,sy+2,8)
 rectfill(sx-1,sy+3,sx+1,sy+5,5)
end

function draw_arm()
 if arm_state=="idle" and arm_len<=0 then return end
 local ang=0.25+aim
 local steps=flr(arm_len/2)
 if steps<1 then steps=1 end
 for i=1,steps do
  local t=i/steps
  local cx=ship_x+cos(ang)*arm_len*t
  local cy=ship_y+8+sin(ang)*arm_len*t
  pset(cx,cy,5)
  pset(cx+1,cy,6)
 end
 local hx=hook.x local hy=hook.y
 local pa=ang+0.25
 line(hx,hy,hx+cos(pa)*3,hy+sin(pa)*3,6)
 line(hx,hy,hx-cos(pa)*3,hy-sin(pa)*3,6)
 line(hx,hy,hx+cos(pa)*3,hy+sin(pa)*3-1,7)
 circfill(hx,hy,1,7)
end

function draw_junk(j)
 draw_junk_icon(j.type,j.x,j.y)
 if hooked==j then
  pset(j.x,j.y-2,10)
 end
end

function draw_junk_icon(t,x,y)
 local sx=flr(x) local sy=flr(y)
 if t.name=="bolt" then
  pset(sx,sy,t.col)
  pset(sx+1,sy,t.col)
  pset(sx,sy+1,5)
 elseif t.name=="can" then
  rectfill(sx-1,sy-1,sx+1,sy+1,t.col)
  pset(sx,sy-1,7)
 elseif t.name=="chip" then
  rectfill(sx-1,sy,sx+1,sy+1,t.col)
  pset(sx-1,sy,7)
  pset(sx+1,sy+1,3)
 elseif t.name=="gem" then
  pset(sx,sy-1,7)
  pset(sx-1,sy,t.col)
  pset(sx+1,sy,t.col)
  pset(sx,sy+1,t.col)
 end
end

__gfx__
00000000666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000677777760000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000676776760000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000005555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000056666500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000056666500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000005555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000200001805018050180501805000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300002405024050240502405024050240502005020050200502005020050200500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100000c0500c0500c0501805024050300503c0500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000200000805008050080500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300001c0501c0501c0501c0500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100001005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
