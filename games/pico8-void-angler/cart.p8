pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- void angler
-- by tic-labs
-- stage 1: core fishing

-- world
-- screen 128x128
-- ship hovers at top, black hole centered around (64, 96)
-- arm extends from ship down into the hole
-- junk drifts inside the hole, hook catches it

bh_x=64
bh_y=96
bh_r=28

ship_x=64
ship_y=18

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
 reset_run()
end

function reset_run()
 -- arm state: idle, dropping, reeling
 arm_state="idle"
 arm_len=0
 arm_max=58
 arm_drop_speed=1.4
 arm_reel_speed=1.1
 aim=0 -- -1 left, 0 down, 1 right (radians offset)
 aim_t=0
 hook={x=ship_x,y=ship_y+8,vx=0,vy=0}
 hooked=nil
 catch_flash=0

 junk={}
 for i=1,7 do spawn_junk() end

 score_msg=""
 score_msg_t=0
 popups={}
end

function spawn_junk()
 -- random angle/radius inside black hole disc
 local a=rnd(1)
 local r=rnd(bh_r-3)+2
 local jx=bh_x+cos(a)*r
 local jy=bh_y+sin(a)*r
 local types={
  {name="bolt",  s=16, val=2,  col=6},
  {name="can",   s=17, val=3,  col=13},
  {name="chip",  s=18, val=5,  col=11},
  {name="gem",   s=19, val=9,  col=12},
 }
 -- weighted: common stuff more often
 local roll=rnd(10)
 local t
 if roll<5 then t=types[1]
 elseif roll<8 then t=types[2]
 elseif roll<9.5 then t=types[3]
 else t=types[4] end
 add(junk,{
  x=jx,y=jy,
  ox=jx,oy=jy,
  spin=rnd(1),
  spinv=(rnd(0.02)+0.005)*(rnd(1)<0.5 and -1 or 1),
  orbit=rnd(1),
  orbitv=(rnd(0.004)+0.001)*(rnd(1)<0.5 and -1 or 1),
  jitter=rnd(1.2)+0.4,
  type=t,
 })
end

function dist(ax,ay,bx,by)
 local dx=ax-bx local dy=ay-by
 return sqrt(dx*dx+dy*dy)
end

function _update60()
 -- aim only when idle
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
 end

 -- update junk drift
 for j in all(junk) do
  j.orbit+=j.orbitv
  j.spin+=j.spinv
  local r=dist(j.ox,j.oy,bh_x,bh_y)
  j.x=bh_x+cos(j.orbit)*r+sin(j.spin*2)*j.jitter
  j.y=bh_y+sin(j.orbit)*r+cos(j.spin*2)*j.jitter
 end

 -- arm dynamics
 if arm_state=="dropping" then
  arm_len+=arm_drop_speed
  if arm_len>=arm_max then
   arm_len=arm_max
   arm_state="reeling"
  end
  -- check catch while dropping
  check_catch()
  -- early reel if player taps X
  if btnp(5) then arm_state="reeling" end
 elseif arm_state=="reeling" then
  arm_len-=arm_reel_speed
  -- hooked junk follows hook
  if hooked then
   hooked.x=hook.x
   hooked.y=hook.y
  end
  if arm_len<=0 then
   arm_len=0
   if hooked then
    catch_flash=18
    score_msg="+"..hooked.type.val.." "..hooked.type.name
    score_msg_t=60
    add(popups,{x=ship_x,y=ship_y,t=30,txt=score_msg})
    sfx(2)
    del(junk,hooked)
    spawn_junk()
    hooked=nil
   else
    sfx(3)
   end
   arm_state="idle"
  end
  -- still allow snagging on the way up
  if not hooked then check_catch() end
 end

 -- hook position from arm length and aim
 local ang=0.25+aim -- pointing down with sideways tilt
 hook.x=ship_x+cos(ang)*arm_len
 hook.y=ship_y+8+sin(ang)*arm_len

 -- gentle ship bob
 ship_y=18+sin(time()/3)*0.6

 if score_msg_t>0 then score_msg_t-=1 end
 if catch_flash>0 then catch_flash-=1 end
 for p in all(popups) do
  p.y-=0.5
  p.t-=1
  if p.t<=0 then del(popups,p) end
 end

 -- twinkle
 for s in all(stars) do
  s.tw+=0.01
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
 cls(0)

 -- starfield
 for s in all(stars) do
  local f=(sin(s.tw)+1)*0.5
  if f>0.3 then pset(s.x,s.y,s.c) end
 end

 -- black hole accretion ring
 draw_blackhole()

 -- arm + ship
 draw_arm()
 draw_ship()

 -- junk
 for j in all(junk) do draw_junk(j) end

 -- ui
 draw_ui()

 -- popups
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
end

function draw_blackhole()
 -- outer accretion swirl
 for i=0,40 do
  local a=i/40+time()*0.05
  local r=bh_r+sin(a*4+time())*1.6
  local x=bh_x+cos(a)*r
  local y=bh_y+sin(a)*r*0.7
  pset(x,y,({2,8,9,10})[flr((a*3)%4)+1])
 end
 -- glow rings
 circ(bh_x,bh_y,bh_r,2)
 circ(bh_x,bh_y,bh_r-2,1)
 -- swirling inside (lensed disc)
 for i=0,30 do
  local a=i/30+time()*0.2
  local r=(bh_r-6)*(0.5+0.5*sin(a*2+time()))
  pset(bh_x+cos(a)*r,bh_y+sin(a)*r*0.7,1)
 end
 -- event horizon
 circfill(bh_x,bh_y,bh_r-10,0)
end

function draw_ship()
 local sx=ship_x local sy=ship_y
 -- hull
 rectfill(sx-7,sy-3,sx+7,sy+3,6)
 rectfill(sx-9,sy-1,sx+9,sy+1,6)
 line(sx-9,sy-1,sx+9,sy-1,7)
 -- cockpit
 rectfill(sx-2,sy-2,sx+2,sy,12)
 pset(sx-1,sy-2,7)
 -- thrusters
 pset(sx-8,sy+2,8)
 pset(sx+8,sy+2,8)
 -- arm mount
 rectfill(sx-1,sy+3,sx+1,sy+5,5)
end

function draw_arm()
 if arm_state=="idle" and arm_len<=0 then return end
 local ang=0.25+aim
 local steps=flr(arm_len/2)
 if steps<1 then steps=1 end
 local px=ship_x local py=ship_y+5
 for i=1,steps do
  local t=i/steps
  local cx=ship_x+cos(ang)*arm_len*t
  local cy=ship_y+8+sin(ang)*arm_len*t
  pset(cx,cy,5)
  pset(cx+1,cy,6)
 end
 -- claw
 local hx=hook.x local hy=hook.y
 -- two prongs
 local pa=ang+0.25
 line(hx,hy,hx+cos(pa)*3,hy+sin(pa)*3,6)
 line(hx,hy,hx-cos(pa)*3,hy-sin(pa)*3,6)
 line(hx,hy,hx+cos(pa)*3,hy+sin(pa)*3-1,7)
 circfill(hx,hy,1,7)
end

function draw_junk(j)
 local sx=flr(j.x) local sy=flr(j.y)
 local t=j.type
 local wob=sin(j.spin)*1
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
 if hooked==j then
  pset(sx,sy-2,10)
 end
end

function draw_ui()
 rectfill(0,0,127,7,1)
 line(0,7,127,7,0)
 print("void angler",2,1,7)
 -- arm gauge
 local gx=72 local gy=2
 rect(gx,gy,gx+50,gy+3,5)
 local fill=flr((arm_len/arm_max)*49)
 if fill>0 then rectfill(gx+1,gy+1,gx+fill,gy+2,11) end
 print("arm",58,1,6)
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
__music__
